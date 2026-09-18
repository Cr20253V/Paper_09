function result = run_A1_offline_matlab(method_filter, seed_filter)
%RUN_A1_OFFLINE_MATLAB Native inference for frozen GRU/TCN offline cases.
if nargin < 1 || isempty(method_filter); method_filter = 'all'; end
if nargin < 2; seed_filter = []; end
init_project(); root = project_root();
task_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '39_paper_final_frozen_benchmark', '01_A1_algorithm_comparison');
raw_dir = fullfile(task_root, '03_offline', 'raw');
if exist(raw_dir, 'dir') ~= 7; mkdir(raw_dir); end
dataset_file = fullfile(root, 'data', 'tcn', ...
    'ModernTCN_dataset_agv_dualsteer_theta10_uniform_conf_h0_v5_plantfix_passive17_plus_all5.mat');
S = load(dataset_file, 'dataset'); d = S.dataset;
assert(size(d.X_test,1) == 3602 && size(d.X_test,2) == 128 && size(d.X_test,3) == 22, ...
    'A1:DatasetContract', 'Expected X_test=[3602,128,22].');
R = readtable(fullfile(task_root, 'model_registry.csv'), 'TextType', 'string');
keep = ismember(R.method_id, ["gru_22d","tcn_22d"]) & R.status == "READY";
if ~strcmpi(method_filter, 'all'); keep = keep & R.method_id == string(method_filter); end
if ~isempty(seed_filter); keep = keep & ismember(R.model_seed, double(seed_filter)); end
R = R(keep,:);
rows = repmat(struct('method_id',"",'seed',NaN,'status',"",'output_file',"",'elapsed_seconds',NaN,'message',""), height(R), 1);
for k = 1:height(R)
    method = char(R.method_id(k)); seed = double(R.model_seed(k)); model_file = char(R.model_file(k));
    out_file = fullfile(raw_dir, sprintf('%s_seed%d_predictions.csv', method, seed));
    rows(k).method_id = string(method); rows(k).seed = seed; rows(k).output_file = string(out_file);
    if local_valid_output(out_file, 3602)
        rows(k).status = "reused_verified"; fprintf('[A1 offline MATLAB] reuse %s seed=%d\n', method, seed); continue;
    end
    t0 = tic;
    try
        fprintf('[A1 offline MATLAB] infer %s seed=%d\n', method, seed);
        if strcmp(method, 'gru_22d')
            M = load(model_file, 'model'); model = M.model; predictor = [];
        else
            predictor = TCN_load_predictor(model_file); model = [];
        end
        n = size(d.X_test,1); lm = nan(n,3); lt = nan(n,3); theta = nan(n,1);
        for i = 1:n
            X = squeeze(d.X_test(i,:,:));
            if strcmp(method, 'gru_22d')
                [~,~,theta(i),conf] = GRU_infer(X, model);
                lm(i,:) = log(max(double(conf.conf_main(:).'), 1e-12));
                lt(i,:) = log(max(double(conf.conf_turn(:).'), 1e-12));
            else
                o = TCN_predict_window(predictor, X);
                theta(i) = o.theta_hat_rad; lm(i,:) = double(o.logits_main); lt(i,:) = double(o.logits_turn);
            end
            if mod(i,500)==0; fprintf('  %s seed=%d %d/%d\n', method, seed, i, n); end
        end
        pred_main = local_argmax0(lm); pred_turn = local_argmax0(lt);
        T = table((1:n).', double(d.run_id_test(:)), double(d.y_main_test(:))-1, ...
            double(d.y_turn_test(:))+1, double(d.y_theta_test(:)), double(d.mask_theta_test(:)), ...
            pred_main, pred_turn, theta, lm(:,1),lm(:,2),lm(:,3),lt(:,1),lt(:,2),lt(:,3), ...
            'VariableNames', {'window_index','run_id','y_main_true','y_turn_true','theta_true_rad','mask_theta', ...
            'pred_main','pred_turn','theta_hat_rad','main_logit_0','main_logit_1','main_logit_2', ...
            'turn_logit_0','turn_logit_1','turn_logit_2'});
        tmp = strrep(out_file, '.csv', '.tmp.csv'); writetable(T, tmp); movefile(tmp, out_file, 'f');
        audit = struct('task_id','A1_algorithm_comparison','method_id',method,'seed',seed, ...
            'model_file',model_file,'dataset_file',dataset_file,'test_windows',n,'seq_len',128, ...
            'raw_input_dim',22,'elapsed_seconds',toc(t0),'output_file',out_file,'status','COMPLETE');
        local_write_json(strrep(out_file, '.csv', '.audit.json'), audit);
        rows(k).status = "complete"; rows(k).elapsed_seconds = audit.elapsed_seconds;
    catch ME
        rows(k).status = "failed"; rows(k).message = string(getReport(ME,'extended','hyperlinks','off'));
        fid=fopen(strrep(out_file,'.csv','.failure.txt'),'w','n','UTF-8'); if fid>=0; fprintf(fid,'%s\n',rows(k).message); fclose(fid); end
        warning('A1:OfflineFailed', '%s seed=%d: %s', method, seed, ME.message);
    end
    writetable(struct2table(rows(1:k)), fullfile(task_root, '03_offline', 'matlab_inference_status_partial.csv'));
end
status_file = fullfile(task_root, '03_offline', 'matlab_inference_status.csv');
writetable(struct2table(rows), status_file);
result = struct('rows',struct2table(rows),'status_file',status_file);
end

function idx = local_argmax0(x)
[~,idx] = max(x,[],2); idx = idx-1;
end
function tf = local_valid_output(path,n)
tf=false; if exist(path,'file')~=2; return; end
try T=readtable(path); tf=height(T)==n && all(ismember({'theta_hat_rad','main_logit_0','turn_logit_0'},T.Properties.VariableNames)); catch; tf=false; end
end
function local_write_json(path,data)
fid=fopen(path,'w','n','UTF-8'); if fid<0; error('A1:JsonWrite','Cannot write %s',path); end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(data,'PrettyPrint',true));
end
