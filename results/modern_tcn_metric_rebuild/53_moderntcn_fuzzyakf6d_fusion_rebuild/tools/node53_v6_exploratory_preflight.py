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

BRANCH = NODE / '08_formal_six_path_exploratory_v6'
V6 = NODE / '04_fusion_calibration' / 'iterations' / '07_supervised_runtime_gate_v6'
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
        'status': 'PASS_NODE53_V6_EXPORT_PARITY' if maximum <= 1e-12 else 'FAIL_NODE53_V6_EXPORT_PARITY',
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
        ('root protocol', NODE / 'protocol_lock.json'), ('V6 frozen config', V6 / 'selected_fusion_config_final_train_validation.json'),
        ('V6 qualification', V6 / 'offline_qualification_v6.json'), ('V6 sklearn model', joblib_file), ('V6 MATLAB export', export),
        ('R2_06 config', NODE / '02_fuzzyakf6/R2_06_FuzzyAKF6D.json'), ('ModernTCN ONNX', onnx), ('ModernTCN checkpoint', checkpoint),
        ('upstream model', ROOT / 'results/modern_tcn_metric_rebuild/51_moderntcn_rkf_highrisk_suppression_rebuild/05_model_freeze/LPVMPC_AGV_ModernTCN_RKFFusion_Node51.slx'),
    ]
    values.extend(('six-path input', p) for _, _, p in PATHS)
    values.extend(('Node53 runtime source', NODE / 'tools' / name) for name in [
        'node53_v6_runtime_config.m','node53_v6_runtime_selector.m','node53_v6_runtime_features.m','node53_v6_predict_help.m',
        'node53_v6_uncertainty_fusion.m','node53_fuzzyakf6_estimator.m','agv_model_sfunc_node53_fuzzyakf6d.m',
        'ModernTCN_FuzzyAKF6DFusion_Node53_v6_sim.m','node53_v6_exploratory_spec.m','run_node53_v6_exploratory_six_path.m',
    ])
    if model.is_file(): values.append(('Node53 exploratory model', model))
    rows = []
    for role, path in values:
        rows.append({'role': role, 'path': str(path.resolve()), 'exists': path.is_file(), 'size': path.stat().st_size if path.is_file() else '', 'sha256_begin': sha256(path) if path.is_file() else ''})
    return rows

