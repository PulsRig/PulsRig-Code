# PulsRig - Probezeit für neue Treiber. Wird von PulsRig.ps1 nach PulsRig-Abstuerze.ps1 eingebunden.
#
# Nach der Laufwerksprüfung beim Start (PulsRig-Verlauf.ps1) liest PulsRig im Hintergrund die Treiberversionen von
# Grafik, Netzwerk, Ton und Speicher-Controllern und das Ereignisprotokoll (dieselbe Abfrage wie "Abstürze").
# Hat sich eine Version seit dem letzten Start geändert - durch PulsRig, Windows Update oder von Hand -, beginnt für
# diesen Treiber eine Probezeit von 7 Tagen. Wann er wirklich installiert wurde, steht im Ereignis 20001 von
# UserPnp; fehlt es, gilt der Zeitpunkt, an dem PulsRig den Wechsel bemerkt hat.
# Bei jedem Start werden die Vorfälle seit dem Wechsel mit den Tagen davor verglichen (Bluescreens und plötzliches
# Ausschalten, beim Grafiktreiber auch seine Aussetzer und Programmabstürze darin). Sind es seitdem mindestens zwei
# und mehr als doppelt so viele pro Tag wie vorher, meldet die Startseite das und bietet die vorige Fassung an.
# Sieben ruhige Tage: bestanden. Alles steht in der Ergebnisdatei unter History.Drivers und History.Probation.

$script:ProbeDays = 7
$script:ProbeClasses = @{ DISPLAY = 'Grafiktreiber'; NET = 'Netzwerktreiber'; MEDIA = 'Audiotreiber'; SCSIADAPTER = 'Speichertreiber'; HDC = 'Speichertreiber' }
$script:ProbeWarnKey = ''

$script:Queries.ProbeCheck = @'
param($a)
$crashes = & ([scriptblock]::Create($a.Crashes)) @{}
$drivers = @()
try {
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY' OR DeviceClass='NET' OR DeviceClass='MEDIA' OR DeviceClass='SCSIADAPTER' OR DeviceClass='HDC'" -ErrorAction Stop |
            Where-Object { "$($_.DeviceID)" -match '^(PCI|HDAUDIO|USB)\\' -and $_.DriverVersion } |
            ForEach-Object { @{ Id = "$($_.DeviceID)"; Name = "$($_.DeviceName)".Trim(); Version = "$($_.DriverVersion)"; Class = "$($_.DeviceClass)" } })
}
catch { }
# wann Windows zuletzt einen Treiber je Gerät installiert hat (Ereignis 20001 von UserPnp, 30 Tage)
$installs = @{}
try {
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-UserPnp'; Id = 20001; StartTime = (Get-Date).AddDays(-30) } -ErrorAction Stop)) {
        foreach ($value in @($e.Properties | ForEach-Object { "$($_.Value)" })) {
            if ($value -match '^(PCI|HDAUDIO|USB)\\' -and -not $installs.ContainsKey($value.ToUpper())) { $installs[$value.ToUpper()] = $e.TimeCreated.Ticks }
        }
    }
}
catch { }
# für "Was hat sich geändert?" (PulsRig-Aenderungen.ps1): Windows-Stand, Energieplan, Programme, Autostart
$windows = ''
try {
    $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $windows = "$($nt.CurrentBuild).$($nt.UBR)" + $(if ($nt.DisplayVersion) { " ($($nt.DisplayVersion))" })
}
catch { }
$plan = ''
try { if ("$(powercfg /getactivescheme)" -match '\((.+)\)') { $plan = $Matches[1].Trim() } } catch { }
$programs = @()
foreach ($path in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    try {
        foreach ($item in @(Get-ItemProperty $path -ErrorAction Stop)) {
            $name = "$($item.DisplayName)".Trim()
            if (-not $name -or $item.SystemComponent -eq 1 -or $item.ParentKeyName -or $name -match '\bKB\d{6,}\b') { continue }
            $programs += @{ Name = $name; Version = "$($item.DisplayVersion)".Trim(); Date = "$($item.InstallDate)".Trim() }
        }
    }
    catch { }
}
$autostart = @()
if ($a.Autostart) {
    try { $autostart = @((& ([scriptblock]::Create($a.Autostart)) @{}).Entries | ForEach-Object { @{ Name = "$($_.Name)"; Enabled = [bool]$_.Enabled } }) } catch { }
}
@{ Crashes = $crashes; Drivers = $drivers; Installs = $installs; Windows = $windows; Plan = $plan; Programs = $programs; Autostart = $autostart }
'@

function Start-ProbeCheck {
    if ($script:Busy -or -not $script:WorkerReady -or (Test-WorkerBusy) -or $script:Query) {
        $script:ProbeTries++
        if ($script:ProbeTries -lt 30) { Invoke-Later 3000 { Start-ProbeCheck } }
        else { Complete-ProbeCheck @{ Error = 'beschäftigt' } }
        return
    }
    $script:DriveCheckRunning = $true
    Start-WorkerJob 'query:ProbeCheck' $script:Queries.ProbeCheck @{ Crashes = $script:Queries.Crashes; Autostart = $script:Queries.Autostart }
}

