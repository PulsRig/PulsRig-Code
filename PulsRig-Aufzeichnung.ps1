# PulsRig - Spielsitzungen ansehen. Wird von PulsRig.ps1 nach PulsRig-Benchmark.ps1 eingebunden.
#
# Aufgezeichnet wird im Helfer neben der Uhr (PulsRig-Aufzeichnung.cs): eine Datei je Sitzung im Ordner
# "Aufzeichnungen", alle 5 Sekunden eine Zeile. Hier: Reiter "Spielsitzungen" im Fenster Sensoren mit Diagramm
# (Temperatur von Prozessor und Grafikkarte über die ganze Sitzung), Zusammenfassung und Auswahl der Sitzung.

$script:RecordFolder = Join-Path $script:OutDir 'Aufzeichnungen'
$script:RecordPick = $null      # gewählte Datei; leer = die neueste

function Get-Recordings {
    if (-not (Test-Path -LiteralPath $script:RecordFolder)) { return @() }
    @(Get-ChildItem -LiteralPath $script:RecordFolder -Filter '*.csv' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
}

# Liest eine Sitzung: Spiel, Beginn und die Zeilen als Zahlenreihen (NaN, wo nichts gemessen wurde)
function Read-Recording([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)
    $head = @{}
    foreach ($part in ("$($lines[0])" -split ';')) { if ($part -match '^(\w+)=(.*)$') { $head[$Matches[1]] = $Matches[2] } }
    $names = "$($lines[1])" -split ';'
    $columns = @{}
    foreach ($name in $names) { $columns[$name] = New-Object 'System.Collections.Generic.List[double]' }
    $culture = [cultureinfo]::InvariantCulture
    for ($i = 2; $i -lt $lines.Count; $i++) {
        $cells = "$($lines[$i])" -split ';'
        if ($cells.Count -ne $names.Count) { continue }
        for ($c = 0; $c -lt $names.Count; $c++) {
            $value = [double]::NaN
            [void][double]::TryParse($cells[$c], [Globalization.NumberStyles]::Float, $culture, [ref]$value)
            $columns[$names[$c]].Add($value)
        }
    }
    $begin = Get-Date
    [void][datetime]::TryParseExact("$($head.Beginn)", 'yyyy-MM-ddTHH:mm:ss', $culture, 'None', [ref]$begin)
    @{ Game = "$($head.Spiel)"; Begin = $begin; Data = $columns; Count = $columns['Sekunde'].Count; Path = $Path
        Seconds = $(if ($columns['Sekunde'].Count) { $columns['Sekunde'][$columns['Sekunde'].Count - 1] } else { 0 }) }
}

# Kennzahlen einer Reihe: Mittel und Höchstwert (ohne Lücken)
function Get-SeriesStats($List) {
    $values = @($List | Where-Object { -not [double]::IsNaN($_) })
    if (-not $values.Count) { return $null }
    $measure = $values | Measure-Object -Average -Maximum
    @{ Avg = [double]$measure.Average; Max = [double]$measure.Maximum; Count = $values.Count }
}

# Drosseln: unter Last fällt der Takt deutlich unter den üblichen Takt unter Last derselben Sitzung
function Get-ThrottleShare($Clock, $Load, [double]$MinLoad, [double]$Drop) {
    $loaded = @(for ($i = 0; $i -lt $Clock.Count; $i++) { if ($Load[$i] -ge $MinLoad -and $Clock[$i] -gt 0) { $Clock[$i] } })
    if ($loaded.Count -lt 6) { return 0.0 }
    $sorted = @($loaded | Sort-Object)
    $median = $sorted[[int]($sorted.Count / 2)]
    $low = @($loaded | Where-Object { $_ -lt $median * $Drop }).Count
    $low / $loaded.Count
}

# Läuft die Sitzung noch? Die Zeit im Ordner hilft nicht: Für eine offene Datei aktualisiert Windows sie verspätet.
# Also: endet die letzte Zeile vor weniger als 20 Sekunden?
function Test-RecordingRunning($Recording) {
    ((Get-Date) - $Recording.Begin.AddSeconds([double]$Recording.Seconds)).TotalSeconds -lt 20
}

# Größe einer Datei, die der Helfer vielleicht gerade schreibt (der Ordner meldet sie dann verspätet)
function Get-RecordingSize([string]$Path) {
    $stream = $null
    try { $stream = New-Object IO.FileStream $Path, 'Open', 'Read', 'ReadWrite'; $stream.Length } catch { 0 } finally { if ($stream) { $stream.Dispose() } }
}

function Format-Duration([double]$Seconds) {
    $span = [TimeSpan]::FromSeconds($Seconds)
    if ($span.TotalHours -ge 1) { '{0}:{1:00} Std.' -f [int][Math]::Floor($span.TotalHours), $span.Minutes } else { '{0} Min.' -f [int][Math]::Round($span.TotalMinutes) }
}

# Zusammenfassung in Sätzen (je Zeile einer, für die Übersetzung) und ein Ton
function Get-RecordingSummary($Recording) {
    $data = $Recording.Data
    $cpu = Get-SeriesStats $data['CpuTemp']
    $gpu = Get-SeriesStats $data['GpuTemp']
    $lines = @()
    $tone = 'good'
    $parts = @()
    if ($cpu) { $parts += ('Prozessor im Schnitt {0:N0} °C, höchstens {1:N0} °C' -f $cpu.Avg, $cpu.Max) }
    if ($gpu) { $parts += ('Grafikkarte im Schnitt {0:N0} °C, höchstens {1:N0} °C' -f $gpu.Avg, $gpu.Max) }
    if ($parts) { $lines += ($parts -join ' · ') + '.' }
    if (-not $cpu) { $lines += 'Die Temperatur des Prozessors fehlt: Sensoren → Freischalten, oder Core Temp laufen lassen.' }
    $step = 5.0
    if ($cpu) {
        $hot = @($data['CpuTemp'] | Where-Object { $_ -ge 88 }).Count * $step / 60
        if ($hot -ge 1) { $lines += ('{0:N0} Minuten lief der Prozessor an seiner Temperaturgrenze.' -f $hot) }
        if ($cpu.Max -ge 95) { $tone = 'warn' }
    }
    if ($gpu) {
        $hot = @($data['GpuTemp'] | Where-Object { $_ -ge 83 }).Count * $step / 60
        if ($hot -ge 1) { $lines += ('{0:N0} Minuten war die Grafikkarte über 83 °C – dort beginnen viele zu drosseln.' -f $hot); $tone = 'warn' }
    }
    $cpuThrottle = Get-ThrottleShare $data['CpuTakt'] $data['CpuLast'] 50 0.8
    $gpuThrottle = Get-ThrottleShare $data['GpuTakt'] $data['GpuLast'] 90 0.85
    if ($gpuThrottle -ge 0.1) { $lines += ('Die Grafikkarte hat unter Last in {0:N0} % der Zeit deutlich weniger Takt gehabt als sonst: Sie drosselt, meist wegen Hitze oder Strombegrenzung.' -f (100 * $gpuThrottle)); $tone = 'warn' }
    if ($cpuThrottle -ge 0.1) { $lines += ('Der Prozessor hat unter Last in {0:N0} % der Zeit deutlich weniger Takt gehabt als sonst.' -f (100 * $cpuThrottle)); $tone = 'warn' }
    if ($tone -eq 'good' -and ($cpu -or $gpu)) { $lines += 'Kein Drosseln zu sehen: Die Kühlung kommt mit dem Spiel zurecht.' }
    @{ Text = ($lines -join "`n"); Tone = $tone; Cpu = $cpu; Gpu = $gpu }
}

# Farbe einer Linie: Prozessor in der Akzentfarbe, Grafikkarte in der dritten Akzentfarbe des Farbdesigns
function Set-RecordPaint($Element, [string]$Property, [string]$Key) {
    if ($Key -ne 'Accent2') { Set-Paint $Element $Property $Key; return }
    $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString("$($script:Theme.A[2])"))
    $Element.GetType().GetProperty($Property).SetValue($Element, $brush)
}

