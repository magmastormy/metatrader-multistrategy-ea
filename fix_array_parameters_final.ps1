# Final array parameter fix
$files = Get-ChildItem -Path "." -Include "*.mqh","*.mq5" -Recurse -File

Write-Host "Fixing array parameters in $($files.Count) files..."

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $original = $content
    
    # Fix method declarations
    $content = $content -replace 'void LogEnsembleDecision\(([^)]*strategies\[\])', 'void LogEnsembleDecision($&strategies[]'
    $content = $content -replace 'void GenerateStrategyReport\(([^)]*strategies\[\])', 'void GenerateStrategyReport($&strategies[]'
    $content = $content -replace 'void LogMultiTimeframeAnalysis\(([^)]*strategies\[\])', 'void LogMultiTimeframeAnalysis($&strategies[]'
    $content = $content -replace 'void LogStrategySelection\(([^)]*selectedStrategies\[\])', 'void LogStrategySelection($&selectedStrategies[]'
    
    # Fix method definitions
    $content = $content -replace 'void CSignalDiagnostics::LogEnsembleDecision\(([^)]*strategies\[\])', 'void CSignalDiagnostics::LogEnsembleDecision($&strategies[]'
    $content = $content -replace 'void CSignalDiagnostics::GenerateStrategyReport\(([^)]*strategies\[\])', 'void CSignalDiagnostics::GenerateStrategyReport($&strategies[]'
    $content = $content -replace 'void CSignalDiagnostics::LogMultiTimeframeAnalysis\(([^)]*strategies\[\])', 'void CSignalDiagnostics::LogMultiTimeframeAnalysis($&strategies[]'
    $content = $content -replace 'void CSignalDiagnostics::LogStrategySelection\(([^)]*selectedStrategies\[\])', 'void CSignalDiagnostics::LogStrategySelection($&selectedStrategies[]'
    
    # Fix TrendEngine methods
    $content = $content -replace 'bool CalculateMAs\(([^)]*ma_fast\[\])', 'bool CalculateMAs($&ma_fast[]'
    $content = $content -replace 'double GetTrendStrength\(([^)]*ma_fast\[\])', 'double GetTrendStrength($&ma_fast[]'
    $content = $content -replace 'double CalculateAngle\(([^)]*ma\[\])', 'double CalculateAngle($&ma[]'
    
    # Fix TrendEngine method definitions
    $content = $content -replace 'TrendState CTrendEngine::CalculateMAs\(([^)]*ma_fast\[\])', 'TrendState CTrendEngine::CalculateMAs($&ma_fast[]'
    $content = $content -replace 'double CTrendEngine::GetTrendStrength\(([^)]*ma_fast\[\])', 'double CTrendEngine::GetTrendStrength($&ma_fast[]'
    $content = $content -replace 'double CTrendEngine::CalculateAngle\(([^)]*ma\[\])', 'double CTrendEngine::CalculateAngle($&ma[]'
    
    # Fix Pipeline methods
    $content = $content -replace 'ProcessMTFSignals\(([^)]*strategies\[\])', 'ProcessMTFSignals($&strategies[]'
    $content = $content -replace 'AutoRegisterStrategies\(([^)]*enabledFlags\[\])', 'AutoRegisterStrategies($&enabledFlags[]'
    
    # Fix Pipeline method definitions
    $content = $content -replace 'CUnifiedSignalPipeline::ProcessMTFSignals\(([^)]*strategies\[\])', 'CUnifiedSignalPipeline::ProcessMTFSignals($&strategies[]'
    $content = $content -replace 'CEnterpriseStrategyManager::AutoRegisterStrategies\(([^)]*enabledFlags\[\])', 'CEnterpriseStrategyManager::AutoRegisterStrategies($&enabledFlags[]'
    
    if($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed arrays in: $($file.Name)"
    }
}

Write-Host "Array parameter fix complete!"
