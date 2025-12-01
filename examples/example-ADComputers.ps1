Clear-Host

# Beispiel: AD-Computerliste mit MRCache cachen

# Modul laden (falls im Standardmodulpfad installiert)
Import-Module MRCache -Force

Write-Host "Starte Beispiel: AD-Computer-Abfrage mit MRCache..." -ForegroundColor Cyan

$ttl = '00:30:00'

$computers = Use-MRCache -Ttl $ttl -Verbose -ScriptBlock {
    Get-ADComputer -Filter { (OperatingSystem -like "Windows 10*") -and (Enabled -eq $true) } `
        -Properties Name, OperatingSystem, Enabled |
    Select-Object Name, OperatingSystem, Enabled |
    Where-Object {
        ($_.Name -notlike "*ALT")   -and
        ($_.Name -notlike "*OLD")   -and
        ($_.Name -notlike "*NEU")   -and
        ($_.Name -notlike "*NEW")   -and
        ($_.Name -notmatch "FERTIG") -and
        ($_.Name -notmatch "TEST")   -and
        ($_.Name -notmatch "IKT")
    }
}

Write-Host ""
Write-Host ("Anzahl gefundener Computer: {0}" -f ($computers.Count)) -ForegroundColor Green

Write-Host ""
Write-Host "Aktuelle Cache-Statistik:" -ForegroundColor Cyan
Get-MRCacheStats | Format-Table -AutoSize

Write-Host ""
Write-Host "Hinweis: Skriptpfad wird für Clear-MRCache verwendet, um nur diesen Cache zu löschen." -ForegroundColor Yellow
$scriptPath = $PSCommandPath

# Beispiel zum selektiven Löschen (auskommentiert lassen, nur als Demo):
# Clear-MRCache -ScriptPath $scriptPath -Verbose
