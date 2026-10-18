# run.ps1 - play the game (windowed). Extra args go to the game, e.g.
#   .\run.ps1 --seed 42
#
# A local crew over ENet (no Steam needed), one window per player:
#   .\run.ps1 -Crew 2                 # a host (opens the job board) and one joiner (waits on the menu)
#   .\run.ps1 -Crew 3 -Link coast     # three players, every window simulating a coast-to-coast link
# Players are named Host, Crew2, Crew3; only the host has the microphone. Extra args go to every window.
.  "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot

$crew = 0; $link = ""; $rest = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Crew" -and $i + 1 -lt $args.Count) { $crew = [int]$args[$i + 1]; $i++ }
    elseif ($args[$i] -eq "-Link" -and $i + 1 -lt $args.Count) { $link = [string]$args[$i + 1]; $i++ }
    else { $rest += $args[$i] }
}
if ($crew -lt 2) {
    & $godot --path $PSScriptRoot -- @rest
    exit $LASTEXITCODE
}

$port = 24600
$common = @("--net-port", "$port")
if ($link -ne "") { $common += @("--net-link", $link) }
# Windows of 800x450 tiled left to right, top to bottom.
function Start-Player([int]$n, [string[]]$gameArgs) {
    $x = 40 + (($n - 1) % 2) * 820; $y = 40 + [Math]::Floor(($n - 1) / 2) * 480
    $all = @("--path", "`"$PSScriptRoot`"", "--resolution", "800x450", "--position", "$x,$y", "--") + $gameArgs + $common + $rest
    return Start-Process -FilePath $godot -ArgumentList $all -PassThru
}
$procs = @(Start-Player 1 @("--net-host", "--net-name", "Host"))
Start-Sleep -Seconds 2
for ($n = 2; $n -le $crew; $n++) {
    $procs += Start-Player $n @("--net-join", "127.0.0.1:$port", "--net-name", "Crew$n", "--no-mic")
}
Write-Host "Started $crew windows on port $port$(if ($link) { " (link: $link)" }). Close them to stop."
