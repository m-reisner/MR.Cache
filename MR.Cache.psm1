#requires -Version 5.1

$script:MRCacheIndexFileName = 'mrcache.xml'

#.EXTERNALHELP MR.Cache.psm1-help.xml
function ConvertTo-MRTimeSpan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Ttl
    )

    if ($Ttl -is [TimeSpan]) {
        Write-Verbose "TTL ist bereits TimeSpan: $Ttl"
        return $Ttl
    }

    if ($Ttl -is [int]) {
        Write-Verbose "TTL ist int (Minuten): $Ttl"
        return [TimeSpan]::FromMinutes($Ttl)
    }

    if ($Ttl -is [string]) {
        $text = $Ttl.Trim()
        Write-Verbose "Versuche TTL-String im Format 'hh:mm:ss' zu interpretieren: '$text'"

        try {
            $ts = [TimeSpan]::ParseExact($text, 'c', [System.Globalization.CultureInfo]::InvariantCulture)
            Write-Verbose "TTL-String als TimeSpan geparst: $ts"
            return $ts
        } catch {
            throw "TTL-Wert '$text' konnte nicht in eine TimeSpan umgewandelt werden. Erwartetes Format: 'hh:mm:ss', z. B. '00:30:00'."
        }
    }

    throw "TTL-Typ '$($Ttl.GetType().FullName)' wird nicht unterstützt. Erlaubt sind: [TimeSpan], [int] (Minuten), [string] im Format 'hh:mm:ss'."
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Get-MRCallerScriptPath {
    [CmdletBinding()]
    param()

    $stack = Get-PSCallStack
    foreach ($frame in $stack) {
        if ([string]::IsNullOrWhiteSpace($frame.ScriptName)) {
            continue
        }
        # Modul-Dateien (.psm1) überspringen
        if ($frame.ScriptName.ToLower().EndsWith('.psm1')) {
            continue
        }
        Write-Verbose "Aufrufendes Script ermittelt: $($frame.ScriptName)"
        return $frame.ScriptName
    }

    Write-Verbose "Kein aufrufendes Script im CallStack gefunden (vermutlich interaktive Konsole)."
    return $null
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Get-MRCachePath {
    [CmdletBinding()]
    param(
        [string]$CachePath,
        [string]$ScriptPath
    )

    if (-not [string]::IsNullOrWhiteSpace($CachePath)) {
        $resolved = (Resolve-Path -Path $CachePath -ErrorAction SilentlyContinue)
        if ($resolved) {
            $CachePath = $resolved.ProviderPath
        }
        Write-Verbose "CachePath explizit vorgegeben: $CachePath"
        if (-not (Test-Path -LiteralPath $CachePath)) {
            Write-Verbose "CachePath existiert nicht, erstelle Ordner: $CachePath"
            New-Item -Path $CachePath -ItemType Directory -Force | Out-Null
        }
        return $CachePath
    }

    $baseFolder = $null

    if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
        $baseFolder = Split-Path -Path $ScriptPath -Parent
        Write-Verbose "Cache-Basisordner aus ScriptPath: $baseFolder"
    } else {
        $callerScript = Get-MRCallerScriptPath
        if ($callerScript) {
            $baseFolder = Split-Path -Path $callerScript -Parent
            Write-Verbose "Cache-Basisordner aus aufrufendem Script: $baseFolder"
        } else {
            # Fallback: aktuelles Verzeichnis (Konsole)
            $baseFolder = (Get-Location).ProviderPath
            Write-Verbose "Cache-Basisordner aus aktuellem Verzeichnis: $baseFolder"
        }
    }

    $cacheFolder = Join-Path -Path $baseFolder -ChildPath '.mrcache'
    if (-not (Test-Path -LiteralPath $cacheFolder)) {
        Write-Verbose "Cache-Ordner existiert nicht, erstelle: $cacheFolder"
        New-Item -Path $cacheFolder -ItemType Directory -Force | Out-Null
    } else {
        Write-Verbose "Cache-Ordner wird verwendet: $cacheFolder"
    }

    return $cacheFolder
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Get-MRCacheIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath
    )

    $indexPath = Join-Path -Path $CachePath -ChildPath $script:MRCacheIndexFileName
    Write-Verbose "Lade Cache-Index: $indexPath"

    if (Test-Path -LiteralPath $indexPath) {
        $index = Import-Clixml -Path $indexPath -ErrorAction SilentlyContinue
        if ($null -eq $index -or -not ($index -is [hashtable])) {
            Write-Verbose "Cache-Index war ungültig oder leer, initialisiere neu."
            $index = @{}
        } else {
            Write-Verbose "Cache-Index geladen. Einträge: $($index.Count)"
        }
    } else {
        Write-Verbose "Cache-Index existiert nicht, initialisiere neuen Index."
        $index = @{}
    }

    return $index
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Save-MRCacheIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Index,
        [Parameter(Mandatory)]
        [string]$CachePath
    )

    $indexPath = Join-Path -Path $CachePath -ChildPath $script:MRCacheIndexFileName
    Write-Verbose "Speichere Cache-Index nach: $indexPath (Einträge: $($Index.Count))"
    $Index | Export-Clixml -Path $indexPath -Force
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Get-MRCacheHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptText
    )

    $normalized = $ScriptText.Trim()

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
    $hashLower = $hash.ToLowerInvariant()

    Write-Verbose "Berechneter Hash für ScriptBlock: $hashLower"

    return $hashLower
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Clear-MRCacheExpired {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Index,
        [Parameter(Mandatory)]
        [string]$CachePath
    )

    $now = Get-Date
    $keysToRemove = @()

    foreach ($key in $Index.Keys) {
        $entry = $Index[$key]
        if ($null -ne $entry -and $entry.PSObject.Properties.Name -contains 'Expires') {
            $expires = [datetime]$entry.Expires
            if ($expires -le $now) {
                Write-Verbose "Cache-Eintrag '$key' ist abgelaufen (Expires: $expires)."
                $keysToRemove += $key
            }
        }
    }

    foreach ($key in $keysToRemove) {
        $entry = $Index[$key]
        if ($entry -and $entry.PSObject.Properties.Name -contains 'CacheFile') {
            $cacheFile = [string]$entry.CacheFile
            if (-not [string]::IsNullOrWhiteSpace($cacheFile) -and (Test-Path -LiteralPath $cacheFile)) {
                Write-Verbose "Lösche abgelaufene Cache-Datei: $cacheFile"
                Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Verbose "Entferne Eintrag '$key' aus dem Index."
        $Index.Remove($key)
    }

    if ($keysToRemove.Count -gt 0) {
        Save-MRCacheIndex -Index $Index -CachePath $CachePath
    } else {
        Write-Verbose "Keine abgelaufenen Cache-Einträge gefunden."
    }
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Use-MRCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object]$Ttl = '00:30:00',

        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [switch]$ForceRefresh,

        # NEU: optionale ID, z.B. ComputerName, UserName, Kombination etc.
        [Parameter()]
        [object]$CacheId
    )

    Write-Verbose "Use-MRCache aufgerufen. TTL='$Ttl', ForceRefresh=$ForceRefresh, CacheId vorhanden: $($PSBoundParameters.ContainsKey('CacheId'))"

    # Cache-Pfad vorbereiten (basierend auf aufrufendem Script oder Konsole)
    $CachePathResolved = Get-MRCachePath -CachePath $CachePath
    Write-Verbose "Verwendetes Cache-Verzeichnis: $CachePathResolved"

    # TTL auf TimeSpan bringen
    $ttlSpan = ConvertTo-MRTimeSpan -Ttl $Ttl
    Write-Verbose "TTL als TimeSpan: $ttlSpan"

    # Index laden (und abgelaufene Einträge aufräumen)
    $index = Get-MRCacheIndex -CachePath $CachePathResolved
    Clear-MRCacheExpired -Index $index -CachePath $CachePathResolved

    # Hash für den Scriptblock + optional CacheId berechnen
    $scriptText = $ScriptBlock.ToString()
    $baseHash   = Get-MRCacheHash -ScriptText $scriptText

    if ($PSBoundParameters.ContainsKey('CacheId')) {
        try {
            $idString = $CacheId | ConvertTo-Json -Depth 5 -Compress
        } catch {
            $idString = [string]$CacheId
        }

        $hashInput = "$baseHash|$idString"
        $hash      = Get-MRCacheHash -ScriptText $hashInput

        Write-Verbose "Verwende CacheId. Basis-Hash: $baseHash, CacheId-String: $idString, kombinierter Hash: $hash"
    } else {
        $hash = $baseHash
        Write-Verbose "Keine CacheId angegeben. Verwende reinen ScriptBlock-Hash: $hash"
    }

    $cacheFile = Join-Path -Path $CachePathResolved -ChildPath ("{0}.xml" -f $hash)
    $now       = Get-Date

    # Prüfen, ob ein gültiger Cache-Eintrag existiert
    $cacheValid = $false
    $entry      = $null

    if (-not $ForceRefresh) {
        if ($index.ContainsKey($hash)) {
            $entry = $index[$hash]
            if ($entry -and $entry.PSObject.Properties.Name -contains 'Expires') {
                $expires = [datetime]$entry.Expires
                Write-Verbose "Gefundener Cache-Eintrag für Hash '$hash' (Expires: $expires)"
                if ($expires -gt $now -and (Test-Path -LiteralPath $cacheFile)) {
                    $cacheValid = $true
                    Write-Verbose "Cache-Eintrag ist gültig und Datei existiert: $cacheFile"
                } else {
                    Write-Verbose "Cache-Eintrag ist ungültig oder Datei fehlt."
                }
            }
        } else {
            Write-Verbose "Kein Cache-Eintrag im Index für Hash '$hash' gefunden."
        }
    } else {
        Write-Verbose "ForceRefresh ist aktiv, Cache wird ignoriert."
    }

    if ($cacheValid) {
        # Aus dem Cache lesen + Statistik ausgeben/aktualisieren
        $lastExecMs = $null
        $hitCount   = 0
        $totalSaved = 0.0

        if ($entry.PSObject.Properties.Name -contains 'LastExecutionMs') {
            $lastExecMs = [double]$entry.LastExecutionMs
        }
        if ($entry.PSObject.Properties.Name -contains 'HitCount') {
            $hitCount = [int]$entry.HitCount
        }
        if ($entry.PSObject.Properties.Name -contains 'TotalSavedMs') {
            $totalSaved = [double]$entry.TotalSavedMs
        }

        if ($null -ne $lastExecMs -and $lastExecMs -gt 0) {
            $savedSec = $lastExecMs / 1000.0
            Write-Verbose ("Cache-Hit. Geschätzte gesparte Zeit in diesem Lauf: {0:N3} Sekunden." -f $savedSec)

            # Statistik aktualisieren
            $hitCount++
            $totalSaved += $lastExecMs

            if (-not ($entry.PSObject.Properties.Name -contains 'HitCount')) {
                $entry | Add-Member -NotePropertyName 'HitCount' -NotePropertyValue $hitCount
            } else {
                $entry.HitCount = $hitCount
            }
            if (-not ($entry.PSObject.Properties.Name -contains 'TotalSavedMs')) {
                $entry | Add-Member -NotePropertyName 'TotalSavedMs' -NotePropertyValue $totalSaved
            } else {
                $entry.TotalSavedMs = $totalSaved
            }

            $totalSec = $totalSaved / 1000.0
            Write-Verbose ("Bisher durch diesen Cache-Eintrag insgesamt gespart: {0:N3} Sekunden (Hits: {1})." -f $totalSec, $hitCount)
        } else {
            Write-Verbose "Cache-Hit. (Keine gespeicherte Ausführungsdauer vorhanden.)"
        }

        $index[$hash] = $entry
        Save-MRCacheIndex -Index $index -CachePath $CachePathResolved

        Write-Verbose "Lese Ergebnis aus Cache: $cacheFile"
        $result = Import-Clixml -Path $cacheFile
        return $result
    }

    # Kein gültiger Cache: Scriptblock ausführen und Ergebnis cachen
    Write-Verbose "Führe ScriptBlock aus, da kein gültiger Cache vorhanden ist."

    $start   = Get-Date
    $result  = & $ScriptBlock
    $end     = Get-Date
    $duration = $end - $start
    $durationMs = [double][math]::Round($duration.TotalMilliseconds, 2)
    $durationSec = $durationMs / 1000.0

    Write-Verbose ("ScriptBlock-Ausführung dauerte {0:N3} Sekunden." -f $durationSec)
    Write-Verbose "Speichere Ergebnis in Cache-Datei: $cacheFile"
    $result | Export-Clixml -Path $cacheFile -Force

    # ggf. alten Eintrag berücksichtigen
    $existing = $null
    if ($index.ContainsKey($hash)) {
        $existing = $index[$hash]
    }

    $created = $now
    if ($existing -and $existing.PSObject.Properties.Name -contains 'Created') {
        try { $created = [datetime]$existing.Created } catch { $created = $now }
    }

    # Index aktualisieren (neue Statistik)
    $entry = [pscustomobject]@{
        Created          = $created
        Expires          = $now.Add($ttlSpan)
        TtlSeconds       = [int][math]::Round($ttlSpan.TotalSeconds)
        CacheFile        = $cacheFile
        LastExecutionMs  = $durationMs
        HitCount         = 0
        TotalSavedMs     = 0.0
    }

    Write-Verbose "Aktualisiere Index für Hash '$hash'. Expires: $($entry.Expires), LastExecutionMs: ${durationMs}ms"
    $index[$hash] = $entry
    Save-MRCacheIndex -Index $index -CachePath $CachePathResolved

    return $result
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Clear-MRCache {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory, ParameterSetName = 'Script')]
        [string]$ScriptPath,

        [Parameter()]
        [string]$CachePath
    )

    if ($PSCmdlet.ParameterSetName -eq 'All') {
        # Cache des aktuellen Scripts (oder der Konsole) löschen
        $CachePathResolved = Get-MRCachePath -CachePath $CachePath
        Write-Verbose "Clear-MRCache -All. Cache-Verzeichnis: $CachePathResolved"

        if (Test-Path -LiteralPath $CachePathResolved) {
            Write-Verbose "Lösche kompletten Cache-Ordner: $CachePathResolved"
            Remove-Item -LiteralPath $CachePathResolved -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Verbose "Cache-Ordner existiert nicht: $CachePathResolved"
        }

        # Ordner ggf. wieder anlegen (leerer Cache)
        Get-MRCachePath -CachePath $CachePathResolved | Out-Null
        return
    }

    # ParameterSet 'Script': Nur Cache-Einträge löschen, die zu Use-MRCache im angegebenen Script gehören
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Das angegebene Script '$ScriptPath' wurde nicht gefunden."
    }

    Write-Verbose "Clear-MRCache -ScriptPath '$ScriptPath'"

    # Cache-Ordner basierend auf dem angegebenen Script
    $CachePathResolved = Get-MRCachePath -CachePath $CachePath -ScriptPath $ScriptPath
    Write-Verbose "Verwendetes Cache-Verzeichnis für dieses Script: $CachePathResolved"

    $index = Get-MRCacheIndex -CachePath $CachePathResolved

    if ($index.Count -eq 0) {
        Write-Verbose "Cache-Index ist leer. Nichts zu löschen."
        return
    }

    # AST des Scripts parsen
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        throw "Fehler beim Parsen des Scripts '$ScriptPath'."
    }

    # Alle Use-MRCache-Aufrufe finden
    $useMRCacheCommands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Use-MRCache'
        }, $true)

    if (-not $useMRCacheCommands -or $useMRCacheCommands.Count -eq 0) {
        Write-Verbose "Keine Use-MRCache-Aufrufe im Script gefunden."
        return
    }

    $hashesToClear = New-Object System.Collections.Generic.HashSet[string]

    foreach ($cmd in $useMRCacheCommands) {
        $scriptBlockAst = $null

        # CommandElements: Name, Parameter, Argumente
        for ($i = 0; $i -lt $cmd.CommandElements.Count; $i++) {
            $elem = $cmd.CommandElements[$i]

            if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                # Expliziter Parameter -ScriptBlock
                if ($elem.ParameterName -eq 'ScriptBlock' -and ($i + 1) -lt $cmd.CommandElements.Count) {
                    $nextElem = $cmd.CommandElements[$i + 1]
                    if ($nextElem -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                        $scriptBlockAst = $nextElem.ScriptBlock
                        break
                    } elseif ($nextElem -is [System.Management.Automation.Language.ScriptBlockAst]) {
                        $scriptBlockAst = $nextElem
                        break
                    }
                }
            } elseif ($elem -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                # Positionaler ScriptBlock
                if (-not $scriptBlockAst) {
                    $scriptBlockAst = $elem.ScriptBlock
                }
            } elseif ($elem -is [System.Management.Automation.Language.ScriptBlockAst]) {
                if (-not $scriptBlockAst) {
                    $scriptBlockAst = $elem
                }
            }
        }

        if ($scriptBlockAst) {
            $scriptText = $scriptBlockAst.Extent.Text
            $hash = Get-MRCacheHash -ScriptText $scriptText
            Write-Verbose "Gefundener Use-MRCache-ScriptBlock im Script. Hash: $hash"
            [void]$hashesToClear.Add($hash)
        }
    }

    if ($hashesToClear.Count -eq 0) {
        Write-Verbose "Keine Hashes aus Use-MRCache-Aufrufen extrahiert. Nichts zu löschen."
        return
    }

    foreach ($hash in $hashesToClear) {
        if ($index.ContainsKey($hash)) {
            $entry = $index[$hash]
            if ($entry -and $entry.PSObject.Properties.Name -contains 'CacheFile') {
                $cacheFile = [string]$entry.CacheFile
                if (-not [string]::IsNullOrWhiteSpace($cacheFile) -and (Test-Path -LiteralPath $cacheFile)) {
                    Write-Verbose "Lösche Cache-Datei für Hash '$hash': $cacheFile"
                    Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Verbose "Cache-Datei für Hash '$hash' existiert nicht mehr: $cacheFile"
                }
            }
            Write-Verbose "Entferne Eintrag '$hash' aus dem Index."
            $index.Remove($hash)
        } else {
            # Fallback: Datei direkt anhand des Hash-Namens löschen, falls vorhanden
            $cacheFile = Join-Path -Path $CachePathResolved -ChildPath ("{0}.xml" -f $hash)
            if (Test-Path -LiteralPath $cacheFile) {
                Write-Verbose "Lösche Cache-Datei ohne Index-Eintrag für Hash '$hash': $cacheFile"
                Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
            } else {
                Write-Verbose "Keine Cache-Datei für Hash '$hash' gefunden."
            }
        }
    }

    Save-MRCacheIndex -Index $index -CachePath $CachePathResolved
}

