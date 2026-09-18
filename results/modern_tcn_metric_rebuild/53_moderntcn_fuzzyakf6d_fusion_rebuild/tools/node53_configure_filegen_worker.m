function previous = node53_configure_filegen_worker(root, worker_id)
%NODE53_CONFIGURE_FILEGEN_WORKER Give each external MATLAB worker private caches.
if nargin < 1 || isempty(root); root = project_root(); end
if nargin < 2 || isempty(worker_id); worker_id = 'serial'; end
worker_id = regexprep(char(string(worker_id)), '[^A-Za-z0-9_-]', '_');
if isempty(worker_id); worker_id = 'serial'; end
node = fullfile(root, 'results', 'modern_tcn_metric_rebuild', ...
    '53_moderntcn_fuzzyakf6d_fusion_rebuild');
node_for_filegen = local_node53_short_mount(node);
cache = fullfile(node_for_filegen, 'cache', 'w', worker_id, 's');
code = fullfile(node_for_filegen, 'cache', 'w', worker_id, 'c');
if exist(cache, 'dir') ~= 7; mkdir(cache); end
if exist(code, 'dir') ~= 7; mkdir(code); end
previous = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', cache, 'CodeGenFolder', code, ...
    'createDir', true);
assignin('base', 'node53_worker_id', worker_id);
assignin('base', 'node53_worker_filegen_cache', cache);
assignin('base', 'node53_worker_filegen_codegen', code);
end

function node_short = local_node53_short_mount(node)
% Keep Simulink-generated internal paths short while still writing physically
% inside Node53.  This avoids intermittent fl:filesystem:SystemError when
% several external MATLAB processes compile the same model tree in parallel.
node_short = node;
if ~ispc; return; end
node_abs = char(java.io.File(node).getCanonicalPath());
drives = {'N:','M:','L:','K:'};
for i = 1:numel(drives)
    drive = drives{i};
    if local_subst_points_to(drive, node_abs)
        node_short = [drive filesep];
        return;
    end
end
for i = 1:numel(drives)
    drive = drives{i};
    if local_drive_is_free(drive)
        cmd = sprintf('subst %s "%s"', drive, node_abs);
        [status, ~] = system(cmd);
        if status == 0 || local_subst_points_to(drive, node_abs)
            node_short = [drive filesep];
            return;
        end
    end
end
end

function tf = local_drive_is_free(drive)
tf = exist([drive filesep], 'dir') ~= 7 && ~local_subst_has_drive(drive);
end

function tf = local_subst_has_drive(drive)
[~, out] = system('subst');
tf = contains(upper(out), upper([drive filesep]));
end

function tf = local_subst_points_to(drive, node_abs)
[~, out] = system('subst');
lines = regexp(out, '\r?\n', 'split');
needle = upper([drive filesep ': => ']);
tf = false;
for k = 1:numel(lines)
    line = strtrim(lines{k});
    if startsWith(upper(line), needle)
        rhs = strtrim(extractAfter(line, '=>'));
        try
            rhs = char(java.io.File(char(rhs)).getCanonicalPath());
        catch
            rhs = char(rhs);
        end
        tf = strcmpi(rhs, node_abs);
        return;
    end
end
end
