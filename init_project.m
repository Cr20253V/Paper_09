function init_project()
% =============================
% 文件名：init_project.m
% 路径：S-Function_14/init_project.m
% 版本号：V1.0
% 最后修改时间：2025-12-10
% 作者：Auto-generated
% 功能描述：
%   初始化 LPV-MPC 项目运行环境：
%     1) 调用 project_root() 获取根目录
%     2) 将 src 及其子目录递归加入 MATLAB 路径
%     3) 将 simulink 目录加入路径，便于加载模型
% =============================

root = project_root();
addpath(root);
addpath(genpath(fullfile(root, 'src')));
addpath(fullfile(root, 'simulink'));

node20_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '20_light_medium_disturbance_validation_v2');
if exist(node20_root, 'dir') == 7
    addpath(node20_root);
end

node21_root = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '21_catastrophic_gate_audit');
if exist(node21_root, 'dir') == 7
    addpath(node21_root);
end

fprintf('[init_project] Root: %s\n', root);
end
