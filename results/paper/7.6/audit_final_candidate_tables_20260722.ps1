[CmdletBinding()]
param(
    [string]$Candidate = "results/paper/Latex/paper_v4_final_candidate.tex"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
Set-Location $root

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ([string]$Actual -cne [string]$Expected) {
        throw "$Name mismatch: actual='$Actual', expected='$Expected'"
    }
    [pscustomobject]@{ Check = $Name; Actual = $Actual; Expected = $Expected; Status = "PASS" }
}

function Assert-Near {
    param([string]$Name, [double]$Actual, [double]$Expected, [double]$Tolerance = 1e-10)
    if ([math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw "$Name mismatch: actual=$Actual, expected=$Expected, tolerance=$Tolerance"
    }
    [pscustomobject]@{ Check = $Name; Actual = $Actual; Expected = $Expected; Status = "PASS" }
}

function Get-Row {
    param($Rows, [hashtable]$Where)
    $matched = @($Rows | Where-Object {
        $row = $_
        -not @($Where.GetEnumerator() | Where-Object { [string]$row.($_.Key) -cne [string]$_.Value })
    })
    if ($matched.Count -ne 1) {
        throw "Expected one row for $($Where | ConvertTo-Json -Compress), found $($matched.Count)"
    }
    $matched[0]
}

$checks = [System.Collections.Generic.List[object]]::new()

$sourceHashes = [ordered]@{
    "results/paper/Latex/paper_v3 _1.tex" = "DCD150E1076631D7F515FB6AD2D0E9A016A7C25A0C00B26786B878375BE54A21"
    "results/paper/7.6/A0_论文最终统一实验配置_20260715.json" = "1FDB75A7EFFBC2DA5D2217DF415004A5819EB577C6FDC275AD0F94520860C911"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/01_A1_algorithm_comparison/03_offline/offline_method_summary.csv" = "C054E679471D4559E7F05D6396B9C22C7CF2F65D66FCD13DB0D8F64438E443F0"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/05_A5_statistical_audit/04_phase2/paired_effects.csv" = "6E8FAC046C930DC083B154405530EA025B4E315B5E2338B8AC9FD71B983B9AE4"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/03_A3_slope_scheduling_necessity/04_summary/bootstrap_ci_results.csv" = "B33725731C4E9876B2CF86D8DE0A42B2AACEC1E703A26616EB33E446A9ABF9DE"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/04_A4_controller_comparison/03_statistics/controller_summary.csv" = "1426CDD6D573E25950EFC475DCF9906E7D1929F16A4723EEF698DA66C099E40A"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/04_A4_controller_comparison/03_statistics/path_summary.csv" = "B77309838408FF0B8F99E751AC56548743BF312D7EEE6F7C8B20AC3EB6EB61F8"
    "results/modern_tcn_metric_rebuild/40_legal_imu_uncertainty_fusion/05_summaries/observer_development_observer_summary.json" = "4792AD87EF1F6039AB6337CBDCDA282EB274E45F4352CA4229AD268109AD970B"
    "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3/04_summaries/innovation_development_summary.json" = "E4DA86AF6D048E9B9EC0FF21A8720E7D00C620342327BA993ABB668F02D7F482"
    "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark/05_A5_statistical_audit/04_phase2/runtime_summary.csv" = "5AE5D7A8BCB906517D2BF4542C490A3662E590D550AC6D4D254FCEEBAF7FE7F3"
}

foreach ($entry in $sourceHashes.GetEnumerator()) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    $checks.Add((Assert-Equal "SHA256 $($entry.Key)" $actual $entry.Value))
}

