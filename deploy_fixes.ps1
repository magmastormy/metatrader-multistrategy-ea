# Deploy EA Fixes to MT5
Write-Host "Deploying EA fixes to MetaTrader 5..." -ForegroundColor Green

$source = "d:\TraeProjects\metatrader-multistrategy-ea"
$target = "C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea"

# Create target directories if they don't exist
$dirs = @(
    "$target\Core\Pipeline",
    "$target\Core\Signals",
    "$target\Core\Visualization",
    "$target\Documentation"
)

foreach($dir in $dirs) {
    if(!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created: $dir" -ForegroundColor Yellow
    }
}

# Copy modified files
$files = @(
    "Core\Pipeline\UnifiedSignalPipeline.mqh",
    "Core\Signals\HedgingProtection.mqh",
    "MultiStrategyAutonomousEA.mq5",
    "Core\Visualization\ChartDrawingManager.mqh",
    "Core\Visualization\SMCStructureVisualizer.mqh",
    "Core\Visualization\OrderBlockVisualizer.mqh",
    "Documentation\FIX_SUMMARY_SILENCE_RESTORED.md"
)

Write-Host ""
Write-Host "Copying modified files..." -ForegroundColor Cyan

foreach($file in $files) {
    $src = Join-Path $source $file
    $dst = Join-Path $target $file
    
    if(Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $file (not found)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Compile EA in MetaEditor" -ForegroundColor Cyan
