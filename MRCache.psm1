Clear-Host
#requires -Version 5.1

$script:MRCacheIndexFileName = 'mrcache.xml'

<#
Kurze Beschreibung

Konvertiert TTL-Angaben in eine TimeSpan.

Ausführliche Beschreibung

Unterstützt TTL-Werte als:

"hh:mm:ss" (empfohlene Form)

TimeSpan

int (interpretiert als Minuten)

Bei ungültigen Formaten wird ein präziser Fehler ausgelöst.
#>
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

<#
Kurze Beschreibung

Ermittelt den Pfad des Scripts, das Use-MRCache aufruft.

Ausführliche Beschreibung

Analysiert den CallStack und liefert den ersten gültigen Skriptpfad, der nicht Teil eines Moduls ist.
Wenn kein Script gefunden wird (z. B. interaktive Konsole), wird null zurückgegeben.

Damit wird der Cache automatisch in der .mrcache-Struktur des aufrufenden Scripts gespeichert.
#>
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

<#
Kurze Beschreibung

Bestimmt den Speicherort des Cache-Verzeichnisses.

Ausführliche Beschreibung

Ermittelt basierend auf Script-Pfad, optionalem -CachePath oder dem aktuellen Arbeitsverzeichnis den Ort, an dem Cache-Dateien abgelegt werden sollen.
Falls das .mrcache-Verzeichnis nicht existiert, wird es automatisch erstellt.
#>
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

<#
Kurze Beschreibung

Liest die Indexdatei für einen Cache ein.

Ausführliche Beschreibung

Lädt die Datei mrcache.xml aus dem Cache-Ordner.
Bei fehlender oder beschädigter Datei wird ein leerer Index erzeugt.
#>
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

<#
Kurze Beschreibung

Speichert den aktuellen Cache-Index.

Ausführliche Beschreibung

Schreibt die hashtable-basierte Indexstruktur mittels Export-Clixml in die Datei mrcache.xml.
Wird nach jeder Cache-Änderung aufgerufen.
#>
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

<#
Kurze Beschreibung

Berechnet einen Hash für den ScriptBlock-Inhalt.

Ausführliche Beschreibung

Normalisiert den ScriptBlock-Text, erzeugt ein SHA256-Hash und gibt ihn als kleingeschriebene Hex-Zeichenkette zurück.
Dieser Hash definiert die Cache-Datei eindeutig.
#>
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

<#
Kurze Beschreibung

Entfernt automatisch abgelaufene Cache-Einträge.

Ausführliche Beschreibung

Clear-MRCacheExpired wird intern durch Use-MRCache aufgerufen, um Cache-Dateien zu entfernen, deren TTL abgelaufen ist.
Die Funktion liest den Cache-Index, prüft die Ablaufzeiten und löscht alle Dateien, deren Expires-Zeitpunkt in der Vergangenheit liegt.

Der Index wird danach automatisch aktualisiert.

Hinweise

Diese Funktion ist nicht für die direkte Verwendung durch Anwender gedacht.

Sie wird automatisch ausgeführt, wenn Use-MRCache aufgerufen wird.
#>
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

# Ende Hilfsfunktionen
<#
Kurze Beschreibung

Führt einen ScriptBlock aus und speichert das Ergebnis für spätere Aufrufe, um wiederholte teure Abfragen zu vermeiden.

Ausführliche Beschreibung

Use-MRCache führt einen angegebenen ScriptBlock aus und speichert dessen Ergebnis in einer Cache-Datei innerhalb des .mrcache-Ordners des aufrufenden Skripts.
Beim nächsten Aufruf mit identischem ScriptBlock wird der Cache anhand eines SHA256-Hashes erkannt und – sofern die TTL noch gültig ist – das gespeicherte Ergebnis zurückgegeben, ohne den ScriptBlock erneut auszuführen.

