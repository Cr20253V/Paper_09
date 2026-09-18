from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "ModernTCN"))

from modern_tcn_data import ModernTCNContract, _check_contract


def _contract(**overrides):
    data = {
        "dataset_file": "dummy.mat",
        "seq_len": 128,
        "input_dim": 22,
        "output_contract": "logits_main3_logits_turn3_theta1",
        "split_policy": "run_level_no_window_leakage",
        "scaler_policy": "fit_train_only_apply_val_test_online",
        "feature_contract": "passive17_plus_all5",
        "label_time_policy": "current_window_end",
        "horizon_steps": 0,
    }
    data.update(overrides)
    return ModernTCNContract(**data)


def test_contract_allows_seq128_and_seq256_passive22():
    _check_contract(_contract(seq_len=128))
    _check_contract(_contract(seq_len=256))


def test_contract_rejects_unlisted_seq_len():
    for seq_len in (64, 512):
        try:
            _check_contract(_contract(seq_len=seq_len))
        except ValueError as exc:
            assert "seq_len=128/256" in str(exc)
        else:
            raise AssertionError(f"seq_len={seq_len} should have failed")


def test_contract_rejects_wrong_input_dim_for_passive22():
    try:
        _check_contract(_contract(input_dim=30))
    except ValueError as exc:
        assert "passive17_plus_all5" in str(exc)
        assert "input_dim=22" in str(exc)
    else:
        raise AssertionError("wrong input_dim should have failed")


def test_contract_rejects_unknown_feature_contract():
    try:
        _check_contract(_contract(feature_contract="wrong_contract"))
    except ValueError as exc:
        assert "feature contract" in str(exc)
    else:
        raise AssertionError("wrong feature_contract should have failed")


def test_contract_rejects_nonzero_horizon():
    try:
        _check_contract(_contract(horizon_steps=1))
    except ValueError as exc:
        assert "horizon_steps=0" in str(exc)
    else:
        raise AssertionError("nonzero horizon should have failed")


if __name__ == "__main__":
    test_contract_allows_seq128_and_seq256_passive22()
    test_contract_rejects_unlisted_seq_len()
    test_contract_rejects_wrong_input_dim_for_passive22()
    test_contract_rejects_unknown_feature_contract()
    test_contract_rejects_nonzero_horizon()
    print("modern_tcn_contract_tests: PASS")
