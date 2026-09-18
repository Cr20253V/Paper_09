function previous=node53_configure_filegen(root)
if nargin<1||isempty(root);root=project_root();end
node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');
cache=fullfile(node,'cache','simulink');code=fullfile(node,'cache','codegen');
if exist(cache,'dir')~=7;mkdir(cache);end;if exist(code,'dir')~=7;mkdir(code);end
previous=Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set','CacheFolder',cache,'CodeGenFolder',code,'createDir',true);
end
