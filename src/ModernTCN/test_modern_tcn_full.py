"""Smoke checks for the ModernTCNFull v0 model family."""

from __future__ import annotations

import torch

from modern_tcn_model import ModernTCNFull, ModernTCNFullConfig, build_model_from_checkpoint_dict


def test_modern_tcn_full_default_forward_shapes() -> None:
    cfg = ModernTCNFullConfig(input_dim=22, seq_len=128)
    model = ModernTCNFull(cfg).eval()
    x = torch.randn(4, 128, 22)
    with torch.no_grad():
        logits_main, logits_turn, theta_hat = model(x)
    assert tuple(logits_main.shape) == (4, 3)
    assert tuple(logits_turn.shape) == (4, 3)
    assert tuple(theta_hat.shape) == (4, 1)


def test_modern_tcn_full_checkpoint_roundtrip() -> None:
    torch.manual_seed(0)
    cfg = ModernTCNFullConfig(
        input_dim=22,
        seq_len=128,
        dims=(8, 12),
        stage_blocks=(1, 1),
        large_kernels=(7, 5),
        small_kernels=(3, 3),
        ffn_ratio=1,
        dropout=0.0,
    )
    model = ModernTCNFull(cfg).eval()
    restored = build_model_from_checkpoint_dict(
        {
            "model_family": "full",
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
    test_modern_tcn_full_default_forward_shapes()
    test_modern_tcn_full_checkpoint_roundtrip()
    print("ModernTCNFull checks passed")
