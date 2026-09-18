"""Lightweight checks for the causal ModernTCN ablation path."""

from __future__ import annotations

import torch

from modern_tcn_model import ModernTCNConfig, ModernTCNSmall, build_model_from_checkpoint_dict


def test_same_and_causal_forward_shapes() -> None:
    for temporal_padding in ("same", "causal"):
        cfg = ModernTCNConfig(
            input_dim=22,
            seq_len=128,
            channels=16,
            blocks=2,
            kernel_size=7,
            dropout=0.0,
            temporal_padding=temporal_padding,
        )
        model = ModernTCNSmall(cfg).eval()
        x = torch.randn(3, 128, 22)
        with torch.no_grad():
            logits_main, logits_turn, theta_hat = model(x)
        assert tuple(logits_main.shape) == (3, 3)
        assert tuple(logits_turn.shape) == (3, 3)
        assert tuple(theta_hat.shape) == (3, 1)


def test_causal_prefix_invariance() -> None:
    torch.manual_seed(0)
    cfg = ModernTCNConfig(
        input_dim=22,
        seq_len=128,
        channels=16,
        blocks=2,
        kernel_size=7,
        dropout=0.0,
        temporal_padding="causal",
    )
    model = ModernTCNSmall(cfg).eval()

    x1 = torch.randn(2, 128, 22)
    x2 = x1.clone()
    cut = 64
    x2[:, cut + 1 :, :] = torch.randn_like(x2[:, cut + 1 :, :])

    with torch.no_grad():
        z1 = model.stem(x1.transpose(1, 2))
        z2 = model.stem(x2.transpose(1, 2))
        for block in model.blocks:
            z1 = block(z1)
            z2 = block(z2)

    max_diff = (z1[:, :, : cut + 1] - z2[:, :, : cut + 1]).abs().max().item()
    assert max_diff < 1e-5, max_diff


def test_legacy_checkpoint_defaults_to_same() -> None:
    cfg = ModernTCNConfig(
        input_dim=22,
        seq_len=128,
        channels=8,
        blocks=1,
        kernel_size=5,
        dropout=0.0,
        temporal_padding="same",
    )
    model = ModernTCNSmall(cfg).eval()
    cfg_dict = cfg.to_dict()
    cfg_dict.pop("temporal_padding")
    restored = build_model_from_checkpoint_dict(
        {
            "model_config": cfg_dict,
            "model_state": model.state_dict(),
        }
    )
    assert restored.cfg.temporal_padding == "same"


def test_causal_checkpoint_roundtrip() -> None:
    cfg = ModernTCNConfig(
        input_dim=22,
        seq_len=128,
        channels=8,
        blocks=1,
        kernel_size=5,
        dropout=0.0,
        temporal_padding="causal",
    )
    model = ModernTCNSmall(cfg).eval()
    restored = build_model_from_checkpoint_dict(
        {
            "model_config": cfg.to_dict(),
            "model_state": model.state_dict(),
        }
    ).eval()
    x = torch.randn(2, 128, 22)
    with torch.no_grad():
        y1 = model(x)
        y2 = restored(x)
    max_diff = max((a - b).abs().max().item() for a, b in zip(y1, y2))
    assert max_diff < 1e-7, max_diff


if __name__ == "__main__":
    test_same_and_causal_forward_shapes()
    test_causal_prefix_invariance()
    test_legacy_checkpoint_defaults_to_same()
    test_causal_checkpoint_roundtrip()
    print("causal ModernTCN checks passed")
