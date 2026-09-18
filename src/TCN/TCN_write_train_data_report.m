function report = TCN_write_train_data_report(input_file, report_file)
%TCN_WRITE_TRAIN_DATA_REPORT 从已有 TCN 训练母集重建 Markdown 自检报告。
%
% 功能说明：
%   读取 TCN_gen_train_data.m 生成的 data/tcn/TCN_train_data_full.mat，
%   重新统计 run 数、样本数、主标签、转弯标签、辅助扰动标签和动态窗口
%   覆盖情况，并写出报告。该函数只读已有 mat 文件，不运行 Simulink，
%   适合报告被 smoke 测试覆盖或需要快速复核数据分布时使用。
%
% 输入：
%   input_file  : 可选，训练母集 mat 文件。默认
%                 data/tcn/TCN_train_data_full.mat。
%   report_file : 可选，输出 Markdown 报告路径。默认 full 数据集写入
%                 data/tcn/TCN_train_data_report.md，其它文件名写入
%                 <输入文件名>_report.md。
%
% 输出：
%   report.input_file  : 实际读取的数据集路径。
%   report.report_file : 实际写出的报告路径。
%   report.stats       : 标签分布、事件覆盖和路径列表等统计信息。
%
% 使用示例：
%   init_project;
%   TCN_write_train_data_report();

if nargin < 1 || isempty(input_file)
    input_file = fullfile(project_root(), 'data', 'tcn', 'TCN_train_data_full.mat');
end
if nargin < 2 || isempty(report_file)
    [folder, name] = fileparts(input_file);
    if strcmp(name, 'TCN_train_data_full')
        report_file = fullfile(folder, 'TCN_train_data_report.md');
    else
        report_file = fullfile(folder, sprintf('%s_report.md', name));
    end
end

S = load(input_file, 'data');
if ~isfield(S, 'data') || ~isfield(S.data, 'runs')
    error('TCN_write_train_data_report:InvalidDataset', ...
        'Input file does not contain data.runs: %s', input_file);
end
data = S.data;

stats = local_collect_stats(data);
local_write_report(report_file, input_file, data, stats);

report = struct();
report.input_file = input_file;
report.report_file = report_file;
report.stats = stats;

fprintf('[TCN] Report rebuilt: %s\n', report_file);
fprintf('[TCN] Runs=%d, samples=%d, slip=%.4f, stall=%.4f, load=%.4f\n', ...
    stats.valid_runs, stats.total_samples, stats.slip_ratio, ...
    stats.stall_ratio, stats.load_change_ratio);
end

function stats = local_collect_stats(data)
stats = struct();
stats.valid_runs = numel(data.runs);
stats.failed_runs = 0;
if isfield(data, 'meta') && isfield(data.meta, 'self_check') ...
        && isfield(data.meta.self_check, 'failed_runs')
    stats.failed_runs = data.meta.self_check.failed_runs;
end
stats.total_samples = 0;
stats.main_counts = zeros(1, 3);
stats.turn_counts = zeros(1, 3);
stats.slip_count = 0;
stats.stall_count = 0;
stats.load_change_count = 0;
stats.slip_run_count = 0;
stats.stall_run_count = 0;
stats.load_change_run_count = 0;
stats.runs_with_transition_windows = 0;
stats.dynamic_window_hits = 0;
stats.path_names = {};

for i = 1:numel(data.runs)
    run = data.runs(i);
    N = numel(run.t);
    stats.total_samples = stats.total_samples + N;
    for lbl = 1:3
        stats.main_counts(lbl) = stats.main_counts(lbl) + sum(run.label_main == lbl);
    end
    stats.turn_counts(1) = stats.turn_counts(1) + sum(run.label_turn == -1);
    stats.turn_counts(2) = stats.turn_counts(2) + sum(run.label_turn == 0);
    stats.turn_counts(3) = stats.turn_counts(3) + sum(run.label_turn == 1);
    stats.slip_count = stats.slip_count + sum(run.label_slip == 1);
    stats.stall_count = stats.stall_count + sum(run.label_stall == 1);
    stats.load_change_count = stats.load_change_count + sum(run.label_load_change == 1);
    stats.slip_run_count = stats.slip_run_count + double(any(run.label_slip == 1));
    stats.stall_run_count = stats.stall_run_count + double(any(run.label_stall == 1));
    stats.load_change_run_count = stats.load_change_run_count + double(any(run.label_load_change == 1));
    stats.path_names{end+1, 1} = run.scene; %#ok<AGROW>

    if isfield(run, 'meta') && isfield(run.meta, 'dynamic_windows') && ~isempty(run.meta.dynamic_windows)
        dw = run.meta.dynamic_windows;
        stats.runs_with_transition_windows = stats.runs_with_transition_windows + 1;
        for j = 1:size(dw, 1)
            m = run.t >= dw(j, 1) & run.t <= dw(j, 2);
            if nnz(m) >= 50
                stats.dynamic_window_hits = stats.dynamic_window_hits + 1;
            end
        end
    end