$a0 = Get-Content -Raw -LiteralPath "results/paper/7.6/A0_论文最终统一实验配置_20260715.json" | ConvertFrom-Json
$checks.Add((Assert-Equal "A0 status" $a0.status "FROZEN_FOR_EXECUTION"))
$checks.Add((Assert-Equal "A0 total runs" ($a0.dataset.train_runs + $a0.dataset.validation_runs + $a0.dataset.test_runs) 102))
$checks.Add((Assert-Equal "A0 run split" "$($a0.dataset.train_runs)/$($a0.dataset.validation_runs)/$($a0.dataset.test_runs)" "71/15/16"))
$checks.Add((Assert-Equal "A0 sequence length" $a0.dataset.sequence_length_steps 128))
$checks.Add((Assert-Equal "A0 delta input dim" $a0.input_representations.delta_bank_124.augmented_input_dim 88))
$checks.Add((Assert-Equal "A0 sample period" $a0.lpv_mpc.sample_time_s 0.01))
$checks.Add((Assert-Equal "A0 horizons" "$($a0.lpv_mpc.prediction_horizon_steps)/$($a0.lpv_mpc.control_horizon_steps)" "150/30"))

$base = "results/modern_tcn_metric_rebuild/39_paper_final_frozen_benchmark"
$offline = Import-Csv "$base/01_A1_algorithm_comparison/03_offline/offline_method_summary.csv"
$offlineExpected = @(
    @("modern_tcn_delta_bank_124", "theta_mae_deg", 0.5988841710129981),
    @("modern_tcn_delta_bank_124", "theta_abs_le_10_p95_abs_err_deg", 1.6777749854958954),
    @("modern_tcn_22d", "theta_mae_deg", 0.653002856522528),
    @("modern_tcn_22d", "theta_abs_le_10_p95_abs_err_deg", 1.806264682254022),
    @("gru_22d", "theta_mae_deg", 0.885828851812979),
    @("gru_22d", "theta_abs_le_10_p95_abs_err_deg", 2.2594999552830504),
    @("tcn_22d", "theta_mae_deg", 0.9153691292422238),
    @("tcn_22d", "theta_abs_le_10_p95_abs_err_deg", 2.6357961635340903)
)
foreach ($e in $offlineExpected) {
    $row = Get-Row $offline @{ method_id = $e[0]; metric = $e[1] }
    $checks.Add((Assert-Near "A1 offline $($e[0]) $($e[1])" ([double]$row.mean) $e[2]))
}

$paired = Import-Csv "$base/05_A5_statistical_audit/04_phase2/paired_effects.csv"
$pairedExpected = @(
    @("A1_OFFLINE_DB124_VS_M22", "theta_mae_deg", 0.05411868550953004, 0.006084589527284233, 0.10180335348874511),
    @("A1_OFFLINE_DB124_VS_M22", "theta_edge_p95_abs_err", 0.42607667944730243, 0.1851698914650369, 0.7098668101868537),
    @("A1_CL_DB124_VS_M22", "ey_rmse", 0.03886813787244639, -0.0065379714954434814, 0.15744370039845706),
    @("A1_CL_DB124_VS_M22", "epsi_rmse", 0.008575948720245441, -0.0025636313403986474, 0.026550606793353117),
    @("A1_CL_DB124_VS_M22", "j_du", 15.91215566910804, 1.63835976135401, 55.89903332228697),
    @("A1_CL_DB124_VS_GRU", "ey_rmse", 1.8746526868120283, 0.6576251709686666, 3.5073376096313478),
    @("A1_CL_DB124_VS_GRU", "epsi_rmse", 0.18153226705430942, 0.08327291097339966, 0.30548621913761387),
    @("A1_CL_DB124_VS_GRU", "j_du", 290.5245459952159, 158.5906057226073, 445.7484026160248),
    @("A1_CL_DB124_VS_TCN", "ey_rmse", 0.8066703689793592, 0.3722470984763312, 1.2958043255794627),
    @("A1_CL_DB124_VS_TCN", "epsi_rmse", 0.15181350066132968, 0.07167647630020657, 0.24455551015678617),
    @("A1_CL_DB124_VS_TCN", "j_du", 126.07380948852031, 69.85963270660119, 191.9652103378061)
)
foreach ($e in $pairedExpected) {
    $row = Get-Row $paired @{ contrast_id = $e[0]; metric = $e[1] }
    $checks.Add((Assert-Near "A5 effect $($e[0]) $($e[1])" ([double]$row.mean_effect) $e[2]))
    $checks.Add((Assert-Near "A5 CI low $($e[0]) $($e[1])" ([double]$row.ci95_low) $e[3]))
    $checks.Add((Assert-Near "A5 CI high $($e[0]) $($e[1])" ([double]$row.ci95_high) $e[4]))
}

