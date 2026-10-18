# PulsRig - Verlauf der Laufwerke und Hinweis auf der Startseite. Wird von PulsRig.ps1 nach PulsRig-Hardware.ps1 eingebunden.
#
# Verlauf: Bei jedem Start liest PulsRig die Laufwerke einmal im Hintergrund (dieselbe Abfrage wie das Fenster
# "Laufwerke") und schreibt je Laufwerk einen Eintrag pro Tag mit: Störungen der letzten 30 Tage, Zustand, Temperatur
# (nur mit Adminrechten) und Abnutzung. Jede Tempomessung kommt dazu. Alles steht in der Ergebnisdatei unter "History";
# der Reiter "Verlauf" im Fenster "Laufwerke" zeigt, ob etwas schlechter wird.
#
# Hinweis: Meldet ein Laufwerk Störungen, einen schlechten Zustand oder ist es bei der Messung auffällig langsam bzw.
# deutlich langsamer als früher, erscheint auf der Startseite ein Hinweis. Weggeklickt bleibt er weg, bis sich etwas
# ändert (neue Störung, neue Messung) - die Kennung dafür steht in der Einstellung DriveWarnHidden.

$script:History = @{ Disks = @{}; Speed = @{} }
$script:LastDrives = $null
$script:DriveWarnKey = ''
$script:DriveCheckTries = 0
$script:DriveCheckRunning = $false
$script:ScanAfterCheck = $false

# --- Verlauf: speichern und einlesen -------------------------------------------

function ConvertTo-HistoryEntry($Object) {
    $entry = @{}
    foreach ($property in $Object.PSObject.Properties) { $entry[$property.Name] = $property.Value }
    $entry
}

function Import-History {
    $saved = $script:SavedHistory
    try {
        if ($saved -and $saved.Disks) {
            foreach ($property in $saved.Disks.PSObject.Properties) { $script:History.Disks["$($property.Name)"] = @($property.Value | Where-Object { $_ } | ForEach-Object { ConvertTo-HistoryEntry $_ }) }
        }
        if ($saved -and $saved.Speed) {
            foreach ($property in $saved.Speed.PSObject.Properties) { $script:History.Speed["$($property.Name)"] = @($property.Value | Where-Object { $_ } | ForEach-Object { ConvertTo-HistoryEntry $_ }) }
        }
        # Treiberstände und Probezeiten (PulsRig-Probezeit.ps1)
        if ($saved -and $saved.Drivers) {
            $script:History.Drivers = @{}
            foreach ($property in $saved.Drivers.PSObject.Properties) { $script:History.Drivers["$($property.Name)"] = ConvertTo-HistoryEntry $property.Value }
        }
        if ($saved -and $saved.Probation) { $script:History.Probation = @($saved.Probation | Where-Object { $_ } | ForEach-Object { ConvertTo-HistoryEntry $_ }) }
        if ($saved -and $saved.LastInstall) { $script:History.LastInstall = [long]$saved.LastInstall }
        # Läufe des Benchmarks (PulsRig-Benchmark.ps1); die Umstände (X) bleiben, wie sie aus der Datei kommen
        # Messpunkte der Staub-Warnung (PulsRig-Verschleiss.ps1)
        if ($saved -and $saved.Thermal) { $script:History.Thermal = @($saved.Thermal | Where-Object { $_ -and $_.D } | ForEach-Object { ConvertTo-HistoryEntry $_ }) }
        if ($saved -and $saved.Benchmarks) { $script:History.Benchmarks = @($saved.Benchmarks | Where-Object { $_ -and $_.D } | ForEach-Object { ConvertTo-HistoryEntry $_ }) }
        # Tagesbilder für "Was hat sich geändert?" (PulsRig-Aenderungen.ps1)
        if ($saved -and $saved.Snapshots) {
            $script:History.Snapshots = @($saved.Snapshots | Where-Object { $_ -and $_.D } | ForEach-Object {
                    @{ D = "$($_.D)"; Windows = "$($_.Windows)"; Plan = "$($_.Plan)"; Programs = @($_.Programs); Autostart = @($_.Autostart); Drivers = @($_.Drivers) } })
        }
    }
    catch { Write-AppError $_ }
    # die Messungen von vor dem Verlauf zählen als erster Eintrag
    foreach ($letter in @($script:DriveSpeed.Keys)) {
        $result = $script:DriveSpeed[$letter]
        if ($result -and -not $result.Error -and -not $script:History.Speed[$letter]) { $script:History.Speed[$letter] = @(New-SpeedEntry $result) }
    }
}