# Diagramm: Temperatur von Prozessor und Grafikkarte über die Sitzung, 30 bis 100 °C. Jede Linie trägt unsichtbare
# Eckpunkte, damit alle mit Stretch="Fill" gleich gestreckt werden - so braucht es keine Pixelrechnung.
function New-RecordingChart($Recording) {
    $culture = [cultureinfo]::InvariantCulture
    $seconds = [Math]::Max(1.0, [double]$Recording.Seconds)
    $time = $Recording.Data['Sekunde']
    $frame = [string]::Format($culture, 'M 0,0 M {0:0.##},70 ', $seconds)
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = 14; $card.Padding = '14,12,14,8'; $card.Margin = '0,0,0,8'; $card.BorderThickness = 1
    Set-Paint $card 'Background' 'Glass'; Set-Paint $card 'BorderBrush' 'GlassEdge'
    $outer = New-Object Windows.Controls.Grid
    foreach ($h in 'Auto', '190', 'Auto') { $row = New-Object Windows.Controls.RowDefinition; $row.Height = $(if ($h -eq 'Auto') { [Windows.GridLength]::Auto } else { New-Object Windows.GridLength ([double]$h) }); $outer.RowDefinitions.Add($row) }
    $card.Child = $outer
    # Kopf: Spiel, Beginn, Dauer und die Farben der Linien
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = '0,0,0,8'
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = '{0} · {1} · {2}' -f $Recording.Game, $Recording.Begin.ToString('dd.MM. HH:mm'), (T (Format-Duration $Recording.Seconds))
    $title.FontSize = 13.5; $title.FontWeight = 'SemiBold'
    Set-Paint $title 'Foreground' 'Text'
    $legend = New-Object Windows.Controls.StackPanel
    $legend.Orientation = 'Horizontal'
    [Windows.Controls.DockPanel]::SetDock($legend, 'Right')
    foreach ($item in @(@('Prozessor', 'Accent'), @('Grafikkarte', 'Accent2'))) {
        $dot = New-Object Windows.Shapes.Ellipse
        $dot.Width = 8; $dot.Height = 8; $dot.Margin = '14,0,6,0'; $dot.VerticalAlignment = 'Center'
        Set-RecordPaint $dot 'Fill' $item[1]
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = T $item[0]; $label.FontSize = 11.5; $label.VerticalAlignment = 'Center'
        Set-Paint $label 'Foreground' 'TextDim'
        [void]$legend.Children.Add($dot); [void]$legend.Children.Add($label)
    }
    [void]$head.Children.Add($legend); [void]$head.Children.Add($title)
    $outer.Children.Add($head) | Out-Null
    # Fläche: Hilfslinien bei 50, 70, 90 °C mit Beschriftung, darüber die Kurven
    $area = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRow($area, 1)
    $area.Margin = '30,0,0,0'
    foreach ($mark in 50, 70, 90) {
        $guide = New-Object Windows.Shapes.Path
        $guide.Data = [Windows.Media.Geometry]::Parse($frame + [string]::Format($culture, 'M 0,{0} L {1:0.##},{0}', 100 - $mark, $seconds))
        $guide.Stretch = 'Fill'; $guide.StrokeThickness = 1; $guide.StrokeDashArray = [Windows.Media.DoubleCollection]::Parse('3 4')
        $guide.Opacity = $(if ($mark -eq 90) { 0.55 } else { 0.25 })
        Set-Paint $guide 'Stroke' $(if ($mark -eq 90) { 'Warn' } else { 'TextDim' })
        [void]$area.Children.Add($guide)
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = "$mark °"; $label.FontSize = 10.5
        $label.Margin = New-Object Windows.Thickness (-30), (190 * (100 - $mark) / 70 - 8), 0, 0
        $label.VerticalAlignment = 'Top'; $label.HorizontalAlignment = 'Left'
        Set-Paint $label 'Foreground' 'TextDim'
        [void]$area.Children.Add($label)
    }
    foreach ($series in @(@('GpuTemp', 'Accent2'), @('CpuTemp', 'Accent'))) {
        $values = $Recording.Data[$series[0]]
        if (-not $values) { continue }
        $points = New-Object Text.StringBuilder
        [void]$points.Append($frame)
        $open = $false
        for ($i = 0; $i -lt $values.Count; $i++) {
            $value = $values[$i]
            if ([double]::IsNaN($value)) { $open = $false; continue }
            $y = 100 - [Math]::Max(30.0, [Math]::Min(100.0, $value))
            [void]$points.Append([string]::Format($culture, '{0} {1:0.##},{2:0.##} ', $(if ($open) { 'L' } else { 'M' }), $time[$i], $y))
            $open = $true
        }
        $line = New-Object Windows.Shapes.Path
        $line.Data = [Windows.Media.Geometry]::Parse($points.ToString())
        $line.Stretch = 'Fill'; $line.StrokeThickness = 1.8; $line.StrokeLineJoin = 'Round'
        Set-RecordPaint $line 'Stroke' $series[1]
        [void]$area.Children.Add($line)
    }
    $outer.Children.Add($area) | Out-Null
    # Zeitachse: Beginn, Mitte, Ende
    $axis = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRow($axis, 2)
    $axis.Margin = '30,4,0,0'
    foreach ($at in @(@(0.0, 'Left'), @(0.5, 'Center'), @(1.0, 'Right'))) {
        $text = New-Object Windows.Controls.TextBlock
        $text.Text = $Recording.Begin.AddSeconds($seconds * $at[0]).ToString('HH:mm')
        $text.FontSize = 10.5; $text.HorizontalAlignment = $at[1]
        Set-Paint $text 'Foreground' 'TextDim'
        [void]$axis.Children.Add($text)
    }
    $outer.Children.Add($axis) | Out-Null
    $card
}

