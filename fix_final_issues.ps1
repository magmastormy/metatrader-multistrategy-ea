# Fix all remaining compilation issues
Write-Host "Fixing remaining compilation issues..."

# 1. Fix array parameter references
$files = Get-ChildItem -Path "." -Include *.mqh,*.mq5 -Recurse -File

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $original = $content
    
    # Fix array parameters - add & reference
    $content = $content -replace '\(([^&]*strategies\[\])', '($&strategies[]'
    $content = $content -replace '\(([^&]*signals\[\])', '($&signals[]'
    $content = $content -replace '\(([^&]*weights\[\])', '($&weights[]'
    $content = $content -replace '\(([^&]*timeframes\[\])', '($&timeframes[]'
    $content = $content -replace '\(([^&]*enabledFlags\[\])', '($&enabledFlags[]'
    $content = $content -replace '\(([^&]*selectedStrategies\[\])', '($&selectedStrategies[]'
    $content = $content -replace '\(([^&]*ma_fast\[\])', '($&ma_fast[]'
    $content = $content -replace '\(([^&]*ma_medium\[\])', '($&ma_medium[]'
    $content = $content -replace '\(([^&]*ma_slow\[\])', '($&ma_slow[]'
    $content = $content -replace '\(([^&]*ma\[\])', '($&ma[]'
    
    if($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed array params in: $($file.Name)"
    }
}

Write-Host "Array parameter fixes complete!"
