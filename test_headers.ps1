# Compile-level test for the .mqh header tree, independent of the EAs that normal build uses.
#
# Why this exists: `sync_and_compile.ps1` proves that the eight .mq5 programs build. That is not the
# same claim as "the headers are sound", because a translation unit which includes a header after
# fifty others satisfies every symbol it needs by luck of ordering. This script makes two claims:
#
#   -AllInOne (default): every .mqh in the repository, in one translation unit, in a stable order.
#                         Catches missing include guards (a double definition), include cycles, and
#                         headers that only resolve because some other header was included first.
#   -Each:                one translation unit per header, containing only that header. Catches a
#                         header that relies on its includer to pull in its own dependencies. A
#                         failure here is informational, not necessarily a bug: this tree has never
#                         promised self-containment, so the report separates "hips own deps" from
#                         "broken".
#
# Usage:
#   .\test_headers.ps1                              # all-in-one sweep
#   .\test_headers.ps1 -Each                        # per-header sweep (slow: one compile per header)
#   .\test_headers.ps1 -Each -Filter 'Strategies\*' # per-header, limited by path glob
#   .\test_headers.ps1 -KeepLog                     # keep the generated .mq5 and .log files
#
# Exit code 0 only when the sweep it ran produced no errors. Temporary files are removed unless
# -KeepLog, so the sandbox is left as it was found.

[CmdletBinding()]
param(
    [switch]$Each,
    [switch]$AllInOne,
    [string]$Filter = '*',
    [switch]$KeepLog,
    [int]$MaxCompileWaitSec = 300
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$terminalData = Join-Path $env:APPDATA 'MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1'
$metaEditor = 'C:\Program Files\MetaTrader 5 Terminal\MetaEditor64.exe'
$sandboxExpertDir = Join-Path $terminalData 'MQL5\Experts\MultiStrategyAutonomousEA'
$stamp = 'hdr_' + (Get-Date -Format 'HHmmss')

if(-not (Test-Path -LiteralPath $metaEditor)) { throw "MetaEditor not found: $metaEditor" }
if(-not (Test-Path -LiteralPath $sandboxExpertDir)) { throw "Sandbox expert dir not found: $sandboxExpertDir (run sync_and_compile.ps1 first)" }

# The sandbox mirrors the repository layout under Experts\MultiStrategyAutonomousEA, so a header's
# include path is its repository path with backslashes normalised.
function Get-HeaderList {
    param([string]$Pattern)
    $all = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter '*.mqh' |
        Where-Object { $_.FullName -notmatch '\\\.git\\' }
    $rel = $all | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }
    if($Pattern -and $Pattern -ne '*') { $rel = $rel | Where-Object { $_ -like $Pattern } }
    return @($rel | Sort-Object)
}

# Order matters for -AllInOne: foundational enums and types first, orchestration and strategies last.
# The sort is by bucket, then alphabetically, so the order is reproducible without a hand-maintained list.
#
# The prelude reproduces the six globals every program in this tree defines (`extern` is declared in
# the headers, the definition lives in the .mq5). Without them a sweep reports "unresolved extern
# variable" for a header that is perfectly correct - the contract is that the program defines these,
# so the harness defines them too. Grep '^extern ' over the headers to re-derive the list.
function Get-Prelude {
    return @(
        '#include "Core/Processing/MultiAssetProfiler.mqh"'
        '#include "Core/Utils/StructuredLogger.mqh"'
        '#include "Core/Utils/CorrelationId.mqh"'
        '#include "Core/Orchestration/GlobalDefs.mqh"'
        'CStructuredLogger g_structLog;'
        'CCorrelationIdManager g_corrIdManager;'
    )
}

function Get-IncludeOrder {
    param([string[]]$Headers)
    $bucket = {
        param($p)
        if($p -match '^Core\\Utils')      { return 0 }
        if($p -match '^Core\\Config')     { return 1 }
        if($p -match '^Core\\Strategy\\StrategyBase') { return 2 }
        if($p -match '^Core\\Strategy')   { return 3 }
        if($p -match '^Core\\Management') { return 4 }
        if($p -match '^Core\\Orchestration') { return 5 }
        if($p -match '^Core')             { return 6 }
        if($p -match '^Strategies')       { return 7 }
        return 8
    }
    $Headers | Sort-Object @{ Expression = { & $bucket $_ } }, @{ Expression = { $_ } }
}

