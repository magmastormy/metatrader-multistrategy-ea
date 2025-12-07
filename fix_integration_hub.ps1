# Fix IntegrationHub.mqh by removing SPredictionWithUncertainty usage
$file = "Core\Connectivity\IntegrationHub.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    
    # Remove the uncertainty member variable line
    $content = $content -replace "    SPredictionWithUncertainty uncertainty;.*\r?\n", ""
    
    Set-Content $file -Value $content -NoNewline -Encoding UTF8
    Write-Host "Fixed IntegrationHub.mqh - removed SPredictionWithUncertainty member"
}

Write-Host "Done!"
