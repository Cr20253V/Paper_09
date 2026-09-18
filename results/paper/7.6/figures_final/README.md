# Final manuscript figure workspace

Each manuscript figure is stored in one numbered directory. The number follows the
current `paper_v3 _1.tex` compilation order, while the suffix follows the LaTeX label.

```text
figures_final/
├─ shared/                         # shared palette and plotting style
├─ Fig03_closed_loop_route_set/
│  ├─ scripts/
│  ├─ source_data/
│  ├─ output/
│  ├─ qa/
│  └─ archive/                    # superseded drafts for this figure only
├─ Fig04_slope_necessity_effects/
├─ Fig05_offline_estimator_distribution/
├─ Fig06_imu_observer_trace/
├─ Fig07_fusion_case_distribution/
├─ Fig08_fusion_qualitative_trace/
└─ Fig09_five_controller_qualitative/
```

Only a figure's current deliverables belong in `output/`. Intermediate or superseded
versions go into that figure's `archive/` directory. Scripts must resolve data from the
project root and write source data, outputs, and QA records into their own numbered
figure directory.
