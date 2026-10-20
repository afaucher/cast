# build.ps1 - import, run the full test gate, then export build\windows\Cast.exe and package
# build\Cast_Windows_v<version>.zip.
#
#   .\build.ps1              # tests, then export + zip
#   .\build.ps1 -SkipTests   # export only (UNVERIFIED build)
#   .\build.ps1 -Force       # export even if tests failed
#
# Export templates (4.7.stable) live in build\deps\godot-data; APPDATA is pointed
# there for the export process only, so nothing machine-wide is read or written.
#
# Versioning (ported from bridge-to-friendship): every build is stamped yyyy-MM-dd.HHmmss. The stamp
# goes into version.txt (project root, gitignored, packed into Cast.pck and shown on the menus by
# scripts/ui/build_version.gd), into build\windows\version.txt and into the zip's name.
param([switch]$SkipTests, [switch]$Force)

$GameName = "Cast"
$buildVersion = Get-Date -Format "yyyy-MM-dd.HHmmss"
Write-Host "Build version: $buildVersion" -ForegroundColor Cyan

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
# The dispatch voice is rendered, not committed: with Kokoro set up (CAST_KOKORO_EXE, CAST_KOKORO_MODEL; README) the build
# renders any missing clips in parallel and drops stale ones; without it the radio calls stay text-only.
if ($env:CAST_KOKORO_EXE -and $env:CAST_KOKORO_MODEL) {
    & "$PSScriptRoot\tools\render_dispatch.ps1" -Prune
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: the dispatch voice did not render fully." -ForegroundColor Yellow }
} elseif (@(Get-ChildItem "$PSScriptRoot\assets\audio\dispatch\*.ogg" -ErrorAction SilentlyContinue).Count -eq 0) {
    Write-Host "WARNING: no dispatch voice clips (set CAST_KOKORO_EXE / CAST_KOKORO_MODEL; see README)." -ForegroundColor Yellow
}
# The sound cues are rendered, not committed (tools\render_sfx.ps1); without them the build runs but is silent.
if (@(Get-ChildItem "$PSScriptRoot\assets\audio\sfx\*.wav" -ErrorAction SilentlyContinue).Count -eq 0) {
    Write-Host "WARNING: no sound cues in assets\audio\sfx (run .\tools\render_sfx.ps1): this build is silent." -ForegroundColor Yellow
}
$buildDir = Join-Path $PSScriptRoot "build"
$outDir = Join-Path $buildDir "windows"
Stop-Process -Name $GameName -ErrorAction SilentlyContinue
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$exe = Join-Path $outDir "$GameName.exe"

# Written right before the export so the .pck carries this build's stamp.
Set-Content -Path "$PSScriptRoot\version.txt" -Value $buildVersion
Write-Host "Exporting $exe ..." -ForegroundColor Cyan
$oldAppData = $env:APPDATA
$env:APPDATA = Join-Path $PSScriptRoot "build\deps\godot-data"
try {
    & $godot --path $PSScriptRoot --headless --export-release "Windows Desktop" $exe 2>&1 |
        Where-Object { $_ -match "ERROR|WARNING|error" } | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
} finally { $env:APPDATA = $oldAppData }

# Godot exits 0 on some failed exports -- the artifacts decide.
foreach ($f in @("Cast.exe", "Cast.pck", "libhero_listen.windows.template_release.x86_64.dll", "sherpa-onnx-c-api.dll", "onnxruntime.dll", "steam_api64.dll")) {
    if (-not (Test-Path (Join-Path $outDir $f))) { Write-Host "BUILD FAILED: missing $f" -ForegroundColor Red; exit 1 }
}
Set-Content -Path (Join-Path $outDir "version.txt") -Value $buildVersion
# Steam needs its app id next to the exe when launched outside the Steam client (480 = Spacewar, dev only).
if (Test-Path "$PSScriptRoot\steam_appid.txt") { Copy-Item "$PSScriptRoot\steam_appid.txt" -Destination $outDir }

# --- Package -------------------------------------------------------------------------------------
# Lessons from bridge-to-friendship's build.ps1: Compress-Archive silently skips a file it cannot open
# (an antivirus scan of the fresh .exe), and Windows leaves full-size `*~RF*.TMP` copies of a replaced
# binary that a wildcard would pack. So: sweep leftovers, pack an explicit list, then VERIFY the zip
# against the folder in both directions (missing, truncated, unwanted) and retry a few times.
$zipPath = Join-Path $buildDir "${GameName}_Windows_v$buildVersion.zip"
Get-ChildItem -Path $buildDir -Filter "${GameName}_Windows_v*.zip" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $outDir -Filter '*~RF*.TMP' -File -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Removing export leftover: $($_.Name)" -ForegroundColor Yellow
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ArchiveFaults([string]$SourceDir, [string]$ZipPath) {
    $expected = @{}
    foreach ($file in (Get-ChildItem -Path $SourceDir -File -Recurse)) {
        if ($file.Name -like '*~RF*.TMP') { continue }   # a leftover is never wanted, even if it survived the sweep
        $rel = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/').Replace('\', '/')
        $expected[$rel] = $file.Length
    }
    $packed = @{}
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try { foreach ($e in $zip.Entries) { $packed[$e.FullName.Replace('\', '/')] = $e.Length } } finally { $zip.Dispose() }
    $faults = @()
    foreach ($rel in $expected.Keys) {
        if (-not $packed.ContainsKey($rel)) { $faults += "MISSING  $rel" }
        elseif ($packed[$rel] -ne $expected[$rel]) { $faults += "TRUNCATED  $rel (packed $($packed[$rel]) of $($expected[$rel]) bytes)" }
    }
    foreach ($rel in $packed.Keys) {
        if (-not $expected.ContainsKey($rel)) { $faults += "UNWANTED  $rel ($($packed[$rel]) bytes)" }
    }
    return $faults
}

Write-Host "Packaging $zipPath ..." -ForegroundColor Cyan
$faults = @()
for ($attempt = 1; $attempt -le 3; $attempt++) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $toPack = Get-ChildItem -Path $outDir -File -Recurse | Where-Object { $_.Name -notlike '*~RF*.TMP' } | ForEach-Object { $_.FullName }
    Compress-Archive -Path $toPack -DestinationPath $zipPath -Force
    $faults = @(Get-ArchiveFaults $outDir $zipPath)
    if ($faults.Count -eq 0) { break }
    Write-Host "Archive does not match the build (attempt $attempt of 3):" -ForegroundColor Yellow
    foreach ($m in $faults) { Write-Host "    $m" -ForegroundColor Yellow }
    if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
}
if ($faults.Count -gt 0) {
    Write-Host "BUILD FAILED: could not package a complete archive (something is holding files open: antivirus, or a running Cast)." -ForegroundColor Red
    exit 1
}

$size = [math]::Round(((Get-ChildItem $outDir -Recurse | Measure-Object Length -Sum).Sum) / 1MB, 1)
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "Build complete: $buildVersion" -ForegroundColor Green
Write-Host "  Executable: $exe  ($size MB folder)"
Write-Host "  ZIP: $zipPath  ($zipSize MB)"
if (-not $ok -or $SkipTests) { Write-Host "WARNING: this build did not pass a clean test gate." -ForegroundColor Yellow }
exit 0