Die Funktion erstellt zusätzlich einen Index mit Ablaufzeiten, Laufzeitstatistiken, Hit-Zählern und kumulierter Zeitersparnis.
Damit lassen sich aufwendige AD-Abfragen oder große Datenabzüge beim Entwickeln erheblich beschleunigen.

Wichtigste Funktionen

Hash-basierter ScriptBlock-Fingerprint

Cache-Dateien pro Script automatisch getrennt

TTL-Überwachung

Statistik: ExecutionTime, HitCount, TotalSavedMs

Verbose-Ausgabe für Analyse der Cache-Nutzung

Parameterbeschreibung

-ScriptBlock (erforderlich)
Der auszuführende Code, dessen Ergebnis gecacht werden soll.

-Ttl (optional, Standard „00:30:00“)
Gültigkeitsdauer im Format hh:mm:ss oder als TimeSpan/int.

-CachePath (optional)
Optionaler Pfad für den Cache, ansonsten automatisch .mrcache im Script-Ordner.

-ForceRefresh
Ignoriert vorhandene Cache-Dateien und führt den ScriptBlock neu aus.

-Verbose
Zeigt detaillierte Statusmeldungen, inkl. Zeitersparnis.
#>
<#
.SYNOPSIS
Führt einen ScriptBlock aus und speichert dessen Ergebnis im Cache.

.DESCRIPTION
Use-MRCache führt den angegebenen ScriptBlock aus und speichert das Ergebnis
in einer Cache-Datei im .mrcache-Ordner des aufrufenden Skripts.

Beim nächsten Aufruf mit identischem ScriptBlock wird das Ergebnis anhand
eines Hash-Wertes aus der Cache-Datei geladen, sofern die TTL noch gültig ist.
Dies spart Ausführungszeit bei wiederholten, ressourcenintensiven Abfragen.

Die Funktion erfasst zusätzlich statistische Werte wie:
- LastExecutionMs (letzte echte Laufzeit)
- HitCount       (Anzahl Cache-Treffer)
- TotalSavedMs   (gesamt eingesparte Zeit)

.PARAMETER ScriptBlock
Der auszuführende PowerShell-Code, dessen Ergebnis gecacht werden soll.

.PARAMETER Ttl
Gültigkeitsdauer des Cache-Eintrags im Format hh:mm:ss.
Akzeptiert auch TimeSpan oder int (Minuten).
Standard: 00:30:00

.PARAMETER CachePath
Optionaler benutzerdefinierter Pfad für den Cache.
Standard: .mrcache im Ordner des aufrufenden Skripts.

.PARAMETER ForceRefresh
Ignoriert vorhandene Cache-Dateien und führt den ScriptBlock neu aus.

.EXAMPLE
Use-MRCache -Ttl "00:30:00" -ScriptBlock {
    Get-ADUser -Filter * -Properties SamAccountName
}

Lädt die Daten aus dem Cache, falls vorhanden und gültig.
Andernfalls wird die Abfrage ausgeführt und das Ergebnis gespeichert.

.EXAMPLE
Use-MRCache -ForceRefresh -ScriptBlock {
    Get-ADComputer -Filter *
}

Erzwingt die Neubefüllung des Cache-Eintrags.

.OUTPUTS
Gibt das Ergebnis des ScriptBlocks zurück, entweder live ausgeführt
oder aus dem Cache.

.NOTES
Autor: m-reisner
Modul: MRCache
#>
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
        [switch]$ForceRefresh
    )

    Write-Verbose "Use-MRCache aufgerufen. TTL='$Ttl', ForceRefresh=$ForceRefresh"

    # Cache-Pfad vorbereiten (basierend auf aufrufendem Script oder Konsole)
    $CachePathResolved = Get-MRCachePath -CachePath $CachePath
    Write-Verbose "Verwendetes Cache-Verzeichnis: $CachePathResolved"

    # TTL auf TimeSpan bringen
    $ttlSpan = ConvertTo-MRTimeSpan -Ttl $Ttl
    Write-Verbose "TTL als TimeSpan: $ttlSpan"

    # Index laden (und abgelaufene Einträge aufräumen)
    $index = Get-MRCacheIndex -CachePath $CachePathResolved
    Clear-MRCacheExpired -Index $index -CachePath $CachePathResolved

    # Hash für den Scriptblock berechnen
    $scriptText = $ScriptBlock.ToString()
    $hash = Get-MRCacheHash -ScriptText $scriptText

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

            # Felder sicherstellen
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

