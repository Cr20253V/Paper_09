function result=node53_v7_save_debug(out_dir)
%NODE53_V7_SAVE_DEBUG Persist truth-free V7 runtime diagnostics.
T=node53_v7_debug_buffer('get'); if exist(out_dir,'dir')~=7; mkdir(out_dir); end
csv_file=fullfile(out_dir,'node53_v7_runtime_debug.csv'); mat_file=fullfile(out_dir,'node53_v7_runtime_debug.mat');
writetable(T,csv_file); save(mat_file,'T','-v7.3'); result=struct('row_count',height(T),'csv_file',csv_file,'mat_file',mat_file);
end