function New-SpeedEntry($Result) {
    @{
        D = $(if ($Result.Date) { "$($Result.Date)" } else { (Get-Date).ToString('dd.MM.yyyy') })
        R = [Math]::Round([double]$Result.Read, 1)
        W = [Math]::Round([double]$Result.Write, 1)
        S = [Math]::Round([double]$Result.Small, 1)
    }
}

# wird von Save-DriveSpeed aufgerufen, bevor die Ergebnisdatei geschrieben wird
function Add-SpeedHistory($Result) {
    if (-not $Result -or $Result.Error -or -not $Result.Letter) { return }
    $list = @($script:History.Speed["$($Result.Letter)"] | Where-Object { $_ }) + (New-SpeedEntry $Result)
    if ($list.Count -gt 30) { $list = $list[-30..-1] }
    $script:History.Speed["$($Result.Letter)"] = $list
}

# Name und Größe erkennen ein Laufwerk wieder, auch wenn Windows die Nummern neu vergibt
function Get-DiskKey($Disk) { "$($Disk.Name)|$([Math]::Round([double]$Disk.Size / 1GB))" }

function Add-DriveHistory($Result) {
    if (-not $Result) { return }
    $today = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($disk in @($Result.Disks)) {
        $key = Get-DiskKey $disk
        $entry = @{ D = $today; F = [int]$disk.Faults; L = "$($disk.LastFault)"; H = "$($disk.Health)" }
        if ($disk.Temperature) { $entry.T = [int]$disk.Temperature }
        if ($null -ne $disk.Wear) { $entry.W = [int]$disk.Wear }
        $old = @($script:History.Disks[$key] | Where-Object { $_ -and $_.D -eq $today })[0]
        # am selben Tag zählt die höchste Temperatur
        if ($old -and $old.T -and (-not $entry.T -or [int]$old.T -gt $entry.T)) { $entry.T = [int]$old.T }
        $list = @($script:History.Disks[$key] | Where-Object { $_ -and $_.D -ne $today }) + $entry
        if ($list.Count -gt 120) { $list = $list[-120..-1] }
        $script:History.Disks[$key] = $list
    }
    Save-HardwareResults
}

# "2026-10-14" -> "14.10."
function Format-HistoryDay([string]$Day) {
    try { [datetime]::ParseExact($Day, 'yyyy-MM-dd', $null).ToString('dd.MM.') } catch { $Day }
}

function Format-Speed([double]$Value) { if ($Value -lt 10) { '{0:N1}' -f $Value } else { '{0:N0}' -f $Value } }

# --- Verlauf: Reiter im Fenster "Laufwerke" ------------------------------------

