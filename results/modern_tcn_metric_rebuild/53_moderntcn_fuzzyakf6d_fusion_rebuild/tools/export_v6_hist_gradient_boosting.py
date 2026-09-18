"""Export the frozen V6 sklearn gate to a small MATLAB-readable JSON model."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

NODE = Path(__file__).resolve().parents[1]
PKG = NODE / "cache" / "python_packages"
if str(PKG) not in sys.path:
    sys.path.insert(0, str(PKG))
import joblib  # noqa: E402


V6 = NODE / "04_fusion_calibration" / "iterations" / "07_supervised_runtime_gate_v6"
MODEL = V6 / "models" / "final_train_validation_hist_gradient_boosting.joblib"
OUT = NODE / "08_formal_six_path_exploratory_v6" / "config" / "v6_hist_gradient_boosting_export.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    model = joblib.load(MODEL)
    trees = []
    for stage in model._predictors:
        tree = stage[0]
        nodes = tree.nodes
        trees.append({
            "value": [float(x) for x in nodes["value"]],
            "feature_idx": [int(x) for x in nodes["feature_idx"]],
            "bin_threshold": [int(x) for x in nodes["bin_threshold"]],
            "left": [int(x) for x in nodes["left"]],
            "right": [int(x) for x in nodes["right"]],
            "is_leaf": [int(x) for x in nodes["is_leaf"]],
            "missing_go_to_left": [int(x) for x in nodes["missing_go_to_left"]],
        })
    payload = {
        "status": "PASS_NODE53_V6_RUNTIME_MODEL_EXPORT",
        "model_family": "HistGradientBoostingClassifier",
        "source_model": str(MODEL),
        "source_model_sha256": sha256(MODEL),
        "feature_count": int(model.n_features_in_),
        "learning_rate": float(model.learning_rate),
        "baseline_prediction": float(model._baseline_prediction[0, 0]),
        "tree_count": len(trees),
        "bin_thresholds": [[float(x) for x in row] for row in model._bin_mapper.bin_thresholds_],
        "trees": trees,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps({"status": payload["status"], "output": str(OUT), "sha256": sha256(OUT), "tree_count": len(trees)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
