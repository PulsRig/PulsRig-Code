# PulsRig - Staub und Verschleiß. Wird von PulsRig.ps1 nach PulsRig-Spiele.ps1 eingebunden.
#
# Lässt die Kühlung nach (Staub, eingetrocknete Wärmeleitpaste), wird es bei gleicher Leistung wärmer, die Lüfter
# drehen schneller, oder ein Prozessor an seiner Temperaturgrenze hält weniger Takt. Dafür merkt sich PulsRig aus jeder
# Spielsitzung (ab der 10. Minute, nur unter Last) und aus jedem Stabilitätstest ab 5 Minuten einen kompakten
# Messpunkt in History.Thermal (die letzten 200) und vergleicht die ältesten mit den neuesten - frühestens nach drei
# Wochen, weil Raumtemperatur und Spiel schwanken. Dazu für jede SSD: Wie schnell steigt die Abnutzung, und wie lange
# hält sie bei diesem Tempo noch?
# Ansicht: Reiter "Verschleiß" im Fenster Sensoren.

$script:CoolMinDays = 21           # Abstand zwischen den ältesten und den neuesten Messpunkten
$script:CoolWarmer = 5.0           # so viel °C mehr bei gleicher Leistung gilt als Nachlassen
$script:CoolFan = 15.0             # so viele Prozentpunkte mehr Lüfter bei gleicher Leistung ebenso
$script:CoolClock = 4.0            # so viel % weniger Takt an der Temperaturgrenze ebenso

function Get-Median($Values) {
    $list = @($Values | Where-Object { $null -ne $_ -and -not [double]::IsNaN([double]$_) } | ForEach-Object { [double]$_ } | Sort-Object)
    if (-not $list.Count) { return [double]::NaN }
    if ($list.Count % 2) { $list[[int][Math]::Floor($list.Count / 2)] } else { ($list[$list.Count / 2 - 1] + $list[$list.Count / 2]) / 2 }
}

# Messpunkt aus einer Spielsitzung: Proben ab der 10. Minute, Grafikkarte nur bei Last ab 85 %
function New-ThermalPoint($Recording) {
    $data = $Recording.Data
    $time = $data['Sekunde']
    $keep = @(for ($i = 0; $i -lt $time.Count; $i++) { if ($time[$i] -ge 600) { $i } })
    if ($keep.Count -lt 60) { return $null }      # weniger als 5 Minuten nach der Aufwärmzeit
    $gpu = @($keep | Where-Object { $data['GpuLast'][$_] -ge 85 })
    $point = @{ D = $Recording.Begin.ToString('yyyy-MM-dd'); Src = 'Spiel'; Name = "$($Recording.Game)"; File = [IO.Path]::GetFileName($Recording.Path); Min = [Math]::Round($keep.Count * 5 / 60) }
    if ($gpu.Count -ge 36) {
        $point.GT = [Math]::Round((Get-Median @($gpu | ForEach-Object { $data['GpuTemp'][$_] })), 1)
        $point.GW = [Math]::Round((Get-Median @($gpu | ForEach-Object { $data['GpuWatt'][$_] })), 1)
        $point.GF = [Math]::Round((Get-Median @($gpu | ForEach-Object { $data['GpuLuefter'][$_] })), 1)
    }
    $cpu = @($keep | Where-Object { -not [double]::IsNaN($data['CpuTemp'][$_]) })
    if ($cpu.Count -ge 36) {
        $point.CT = [Math]::Round((Get-Median @($cpu | ForEach-Object { $data['CpuTemp'][$_] })), 1)
        $point.CC = [Math]::Round((Get-Median @($cpu | ForEach-Object { $data['CpuTakt'][$_] })))
        $point.CW = [Math]::Round((Get-Median @($cpu | ForEach-Object { $data['CpuWatt'][$_] })), 1)
    }
    if (-not $point.GT -and -not $point.CT) { return $null }
    $point
}

