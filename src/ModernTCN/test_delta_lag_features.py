from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "ModernTCN"))

from modern_tcn_delta_features import augment_with_delta_lag


def test_lag1_shape_and_values():
    X = np.arange(2 * 5 * 3, dtype=np.float32).reshape(2, 5, 3)
    out = augment_with_delta_lag(X, lag=1)
    assert out.shape == (2, 5, 6)
    np.testing.assert_array_equal(out[:, :, :3], X)
    np.testing.assert_array_equal(out[:, 0, 3:], np.zeros((2, 3), dtype=np.float32))
    np.testing.assert_array_equal(out[:, 1:, 3:], X[:, 1:, :] - X[:, :-1, :])
    assert out.dtype == np.float32


def test_lag2_zero_pad():
    X = np.arange(2 * 5 * 3, dtype=np.float32).reshape(2, 5, 3)
    out = augment_with_delta_lag(X, lag=2)
    np.testing.assert_array_equal(out[:, :2, 3:], np.zeros((2, 2, 3), dtype=np.float32))
    np.testing.assert_array_equal(out[:, 2:, 3:], X[:, 2:, :] - X[:, :-2, :])


def test_rejects_invalid_lag():
    X = np.zeros((2, 5, 3), dtype=np.float32)
    for lag in (0, 5, 6):
        try:
            augment_with_delta_lag(X, lag=lag)
        except ValueError:
            pass
        else:
            raise AssertionError(f"lag={lag} should have failed")


def test_rejects_non_3d_and_non_zero_pad():
    try:
        augment_with_delta_lag(np.zeros((5, 3), dtype=np.float32), lag=1)
    except ValueError as exc:
        assert "[N,T,F]" in str(exc)
    else:
        raise AssertionError("2D input should have failed")

    try:
        augment_with_delta_lag(np.zeros((2, 5, 3), dtype=np.float32), lag=1, pad="repeat")
    except ValueError as exc:
        assert "zero padding" in str(exc)
    else:
        raise AssertionError("non-zero pad should have failed")


def test_does_not_modify_original():
    X = np.arange(2 * 5 * 3, dtype=np.float32).reshape(2, 5, 3)
    before = X.copy()
    _ = augment_with_delta_lag(X, lag=1)
    np.testing.assert_array_equal(X, before)


if __name__ == "__main__":
    test_lag1_shape_and_values()
    test_lag2_zero_pad()
    test_rejects_invalid_lag()
    test_rejects_non_3d_and_non_zero_pad()
    test_does_not_modify_original()
    print("delta_lag_feature_tests: PASS")
