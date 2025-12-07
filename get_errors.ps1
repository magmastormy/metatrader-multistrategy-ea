# Get compilation errors
$output = & .\compile_EA.bat 2>&1 | Out-String
$errors = $output -split "`n" | Where-Object { $_ -match "error \d+:" }

Write-Host "Total errors found: $($errors.Count)"
Write-Host "`n=== UNIQUE ERROR TYPES ===" -ForegroundColor Yellow
$errors | ForEach-Object {
    if($_ -match "error (\d+):") {
        $matches[1]
    }
} | Sort-Object -Unique | ForEach-Object {
    $errorNum = $_
    $example = $errors | Where-Object { $_ -match "error ${errorNum}:" } | Select-Object -First 1
    Write-Host "Error $errorNum : $example" -ForegroundColor Cyan
}

Write-Host "`n=== ALL ERRORS ===" -ForegroundColor Yellow
$errors | ForEach-Object { Write-Host $_ }