#.EXTERNALHELP MR.Cache.psm1-help.xml
function Get-MRCacheStats {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CachePath,

        [Parameter()]
        [string]$ScriptPath
    )

    $CachePathResolved = Get-MRCachePath -CachePath $CachePath -ScriptPath $ScriptPath
    $index = Get-MRCacheIndex -CachePath $CachePathResolved

    foreach ($key in $index.Keys) {
        $entry = $index[$key]
        [pscustomobject]@{
            Hash            = $key
            Created         = [datetime]$entry.Created
            Expires         = [datetime]$entry.Expires
            TtlSeconds      = [int]$entry.TtlSeconds
            CacheFile       = [string]$entry.CacheFile
            HitCount        = if ($entry.PSObject.Properties.Name -contains 'HitCount') { [int]$entry.HitCount } else { 0 }
            LastExecutionMs = if ($entry.PSObject.Properties.Name -contains 'LastExecutionMs') { [double]$entry.LastExecutionMs } else { 0.0 }
            TotalSavedMs    = if ($entry.PSObject.Properties.Name -contains 'TotalSavedMs') { [double]$entry.TotalSavedMs } else { 0.0 }
        }
    }
}

Export-ModuleMember -Function Use-MRCache, Clear-MRCache, Get-MRCacheStats