# übernimmt neue, abgeschlossene Spielsitzungen in History.Thermal (je Datei einmal)
function Update-ThermalHistory {
    $known = @($script:History.Thermal | Where-Object { $_ -and $_.File } | ForEach-Object { "$($_.File)" })
    $added = 0
    foreach ($file in @(Get-Recordings | Sort-Object Name)) {
        if ($known -contains $file.Name) { continue }
        try {
            $recording = Read-Recording $file.FullName
            if (Test-RecordingRunning $recording) { continue }
            $point = New-ThermalPoint $recording
            # auch ohne Messpunkt merken, dass die Datei gelesen ist (sonst würde sie bei jedem Start neu gelesen)
            if (-not $point) { $point = @{ D = $recording.Begin.ToString('yyyy-MM-dd'); Src = 'kurz'; File = $file.Name } }
            $script:History.Thermal = @(@($script:History.Thermal | Where-Object { $_ }) + $point | Select-Object -Last 200)
            $added++
        }
        catch { }
    }
    if ($added) { Save-HardwareResults }
}

# Messpunkt aus einem Stabilitätstest (ab 5 Minuten): Mittel der letzten Minute
function Add-StressThermalPoint($Stress, [double]$Seconds) {
    if ($Seconds -lt 290 -or -not $Stress.Tail -or $Stress.Tail.Count -lt 20) { return }
    $tail = @($Stress.Tail)
    $point = @{ D = (Get-Date).ToString('yyyy-MM-dd'); Src = 'Stresstest'; Name = "$($Stress.What)"; Min = [Math]::Round($Seconds / 60) }
    if ($Stress.What -in 'gpu', 'both') {
        $point.GT = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.GT })), 1)
        $point.GW = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.GW })), 1)
        $point.GF = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.GF })), 1)
    }
    if ($Stress.What -in 'cpu', 'both') {
        $point.CT = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.CT })), 1)
        $point.CC = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.CC })) * 1000)
        $point.CW = [Math]::Round((Get-Median @($tail | ForEach-Object { $_.CW })), 1)
    }
    foreach ($key in @($point.Keys)) { if ($point[$key] -is [double] -and [double]::IsNaN($point[$key])) { $point.Remove($key) } }
    $script:History.Thermal = @(@($script:History.Thermal | Where-Object { $_ }) + $point | Select-Object -Last 200)
}

