function root = project_root()
% =============================
% 文件名：project_root.m
% 路径：S-Function_14/project_root.m
% 版本号：V1.0
% 最后修改时间：2025-12-10
% 作者：Auto-generated
% 功能描述：
%   返回项目根目录的绝对路径，供所有脚本构建相对路径。
%   该函数应位于项目根目录，不随其他脚本迁移。
% =============================

persistent cached_root
if isempty(cached_root) || ~isfolder(cached_root)
    [cached_root, ~] = fileparts(mfilename('fullpath'));
end
root = cached_root;
end
