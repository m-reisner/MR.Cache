[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository = 'IKT-PSRepository',

    [Parameter()]
    [string]$ApiKeyEnvVar = 'MRREPO_API_KEY',

    [Parameter()]
    [switch]$UseApiKey = $false,

    [Parameter()]
    [switch]$WhatIfPublish
)

Clear-Host

$env:DOTNET_CLI_UI_LANGUAGE = "en_US"

Write-Host "=== MRCache Publish-Skript (Custom Repository, NuGet/.nupkg) ===" -ForegroundColor Cyan
Write-Host ""

$moduleName = 'MRCache'
$moduleRoot = $PSScriptRoot
if (-not $moduleRoot) {
    $moduleRoot = Split-Path -Path $PSCommandPath -Parent
}

Write-Host ("Modulname : {0}" -f $moduleName)
Write-Host ("Modulroot : {0}" -f $moduleRoot)
Write-Host ("Repo      : {0}" -f $Repository)
Write-Host ""

# Manifest suchen: wir erwarten .\<Version>\MRCache.psd1
$manifestFiles = Get-ChildItem -Path $moduleRoot -Recurse -Filter "$moduleName.psd1" -File
if ($manifestFiles.Count -eq 0) {
    Write-Error "Kein Manifest '$moduleName.psd1' unterhalb von '$moduleRoot' gefunden."
    exit 1
}

if ($manifestFiles.Count -gt 1) {
    Write-Host "Mehrere Manifeste gefunden, nehme das erste:" -ForegroundColor Yellow
    $manifestFiles | ForEach-Object { "  " + $_.FullName } | Write-Host
}

$manifestPath = $manifestFiles[0].FullName
Write-Host ("Manifest  : {0}" -f $manifestPath)

$moduleVersionFolder = Split-Path -Path $manifestPath -Parent
Write-Host ("Versionsordner (Manifestordner): {0}" -f $moduleVersionFolder)
Write-Host ""

Write-Host "Prüfe Modulmanifest mit Test-ModuleManifest..." -ForegroundColor Yellow
try {
    $manifestInfo = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
} catch {
    Write-Error "Test-ModuleManifest ist fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}

$version = $manifestInfo.Version.ToString()
Write-Host ("Gefundene Modulversion: {0}" -f $version) -ForegroundColor Green
Write-Host ""

# Repository prüfen
Write-Host ("Prüfe Repository '{0}'..." -f $Repository) -ForegroundColor Yellow
$repo = Get-PSRepository -Name $Repository -ErrorAction SilentlyContinue
if (-not $repo) {
    Write-Error "Repository '$Repository' ist nicht registriert. Bitte zuerst mit Register-PSRepository einrichten."
    exit 1
}

Write-Host ("Repository gefunden: {0} -> {1}" -f $repo.Name, $repo.SourceLocation) -ForegroundColor Green
Write-Host ""

# API-Key (nur falls benötigt)
$apiKey = $null
if ($UseApiKey) {
    Write-Host ("-UseApiKey ist gesetzt. Versuche API-Key aus Umgebungsvariablen '{0}' zu lesen..." -f $ApiKeyEnvVar) -ForegroundColor Yellow
    $apiKey = [Environment]::GetEnvironmentVariable($ApiKeyEnvVar, 'Process')

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host ("Umgebungsvariable '{0}' ist nicht gesetzt oder leer." -f $ApiKeyEnvVar) -ForegroundColor Yellow
        Write-Host "Bitte gib jetzt den API-Key für das Repository ein." -ForegroundColor Yellow
        $secureApiKey = Read-Host -AsSecureString -Prompt "API Key"
        if (-not $secureApiKey) {
            Write-Error "Kein API-Key angegeben. Abbruch."
            exit 1
        }
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey)
        try {
            $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    } else {
        Write-Host ("API-Key wurde aus Umgebungsvariablen '{0}' geladen." -f $ApiKeyEnvVar) -ForegroundColor Green
    }

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Error "API-Key ist leer. Abbruch."
        exit 1
    }
} else {
    Write-Host "-UseApiKey ist NICHT gesetzt. Publish-Module wird ohne NuGetApiKey ausgeführt." -ForegroundColor Yellow
}

# Lokaler Test-Import
Write-Host ""
Write-Host "Importiere Modul lokal zum Test (über Manifest)..." -ForegroundColor Yellow
try {
    Import-Module -Name $manifestPath -Force -ErrorAction Stop
    Write-Host "Modulimport erfolgreich. Funktionen vorhanden:" -ForegroundColor Green
    Get-Command -Module $moduleName | Select-Object Name, CommandType | Format-Table -AutoSize
} catch {
    Write-Error "Import-Module ist fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "Bereit zum Veröffentlichen." -ForegroundColor Cyan
Write-Host ("Modul: {0}, Version: {1}, Repository: {2}" -f $moduleName, $version, $Repository)
Write-Host ""

# Jetzt wichtig: Path = Versionsordner (z.B. ...\MRCache\1.0.0)
$publishParams = @{
    Path        = $moduleVersionFolder
    Repository  = $Repository
    ErrorAction = 'Stop'
}
if ($UseApiKey -and -not [string]::IsNullOrWhiteSpace($apiKey)) {
    $publishParams['NuGetApiKey'] = $apiKey
}

Write-Host "Publish-Module wird mit folgenden Parametern aufgerufen:" -ForegroundColor Yellow
$publishParams.GetEnumerator() | Sort-Object Name | ForEach-Object {
    if ($_.Name -eq 'NuGetApiKey') {
        Write-Host ("  {0} = **** (API-Key gesetzt)" -f $_.Name)
    } else {
        Write-Host ("  {0} = {1}" -f $_.Name, $_.Value)
    }
}
Write-Host ""

if ($WhatIfPublish) {
    Write-Host "[WhatIf] Publish-Module wird NICHT ausgeführt (WhatIfPublish ist gesetzt)." -ForegroundColor Yellow
    exit 0
}

try {
    Write-Host "Starte Publish-Module..." -ForegroundColor Cyan
    Publish-Module @publishParams
    Write-Host ""
    Write-Host ("Publish-Module erfolgreich abgeschlossen. Modul '{0}' Version {1} wurde nach '{2}' veröffentlicht." -f $moduleName, $version, $Repository) -ForegroundColor Green
} catch {
    Write-Error "Publish-Module ist fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}
