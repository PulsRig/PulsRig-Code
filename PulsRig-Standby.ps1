# PulsRig - Standby-Detektiv. Wird von PulsRig.ps1 nach PulsRig-Spielcheck.ps1 eingebunden.
#
# Zwei Fragen in einfachen Worten:
#   "Warum wacht mein PC auf?"  - Ereignis 1 von Power-Troubleshooter (14 Tage): Weckquelle und Zeit, gelesen aus dem
#     XML des Ereignisses (Feldnamen statt übersetzter Texte). Zusammengefasst nach Art: Maus/Tastatur, Netzwerkkarte,
#     geplante Aufgabe (Aufweck-Timer), Netzschalter, anderes Gerät; nächtliches Aufwachen (0 bis 6 Uhr) fällt auf.
#     Dazu, welche Geräte den PC wecken dürfen (powercfg /devicequery wake_armed) und ob Aufweck-Timer erlaubt sind.
#   "Warum geht er nicht in den Standby?" - die Standby-Zeit des Energieplans (bei "Nie" liegt es daran) und was den
#     PC gerade wach hält (powercfg /requests; das gibt Windows nur mit Adminrechten heraus).
# PulsRig ändert hier nichts; die Knöpfe öffnen Geräte-Manager und Energieeinstellungen.

$script:Queries.Standby = @'
param($a)
$r = @{ Wakes = @(); Armed = @(); Timers = $null; Idle = $null; Requests = @(); NeedsAdmin = $false; Log = $true }
# Aufwachen aus dem Standby (Feldnamen aus dem XML, damit die Sprache von Windows keine Rolle spielt)
try {
    foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1; StartTime = (Get-Date).AddDays(-14) } -ErrorAction Stop)) {
        $fields = @{}
        foreach ($node in ([xml]$e.ToXml()).Event.EventData.Data) { $fields["$($node.Name)"] = "$($node.'#text')" }
        $r.Wakes += @{ Ticks = $e.TimeCreated.Ticks; Text = $e.TimeCreated.ToString('dd.MM. HH:mm'); Hour = $e.TimeCreated.Hour
            Source = "$($fields['WakeSourceText'])".Trim(); Type = "$($fields['WakeSourceType'])"; Owner = "$($fields['WakeTimerOwner'])".Trim() }
    }
}
catch { if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $r.Log = $false } }
# Geräte, die den PC wecken dürfen; "NONE"/"KEINE" heißt: keine
try { $r.Armed = @(powercfg /devicequery wake_armed | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^(NONE|KEINE|Keine)$' }) } catch { }
# Werte des Energieplans: die beiden letzten Hex-Zahlen der Ausgabe sind Netzbetrieb und Akku
function Get-PlanValue([string]$Sub, [string]$Setting) {
    try {
        $hex = @([regex]::Matches(((powercfg /query SCHEME_CURRENT $Sub $Setting) -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
        if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[-2], 16) }
    }
    catch { }
    $null
}
$r.Timers = Get-PlanValue 'SUB_SLEEP' 'RTCWAKE'
$r.Idle = Get-PlanValue 'SUB_SLEEP' 'STANDBYIDLE'
# was den PC gerade wach hält (Abschnitte wie "SYSTEM:", Einträge wie "[PROCESS] \Device\...\chrome.exe")
try {
    $lines = @(powercfg /requests 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or -not ($lines -match '^[A-Z]+:\s*$')) { $r.NeedsAdmin = $true }
    else {
        $section = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line -match '^([A-Z]+):$') { $section = $Matches[1]; continue }
            if ($line -match '^\[(\w+)\]\s*(.+)$') {
                $why = if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -and $lines[$i + 1].Trim() -notmatch '^\[|^[A-Z]+:$') { $lines[$i + 1].Trim() } else { '' }
                $r.Requests += @{ Section = $section; Kind = $Matches[1]; Name = (Split-Path -Leaf $Matches[2].Trim()); Why = $why }
            }
        }
    }
}
catch { $r.NeedsAdmin = $true }
$r
'@

