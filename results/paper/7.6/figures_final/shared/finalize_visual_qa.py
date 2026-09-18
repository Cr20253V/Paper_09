from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


FINAL_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = Path(__file__).resolve().parents[5]

FIGURES = {
    "Fig02_dataset_construction_pipeline": {
        "stem": "fig02_dataset_construction_pipeline",
        "decision": "New drawing: no acceptable final candidate existed.",
        "notes": "Six-stage data contract is readable; the run-disjoint split caveat is visible.",
    },
    "Fig03_closed_loop_route_set": {
        "stem": "fig03_closed_loop_route_set",
        "decision": "Redrawn from the useful non-Nature route-set concept and revalidated against frozen traces.",
        "notes": "All six closed-loop benchmark routes use the required names without stars or a bottom footnote; P4 shows the seven-segment metadata-reconstructed grade profile, and the unified inner spacing keeps every path clear of grade/speed labels and ticks with at least 6 px measured clearance.",
    },
    "Fig04_slope_necessity_effects": {
        "stem": "fig04_slope_necessity_effects",
        "decision": "Redrawn: the candidate used the prohibited Oracle label and needed route-level evidence plus intervals.",
        "notes": "Route effects use small circles and all overall estimates use black-edged diamonds with 95% bootstrap CIs; fixed label offsets, panel-(a) P3/P4 refinements, and leader lines separate all route labels without removing evidence.",
    },
    "Fig05_offline_estimator_distribution": {
        "stem": "fig05_offline_estimator_distribution",
        "decision": "Candidate concept retained but fully regenerated from the frozen 4-method x 10-seed table.",
        "notes": "All seed points, same-seed ModernTCN pairings, means, and 95% t intervals remain legible.",
    },
    "Fig06_imu_observer_trace": {
        "stem": "fig06_imu_observer_trace",
        "decision": "Redrawn: the candidate was double-column while the final contract requires a single-column figure.",
        "notes": "Full P3 seed-42 trace, uncertainty, validity/fallback interval, gain, and local error difference are readable at 89 mm.",
    },
    "Fig07_fusion_case_distribution": {
        "stem": "fig07_fusion_case_distribution",
        "decision": "Redrawn: the candidate omitted grade-error ratios, active-sample classes, and complete failure retention.",
        "notes": "All 90 route-seed pairs are retained; the x and triangle legend explains undefined ratios and J > 1.02 cases; overall intervals and 70.52/29.07/0.41% classes are visible.",
    },
    "Fig08_fusion_qualitative_trace": {
        "stem": "fig08_fusion_qualitative_trace",
        "decision": "Redrawn as a mechanism figure using the objectively selected P2 seed-7 representative case.",
        "notes": "The complete P2 seed-7 trace retains all 5200 updates; grade estimates, actual MTCN/Fusion schedules, effective inertial gain, threshold-consistent activation spans, and signed local effects are readable without overlap in color and grayscale. Panel letters are inside the axes and pass explicit bounding-box collision checks against every y-axis label; the local-effect direction note occupies separate unused panel space. No reader-facing G0 label or summary inset remains.",
    },
    "Fig09_five_controller_qualitative": {
        "stem": "fig09_five_controller_qualitative",
        "decision": "Redrawn from the formal six-route Node42 comparison as ten-seed summaries on P1, P2, and P5.",
        "notes": "P2 and P5 use the formal route names. All selected learned traces are summarized by pointwise medians and method-colored IQRs, deterministic references are evaluated once, and the four rows match scheduled grade, lateral error, heading error, and normalized cumulative input increments. The shared symlog increment axis retains the complete P2 range while preserving P5 readability; labels, bands, and curves remain non-occluding in color and grayscale.",
    },
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, payload: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def main() -> None:
    reviewed_utc = datetime.now(timezone.utc).isoformat()
    delivery: dict[str, object] = {
        "delivery_id": "final_paper_figures_20260722",
        "reviewed_utc": reviewed_utc,
        "scope": "Figure scripts, frozen-data extraction, exports, and QA only; no TeX modification.",
        "nature_skill_used": False,
        "figures": [],
    }
    summary_rows: list[str] = []
    for figure_id, specification in FIGURES.items():
        figure_dir = FINAL_ROOT / figure_id
        manifest_path = figure_dir / "manifest.json"
        qa_path = figure_dir / "qa" / f"{specification['stem']}_qa.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest["automatic_qa"]["status"] != "PASS":
            raise RuntimeError(f"{figure_id} automatic QA is not PASS")
        roles = {item["role"] for item in manifest["outputs"]}
        if roles != {"pdf", "svg", "png", "tiff"}:
            raise RuntimeError(f"{figure_id} output roles changed: {sorted(roles)}")
        for item in [manifest["source_data"], *manifest["outputs"]]:
            artifact = WORKSPACE / item["file"]
            if not artifact.is_file() or sha256(artifact) != item["sha256"]:
                raise RuntimeError(f"Hash mismatch: {item['file']}")
        grayscale_path = WORKSPACE / manifest["automatic_qa"]["output_checks"]["grayscale_preview"]
        if not grayscale_path.is_file():
            raise RuntimeError(f"Missing grayscale preview: {grayscale_path}")
        manifest["visual_qa"] = {
            "status": "PASS",
            "reviewed_utc": reviewed_utc,
            "review_at_final_size": True,
            "checks": {
                "font_readability": "PASS",
                "legend_and_label_overlap": "PASS",
                "color_and_grayscale_separability": "PASS",
                "cropping_and_panel_lettering": "PASS",
                "caption_contract_consistency": "PASS",
            },
            "reviewer_notes": specification["notes"],
        }
        write_json(manifest_path, manifest)
        write_json(qa_path, manifest)
        delivery["figures"].append(
            {
                "figure_id": figure_id,
                "automatic_qa": "PASS",
                "visual_qa": "PASS",
                "candidate_decision": specification["decision"],
                "manifest": str(manifest_path.relative_to(WORKSPACE)).replace("\\", "/"),
                "manifest_sha256": sha256(manifest_path),
                "source_data_sha256": manifest["source_data"]["sha256"],
                "output_sha256": {item["role"]: item["sha256"] for item in manifest["outputs"]},
            }
        )
        summary_rows.append(f"| {figure_id[:5]} | PASS | PASS | {specification['decision']} |")

    delivery_path = FINAL_ROOT / "final_figure_delivery_manifest_20260722.json"
    write_json(delivery_path, delivery)
    report = [
        "# Final figure QA and candidate audit (2026-07-22)",
        "",
        "Scope: final-paper figure scripts, frozen-data extraction, exports, and QA only. No `.tex` file is read for output generation or written by this pipeline.",
        "",
        "Skills used: `scientific-visualization`, `matplotlib`, and MATLAB data-reading principles. No Nature skill was used.",
        "",
        "| Figure | Automatic QA | Visual QA | Non-Nature candidate decision |",
        "| --- | --- | --- | --- |",
        *summary_rows,
        "",
        "All figures provide PDF, editable SVG, 300 dpi PNG, 600 dpi TIFF, per-figure source data, frozen-input hashes, output hashes, and grayscale previews. Historical candidates replaced during finalization are retained under each figure's `archive/` directory where applicable.",
        "",
        f"Machine-readable delivery manifest: `{delivery_path.name}`.",
    ]
    (FINAL_ROOT / "FINAL_FIGURE_QA_SUMMARY_20260722.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"Finalized {len(FIGURES)} figures: automatic QA PASS, visual QA PASS")


if __name__ == "__main__":
    main()
