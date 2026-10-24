# Packs this machine's Cast logs into Cast_logs_v<version>_<timestamp>.zip next to the game, for a playtest report.
# Pack_logs.bat runs it (double-click). build.ps1 ships both beside Cast.exe; version.txt there names the build.
# The logs are copied to a temp folder first, so a running Cast (holding godot.log open) is fine.
$ErrorActionPreference = "Stop"
$data = Join-Path $env:APPDATA "Godot\app_userdata\Cast"
# What a playtest report needs. Left out: models\ (the speech model, large), net_tests\ (dev test runs), garage.cfg.
$items = @("logs", "net", "voice_log.csv", "play_log.csv", "combat_log.csv", "move_lab.csv", "settings.cfg")

if (-not (Test-Path $data)) {
    Write-Host "No Cast logs found at $data" -ForegroundColor Yellow
    exit 1
}
$version = "unknown"
$versionFile = Join-Path $PSScriptRoot "version.txt"
if (Test-Path $versionFile) { $version = (Get-Content $versionFile -TotalCount 1).Trim() }
$name = "Cast_logs_v${version}_$(Get-Date -Format 'yyyy-MM-dd_HHmmss')"

Write-Host "Packing Cast logs from $data ..."
$stage = Join-Path $env:TEMP $name
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    foreach ($item in $items) {
        $src = Join-Path $data $item
        if (-not (Test-Path $src)) { continue }
        try { Copy-Item -Path $src -Destination $stage -Recurse -Force }
        catch { Write-Host "  Skipped $item ($($_.Exception.Message))" -ForegroundColor Yellow }
    }
    # Next to the game; the Desktop when that folder is read-only (Program Files).
    $outDir = $PSScriptRoot
    try { [IO.File]::WriteAllText((Join-Path $outDir ".pack_logs_probe"), ""); Remove-Item (Join-Path $outDir ".pack_logs_probe") }
    catch { $outDir = [Environment]::GetFolderPath("Desktop") }
    $zip = Join-Path $outDir "$name.zip"
    # Entry by entry: PowerShell 5.1's CreateFromDirectory writes `\` into entry names, which other unzippers misread.
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -File -Recurse) {
            $entry = "$name/" + $f.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose() }
} finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Saved $zip ($mb MB)" -ForegroundColor Green
Write-Host "Send this file to whoever runs the playtest."
Start-Process explorer.exe -ArgumentList "/select,`"$zip`""
