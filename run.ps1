# run.ps1 - play the game (windowed). Extra args go to the game, e.g.
#   .\run.ps1 --seed 42
.  "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot
& $godot --path $PSScriptRoot -- @args
