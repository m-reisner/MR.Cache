[CmdletBinding()]
param(
    # Quellordner, in dem MRCache.psd1 / MRCache.psm1 liegen
    [Parameter()]
    [string]$SourceRoot = $PSScriptRoot,

    # Wenn gesetzt, wird der Zielordner (Version) vorher gelöscht
    [Parameter()]
    [switch]$CleanTarget
)

Clear-Host

Write-Host "=== Lokale Installation von MRCache (ohne PowerShellGet) ===" -ForegroundColor Cyan
Write-Host ""

$moduleName = 'MRCache'

if (-not $SourceRoot) {
    $SourceRoot = Split-Path -Path $PSCommandPath -Parent
}

Write-Host ("Quellordner : {0}" -f $SourceRoot)

# 1) Geeigneten Benutzermodulpfad aus PSModulePath ermitteln
$psModulePaths = $env:PSModulePath -split ';' | Where-Object { $_ -and ($_ -like "$HOME*") }

if (-not $psModulePaths -or $psModulePaths.Count -eq 0) {
    Write-Error "Kein Benutzer-Modulpfad unterhalb von `$HOME in PSModulePath gefunden."
    exit 1
}

# Nimm den ersten Pfad unterhalb von $HOME
$UserModuleRoot = $psModulePaths[0]

Write-Host ("Benutzer-Modulroot (aus PSModulePath): {0}" -f $UserModuleRoot)
Write-Host ("Modulname                       : {0}" -f $moduleName)
Write-Host ""

# Manifest prüfen
$manifestPath = Join-Path -Path $SourceRoot -ChildPath ("{0}.psd1" -f $moduleName)
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Error "Modulmanifest wurde nicht gefunden: $manifestPath"
    exit 1
}

Write-Host ("Manifest   : {0}" -f $manifestPath)
Write-Host "Prüfe Modulmanifest mit Test-ModuleManifest..." -ForegroundColor Yellow

try {
    $manifestInfo = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
} catch {
    Write-Error "Test-ModuleManifest ist fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}

$version = $manifestInfo.Version.ToString()
Write-Host ("Gefundene Version: {0}" -f $version) -ForegroundColor Green
Write-Host ""

# Zielpfade aufbauen
if (-not (Test-Path -LiteralPath $UserModuleRoot)) {
    Write-Host "Benutzer-Modulroot existiert nicht, erstelle: $UserModuleRoot" -ForegroundColor Yellow
    New-Item -Path $UserModuleRoot -ItemType Directory -Force | Out-Null
}

$moduleTargetRoot  = Join-Path -Path $UserModuleRoot -ChildPath $moduleName
$targetVersionPath = Join-Path -Path $moduleTargetRoot -ChildPath $version

Write-Host ("Ziel-Modulordner   : {0}" -f $moduleTargetRoot)
Write-Host ("Ziel-Versionsordner: {0}" -f $targetVersionPath)
Write-Host ""

# Ziel bereinigen
if (Test-Path -LiteralPath $targetVersionPath) {
    if ($CleanTarget) {
        Write-Host "CleanTarget ist gesetzt. Lösche Zielordner: $targetVersionPath" -ForegroundColor Yellow
        Remove-Item -LiteralPath $targetVersionPath -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $targetVersionPath -ItemType Directory -Force | Out-Null
    } else {
        Write-Host "Zielordner existiert bereits, Inhalte werden überschrieben." -ForegroundColor Yellow
    }
} else {
    Write-Host "Erstelle Zielordner: $targetVersionPath" -ForegroundColor Yellow
    New-Item -Path $targetVersionPath -ItemType Directory -Force | Out-Null
}

Write-Host ""
Write-Host "Kopiere Moduldateien..." -ForegroundColor Yellow

# Install-Skript selbst nicht mitkopieren
$installScriptName = [System.IO.Path]::GetFileName($PSCommandPath)

$itemsToCopy = Get-ChildItem -Path $SourceRoot -Force | Where-Object {
    $_.Name -ne $installScriptName
}

foreach ($item in $itemsToCopy) {
    $dest = Join-Path -Path $targetVersionPath -ChildPath $item.Name
    Write-Host ("  {0} -> {1}" -f $item.FullName, $dest)
    Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force
}

Write-Host ""
Write-Host ("Lokale Installation abgeschlossen. Modul '{0}' Version {1} wurde installiert unter:" -f $moduleName, $version) -ForegroundColor Green
Write-Host ("  {0}" -f $targetVersionPath)
Write-Host ""
Write-Host "Test auf dieser Maschine:" -ForegroundColor Cyan
Write-Host ("  Remove-Module {0} -ErrorAction SilentlyContinue" -f $moduleName)
Write-Host ("  Import-Module {0} -Force" -f $moduleName)
Write-Host ("  Get-Module {0} -ListAvailable" -f $moduleName)
Write-Host ("  Get-Command -Module {0}" -f $moduleName)