$a3 = Import-Csv "$base/03_A3_slope_scheduling_necessity/04_summary/bootstrap_ci_results.csv"
$a3Expected = @(
    @("A3_ORACLE_VS_ZS", "ey_rmse", 1.4679837236765056, 0.11715140655630914, 3.746816090827332),
    @("A3_ORACLE_VS_ZS", "epsi_rmse", 0.33064914196748224, 0.050652912886204604, 0.8000447207231401),
    @("A3_ORACLE_VS_ZS", "j_du", 695.5871020059634, 116.40830243921, 1339.4542529553248),
    @("A3_IMU_VS_ZS", "ey_rmse", 0.0690628440576017, 0.006631593343729518, 0.17809962037748137),
    @("A3_IMU_VS_ZS", "epsi_rmse", -0.056118434625350454, -0.19831304920997175, 0.025024147652474505),
    @("A3_IMU_VS_ZS", "j_du", -7.22470042357423, -475.1041237874371, 439.4677513776466)
)
foreach ($e in $a3Expected) {
    $row = Get-Row $a3 @{ contrast_id = $e[0]; metric = $e[1] }
    $checks.Add((Assert-Near "A3 effect $($e[0]) $($e[1])" ([double]$row.estimate) $e[2]))
    $checks.Add((Assert-Near "A3 CI low $($e[0]) $($e[1])" ([double]$row.ci95_low) $e[3]))
    $checks.Add((Assert-Near "A3 CI high $($e[0]) $($e[1])" ([double]$row.ci95_high) $e[4]))
}

$a4Controllers = Import-Csv "$base/04_A4_controller_comparison/03_statistics/controller_summary.csv"
$a4Expected = @(
    @("ZS_LPV_MPC", 6, 1.4804637878523914, 0.34204178995643636, 9.888606673125452, 696.0139381286762, 0.3851385296207526),
    @("IMU_LPV_MPC", 6, 1.4114009437947894, 0.3981602245817866, 6.748557323885303, 703.2386385522504, 0.36175134735949593),
    @("MTCN_LPV_MPC", 60, 0.026348949056145946, 0.022161334247498457, 0.505883208833946, 0.9305307636811345, 0.05867544860271538),
    @("Fusion_LPV_MPC", 60, 0.023632938419467876, 0.020038468667678035, 0.47683723155475527, 0.7788492097027405, 0.056172777768557745),
    @("Oracle_LPV_MPC", 6, 0.012480064175885867, 0.011392647988954148, 0.25546470382162534, 0.42683612271268595, 0.05155935356023835)
)
foreach ($e in $a4Expected) {
    $row = Get-Row $a4Controllers @{ controller_id = $e[0] }
    $checks.Add((Assert-Equal "A4 cases $($e[0])" $row.n_cases $e[1]))
    foreach ($j in 2..6) {
        $field = @("", "", "ey_rmse_mean", "epsi_rmse_mean", "xy_rmse_mean", "j_du_mean", "omega_cmd_rms_mean")[$j]
        $checks.Add((Assert-Near "A4 $field $($e[0])" ([double]$row.$field) $e[$j]))
    }
}

$a4Paired = Import-Csv "$base/04_A4_controller_comparison/03_statistics/paired_effects.csv"
$tieExpected = @{ ey_rmse = "27/17/16"; epsi_rmse = "32/12/16"; j_du = "24/20/16" }
foreach ($metric in $tieExpected.Keys) {
    $row = Get-Row $a4Paired @{ contrast_id = "Fusion_vs_MTCN"; metric = $metric }
    $actual = "$($row.improved_case_count)/$($row.degraded_case_count)/$($row.tie_case_count)"
    $checks.Add((Assert-Equal "A4 direction counts $metric" $actual $tieExpected[$metric]))
}

