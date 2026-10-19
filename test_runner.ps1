# test_runner.ps1 - run headless Godot tests from tests/<name>.gd.
#
#   .\test_runner.ps1 -TestName test_hex       # one test
#   .\test_runner.ps1 -TestAll                 # every tests\test_*.gd, in parallel
#   .\test_runner.ps1 -TestAll -NoImport       # skip the import pass
#   .\test_runner.ps1 -TestName test_net_clock -Link coast   # a net test under one link preset only
#
# Logs: test_logs\<name>.log / .err.log. A test passes only with exit code 0,
# the ">>> [TEST PASSED] <name> <<<" marker, AND no "SCRIPT ERROR" in its output.
#
# NET TESTS (docs/design/networking-build-plan.md §3): a test whose source declares `const PEERS := N` runs
# as N headless processes over ENet on localhost: a host, then N-1 clients, each with
#   --run-test X --net-role host|client --net-index i --net-port P --net-peers N --net-link L
# once per link preset in its `const LINKS := [...]` (default "off" and "coast"). Each run gets its own port
# (28000 + 10 * slot). Logs: test_logs\<name>.<link>.host.log, .c1.log, ... A run passes only if EVERY
# process exits 0, the host log has the PASS marker and no log has a SCRIPT ERROR; every process of a run is
# killed at its timeout. Net runs go after the parallel batch, at most 2 at a time, so a starved CPU can't
# fake lag (they measure real-time clocks). They run in real time (--max-fps 60, not --fixed-fps).
param(
    [string]$TestName = "",
    [switch]$TestAll,
    [switch]$NoImport,
    [int]$TimeoutSec = 300,
    [string]$Link = "",
    [int]$NetTimeoutSec = 90
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

function Start-Godot([string]$Name, [string]$Extra = "", [string]$Timing = "--fixed-fps 60") {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godot
    $psi.Arguments = "--path `"$PSScriptRoot`" --headless $Timing -- --run-test $Name $Extra"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    return [PSCustomObject]@{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

function Start-Test([string]$Name) {
    $g = Start-Godot $Name
    return [PSCustomObject]@{ Name = $Name; Proc = $g.Proc; Out = $g.Out; Err = $g.Err; Watch = [Diagnostics.Stopwatch]::StartNew() }
}

function Finish-Test($r, [int]$Limit = $TimeoutSec) {
    if (-not $r.Proc.WaitForExit($Limit * 1000)) { try { $r.Proc.Kill() } catch {}; $r.Proc.WaitForExit() }
    $out = $r.Out.Result; $err = $r.Err.Result
    Set-Content -Path "$logDir\$($r.Name).log" -Value $out
    Set-Content -Path "$logDir\$($r.Name).err.log" -Value $err
    # A script error inside a coroutine aborts the test silently but can still end in a
    # PASS marker, so any SCRIPT ERROR in the output fails the test too.
    $scriptErr = ($out + "`n" + $err) -match "SCRIPT ERROR"
    $ok = ($r.Proc.ExitCode -eq 0) -and ($out -match [regex]::Escape(">>> [TEST PASSED] $($r.Name) <<<")) -and (-not $scriptErr)
    $secs = $r.Watch.Elapsed.TotalSeconds.ToString("F1")
    if ($ok) { Write-Host "  PASS  $($r.Name)  ($secs s)" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $($r.Name)  ($secs s, exit $($r.Proc.ExitCode))" -ForegroundColor Red
        ($out + "`n" + $err) -split "`n" | Where-Object { $_ -match "ASSERT FAILED|SCRIPT ERROR|Parse Error|ERROR:|TEST FAILED" } | Select-Object -First 15 | ForEach-Object { Write-Host "        $_" }
    }
    return $ok
}

# --- Net tests: several processes per run ------------------------------------------------------------

# $null for an ordinary test, else @{ Peers = N; Links = @(...) }.
function Get-NetSpec([string]$Name) {
    $src = Get-Content -Raw "$PSScriptRoot\tests\$Name.gd"
    $m = [regex]::Match($src, '(?m)^const PEERS\s*:=\s*(\d+)')
    if (-not $m.Success) { return $null }
    $links = @("off", "coast")
    $lm = [regex]::Match($src, '(?m)^const LINKS\s*:=\s*\[([^\]]*)\]')
    if ($lm.Success) { $links = @([regex]::Matches($lm.Groups[1].Value, '"([a-z]+)"') | ForEach-Object { $_.Groups[1].Value }) }
    if ($Link -ne "") { $links = @($Link) }
    return @{ Peers = [int]$m.Groups[1].Value; Links = $links }
}

$script:netSlot = 0
# Real time, not --fixed-fps: under --fixed-fps a headless process runs as fast as it can and game time
# races ahead of the wall clock, which is exactly what a clock-sync or lag test must not have. Capped at
# 60 fps so four processes don't spin the CPU.
$netTiming = "--max-fps 60"
function Start-NetRun([string]$Name, [int]$Peers, [string]$LinkName) {
    $script:netSlot += 1
    $port = 28000 + 10 * $script:netSlot
    $common = "--net-port $port --net-peers $Peers --net-link $LinkName"
    $procs = @()
    $procs += [PSCustomObject]@{ Role = "host"; G = (Start-Godot $Name "--net-role host --net-index 0 $common" $netTiming) }
    # The host binds first; clients also retry while it starts.
    Start-Sleep -Milliseconds 400
    for ($i = 1; $i -lt $Peers; $i++) {
        $procs += [PSCustomObject]@{ Role = "c$i"; G = (Start-Godot $Name "--net-role client --net-index $i $common" $netTiming) }
    }
    return [PSCustomObject]@{ Name = $Name; Link = $LinkName; Label = "$Name [$LinkName]"; Procs = $procs; Watch = [Diagnostics.Stopwatch]::StartNew() }
}

function Test-NetRunExited($run) {
    return @($run.Procs | Where-Object { -not $_.G.Proc.HasExited }).Count -eq 0
}

function Finish-NetRun($run) {
    $deadline = [DateTime]::Now.AddSeconds([Math]::Max(0, $NetTimeoutSec - $run.Watch.Elapsed.TotalSeconds))
    foreach ($p in $run.Procs) {
        $left = [Math]::Max(0, ($deadline - [DateTime]::Now).TotalMilliseconds)
        if (-not $p.G.Proc.WaitForExit([int]$left)) { try { $p.G.Proc.Kill() } catch {}; $p.G.Proc.WaitForExit() }
    }
    $ok = $true; $why = @()
    foreach ($p in $run.Procs) {
        $out = $p.G.Out.Result; $err = $p.G.Err.Result
        $base = "$logDir\$($run.Name).$($run.Link).$($p.Role)"
        Set-Content -Path "$base.log" -Value $out
        Set-Content -Path "$base.err.log" -Value $err
        if ($p.G.Proc.ExitCode -ne 0) { $ok = $false; $why += "$($p.Role) exit $($p.G.Proc.ExitCode)" }
        if (($out + "`n" + $err) -match "SCRIPT ERROR") { $ok = $false; $why += "$($p.Role) SCRIPT ERROR" }
        if ($p.Role -eq "host" -and -not ($out -match [regex]::Escape(">>> [TEST PASSED] $($run.Name) <<<"))) { $ok = $false; $why += "no PASS marker from the host" }
        $p | Add-Member -NotePropertyName Text -NotePropertyValue ($out + "`n" + $err) -Force
    }
    $secs = $run.Watch.Elapsed.TotalSeconds.ToString("F1")
    if ($ok) { Write-Host "  PASS  $($run.Label)  ($secs s, $($run.Procs.Count) processes)" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $($run.Label)  ($secs s: $($why -join ', '))" -ForegroundColor Red
        foreach ($p in $run.Procs) {
            $p.Text -split "`n" | Where-Object { $_ -match "ASSERT FAILED|SCRIPT ERROR|Parse Error|ERROR:|TEST FAILED" } | Select-Object -First 8 | ForEach-Object { Write-Host "        [$($p.Role)] $_" }
        }
    }
    return $ok
}

# --- Schedule ------------------------------------------------------------------------------------

$names = if ($TestAll) { Get-ChildItem "$PSScriptRoot\tests\test_*.gd" | ForEach-Object { $_.BaseName } } else { @($TestName) }
$max = [Math]::Max(2, [Math]::Min(8, [Environment]::ProcessorCount - 2))
$running = @(); $failed = @(); $total = 0
# Real-time audio tests feed the speech model on a wall-clock schedule; under a
# parallel batch the recognizer thread starves and borderline clips flip. They
# run one at a time, after everything else, with the box otherwise idle.
$serialNames = @("test_voice_audio", "test_voice_triggers", "test_voice_noise", "test_voice_orders")
$netRuns = @()
foreach ($n in $names) {
    $spec = Get-NetSpec $n
    if ($spec -ne $null) { foreach ($l in $spec.Links) { $netRuns += [PSCustomObject]@{ Name = $n; Peers = $spec.Peers; Link = $l } } }
}
$netNames = @($netRuns | ForEach-Object { $_.Name } | Select-Object -Unique)
$parallel = @($names | Where-Object { $serialNames -notcontains $_ -and $netNames -notcontains $_ })
$serial = @($names | Where-Object { $serialNames -contains $_ })
foreach ($n in $parallel) {
    while (@($running | Where-Object { -not $_.Proc.HasExited }).Count -ge $max) { Start-Sleep -Milliseconds 100 }
    $running += Start-Test $n
}
foreach ($r in $running) { $total += 1; if (-not (Finish-Test $r)) { $failed += $r.Name } }

# Net runs: at most 2 at a time.
if ($netRuns.Count -gt 0) {
    $netWatch = [Diagnostics.Stopwatch]::StartNew()
    $queue = [System.Collections.ArrayList]@($netRuns)
    $active = @()
    while ($queue.Count -gt 0 -or $active.Count -gt 0) {
        while ($queue.Count -gt 0 -and $active.Count -lt 2) {
            $next = $queue[0]; $queue.RemoveAt(0)
            $active += Start-NetRun $next.Name $next.Peers $next.Link
        }
        $doneRun = $active | Where-Object { (Test-NetRunExited $_) -or $_.Watch.Elapsed.TotalSeconds -gt $NetTimeoutSec } | Select-Object -First 1
        if ($doneRun -eq $null) { Start-Sleep -Milliseconds 100; continue }
        $total += 1
        if (-not (Finish-NetRun $doneRun)) { $failed += $doneRun.Label }
        $active = @($active | Where-Object { $_ -ne $doneRun })
    }
    Write-Host "  net runs: $($netRuns.Count) in $($netWatch.Elapsed.TotalSeconds.ToString('F1')) s (2 at a time)" -ForegroundColor DarkCyan
}

foreach ($n in $serial) {
    $r = Start-Test $n
    $total += 1
    # The audio suite replays every clip at real-time pace: ~5 min alone.
    if (-not (Finish-Test $r ([Math]::Max($TimeoutSec, 900)))) { $failed += $r.Name }
}

if ($failed.Count -gt 0) { Write-Host "$($failed.Count) of $total test(s) FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "All $total test(s) passed." -ForegroundColor Green
exit 0
