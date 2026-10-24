# PulsRig - Temperatur des Prozessors. Wird von PulsRig.ps1 nach PulsRig-Hardware.ps1 eingebunden.
#
# Gelesen wird in PulsRig-Temperatur.cs: über LibreHardwareMonitor (Ordner "Sensoren") mit dem Treiber PawnIO oder,
# falls es läuft, aus Core Temp. Die Messschleife der Sensoren (PulsRig-Hardware.ps1) fragt den Wert jede Sekunde ab.
# PawnIO installiert PulsRig nie von selbst: Erst ein Klick auf "Freischalten" lädt das offizielle, signierte Setup
# in einer fest vorgegebenen Fassung, prüft Größe, Prüfsumme und Signatur und startet es.

$script:SensorFolder = Join-Path $script:Root 'Sensoren'
$script:CpuTempLoaded = $false
$script:CpuTempSeen = $false        # hat es in dieser Sitzung schon einen Wert gegeben? Dann zeigen die Fenster Kacheln dafür
$script:PawnIoJob = $null
# die geprüfte Fassung des Setups: neuere erst nach eigenem Test eintragen
$script:PawnIoSetup = @{
    Url    = 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe'
    Bytes  = 3410960
    Sha256 = '1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032'
}

# Übersetzt den Baustein einmal und fragt gleich einen ersten Wert ab, damit die Fenster wissen, ob es Kacheln gibt
function Initialize-CpuTemp {
    if (-not $script:CpuTempLoaded) {
        $library = Join-Path $script:SensorFolder 'LibreHardwareMonitorLib.dll'
        if (-not (Test-Path -LiteralPath $library)) { return }
        try {
            if (-not ('PulsRigCpuTemp' -as [type])) { Add-Type -TypeDefinition (Get-AppText 'PulsRig-Temperatur.cs') -ReferencedAssemblies $library, System.Core }
            [PulsRigCpuTemp]::Init($script:SensorFolder)
            $script:CpuTempLoaded = $true
            $sync.CpuTempReady = $true
        }
        catch { Write-AppError $_; return }
    }
    if ($sync.CpuTempDemo) { $script:CpuTempSeen = $true; return }
    try { if (-not [double]::IsNaN([PulsRigCpuTemp]::Read())) { $script:CpuTempSeen = $true } } catch { Write-AppError $_ }
}

# Warum es keinen Wert gibt, als Satz und mit dem nächsten Schritt (Knopf): install, admin oder keiner
function Get-CpuTempHint {
    $status = if ($script:CpuTempLoaded) { "$([PulsRigCpuTemp]::Status)" } else { 'nolib' }
    switch ($status) {
        'nodriver' { @{ Text = 'Windows gibt die Temperatur des Prozessors nicht heraus. PulsRig kann sie mit dem freien Treiber PawnIO lesen; „Freischalten“ installiert ihn über sein offizielles Setup (braucht Adminrechte). Hinweis: Das Anti-Cheat von FACEIT hat PawnIO schon blockiert.'; Action = 'Freischalten'; Do = 'install' } }
        'noadmin' { @{ Text = 'Der Treiber PawnIO ist installiert. Lesen darf PulsRig die Temperatur des Prozessors aber nur mit Adminrechten.'; Action = 'Als Admin neu starten'; Do = 'admin' } }
        'none' { @{ Text = 'PawnIO ist installiert, aber dieser Prozessor meldet keine Temperatur. Läuft Core Temp, übernimmt PulsRig dessen Werte.'; Action = ''; Do = '' } }
        default { @{ Text = 'Die Temperatur des Prozessors gibt Windows nicht heraus, und der Baustein dafür fehlt in diesem Ordner.'; Action = ''; Do = '' } }
    }
}

# Zeile "Was hier fehlt" mit Knopf in der freien Fläche eines Fensters
function Add-CpuTempHint {
    $hint = Get-CpuTempHint
    $text = $hint.Text
    $slot = Add-SettingRow 'Was hier fehlt' $text 0xE946
    $script:CpuTempHintSlot = $slot
    if ($hint.Action) {
        $chip = New-SettingChip $hint.Action $hint.Do
        $chip.Add_Click({ param($sender) try { Invoke-CpuTempAction $sender.Uid } catch { Write-AppError $_ } })
        [void]$slot.Children.Add($chip)
    }
}

function Invoke-CpuTempAction([string]$Do) {
    switch ($Do) {
        'install' { Start-PawnIoSetup }
        'admin' { try { Restart-Elevated; $window.Close() } catch { } }
    }
}

function Set-CpuTempHintText([string]$Text) {
    if ($script:CpuTempHintSlot) { try { $script:CpuTempHintSlot.Parent.FindName('Text').Text = T $Text } catch { } }
    Set-SheetStateText $Text
}