# Vergleich alt gegen neu für einen Teil ('G' Grafikkarte, 'C' Prozessor): Ergebnis mit Ton, Satz und Zahlen
function Get-CoolingTrend([string]$Part) {
    $temp = "$($Part)T"; $watt = "$($Part)W"
    $points = @($script:History.Thermal | Where-Object { $_ -and $_.Src -ne 'kurz' -and $null -ne $_[$temp] -and [double]$_[$temp] -gt 0 } | Sort-Object { $_.D })
    $name = if ($Part -eq 'G') { 'Grafikkarte' } else { 'Prozessor' }
    if ($points.Count -lt 4) {
        return @{ Tone = ''; Title = $name; State = 'zu wenig Daten'; Text = "Erst $($points.Count) Messpunkte. Der Vergleich beginnt ab vier, aus Spielsitzungen ab 15 Minuten oder Stabilitätstests ab 5 Minuten." }
    }
    $first = [datetime]::ParseExact($points[0].D, 'yyyy-MM-dd', $null)
    $last = [datetime]::ParseExact($points[-1].D, 'yyyy-MM-dd', $null)
    $span = ($last - $first).TotalDays
    if ($span -lt $script:CoolMinDays) {
        return @{ Tone = ''; Title = $name; State = 'sammelt noch'; Text = ("{0} Messpunkte seit dem {1}. Verglichen wird ab drei Wochen Abstand, ab dem {2}." -f $points.Count, $first.ToString('dd.MM.'), $first.AddDays($script:CoolMinDays).ToString('dd.MM.')) }
    }
    # die ältesten und die neuesten Messpunkte, je ein Drittel, mindestens zwei
    $size = [Math]::Max(2, [int][Math]::Floor($points.Count / 3))
    $old = @($points | Select-Object -First $size); $new = @($points | Select-Object -Last $size)
    $oldT = Get-Median @($old | ForEach-Object { $_[$temp] }); $newT = Get-Median @($new | ForEach-Object { $_[$temp] })
    $oldW = Get-Median @($old | ForEach-Object { $_[$watt] }); $newW = Get-Median @($new | ForEach-Object { $_[$watt] })
    $since = $first.ToString('dd.MM.yyyy')
    $parts = @()
    $tone = 'good'
    # Temperatur im Verhältnis zur Leistung: auf die Leistung der alten Punkte umgerechnet (25 °C Raum angenommen)
    $warmer = $newT - $oldT
    if ($oldW -gt 0 -and $newW -gt 0) { $warmer = (($newT - 25) * $oldW / $newW + 25) - $oldT }
    if ($Part -eq 'C' -and $oldT -ge 87 -and $newT -ge 87) {
        # an der Temperaturgrenze sagt die Temperatur nichts mehr: dort zählt, wie viel Takt die Kühlung zulässt
        $oldC = Get-Median @($old | ForEach-Object { $_.CC }); $newC = Get-Median @($new | ForEach-Object { $_.CC })
        $drop = if ($oldC -gt 0) { 100 * ($oldC - $newC) / $oldC } else { 0 }
        $parts += ('An der Temperaturgrenze hält er jetzt im Schnitt {0:N0} MHz, anfangs ({1}) {2:N0} MHz.' -f $newC, $since, $oldC)
        if ($drop -ge $script:CoolClock) { $tone = 'warn'; $parts += ('Das sind {0:N0} % weniger: Die Kühlung schafft weniger als früher.' -f $drop) }
    }
    else {
        $parts += ('Unter Last jetzt im Schnitt {0:N0} °C bei {1:N0} W, anfangs ({2}) {3:N0} °C bei {4:N0} W.' -f $newT, $newW, $since, $oldT, $oldW)
        if ($warmer -ge $script:CoolWarmer) { $tone = 'warn'; $parts += ('Bei gleicher Leistung {0:N0} °C wärmer als damals.' -f $warmer) }
    }
    if ($Part -eq 'G') {
        $oldF = Get-Median @($old | ForEach-Object { $_.GF }); $newF = Get-Median @($new | ForEach-Object { $_.GF })
        if (-not [double]::IsNaN($oldF) -and -not [double]::IsNaN($newF) -and $newF - $oldF -ge $script:CoolFan) {
            $tone = 'warn'; $parts += ('Die Lüfter drehen {0:N0} % schneller als damals ({1:N0} statt {2:N0} %).' -f ($newF - $oldF), $newF, $oldF)
        }
    }
    if ($tone -eq 'warn') { $parts += 'Zeit zum Entstauben: Lüfter, Kühlrippen und Filter reinigen. Hilft das nicht, kann die Wärmeleitpaste eingetrocknet sein.' }
    else { $parts += 'Die Kühlung hält mit: kein Nachlassen zu sehen.' }
    @{ Tone = $tone; Title = $name; State = $(if ($tone -eq 'warn') { 'lässt nach' } else { 'unverändert' }); Text = ($parts -join "`n") }
}

