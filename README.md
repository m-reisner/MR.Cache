# MRCache -- ScriptBlock-Caching für PowerShell

## Übersicht

MRCache ist ein PowerShell-Modul, das umfangreiche oder zeitintensive
Abfragen lokal zwischenspeichert und bei wiederholter Verwendung
automatisch aus dem Cache lädt. Dies spart erhebliche Ausführungszeit
und entlastet Systeme wie Active Directory, SQL, REST-APIs oder
Dateisysteme.

Der Cache wird automatisch skriptbasiert isoliert in einem
`.mrcache`-Ordner neben dem aufrufenden Skript gespeichert.

## Hauptfunktionen

### Use-MRCache

Führt einen ScriptBlock aus und speichert dessen Ergebnis in einer
Cache-Datei.

### Clear-MRCache

Bereinigt Cache-Dateien vollständig oder bezogen auf ein bestimmtes
Skript.

## Installation

``` powershell
Import-Module "MRCache" -Force
```

## Lizenz & Autor

Autor: m-reisner Modul: MRCache
