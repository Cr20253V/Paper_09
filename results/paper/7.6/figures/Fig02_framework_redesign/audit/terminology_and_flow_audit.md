# Figure 2 terminology and flow audit

## Confirmed implementation facts

| Figure element | Verified wording/content | Source in manuscript |
|---|---|---|
| Primary perception branch | Lightweight task-specific **ModernTCN**; 22-D proprioceptive features, normalized delta bank with lags `{1,2,4}`, chronological `128 x 88` history | Sec. III-A to III-C, lines 389–420 and 549–593 |
| Primary output | ModernTCN grade estimate plus main-regime confidence; it remains the primary source for fusion | lines 422–447 and 598–601 |
| Auxiliary branch | **Qualified observer**, not “force-balance observer”; it receives a bias-compensated six-axis IMU packet and outputs an observer grade/quality signal | lines 595–607 and 609–646 |
| Fusion logic | Innovation/NIS-conditioned, asymmetric correction; bounded target correction, rate limiting, and exact identity fallback to the ModernTCN estimate | lines 648–708 and Algorithm 1, lines 719–737 |
| Grade conditioning | Deadband, amplitude clip to `[-10°,10°]`, then the unchanged causal scheduling filter | lines 706–717 |
| Controller interface | One `theta_sch` updates the scheduling vector, measured-disturbance channel, grade feedforward, weights, and input envelopes; constrained QP uses `Np=150`, `Nc=30` | lines 817–829 and 933–944 |
| LPV database | `11 x 15 x 25 = 4125` local models over speed, yaw rate, and grade; online use is interpolation | lines 799–813 |
| Offline data | 102 continuous simulation runs from 51 route templates; normalization is fit on training runs and the deployed interface is fixed before closed-loop evaluation | lines 971–984 |

## Corrections made relative to the previous figure

1. Replaced **Force-balance observer** with **Qualified observer**.
2. Split the former generic “onboard measurements” trunk into two explicit packets: vehicle-response history for ModernTCN and bias-compensated six-axis IMU for the Qualified observer.
3. Replaced the ambiguous “Delta-lag window” block with the more precise “22-D features + delta bank” and showed the four blocks `[z, Delta_1, Delta_2, Delta_4]`.
4. Renamed the controller stage to **Fused-grade-scheduled LPV-MPC** and exposed the five synchronized grade-dependent paths (`model`, `d`, `F_eq`, `Q/R`, `bounds`).
5. Separated offline deployment artifacts into ModernTCN weights/statistics, fusion error moments, and the 4125-model LPV database.
6. Made the online loop explicit: `u_k` is applied to the nonlinear AGV plant, whose responses return to onboard sensing at the next control period.

## Design rationale

The reference image was used only for its clear visual grammar: a dashed offline layer, a solid online layer, pictorial module icons, and short labels carried by arrows. The redesigned figure keeps the manuscript's information but removes long text-in-box paragraphs, uses blue/teal/navy/orange to distinguish signal roles, and makes the single-source grade-scheduling rule visible rather than leaving it implicit in a large LPV-MPC box.
