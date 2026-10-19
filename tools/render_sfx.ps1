# render_sfx.ps1 - render the game's sound cues into assets\audio\sfx\*.wav and import them.
#
#   .\tools\render_sfx.ps1
#
# The WAVs are generated (gitignored, like models\): tools\sfx_proto\render_game_sfx.gd builds each game cue from its
# prototype recipe, using the CC0 recordings in assets\audio\third_party\ (also untracked; SOURCES.md lists them).
# Without them the game still runs; the missing cues stay silent.
. "$PSScriptRoot\..\godot_env.ps1"
$godot = Resolve-CastGodot
$root = Resolve-Path "$PSScriptRoot\.."
& $godot --path $root --headless --script res://tools/sfx_proto/render_game_sfx.gd
$ok = ($LASTEXITCODE -eq 0)
Invoke-CastImport $godot
if (-not $ok) { Write-Host "Some cues were not rendered (see the errors above)." -ForegroundColor Yellow; exit 1 }
Write-Host "Rendered and imported assets\audio\sfx\." -ForegroundColor Green