# Bewertung eines Laufwerks über die Zeit: Teile für die Unterzeile, Zustand und Farbton.
# Eine Zeile je Laufwerk, damit auch vier Laufwerke ohne Scrollen passen.
function Get-DiskTrend($Disk, $Detailed) {
    $list = @($script:History.Disks[(Get-DiskKey $Disk)] | Where-Object { $_ })
    $parts = @()
    $more = @()      # zweite Zeile: Tempo und wie lange schon mitgeschrieben wird
    $worse = $false
    $first = if ($list.Count) { $list[0] } else { $null }
    $last = if ($list.Count) { $list[-1] } else { $null }
    $since = if ($first) { Format-HistoryDay $first.D } else { '' }

    $faults = [int]$Disk.Faults
    if (@($list | Where-Object { [int]$_.F -gt 0 }).Count -eq 0 -and $faults -eq 0) { $parts += "Störungen: keine seit $since" }
    elseif ($list.Count -gt 1 -and [int]$first.F -ne $faults) {
        $parts += "Störungen: $faults in 30 Tagen, am $since waren es $([int]$first.F)"
        if ($faults -gt [int]$first.F) { $worse = $true }
    }
    else { $parts += "Störungen: $faults in 30 Tagen" }

    $temps = @($list | Where-Object { $_.T })
    if ($temps.Count -gt 0) {
        $max = [int](($temps | ForEach-Object { [int]$_.T } | Measure-Object -Maximum).Maximum)
        $parts += "Temperatur: $([int]$temps[-1].T) °C, höchstens $max °C"
    }
    elseif (-not $Detailed) { $parts += 'Temperatur nur mit Adminrechten' }

    $wear = @($list | Where-Object { $null -ne $_.W })
    if ($wear.Count -gt 0) {
        if ($wear.Count -gt 1 -and [int]$wear[0].W -ne [int]$wear[-1].W) { $parts += "Abnutzung: $([int]$wear[-1].W) %, am $(Format-HistoryDay $wear[0].D) waren es $([int]$wear[0].W) %" }
        else { $parts += "Abnutzung: $([int]$wear[-1].W) %" }
    }

    $slower = $false
    foreach ($letter in @($Disk.Letters)) {
        $speeds = @($script:History.Speed["$letter"] | Where-Object { $_ })
        if ($speeds.Count -eq 0) { continue }
        $now = [double]$speeds[-1].R
        if ($speeds.Count -eq 1) { $more += "$($letter): Lesen $(Format-Speed $now) MB/s am $(([string]$speeds[-1].D).Substring(0, [Math]::Min(6, ([string]$speeds[-1].D).Length)))" }
        else {
            $best = [double](($speeds | ForEach-Object { [double]$_.R } | Measure-Object -Maximum).Maximum)
            $more += "$($letter): Lesen $(Format-Speed $now) MB/s, bestes $(Format-Speed $best) MB/s"
            if ($now -lt $best * 0.6) { $slower = $true }
        }
    }

    $days = $list.Count
    $more += $(if ($days -le 1) { 'mitgeschrieben ab heute' } else { "$days Tage mitgeschrieben" })
    $state, $tone = if ($Disk.Health -in 'Warning', 'Unhealthy') { 'prüfen', 'bad' }
    elseif ($worse) { 'mehr Störungen', 'warn' }
    elseif ($slower) { 'langsamer', 'warn' }
    elseif ($faults -gt 0) { 'auffällig', 'warn' }
    elseif ($days -le 1) { 'ab heute', '' }
    else { 'unverändert', 'good' }
    @{ Text = ($parts -join ' · ') + "`n" + ($more -join ' · '); State = $state; Tone = $tone }
}

function Show-DriveHistoryTab {
    $data = $script:Sheet.Drives
    $rows = @()
    foreach ($disk in @($data.Disks | Sort-Object { "$(@($_.Letters)[0])" })) {
        $trend = Get-DiskTrend $disk $data.Detailed
        $letters = (@($disk.Letters | ForEach-Object { "$_`:" }) -join ' ')
        $rows += New-SheetRow -Title $(if ($letters) { "$letters · $($disk.Name)" } else { $disk.Name }) -Sub $trend.Text `
            -Glyph 0xE81C -State $trend.State -Tone $trend.Tone
    }
    if ($rows.Count -eq 0) { $rows += New-SheetRow -Title 'Windows hat kein Laufwerk gemeldet' -Glyph 0xE946 }
    Show-SheetList $rows
    Set-SheetStateText 'Bei jedem Start schreibt PulsRig einen Eintrag pro Tag mit, dazu jede Tempomessung'
}

# --- Hinweis auf der Startseite ------------------------------------------------

function Get-DriveWarnings($Result) {
    $list = @()
    $named = @()
    foreach ($disk in @($Result.Disks)) {
        $letters = (@($disk.Letters | ForEach-Object { "$_`:" }) -join ' ')
        $label = if ($letters) { "$letters $($disk.Name)" } else { "$($disk.Name)" }
        if ($disk.Health -in 'Warning', 'Unhealthy') {
            $list += @{ Key = "h|$($disk.Name)|$($disk.Health)"; Title = "$label meldet einen schlechten Zustand"; Text = 'Wichtige Daten sichern und das Laufwerk bald ersetzen.' }
            $named += @($disk.Letters)
        }
        elseif ($disk.Faults -gt 0) {
            $list += @{ Key = "f|$($disk.Name)|$($disk.LastFault)"; Title = "$label ist auffällig"
                Text = "$(if ($disk.Faults -eq 1) { '1 Störung' } else { "$($disk.Faults) Störungen" }) in 30 Tagen, zuletzt $($disk.LastFault). Kabel und Anschluss prüfen, wichtige Daten sichern." }
            $named += @($disk.Letters)
        }
    }
    foreach ($letter in @($script:DriveSpeed.Keys | Sort-Object)) {
        if ($named -contains $letter) { continue }
        $result = $script:DriveSpeed[$letter]
        if (-not $result -or $result.Error) { continue }
        if ($result.Read -lt 25 -or $result.Write -lt 15) {
            $list += @{ Key = "s|$letter|$($result.Date) $($result.Time)"; Title = "$($letter): ist auffällig langsam"; Text = "Lesen $(Format-Speed $result.Read) MB/s bei der letzten Messung. Kabel und Anschluss prüfen." }
            continue
        }
        $speeds = @($script:History.Speed["$letter"] | Where-Object { $_ })
        if ($speeds.Count -gt 1) {
            $best = [double](($speeds | ForEach-Object { [double]$_.R } | Measure-Object -Maximum).Maximum)
            if ($result.Read -lt $best * 0.6) {
                $list += @{ Key = "d|$letter|$($result.Date) $($result.Time)"; Title = "$($letter): liest langsamer als früher"
                    Text = "Lesen $(Format-Speed $result.Read) statt bis zu $(Format-Speed $best) MB/s. Ist das Laufwerk fast voll oder läuft nebenher etwas, noch einmal messen." }
            }
        }
    }
    if ($list.Count -eq 0 -and $Result.Resets -gt 0) {
        $list += @{ Key = "r|$($Result.LastReset)"; Title = $(if ($Result.Resets -eq 1) { 'Windows musste 1-mal die Verbindung zu einem Laufwerk neu aufbauen' } else { "Windows musste $($Result.Resets)-mal die Verbindung zu einem Laufwerk neu aufbauen" })
            Text = "In den letzten 30 Tagen, zuletzt $($Result.LastReset). Häufige Ursachen: Kabel, Anschluss oder ein schwächelndes Laufwerk." }
    }
    $list
}

