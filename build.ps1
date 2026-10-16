# build.ps1 - import the project and run the full test gate.
# (No export step yet: the POC runs from the editor / `.\run.ps1`.)
.  "$PSScriptRoot\godot_env.ps1"
$godot = Resolve-CastGodot
Write-Host "Engine: $godot" -ForegroundColor DarkCyan
Write-Host "Importing project..." -ForegroundColor Cyan
Invoke-CastImport $godot
& "$PSScriptRoot\test_runner.ps1" -TestAll -NoImport
exit $LASTEXITCODE
