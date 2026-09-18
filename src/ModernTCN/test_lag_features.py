from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "ModernTCN"))

from modern_tcn_lag_features import (  # noqa: E402
    augment_array_by_metadata,
    augmented_feature_names,
    build_input_augmentation_metadata,
    fit_input_augmentation_metadata,
)


def _base_x():
    return np.arange(2 * 6 * 22, dtype=np.float32).reshape(2, 6, 22)


def _meta(mode, steps):
    return build_input_augmentation_metadata(
        mode,
        raw_input_dim=22,
        seq_len=6,
        feature_contract="passive17_plus_all5",
        feat_names=[f"f{i}" for i in range(22)],
        lag_steps=steps,
        lag_pad="edge",
        delta_clip_abs=5.0,
    )


def test_lag_stack_124_shape_and_edge_values():
    X = _base_x()
    meta = _meta("lag_stack", [1, 2, 4])
    out = augment_array_by_metadata(X, meta)
    assert out.shape == (2, 6, 88)
    np.testing.assert_array_equal(out[:, :, :22], X)
    np.testing.assert_array_equal(out[:, 0, 22:44], X[:, 0, :])
    np.testing.assert_array_equal(out[:, 2, 22:44], X[:, 1, :])
    np.testing.assert_array_equal(out[:, 2, 44:66], X[:, 0, :])
    np.testing.assert_array_equal(out[:, 5, 66:88], X[:, 1, :])


def test_delta_bank_124_clips():
    X = _base_x() * 10.0
    meta = _meta("delta_bank", [1, 2, 4])
    out = augment_array_by_metadata(X, meta)
    assert out.shape == (2, 6, 88)
    assert np.max(out[:, :, 22:]) <= 5.0
    assert np.min(out[:, :, 22:]) >= -5.0
    np.testing.assert_array_equal(out[:, 0, 22:44], np.zeros((2, 22), dtype=np.float32))


def test_mixed_lag_delta_14_shape():
    X = _base_x()
    meta = _meta("mixed_lag_delta", [1, 4])
    out = augment_array_by_metadata(X, meta)
    assert out.shape == (2, 6, 110)
    raw_names = [f"f{i}" for i in range(22)]
    names = augmented_feature_names(raw_names, meta)
    assert len(names) == 110
    assert names[:3] == ["f0", "f1", "f2"]
    assert names[22:25] == ["lag1_f0", "lag1_f1", "lag1_f2"]
    assert names[66:69] == ["delta_lag1_f0", "delta_lag1_f1", "delta_lag1_f2"]


def test_rejects_long_lag():
    try:
        _meta("lag_stack", [6])
    except ValueError:
        pass
    else:
        raise AssertionError("lag >= seq_len should fail")


def test_physics_residual_8_shape_and_train_fit_stats():
    raw_names = [
        "gyro_z",
        "I_lf",
        "I_rr",
        "omega_wheel_lf",
        "omega_wheel_rr",
        "delta_lf",
        "delta_rr",
        "v_hat",
        "dv_hat_dt",
        "ws_imbalance",
        "I_sum",
        "I_diff_signed",
        "I_diff_abs",
        "kappa_proxy",
        "accel_per_current",
        "dv_hat_dt_lp",
        "accel_x_wheel",
        "I_drive_signed",
        "current_per_accel",
        "drive_load_proxy",
        "a_hp",
        "yaw_consistency_error",
    ]
    X = (_base_x() / 100.0).astype(np.float32)
    scaler = {
        "mean": np.linspace(-0.2, 0.2, 22, dtype=np.float32),
        "std": np.linspace(0.5, 1.5, 22, dtype=np.float32),
    }
    meta = build_input_augmentation_metadata(
        "physics_residual_8",
        raw_input_dim=22,
        seq_len=6,
        feature_contract="passive17_plus_all5",
        feat_names=raw_names,
    )
    meta = fit_input_augmentation_metadata(meta, X, scaler)
    out = augment_array_by_metadata(X, meta)
    assert out.shape == (2, 6, 30)
    np.testing.assert_array_equal(out[:, :, :22], X)
    assert len(meta["physics_feature_mean"]) == 8
    assert len(meta["physics_feature_std"]) == 8
    assert meta["source_feature_names"] == ["gyro_z", "I_lf", "I_rr", "v_hat", "dv_hat_dt_lp"]
    assert "y_raw(:,16)" in meta["forbidden_source_features"]
    names = augmented_feature_names(raw_names, meta)
    assert names[-3:] == ["phys_yaw_drive_accel", "phys_yaw_residual", "phys_yaw_res_ema_tau03"]
    assert np.all(np.isfinite(out))


def test_physics_residual_8_rejects_wrong_feature_order():
    raw_names = [f"f{i}" for i in range(22)]
    try:
        build_input_augmentation_metadata(
            "physics_residual_8",
            raw_input_dim=22,
            seq_len=6,
            feature_contract="passive17_plus_all5",
            feat_names=raw_names,
        )
    except ValueError as exc:
        assert "exact passive17_plus_all5 feature order" in str(exc)
    else:
        raise AssertionError("physics_residual_8 should reject unknown feature order")


if __name__ == "__main__":
    test_lag_stack_124_shape_and_edge_values()
    test_delta_bank_124_clips()
    test_mixed_lag_delta_14_shape()
    test_rejects_long_lag()
    test_physics_residual_8_shape_and_train_fit_stats()
    test_physics_residual_8_rejects_wrong_feature_order()
    print("lag_feature_tests: PASS")
