from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageOps

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import generate_fig04_alternatives as base


VARIANT_ID = "ra_x2_qg_x05"
OUTPUT_STEM = f"fig04_slope_necessity_effects_{VARIANT_ID}"
BOOTSTRAP_ITERATIONS = 10000
BOOTSTRAP_SEED = 20260715
METRIC_NAMES = ("ey_rmse", "epsi_rmse", "j_du")


def locate_inputs(root: Path) -> tuple[Path, Path]:
    control_source = (
        base.FIGURE_DIR
        / "source_data"
        / "fig04_slope_necessity_effects_source_data.csv"
    )
    rkf_source = (
        root
        / "results"
        / "modern_tcn_metric_rebuild"
        / "45_imu_only_five_method_comparison"
        / "15_rkf_ra_covariance_sensitivity"
        / VARIANT_ID
        / "04_rkf_closed_loop"
        / f"rkf_{VARIANT_ID}_six_path_metrics.csv"
    )
    for path in (control_source, rkf_source):
        if not path.is_file():
            raise FileNotFoundError(path)
    return control_source, rkf_source


def validate_rkf_rows(rkf: pd.DataFrame, expected_paths: set[str]) -> None:
    required = {"path_id", "case_status", *METRIC_NAMES}
    missing = required.difference(rkf.columns)
    if missing:
        raise ValueError(f"RKF source is missing columns: {sorted(missing)}")
    if len(rkf) != len(expected_paths) or set(rkf["path_id"]) != expected_paths:
        raise ValueError("RKF source must contain exactly the six Fig. 4 routes")
    if not rkf["path_id"].is_unique:
        raise ValueError("RKF source contains duplicate routes")
    if not rkf["case_status"].eq("COMPLETE").all():
        raise ValueError("All RKF routes must have case_status=COMPLETE")
    values = rkf.loc[:, METRIC_NAMES].apply(pd.to_numeric, errors="coerce")
    if not np.isfinite(values.to_numpy()).all() or (values.to_numpy() <= 0).any():
        raise ValueError("All plotted RKF metrics must be finite and positive")


def bootstrap_summary(
    effects: pd.DataFrame, columns: pd.Index
) -> pd.DataFrame:
    rng = np.random.default_rng(BOOTSTRAP_SEED)
    rows: list[dict[str, object]] = []
    for metric in METRIC_NAMES:
        values = effects.loc[effects["metric"] == metric, "effect_comparator_minus_target"].to_numpy(
            dtype=float
        )
        if values.size != 6:
            raise ValueError(f"Expected six route effects for {metric}")
        bootstrap_means = rng.choice(
            values,
            size=(BOOTSTRAP_ITERATIONS, values.size),
            replace=True,
        ).mean(axis=1)
        row = {column: np.nan for column in columns}
        row.update(
            {
                "record_type": "bootstrap_summary",
                "contrast_id": "A3_IMU_VS_ZS",
                "priority": "secondary",
                "target": "RKF_RA_X2_QG_X05_LPV_MPC",
                "comparator": "ZS_LPV_MPC",
                "metric": metric,
                "estimate": float(values.mean()),
                "bootstrap_mean": float(bootstrap_means.mean()),
                "ci95_low": float(np.percentile(bootstrap_means, 2.5)),
                "ci95_high": float(np.percentile(bootstrap_means, 97.5)),
                "iterations": BOOTSTRAP_ITERATIONS,
                "random_seed": BOOTSTRAP_SEED,
                "n_paths": int(values.size),
            }
        )
        rows.append(row)
    return pd.DataFrame(rows, columns=columns)