function Complete-ProbeCheck($Message) {
    $script:DriveCheckRunning = $false
    if (-not $Message.Error -and $Message.Result) {
        try { Update-Probation $Message.Result } catch { Write-AppError $_ }
        try { Add-Snapshot $Message.Result } catch { Write-AppError $_ }
    }
    if ($script:ScanAfterCheck) {
        $script:ScanAfterCheck = $false
        Invoke-Later 300 { Start-Scan }
    }
}

# Vorfälle, die zu einem Treiber zählen: Ticks und Art
function Get-ProbeEvents($Crashes, [string]$Class) {
    $list = @(@($Crashes.Blue) | Where-Object { $_ } | ForEach-Object { [long]$_.When.Ticks })
    $list += @(@($Crashes.Off) | Where-Object { $_ } | ForEach-Object { [long]$_.When.Ticks })
    if ($Class -eq 'DISPLAY') {
        $list += @(@($Crashes.Tdr) | Where-Object { $_ } | ForEach-Object { [long]$_.When.Ticks })
        $list += @(@($Crashes.Apps) | Where-Object { $_ } | ForEach-Object { [long]$_.When.Ticks })
    }
    $list
}

function Update-Probation($Result) {
    $history = $script:History
    if (-not $history.Drivers) { $history.Drivers = @{} }
    $list = @($history.Probation | Where-Object { $_ })
    $first = $history.Drivers.Count -eq 0
    $now = Get-Date
    $installs = $Result.Installs
    foreach ($driver in @($Result.Drivers)) {
        $old = $history.Drivers[$driver.Id]
        if ($old -and "$($old.Version)" -ne "$($driver.Version)" -and -not $first -and $script:ProbeClasses[$driver.Class]) {
            $since = $now.Ticks
            if ($installs -and $installs[$driver.Id.ToUpper()]) { $since = [long]$installs[$driver.Id.ToUpper()] }
            $byPulsRig = $history.LastInstall -and [Math]::Abs($since - [long]$history.LastInstall) -lt [TimeSpan]::FromHours(6).Ticks
            $list = @($list | Where-Object { $_.Id -ne $driver.Id })
            $list += @{ Id = $driver.Id; Name = $driver.Name; Class = $driver.Class; Old = "$($old.Version)"; New = "$($driver.Version)"
                Since = $since; Source = $(if ($byPulsRig) { 'PulsRig' } else { 'Windows' }); Done = $false; Verdict = 'läuft'; After = 0; Before = 0; BeforeDays = 0 }
        }
        $history.Drivers[$driver.Id] = @{ Name = $driver.Name; Version = "$($driver.Version)"; Class = $driver.Class }
    }
    # laufende Probezeiten bewerten
    $windowStart = $now.AddDays(-30).Ticks
    foreach ($entry in @($list | Where-Object { -not $_.Done })) {
        $since = [long]$entry.Since
        $events = @(Get-ProbeEvents $Result.Crashes $entry.Class)
        $after = @($events | Where-Object { $_ -ge $since }).Count
        $beforeStart = [Math]::Max($since - [TimeSpan]::FromDays(14).Ticks, $windowStart)
        $before = @($events | Where-Object { $_ -ge $beforeStart -and $_ -lt $since }).Count
        $beforeDays = [Math]::Max(1, [Math]::Round(($since - $beforeStart) / [TimeSpan]::TicksPerDay))
        $days = ($now.Ticks - $since) / [TimeSpan]::TicksPerDay
        $worse = $after -ge 2 -and ($after / [Math]::Max(1, $days)) -gt 2 * ($before / $beforeDays)
        $entry.After = $after; $entry.Before = $before; $entry.BeforeDays = $beforeDays
        if ($worse) { $entry.Verdict = 'auffällig' }
        elseif ($days -ge $script:ProbeDays) { $entry.Verdict = 'bestanden'; $entry.Done = $true }
        else { $entry.Verdict = 'läuft' }
        # nach 14 Tagen endet auch eine auffällige Probezeit; der Befund bleibt im Absturz-Fenster sichtbar
        if ($days -ge 14) { $entry.Done = $true }
    }
    if ($list.Count -gt 20) { $list = $list[-20..-1] }
    $history.Probation = $list
    Save-HardwareResults
    Update-ProbeWarn
}

function Get-ProbeClassName([string]$Class) { if ($script:ProbeClasses[$Class]) { $script:ProbeClasses[$Class] } else { 'Treiber' } }
function Format-ProbeDay([long]$Ticks) { ([datetime]$Ticks).ToString('dd.MM.') }

# die Probezeiten, die etwas zu sagen haben: laufend, auffällig oder seit höchstens 7 Tagen bestanden
function Get-ProbeEntries {
    $now = (Get-Date).Ticks
    @($script:History.Probation | Where-Object { $_ -and (-not $_.Done -or $_.Verdict -eq 'auffällig' -or ($now - [long]$_.Since) -lt [TimeSpan]::FromDays(14).Ticks) } |
        Sort-Object { [long]$_.Since } -Descending)
}

