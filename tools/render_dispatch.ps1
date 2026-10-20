# render_dispatch.ps1 - render the dispatch headset voice into assets\audio\dispatch\<key>.ogg and import the clips.
#
#   $env:CAST_KOKORO_EXE   = "...\sherpa-onnx-offline-tts.exe"
#   $env:CAST_KOKORO_MODEL = "...\kokoro-multi-lang-v1_0"        # the model folder (model.onnx, voices.bin, ...)
#   .\tools\render_dispatch.ps1 [-Force] [-Prune] [-Jobs N]
#
# Parallel: -Jobs Kokoro processes at once (default half the logical CPUs; CAST_DISPATCH_JOBS too). Incremental: a clip
# that exists is skipped unless -Force; -Prune deletes clips for lines the game no longer has. build.ps1 runs this too
# when CAST_KOKORO_EXE and CAST_KOKORO_MODEL are set.
#
# The line list comes from the game's own constants (tools\dispatch_lines.tscn -> DispatchVoice.all_lines), so it cannot
# drift from the code; tools\render_dispatch.py reads each line with Kokoro (voice af_bella) and runs it through the walkie
# radio chain. The clips are generated (gitignored, like the sfx WAVs): a clip that exists is skipped unless -Force.
# Needs python and ffmpeg (with libvorbis) on PATH (CAST_FFMPEG names ffmpeg explicitly), and assets\audio\third_party\
# (the Kenney key clicks). Without a clip the banner stays silent.
param([switch]$Force, [switch]$Prune, [int]$Jobs = 0, [string]$TtsExe = $env:CAST_KOKORO_EXE, [string]$Model = $env:CAST_KOKORO_MODEL)
. "$PSScriptRoot\..\godot_env.ps1"
$godot = Resolve-CastGodot
$root = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $TtsExe -or -not $Model) {
    Write-Host "Set CAST_KOKORO_EXE (sherpa-onnx-offline-tts.exe) and CAST_KOKORO_MODEL (the kokoro-multi-lang-v1_0 folder); see README." -ForegroundColor Yellow
    exit 1
}
Invoke-CastImport $godot   # (class names must be cached before the lines scene compiles)
$lines = Join-Path ([IO.Path]::GetTempPath()) "cast_dispatch_lines.json"
& $godot --path $root --headless res://tools/dispatch_lines.tscn -- $lines
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $lines)) { Write-Host "Could not list the dispatch lines." -ForegroundColor Red; exit 1 }
$pyArgs = @("-I", "$root\tools\render_dispatch.py", "--lines", $lines, "--out", "$root\assets\audio\dispatch",
    "--tts-exe", $TtsExe, "--model", $Model, "--kenney", "$root\assets\audio\third_party\kenney_interface-sounds")
if ($Force) { $pyArgs += "--force" }
if ($Prune) { $pyArgs += "--prune" }
if ($Jobs -gt 0) { $pyArgs += @("--jobs", "$Jobs") }
& python @pyArgs
if ($LASTEXITCODE -ne 0) { Write-Host "Rendering failed (see above)." -ForegroundColor Red; exit 1 }
Invoke-CastImport $godot
Write-Host "Rendered and imported assets\audio\dispatch\." -ForegroundColor Green
