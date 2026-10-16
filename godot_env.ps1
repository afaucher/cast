# godot_env.ps1 - locate the Godot 4.7 console binary for this project.
# Order: $env:CAST_GODOT, then the copy Hero-Reader's tools/setup.py installed
# next door (..\Hero-Reader\third_party\godot). No machine-wide fallback.
function Resolve-CastGodot {
    if ($env:CAST_GODOT -and (Test-Path $env:CAST_GODOT)) { return $env:CAST_GODOT }
    $sibling = Join-Path $PSScriptRoot "..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe"
    if (Test-Path $sibling) { return (Resolve-Path $sibling).Path }
    throw "Godot 4.7 not found. Set CAST_GODOT to Godot_v4.7-stable_win64_console.exe."
}

# Import (or reimport) the project once so class_name caches and .import files exist.
function Invoke-CastImport([string]$Godot) {
    & $Godot --path $PSScriptRoot --headless --import 2>&1 | Out-Null
}
