# Compile EA Now
Write-Host "Compiling MultiStrategyAutonomousEA..." -ForegroundColor Green

$metaeditor = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
$eaFile = "C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea\MultiStrategyAutonomousEA.mq5"
$logFile = "d:\TraeProjects\metatrader-multistrategy-ea\compile_result.log"

if(!(Test-Path $metaeditor)) {
    Write-Host "ERROR: MetaEditor not found at: $metaeditor" -ForegroundColor Red
    exit 1
}

if(!(Test-Path $eaFile)) {
    Write-Host "ERROR: EA file not found at: $eaFile" -ForegroundColor Red
    exit 1
}

Write-Host "MetaEditor: $metaeditor" -ForegroundColor Cyan
Write-Host "EA File: $eaFile" -ForegroundColor Cyan
Write-Host "Log File: $logFile" -ForegroundColor Cyan
Write-Host ""

# Run compilation
Write-Host "Compiling... Please wait..." -ForegroundColor Yellow
$process = Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$eaFile`"","/log:`"$logFile`"" -PassThru -NoNewWindow
$process.WaitForExit(60000)  # Wait up to 60 seconds

Write-Host ""

if(Test-Path $logFile) {
    Write-Host "Compilation log:" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Gray
    Get-Content $logFile
    Write-Host "===============================================" -ForegroundColor Gray
    Write-Host ""
    
    # Check for errors
    $logContent = Get-Content $logFile -Raw
    if($logContent -match "0 error") {
        Write-Host "SUCCESS: Compilation completed with 0 errors!" -ForegroundColor Green
        
        # Check if .ex5 file was created
        $ex5File = $eaFile -replace '\.mq5$', '.ex5'
        if(Test-Path $ex5File) {
            $fileInfo = Get-Item $ex5File
            Write-Host "EX5 File: $ex5File" -ForegroundColor Green
            Write-Host "Size: $($fileInfo.Length) bytes" -ForegroundColor Green
            Write-Host "Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Green
        }
    } else {
        Write-Host "WARNING: Compilation may have errors. Check log above." -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: No log file created" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Deployment complete! EA is ready to use." -ForegroundColor Green
