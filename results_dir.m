function dir_out = results_dir(subdir)
% =============================
% 文件名：results_dir.m
% 路径：S-Function_14/results_dir.m
% 版本号：V1.0
% 最后修改时间：2025-12-10
% 作者：Auto-generated
% 功能描述：
%   构建结果输出目录的绝对路径，并在不存在时自动创建。
%   示例：out_dir = results_dir('gru/performance_offline');
% =============================

if nargin < 1 || isempty(subdir)
    subdir = '';
end

root = project_root();
dir_out = fullfile(root, 'results', subdir);

if ~exist(dir_out, 'dir')
    mkdir(dir_out);
end
end
