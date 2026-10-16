# test_runner.ps1 - run headless Godot tests from tests/<name>.gd.
#
#   .\test_runner.ps1 -TestName test_hex       # one test
#   .\test_runner.ps1 -TestAll                 # every tests\test_*.gd, in parallel
#   .\test_runner.ps1 -TestAll -NoImport       # skip the import pass
#
# Logs: test_logs\<name>.log / .err.log. A test passes only with exit code 0
# AND the ">>> [TEST PASSED] <name> <<<" marker.
param(
    [string]$TestName = "",
    [switch]$TestAll,
    [switch]$NoImport,
    [int]$TimeoutSec = 300
)
. "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot
$logDir = Join-Path $PSScriptRoot "test_logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not $TestAll -and $TestName -eq "") {
    Write-Host "Usage: .\test_runner.ps1 -TestName <name> | -TestAll" -ForegroundColor Yellow
    Get-ChildItem "$PSScriptRoot\tests\test_*.gd" | ForEach-Object { Write-Host "  $($_.BaseName)" }
    exit 1
}
if (-not $NoImport) { Invoke-CastImport $godot }

function Start-Test([string]$Name) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godot
    $psi.Arguments = "--path `"$PSScriptRoot`" --headless --fixed-fps 60 -- --run-test $Name"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    return [PSCustomObject]@{ Name = $Name; Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync(); Watch = [Diagnostics.Stopwatch]::StartNew() }
}

function Finish-Test($r) {
    if (-not $r.Proc.WaitForExit($TimeoutSec * 1000)) { try { $r.Proc.Kill() } catch {}; $r.Proc.WaitForExit() }
    $out = $r.Out.Result; $err = $r.Err.Result
    Set-Content -Path "$logDir\$($r.Name).log" -Value $out
    Set-Content -Path "$logDir\$($r.Name).err.log" -Value $err
    $ok = ($r.Proc.ExitCode -eq 0) -and ($out -match [regex]::Escape(">>> [TEST PASSED] $($r.Name) <<<"))
    $secs = $r.Watch.Elapsed.TotalSeconds.ToString("F1")
    if ($ok) { Write-Host "  PASS  $($r.Name)  ($secs s)" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $($r.Name)  ($secs s, exit $($r.Proc.ExitCode))" -ForegroundColor Red
        ($out + "`n" + $err) -split "`n" | Where-Object { $_ -match "ASSERT FAILED|SCRIPT ERROR|Parse Error|ERROR:|TEST FAILED" } | Select-Object -First 15 | ForEach-Object { Write-Host "        $_" }
    }
    return $ok
}

$names = if ($TestAll) { Get-ChildItem "$PSScriptRoot\tests\test_*.gd" | ForEach-Object { $_.BaseName } } else { @($TestName) }
$max = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount - 2))
$running = @(); $failed = @()
foreach ($n in $names) {
    while (@($running | Where-Object { -not $_.Proc.HasExited }).Count -ge $max) { Start-Sleep -Milliseconds 100 }
    $running += Start-Test $n
}
foreach ($r in $running) { if (-not (Finish-Test $r)) { $failed += $r.Name } }

if ($failed.Count -gt 0) { Write-Host "$($failed.Count) of $($names.Count) test(s) FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All $($names.Count) test(s) passed." -ForegroundColor Green
exit 0
