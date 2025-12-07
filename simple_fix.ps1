# Simple working fix
Write-Host "Applying simple fixes..."

# 1. Fix SignalDiagnostics array parameters
$file = "Core\Signals\SignalDiagnostics.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'const string strategies\[\]', 'const string &strategies[]'
    $content = $content -replace 'ENUM_TRADE_SIGNAL signals\[\]', 'ENUM_TRADE_SIGNAL &signals[]'
    $content = $content -replace 'const string selectedStrategies\[\]', 'const string &selectedStrategies[]'
    $content = $content -replace 'const double weights\[\]', 'const double &weights[]'
    $content = $content -replace 'const int success\[\]', 'const int &success[]'
    $content = $content -replace 'const int failures\[\]', 'const int &failures[]'
    $content = $content -replace 'const double avgConf\[\]', 'const double &avgConf[]'
    $content = $content -replace 'const double confidences\[\]', 'const double &confidences[]'
    $content = $content -replace 'const ENUM_TIMEFRAMES timeframes\[\]', 'const ENUM_TIMEFRAMES &timeframes[]'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed SignalDiagnostics"
}

# 2. Fix TrendEngine array parameters
$file = "Core\Engines\TrendEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'double ma_fast\[\]', 'double &ma_fast[]'
    $content = $content -replace 'double ma_medium\[\]', 'double &ma_medium[]'
    $content = $content -replace 'double ma_slow\[\]', 'double &ma_slow[]'
    $content = $content -replace 'double ma\[\]', 'double &ma[]'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed TrendEngine"
}

# 3. Fix Pipeline array parameters
$file = "Core\Pipeline\UnifiedSignalPipeline.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'IStrategy\* strategies\[\]', 'IStrategy* &strategies[]'
    $content = $content -replace 'ENUM_TIMEFRAMES timeframes\[\]', 'ENUM_TIMEFRAMES &timeframes[]'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed UnifiedSignalPipeline"
}

# 4. Fix EnterpriseStrategyManager array parameters
$file = "Core\Management\EnterpriseStrategyManager.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'bool enabledFlags\[\]', 'bool &enabledFlags[]'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed EnterpriseStrategyManager"
}

Write-Host "Simple fixes complete!"
