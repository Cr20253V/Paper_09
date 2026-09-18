from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np

from node53_common import NODE, R2_CONFIG, R2_MATLAB, R2_PYTHON, sha256, write_json
from node53_fuzzyakf6_estimator import replay


def fixture() -> np.ndarray:
    rng = np.random.default_rng(5306)
    n = 1200
    packet = np.zeros((n, 6), dtype=float)
    t = np.arange(n) * 0.01
    packet[:, 0] = 9.81 * np.sin(0.08 * np.sin(0.7 * t)) + 0.04 * rng.normal(size=n)
    packet[:, 1] = 0.25 * np.sin(4.0 * t) + 0.12 * rng.normal(size=n)
    packet[:, 2] = 9.81 * np.cos(0.08 * np.sin(0.7 * t)) + 0.08 * rng.normal(size=n)
    packet[:, 3] = 0.04 * np.sin(2.0 * t) + 0.01 * rng.normal(size=n)
    packet[:, 4] = 0.08 * np.cos(0.5 * t) + 0.02 * rng.normal(size=n)
    packet[:, 5] = 0.03 * np.sin(6.0 * t) + 0.01 * rng.normal(size=n)
    packet[250:350, :3] += np.array([0.7, 0.2, -0.4])
    packet[700:760, 3:] += np.array([0.15, 0.42, 0.2])
    packet[980:1030, 0] += 1.2
    return packet


def load_cfg() -> dict:
    return json.loads((NODE / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json").read_text(encoding="utf-8"))


def write_matrix(path: Path, array: np.ndarray, names: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(names)
        writer.writerows(array.tolist())


def generate() -> int:
    packet = fixture()
    result = replay(packet, load_cfg())
    input_path = NODE / "cache/parity_input.csv"
    python_path = NODE / "cache/parity_python.csv"
    write_matrix(input_path, packet, ["fx", "fy", "fz", "gx", "gy", "gz"])
    names = ["theta_imu", "theta_acc", "theta_pred", "accel_weight", "accel_norm", "innovation", "nis", "min_covariance_eigenvalue", "observer_valid", "gyro_energy", "gyro_vibration_feature"]
    write_matrix(python_path, np.column_stack([result[name].astype(float) for name in names]), names)
    write_json(NODE / "cache/parity_fixture_meta.json", {"status": "PASS_NODE53_PARITY_FIXTURE", "sample_count": int(len(packet)), "seed": 5306, "config_sha256": sha256(NODE / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json"), "python_impl_sha256": sha256(NODE / "tools/node53_fuzzyakf6_estimator.py"), "matlab_impl_source_sha256": sha256(R2_MATLAB), "upstream_python_source_sha256": sha256(R2_PYTHON), "upstream_config_sha256": sha256(R2_CONFIG)})
    print(json.dumps({"status": "PASS_NODE53_PARITY_FIXTURE", "sample_count": len(packet)}, indent=2))
    return 0


def compare() -> int:
    py = np.genfromtxt(NODE / "cache/parity_python.csv", delimiter=",", names=True)
    ml = np.genfromtxt(NODE / "cache/parity_matlab.csv", delimiter=",", names=True)
    names = ["theta_imu", "theta_acc", "theta_pred", "accel_weight", "accel_norm", "innovation", "nis", "min_covariance_eigenvalue", "observer_valid", "gyro_energy", "gyro_vibration_feature"]
    errors = {name: float(np.max(np.abs(np.asarray(py[name], float) - np.asarray(ml[name], float)))) for name in names}
    boolean_ok = bool(np.array_equal(np.asarray(py["observer_valid"], float) > 0.5, np.asarray(ml["observer_valid"], float) > 0.5))
    max_state = max(errors[k] for k in names if k != "min_covariance_eigenvalue")
    passed = len(py) == len(ml) and boolean_ok and max_state <= 1e-10 and errors["min_covariance_eigenvalue"] <= 1e-12
    result = {"status": "PASS_NODE53_MATLAB_PYTHON_PARITY" if passed else "FAIL_NODE53_MATLAB_PYTHON_PARITY", "sample_count": int(len(py)), "matlab_rows": int(len(ml)), "max_abs_error": errors, "boolean_exact": boolean_ok, "tolerances": {"state": 1e-10, "covariance_min_eigenvalue": 1e-12}, "config_sha256": sha256(NODE / "02_fuzzyakf6/R2_06_FuzzyAKF6D.json"), "matlab_impl_sha256": sha256(NODE / "tools/node53_fuzzyakf6_estimator.m"), "python_impl_sha256": sha256(NODE / "tools/node53_fuzzyakf6_estimator.py")}
    write_json(NODE / "parity_audit.json", result)
    print(json.dumps(result, indent=2))
    return 0 if passed else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--compare", action="store_true")
    args = parser.parse_args()
    if args.generate:
        return generate()
    if args.compare:
        return compare()
    parser.error("choose --generate or --compare")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
