from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import tempfile
from pathlib import Path
from typing import Any, Iterable, Mapping

HERE = Path(__file__).resolve()
NODE = HERE.parents[1]
ROOT = HERE.parents[4]
PROTOCOL = NODE / "protocol_lock.json"
NODE43 = ROOT / "results/modern_tcn_metric_rebuild/43_fusion_offline_recalibration_and_6path_retest"
NODE44 = ROOT / "results/modern_tcn_metric_rebuild/44R1_quality_adaptive_uncertainty_repair"
NODE51 = ROOT / "results/modern_tcn_metric_rebuild/51_moderntcn_rkf_highrisk_suppression_rebuild"
NODE16 = ROOT / "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/16_six_axis_imu_candidate_screening"
NODE17 = ROOT / "results/modern_tcn_metric_rebuild/45_imu_only_five_method_comparison/17_r2_06_fuzzyakf_exploratory_validation"
PAPER = ROOT / "results/paper/Latex/paper_v4_final_candidate.tex"
RAW = ROOT / "data/tcn/ModernTCN_train_data_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat"
SPLIT = NODE43 / "01_inventory/split_audit.json"
R2_CONFIG = NODE16 / "02_configs/refinement/R2_06_FuzzyAKF6D.json"
R2_MATLAB = NODE16 / "tools/node16_fuzzyakf6_estimator.m"
R2_PYTHON = NODE16 / "tools/node16_estimators.py"


def ensure_node(path: Path) -> Path:
    resolved = Path(path).resolve()
    try:
        resolved.relative_to(NODE.resolve())
    except ValueError as exc:
        raise RuntimeError(f"Node53 write outside guard: {resolved}") from exc
    return resolved


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def clean(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {str(k): clean(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if hasattr(value, "item"):
        try:
            return clean(value.item())
        except (TypeError, ValueError):
            pass
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, Path):
        return str(value)
    return value


def write_json(path: Path, value: Any) -> None:
    path = ensure_node(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(clean(value), indent=2, ensure_ascii=True, allow_nan=False) + "\n"
    fd, temp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def write_csv(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    path = ensure_node(path)
    materialized = [clean(dict(row)) for row in rows]
    fields: list[str] = []
    for row in materialized:
        for key in row:
            if key not in fields:
                fields.append(key)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(materialized)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def rel(path: Path) -> str:
    try:
        return Path(path).resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(Path(path).resolve())


def load_protocol() -> dict[str, Any]:
    value = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    if value.get("classification") != "EXPLORATORY_NONQUALIFIED_R2_06_FUSION_REBUILD":
        raise RuntimeError("Node53 protocol classification mismatch")
    return value


def protected_sources() -> list[tuple[str, Path]]:
    fixed = [
        ("paper", PAPER),
        ("44R1 directory", NODE44),
        ("Node51 directory", NODE51),
        ("R2_06 config", R2_CONFIG),
        ("Node16 FuzzyAKF MATLAB", R2_MATLAB),
        ("Node16 FuzzyAKF Python", R2_PYTHON),
        ("Node17 directory", NODE17),
        ("raw dataset", RAW),
        ("split audit", SPLIT),
        ("ModernTCN-only registry", NODE43 / "01_inventory/reused_mtcn_baseline_60.csv"),
    ]
    registry = NODE43 / "01_inventory/reused_mtcn_baseline_60.csv"
    if registry.is_file():
        # The registry is the authority for the exact frozen path/model inputs.
        # Hash unique artifacts explicitly so the manifest proves their identity,
        # rather than relying only on a hash of the registry CSV.
        try:
            with registry.open("r", encoding="utf-8-sig", newline="") as handle:
                rows = list(csv.DictReader(handle))
            seen: set[tuple[str, str]] = set()
            for row in rows:
                for field, role in (("path_file", "six path input"), ("onnx_file", "ModernTCN ONNX"), ("checkpoint_file", "ModernTCN checkpoint")):
                    value = row.get(field, "")
                    if not value:
                        continue
                    path = Path(value)
                    key = (role, str(path.resolve()))
                    if path.is_file() and key not in seen:
                        fixed.append((role, path))
                        seen.add(key)
        except (OSError, UnicodeError, csv.Error):
            # The registry itself remains protected; a missing expansion is
            # surfaced by downstream manifest validation rather than silently
            # changing the experiment inputs.
            pass
    return fixed


def snapshot(phase: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for role, path in protected_sources():
        targets = sorted(path.rglob("*") if path.is_dir() else [path])
        for item in targets:
            if not item.is_file():
                continue
            rows.append({"phase": phase, "role": role, "path": rel(item), "absolute_path": str(item.resolve()), "size": item.stat().st_size, "sha256": sha256(item)})
    write_json(NODE / f"protection_hash_{phase}.json", rows)
    return rows


def merge_manifest(begin: list[dict[str, Any]], end: list[dict[str, Any]] | None = None) -> None:
    end_map = {(x["role"], x["path"]): x for x in (end or [])}
    rows = []
    for row in begin:
        current = end_map.get((row["role"], row["path"]))
        rows.append({"role": row["role"], "path": row["path"], "absolute_path": row["absolute_path"], "size_begin": row["size"], "sha256_begin": row["sha256"], "size_end": current["size"] if current else "", "sha256_end": current["sha256"] if current else "", "unchanged": bool(current and current["sha256"] == row["sha256"])})
    write_csv(NODE / "source_manifest.csv", rows)
