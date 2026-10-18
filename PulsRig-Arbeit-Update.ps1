# PulsRig - Arbeitsbereich: Treiber laden und installieren. Wird von PulsRig.ps1 als Text geladen.
param($a)
$global:DryRun = $false
$global:OutDir = if ($a.TargetDir) { $a.TargetDir } else { $global:DD_BaseDir }
$stats = @{ Found = 0; Downloaded = 0; Installed = 0; Failed = 0 }
$items = @($global:DD_Items | Where-Object { $a.Ids -contains "$($_.Id)" })
$ready = @()
if ($items.Count -gt 0) { $ready = @(Save-DriverUpdates $global:DD_Session $items $OutDir $stats) }
$nvidiaFile = $null
if ($a.Nvidia -and $global:DD_Nvidia) {
    try { $nvidiaFile = Save-NvidiaDriver $global:DD_Nvidia $OutDir }
    catch { Write-Host "NVIDIA-Download fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red }
    if ($nvidiaFile) { $stats.Downloaded++ } else { $stats.Failed++ }
}
$reboot = $false
if ($ready.Count -gt 0 -or $nvidiaFile) {
    Write-Host ''
    if ($a.RestorePoint) { New-DriverRestorePoint } else { Write-Host 'Wiederherstellungspunkt: in den Einstellungen abgeschaltet.' -ForegroundColor DarkGray }
    if ($ready.Count -gt 0) {
        if ($a.AutoBackup) { try { Backup-ReplacedDrivers $ready $global:DD_Installed $OutDir } catch { } }
        $reboot = Install-DriverUpdates $global:DD_Session $ready $stats
    }
    if ($nvidiaFile) {
        Write-Host 'Starte den NVIDIA-Installer - bitte dem Assistenten folgen ...'
        Start-SignedInstaller $nvidiaFile 'O=NVIDIA Corporation'
        $stats.Installed++
    }
}
@{ Downloaded = $stats.Downloaded; Installed = $stats.Installed; Failed = $stats.Failed; Reboot = [bool]$reboot }