def main(command: str = 'preflight') -> int:
    export = BRANCH / 'config/v6_hist_gradient_boosting_export.json'
    joblib = V6 / 'models/final_train_validation_hist_gradient_boosting.joblib'
    model = NODE / '06_model_freeze/v6_exploratory/LPVMPC_AGV_MTCN_FAKF6D_V6_Exp.slx'
    rows = []
    for path_id, path_name, path_file in PATHS:
        case_dir = BRANCH / 'cases/V6/seed42' / path_id
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
    write_csv(BRANCH / 'preflight_v6.csv', rows)
    q = json.loads((V6 / 'offline_qualification_v6.json').read_text(encoding='utf-8'))
    selected = json.loads((V6 / 'selected_fusion_config_final_train_validation.json').read_text(encoding='utf-8'))
    receipt = {
        'status': 'PASS_NODE53_V6_EXPLORATORY_PREFLIGHT' if all(r['status'].startswith('READY_') for r in rows) else 'FAIL_NODE53_V6_EXPLORATORY_PREFLIGHT',
        'protocol_id': 'node53_v6_exploratory_six_path_seed42_v1',
        'classification': 'EXPLORATORY_NONQUALIFIED_R2_06_FUSION_REBUILD',
        'exploratory_only': True, 'qualification_failed': True, 'formal_allowed': False, 'formal_claim_allowed': False,
        'case_count': len(rows), 'ready_count': sum(r['status'].startswith('READY_') for r in rows),
        'model_pending': not model.is_file(),
        'model_seed': SEED, 'sensor_seed': SENSOR_SEED, 'test_read_count': 1,
        'v6_qualification_status': q.get('status'), 'v6_selected_candidate': selected.get('selected', {}).get('candidate_id'),
        'v6_Kmax': selected.get('selected', {}).get('Kmax'), 'v6_p_help_threshold': selected.get('selected', {}).get('p_help_threshold'),
        'runtime_truth_read': False, 'python': sys.version, 'platform': platform.platform(),
        'v6_export_sha256': sha256(export) if export.is_file() else '', 'v6_joblib_sha256': sha256(joblib) if joblib.is_file() else '',
    }
    parity = _export_parity(export, joblib)
    receipt['v6_export_parity_status'] = parity['status']
    receipt['v6_export_parity_max_abs_error'] = parity['max_abs_error']
    write_json(BRANCH / 'config/v6_export_parity.json', parity)
    protocol = {
        'protocol_id': receipt['protocol_id'], 'classification': receipt['classification'], 'status': 'LOCKED_FOR_SINGLE_SEED_EXPLORATORY_SIX_PATH',
        'exploratory_only': True, 'qualification_failed': True, 'formal_allowed': False, 'formal_claim_allowed': False,
        'retrospective_frozen_benchmark': True, 'test_read_count': 1, 'test_read_limit': 1, 'paper_write_allowed': False,
        'runtime_truth_read': False, 'Ts': 0.01, 'g': 9.81, 'imu_order': ['fx','fy','fz','gx','gy','gz'],
        'model_seed': SEED, 'sensor_seed': SENSOR_SEED, 'case_count': 6, 'paths': [{'path_id': x[0], 'path_name': x[1], 'path_file': str(x[2].resolve())} for x in PATHS],
        'selected_candidate': 'C24', 'Kmax': 0.9, 'p_help_threshold': 0.6, 'quality_intercept': 1.0, 'quality_slope': 0.5, 'quality_floor': 0.5,
        'innovation_gate_deg': 2.0, 'nis_downweight': 9.0, 'nis_reject': 25.0, 'correction_limit_deg': 0.5, 'rate_limit_deg_s': 5.0,
        'guard_deadband_deg': 1.3, 'guard_clip_deg': [-10.0,10.0], 'fallback_identity': 'theta_fused == theta_tcn and correction == 0',
        'output_root': str(BRANCH.resolve()), 'stale_case_policy': 'preserve under attempts; never overwrite',
    }
    write_json(BRANCH / 'config/exploratory_protocol_lock.json', protocol)
    write_csv(BRANCH / 'config/source_manifest_v6_exploratory.csv', _assets(export, joblib, model))
    write_json(BRANCH / 'preflight_v6.json', receipt)
    if command == 'summarize':
        summaries = []
        locations = {path_id: BRANCH / 'cases/V6/seed42' / path_id for path_id, _, _ in PATHS}
        progress = BRANCH / 'progress_v6.csv'
        if progress.is_file():
            with progress.open('r', encoding='utf-8-sig', newline='') as handle:
                for row in csv.DictReader(handle):
                    if row.get('path_id') and row.get('actual_case_dir'):
                        locations[row['path_id']] = Path(row['actual_case_dir'])
        for path_id, _, _ in PATHS:
            p = locations[path_id] / 'case_metrics.json'
            if p.is_file():
                summaries.append(json.loads(p.read_text(encoding='utf-8')))
        write_json(BRANCH / 'v6_six_path_metrics_python.json', summaries)
        manifest_file = BRANCH / 'config/source_manifest_v6_exploratory.csv'
        end_rows = []
        with manifest_file.open('r', encoding='utf-8-sig', newline='') as handle:
            for row in csv.DictReader(handle):
                path = Path(row['path']); exists = path.is_file(); end_hash = sha256(path) if exists else ''
                row['exists_end'] = exists; row['sha256_end'] = end_hash; row['unchanged'] = bool(exists and end_hash == row['sha256_begin']); end_rows.append(row)
        write_csv(BRANCH / 'config/source_manifest_v6_exploratory_end.csv', end_rows)
        write_json(BRANCH / 'protection_audit_end.json', {'status': 'PASS_NODE53_V6_EXPLORATORY_PROTECTION_AUDIT' if all(r['unchanged'] for r in end_rows) else 'FAIL_NODE53_V6_EXPLORATORY_PROTECTION_AUDIT', 'asset_count': len(end_rows), 'unchanged_count': sum(r['unchanged'] for r in end_rows)})
        return 0
    return 0 if receipt['status'].startswith('PASS') and parity['status'].startswith('PASS') else 2

if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else 'preflight'))
