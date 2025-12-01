Clear-Host

$sw = [System.Diagnostics.Stopwatch]::StartNew()

Import-Module './MRCache.psm1' -Force

$computers = Use-MRCache -Verbose -ScriptBlock {
    Get-ADComputer -Filter { (Operatingsystem -like "Windows 11*") -and (Enabled -eq $true) } -Properties Name,Operatingsystem,Enabled |
    Select-Object Name, Operatingsystem, Enabled |
    Where-Object {
        ($_.Name -notlike "*ALT")    -and
        ($_.Name -notlike "*OLD")    -and
        ($_.Name -notlike "*NEU")    -and
        ($_.Name -notlike "*NEW")    -and
        ($_.Name -notmatch "FERTIG") -and
        ($_.Name -notmatch "TEST")   -and
        ($_.Name -notmatch "IKT")
    }
}

$computers | Format-Table

$sw.Stop()
Write-Host "Elapsed:"
Write-Host ("  Ticks      : {0}" -f $sw.ElapsedTicks)
Write-Host ("  ms         : {0} ms" -f $sw.ElapsedMilliseconds)
$elapsed = $sw.Elapsed
Write-Host ("  Formatiert: {0:00}:{1:00}:{2:00}.{3:000}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds, $elapsed.Milliseconds)