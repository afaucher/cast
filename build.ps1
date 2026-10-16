# build.ps1 - import, run the full test gate, then export build\windows\Cast.exe.
#
#   .\build.ps1              # tests, then export
#   .\build.ps1 -SkipTests   # export only (UNVERIFIED build)
#   .\build.ps1 -Force       # export even if tests failed
#
# Export templates (4.7.stable) live in build\deps\godot-data; APPDATA is pointed
# there for the export process only, so nothing machine-wide is read or written.
param([switch]$SkipTests, [switch]$Force)

. "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot
Write-Host "Engine: $godot" -ForegroundColor DarkCyan
Write-Host "Importing project..." -ForegroundColor Cyan
Invoke-CastImport $godot

$ok = $true
if (-not $SkipTests) {
    & "$PSScriptRoot\test_runner.ps1" -TestAll -NoImport
    $ok = ($LASTEXITCODE -eq 0)
    if (-not $ok -and -not $Force) { Write-Host "BUILD ABORTED: tests failed." -ForegroundColor Red; exit 1 }
}

$templates = Join-Path $PSScriptRoot "build\deps\godot-data\Godot\export_templates\4.7.stable\windows_release_x86_64.exe"
if (-not (Test-Path $templates)) {
    Write-Host "Missing export templates: $templates" -ForegroundColor Red
    Write-Host "Copy ..\bridge-to-friendship\build\deps\godot-data\Godot\export_templates\4.7.stable there." -ForegroundColor Yellow
    exit 1
}
$outDir = Join-Path $PSScriptRoot "build\windows"
Stop-Process -Name Cast -ErrorAction SilentlyContinue
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$exe = Join-Path $outDir "Cast.exe"

Write-Host "Exporting $exe ..." -ForegroundColor Cyan
$oldAppData = $env:APPDATA
$env:APPDATA = Join-Path $PSScriptRoot "build\deps\godot-data"
try {
    & $godot --path $PSScriptRoot --headless --export-release "Windows Desktop" $exe 2>&1 |
        Where-Object { $_ -match "ERROR|WARNING|error" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
} finally { $env:APPDATA = $oldAppData }

# Godot exits 0 on some failed exports -- the artifacts decide.
foreach ($f in @("Cast.exe", "Cast.pck", "libhero_listen.windows.template_debug.x86_64.dll", "sherpa-onnx-c-api.dll", "onnxruntime.dll")) {
    if (-not (Test-Path (Join-Path $outDir $f))) { Write-Host "BUILD FAILED: missing $f" -ForegroundColor Red; exit 1 }
}
$size = [math]::Round(((Get-ChildItem $outDir -Recurse | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host "Build complete: $exe  ($size MB total)" -ForegroundColor Green
if (-not $ok -or $SkipTests) { Write-Host "WARNING: this build did not pass a clean test gate." -ForegroundColor Yellow }
exit 0
