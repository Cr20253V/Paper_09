function result=node53_save_debug(out_dir)
T=node53_debug_buffer('get');if exist(out_dir,'dir')~=7;mkdir(out_dir);end;csv_file=fullfile(out_dir,'node53_runtime_debug.csv');mat_file=fullfile(out_dir,'node53_runtime_debug.mat');writetable(T,csv_file);save(mat_file,'T','-v7.3');result=struct('row_count',height(T),'csv_file',csv_file,'mat_file',mat_file);
end
