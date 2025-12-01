# MRCache – ScriptBlock-Caching für PowerShell

## Übersicht
MRCache ist ein PowerShell-Modul, das umfangreiche oder zeitintensive Abfragen
lokal zwischenspeichert und bei wiederholter Verwendung automatisch aus dem
Cache lädt. Dies spart erhebliche Ausführungszeit und entlastet Systeme wie
Active Directory, SQL, REST-APIs oder Dateisysteme.

Der Cache wird automatisch **skriptbasiert isoliert** in einem
`.mrcache`-Ordner neben dem aufrufenden Skript gespeichert.

---

## Hauptfunktionen

### ✅ Use-MRCache
Führt einen ScriptBlock aus und speichert dessen Ergebnis in einer Cache-Datei.
Beim nächsten identischen Aufruf wird das Ergebnis aus dem Cache geladen.

Funktionen:
- Hash-basierter ScriptBlock-Fingerprint
- TTL-Unterstützung (hh:mm:ss)
- Statistik (Hits, gesparte Zeit, letzte Ausführungsdauer)
- Vollständige Verbose-Ausgabe
- Automatische Cache-Ordnererstellung
- Cache pro Skript isoliert

Beispiel:

```powershell
$result = Use-MRCache -Ttl "00:30:00" -ScriptBlock {
    Get-ADComputer -Filter * -Properties *
}

### ✅ Clear-MRCache

Bereinigt Cache-Dateien vollständig oder bezogen auf ein bestimmtes Skript.

Modi:

-All → gesamten Cache löschen

-ScriptPath → nur die Einträge löschen, die in einem Skript verwendet wurden

Beispiele:

Clear-MRCache -All

Clear-MRCache -ScriptPath "C:\Scripts\MeinTool.ps1"

### Statistikfunktionen

Jeder Cache-Eintrag speichert:

LastExecutionMs

HitCount

TotalSavedMs

Beispiel der Verbose-Ausgabe:

Cache-Hit. Geschätzte gesparte Zeit in diesem Lauf: 3.212 Sekunden.
Bisher durch diesen Cache-Eintrag insgesamt gespart: 12.848 Sekunden (Hits: 4).

### Cache-Speicherort

Der Cache liegt immer im Ordner des aufrufenden Skripts:

<ScriptFolder>\.mrcache\
    mrcache.xml
    <hash>.xml


Bei interaktiver Nutzung (Konsole) gilt das aktuelle Arbeitsverzeichnis.

### Installation

PSM1-Datei speichern unter einem Modulnamen:

MRCache\MRCache.psm1


Modul importieren:

Import-Module "MRCache" -Force

### Motivation

Während der Entwicklung werden komplexe Abfragen häufig mehrfach ausgeführt.
Beispiele:

Active Directory Queries

große SQL-Resultsets

REST-API-Aufrufe

Dateisystem-Analysen

Mit MRCache wird jede identische Abfrage einmal ausgeführt und danach
ultraschnell aus einer Cache-Datei geladen.

Dadurch spart man:

Zeit

AD-Last

API-Ressourcen

Rechenleistung

Beispiel: Zeitersparnis im Verbose-Modus
Use-MRCache -Ttl "00:30:00" -Verbose -ScriptBlock {
    Get-ADUser -Filter * -Properties *
}


Ergebnis (Beispiel):

ScriptBlock-Ausführung dauerte 3.514 Sekunden.
Cache-Hit. Geschätzte gesparte Zeit: 3.514 Sekunden.
Bisher insgesamt gespart: 17.570 Sekunden (Hits: 5).

### Lizenz & Autor

Autor: m-reisner
Modul: MRCache
Lizenz: frei verwendbar innerhalb eigener Projekte.