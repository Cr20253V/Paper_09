from __future__ import annotations

import csv
import json
import math
import platform
import sys
from pathlib import Path

from node53_common import NODE, ROOT, sha256, write_csv, write_json

PKG = NODE / 'cache/python_packages'
if str(PKG) not in sys.path:
    sys.path.insert(0, str(PKG))
import joblib  # noqa: E402
import numpy as np  # noqa: E402

BRANCH = NODE / '08_formal_six_path_exploratory_v7'
V7 = NODE / '04_fusion_calibration' / 'iterations' / '08_slope_aware_paper_fusion_v7'
PATHS = [
    ('p01_factory_logistics_showcase', 'P1 Factory logistics', ROOT / 'data/paths/path_factory_logistics_showcase_theta10_v10.mat'),
    ('p02_sharp_turn_transition', 'P2 Sharp-turn transition', ROOT / 'data/paths/path_closed_loop_sharp_turn_transition_theta10_v1.mat'),
    ('p03_long_updown', 'P3 Long up/down', ROOT / 'data/paths/path_closed_loop_long_updown_theta10_v1.mat'),
    ('p04_soft_updown_straight_turn', 'P4 Mild slope-turn coupling', ROOT / 'data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat'),
    ('p05_factory_flat_logistics', 'P5 Flat factory logistics', ROOT / 'data/paths/modern_tcn_showcase/candidates/path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat'),
    ('p06_downhill_after_turn', 'P6 Downhill recovery', ROOT / 'data/paths/factory_targeted_eval/path_factory_target_downhill_straight_after_turn_v1.mat'),
]
SEED = 42
SENSOR_SEED = 4631
MODEL_SEEDS = [1, 7, 11, 21, 42, 73, 101, 202, 340, 520]

def _latest_metrics_path(case_root: Path) -> Path | None:
    candidates = []
    direct = case_root / 'case_metrics.json'
    if direct.is_file():
        candidates.append(direct)
    attempts = case_root / 'attempts'
    if attempts.is_dir():
        candidates.extend(attempts.glob('*/case_metrics.json'))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)

def _json_probability(payload: dict, row: np.ndarray) -> float:
    raw = float(payload['baseline_prediction'])
    for tree in payload['trees']:
        node = 0
        while int(tree['is_leaf'][node]) == 0:
            feature = int(tree['feature_idx'][node])
            value = float(row[feature])
            if not math.isfinite(value):
                go_left = bool(tree['missing_go_to_left'][node])
            else:
                bin_index = sum(value > float(t) for t in payload['bin_thresholds'][feature])
                go_left = bin_index <= int(tree['bin_threshold'][node])
            node = int(tree['left'][node] if go_left else tree['right'][node])
        raw += float(tree['value'][node])
    return 1.0 / (1.0 + math.exp(-raw))

def _export_parity(export_file: Path, joblib_file: Path) -> dict:
    payload = json.loads(export_file.read_text(encoding='utf-8'))
    model = joblib.load(joblib_file)
    rng = np.random.default_rng(530642)
    fixture = rng.normal(0.0, 2.0, size=(128, int(payload['feature_count'])))
    fixture[0, :] = 0.0
    fixture[1, 0] = np.nan
    expected = np.asarray(model.predict_proba(fixture)[:, 1], dtype=float)
    actual = np.asarray([_json_probability(payload, row) for row in fixture], dtype=float)
    maximum = float(np.max(np.abs(expected - actual)))
    return {
        'status': 'PASS_NODE53_V7_EXPORT_PARITY' if maximum <= 1e-12 else 'FAIL_NODE53_V7_EXPORT_PARITY',
        'fixture_seed': 530642, 'sample_count': len(fixture), 'feature_count': fixture.shape[1],
        'tree_count': len(payload['trees']), 'max_abs_error': maximum,
        'source_model_sha256': sha256(joblib_file), 'export_sha256': sha256(export_file),
        'fixture': {'features': fixture[:16].tolist(), 'expected_probability': expected[:16].tolist()},
    }

