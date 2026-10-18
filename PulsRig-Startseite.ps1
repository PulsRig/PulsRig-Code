# PulsRig - Startseite: Gruß nach Tageszeit, Live-Werte mit Kurve, Zeitleiste der Änderungen und Gaming-Check.
# Wird von PulsRig.ps1 nach PulsRig-Standby.ps1 eingebunden. Die Messung selbst ist die der Sensoren
# (Start-Sensors in PulsRig-Hardware.ps1); sie läuft nur, solange die Startseite im Vordergrund steht.

function Update-HomeGreeting {
    $hour = (Get-Date).Hour
    $text = if ($hour -ge 5 -and $hour -lt 11) { 'Guten Morgen' } elseif ($hour -ge 11 -and $hour -lt 18) { 'Guten Tag' } elseif ($hour -ge 18 -and $hour -lt 23) { 'Guten Abend' } else { 'Hallo' }
    $ui.HomeGreeting.Text = T $text
}

# --- Live -----------------------------------------------------------------------
# Drei Zeilen: Grafikkarte (ohne NVIDIA-Karte der Takt des Prozessors), Prozessor, Arbeitsspeicher

$script:HomeLive = @(
    @{ History = (New-Object 'System.Collections.Generic.List[double]') },
    @{ History = (New-Object 'System.Collections.Generic.List[double]') },
    @{ History = (New-Object 'System.Collections.Generic.List[double]') }
)
$script:HomeLiveStamp = -1
$script:HomeLiveOwn = $false     # die Startseite hat die Messung gestartet und beendet sie auch wieder
$script:HomeLiveSeen = 0         # Messwerte seit dem Start - ohne Grafikkarten-Werte nach drei Takten auf den Takt wechseln

function Clear-HomeLive {
    foreach ($row in $script:HomeLive) { $row.History.Clear() }
    for ($i = 0; $i -lt 3; $i++) { $ui["HomeLive$($i)Line"].Data = $null; $ui["HomeLive$($i)Value"].Text = '–' }
    $script:HomeLiveStamp = -1
    $script:HomeLiveSeen = 0
}

# Kurve der letzten Minute: passt sich der Spanne der Werte an, mindestens $MinSpan hoch
function Set-HomeLiveLine([int]$Index, [double]$MinSpan) {
    $area = $ui["HomeLive$($Index)Area"]
    $values = $script:HomeLive[$Index].History
    $width = $area.ActualWidth; $height = $area.ActualHeight
    if ($values.Count -lt 2 -or $width -lt 10 -or $height -lt 6) { return }
    $low = ($values | Measure-Object -Minimum).Minimum
    $high = ($values | Measure-Object -Maximum).Maximum
    if ($high - $low -lt $MinSpan) { $middle = ($high + $low) / 2; $low = $middle - $MinSpan / 2; $high = $middle + $MinSpan / 2 }
    $culture = [cultureinfo]::InvariantCulture
    $step = $width / 59.0
    $start = $width - $step * ($values.Count - 1)
    $parts = for ($i = 0; $i -lt $values.Count; $i++) {
        $x = $start + $step * $i
        $y = $height - 1 - ($values[$i] - $low) / ($high - $low) * ($height - 2)
        '{0}{1},{2}' -f $(if ($i) { ' L ' } else { 'M ' }), $x.ToString('0.0', $culture), $y.ToString('0.0', $culture)
    }
    $ui["HomeLive$($Index)Line"].Data = [Windows.Media.Geometry]::Parse(($parts -join ''))
}

