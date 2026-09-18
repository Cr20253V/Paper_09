function result=node53_run_parity(root)
%NODE53_RUN_PARITY Run MATLAB copy on the fixed Node53 fixture.
if nargin<1||isempty(root);root=project_root();end
node=fullfile(root,'results','modern_tcn_metric_rebuild','53_moderntcn_fuzzyakf6d_fusion_rebuild');
addpath(fullfile(node,'tools'));
cfg=jsondecode(fileread(fullfile(node,'02_fuzzyakf6','R2_06_FuzzyAKF6D.json')));
X=readmatrix(fullfile(node,'cache','parity_input.csv'));[s,~]=node53_fuzzyakf6_estimator('init',cfg,[]);
n=size(X,1);Y=zeros(n,11);
for k=1:n
    [s,o]=node53_fuzzyakf6_estimator('update',s,X(k,:).');
    Y(k,:)=[o.theta_imu,o.theta_acc,o.theta_pred,o.accel_weight,o.accel_norm,o.innovation,o.nis,o.min_covariance_eigenvalue,double(o.observer_valid),o.gyro_energy,o.gyro_vibration_feature];
end
names={'theta_imu','theta_acc','theta_pred','accel_weight','accel_norm','innovation','nis','min_covariance_eigenvalue','observer_valid','gyro_energy','gyro_vibration_feature'};
T=array2table(Y,'VariableNames',names);writetable(T,fullfile(node,'cache','parity_matlab.csv'));
result=struct('status','PASS_NODE53_MATLAB_PARITY_RUN','sample_count',n,'output_file',fullfile(node,'cache','parity_matlab.csv'));
end
