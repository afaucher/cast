# run_bench.ps1 - run stagger_bench.gd and report the process CPU time it used.
#
#   .\tools\stt_stagger\run_bench.ps1 -Streams 2 -Phases 6
#   .\tools\stt_stagger\run_bench.ps1 -Streams 1 -Phases 12 -Flush 460
#
# Results: tools\stt_stagger\results\<tag>.csv and <tag>.log (git-ignored scratch output; the
# voice clips are local only). Run it with the machine otherwise idle: the bench feeds audio in
# real time, and other Godot processes (a test suite) skew both latency and CPU numbers.
param(
    [int]$Streams = 1,
    [int]$Phases = 1,
    [string]$Groups = "clean,rate",
    [double]$Flush = 0,
    [double]$Quiet = 100,
    [double]$SoftDb = 15,
    [int]$Limit = 0,
    [string]$Tag = "",
    [string]$Extra = ""
)
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
. (Join-Path $root "godot_env.ps1")
$godot = Resolve-CastGodot
$others = @(Get-Process | Where-Object { $_.ProcessName -like 'Godot*' })
if ($others.Count -gt 0) { Write-Host "WARNING: $($others.Count) other Godot process(es) running; numbers will be skewed." -ForegroundColor Yellow }
if ($Tag -eq "") { $Tag = "n$Streams-p$Phases" + $(if ($Flush -gt 0) { "-flush$Flush-q$Quiet-s$SoftDb" } else { "" }) + "-" + ($Groups -replace ",", "+") }
$outDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$csv = Join-Path $outDir "$Tag.csv"
$log = Join-Path $outDir "$Tag.log"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $godot
$psi.Arguments = "--path `"$root`" --headless --script res://tools/stt_stagger/stagger_bench.gd -- --streams $Streams --phases $Phases --groups $Groups --flush $Flush --quiet $Quiet --soft-db $SoftDb --limit $Limit $Extra --out `"$csv`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$watch = [Diagnostics.Stopwatch]::StartNew()
[void]$p.Start()
$null = $p.Handle   # keep the handle so CPU time is readable after exit
$out = $p.StandardOutput.ReadToEndAsync()
$err = $p.StandardError.ReadToEndAsync()
# The console exe is a thin wrapper that starts the real Godot exe as a child: sample both.
$cpu = 0.0
$child = $null
while (-not $p.HasExited) {
    try {
        if ($null -eq $child) {
            $cid = (Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" | Select-Object -First 1).ProcessId
            if ($cid) { $child = Get-Process -Id $cid; $null = $child.Handle }
        }
        $c = 0.0
        if ($null -ne $child) { $child.Refresh(); $c = $child.TotalProcessorTime.TotalSeconds }
        $p.Refresh()
        $cpu = [Math]::Max($cpu, $c + $p.TotalProcessorTime.TotalSeconds)
    } catch {}
    Start-Sleep -Milliseconds 200
}
$p.WaitForExit()
$wall = $watch.Elapsed.TotalSeconds
$text = $out.Result + "`n" + $err.Result + "`nprocess: wall {0:F1} s, cpu {1:F1} s, mean cores busy {2:F2}`n" -f $wall, $cpu, ($cpu / $wall)
Set-Content -Path $log -Value $text -Encoding utf8
$text -split "`n" | Where-Object { $_ -match "^(streams|stream \d|wall|hypothesis|main-thread|push\+poll|process:|wrote)|ERROR" } | ForEach-Object { Write-Host $_ }