function Update-HomeLive {
    $want = $script:Page -eq 'Home' -and -not $script:Sheet -and -not $script:Dialog -and $window.WindowState -ne 'Minimized' -and ($window.IsActive -or $Snapshot)
    if (-not $want) {
        # die eigene Messung beenden; eine, die der Sensoren-Dialog gestartet hat, läuft weiter
        if ($script:HomeLiveOwn -and $script:SensorRun -and -not $script:Sheet) { Stop-Sensors }
        $script:HomeLiveOwn = $false
        return
    }
    if (-not $script:SensorRun) {
        $script:SensorTiles = @{}
        Start-Sensors
        $script:HomeLiveOwn = $true
        $script:HomeLiveStamp = -1      # die Kurven der letzten Minute bleiben stehen und laufen weiter
        return
    }
    $values = $sync.Sensors
    if (-not $values -or $values.Stamp -eq $script:HomeLiveStamp) { return }
    $script:HomeLiveStamp = $values.Stamp
    $script:HomeLiveSeen++
    $gpu = $null -ne $values.GpuTemp
    $rows = @(
        $(if ($gpu -or $script:HomeLiveSeen -lt 3) { @{ Label = 'Grafikkarte'; Value = $values.GpuTemp; Format = '{0:N0} °C'; Span = 6 } }
            else { @{ Label = 'Prozessor-Takt'; Value = $values.CpuClock; Format = '{0:N2} GHz'; Span = 0.4 } }),
        @{ Label = 'Prozessor'; Value = $values.CpuLoad; Format = '{0:N0} %'; Span = 10 },
        @{ Label = 'Arbeitsspeicher'; Value = $values.Ram; Format = '{0:N0} %'; Span = 6 }
    )
    for ($i = 0; $i -lt 3; $i++) {
        $row = $rows[$i]
        $label = T $row.Label
        if ($ui["HomeLive$($i)Label"].Text -ne $label) { $ui["HomeLive$($i)Label"].Text = $label; $script:HomeLive[$i].History.Clear() }
        if ($null -eq $row.Value) { continue }
        $ui["HomeLive$($i)Value"].Text = $row.Format -f [double]$row.Value
        $script:HomeLive[$i].Text = $ui["HomeLive$($i)Value"].Text
        $history = $script:HomeLive[$i].History
        $history.Add([double]$row.Value)
        while ($history.Count -gt 60) { $history.RemoveAt(0) }
        Set-HomeLiveLine $i $row.Span
    }
}

# --- Gaming-Check ---------------------------------------------------------------------

function Set-HomeGameArc([double]$Fraction) {
    if ($Fraction -le 0) { $ui.HomeGameArc.Data = $null; return }
    $Fraction = [Math]::Min($Fraction, 0.999)
    $culture = [cultureinfo]::InvariantCulture
    $angle = 2 * [Math]::PI * $Fraction - [Math]::PI / 2
    $x = 23 + 20.5 * [Math]::Cos($angle); $y = 23 + 20.5 * [Math]::Sin($angle)
    $large = if ($Fraction -gt 0.5) { 1 } else { 0 }
    $ui.HomeGameArc.Data = [Windows.Media.Geometry]::Parse(('M 23,2.5 A 20.5,20.5 0 {0} 1 {1},{2}' -f $large, $x.ToString('0.00', $culture), $y.ToString('0.00', $culture)))
}

function Update-HomeGameCard {
    if (-not $ui.HomeGameScore) { return }
    $state = $script:CardState.GameCheck
    if (-not $state -or -not $state.Text) {
        $ui.HomeGameScore.Text = '–'
        $ui.HomeGameText.Text = T 'Noch nicht geprüft'
        Set-HomeGameArc 0
        return
    }
    $score = [int]$state.Text
    $ui.HomeGameScore.Text = "$score"
    Set-HomeGameArc ($score / 100.0)
    $date = "$($state.Date)"
    $when = if ($date -eq (Get-Date).ToString('dd.MM.yyyy')) { 'heute' } elseif ($date.Length -ge 6) { $date.Substring(0, 6) } else { '' }
    $hints = if ($null -ne $state.Hints) { [int]$state.Hints } else { -1 }
    $what = if ($hints -eq 0) { 'Alles gut eingestellt' } elseif ($hints -eq 1) { '1 Tipp' } elseif ($hints -gt 1) { "$hints Tipps" } else { 'von 100 Punkten' }
    $ui.HomeGameText.Text = T $((@($what, $when) | Where-Object { $_ }) -join ' · ')
}

# --- Was hat sich geändert? ---------------------------------------------------------------
# Die neuesten Änderungen der letzten sieben Tage als Zeitleiste; nur so viele, wie ganz in die Karte passen