<#
Kurze Beschreibung

Entfernt Cache-Dateien vollständig oder selektiv basierend auf einem Script.

Ausführliche Beschreibung

Clear-MRCache löscht Cache-Dateien aus dem .mrcache-Ordner.
Es gibt zwei Modi:

-All
Entfernt den gesamten Cache-Ordner des aufrufenden Scripts (oder des angegebenen Cache-Pfads).
Danach wird der leere Ordner automatisch neu erstellt.

-ScriptPath
Analysiert ein angegebenes PowerShell-Script, extrahiert alle darin enthaltenen Use-MRCache-Aufrufe, berechnet deren Hashes und löscht ausschließlich die zugehörigen Cache-Dateien.
Der Cache anderer Scripts bleibt dabei unverändert.

Der zugehörige Cache-Index wird entsprechend aktualisiert.

Parameterbeschreibung

-All
Löscht den vollständigen Cache für das aktuelle Script oder den angegebenen Cache-Pfad.

-ScriptPath
Nur Cache-Einträge löschen, die im angegebenen Script durch Use-MRCache verwendet werden.

-CachePath (optional)
Falls der Cache an einem benutzerdefinierten Ort liegt.

-Verbose
Gibt detaillierte Auskunft über gelöschte Dateien und geänderte Index-Einträge.
#>
<#
.SYNOPSIS
Löscht Cache-Dateien vollständig oder selektiv.

.DESCRIPTION
Clear-MRCache ermöglicht das Entfernen von Cache-Dateien im .mrcache-Ordner
des aufrufenden Skripts oder eines angegebenen Skripts.

- Mit -All wird der gesamte Cache-Ordner gelöscht.
- Mit -ScriptPath werden nur die Cache-Dateien entfernt, die durch
  Use-MRCache im angegebenen Skript verwendet wurden.

Der Cache-Index wird automatisch aktualisiert.

.PARAMETER All
Löscht den kompletten Cache-Ordner für das aktuelle Skript bzw. den angegebenen CachePath.

.PARAMETER ScriptPath
Pfad zu einem PowerShell-Skript.
Es werden nur die Cache-Dateien gelöscht, die von Use-MRCache innerhalb
dieses Skripts verwendet werden.

.PARAMETER CachePath
Optional: benutzerdefinierter Cache-Speicherort.

.EXAMPLE
Clear-MRCache -All

Löscht den gesamten Cache des aktuellen Skripts.

.EXAMPLE
Clear-MRCache -ScriptPath "C:\Scripts\MeinScript.ps1"

Bereinigt nur die Cache-Einträge, die in MeinScript.ps1 verwendet werden.

.OUTPUTS
Kein Rückgabewert.

.NOTES
Autor: m-reisner
Modul: MRCache
#>
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

<#
.SYNOPSIS
Zeigt Statistiken zu den Cache-Einträgen an.

.DESCRIPTION
Liest den Cache-Index mrcache.xml und gibt pro Eintrag ein Objekt mit
Hash, Created, Expires, HitCount, LastExecutionMs und TotalSavedMs zurück.

.PARAMETER CachePath
Optional: benutzerdefinierter Cache-Speicherort.

.EXAMPLE
Get-MRCacheStats

Gibt alle Cache-Einträge des aktuellen Skripts zurück.

.EXAMPLE
Get-MRCacheStats -CachePath "C:\Temp\CustomCache"

Liest den Cache-Index aus einem benutzerdefinierten Ordner.

.OUTPUTS
[pscustomobject]
#>
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