function Start-PawnIoSetup {
    if ($script:PawnIoJob) { return }
    if ($Snapshot) { Set-SheetStateText 'Im Probelauf wird PawnIO nicht installiert'; return }
    try {
        $folder = Join-Path ([IO.Path]::GetTempPath()) 'PulsRig-PawnIO'
        if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force -Confirm:$false }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $file = Join-Path $folder 'PawnIO_setup.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.WebClient
        $client.Headers['User-Agent'] = 'PulsRig'
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({ try { Update-PawnIoSetup } catch { Write-AppError $_ } })
        $script:PawnIoJob = @{ Client = $client; File = $file; Since = Get-Date; Timer = $timer; Step = 'load'; Task = $client.DownloadFileTaskAsync($script:PawnIoSetup.Url, $file) }
        Set-CpuTempHintText 'Lade das Setup von PawnIO …'
        $timer.Start()
    }
    catch {
        $script:PawnIoJob = $null
        Set-CpuTempHintText "Das Laden ließ sich nicht beginnen: $(@("$($_.Exception.Message)" -split "`r?`n")[0])"
    }
}

function Stop-PawnIoSetup([string]$Text) {
    $job = $script:PawnIoJob
    $script:PawnIoJob = $null
    if ($job) { $job.Timer.Stop(); try { $job.Client.Dispose() } catch { } }
    if ($Text) { Set-CpuTempHintText $Text }
}

function Update-PawnIoSetup {
    $job = $script:PawnIoJob
    if (-not $job) { return }
    if ($job.Step -eq 'load') {
        if (-not $job.Task.IsCompleted) {
            if (((Get-Date) - $job.Since).TotalSeconds -gt 180) { $job.Client.CancelAsync() }
            return
        }
        if ($job.Task.Status -ne 'RanToCompletion') { [void]$job.Task.Exception; Stop-PawnIoSetup 'Das Laden hat nicht geklappt. Später noch einmal versuchen.'; return }
        # nur genau die geprüfte Datei mit gültiger Signatur wird gestartet
        $size = (Get-Item -LiteralPath $job.File).Length
        $hash = (Get-FileHash -LiteralPath $job.File -Algorithm SHA256).Hash
        $signature = Get-AuthenticodeSignature -LiteralPath $job.File
        if ($size -ne $script:PawnIoSetup.Bytes -or $hash -ne $script:PawnIoSetup.Sha256 -or $signature.Status -ne 'Valid') {
            try { Remove-Item -LiteralPath $job.File -Force -Confirm:$false } catch { }
            Stop-PawnIoSetup 'Die geladene Datei passt nicht zur geprüften Fassung von PawnIO. Sie wurde gelöscht und nicht gestartet.'
            return
        }
        try {
            $start = @{ FilePath = $job.File; ArgumentList = '-install'; PassThru = $true; ErrorAction = 'Stop' }
            if (-not $script:IsAdmin) { $start.Verb = 'RunAs' }
            $job.Process = Start-Process @start
        }
        catch { Stop-PawnIoSetup 'Das Setup wurde nicht gestartet – die Abfrage von Windows wurde abgelehnt.'; return }
        $job.Step = 'run'
        Set-CpuTempHintText 'Das Setup von PawnIO läuft …'
        return
    }
    if ($job.Process -and -not $job.Process.HasExited) { return }
    try { Remove-Item -LiteralPath (Split-Path -Parent $job.File) -Recurse -Force -Confirm:$false } catch { }
    Stop-PawnIoSetup
    # neu verbinden: die Bibliothek sieht den Treiber erst beim nächsten Öffnen
    try { [PulsRigCpuTemp]::Close() } catch { }
    if (-not [PulsRigCpuTemp]::DriverInstalled()) { Set-CpuTempHintText 'PawnIO ist nicht installiert worden. Das Setup wurde wohl abgebrochen.'; return }
    Initialize-CpuTemp
    if ($script:CpuTempSeen) {
        Set-SheetStateText 'Freigeschaltet: Die Temperatur des Prozessors wird jetzt gemessen.'
        # das Fenster neu aufbauen, damit die Kacheln dafür erscheinen
        if ($script:Sheet -and $script:Sheet.Title -eq 'Sensoren') { Show-SensorPanel }
    }
    elseif (-not $script:IsAdmin) { Set-CpuTempHintText 'PawnIO ist installiert. Lesen darf PulsRig die Temperatur nur mit Adminrechten: einmal als Admin neu starten.' }
    else { Set-CpuTempHintText 'PawnIO ist installiert, aber der Prozessor meldet noch keine Temperatur. PulsRig einmal neu starten.' }
}

# Kurzer Stand für das Diagnose-Paket
function Get-CpuTempReport {
    # ohne geöffnetes Fenster Sensoren ist der Baustein noch nicht geladen: jetzt nachholen, statt "fehlt" zu melden
    if (-not $script:CpuTempLoaded) { Initialize-CpuTemp }
    if (-not $script:CpuTempLoaded) { return $(if (Test-Path -LiteralPath (Join-Path $script:SensorFolder 'LibreHardwareMonitorLib.dll')) { 'Baustein ließ sich nicht laden' } else { 'Baustein fehlt' }) }
    $value = [PulsRigCpuTemp]::Read()
    $status = "$([PulsRigCpuTemp]::Status)"
    if (-not [double]::IsNaN($value)) { return ('{0:N0} °C über {1} ({2})' -f $value, [PulsRigCpuTemp]::Source, [PulsRigCpuTemp]::Sensor) }
    "kein Wert ($status) · PawnIO $(if ([PulsRigCpuTemp]::DriverInstalled()) { 'installiert' } else { 'fehlt' })"
}