function New-HomeChangeRow($Change, [bool]$First, [bool]$Line) {
    $row = New-Object Windows.Controls.Grid
    $row.Margin = '0,0,0,0'
    $left = New-Object Windows.Controls.ColumnDefinition; $left.Width = 18
    $right = New-Object Windows.Controls.ColumnDefinition
    $row.ColumnDefinitions.Add($left); $row.ColumnDefinitions.Add($right)
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 9; $dot.Height = 9; $dot.VerticalAlignment = 'Top'; $dot.HorizontalAlignment = 'Left'; $dot.Margin = '0,4,0,0'
    if ($First) { Set-Paint $dot 'Fill' 'Accent' } else { $dot.Fill = New-Brush '#3A4767' }
    [void]$row.Children.Add($dot)
    if ($Line) {
        $rule = New-Object Windows.Shapes.Rectangle
        $rule.Width = 2; $rule.HorizontalAlignment = 'Left'; $rule.Margin = '3.5,16,0,0'
        $rule.Fill = New-Brush '#222B40'
        [void]$row.Children.Add($rule)
    }
    $text = New-Object Windows.Controls.StackPanel
    $text.Margin = '0,0,0,12'
    [Windows.Controls.Grid]::SetColumn($text, 1)
    $title = New-Object Windows.Controls.TextBlock
    $title.Text = T $Change.Title; $title.FontSize = 12.5; $title.FontWeight = 'SemiBold'; $title.TextWrapping = 'Wrap'
    Set-Paint $title 'Foreground' 'Text'
    [void]$text.Children.Add($title)
    if ($Change.Sub) {
        $sub = New-Object Windows.Controls.TextBlock
        $sub.Text = T $Change.Sub; $sub.FontSize = 11; $sub.TextWrapping = 'Wrap'; $sub.Margin = '0,2,0,0'
        Set-Paint $sub 'Foreground' 'TextDim'
        [void]$text.Children.Add($sub)
    }
    [void]$row.Children.Add($text)
    $row
}

function Update-HomeChangesList {
    $list = $ui.HomeChangesList
    if (-not $list) { return }
    $list.Children.Clear()
    $snaps = @($script:History.Snapshots | Where-Object { $_ } | Sort-Object { $_.D })
    $changes = if ($snaps.Count -ge 2) { @(Get-Changes (Get-SnapshotBefore 7) $snaps[-1] | Select-Object -First 3) } else { @() }
    if ($changes.Count -eq 0) {
        # noch nichts zu zeigen: sagen, was hier erscheinen wird
        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = T 'Sobald sich Treiber, Programme, der Autostart oder Windows ändern, steht es hier mit Datum.'
        $hint.FontSize = 11.5; $hint.TextWrapping = 'Wrap'; $hint.LineHeight = 17
        Set-Paint $hint 'Foreground' 'TextFaint'
        [void]$list.Children.Add($hint)
        return
    }
    $room = $list.ActualHeight
    for ($i = 0; $i -lt $changes.Count; $i++) {
        $row = New-HomeChangeRow $changes[$i] ($i -eq 0) ($i -lt $changes.Count - 1)
        [void]$list.Children.Add($row)
        # passt der Eintrag nicht mehr ganz hinein, bleibt er weg - lieber einer weniger als ein halber
        if ($room -gt 0) {
            $list.Measure((New-Object Windows.Size $list.ActualWidth, ([double]::PositiveInfinity)))
            if ($list.DesiredSize.Height -gt $room + 0.5) { $list.Children.Remove($row); break }
        }
    }
    # die Linie zur nächsten Zeile endet beim letzten gezeigten Eintrag
    $last = $list.Children.Count - 1
    if ($last -ge 0) { foreach ($child in @($list.Children[$last].Children)) { if ($child -is [Windows.Shapes.Rectangle]) { $list.Children[$last].Children.Remove($child) } } }
}

# erst wenn die Karte ihre Größe kennt, lässt sich sagen, wie viele Einträge hineinpassen
$ui.HomeChangesList.Add_SizeChanged({ try { if ($_.PreviousSize.Height -ne $_.NewSize.Height) { Update-HomeChangesList } } catch { Write-AppError $_ } })

$script:HomeLiveTimer = New-Object Windows.Threading.DispatcherTimer
$script:HomeLiveTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:HomeLiveTimer.Add_Tick({ try { Update-HomeLive } catch { Write-AppError $_ } })
$script:HomeLiveTimer.Start()

# der Punkt neben "Live" pocht ruhig, solange gemessen wird
if ($script:Settings.Animations) {
    $ui.HomeLiveDot.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.35 -Ms 800 -Ease $script:EaseSine -Forever -AutoReverse))
}

Update-HomeGreeting
Update-HomeGameCard
Update-HomeChangesList
