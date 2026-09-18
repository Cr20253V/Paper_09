function score=node53_quality_score(model,o,g)
%NODE53_QUALITY_SCORE Maximum ECDF risk from runtime-only observables.
values=[1-double(o.accel_weight),abs(double(o.accel_norm)-double(g)),abs(double(o.innovation)),double(o.nis),double(o.gyro_vibration_feature)];
names={'one_minus_accel_weight','accel_norm_deviation','abs_innovation','nis','gyro_vibration_feature'};parts=zeros(1,5);
for k=1:5
    curve=model.(names{k});x=double(curve.values(:));p=double(curve.probabilities(:));[x,last]=unique(x,'last');p=p(last);
    if values(k)<x(1);parts(k)=0;elseif values(k)>x(end);parts(k)=1;elseif numel(x)==1;parts(k)=p(1);else;parts(k)=interp1(x,p,values(k),'linear');end
end
score=max(0,min(1,max(parts)));
end