function Open-StandbySheet {
    $opened = Open-Sheet @{
        Title    = 'Standby-Detektiv'
        Sub      = 'Warum der PC aufwacht und was ihn wach hält'
        Glyph    = 0xE708
        Tabs     = 'Aufwachen', 'Wach gehalten'
        Link     = 'Neu einlesen'
        Show     = { param($tab) Show-StandbyTab }
        OnAction = { param($item) if ($item.Data) { Invoke-StandbyAction $item.Data.Do } }
        OnLink   = {
            $script:Sheet.Standby = $null
            $ui.SheetChips.Children.Clear()
            Show-StandbyTab
            Start-Query 'Standby' { param($result) Complete-StandbyQuery $result }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese das Ereignisprotokoll …'
    Start-Query 'Standby' { param($result) Complete-StandbyQuery $result }
}

function Invoke-StandbyAction([string]$Do) {
    try {
        switch ($Do) {
            'devmgmt' { Start-Process devmgmt.msc; Set-SheetStateText 'Im Geräte-Manager: Gerät doppelklicken → Energieverwaltung → „Gerät kann den Computer aus dem Standby aktivieren“' }
            'sleep' { Start-Process 'ms-settings:powersleep' }
            'timers' { Start-Process control.exe 'powercfg.cpl,,3'; Set-SheetStateText 'Energieoptionen: Energiesparen → Zeitgeber zur Aktivierung zulassen' }
            'admin' { Restart-Elevated; $window.Close() }
        }
    }
    catch { Set-SheetStateText 'Das ließ sich nicht öffnen' }
}

function Complete-StandbyQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Standby = $Result
    $ui.SheetChips.Children.Clear()
    $wakes = @($Result.Wakes).Count
    $night = @($Result.Wakes | Where-Object { $_.Hour -lt 6 }).Count
    Add-ResultChip $(if ($wakes -eq 1) { '1-mal aufgewacht' } else { "$wakes-mal aufgewacht" }) $(if ($wakes) { 'Accent' } else { 'Good' }) $ui.SheetChips
    if ($night) { Add-ResultChip $(if ($night -eq 1) { '1-mal nachts' } else { "$night-mal nachts" }) 'Warn' $ui.SheetChips }
    if ($Result.Idle -eq 0) { Add-ResultChip 'Standby aus' 'Warn' $ui.SheetChips }
    Show-StandbyTab
}

# Art der Weckquelle: Name, Erklärung, Knopf
function Get-WakeKind($Wake) {
    $text = "$($Wake.Source) $($Wake.Owner)"
    if ($Wake.Owner -or $text -match 'Timer|Zeitgeber|geplante|scheduled|\\Microsoft\\Windows\\') {
        return @{ Key = 'timer'; Title = 'Geplante Aufgabe weckt den PC'; Hint = 'Aufweck-Timer lassen sich in den Energieoptionen abschalten'; Action = 'Energieoptionen'; Do = 'timers'; Glyph = 0xE823 }
    }
    if ($text -match 'Maus|Mouse|Tastatur|Keyboard|HID|Eingabe') {
        return @{ Key = 'input'; Title = 'Maus oder Tastatur weckt den PC'; Hint = 'Schon ein Ruckeln am Tisch reicht. Im Geräte-Manager lässt sich das je Gerät abschalten'; Action = 'Geräte-Manager'; Do = 'devmgmt'; Glyph = 0xE962 }
    }
    if ($text -match 'Ethernet|Network|Netzwerk|Wi-?Fi|WLAN|LAN|Realtek|Killer|Intel\(R\).*Connection') {
        return @{ Key = 'net'; Title = 'Netzwerkkarte weckt den PC'; Hint = 'Wake-on-LAN oder Netzwerkverkehr. Im Geräte-Manager unter Energieverwaltung abschaltbar'; Action = 'Geräte-Manager'; Do = 'devmgmt'; Glyph = 0xE774 }
    }
    if ($text -match 'Power Button|Netzschalter|Ein/Aus|Betriebsschalter') {
        return @{ Key = 'button'; Title = 'Netzschalter'; Hint = 'Der PC wurde von Hand aufgeweckt'; Action = ''; Do = ''; Glyph = 0xE7E8 }
    }
    if (-not "$($Wake.Source)") {
        return @{ Key = 'unknown'; Title = 'Ohne erkennbaren Grund aufgewacht'; Hint = 'Windows nennt keine Quelle; oft ein USB-Gerät oder das BIOS'; Action = 'Geräte-Manager'; Do = 'devmgmt'; Glyph = 0xE946 }
    }
    @{ Key = "dev:$($Wake.Source)"; Title = "$($Wake.Source) weckt den PC"; Hint = 'Im Geräte-Manager unter Energieverwaltung abschaltbar'; Action = 'Geräte-Manager'; Do = 'devmgmt'; Glyph = 0xE772 }
}

function Show-StandbyTab {
    $data = $script:Sheet.Standby
    if (-not $data) { Start-SheetLoader 'Lese das Ereignisprotokoll …'; return }
    $rows = @()
    if ([int]$script:Sheet.Tab -eq 0) {
        $wakes = @($data.Wakes | Sort-Object { [long]$_.Ticks } -Descending)
        if ($wakes.Count -eq 0) {
            $rows += New-SheetRow -Title $(if ($false -eq $data.Log) { 'Das Ereignisprotokoll ist nicht lesbar' } else { 'Kein Aufwachen aus dem Standby in 14 Tagen' }) -Glyph 0xE73E -Tone $(if ($false -eq $data.Log) { '' } else { 'good' }) `
                -Sub $(if ($data.Idle -eq 0) { 'Der PC geht allerdings gar nicht von selbst in den Standby; siehe „Wach gehalten“.' } else { 'Der PC hat geschlafen, bis ihn jemand geweckt hat.' })
        }
        else {
            $groups = [ordered]@{}
            foreach ($wake in $wakes) {
                $kind = Get-WakeKind $wake
                if (-not $groups.Contains($kind.Key)) { $groups[$kind.Key] = @{ Kind = $kind; Wakes = @() } }
                $groups[$kind.Key].Wakes += $wake
            }
            foreach ($group in @($groups.Values | Sort-Object { -$_.Wakes.Count } | Select-Object -First 5)) {
                $list = @($group.Wakes)
                $night = @($list | Where-Object { $_.Hour -lt 6 }).Count
                $names = @($list | ForEach-Object { $(if ($_.Owner) { $_.Owner } else { $_.Source }) } | Where-Object { $_ } | Sort-Object -Unique | Select-Object -First 2)
                $parts = @("$(if ($list.Count -eq 1) { '1-mal' } else { "$($list.Count)-mal" }) in 14 Tagen, zuletzt $($list[0].Text) Uhr")
                if ($names.Count -and $group.Kind.Key -notlike 'dev:*') { $parts += ($names -join ', ') }
                $parts += $group.Kind.Hint
                $rows += New-SheetRow -Title $group.Kind.Title -Sub ($parts -join ' · ') -Glyph $group.Kind.Glyph -Tone $(if ($night) { 'warn' } else { 'accent' }) `
                    -State $(if ($night) { $(if ($night -eq 1) { '1-mal nachts' } else { "$night-mal nachts" }) }) -Action $group.Kind.Action -Data @{ Do = $group.Kind.Do }
            }
        }
        $armed = @($data.Armed)
        $rows += New-SheetRow -Title $(if ($armed.Count -eq 0) { 'Kein Gerät darf den PC wecken' } elseif ($armed.Count -eq 1) { '1 Gerät darf den PC wecken' } else { "$($armed.Count) Geräte dürfen den PC wecken" }) `
            -Sub $(if ($armed.Count) { Join-Names $armed 3 } else { 'Nur Netzschalter und geplante Aufgaben können ihn aufwecken.' }) -Glyph 0xE772 -Action $(if ($armed.Count) { 'Geräte-Manager' }) -Data @{ Do = 'devmgmt' }
        $timer = switch ($data.Timers) { 0 { @('Aufweck-Timer sind aus', 'Geplante Aufgaben können den PC nicht wecken.', 'good') } 1 { @('Aufweck-Timer sind erlaubt', 'Geplante Aufgaben wie Windows Update dürfen den PC wecken.', 'accent') } 2 { @('Nur wichtige Aufweck-Timer', 'Nur wichtige Aufgaben von Windows dürfen den PC wecken, etwa ein Neustart nach Updates.', 'accent') } default { $null } }
        if ($timer) { $rows += New-SheetRow -Title $timer[0] -Sub $timer[1] -Glyph 0xE823 -Tone $timer[2] -Action 'Energieoptionen' -Data @{ Do = 'timers' } }
    }
    else {
        if ($null -ne $data.Idle) {
            if ($data.Idle -eq 0) {
                $rows += New-SheetRow -Title 'Standby ist ausgeschaltet' -Sub 'Im Energieplan steht „Nie“: der PC geht nicht von selbst in den Standby. Das ist der häufigste Grund.' -Glyph 0xE708 -Tone 'warn' -State 'Nie' -Action 'Einstellungen' -Data @{ Do = 'sleep' }
            }
            else {
                $minutes = [Math]::Round($data.Idle / 60)
                $rows += New-SheetRow -Title "Standby nach $(if ($minutes -ge 60 -and $minutes % 60 -eq 0) { "$($minutes / 60) Stunden" } else { "$minutes Minuten" }) ohne Bedienung" -Sub 'So steht es im Energieplan. Geht er trotzdem nicht schlafen, hält ihn etwas wach (siehe unten).' -Glyph 0xE708 -Tone 'good' -Action 'Einstellungen' -Data @{ Do = 'sleep' }
            }
        }
        if ($data.NeedsAdmin) {
            $rows += New-SheetRow -Title 'Was den PC gerade wach hält, verrät Windows nur mit Adminrechten' -Sub 'PulsRig als Admin starten und hier neu einlesen.' -Glyph 0xE72E -Action $(if (-not $script:IsAdmin) { 'Als Admin neu starten' }) -Data @{ Do = 'admin' }
        }
        elseif (@($data.Requests).Count -eq 0) {
            $rows += New-SheetRow -Title 'Gerade hält nichts den PC wach' -Sub 'Kein Programm, Dienst oder Treiber verhindert den Standby.' -Glyph 0xE73E -Tone 'good'
        }
        else {
            foreach ($request in @($data.Requests | Select-Object -First 5)) {
                $what = switch ($request.Section) { 'DISPLAY' { 'hält den Bildschirm an' } 'SYSTEM' { 'verhindert den Standby' } 'AWAYMODE' { 'hält den Abwesenheitsmodus' } 'EXECUTION' { 'arbeitet im Hintergrund weiter' } default { 'hält den PC wach' } }
                $type = switch ($request.Kind) { 'PROCESS' { 'Programm' } 'SERVICE' { 'Dienst' } 'DRIVER' { 'Treiber' } default { "$($request.Kind)" } }
                $rows += New-SheetRow -Title "$($request.Name) $what" -Sub ((@($type, $request.Why) | Where-Object { $_ }) -join ' · ') -Glyph 0xE7BA -Tone 'warn'
            }
        }
    }
    Show-SheetList $rows
    Set-SheetStateText $(if ([int]$script:Sheet.Tab -eq 0) { 'Ereignisprotokoll von Windows · letzte 14 Tage' } else { 'Energieplan und Anfragen von Programmen, Diensten und Treibern' })
}