end

if stats.total_samples > 0
    stats.main_ratio = stats.main_counts / stats.total_samples;
    stats.turn_ratio = stats.turn_counts / stats.total_samples;
    stats.slip_ratio = stats.slip_count / stats.total_samples;
    stats.stall_ratio = stats.stall_count / stats.total_samples;
    stats.load_change_ratio = stats.load_change_count / stats.total_samples;
else
    stats.main_ratio = [NaN NaN NaN];
    stats.turn_ratio = [NaN NaN NaN];
    stats.slip_ratio = NaN;
    stats.stall_ratio = NaN;
    stats.load_change_ratio = NaN;
end
stats.unique_paths = unique(stats.path_names);
end

function local_write_report(report_file, input_file, data, stats)
fid = fopen(report_file, 'w');
if fid < 0
    error('TCN_write_train_data_report:CannotWrite', 'Cannot write report: %s', report_file);
end
cleanup = onCleanup(@() fclose(fid));

model_name = 'unknown';
if isfield(data, 'meta') && isfield(data.meta, 'model_name')
    model_name = data.meta.model_name;
end

fprintf(fid, '# TCN Training Data Generation Report\n\n');
fprintf(fid, '- Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '- Output: `%s`\n', input_file);
fprintf(fid, '- Model: `%s`\n', model_name);
fprintf(fid, '- Valid runs: %d\n', stats.valid_runs);
fprintf(fid, '- Failed runs: %d\n', stats.failed_runs);
fprintf(fid, '- Total samples: %d\n\n', stats.total_samples);

fprintf(fid, '## Label Distribution\n\n');
fprintf(fid, '| label | count | ratio |\n|---|---:|---:|\n');
fprintf(fid, '| flat | %d | %.4f |\n', stats.main_counts(1), stats.main_ratio(1));
fprintf(fid, '| stall | %d | %.4f |\n', stats.main_counts(2), stats.main_ratio(2));
fprintf(fid, '| slope | %d | %.4f |\n', stats.main_counts(3), stats.main_ratio(3));
fprintf(fid, '| turn right | %d | %.4f |\n', stats.turn_counts(1), stats.turn_ratio(1));
fprintf(fid, '| turn straight | %d | %.4f |\n', stats.turn_counts(2), stats.turn_ratio(2));
fprintf(fid, '| turn left | %d | %.4f |\n', stats.turn_counts(3), stats.turn_ratio(3));
fprintf(fid, '| slip aux | %d | %.4f |\n', stats.slip_count, stats.slip_ratio);
fprintf(fid, '| stall aux | %d | %.4f |\n', stats.stall_count, stats.stall_ratio);
fprintf(fid, '| load_change aux | %d | %.4f |\n\n', stats.load_change_count, stats.load_change_ratio);

fprintf(fid, '## Transition Coverage\n\n');
fprintf(fid, '- Runs with dynamic windows: %d\n', stats.runs_with_transition_windows);
fprintf(fid, '- Dynamic window hits: %d\n\n', stats.dynamic_window_hits);

fprintf(fid, '## Event Coverage\n\n');
fprintf(fid, '- Runs with slip labels: %d\n', stats.slip_run_count);
fprintf(fid, '- Runs with stall labels: %d\n', stats.stall_run_count);
fprintf(fid, '- Runs with load-change labels: %d\n\n', stats.load_change_run_count);

fprintf(fid, '## Paths\n\n');
for i = 1:numel(stats.unique_paths)
    fprintf(fid, '- `%s`\n', stats.unique_paths{i});
end
end
