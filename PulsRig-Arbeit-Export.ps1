# PulsRig - Arbeitsbereich: sichert das Treiberpaket eines einzelnen Geräts. Wird von PulsRig.ps1 als Text geladen.
param($a)
$target = Join-Path $a.TargetDir ('Einzeltreiber_{0}_{1:yyyy-MM-dd_HHmm}' -f ($a.Inf -replace '\.inf$', ''), (Get-Date))
Write-Host "Sichere den Treiber von `"$($a.Name)`" ($($a.Inf)) ..."
New-Item -ItemType Directory -Path $target -Force | Out-Null
& pnputil.exe /export-driver $a.Inf $target | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Die Sicherung ist fehlgeschlagen (pnputil-Code $LASTEXITCODE)." -ForegroundColor Red
    return @{ Failed = $true }
}
Write-Host "Gespeichert: $target" -ForegroundColor Green
Write-Host "Zurückspielen bei Bedarf: pnputil /add-driver `"$target\*.inf`" /subdirs /install"
@{ Failed = $false }
