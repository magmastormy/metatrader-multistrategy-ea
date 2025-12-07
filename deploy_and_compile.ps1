# Deploy and Compile - Combined Script
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " EA DEPLOYMENT & COMPILATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Sync files
Write-Host "[1/2] Syncing files to MT5..." -ForegroundColor Yellow
& "$PSScriptRoot\sync_to_mt5.ps1"
if($LASTEXITCODE -ge 8) {
    Write-Host "ERROR: Sync failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Compile
Write-Host "[2/2] Compiling EA..." -ForegroundColor Yellow
& "$PSScriptRoot\compile_now.ps1"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
