$src = 'D:\TraeProjects\metatrader-multistrategy-ea'
$dst = 'C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\Experts\MultiStrategyAutonomousEA'
$excluded = @('Dashboard', 'node_modules', '.venv-ea-dashboard', '.trae', '.git', '.joycode', '.kiro', '.sixth', '.trunk', '.windsurf', 'docs')
Get-ChildItem $src -File -Include *.mq5,*.mqh -Recurse | Where-Object { $excluded -notcontains $_.Directory.Name -and $_.FullName -notmatch '\\.git' } | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1)
    $destFile = Join-Path $dst $rel
    $destDir = Split-Path $destFile -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item $_.FullName $destFile -Force
    Write-Host "Copied: $rel"
}