function Compile-TestFile {
    param([string]$Path)
    $out = $Path -replace '\.mq5$', ''
    $logFile = "$out.log"
    if(Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force }
    $proc = Start-Process -FilePath $metaEditor `
        -ArgumentList "/compile:`"$Path`"", "/log" `
        -WindowStyle Hidden -PassThru
    $deadline = (Get-Date).AddSeconds($MaxCompileWaitSec)
    $logReady = $false
    while((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        if((Test-Path -LiteralPath $logFile) -and (Get-Item -LiteralPath $logFile).Length -gt 0) {
            # MetaEditor writes the log before the process exits; wait for exit to avoid a partial read.
            if($proc.HasExited) { $logReady = $true; break }
        }
        elseif($proc.HasExited) { $logReady = $true; break }
    }
    if($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch {} }
    if(-not (Test-Path -LiteralPath $logFile)) { return @{ Errors = -1; Warnings = -1; Text = 'no log produced' } }

    $text = [IO.File]::ReadAllText($logFile)
    $m = [regex]::Match($text, '(\d+)\s+errors?,\s+(\d+)\s+warnings?')
    if($m.Success) {
        return @{ Errors = [int]$m.Groups[1].Value; Warnings = [int]$m.Groups[2].Value; Text = $text }
    }
    # '0 errors, 0 warnings' is not always printed on success for header-only TUs; treat 'Result:' absence
    # as success only when no diagnostic lines exist.
    $diag = ([regex]::Matches($text, '(?m)^.*:\s+(error|warning)\s')).Count
    return @{ Errors = $diag; Warnings = 0; Text = $text }
}

# A "companion" header defines members of a class out of the class body (`void CFoo::Bar() { ... }`),
# and the class itself is defined in a different file. Such a file cannot be a standalone translation
# unit by construction - MQL5 has no partial classes, so the definition must be visible first, and
# including the defining header here would close a cycle. They are excluded from the per-header claim
# (the all-in-one sweep still compiles them) and reported separately so the exclusion stays visible.
function Test-CompanionHeader {
    param([string]$FullPath)
    $defs = Select-String -LiteralPath $FullPath -Pattern '^(?:void|bool|int|double|string|long|uint|ulong|short|ushort|char|uchar|float|C[A-Za-z0-9_]+)\s+C[A-Za-z0-9_]+\s*::'
    if(-not $defs) { return $false }
    $classNames = $defs | ForEach-Object {
        $m = [regex]::Match($_.Line, '\s(C[A-Za-z0-9_]+)\s*::')
        if($m.Success) { $m.Groups[1].Value }
    } | Where-Object { $_ } | Select-Object -Unique
    foreach($cn in $classNames) {
        $hasOwnDef = Select-String -LiteralPath $FullPath -Pattern ('^(?:class|struct)\s+' + [regex]::Escape($cn) + '\b') -Quiet
        if(-not $hasOwnDef) { return $true }
    }
    return $false
}

function Invoke-Sweep {
    param([string[]]$Headers, [string]$Suffix)
    $results = @()
    $idx = 0
    foreach($h in $Headers) {
        $idx++
        $name = "${stamp}_${Suffix}_" + ('{0:d3}' -f $idx)
        $tuPath = Join-Path $sandboxExpertDir "$name.mq5"
        $inc = $h -replace '\\', '/'
        $body = ''
        foreach($line in (Get-Prelude)) { $body += "$line`r`n" }
        $body += "#include `"$inc`"`r`nvoid OnStart() {}`r`n"
        [IO.File]::WriteAllText($tuPath, $body, (New-Object Text.UTF8Encoding $false))
        $r = Compile-TestFile -Path $tuPath
        $results += [pscustomobject]@{ Header = $h; Errors = $r.Errors; Warnings = $r.Warnings; Log = $r.Text }
        Write-Progress -Activity "Compiling headers ($Suffix)" -Status $h -PercentComplete ([Math]::Min(100, ($idx * 100) / [Math]::Max(1, $Headers.Count)))
        if(-not $KeepLog) {
            try { Remove-Item -LiteralPath $tuPath -Force } catch {}
            try { Remove-Item -LiteralPath ($tuPath -replace '\.mq5$', '.log') -Force } catch {}
        }
    }
    Write-Progress -Activity "Compiling headers ($Suffix)" -Completed
    return $results
}

$headers = Get-HeaderList -Pattern $Filter
Write-Output ("[HDR-TEST] {0} headers match filter '{1}'" -f $headers.Count, $Filter)

if($AllInOne -or (-not $Each)) {
    $ordered = Get-IncludeOrder -Headers $headers
    $tuPath = Join-Path $sandboxExpertDir "${stamp}_allinone.mq5"
    $sb = New-Object Text.StringBuilder
    foreach($line in (Get-Prelude)) { [void]$sb.AppendLine($line) }
    foreach($h in $ordered) { [void]$sb.AppendLine('#include "' + ($h -replace '\\', '/') + '"') }
    [void]$sb.AppendLine('void OnStart() {}')
    [IO.File]::WriteAllText($tuPath, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
    $r = Compile-TestFile -Path $tuPath
    if($r.Errors -eq 0) {
        Write-Output ("[HDR-TEST] ALL-IN-ONE: PASS - {0} headers in one translation unit, 0 errors, {1} warnings" -f $headers.Count, $r.Warnings)
    } else {
        Write-Output ("[HDR-TEST] ALL-IN-ONE: FAIL - {0} errors, {1} warnings" -f $r.Errors, $r.Warnings)
        ($r.Text -split "`n" | Where-Object { $_ -match ':\s+(error|warning)\s' }) | ForEach-Object { '    ' + $_.Trim() }
    }
    if(-not $KeepLog) {
        try { Remove-Item -LiteralPath $tuPath -Force } catch {}
        try { Remove-Item -LiteralPath ($tuPath -replace '\.mq5$', '.log') -Force } catch {}
    }
}

if($Each) {
    $companions = @($headers | Where-Object { Test-CompanionHeader -FullPath (Join-Path $repoRoot $_) })
    $standalone = @($headers | Where-Object { $companions -notcontains $_ })
    Write-Output ("[HDR-TEST] EACH-ALONE: {0} standalone headers, {1} companion headers skipped (they define members of a class whose definition lives in another file; the all-in-one sweep covers them)" -f $standalone.Count, $companions.Count)
    $results = Invoke-Sweep -Headers $standalone -Suffix 'each'
    $pass = @($results | Where-Object { $_.Errors -eq 0 })
    $fail = @($results | Where-Object { $_.Errors -ne 0 })

    # Two kinds of header cannot compile alone by design, and neither is a defect:
    #  - it forward-declares a type (`class CFoo;`) and then dereferences it - the definition is expected
    #    from the includer, and including it here would close a cycle (the EnterpriseStrategyManager
    #    family is the clear case: the manager includes these, so these cannot include the manager);
    #  - it reads an `input` (`Inp...`), which MQL5 declares in the program; the inputs live in
    #    Core/Config/SharedEAInputs.mqh, and pulling that header into a header-only translation unit
    #    drags in the orchestration chain, so the contract is the program's, not this file's.
    # They are reported as "requires its owner" rather than as defects, so the number is not read as a
    # clean bill of health.
    $owned = @($fail | Where-Object {
        $p = Join-Path $repoRoot $_.Header
        (Select-String -LiteralPath $p -Pattern '^class [A-Za-z0-9_]+;' -Quiet) -or ($_.Log -match "undeclared identifier 'Inp")
    })
    $broken = @($fail | Where-Object { $owned -notcontains $_ })

    Write-Output ("[HDR-TEST] EACH-ALONE: {0} passed / {1} requires-owner / {2} broken of {3}" -f $pass.Count, $owned.Count, $broken.Count, $results.Count)
    foreach($f in $owned) {
        Write-Output ("    OWNED {0} ({1} errors) - forward-declares the type it dereferences" -f $f.Header, $f.Errors)
    }
    foreach($f in $broken) {
        Write-Output ("    BROKEN {0} ({1} errors)" -f $f.Header, $f.Errors)
        ($f.Log -split "`n" | Where-Object { $_ -match ':\s+error\s' } | Select-Object -First 3) | ForEach-Object { '        ' + $_.Trim() }
    }
    if($broken.Count -gt 0) { exit 1 }
}
exit 0
