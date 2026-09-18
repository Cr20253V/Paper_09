from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

from a2ort_paths import A1_ROOT, A2_ROOT, ORT_ROOT, ROOT


SNAPSHOT = ORT_ROOT / "00_protocol_lock/protected_artifact_snapshot.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def protected_files() -> list[Path]:
    explicit = [
        ROOT / "results/paper/7.6/A0_论文最终统一实验配置_20260715.json",
        ROOT / "results/paper/7.6/A0_论文最终统一实验配置说明_20260715.md",
        ROOT / "results/paper/7.6/后续三章实验审计与写作大纲_20260715.md",
        A1_ROOT / "receipt.json",
        A1_ROOT / "model_registry.csv",
        ROOT / "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/03_A3_slope_scheduling_necessity/receipt.json",
        ROOT / "results/paper/Latex/paper_v3.tex",
    ]
    node38 = ROOT / "results/modern_tcn_metric_rebuild/38_moderntcn_imu_control_aware_selective_fusion"
    files = [p for p in explicit if p.is_file()]
    def walk_files(root: Path):
        for directory, _, names in os.walk(root, onerror=lambda _: None, followlinks=False):
            for name in names:
                path = Path(directory) / name
                if path.is_file():
                    yield path
    if node38.is_dir():
        files.extend(walk_files(node38))
    if A2_ROOT.is_dir():
        files.extend(p for p in walk_files(A2_ROOT) if ORT_ROOT not in p.parents)
    return sorted(set(p.resolve() for p in files))


def current_records() -> list[dict[str, object]]:
    return [
        {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
        for path in protected_files()
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.create == args.verify:
        raise RuntimeError("Choose exactly one of --create or --verify")
    if args.create:
        if SNAPSHOT.exists():
            raise FileExistsError(f"Refusing to overwrite protected snapshot: {SNAPSHOT}")
        records = current_records()
        SNAPSHOT.write_text(json.dumps({"file_count": len(records), "files": records}, indent=2), encoding="utf-8")
        print(f"Protected snapshot created: {len(records)} files")
        return
    expected = json.loads(SNAPSHOT.read_text(encoding="utf-8"))["files"]
    current = current_records()
    if expected != current:
        expected_map = {r["path"]: r for r in expected}
        current_map = {r["path"]: r for r in current}
        changed = sorted(k for k in expected_map.keys() & current_map.keys() if expected_map[k] != current_map[k])
        missing = sorted(expected_map.keys() - current_map.keys())
        added = sorted(current_map.keys() - expected_map.keys())
        raise RuntimeError(f"Protected artifacts changed: changed={changed[:10]} missing={missing[:10]} added={added[:10]}")
    print(f"Protected snapshot verified: {len(current)} files")


if __name__ == "__main__":
    main()