def build_combined_source(
    control_source: Path, rkf_source: Path
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    control = pd.read_csv(control_source)
    rkf = pd.read_csv(rkf_source)
    oracle_effects = control[
        (control["record_type"] == "route_effect")
        & (control["contrast_id"] == "A3_ORACLE_VS_ZS")
        & control["metric"].isin(METRIC_NAMES)
    ].copy()
    if len(oracle_effects) != 18:
        raise ValueError("Control source must contain 18 truth-driven route effects")
    expected_paths = set(oracle_effects["path_id"])
    validate_rkf_rows(rkf, expected_paths)
    rkf_indexed = rkf.set_index("path_id")

    rkf_rows: list[dict[str, object]] = []
    for _, control_row in oracle_effects.iterrows():
        metric = str(control_row["metric"])
        path_id = str(control_row["path_id"])
        target_value = float(rkf_indexed.at[path_id, metric])
        comparator_value = float(control_row["comparator_value"])
        effect = comparator_value - target_value
        row = {column: np.nan for column in control.columns}
        row.update(
            {
                "record_type": "route_effect",
                "contrast_id": "A3_IMU_VS_ZS",
                "priority": "secondary",
                "target": "RKF_RA_X2_QG_X05_LPV_MPC",
                "comparator": "ZS_LPV_MPC",
                "path_id": path_id,
                "metric": metric,
                "target_value": target_value,
                "comparator_value": comparator_value,
                "effect_comparator_minus_target": effect,
                "relative_effect_pct": 100.0 * effect / comparator_value,
                "target_to_comparator_ratio": target_value / comparator_value,
                "positive_favors_target": True,
                "route_id": control_row["route_id"],
            }
        )
        rkf_rows.append(row)
    rkf_effects = pd.DataFrame(rkf_rows, columns=control.columns)

    oracle_summaries = control[
        (control["record_type"] == "bootstrap_summary")
        & (control["contrast_id"] == "A3_ORACLE_VS_ZS")
        & control["metric"].isin(METRIC_NAMES)
    ].copy()
    rkf_summaries = bootstrap_summary(rkf_effects, control.columns)
    combined = pd.concat(
        [oracle_effects, rkf_effects, oracle_summaries, rkf_summaries],
        ignore_index=True,
    )
    return combined, pd.concat([oracle_effects, rkf_effects]), rkf_summaries


def main() -> None:
    root = base.find_project_root()
    control_source, rkf_source = locate_inputs(root)
    combined, effects, rkf_summaries = build_combined_source(control_source, rkf_source)

    output_dir = base.FIGURE_DIR / "output"
    source_dir = base.FIGURE_DIR / "source_data"
    qa_dir = base.FIGURE_DIR / "qa"
    for directory in (output_dir, source_dir, qa_dir):
        directory.mkdir(parents=True, exist_ok=True)

    copied_rkf = source_dir / f"fig04_{VARIANT_ID}_rkf_input.csv"
    shutil.copyfile(rkf_source, copied_rkf)
    combined_source = source_dir / f"{OUTPUT_STEM}_source_data.csv"
    combined.to_csv(combined_source, index=False)

    figure = base.build_dumbbell(effects, imu_label="Qualified observer")
    artist_checks = base.inspect_artists(figure)
    outputs = base.export_figure(figure, output_dir / OUTPUT_STEM)
    png_path = next(path for path in outputs if path.suffix == ".png")
    tiff_path = next(path for path in outputs if path.suffix == ".tiff")
    grayscale_path = qa_dir / f"{OUTPUT_STEM}_grayscale.png"
    with Image.open(png_path) as image:
        ImageOps.grayscale(image).save(grayscale_path)

    output_records = [
        {
            "format": path.suffix[1:],
            "file": base.relpath(path, root),
            "bytes": path.stat().st_size,
            "sha256": base.sha256_file(path),
        }
        for path in outputs
    ]
    summary_records = rkf_summaries[
        ["metric", "estimate", "ci95_low", "ci95_high", "n_paths"]
    ].to_dict(orient="records")
    manifest = {
        "figure_id": OUTPUT_STEM,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "backend": "Python/matplotlib",
        "figure_contract": {
            "archetype": "quantitative grid",
            "core_conclusion": "Accurate grade scheduling improves the route-resolved LPV-MPC closed loop relative to zero-grade scheduling, while the qualified-observer response remains route dependent.",
            "panel_map": {
                "a": "lateral-error RMS",
                "b": "heading-error RMS",
                "c": "composite input-increment index",
            },
            "final_size_mm": [183, 91],
        },
        "data_policy": {
            "unchanged_controls": "zero-grade and truth-driven values retained from the frozen Fig. 4 control source",
            "replaced_series": "Qualified observer points use the RKF R_a x2, Q_g x0.5 six-route results",
            "control_source": {
                "file": base.relpath(control_source, root),
                "sha256": base.sha256_file(control_source),
            },
            "rkf_source": {
                "file": base.relpath(rkf_source, root),
                "sha256": base.sha256_file(rkf_source),
                "copied_file": base.relpath(copied_rkf, root),
                "routes_complete": 6,
            },
            "combined_source": {
                "file": base.relpath(combined_source, root),
                "sha256": base.sha256_file(combined_source),
                "route_effect_rows": int(len(effects)),
                "bootstrap_summary_rows": 6,
            },
        },
        "rkf_vs_zero_route_bootstrap": {
            "iterations": BOOTSTRAP_ITERATIONS,
            "seed": BOOTSTRAP_SEED,
            "effect_definition": "zero-grade minus RKF; positive favors RKF",
            "summaries": summary_records,
        },
        "outputs": output_records,
        "automatic_qa": {
            "status": "PASS",
            "artist_checks": artist_checks,
            "png": base.inspect_raster(png_path, (183.0, 91.0), 300),
            "tiff": base.inspect_raster(tiff_path, (183.0, 91.0), 600),
            "grayscale_preview": base.relpath(grayscale_path, root),
        },
    }
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False)
    (base.FIGURE_DIR / f"manifest_{VARIANT_ID}.json").write_text(
        encoded, encoding="utf-8"
    )
    (qa_dir / f"fig04_{VARIANT_ID}_qa.json").write_text(encoded, encoding="utf-8")
    print(
        json.dumps(
            {
                "figure_id": OUTPUT_STEM,
                "outputs": len(outputs),
                "route_effect_rows": int(len(effects)),
                "automatic_qa": "PASS",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
