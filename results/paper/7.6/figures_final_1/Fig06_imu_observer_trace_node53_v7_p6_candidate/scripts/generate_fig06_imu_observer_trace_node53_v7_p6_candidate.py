"""Generate the V7/P6 Fig. 6 candidate by specializing the verified V7/P1 pipeline."""

from pathlib import Path


HERE = Path(__file__).resolve()
P1_SCRIPT = (
    HERE.parents[2]
    / "Fig06_imu_observer_trace_node53_v7_p1_candidate"
    / "scripts"
    / "generate_fig06_imu_observer_trace_node53_v7_p1_candidate.py"
)

source = P1_SCRIPT.read_text(encoding="utf-8")
replacements = {
    "Node53 V7/P1": "Node53 V7/P6",
    "Node53_V7_P1_seed42": "Node53_V7_P6_seed42",
    "Fig06_imu_observer_trace_node53_v7_p1_candidate": (
        "Fig06_imu_observer_trace_node53_v7_p6_candidate"
    ),
    "p01_factory_logistics_showcase": "p06_downhill_after_turn",
    "P1 factory-logistics showcase": "P6 downhill-after-turn",
    "P1 trace": "P6 trace",
    "V7/P1 case": "V7/P6 case",
    "V7/P1 observer": "V7/P6 observer",
    "tick_step = 50.0": (
        "tick_step = 10.0 if time_end <= 60.0 else "
        "(20.0 if time_end <= 120.0 else 50.0)"
    ),
}
for old, new in replacements.items():
    if old not in source:
        raise RuntimeError(f"Expected specialization token missing from P1 pipeline: {old}")
    source = source.replace(old, new)

exec(compile(source, str(HERE), "exec"), {"__name__": "__main__", "__file__": str(HERE)})
