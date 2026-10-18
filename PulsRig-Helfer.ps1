# PulsRig - Helfer neben der Uhr: einrichten, starten, Zustand anzeigen. Der Helfer selbst steckt in PulsRig.exe
# (PulsRig-Start.cs, Klasse PulsRigHelper) und läuft ohne dieses Fenster; er liest seine Schalter aus den Einstellungen.
#
# Mit Windows starten lässt PulsRig ihn auf zwei Wegen:
#   - mit Adminrechten als Aufgabe "PulsRig Helfer" in der Aufgabenplanung, die beim Anmelden mit höchsten Rechten
#     startet - nur so kann er den Boost bei einem Spielstart ohne Abfrage von Windows einschalten
#   - ohne Adminrechte als normaler Autostart-Eintrag; dann gibt es keinen automatischen Boost
# Beides nur im installierten Programm: Eine Aufgabe mit höchsten Rechten darf nur auf eine Datei unter "Programme"
# zeigen, die niemand ohne Adminrechte austauschen kann.

$script:HelperTask = 'PulsRig Helfer'
$script:HelperRunKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$script:HelperRunName = 'PulsRig-Helfer'

# die Programmdatei, aus der der Helfer startet - nur das installierte PulsRig.exe
function Get-HelperExe {
    if (-not $script:Installed) { return $null }
    $exe = Join-Path $script:Root 'PulsRig.exe'
    if (Test-Path -LiteralPath $exe) { $exe } else { $null }
}

function Test-HelperRunning {
    $mark = $null
    try { $mark = [Threading.Mutex]::OpenExisting('PulsRig-8B6C1F0E-Helfer'); $true } catch { $false } finally { if ($mark) { $mark.Dispose() } }
}

function Test-HelperTask {
    try { [bool](Get-ScheduledTask -TaskName $script:HelperTask -ErrorAction Stop) } catch { $false }
}

# Richtet den Start mit Windows ein oder nimmt ihn zurück, und startet den Helfer, wenn er laufen soll
function Update-Helper {
    $exe = Get-HelperExe
    if (-not $exe) { return }
    if ($script:Settings.Helper) {
        if ($script:IsAdmin) {
            $user = "$env:USERDOMAIN\$env:USERNAME"
            $action = New-ScheduledTaskAction -Execute $exe -Argument '-Helfer'
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
            $options = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName $script:HelperTask -Action $action -Trigger $trigger -Principal $principal -Settings $options -Force | Out-Null
            Remove-HelperRunEntry
        }
        elseif (-not (Test-HelperTask)) {
            $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:HelperRunKey)
            try { $key.SetValue($script:HelperRunName, "`"$exe`" -Helfer") } finally { $key.Close() }
        }
        Start-Helper
    }
    else {
        # der laufende Helfer liest die Einstellung und beendet sich selbst
        if ($script:IsAdmin -and (Test-HelperTask)) { Unregister-ScheduledTask -TaskName $script:HelperTask -Confirm:$false }
        Remove-HelperRunEntry
    }
}

function Remove-HelperRunEntry {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:HelperRunKey, $true)
    if ($key) { try { $key.DeleteValue($script:HelperRunName, $false) } finally { $key.Close() } }
}

function Start-Helper {
    $exe = Get-HelperExe
    if (-not $exe -or -not $script:Settings.Helper -or (Test-HelperRunning)) { return }
    # über die Aufgabe startet er mit höchsten Rechten, sonst mit denen dieses Fensters
    if (Test-HelperTask) { try { Start-ScheduledTask -TaskName $script:HelperTask; return } catch { } }
    Start-Process -FilePath $exe -ArgumentList '-Helfer'
}

# Ein Satz zum Zustand für die Einstellungen
function Get-HelperStatus {
    if (-not (Get-HelperExe)) { return 'Den Helfer gibt es nur im installierten Programm.' }
    if (-not $script:Settings.Helper) { return 'Ausgeschaltet.' }
    $running = Test-HelperRunning
    if (Test-HelperTask) {
        if ($running) { 'Läuft und startet mit Windows - mit Adminrechten, Boost automatisch ist möglich.' } else { 'Startet mit Windows - mit Adminrechten, Boost automatisch ist möglich.' }
    }
    elseif ($running) { 'Läuft ohne Adminrechte: Boost automatisch ist so nicht möglich. PulsRig einmal als Admin starten und den Helfer neu einschalten.' }
    else { 'Startet mit Windows, ohne Adminrechte: Boost automatisch ist so nicht möglich.' }
}

# beim Start des Fensters: soll der Helfer laufen, läuft er auch (etwa nach einem Update)
if ($script:Settings.Helper -and -not $Snapshot) { Invoke-Later 3000 { try { Start-Helper } catch { Write-AppError $_ } } }