def _assets(export: Path, joblib_file: Path, model: Path) -> list[dict]:
    checkpoint = ROOT / 'results/modern_tcn_metric_rebuild/25_lag_representation_repair/02_train_candidates/delta_bank_124/seed42/modern_tcn_seed42.pt'
    onnx = ROOT / 'results/modern_tcn_metric_rebuild/25_lag_representation_repair/03_onnx_and_smoke/delta_bank_124/seed42/modern_tcn_delta_bank_124_seed42.onnx'
    values = [
        ('paper', ROOT / 'results/paper/Latex/paper_v4_final_candidate.tex'),
        ('root protocol', NODE / 'protocol_lock.json'), ('V7 frozen config', V7 / 'selected_fusion_config.json'),
        ('V7 development assessment', V7 / 'offline_development_assessment.json'), ('V7 sklearn model', joblib_file), ('V7 MATLAB export', export),
        ('R2_06 config', NODE / '02_fuzzyakf6/R2_06_FuzzyAKF6D.json'), ('ModernTCN ONNX', onnx), ('ModernTCN checkpoint', checkpoint),
        ('upstream model', ROOT / 'results/modern_tcn_metric_rebuild/51_moderntcn_rkf_highrisk_suppression_rebuild/05_model_freeze/LPVMPC_AGV_ModernTCN_RKFFusion_Node51.slx'),
    ]
    values.extend(('six-path input', p) for _, _, p in PATHS)
    values.extend(('Node53 runtime source', NODE / 'tools' / name) for name in [
        'node53_v7_runtime_config.m','node53_v7_runtime_selector.m','node53_v7_runtime_features.m','node53_v7_predict_help.m',
        'node53_v7_uncertainty_fusion.m','node53_fuzzyakf6_estimator.m','agv_model_sfunc_node53_fuzzyakf6d.m',
        'ModernTCN_FuzzyAKF6DFusion_Node53_v7_sim.m','node53_v7_exploratory_spec.m','run_node53_v7_exploratory_six_path.m',
    ])
    if model.is_file(): values.append(('Node53 exploratory model', model))
    rows = []
    for role, path in values:
        rows.append({'role': role, 'path': str(path.resolve()), 'exists': path.is_file(), 'size': path.stat().st_size if path.is_file() else '', 'sha256_begin': sha256(path) if path.is_file() else ''})
    return rows

