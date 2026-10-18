# run.ps1 - play the game (windowed). Extra args go to the game, e.g.
#   .\run.ps1 --seed 42
#
# A local crew over ENet (no Steam needed), one window per player:
#   .\run.ps1 -Crew 2                 # a host (opens the job board) and one joiner (lands on the same board, read-only)
#   .\run.ps1 -Crew 3 -Link coast     # three players, every window simulating a coast-to-coast link
#   .\run.ps1 -Crew 2 -Bot 2          # window 2's hero walks a loop by itself (--net-bot); -Bot 1,2 for both windows
#   .\run.ps1 -Crew 2 -Size 1280x720  # bigger windows (default 800x450)
#   .\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn -ShotDir C:\shots
#                                     # the host takes offer 2 once both are in, both sign heal+corn, and each
#                                     # window saves <Name>.png 3 s after the shared floor start and quits
# Players are named Host, Crew2, Crew3; only the host has the microphone. Extra args go to every window.
.  "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot

$crew = 0; $link = ""; $shotDir = ""; $bots = @(); $size = "800x450"; $rest = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Crew" -and $i + 1 -lt $args.Count) { $crew = [int]$args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-Link" -and $i + 1 -lt $args.Count) { $link = [string]$args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-ShotDir" -and $i + 1 -lt $args.Count) { $shotDir = [string]$args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-Size" -and $i + 1 -lt $args.Count) { $size = [string]$args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-Bot" -and $i + 1 -lt $args.Count) { $bots = @(([string]$args[$i + 1]) -split "[, ]+" | Where-Object { $_ -ne "" } | ForEach-Object { [int]$_ }); $i++ }
    elseif ($args[$i] -is [array]) { $rest += ($args[$i] -join ",") }   # (heal,corn reaches a script as an array)
    else { $rest += $args[$i] }
}
if ($crew -lt 2) {
    & $godot --path $PSScriptRoot -- @rest
    exit $LASTEXITCODE
}

$port = 24600
$common = @("--net-port", "$port")
if ($link -ne "") { $common += @("--net-link", $link) }
# Windows (-Size WxH, default 800x450) tiled left to right, top to bottom.
$w = [int]($size -split "x")[0]; $h = [int]($size -split "x")[1]
function Start-Player([int]$n, [string[]]$gameArgs, [string]$who) {
    $x = 40 + (($n - 1) % 2) * ($w + 20); $y = 40 + [Math]::Floor(($n - 1) / 2) * ($h + 30)
    $all = @("--path", "`"$PSScriptRoot`"", "--resolution", $size, "--position", "$x,$y", "--") + $gameArgs + $common + $rest
    if ($bots -contains $n) { $all += "--net-bot" }
    if ($shotDir -ne "") { New-Item -ItemType Directory -Force -Path $shotDir | Out-Null; $all += @("--shot", "`"$shotDir\$who.png`"") }
    return Start-Process -FilePath $godot -ArgumentList $all -PassThru
}
$procs = @(Start-Player 1 @("--net-host", "--net-name", "Host") "Host")
Start-Sleep -Seconds 2
for ($n = 2; $n -le $crew; $n++) {
    $procs += Start-Player $n @("--net-join", "127.0.0.1:$port", "--net-name", "Crew$n", "--no-mic") "Crew$n"
}
Write-Host "Started $crew windows on port $port$(if ($link) { " (link: $link)" }). Close them to stop."
