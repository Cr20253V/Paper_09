# TCN/GRU authority-semantics audit

The frozen MATLAB public predictors receive one logical `[128,22]` window, transpose it to `[22,128,1]`, and label the resulting `dlarray` as `CBT`. Direct inspection on the frozen seed-42 models produced:

```text
X size=[22 128 1] dims=CBT
TCN Z size=[96 128 1] dims=CBT
GRU Z size=[96 128 1] dims=CBT
```

Thus the authority execution uses `C=features`, `B=128`, and `T=1`, then applies its `last`/mean/max readout along dimension 2 (the labeled B axis). This is not changed in the supplemental benchmark because doing so would create a different predictor and invalidate comparison with A1 accuracy and the frozen model artifacts.

The derived TCN/GRU ONNX graphs therefore use MATLAB export `BatchSize=128`, accept the same numeric `[1,128,22]` FP32 tensor, and reproduce the authority readout over ONNX axis 1. The numerical-equivalence gate must pass all 3,602 test windows before timing.

Interpretation limitation: the same-backend result removes the runtime-backend confound, but it does not establish a conventional sequence-model FLOP comparison between a length-128 GRU/TCN and ModernTCN. Any paper claim must disclose this frozen execution semantics or restrict itself to measured latency of the evaluated implementations.