# SSD: Wie schnell steigt die Abnutzung, und wie lange hält sie bei diesem Tempo noch?
function Get-SsdLife {
    $rows = @()
    foreach ($key in @($script:History.Disks.Keys)) {
        $list = @($script:History.Disks[$key] | Where-Object { $_ -and $null -ne $_.W } | Sort-Object { $_.D })
        $name = ("$key" -split '\|')[0]
        $disk = @($script:LastDrives.Disks | Where-Object { "$($_.Name)" -eq $name })[0]
        # nur SSDs: Festplatten melden keine Abnutzung (Windows schreibt 0 %); unbekannte Laufwerke ebenso nicht
        if (-not $disk -or (Get-DriveKind $disk) -ne 'SSD') { continue }
        if ($list.Count -lt 1) { continue }
        $first = $list[0]; $last = $list[-1]
        $wear = [int]$last.W
        $days = ([datetime]::ParseExact($last.D, 'yyyy-MM-dd', $null) - [datetime]::ParseExact($first.D, 'yyyy-MM-dd', $null)).TotalDays
        $rise = [int]$last.W - [int]$first.W
        if ($rise -ge 1 -and $days -ge 30) {
            $perYear = $rise / $days * 365
            $years = (100 - $wear) / $perYear
            $text = ('Abnutzung {0} %, seit dem {1} um {2} Punkte gestiegen: rund {3:N1} Punkte im Jahr. Bei diesem Tempo hält sie noch etwa {4:N0} Jahre.' -f $wear, ([datetime]::ParseExact($first.D, 'yyyy-MM-dd', $null)).ToString('dd.MM.yyyy'), $rise, $perYear, $years)
            $tone = if ($wear -ge 90 -or $years -lt 1) { 'bad' } elseif ($wear -ge 70 -or $years -lt 3) { 'warn' } else { 'good' }
            $state = if ($years -ge 10) { 'über 10 Jahre' } else { ('~{0:N0} Jahre' -f $years) }
        }
        else {
            $text = "Abnutzung $wear %. " + $(if ($days -lt 30) { "Für eine Schätzung braucht es einen Monat Verlauf (bisher $([int]$days) Tage)." } else { 'Seit Beginn der Aufzeichnung unverändert: Für eine Schätzung ist sie noch zu jung oder wird wenig beschrieben.' })
            $tone = if ($wear -ge 90) { 'bad' } elseif ($wear -ge 70) { 'warn' } else { 'good' }
            $state = "$wear %"
        }
        $rows += @{ Title = $name; Text = $text; Tone = $tone; State = $state }
    }
    $rows
}

function Show-WearTab {
    Show-SheetPanel
    $script:SensorTiles = @{}
    try { Update-ThermalHistory } catch { Write-AppError $_ }
    foreach ($trend in @((Get-CoolingTrend 'G'), (Get-CoolingTrend 'C'))) {
        $slot = Add-SettingRow "$($trend.Title): $($trend.State)" $trend.Text $(if ($trend.Title -eq 'Grafikkarte') { 0xE7F4 } else { 0xE950 })
        try { Set-Paint $slot.Parent.FindName('Glyph') 'Foreground' $(switch ($trend.Tone) { 'warn' { 'Warn' } 'good' { 'Good' } default { 'Accent' } }) } catch { }
    }
    $ssd = @(Get-SsdLife)
    if (-not $ssd.Count) { [void](Add-SettingRow 'SSD' 'Die Abnutzung liest Windows nur mit Adminrechten. PulsRig einmal als Admin starten.' 0xEDA2) }
    foreach ($row in $ssd) {
        $slot = Add-SettingRow "$($row.Title): $(T $row.State)" $row.Text 0xEDA2
        try { Set-Paint $slot.Parent.FindName('Glyph') 'Foreground' $(switch ($row.Tone) { 'bad' { 'Bad' } 'warn' { 'Warn' } default { 'Good' } }) } catch { }
    }
    $count = @($script:History.Thermal | Where-Object { $_ -and $_.Src -ne 'kurz' }).Count
    Set-SheetStateText "$count Messpunkte aus Spielsitzungen und Stabilitätstests · es zählen nur deutliche Unterschiede"
}

# für "Was ist los?": der schlechtere Zustand von Grafikkarte und Prozessor
function Get-CoolingState {
    $trends = @((Get-CoolingTrend 'G'), (Get-CoolingTrend 'C'))
    if (@($trends | Where-Object { $_.Tone -eq 'warn' }).Count) { return @{ Text = 'lässt nach'; Tone = 'warn' } }
    if (@($trends | Where-Object { $_.Tone -eq 'good' }).Count) { return @{ Text = 'unverändert'; Tone = 'good' } }
    @{ Text = 'sammelt noch'; Tone = '' }
}

# beim Start: neue Spielsitzungen einmal übernehmen, ohne den Start aufzuhalten
if (-not $Snapshot) { Invoke-Later 9000 { try { Update-ThermalHistory } catch { Write-AppError $_ } } }
