function spec = node53_v7_exploratory_spec(root,model_seed)
%NODE53_V7_EXPLORATORY_SPEC Fixed single-seed six-path exploratory contract.
if nargin < 1 || isempty(root); root = project_root(); end
if nargin < 2 || isempty(model_seed); model_seed = 42; end
node = fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');
branch = fullfile(node,'08_formal_six_path_exploratory_v7');
rel = { ...
    fullfile('data','paths','path_factory_logistics_showcase_theta10_v10.mat'), ...
    fullfile('data','paths','path_closed_loop_sharp_turn_transition_theta10_v1.mat'), ...
    fullfile('data','paths','path_closed_loop_long_updown_theta10_v1.mat'), ...
    fullfile('data','paths','modern_tcn_showcase','candidates','path_modern_tcn_showcase_candidate_soft_updown_straight_turn_v1.mat'), ...
    fullfile('data','paths','modern_tcn_showcase','candidates','path_modern_tcn_showcase_candidate_factory_flat_logistics_safe_190_v1.mat'), ...
    fullfile('data','paths','factory_targeted_eval','path_factory_target_downhill_straight_after_turn_v1.mat')};
spec = struct();
spec.protocol_id = sprintf('node53_v7_exploratory_six_path_seed%d_v1',model_seed);
spec.classification = 'RETROSPECTIVE_EXPLORATORY_R2_06_FUSION_BENCHMARK';
spec.exploratory_only = true;
spec.qualification_bypassed = true;
spec.formal_allowed = false;
spec.formal_claim_allowed = false;
spec.model_seed = double(model_seed);
spec.sensor_seed = 4631;
spec.path_ids = {'p01_factory_logistics_showcase','p02_sharp_turn_transition','p03_long_updown', ...
    'p04_soft_updown_straight_turn','p05_factory_flat_logistics','p06_downhill_after_turn'};
spec.path_names = {'P1 Factory logistics','P2 Sharp-turn transition','P3 Long up/down', ...
    'P4 Mild slope-turn coupling','P5 Flat factory logistics','P6 Downhill recovery'};
spec.path_files = cellfun(@(x)fullfile(root,x),rel,'UniformOutput',false);
spec.case_count = 6;
spec.group = 'EXPLORATORY';
spec.output_root = branch;
spec.case_root = fullfile(branch,'cases','V7',sprintf('seed%d',model_seed));
spec.model_file = fullfile(node,'06_model_freeze','v7_exploratory','LPVMPC_AGV_MTCN_FAKF6D_V7_Exp.slx');
spec.model_audit = fullfile(node,'06_model_freeze','v7_exploratory','model_build_audit.json');
spec.v7_config = fullfile(node,'04_fusion_calibration','iterations','08_slope_aware_paper_fusion_v7','selected_fusion_config.json');
spec.v7_export = fullfile(branch,'config','v7_hist_gradient_boosting_export.json');
spec.v7_joblib = fullfile(node,'04_fusion_calibration','iterations','08_slope_aware_paper_fusion_v7','models','final_train_validation_hist_gradient_boosting.joblib');
spec.estimator_config = fullfile(node,'02_fuzzyakf6','R2_06_FuzzyAKF6D.json');
spec.development_assessment = fullfile(node,'04_fusion_calibration','iterations','08_slope_aware_paper_fusion_v7','offline_development_assessment.json');
spec.upstream_model = fullfile(root,'results','modern_tcn_metric_rebuild','51_moderntcn_rkf_highrisk_suppression_rebuild','05_model_freeze','LPVMPC_AGV_ModernTCN_RKFFusion_Node51.slx');
spec.runtime_truth_read = false;
spec.test_read_count = 1;
spec.reuse_existing = true;
spec.stale_case_policy = 'move_under_case_attempts_without_overwrite';
spec.outputs = {'out.mat','trace.csv','normalized_trace.mat','node53_v7_runtime_debug.csv','node53_v7_runtime_debug.mat','case_metrics.json','case_manifest.json'};
end