# Warum es noch keine Sitzung gibt, und der nächste Schritt
function Get-RecordingHint {
    if (-not (Get-HelperExe)) { return @{ Text = 'Aufgezeichnet wird im Helfer neben der Uhr. Den gibt es nur im installierten Programm.'; Action = ''; Do = '' } }
    if (-not $script:Settings.Helper) { return @{ Text = 'Aufgezeichnet wird im Helfer neben der Uhr. Er ist ausgeschaltet.'; Action = 'Helfer einschalten'; Do = 'helper' } }
    if ($script:Settings.RecordGames -eq $false) { return @{ Text = 'Die Aufzeichnung beim Spielen ist ausgeschaltet.'; Action = 'Einschalten'; Do = 'record' } }
    $recorded = @(@($script:Settings.BoostGames) + @($script:Settings.RecordList) | Where-Object { $_ } | Select-Object -Unique)
    if (-not $recorded.Count) { return @{ Text = 'Der Helfer zeichnet die Spiele auf, die unter „Deine Spiele“ zum Aufzeichnen gewählt sind, und die Boost-Spiele. Noch ist keines gewählt.'; Action = 'Spiele wählen'; Do = 'games' } }
    @{ Text = "Sobald eines der gewählten Spiele läuft ($($recorded -join ', ')), schreibt der Helfer alle 5 Sekunden mit. Für alles andere: Rechtsklick auf das Symbol neben der Uhr → Temperaturen aufzeichnen."; Action = ''; Do = '' }
}