function Update-ProbeWarn {
    if (-not $ui.ProbeWarn) { return }
    $bad = @(Get-ProbeEntries | Where-Object { $_.Verdict -eq 'auffällig' -and -not $_.Done } | Sort-Object { if ($_.Class -eq 'DISPLAY') { 0 } else { 1 } })
    if ($bad.Count -eq 0) { $ui.ProbeWarn.Visibility = 'Collapsed'; return }
    $entry = $bad[0]
    $key = "$($entry.Id)|$($entry.New)|$($entry.After)"
    if ($key -eq $script:Settings.ProbeWarnHidden) { $ui.ProbeWarn.Visibility = 'Collapsed'; return }
    $script:ProbeWarnKey = $key
    $script:ProbeWarnEntry = $entry
    $ui.ProbeWarnTitle.Text = T "Seit dem neuen $(Get-ProbeClassName $entry.Class) $($entry.After) Abstürze oder Aussetzer"
    $ui.ProbeWarnText.Text = T (Get-ProbeText $entry)
    if ($ui.ProbeWarn.Visibility -ne 'Visible') {
        $ui.ProbeWarn.Visibility = 'Visible'
        if ($script:Settings.Animations) { Start-Reveal $ui.ProbeWarn 0 10 360 }
    }
}

# "Neu seit 14.10. (Version 32.0.15.6094, vorher 32.0.15.5612). In den 14 Tagen davor: keine. Die vorige Fassung zurückholen?"
function Get-ProbeText($Entry) {
    $before = if ($Entry.Before -eq 0) { "In den $($Entry.BeforeDays) Tagen davor: keine." } else { "In den $($Entry.BeforeDays) Tagen davor: $($Entry.Before)." }
    "$($Entry.Name), neu seit $(Format-ProbeDay $Entry.Since) (Version $($Entry.New), vorher $($Entry.Old)). $before Die vorige Fassung zurückholen?"
}

# vorige Fassung: aus den Sicherungen von PulsRig, sonst über "Vorheriger Treiber" im Geräte-Manager
function Invoke-ProbeRollback {
    if (Test-DriverBackups) {
        if ($script:Sheet) { Close-Sheet }
        Invoke-Later 300 { Open-ToolDialog 'Restore' }
        return
    }
    try { Start-Process devmgmt.msc } catch { }
    $hint = 'Im Geräte-Manager das Gerät doppelklicken, dann Treiber → Vorheriger Treiber'
    if ($script:Sheet) { Set-SheetStateText $hint } else { Set-Status $hint 'Accent' }
}

$ui.ProbeWarnOpen.Add_Click({ try { Invoke-ProbeRollback } catch { Write-AppError $_ } })
$ui.ProbeWarnHide.Add_Click({
        try {
            $script:Settings.ProbeWarnHidden = $script:ProbeWarnKey
            Save-Settings
            Start-Fade $ui.ProbeWarn 0 220
            Invoke-Later 230 { $ui.ProbeWarn.Visibility = 'Collapsed'; $ui.ProbeWarn.Opacity = 1 }
        }
        catch { Write-AppError $_ }
    })

# Zeilen für das Fenster "Abstürze": laufende und kürzlich beendete Probezeiten
function Get-ProbeRows {
    $rows = @()
    $now = (Get-Date).Ticks
    foreach ($entry in @(Get-ProbeEntries | Select-Object -First 3)) {
        $day = [Math]::Min($script:ProbeDays, [Math]::Floor(($now - [long]$entry.Since) / [TimeSpan]::TicksPerDay) + 1)
        $parts = @("Treiber $($entry.New) seit $(Format-ProbeDay $entry.Since), vorher $($entry.Old)")
        $parts += $(if ($entry.Source -eq 'PulsRig') { 'von PulsRig installiert' } else { 'von Windows Update oder von Hand' })
        $parts += $(if ($entry.Verdict -eq 'bestanden') { 'sieben Tage ohne Auffälligkeiten' } else { "Tag $day von $($script:ProbeDays)" })
        $parts += $(if ($entry.After -eq 0) { 'seitdem keine Abstürze' } elseif ($entry.After -eq 1) { 'seitdem 1 Absturz oder Aussetzer' } else { "seitdem $($entry.After) Abstürze oder Aussetzer" })
        if ($entry.Verdict -eq 'auffällig') { $parts += $(if ($entry.Before -eq 0) { 'davor keine' } else { "davor $($entry.Before) in $($entry.BeforeDays) Tagen" }) }
        $state, $tone = switch ($entry.Verdict) { 'auffällig' { 'auffällig', 'warn' } 'bestanden' { 'bestanden', 'good' } default { 'läuft', 'accent' } }
        $rows += New-SheetRow -Title "Probezeit: $($entry.Name)" -Sub ($parts -join ' · ') -Glyph 0xE916 -Tone $tone -State $state `
            -Action $(if ($entry.Verdict -eq 'auffällig') { 'Zurückholen' }) -Data @{ Do = 'rollback' }
    }
    $rows
}