$observer = Get-Content -Raw "results/modern_tcn_metric_rebuild/40_legal_imu_uncertainty_fusion/05_summaries/observer_development_observer_summary.json" | ConvertFrom-Json
$checks.Add((Assert-Equal "Node40 observer status" $observer.status "PASS_OBSERVER_QUALIFICATION"))
$checks.Add((Assert-Near "Node40 observer MAE" $observer.mean_mae_deg 0.1998545532401204))

$fusion = Get-Content -Raw "results/modern_tcn_metric_rebuild/42_fusion_guard_repair_and_innovation3/04_summaries/innovation_development_summary.json" | ConvertFrom-Json
$checks.Add((Assert-Equal "Node42 development status" $fusion.status "FAIL_NODE42_INNOVATION_DEVELOPMENT"))
$checks.Add((Assert-Near "Node42 mean J ratio" $fusion.mean_J 0.9540564463729228))
$checks.Add((Assert-Near "Node42 grade ratio" $fusion.mean_theta_ratio 0.8359705701893262))
$neutral = 1.0 - $fusion.active_improve_fraction - $fusion.active_degrade_fraction
$checks.Add((Assert-Near "Node42 active neutral fraction" $neutral 0.2907389518491466))

$runtime = Import-Csv "$base/05_A5_statistical_audit/04_phase2/runtime_summary.csv"
$onnxDelta = Get-Row $runtime @{ component_id = "ONNXRUNTIME_CPU_SAME_BACKEND::core_inference__modern_tcn_delta_bank_124" }
$checks.Add((Assert-Near "ONNX delta p95" ([double]$onnxDelta.p95_ms) 0.4038))
$matlabDeltaRows = @($runtime | Where-Object { $_.component_id -eq "MATLAB_NATIVE_CORE_AND_E2E::modern_tcn_delta_bank_124" })
$checks.Add((Assert-Equal "MATLAB delta duplicate-scope row count" $matlabDeltaRows.Count 2))
$checks.Add((Assert-Near "MATLAB delta core p95 by frozen row order" ([double]$matlabDeltaRows[0].p95_ms) 12.1382))
$checks.Add((Assert-Near "MATLAB delta end-to-end p95 by frozen row order" ([double]$matlabDeltaRows[1].p95_ms) 13.30685))
$fullCycle = Get-Row $runtime @{ component_id = "MATLAB_NATIVE_SUPPLEMENTAL::slope_estimation_mpc" }
$checks.Add((Assert-Near "MATLAB full-cycle p95" ([double]$fullCycle.p95_ms) 52.20685))

$tex = Get-Content -Raw -LiteralPath $Candidate
$requiredLabels = @(
    "tab:frozen_experimental_configuration", "tab:evaluation_protocol",
    "tab:slope_necessity_effects", "tab:estimator_and_delta_results", "tab:observer_fusion_evidence",
    "tab:five_source_closed_loop", "tab:fusion_route_stratification", "tab:runtime_scope"
)
foreach ($label in $requiredLabels) {
    $count = ([regex]::Matches($tex, [regex]::Escape("\label{$label}"))).Count
    $checks.Add((Assert-Equal "Unique table label $label" $count 1))
}
$removedComparisonLabelCount = ([regex]::Matches($tex, [regex]::Escape("\label{tab:comparison_protocol}"))).Count
$checks.Add((Assert-Equal "Removed table label tab:comparison_protocol" $removedComparisonLabelCount 0))
$requiredVisualLabels = @(
    "alg:dataset_construction", "fig:closed_loop_route_set", "fig:slope_necessity_effects",
    "fig:offline_estimator_distribution", "fig:imu_observer_trace", "fig:fusion_case_distribution",
    "fig:fusion_qualitative_trace", "fig:five_controller_qualitative"
)
foreach ($label in $requiredVisualLabels) {
    $count = ([regex]::Matches($tex, [regex]::Escape("\label{$label}"))).Count
    $checks.Add((Assert-Equal "Unique visual label $label" $count 1))
}
$checks.Add((Assert-Equal "TODO-FIG-FINAL count after figure insertion" ([regex]::Matches($tex, "TODO-FIG-FINAL")).Count 0))

$checks | Format-Table -AutoSize
"AUDIT_PASS: $($checks.Count) checks"