function Invoke-RecordingAction([string]$Do) {
    switch ($Do) {
        'helper' { Close-Sheet -Quick; Open-SettingsSheet 5 }
        'record' { $script:Settings.RecordGames = $true; Save-Settings; Show-RecordingTab }
        'games' { Close-Sheet -Quick; Open-GamesSheet }
        default { if ($Do -like 'pick:*') { $script:RecordPick = $Do.Substring(5); Show-RecordingTab } }
    }
}

function Show-RecordingTab {
    Show-SheetPanel
    $script:SensorTiles = @{}
    $files = @(Get-Recordings)
    if (-not $files.Count) {
        $hint = Get-RecordingHint
        $slot = Add-SettingRow 'Noch keine Spielsitzung' $hint.Text 0xE7FC
        if ($hint.Action) {
            $chip = New-SettingChip $hint.Action $hint.Do
            $chip.Add_Click({ param($sender) try { Invoke-RecordingAction $sender.Uid } catch { Write-AppError $_ } })
            [void]$slot.Children.Add($chip)
        }
        [void](Add-SettingRow 'Was aufgezeichnet wird' 'Alle 5 Sekunden Temperatur, Last und Takt von Prozessor und Grafikkarte, dazu Leistung und Lüfter der Grafikkarte. Es bleiben die letzten 30 Sitzungen.' 0xE9D9)
        Set-SheetStateText 'Aufzeichnungen: keine'
        return
    }
    $file = @($files | Where-Object { $_.FullName -eq $script:RecordPick })[0]
    if (-not $file) { $file = $files[0] }
    try { $recording = Read-Recording $file.FullName }
    catch { [void](Add-SettingRow 'Die Sitzung ließ sich nicht lesen' "$($_.Exception.Message)" 0xE7BA); return }
    [void]$ui.SheetPanel.Children.Add((New-RecordingChart $recording))
    $summary = Get-RecordingSummary $recording
    $slot = Add-SettingRow $(if ($summary.Tone -eq 'warn') { 'Zu warm oder gedrosselt' } else { 'Zusammenfassung' }) $summary.Text $(if ($summary.Tone -eq 'warn') { 0xE7BA } else { 0xE73E })
    try { Set-Paint $slot.Parent.FindName('Glyph') 'Foreground' $(if ($summary.Tone -eq 'warn') { 'Warn' } else { 'Good' }) } catch { }
    # Auswahl der Sitzung: die letzten acht als Knöpfe
    $pick = New-Object Windows.Controls.WrapPanel
    $pick.Margin = '-3,2,0,0'
    foreach ($entry in @($files | Select-Object -First 8)) {
        $label = if ($entry.Name -match '^(\d{4})-(\d\d)-(\d\d)_(\d\d)-(\d\d)-\d\d_(.+)\.csv$') { "$($Matches[3]).$($Matches[2]). $($Matches[4]):$($Matches[5]) $($Matches[6])" } else { $entry.BaseName }
        $chip = New-SettingChip $label "pick:$($entry.FullName)"
        if ($entry.FullName -eq $file.FullName) { $chip.Tag = 'on' }
        $chip.Add_Click({ param($sender) try { Invoke-RecordingAction $sender.Uid } catch { Write-AppError $_ } })
        [void]$pick.Children.Add($chip)
    }
    [void]$ui.SheetPanel.Children.Add($pick)
    Set-SheetStateText ("$($files.Count) von höchstens 30 Sitzungen gespeichert" + $(if (Test-RecordingRunning $recording) { ' · diese läuft gerade' }))
}
