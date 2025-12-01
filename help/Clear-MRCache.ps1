<#
.SYNOPSIS
Löscht Cache-Dateien vollständig oder selektiv.

.DESCRIPTION
Clear-MRCache ermöglicht das Entfernen von Cache-Dateien im .mrcache-Ordner
des aufrufenden Skripts oder eines angegebenen Skripts.

Zwei Modi stehen zur Verfügung:

-ALL: Löscht den gesamten Cache-Ordner.
-ScriptPath: Analysiert ein Skript, ermittelt alle darin genutzten Use-MRCache-Aufrufe
             und löscht ausschließlich die entsprechenden Cache-Dateien.

Der Cache-Index wird automatisch aktualisiert.

.PARAMETER All
Löscht den kompletten Cache-Ordner für das aktuelle Skript bzw. den angegebenen CachePath.

.PARAMETER ScriptPath
Pfad zu einem PowerShell-Skript. 
Es werden nur die Cache-Dateien gelöscht, die von Use-MRCache innerhalb dieses Skripts verwendet werden.

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