function Update-DriveWarn($Result) {
    if ($Result) { $script:LastDrives = $Result }
    if (-not $script:LastDrives -or -not $ui.DriveWarn) { return }
    $list = @(Get-DriveWarnings $script:LastDrives)
    $key = (@($list | ForEach-Object { $_.Key }) -join ';')
    if ($list.Count -eq 0 -or $key -eq $script:Settings.DriveWarnHidden) {
        $ui.DriveWarn.Visibility = 'Collapsed'
        return
    }
    $script:DriveWarnKey = $key
    if ($list.Count -eq 1) {
        $ui.DriveWarnTitle.Text = T $list[0].Title
        $ui.DriveWarnText.Text = T $list[0].Text
    }
    else {
        $ui.DriveWarnTitle.Text = T "$($list.Count) Auffälligkeiten bei den Laufwerken"
        $ui.DriveWarnText.Text = T (@($list | ForEach-Object { $_.Title }) -join ' · ')
    }
    if ($ui.DriveWarn.Visibility -ne 'Visible') {
        $ui.DriveWarn.Visibility = 'Visible'
        if ($script:Settings.Animations) { Start-Reveal $ui.DriveWarn 0 10 360 }
    }
}

$ui.DriveWarnOpen.Add_Click({ try { Open-DriveSheet } catch { Write-AppError $_ } })
$ui.DriveWarnHide.Add_Click({
        try {
            $script:Settings.DriveWarnHidden = $script:DriveWarnKey
            Save-Settings
            Start-Fade $ui.DriveWarn 0 220
            Invoke-Later 230 { $ui.DriveWarn.Visibility = 'Collapsed'; $ui.DriveWarn.Opacity = 1 }
        }
        catch { Write-AppError $_ }
    })

# --- Prüfung beim Start --------------------------------------------------------
# Läuft auf dem Arbeitsbereich, sobald er frei ist; ein Klick auf SCAN in dieser Zeit startet den Scan direkt danach.

function Start-DriveCheck {
    if ($script:Busy -or -not $script:WorkerReady -or (Test-WorkerBusy) -or $script:Query) {
        $script:DriveCheckTries++
        if ($script:DriveCheckTries -lt 30) { Invoke-Later 10000 { Start-DriveCheck } }
        return
    }
    $script:DriveCheckRunning = $true
    Start-WorkerJob 'query:DriveCheck' $script:Queries.Drives $null
}

function Complete-DriveCheck($Message) {
    if (-not $Message.Error -and $Message.Result) {
        Set-CardState 'Drives' (Get-DriveCardState $Message.Result)
        Add-DriveHistory $Message.Result
        Update-DriveWarn $Message.Result
    }
    # danach Treiberstände und Abstürze für die Probezeit (PulsRig-Probezeit.ps1); ein wartender Scan kommt erst danach
    $script:ProbeTries = 0
    Invoke-Later 400 { Start-ProbeCheck }
}

Import-History
if (-not $Snapshot) { Invoke-Later 8000 { Start-DriveCheck } }
