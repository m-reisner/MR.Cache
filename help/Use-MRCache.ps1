<#
.SYNOPSIS
Führt einen ScriptBlock aus und speichert dessen Ergebnis im Cache.

.DESCRIPTION
Use-MRCache führt den angegebenen ScriptBlock aus und speichert das Ergebnis
in einer Cache-Datei im .mrcache-Ordner des aufrufenden Skripts.

Beim nächsten Aufruf mit identischem ScriptBlock wird das Ergebnis anhand
eines Hash-Wertes aus der Cache-Datei geladen, sofern die TTL noch gültig ist.
Dies spart erhebliche Ausführungszeit bei wiederholten, ressourcenintensiven
Abfragen.

Die Funktion erfasst zusätzlich statistische Werte wie:
- LastExecutionMs (letzte echte Laufzeit)
- HitCount (Anzahl Cache-Treffer)
- TotalSavedMs (gesamt eingesparte Zeit)

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
Gibt das Ergebnis des ScriptBlocks zurück, entweder live ausgeführt oder aus dem Cache.

.NOTES
Autor: m-reisner
Modul: MRCache
#>
