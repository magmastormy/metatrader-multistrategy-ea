# Sync project to MetaTrader 5 directory
Write-Host "Syncing project to MetaTrader 5..." -ForegroundColor Green

$sourceDir = "D:\TraeProjects\metatrader-multistrategy-ea"
$targetDir = "C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea"

# Check if source exists
if(!(Test-Path $sourceDir)) {
    Write-Host "ERROR: Source directory not found: $sourceDir" -ForegroundColor Red
    exit 1
}

# Create target directory if it doesn't exist
if(!(Test-Path $targetDir)) {
    Write-Host "Creating target directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying files from:" -ForegroundColor Cyan
Write-Host "  $sourceDir" -ForegroundColor White
Write-Host "To:" -ForegroundColor Cyan
Write-Host "  $targetDir" -ForegroundColor White
Write-Host ""

# Use robocopy for efficient sync
# /MIR = Mirror (delete files in target that don't exist in source)
# /XD = Exclude directories
# /XF = Exclude files
# /NFL = No file list
# /NDL = No directory list
# /NP = No progress
# /R:3 = Retry 3 times
# /W:1 = Wait 1 second between retries

$excludeDirs = @(".git", ".vs", "x64", "Debug", "Release", ".windsurf")
$excludeFiles = @("*.exe", "*.pdb", "*.obj", "*.log")

$robocopyArgs = @(
    $sourceDir,
    $targetDir,
    "/MIR",
    "/R:3",
    "/W:1"
)

# Add excluded directories
foreach($dir in $excludeDirs) {
    $robocopyArgs += "/XD"
    $robocopyArgs += $dir
}

# Add excluded files
foreach($file in $excludeFiles) {
    $robocopyArgs += "/XF"
    $robocopyArgs += $file
}

# Execute robocopy
$result = & robocopy $robocopyArgs

# Check result (robocopy returns 0-7 for success, 8+ for errors)
$exitCode = $LASTEXITCODE
if($exitCode -ge 8) {
    Write-Host "ERROR: Sync failed with exit code $exitCode" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "Sync completed successfully!" -ForegroundColor Green
    Write-Host "Exit code: $exitCode (0=No change, 1=Files copied, 2=Extra files, 3=Files copied + extra)" -ForegroundColor Cyan
}