def main(command: str = 'preflight') -> int:
    export = BRANCH / 'config/v7_hist_gradient_boosting_export.json'
    joblib = V7 / 'models/final_train_validation_hist_gradient_boosting.joblib'
    model = NODE / '06_model_freeze/v7_exploratory/LPVMPC_AGV_MTCN_FAKF6D_V7_Exp.slx'
    rows = []
    for path_id, path_name, path_file in PATHS:
        case_dir = BRANCH / 'cases/V7/seed42' / path_id
        onnx = ROOT / 'results/modern_tcn_metric_rebuild/25_lag_representation_repair/03_onnx_and_smoke/delta_bank_124/seed42/modern_tcn_delta_bank_124_seed42.onnx'
        ready = path_file.is_file() and onnx.is_file()
        rows.append({
            'model_seed': SEED, 'sensor_seed': SENSOR_SEED, 'path_id': path_id, 'path_name': path_name,
            'path_file': str(path_file.resolve()), 'path_sha256': sha256(path_file) if path_file.is_file() else '',
            'onnx_file': str(onnx.resolve()), 'onnx_sha256': sha256(onnx) if onnx.is_file() else '',
            'model_file': str(model.resolve()), 'model_sha256': sha256(model) if model.is_file() else '',
            'case_dir': str(case_dir.resolve()), 'case_key': f'EXPLORATORY|{SEED}|{path_id}',
            'status': 'READY_ASSETS' if ready and model.is_file() else ('READY_MODEL_PENDING' if ready else 'MISSING'),
        })
    write_csv(BRANCH / 'preflight_v7.csv', rows)
    assessment = json.loads((V7 / 'offline_development_assessment.json').read_text(encoding='utf-8'))
    selected = json.loads((V7 / 'selected_fusion_config.json').read_text(encoding='utf-8'))
    receipt = {
        'status': 'PASS_NODE53_V7_EXPLORATORY_PREFLIGHT' if all(r['status'].startswith('READY_') for r in rows) else 'FAIL_NODE53_V7_EXPLORATORY_PREFLIGHT',
        'protocol_id': 'node53_v7_exploratory_six_path_seed42_v1',
        'classification': 'RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK',
        'exploratory_only': True, 'qualification_bypassed': True, 'formal_allowed': False, 'formal_claim_allowed': False,
        'case_count': len(rows), 'ready_count': sum(r['status'].startswith('READY_') for r in rows),
        'model_pending': not model.is_file(),
        'model_seed': SEED, 'sensor_seed': SENSOR_SEED, 'test_read_count': 1,
        'v7_development_status': assessment.get('status'), 'v7_selected_candidate': selected.get('selected', {}).get('candidate_id'),
        'v7_Kmax': selected.get('selected', {}).get('Kmax'), 'v7_p_help_threshold': selected.get('selected', {}).get('p_help_threshold'),
        'v7_slope_entry_deg': selected.get('selected', {}).get('slope_entry_deg'), 'v7_slope_exit_deg': selected.get('selected', {}).get('slope_exit_deg'),
        'v7_innovation_min_deg': selected.get('selected', {}).get('innovation_min_deg'),
        'runtime_truth_read': False, 'python': sys.version, 'platform': platform.platform(),
        'v7_export_sha256': sha256(export) if export.is_file() else '', 'v7_joblib_sha256': sha256(joblib) if joblib.is_file() else '',
    }
    parity = _export_parity(export, joblib)
    receipt['v7_export_parity_status'] = parity['status']
    receipt['v7_export_parity_max_abs_error'] = parity['max_abs_error']
    write_json(BRANCH / 'config/v7_export_parity.json', parity)
    protocol = {
        'protocol_id': receipt['protocol_id'], 'classification': receipt['classification'], 'status': 'LOCKED_FOR_SINGLE_SEED_EXPLORATORY_SIX_PATH',
        'exploratory_only': True, 'qualification_bypassed': True, 'formal_allowed': False, 'formal_claim_allowed': False,
        'retrospective_frozen_benchmark': True, 'test_read_count': 1, 'test_read_limit': 1, 'paper_write_allowed': False,
        'runtime_truth_read': False, 'Ts': 0.01, 'g': 9.81, 'imu_order': ['fx','fy','fz','gx','gy','gz'],
        'model_seed': SEED, 'sensor_seed': SENSOR_SEED, 'case_count': 6, 'paths': [{'path_id': x[0], 'path_name': x[1], 'path_file': str(x[2].resolve())} for x in PATHS],
        'selected_candidate': selected['selected']['candidate_id'], 'Kmax': selected['selected']['Kmax'], 'p_help_threshold': selected['selected']['p_help_threshold'],
        'slope_entry_deg': selected['selected']['slope_entry_deg'], 'slope_exit_deg': selected['selected']['slope_exit_deg'],
        'innovation_min_deg': selected['selected']['innovation_min_deg'], 'quality_intercept': selected['selected']['quality_intercept'], 'quality_slope': selected['selected']['quality_slope'], 'quality_floor': selected['selected']['quality_floor'],
        'innovation_gate_deg': 2.0, 'nis_downweight': 9.0, 'nis_reject': 25.0, 'correction_limit_deg': 0.5, 'rate_limit_deg_s': 5.0,
        'guard_deadband_deg': 1.3, 'guard_clip_deg': [-10.0,10.0], 'fallback_identity': 'theta_fused == theta_tcn and correction == 0',
        'output_root': str(BRANCH.resolve()), 'stale_case_policy': 'preserve under attempts; never overwrite',
    }
    write_json(BRANCH / 'config/exploratory_protocol_lock.json', protocol)
    write_csv(BRANCH / 'config/source_manifest_v7_exploratory.csv', _assets(export, joblib, model))
    write_json(BRANCH / 'preflight_v7.json', receipt)
    if command == 'summarize':
        summaries = []
        for seed in MODEL_SEEDS:
            locations = {path_id: BRANCH / f'cases/V7/seed{seed}' / path_id for path_id, _, _ in PATHS}
            progress = BRANCH / f'progress_v7_seed{seed}.csv'
            if progress.is_file():
                with progress.open('r', encoding='utf-8-sig', newline='') as handle:
                    for row in csv.DictReader(handle):
                        if row.get('path_id') and row.get('actual_case_dir'):
                            locations[row['path_id']] = Path(row['actual_case_dir'])
            for path_id, _, _ in PATHS:
                base = BRANCH / f'cases/V7/seed{seed}' / path_id
                p = locations[path_id] / 'case_metrics.json'
                if not p.is_file():
                    p = _latest_metrics_path(base)
                if p is not None and p.is_file():
                    value = json.loads(p.read_text(encoding='utf-8')); value['case_metrics_path'] = str(p.resolve()); summaries.append(value)
        write_json(BRANCH / 'v7_all_available_metrics.json', summaries)
        summary_rows = [{name: value.get(name) for name in ('path_id','model_seed','sensor_seed','case_status','safety_status','theta_sched_mae_deg','ey_rmse','epsi_rmse','xy_rmse','j_du','omega_cmd_rms','active_fraction','active_improve_fraction','active_degrade_fraction','fallback_fraction','safety_failure_count','case_metrics_path')} for value in summaries]
        if summary_rows: write_csv(BRANCH / 'v7_all_available_metrics.csv', summary_rows)
        safety_status = 'PENDING_NODE53_V7_CLOSED_LOOP' if not summaries else ('PASS_NODE53_V7_ALL_AVAILABLE_SAFETY' if all(x.get('safety_status') == 'PASS_NODE53_V7_CASE_SAFETY' for x in summaries) else 'INCOMPLETE_OR_FAILED_NODE53_V7_ALL_AVAILABLE_SAFETY')
        write_json(BRANCH / 'v7_all_available_safety_summary.json', {
            'status': safety_status,
            'available_case_count': len(summaries), 'expected_single_seed_case_count': 6, 'expected_multi_seed_case_count': 60,
            'safety_pass_count': sum(x.get('safety_status') == 'PASS_NODE53_V7_CASE_SAFETY' for x in summaries),
            'model_seeds_present': sorted({int(x['model_seed']) for x in summaries if x.get('model_seed') is not None}),
        })
        manifest_file = BRANCH / 'config/source_manifest_v7_exploratory.csv'
        end_rows = []
        with manifest_file.open('r', encoding='utf-8-sig', newline='') as handle:
            for row in csv.DictReader(handle):
                path = Path(row['path']); exists = path.is_file(); end_hash = sha256(path) if exists else ''
                row['exists_end'] = exists; row['sha256_end'] = end_hash; row['unchanged'] = bool(exists and end_hash == row['sha256_begin']); end_rows.append(row)
        write_csv(BRANCH / 'config/source_manifest_v7_exploratory_end.csv', end_rows)
        write_json(BRANCH / 'protection_audit_end.json', {'status': 'PASS_NODE53_V7_EXPLORATORY_PROTECTION_AUDIT' if all(r['unchanged'] for r in end_rows) else 'FAIL_NODE53_V7_EXPLORATORY_PROTECTION_AUDIT', 'asset_count': len(end_rows), 'unchanged_count': sum(r['unchanged'] for r in end_rows)})
        return 0
    return 0 if receipt['status'].startswith('PASS') and parity['status'].startswith('PASS') else 2

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else 'preflight'))
