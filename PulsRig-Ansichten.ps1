# PulsRig - Ansichten: Seitenmenü mit Designs, Einstellungen und die Dialoge mit Listen
# (Boost-Auswahl, Spielkomponenten, Systeminformationen, Verlauf, Treiber-Einzelheiten).
# Wird von PulsRig.ps1 eingebunden und nutzt dessen Fenster, Animationen und Arbeitsbereich.

# --- Abfragen an den Arbeitsbereich -------------------------------------------
# Eine Abfrage wartet, bis der Arbeitsbereich frei ist, läuft dort und meldet ihr Ergebnis an $Then.

$script:Query = $null

function Start-Query([string]$Name, [scriptblock]$Then, $Argument) {
    $script:Query = @{ Name = $Name; Then = $Then; Argument = $Argument; Started = $false }
    Step-Query
}

function Step-Query {
    $query = $script:Query
    if (-not $query -or $query.Started) { return }
    if ($script:Busy -or -not $script:WorkerReady -or (Test-WorkerBusy)) {
        if ($script:Busy -eq 'scan') { $ui.SheetLoaderText.Text = T 'Wartet, bis der Scan fertig ist …' }
        return
    }
    $query.Started = $true
    Start-WorkerJob "query:$($query.Name)" $script:Queries[$query.Name] $query.Argument
}

function Complete-Query($Message) {
    # eine Tempomessung zählt auch dann, wenn ihr Fenster inzwischen geschlossen wurde
    if ($Message.Job -eq 'query:DriveSpeed' -and -not $Message.Error) { Save-DriveSpeed $Message.Result }
    # die Prüfung der Laufwerke beim Start gehört zu keinem Fenster
    if ($Message.Job -eq 'query:DriveCheck') { Complete-DriveCheck $Message; return }
    if ($Message.Job -eq 'query:ProbeCheck') { Complete-ProbeCheck $Message; return }
    $query = $script:Query
    if (-not $query -or -not $query.Started -or "query:$($query.Name)" -ne $Message.Job) { return }   # Dialog wurde inzwischen geschlossen
    $script:Query = $null
    if ($Message.Error) {
        Stop-SheetLoader
        # nur die erste Zeile: eine lange Meldung würde die Fußzeile sprengen
        $ui.SheetState.Text = T $('Fehler beim Lesen: ' + @("$($Message.Error)" -split "`r?`n")[0])
        return
    }
    & $query.Then $Message.Result
}

# --- Großer Dialog ------------------------------------------------------------

$script:Sheet = $null
$script:SheetTabButtons = @()

# Eine Zeile für die Liste: head = Überschrift, pair = Schlüssel und Wert, row = Zeile mit Auswahl, Balken, Zustand und Aktion
function New-SheetRow {
    param([string]$Kind = 'row', [string]$Title, [string]$Sub, [string]$Value, [switch]$Checkable, [bool]$Checked,
        $Bar = $null, [string]$State, [string]$Tone, [string]$Action, $Data, [int]$Glyph)
    $Title = T $Title; $Sub = T $Sub; $Value = T $Value; $State = T $State; $Action = T $Action
    [pscustomobject]@{
        Kind      = $Kind
        Title     = $Title
        Sub       = $Sub
        SubVis    = $(if ($Sub) { 'Visible' } else { 'Collapsed' })
        Value     = $Value
        Checked   = $Checked
        CheckVis  = $(if ($Checkable) { 'Visible' } else { 'Collapsed' })
        Bar       = $(if ($null -ne $Bar) { [double]$Bar } else { 0.0 })
        BarVis    = $(if ($null -ne $Bar) { 'Visible' } else { 'Collapsed' })
        State     = $State
        StateVis  = $(if ($State) { 'Visible' } else { 'Collapsed' })
        Tone      = $Tone
        Action    = $Action
        ActionVis = $(if ($Action) { 'Visible' } else { 'Collapsed' })
        Data      = $Data
        Glyph     = $(if ($Glyph) { [string][char]$Glyph } else { '' })
        GlyphVis  = $(if ($Glyph) { 'Visible' } else { 'Collapsed' })
    }
}

function Start-SheetLoader([string]$Text = 'Laden …') {
    $Text = T $Text
    $ui.SheetList.ItemsSource = $null
    $ui.SheetList.Visibility = 'Collapsed'
    $ui.SheetScroll.Visibility = 'Collapsed'
    $ui.SheetLoaderText.Text = $Text
    $ui.SheetLoader.Visibility = 'Visible'
    Start-Fade $ui.SheetLoader 1 260 0 0
    Start-Spin $ui.SheetSpinner 0.9
}

function Stop-SheetLoader {
    $ui.SheetSpinner.RenderTransform.BeginAnimation($P.Angle, $null)
    $ui.SheetLoader.Visibility = 'Collapsed'
}

# Zeigt die Liste; der Suchtext im Kopf des Dialogs schränkt sie ein
function Update-SheetList {
    if (-not $script:Sheet) { return }
    $rows = @($script:Sheet.Rows)
    $text = $ui.SheetSearch.Text.Trim().ToLower()
    if ($text) { $rows = @($rows | Where-Object { $_.Kind -ne 'head' -and "$($_.Title) $($_.Sub) $($_.Value) $($_.State)".ToLower().Contains($text) }) }
    $ui.SheetList.ItemsSource = $rows
}

function Show-SheetList($Rows) {
    Stop-SheetLoader
    $ui.SheetScroll.Visibility = 'Collapsed'
    $ui.SheetList.Visibility = 'Visible'
    $script:Sheet.Rows = @($Rows)
    Update-SheetList
    Start-SheetRows
}

# Sucht im Aufbau eines Elements das erste Kind der gesuchten Art
function Find-VisualChild($Element, [type]$Type) {
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        $child = [Windows.Media.VisualTreeHelper]::GetChild($Element, $i)
        if ($child -is $Type) { return $child }
        $found = Find-VisualChild $child $Type
        if ($found) { return $found }
    }
}

# Die sichtbaren Zeilen der Liste kommen nacheinander herein: beim Öffnen von unten, beim Reiterwechsel
# aus der Richtung des neuen Reiters; das Symbol jeder Zeile federt dabei nach. Die Suche löst das nicht aus.
function Start-SheetRows {
    if (-not $script:Settings.Animations) { return }
    $ui.SheetList.UpdateLayout()
    $count = [Math]::Min($ui.SheetList.Items.Count, 16)
    for ($i = 0; $i -lt $count; $i++) {
        $row = $ui.SheetList.ItemContainerGenerator.ContainerFromIndex($i)
        if (-not $row) { continue }
        $delay = 40 + 38 * $i
        $row.RenderTransform = New-Object Windows.Media.TranslateTransform
        $row.BeginAnimation($P.Opacity, $null)
        $row.Opacity = 0
        Start-Fade $row 1 280 $delay
        if ($script:SheetWay) { $row.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From (20 * $script:SheetWay) -To 0 -Ms 420 -Delay $delay)) }
        else { Start-Slide $row 0 420 $delay 12 }
        $presenter = Find-VisualChild $row ([Windows.Controls.ContentPresenter])
        $glyph = if ($presenter -and $presenter.ContentTemplate) { $presenter.ContentTemplate.FindName('RowGlyph', $presenter) }
        # der Speicherbalken einer Zeile wächst von links; danach gilt wieder der gebundene Wert
        $bar = if ($presenter -and $presenter.ContentTemplate) { $presenter.ContentTemplate.FindName('RowBar', $presenter) }
        $share = $ui.SheetList.Items[$i].Bar
        if ($bar -and $share) {
            $grow = New-DoubleAnim -From 0 -To ([double]$share) -Ms 700 -Delay $delay -Ease $script:EaseInOut
            $grow.FillBehavior = 'Stop'
            $bar.RenderTransform.BeginAnimation($P.ScaleX, $grow)
        }
        $kind = "$($ui.SheetList.Items[$i].Kind)"
        if ($kind -eq 'pair' -and $presenter -and $presenter.ContentTemplate) {
            # Schlüssel und Wert: der Wert rückt kurz nach seiner Bezeichnung von rechts nach
            $pair = $presenter.ContentTemplate.FindName('Pair', $presenter)
            $value = if ($pair -and $pair.Child -and $pair.Child.Children.Count -gt 1) { $pair.Child.Children[1] }
            if ($value) {
                $value.RenderTransform = New-Object Windows.Media.TranslateTransform
                $value.BeginAnimation($P.Opacity, $null)
                $value.Opacity = 0
                Start-Fade $value 1 300 ($delay + 130)
                $value.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From 12 -To 0 -Ms 400 -Delay ($delay + 130)))
            }
        }
        elseif ($kind -eq 'head' -and $presenter -and $presenter.ContentTemplate) {
            # Überschrift eines Abschnitts: der farbige Strich wächst aus der Mitte
            $head = $presenter.ContentTemplate.FindName('Head', $presenter)
            if ($head -and $head.Children.Count -gt 0) {
                $mark = $head.Children[0]
                $mark.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
                $mark.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 0
                $mark.RenderTransform.BeginAnimation($P.ScaleY, (New-DoubleAnim -To 1 -Ms 420 -Delay $delay -Ease $script:EaseBack))
            }
        }
        $state = if ($presenter -and $presenter.ContentTemplate) { $presenter.ContentTemplate.FindName('State', $presenter) }
        if ($state -and $state.Parent -and $state.Text) {
            # das Zustandsschild rechts ("fehlt", "veraltet", "installiert") springt kurz nach der Zeile auf
            $badge = $state.Parent
            $badge.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $badge.RenderTransform = New-Object Windows.Media.ScaleTransform 0, 0
            Start-Scale $badge 1 440 ($delay + 160) $null $script:EaseBack
        }
        if ($glyph -and $glyph.Parent) {
            $tile = $glyph.Parent
            $tile.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $tile.RenderTransform = New-Object Windows.Media.ScaleTransform
            Start-Scale $tile 1 650 $delay 0.5 $script:EaseElastic
        }
    }
    # der Text in der Fußzeile blendet mit auf
    Start-Fade $ui.SheetState 1 420 0 0
}

# Leert die freie Fläche (für Einstellungen und Texte) und zeigt sie statt der Liste
function Show-SheetPanel {
    Stop-SheetLoader
    $ui.SheetList.ItemsSource = $null
    $ui.SheetList.Visibility = 'Collapsed'
    $ui.SheetPanel.Children.Clear()
    $ui.SheetScroll.Visibility = 'Visible'
    $ui.SheetScroll.ScrollToTop()
    Start-Fade $ui.SheetScroll 1 260 0 0
}

function Set-SheetButtons([string]$Primary, [string]$Secondary = 'Schließen', [string]$Link) {
    $ui.BtnSheetPrimary.Content = T $Primary
    $ui.BtnSheetPrimary.Visibility = if ($Primary) { 'Visible' } else { 'Collapsed' }
    $ui.BtnSheetPrimary.IsEnabled = $true
    $ui.BtnSheetSecondary.Content = T $Secondary
    $ui.BtnSheetLink.Content = T $Link
    $ui.BtnSheetLink.Visibility = if ($Link) { 'Visible' } else { 'Collapsed' }
}

function Select-SheetTab([int]$Index, [switch]$Initial) {
    if (-not $script:Sheet) { return }
    # Richtung des Wechsels: der Inhalt kommt von der Seite, auf der der neue Reiter liegt
    $script:SheetWay = if ($Initial -or $null -eq $script:Sheet.Tab) { 0 } else { [Math]::Sign($Index - [int]$script:Sheet.Tab) }
    $script:Sheet.Tab = $Index
    if ($script:SheetTabButtons.Count -gt 0) {
        $button = $script:SheetTabButtons[$Index]
        $button.IsChecked = $true
        $ui.SheetTabs.UpdateLayout()
        $origin = $button.TranslatePoint((New-Object Windows.Point 0, 0), $ui.SheetTabs)
        $mark = $ui.SheetTabMark
        if ($Initial) {
            $mark.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $null)
            $mark.RenderTransform.BeginAnimation($P.X, $null)
            $mark.Width = $button.ActualWidth
            $mark.RenderTransform.X = $origin.X
            Start-Fade $mark 1 260 120 0
        }
        else {
            # die Marke gleitet zum gewählten Reiter und nimmt dessen Breite an
            $mark.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To $origin.X -Ms 340 -Ease $script:EaseBack))
            $mark.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-DoubleAnim -To $button.ActualWidth -Ms 300))
        }
    }
    $ui.SheetSearch.Text = ''
    & $script:Sheet.Show $Index
}

# $Definition: Title, Sub, Glyph, Tabs, Primary, Secondary, Link, Search und die Abläufe
# Show (Reiter gewählt), OnPrimary, OnSecondary, OnLink, OnAction (Textknopf einer Zeile), OnCheck, OnClose
function Open-Sheet([hashtable]$Definition) {
    if ($script:Dialog -or ($script:Busy -and $script:Busy -ne 'scan')) { return $false }
    Close-Drawer
    $alreadyOpen = [bool]$script:Sheet
    Add-MemTrace "Fenster auf: $($Definition.Title)"
    # tritt ein Dialog an die Stelle eines anderen, räumt der alte trotzdem auf (Messung, laufender Test)
    if ($alreadyOpen) { Stop-Meter; $script:Query = $null; if ($script:Sheet.OnClose) { & $script:Sheet.OnClose } }
    $script:Sheet = $Definition
    $ui.SheetTitle.Text = T $Definition.Title
    $ui.SheetSub.Text = T $Definition.Sub
    $ui.SheetGlyph.Text = Get-Glyph $Definition.Glyph
    $ui.SheetState.Text = ''
    $ui.SheetChart.Visibility = 'Collapsed'
    $ui.SheetSearchBox.Visibility = if ($Definition.Search) { 'Visible' } else { 'Collapsed' }
    $ui.SheetPanel.Children.Clear()
    $ui.SheetChips.Children.Clear()
    Set-SheetButtons $Definition.Primary $(if ($Definition.Secondary) { $Definition.Secondary } else { 'Schließen' }) $Definition.Link

    $ui.SheetTabs.Children.Clear()
    $script:SheetTabButtons = @()
    $tabs = @($Definition.Tabs | Where-Object { $_ })
    $ui.SheetTabRow.Visibility = if ($tabs.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    if ($tabs.Count -gt 1) {
        for ($i = 0; $i -lt $tabs.Count; $i++) {
            $button = New-Object Windows.Controls.RadioButton
            $button.Style = $window.FindResource('PillTab')
            $button.Content = T $tabs[$i]
            $button.GroupName = 'SheetTabs'
            $button.Tag = $i
            $button.Add_Click({ try { Select-SheetTab ([int]$this.Tag) } catch { Write-AppError $_ } })
            [void]$ui.SheetTabs.Children.Add($button)
            $script:SheetTabButtons += $button
        }
    }

    if (-not $alreadyOpen) {
        $ui.Sheet.Visibility = 'Visible'
        Start-Fade $ui.SheetDim 1 220
        Start-Fade $ui.SheetCard 1 240 40 0
        Start-Scale $ui.SheetCard 1 420 40 0.92 $script:EaseBack
        # der Kopf baut sich auf: das Symbol federt, Titel und Untertitel gleiten nach; die Knöpfe unten steigen auf
        $symbol = $ui.SheetGlyph.Parent
        $symbol.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $symbol.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Scale $symbol 1 750 40 0.5 $script:EaseElastic
        Start-Reveal $ui.SheetTitle 120 8
        Start-Reveal $ui.SheetSub 180 8
        $wait = 260
        foreach ($button in $ui.BtnSheetLink, $ui.BtnSheetSecondary, $ui.BtnSheetPrimary) {
            if ($button.Visibility -ne 'Visible') { continue }
            Start-Reveal $button $wait 10
            $wait += 60
        }
    }
    Select-SheetTab 0 -Initial
    $true
}

function Close-Sheet([switch]$Quick) {
    if (-not $script:Sheet) { return }
    Add-MemTrace 'Fenster zu'
    Update-ScanHint   # in den Einstellungen können die Quellen des Scans geändert worden sein
    $closing = $script:Sheet
    $script:Sheet = $null
    $script:Query = $null
    Stop-Meter
    Stop-SheetLoader
    if ($Quick) {
        # gleich danach öffnet sich ein anderer Dialog - nicht erst ausblenden
        foreach ($element in $ui.SheetDim, $ui.SheetCard) { $element.BeginAnimation($P.Opacity, $null); $element.Opacity = 0 }
        $ui.Sheet.Visibility = 'Collapsed'
        $ui.SheetList.ItemsSource = $null
    }
    else {
        Start-Fade $ui.SheetDim 0 200
        Start-Fade $ui.SheetCard 0 160
        Start-Scale $ui.SheetCard 0.95 200
        Invoke-Later 220 {
            if (-not $script:Sheet) {
                $ui.Sheet.Visibility = 'Collapsed'
                $ui.SheetList.ItemsSource = $null
                $ui.SheetPanel.Children.Clear()
            }
        }
    }
    if ($closing.OnClose) { & $closing.OnClose }
}

$ui.BtnSheetClose.Add_Click({ try { Close-Sheet } catch { Write-AppError $_ } })
$ui.BtnSheetSecondary.Add_Click({
        try { if ($script:Sheet -and $script:Sheet.OnSecondary) { & $script:Sheet.OnSecondary } else { Close-Sheet } }
        catch { Write-AppError $_ }
    })
$ui.BtnSheetPrimary.Add_Click({ try { if ($script:Sheet -and $script:Sheet.OnPrimary) { & $script:Sheet.OnPrimary } } catch { Write-AppError $_ } })
$ui.BtnSheetLink.Add_Click({ try { if ($script:Sheet -and $script:Sheet.OnLink) { & $script:Sheet.OnLink } } catch { Write-AppError $_ } })
$ui.SheetSearch.Add_TextChanged({
        try {
            $ui.SheetSearchHint.Visibility = if ($ui.SheetSearch.Text) { 'Collapsed' } else { 'Visible' }
            if ($script:Sheet -and $ui.SheetList.Visibility -eq 'Visible') { Update-SheetList }
        }
        catch { Write-AppError $_ }
    })
# Klicks in der Liste: Auswahlkästchen und Textknöpfe der Zeilen melden sich hier gesammelt
$ui.SheetList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
        param($sender, $e)
        try {
            if (-not $script:Sheet) { return }
            $source = $e.OriginalSource
            $item = $source.DataContext
            if (-not $item -or -not $item.PSObject.Properties['Kind']) { return }
            if ($source -is [Windows.Controls.CheckBox]) {
                $item.Checked = [bool]$source.IsChecked
                if ($script:Sheet.OnCheck) { & $script:Sheet.OnCheck $item }
            }
            elseif ($source -is [Windows.Controls.Button]) {
                if ($script:Sheet.OnAction) { & $script:Sheet.OnAction $item }
            }
        }
        catch { Write-AppError $_ }
    })

# --- Verlaufskurve für Prozessor und Arbeitsspeicher --------------------------
# Ein eigener kleiner Arbeitsbereich misst jede Sekunde; das Fenster zeichnet nur.

$script:Meter = $null
$script:OldMeters = @()
$meterCode = @'
param($id)
$counter = $null
foreach ($name in @('Processor Information', '% Processor Utility'), @('Processor', '% Processor Time')) {
    try {
        $counter = New-Object Diagnostics.PerformanceCounter $name[0], $name[1], '_Total'
        [void]$counter.NextValue()
        break
    }
    catch { $counter = $null }
}
while ($sync.MeterId -eq $id) {
    Start-Sleep -Milliseconds 1000
    try { if ($counter) { $sync.Cpu = [double]$counter.NextValue() } } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize
        $sync.Ram = 100.0 * (1.0 - [double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)
    }
    catch { }
}
'@

function Start-Meter {
    if ($script:Meter) { return }
    # beendete Messschleifen früherer Dialoge aufräumen
    $script:OldMeters = @($script:OldMeters | Where-Object {
            if ($_ -and $_.Ps.InvocationStateInfo.State -ne 'Running') { try { $_.Ps.Dispose(); $_.Space.Dispose() } catch { }; $false } else { [bool]$_ }
        })
    # jede Messschleife läuft nur, solange ihre Nummer die aktuelle ist
    $sync.MeterId = [int]$sync.MeterId + 1
    $sync.Cpu = -1.0
    $sync.Ram = -1.0
    $meterSpace = [runspacefactory]::CreateRunspace()
    $meterSpace.Open()
    $meterSpace.SessionStateProxy.SetVariable('sync', $sync)
    $ps = [powershell]::Create()
    $ps.Runspace = $meterSpace
    [void]$ps.AddScript($meterCode).AddArgument($sync.MeterId)
    [void]$ps.BeginInvoke()
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $timer.Add_Tick({ try { Update-Chart } catch { Write-AppError $_ } })
    $timer.Start()
    $shift = New-Object Windows.Media.TranslateTransform
    $ui.ChartLine.RenderTransform = $shift
    $ui.ChartFill.RenderTransform = $shift
    $script:Meter = @{ Space = $meterSpace; Ps = $ps; Timer = $timer; Shift = $shift; Kind = ''
        Cpu = (New-Object 'System.Collections.Generic.List[double]'); Ram = (New-Object 'System.Collections.Generic.List[double]') }
}

function Stop-Meter {
    if (-not $script:Meter) { return }
    $sync.MeterId = [int]$sync.MeterId + 1   # die Messschleife endet von selbst nach ihrem nächsten Takt
    $script:Meter.Timer.Stop()
    $script:OldMeters = @($script:OldMeters) + @{ Ps = $script:Meter.Ps; Space = $script:Meter.Space }
    $script:Meter = $null
}

# Zählt die große Prozentzahl neben der Kurve weich vom alten zum neuen Messwert
$script:ChartShown = $null
function Start-ChartCount([double]$To) {
    if (-not $script:Settings.Animations -or $null -eq $script:ChartShown) {
        $script:ChartShown = $To
        $ui.ChartValue.Text = '{0:N0} %' -f $To
        return
    }
    $script:ChartCount = @{ From = [double]$script:ChartShown; To = $To; Start = [DateTime]::UtcNow }
    if (-not $script:ChartCountTimer) {
        $script:ChartCountTimer = New-Object Windows.Threading.DispatcherTimer
        $script:ChartCountTimer.Interval = [TimeSpan]::FromMilliseconds(40)
        $script:ChartCountTimer.Add_Tick({
                try {
                    $count = $script:ChartCount
                    $t = [Math]::Min(1.0, ([DateTime]::UtcNow - $count.Start).TotalMilliseconds / 600)
                    $eased = 1 - [Math]::Pow(1 - $t, 3)
                    $script:ChartShown = $count.From + ($count.To - $count.From) * $eased
                    $ui.ChartValue.Text = '{0:N0} %' -f $script:ChartShown
                    if ($t -ge 1) { $script:ChartCountTimer.Stop() }
                }
                catch { $script:ChartCountTimer.Stop(); Write-AppError $_ }
            })
    }
    $script:ChartCountTimer.Start()
}

# Ring, der sich bei jedem neuen Messwert vom Punkt am Ende der Kurve löst
$script:ChartPing = New-Object Windows.Shapes.Ellipse
$script:ChartPing.Width = 9; $script:ChartPing.Height = 9
$script:ChartPing.Stroke = [Windows.Media.Brushes]::White
$script:ChartPing.StrokeThickness = 1.2
$script:ChartPing.HorizontalAlignment = 'Left'; $script:ChartPing.VerticalAlignment = 'Top'
$script:ChartPing.Margin = '-4.5,-4.5,0,0'
$script:ChartPing.Opacity = 0
$script:ChartPing.IsHitTestVisible = $false
$script:ChartPingScale = New-Object Windows.Media.ScaleTransform 1, 1, 4.5, 4.5
$script:ChartPingMove = New-Object Windows.Media.TranslateTransform
$chartPingGroup = New-Object Windows.Media.TransformGroup
$chartPingGroup.Children.Add($script:ChartPingScale)
$chartPingGroup.Children.Add($script:ChartPingMove)
$script:ChartPing.RenderTransform = $chartPingGroup
[void]$ui.ChartArea.Children.Add($script:ChartPing)

# $Kind: 'cpu', 'ram' oder leer (Kurve ausblenden)
function Show-Chart([string]$Kind) {
    if (-not $script:Meter) { return }
    $script:Meter.Kind = $Kind
    if (-not $Kind) {
        $ui.SheetChart.Visibility = 'Collapsed'
        return
    }
    $ui.ChartLabel.Text = T $(if ($Kind -eq 'cpu') { 'PROZESSOR-AUSLASTUNG' } else { 'ARBEITSSPEICHER BELEGT' })
    if ($ui.SheetChart.Visibility -ne 'Visible') {
        $ui.SheetChart.Visibility = 'Visible'
        # die Kurve steigt von unten auf
        Start-Reveal $ui.SheetChart 0 18 340
    }
    Update-Chart -Redraw
}

function Update-Chart([switch]$Redraw) {
    $meter = $script:Meter
    if (-not $meter) { return }
    if (-not $Redraw) {
        foreach ($pair in @(@{ List = $meter.Cpu; Value = $sync.Cpu }, @{ List = $meter.Ram; Value = $sync.Ram })) {
            if ($pair.Value -lt 0) { continue }
            $value = [double]$pair.Value
            if ($value -gt 100.0) { $value = 100.0 }
            $pair.List.Add($value)
            while ($pair.List.Count -gt 61) { $pair.List.RemoveAt(0) }
        }
    }
    if (-not $meter.Kind) { return }
    $list = if ($meter.Kind -eq 'cpu') { $meter.Cpu } else { $meter.Ram }
    if ($list.Count -eq 0) {
        $ui.ChartValue.Text = '– %'
        $script:ChartShown = $null
        $ui.ChartLine.Data = $null; $ui.ChartFill.Data = $null
        return
    }
    # beim Wechsel zwischen Prozessor und Speicher steht der Wert sofort da, danach zählt er von Messung zu Messung
    if ($Redraw) { $script:ChartShown = $null }
    Start-ChartCount $list[$list.Count - 1]
    $width = $ui.ChartArea.ActualWidth
    if ($width -lt 50) { $width = 660.0 }
    $height = 74.0
    $right = $width - 16.0     # Platz für den Punkt am rechten Ende und den Ring, der sich von ihm löst
    $step = $right / 60.0
    $culture = [cultureinfo]::InvariantCulture
    $points = New-Object Text.StringBuilder
    $firstX = 0.0; $lastY = 0.0
    for ($i = 0; $i -lt $list.Count; $i++) {
        $x = $right - ($list.Count - 1 - $i) * $step
        $y = $height - 4.0 - $list[$i] / 100.0 * ($height - 10.0)
        if ($i -eq 0) { $firstX = $x }
        $lastY = $y
        [void]$points.Append([string]::Format($culture, '{0}{1:0.##},{2:0.##} ', $(if ($i -eq 0) { 'M ' } else { 'L ' }), $x, $y))
    }
    $line = $points.ToString()
    $ui.ChartLine.Data = [Windows.Media.Geometry]::Parse($line)
    $ui.ChartFill.Data = [Windows.Media.Geometry]::Parse($line + [string]::Format($culture, 'L {0:0.##},{1:0.##} L {2:0.##},{1:0.##} Z', $right, $height, $firstX))
    # die Kurve gleitet einen Messschritt nach links, der neue Wert rückt von rechts nach
    if (-not $Redraw -and $script:Settings.Animations) {
        $meter.Shift.BeginAnimation($P.X, (New-DoubleAnim -From $step -To 0 -Ms 1000 -Linear))
    }
    $ui.ChartDot.Opacity = 1
    $ui.ChartDot.RenderTransform.X = $right
    $ui.ChartDot.RenderTransform.BeginAnimation($P.Y, (New-DoubleAnim -To $lastY -Ms 600))
    if (-not $Redraw -and $script:Settings.Animations) {
        $script:ChartPingMove.X = $right
        $script:ChartPingMove.Y = $lastY
        $script:ChartPingScale.BeginAnimation($P.ScaleX, (New-DoubleAnim -From 1 -To 3.2 -Ms 800))
        $script:ChartPingScale.BeginAnimation($P.ScaleY, (New-DoubleAnim -From 1 -To 3.2 -Ms 800))
        Start-Fade $script:ChartPing 0 800 0 0.7
    }
}

# --- Boost einrichten ---------------------------------------------------------

function Open-BoostSheet {
    $boostOn = Test-Path -LiteralPath (Join-Path $script:OutDir 'Spiel-Beschleunigung.json')
    $definition = @{
        Title       = 'Boost einrichten'
        Sub         = 'Auswählen, was die Spiel-Beschleunigung schließt, anhält und umstellt'
        Glyph       = 0xEC4A
        Tabs        = 'Programme', 'Dienste', 'Weitere', 'Spiele'
        Link        = 'Empfohlene Auswahl'
        Search      = $true
        Show        = { param($tab) Show-BoostTab }
        OnLink      = { Set-BoostRecommended }
        OnCheck     = { param($item) Update-BoostState }
    }
    if ($boostOn) {
        # eingeschaltet: nur die Auswahl für das nächste Mal ändern
        $definition.Primary = 'Speichern'
        $definition.Secondary = 'Abbrechen'
        $definition.OnPrimary = { Save-BoostSheet; Close-Sheet }
    }
    else {
        $definition.Primary = 'Boost starten'
        $definition.Secondary = 'Nur speichern'
        $definition.OnPrimary = { Save-BoostSheet; Close-Sheet -Quick; Start-Boost }
        $definition.OnSecondary = { Save-BoostSheet; Close-Sheet }
    }
    if (-not (Open-Sheet $definition)) { return }
    Start-SheetLoader 'Lese Programme und Dienste …'
    Start-Query 'Boost' { param($result) Complete-BoostQuery $result }
}

function Complete-BoostQuery($Result) {
    if (-not $script:Sheet) { return }
    $games = @($Result.Games)
    $Result = $Result.Choices
    $plan = $script:Settings.Boost
    $apps = @($Result.Apps)
    $largest = [double](($apps | Measure-Object Bytes -Maximum).Maximum)
    if ($largest -le 0) { $largest = 1.0 }

    $appRows = @()
    $newApp = {
        param($app)
        $title = if ($app.Count -gt 1) { "$($app.Name)   ×$($app.Count)" } else { $app.Name }
        $sub = if ($app.Description -and $app.Description -ne $app.Name) { $app.Description } else { '' }
        New-SheetRow -Title $title -Sub $sub -Value ('{0:N0} MB' -f ($app.Bytes / 1MB)) -Bar ($app.Bytes / $largest) -Checkable -Glyph 0xECAA `
            -Checked ($plan.Apps -contains $app.Name) -Data @{ Type = 'app'; Name = $app.Name; Suggested = [bool]$app.Suggested }
    }
    $suggested = @($apps | Where-Object { $_.Suggested })
    # gemerkte Programme, die gerade nicht laufen, bleiben in der Auswahl sichtbar
    $absent = @($plan.Apps | Where-Object { $_ -and ($apps | ForEach-Object { $_.Name }) -notcontains $_ })
    if ($suggested.Count -gt 0 -or $absent.Count -gt 0) {
        $appRows += New-SheetRow -Kind 'head' -Title 'VORGESCHLAGEN ODER GEMERKT'
        foreach ($app in $suggested) { $appRows += & $newApp $app }
        foreach ($name in $absent) {
            $appRows += New-SheetRow -Title $name -Value 'läuft nicht' -Glyph 0xECAA -Checkable -Checked $true -Data @{ Type = 'app'; Name = $name; Suggested = $false }
        }
    }
    $others = @($apps | Where-Object { -not $_.Suggested })
    if ($others.Count -gt 0) {
        $appRows += New-SheetRow -Kind 'head' -Title 'LAUFENDE PROGRAMME, GRÖSSTE ZUERST'
        foreach ($app in $others) { $appRows += & $newApp $app }
    }

    $serviceRows = @()
    $known = @($Result.Services | Where-Object { $_.Known })
    $foreign = @($Result.Services | Where-Object { -not $_.Known })
    $newService = {
        param($service)
        $checked = if ($null -eq $plan.Services) { [bool]$service.Known } else { $plan.Services -contains $service.Name }
        New-SheetRow -Title $service.Title -Sub $service.Description -Glyph 0xE9F5 -Checkable -Checked $checked `
            -Data @{ Type = 'service'; Name = $service.Name; Suggested = [bool]$service.Known }
    }
    if ($known.Count -gt 0) {
        $serviceRows += New-SheetRow -Kind 'head' -Title 'ENTBEHRLICHE WINDOWS-DIENSTE, DIE GERADE LAUFEN'
        foreach ($service in $known) { $serviceRows += & $newService $service }
    }
    if ($foreign.Count -gt 0) {
        $serviceRows += New-SheetRow -Kind 'head' -Title 'DIENSTE ANDERER HERSTELLER'
        foreach ($service in $foreign) { $serviceRows += & $newService $service }
    }
    if ($serviceRows.Count -eq 0) { $serviceRows += New-SheetRow -Title 'Keine entbehrlichen Dienste gefunden' }

    $otherRows = @(
        New-SheetRow -Title 'Energieplan „Höchstleistung“' -Sub 'Stellt den Energieplan um und nach dem Spielen wieder zurück' -Glyph 0xE945 -Checkable `
            -Checked ([bool]$plan.PowerPlan) -Data @{ Type = 'option'; Name = 'PowerPlan'; Suggested = $true }
        New-SheetRow -Title 'Spielmodus von Windows' -Sub 'Schaltet den Spielmodus ein, falls er ausgeschaltet ist' -Glyph 0xE7FC -Checkable `
            -Checked ([bool]$plan.GameMode) -Data @{ Type = 'option'; Name = 'GameMode'; Suggested = $true }
        New-SheetRow -Title 'Zwischenablage leeren' -Sub 'Gibt den Speicher frei, den kopierte Inhalte belegen' -Glyph 0xE77F -Checkable `
            -Checked ([bool]$plan.Clipboard) -Data @{ Type = 'option'; Name = 'Clipboard'; Suggested = $false }
    )
    # Spiele für den automatischen Boost: die, die Windows kennt, und gemerkte, die gerade nicht mehr da sind
    $gameRows = @()
    if (-not $script:Settings.AutoBoost) {
        $gameRows += New-SheetRow -Title 'Boost automatisch ist ausgeschaltet' -Sub 'Einschalten unter Einstellungen → Hintergrund. Die Auswahl hier gilt dann sofort.' -Glyph 0xE946
    }
    $knownExe = @($games | ForEach-Object { $_.Exe })
    $gameRows += New-SheetRow -Kind 'head' -Title 'SPIELE, DIE WINDOWS KENNT'
    foreach ($game in $games) {
        $gameRows += New-SheetRow -Title $game.Name -Sub ("$($game.Exe).exe" + $(if ($game.Running) { ' · läuft gerade' })) -Glyph 0xE7FC -Checkable `
            -Checked (@($script:Settings.BoostGames) -contains $game.Exe) -Data @{ Type = 'game'; Name = $game.Exe; Suggested = $false }
    }
    foreach ($exe in @($script:Settings.BoostGames | Where-Object { $_ -and $knownExe -notcontains $_ })) {
        $gameRows += New-SheetRow -Title $exe -Sub 'gemerkt, Windows kennt es nicht mehr' -Glyph 0xE7FC -Checkable -Checked $true -Data @{ Type = 'game'; Name = $exe; Suggested = $false }
    }
    if ($games.Count -eq 0 -and @($script:Settings.BoostGames).Count -eq 0) {
        $gameRows += New-SheetRow -Title 'Windows kennt auf diesem PC noch keine Spiele' -Sub 'Ein Spiel erscheint hier, sobald Windows es einmal als Spiel erkannt hat.' -Glyph 0xE946
    }
    $script:Sheet.Lists = @($appRows, $serviceRows, $otherRows, $gameRows)
    Show-BoostTab
    Update-BoostState
}

function Show-BoostTab {
    if (-not $script:Sheet.Lists) {
        Start-SheetLoader 'Lese Programme und Dienste …'
        return
    }
    Show-SheetList $script:Sheet.Lists[$script:Sheet.Tab]
}

function Get-BoostChecked([string]$Type) {
    @($script:Sheet.Lists | ForEach-Object { $_ } | Where-Object { $_.Kind -eq 'row' -and $_.Data -and $_.Data.Type -eq $Type -and $_.Checked } | ForEach-Object { $_.Data.Name })
}

function Update-BoostState {
    if (-not $script:Sheet.Lists) { return }
    $apps = @(Get-BoostChecked 'app').Count
    $services = @(Get-BoostChecked 'service').Count
    $text = 'Gewählt: {0} · {1} · {2} weitere' -f $(if ($apps -eq 1) { '1 Programm' } else { "$apps Programme" }), $(if ($services -eq 1) { '1 Dienst' } else { "$services Dienste" }), @(Get-BoostChecked 'option').Count
    $gameCount = @(Get-BoostChecked 'game').Count
    if ($gameCount -gt 0) { $text += $(if ($gameCount -eq 1) { ' · 1 Spiel' } else { " · $gameCount Spiele" }) }
    if (-not $script:IsAdmin) { $text += ' · nur Probelauf' }
    # ändert sich die Auswahl, gleitet die neue Zählung herein
    if ($ui.SheetState.Text -and $ui.SheetState.Text -ne $text) {
        if ($ui.SheetState.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $ui.SheetState.RenderTransform = New-Object Windows.Media.TranslateTransform }
        Start-Fade $ui.SheetState 1 240 0 0
        Start-Slide $ui.SheetState 0 320 0 7
    }
    $ui.SheetState.Text = T $($text)
}

function Set-BoostRecommended {
    if (-not $script:Sheet.Lists) { return }
    foreach ($row in @($script:Sheet.Lists | ForEach-Object { $_ })) {
        # die Spiele sind keine Empfehlung, sondern die eigene Wahl: sie bleiben, wie sie sind
        if ($row.Kind -eq 'row' -and $row.Data -and $row.Data.Type -ne 'game') { $row.Checked = [bool]$row.Data.Suggested }
    }
    $ui.SheetList.Items.Refresh()
    # die Liste baut sich mit der empfohlenen Auswahl neu auf
    $script:SheetWay = 0
    Start-SheetRows
    Update-BoostState
}

function Save-BoostSheet {
    if (-not $script:Sheet -or -not $script:Sheet.Lists) { return }
    $options = Get-BoostChecked 'option'
    $script:Settings.Boost = @{
        Apps      = @(Get-BoostChecked 'app')
        Services  = @(Get-BoostChecked 'service')
        PowerPlan = $options -contains 'PowerPlan'
        GameMode  = $options -contains 'GameMode'
        Clipboard = $options -contains 'Clipboard'
    }
    $script:Settings.BoostGames = @(Get-BoostChecked 'game')
    Save-Settings
    # die Schilder auf der Boost-Seite zeigen die neue Auswahl
    if ($script:Page -eq 'Boost') { Update-Boost }
}

function Start-Boost {
    Open-ToolDialog 'GameBoost'
    Invoke-Later 450 { if ($script:Dialog -and $script:Dialog.Name -eq 'GameBoost') { Start-DialogJob } }
}

# --- Spielkomponenten ---------------------------------------------------------

function Open-RuntimeSheet {
    $opened = Open-Sheet @{
        Title     = 'Spielkomponenten'
        Sub       = 'Laufzeitbibliotheken, die Spiele voraussetzen'
        Glyph     = 0xE7FC
        Tabs      = 'Komponenten', 'Einzelne Dateien'
        Primary   = 'Ausgewählte installieren'
        Link      = 'Vorhandene ausblenden'
        Search    = $true
        ShowAll   = @($true, $false)     # je Reiter: auch Vorhandenes zeigen?
        Show      = { param($tab) Show-RuntimeTab }
        OnPrimary = {
            $names = @($script:Sheet.Components | Where-Object { $_.Checked } | ForEach-Object { $_.Data.Name })
            if ($names.Count -gt 0) { Close-Sheet -Quick; Open-RuntimeInstall $names }
        }
        OnLink    = {
            $script:Sheet.ShowAll[$script:Sheet.Tab] = -not $script:Sheet.ShowAll[$script:Sheet.Tab]
            # kein Reiterwechsel: die Liste baut sich von unten neu auf
            $script:SheetWay = 0
            Show-RuntimeTab
        }
        OnAction  = {
            param($item)
            $name = if ($item.Data.Type -eq 'file') { $item.Data.Component } else { $item.Data.Name }
            Close-Sheet -Quick
            Open-RuntimeInstall @($name)
        }
        OnCheck   = { param($item) Update-RuntimeState }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Prüfe die Komponenten …'
    Start-Query 'Runtime' { param($result) Complete-RuntimeQuery $result }
}

function Complete-RuntimeQuery($Result) {
    if (-not $script:Sheet) { return }
    $components = @($Result.Components)
    $withUrl = @{}
    foreach ($component in $components) { $withUrl[$component.Name] = [bool]$component.Url }

    $script:Sheet.Components = @(foreach ($component in $components) {
            $tone = switch ($component.Status) { 'vorhanden' { 'good' } 'veraltet' { 'warn' } default { '' } }
            $glyph = switch ($component.Status) { 'vorhanden' { 0xE73E } 'veraltet' { 0xE72C } default { 0xE896 } }
            $action = if (-not $component.Url) { '' } elseif ($component.Status -eq 'vorhanden') { 'Neu installieren' } else { 'Installieren' }
            $sub = if ($component.Version -match '^\d') { "Version $($component.Version)" } else { "$($component.Version)" }
            New-SheetRow -Title $component.Name -Sub $sub -State $component.Status -Tone $tone -Glyph $glyph -Action $action -Checkable:([bool]$component.Url) `
                -Checked ($component.Status -eq 'veraltet') -Data @{ Type = 'component'; Name = $component.Name; Status = $component.Status }
        })

    $files = @($Result.Files)
    $script:Sheet.Files = @(foreach ($group in ($files | Group-Object Group)) {
            $missing = @($group.Group | Where-Object { $_.Status -ne 'vorhanden' }).Count
            $detail = if ($missing) { "$missing von $($group.Count) fehlen" } else { "alle $($group.Count) vorhanden" }
            New-SheetRow -Kind 'head' -Title ("$($group.Name) – $detail").ToUpper() -Data @{ Type = 'head'; Missing = $missing }
            foreach ($file in $group.Group) {
                $present = $file.Status -eq 'vorhanden'
                New-SheetRow -Title $file.Name -Value $file.Arch -State $file.Status -Tone $(if ($present) { 'good' } else { '' }) -Glyph $(if ($present) { 0xE73E } else { 0xE896 }) `
                    -Action $(if (-not $present -and $withUrl[$file.Component]) { 'Beheben' } else { '' }) `
                    -Data @{ Type = 'file'; Component = $file.Component; Status = $file.Status }
            }
        })

    $missingComponents = @($components | Where-Object { $_.Status -eq 'fehlt' }).Count
    $outdated = @($components | Where-Object { $_.Status -eq 'veraltet' }).Count
    $missingFiles = @($files | Where-Object { $_.Status -ne 'vorhanden' }).Count
    # Bilanz als Schilder neben den Reitern
    $ui.SheetChips.Children.Clear()
    Add-ResultChip $(if ($missingComponents -eq 1) { '1 Komponente fehlt' } elseif ($missingComponents) { "$missingComponents Komponenten fehlen" } else { 'Keine Komponente fehlt' }) $(if ($missingComponents) { 'Warn' } else { 'Good' }) $ui.SheetChips
    if ($outdated) { Add-ResultChip "$outdated veraltet" 'Warn' $ui.SheetChips }
    Add-ResultChip $(if ($missingFiles) { "$missingFiles von $($files.Count) Dateien fehlen" } else { "$($files.Count) Dateien vorhanden" }) $(if ($missingFiles) { 'Warn' } else { 'Good' }) $ui.SheetChips
    Show-RuntimeTab
}

function Show-RuntimeTab {
    if (-not $script:Sheet.Components) {
        Start-SheetLoader 'Prüfe die Komponenten …'
        return
    }
    $tab = $script:Sheet.Tab
    $all = $script:Sheet.ShowAll[$tab]
    $rows = if ($tab -eq 0) { $script:Sheet.Components } else { $script:Sheet.Files }
    if (-not $all) {
        # Vorhandenes ausblenden; Überschriften nur behalten, wenn darunter etwas fehlt
        $rows = @($rows | Where-Object { if ($_.Kind -eq 'head') { $_.Data.Missing -gt 0 } else { $_.Data.Status -ne 'vorhanden' } })
        if ($rows.Count -eq 0) { $rows = @(New-SheetRow -Title 'Hier fehlt nichts' -Sub 'Alle geprüften Einträge sind vorhanden' -State 'vollständig' -Tone 'good' -Glyph 0xE73E) }
    }
    $ui.BtnSheetLink.Content = T $(if ($all) { 'Vorhandene ausblenden' } else { 'Vorhandene einblenden' })
    Show-SheetList $rows
    Update-RuntimeState
}

# Setzt den Text in der Fußzeile des großen Dialogs; ändert er sich, gleitet der neue von unten herein
function Set-SheetStateText([string]$Text) {
    $Text = T $Text
    if ($ui.SheetState.Text -and $ui.SheetState.Text -ne $Text) {
        if ($ui.SheetState.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $ui.SheetState.RenderTransform = New-Object Windows.Media.TranslateTransform }
        Start-Fade $ui.SheetState 1 240 0 0
        Start-Slide $ui.SheetState 0 320 0 7
    }
    $ui.SheetState.Text = $Text
}

function Update-RuntimeState {
    $selected = @($script:Sheet.Components | Where-Object { $_.Checked }).Count
    # der Knopf "Ausgewählte installieren" springt auf, sobald er benutzbar wird
    if ($selected -gt 0 -and -not $ui.BtnSheetPrimary.IsEnabled) {
        $ui.BtnSheetPrimary.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $ui.BtnSheetPrimary.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Scale $ui.BtnSheetPrimary 1 420 0 0.9 $script:EaseBack
    }
    $ui.BtnSheetPrimary.IsEnabled = $selected -gt 0
    Set-SheetStateText $(if ($selected -gt 0) { "$selected ausgewählt" } else { 'Nur nötig, wenn ein Spiel danach fragt.' })
}

# --- Systeminformationen ------------------------------------------------------

$script:SystemTabs = 'Übersicht', 'Windows', 'Prozessor', 'Speicher', 'Grafik', 'Laufwerke', 'Netzwerk', 'Geräte'

function Open-SystemSheet {
    $opened = Open-Sheet @{
        Title     = 'Systeminformationen'
        Sub       = 'Hardware und Windows im Überblick'
        Glyph     = 0xE946
        Tabs      = $script:SystemTabs
        Primary   = 'Als Text speichern'
        Show      = { param($tab) Show-SystemTab }
        OnPrimary = { Export-SystemInfo }
        OnLink    = { if ($script:Sheet.File) { Start-Process explorer.exe "/select,`"$($script:Sheet.File)`"" } }
    }
    if (-not $opened) { return }
    Start-Meter
    Start-SheetLoader 'Lese die Hardware aus …'
    Start-Query 'System' { param($result) if ($script:Sheet) { $script:Sheet.Info = @($result.Rows); Show-SystemTab } }
}

function Show-SystemTab {
    $name = $script:SystemTabs[$script:Sheet.Tab]
    Show-Chart $(switch ($name) { 'Prozessor' { 'cpu' } 'Speicher' { 'ram' } default { '' } })
    if (-not $script:Sheet.Info) {
        Start-SheetLoader 'Lese die Hardware aus …'
        return
    }
    $rows = @($script:Sheet.Info | Where-Object { $_.Category -eq $name } | ForEach-Object {
            if ($name -eq 'Übersicht' -and $_.Kind -ne 'head') {
                # die Übersicht als Karten: der Wert groß, darunter wozu er gehört
                $glyph = switch -Regex ($_.Title) {
                    'Windows' { 0xE770; break } 'Prozessor' { 0xE950; break } 'Grafik' { 0xE8B9; break } 'speicher' { 0xE9D9; break }
                    'Bildschirm' { 0xE7F4; break } 'Datentr' { 0xEDA2; break } 'Audio' { 0xE767; break } 'Tastatur' { 0xE765; break }
                    'Maus' { 0xE962; break } default { 0xE772 }
                }
                New-SheetRow -Title $_.Value -Sub $_.Title -Glyph $glyph -Tone 'accent'
            }
            else { New-SheetRow -Kind $_.Kind -Title $(if ($_.Kind -eq 'head') { "$($_.Title)".ToUpper() } else { $_.Title }) -Value $_.Value }
        })
    if ($rows.Count -eq 0) { $rows = @(New-SheetRow -Title 'Dazu liegt nichts vor') }
    Show-SheetList $rows
}

function Export-SystemInfo {
    if (-not $script:Sheet.Info) { return }
    $lines = @("Systeminformationen vom $((Get-Date).ToString('dd.MM.yyyy HH:mm'))", '')
    foreach ($category in $script:SystemTabs) {
        $lines += $category.ToUpper()
        foreach ($row in @($script:Sheet.Info | Where-Object { $_.Category -eq $category })) {
            $lines += if ($row.Kind -eq 'head') { "  [$($row.Title)]" } else { '  {0}: {1}' -f $row.Title, $row.Value }
        }
        $lines += ''
    }
    $file = Join-Path (Get-TargetDir) 'Systeminformationen.txt'
    Set-Content -LiteralPath $file -Value $lines -Encoding UTF8
    $script:Sheet.File = $file
    # die Bestätigung gleitet in die Fußzeile, der Verweis zum Ordner springt auf
    Set-SheetStateText "Gespeichert: $(Format-ShownPath $file)"
    $ui.BtnSheetLink.Content = T $('Im Ordner zeigen')
    if ($ui.BtnSheetLink.Visibility -ne 'Visible') {
        $ui.BtnSheetLink.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $ui.BtnSheetLink.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Pop $ui.BtnSheetLink 80
    }
    $ui.BtnSheetLink.Visibility = 'Visible'
}

# --- Treiberverlauf -----------------------------------------------------------

function Open-HistorySheet {
    $opened = Open-Sheet @{
        Title  = 'Treiberverlauf'
        Sub    = 'Was Windows Update eingespielt hat und wann Treiberpakete ins System kamen'
        Glyph  = 0xE81C
        Tabs   = 'Windows Update', 'Treiberpakete'
        Search = $true
        Show   = { param($tab) Show-HistoryTab }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese den Verlauf …'
    Start-Query 'History' { param($result) if ($script:Sheet) { $script:Sheet.History = $result; Show-HistoryTab } }
}

# Überschrift für einen Monat des Verlaufs aus einem Datumstext "TT.MM.JJJJ ..."; leer, wenn kein Datum erkennbar ist
function Get-HistoryMonth([string]$DateText) {
    if ($DateText -notmatch '^\d{2}\.(\d{2})\.(\d{4})') { return '' }
    $month = [int]$Matches[1]
    if ($month -lt 1 -or $month -gt 12) { return '' }
    '{0} {1}' -f ([cultureinfo]'de-DE').DateTimeFormat.GetMonthName($month), $Matches[2]
}

# Fügt vor jedem neuen Monat eine Überschrift mit der Zahl der Einträge ein
function Add-HistoryMonths($Items, [scriptblock]$NewRow) {
    $groups = [ordered]@{}
    foreach ($item in @($Items)) {
        $month = Get-HistoryMonth "$($item.DateText)"
        if (-not $month) { $month = 'Ohne Datum' }
        if (-not $groups.Contains($month)) { $groups[$month] = @() }
        $groups[$month] += $item
    }
    foreach ($month in $groups.Keys) {
        $count = @($groups[$month]).Count
        New-SheetRow -Kind 'head' -Title ("$month · $count " + $(if ($count -eq 1) { 'Eintrag' } else { 'Einträge' })).ToUpper()
        foreach ($item in $groups[$month]) { & $NewRow $item }
    }
}

function Show-HistoryTab {
    $history = $script:Sheet.History
    if (-not $history) {
        Start-SheetLoader 'Lese den Verlauf …'
        return
    }
    $ui.SheetChips.Children.Clear()
    if ($script:Sheet.Tab -eq 0) {
        $updates = @($history.Updates)
        $rows = @(Add-HistoryMonths $updates {
                param($update)
                $tone = switch ($update.Result) { 'installiert' { 'good' } 'fehlgeschlagen' { 'bad' } default { 'warn' } }
                $glyph = switch ($update.Result) { 'installiert' { 0xE73E } 'fehlgeschlagen' { 0xE711 } default { 0xE7BA } }
                New-SheetRow -Title $update.Title -Sub $update.DateText -Glyph $glyph -Tone $tone `
                    -State $(if ($update.Removed) { "entfernt · $($update.Result)" } else { $update.Result })
            })
        if ($updates.Count -eq 0) { $rows = @(New-SheetRow -Title 'Windows Update hat hier noch keinen Treiber eingespielt' -Glyph 0xE946) }
        else {
            $installed = @($updates | Where-Object { $_.Result -eq 'installiert' }).Count
            $failed = @($updates | Where-Object { $_.Result -eq 'fehlgeschlagen' }).Count
            Add-ResultChip "$installed installiert" 'Good' $ui.SheetChips
            if ($failed) { Add-ResultChip "$failed fehlgeschlagen" 'Bad' $ui.SheetChips }
            if ($updates.Count - $installed - $failed -gt 0) { Add-ResultChip "$($updates.Count - $installed - $failed) weitere" 'Warn' $ui.SheetChips }
        }
        $ui.SheetState.Text = T $('Aus dem Verlauf von Windows Update, neueste zuerst')
    }
    else {
        $packages = @($history.Packages)
        $rows = @(Add-HistoryMonths $packages {
                param($package)
                New-SheetRow -Title $package.Devices -Sub "$($package.Provider) · Version $($package.Version) · $($package.Inf)" `
                    -Value "seit $($package.DateText)" -Glyph 0xE7B8 -Tone 'accent'
            })
        if ($packages.Count -eq 0) { $rows = @(New-SheetRow -Title 'Keine Treiberpakete von Drittherstellern gefunden' -Glyph 0xE946) }
        else {
            Add-ResultChip $(if ($packages.Count -eq 1) { '1 Treiberpaket' } else { "$($packages.Count) Treiberpakete" }) 'Accent' $ui.SheetChips
            $makers = @($packages | ForEach-Object { "$($_.Provider)" } | Where-Object { $_ } | Sort-Object -Unique).Count
            if ($makers) { Add-ResultChip $(if ($makers -eq 1) { '1 Hersteller' } else { "$makers Hersteller" }) 'Ring2' $ui.SheetChips }
        }
        $ui.SheetState.Text = T $('Treiberpakete von Drittherstellern, neueste zuerst')
    }
    Show-SheetList $rows
}

# --- Einzelheiten zu einem Treiber --------------------------------------------

function Open-DetailSheet($Driver) {
    $canExport = $Driver.Inf -like 'oem*.inf'
    $opened = Open-Sheet @{
        Title     = $Driver.Name
        Sub       = (@($Driver.Class, $Driver.Provider | Where-Object { "$_" }) -join ' · ')
        Glyph     = 0xE772
        Link      = $(if ($Driver.Catalog) { 'Im Microsoft-Katalog suchen' } else { '' })
        # Pakete von Drittherstellern lassen sich von hier aus sichern (wie über die drei Punkte der Zeile)
        Primary   = $(if ($canExport) { 'Diesen Treiber sichern' } else { '' })
        Driver    = $Driver
        Show      = {
            param($tab)
            $driver = $script:Sheet.Driver
            $ui.SheetGlyph.Text = Get-ClassGlyph "$($driver.Class)"
            # oben das Wichtigste als Karten, darunter alles Weitere in zwei Abschnitten
            $rows = @()
            $signed = [bool]"$($driver.Signer)"
            if ("$($driver.Version)") {
                $rows += New-SheetRow -Title "$($driver.Version)" -Sub 'Version des installierten Treibers' -Glyph 0xE8D7 -Value (Get-DateLabel "$($driver.Date)") `
                    -State $(if ($signed) { 'signiert' } else { 'ohne Signatur' }) -Tone $(if ($signed) { 'good' } else { 'warn' })
            }
            if ("$($driver.Inf)") { $rows += New-SheetRow -Title "$($driver.Inf)" -Sub 'Treiberpaket im Treiberspeicher von Windows' -Glyph 0xE7B8 -Tone 'accent' }
            $sections = [ordered]@{
                'Gerät'   = [ordered]@{ 'Name' = $driver.Name; 'Geräteklasse' = $driver.Class; 'Hardware-ID' = $driver.HardwareId; 'Geräte mit diesem Treiber' = $driver.Count }
                'Treiber' = [ordered]@{ 'Treiber von' = $driver.Provider; 'Datum' = $(if ((Get-DateLabel "$($driver.Date)") -eq 'ohne Datum') { 'vom Hersteller nicht angegeben' } else { $driver.Date }); 'Signiert von' = $driver.Signer }
            }
            foreach ($section in $sections.Keys) {
                $pairs = $sections[$section]
                $filled = @($pairs.Keys | Where-Object { "$($pairs[$_])" })
                if ($filled.Count -eq 0) { continue }
                $rows += New-SheetRow -Kind 'head' -Title $section.ToUpper()
                foreach ($key in $filled) { $rows += New-SheetRow -Kind 'pair' -Title $key -Value "$($pairs[$key])" }
            }
            Show-SheetList $rows
        }
        OnLink    = { Open-WebLink $script:Sheet.Driver.Catalog }
        OnPrimary = { $driver = $script:Sheet.Driver; Close-Sheet -Quick; Open-ExportDialog $driver }
    }
    [void]$opened
}

# --- Einstellungen ------------------------------------------------------------

$settingRowXaml = ConvertTo-ThemedXaml @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,0,8" Padding="16,13,18,13" CornerRadius="14" Background="#0AFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="Tile" Width="38" Height="38" Margin="0,0,14,0" VerticalAlignment="Top">
            <Border CornerRadius="11" Background="#2422D3EE"/>
            <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
            <TextBlock x:Name="Title" FontSize="14" FontWeight="SemiBold" Foreground="#E8EEFC"/>
            <TextBlock x:Name="Text" FontSize="12" Foreground="#93A3C7" TextWrapping="Wrap" Margin="0,3,0,0"/>
            <WrapPanel x:Name="Below" Margin="-3,9,-3,-3" Visibility="Collapsed"/>
        </StackPanel>
        <StackPanel x:Name="Slot" Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0,0,0"/>
    </Grid>
</Border>
'@

# Legt eine Einstellungszeile an und gibt die Fläche für ihr Bedienelement zurück:
# rechts neben dem Text, mit -Below darunter über die ganze Breite
function Add-SettingRow([string]$Title, [string]$Text, [int]$Glyph, [switch]$Below) {
    $Title = T $Title; $Text = T $Text
    $row = [Windows.Markup.XamlReader]::Parse($settingRowXaml)
    $row.FindName('Title').Text = $Title
    $row.FindName('Text').Text = $Text
    if (-not $Text) { $row.FindName('Text').Visibility = 'Collapsed' }
    if ($Glyph) { $row.FindName('Glyph').Text = Get-Glyph $Glyph } else { $row.FindName('Tile').Visibility = 'Collapsed' }
    $tile = $row.FindName('Tile')
    $tile.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $tile.RenderTransform = New-Object Windows.Media.ScaleTransform
    if ($script:Settings.Animations) {
        # die Zeilen kommen nacheinander: beim Öffnen von unten, beim Reiterwechsel aus der Richtung des neuen Reiters;
        # das Symbol federt dabei nach
        $delay = 50 + 45 * [Math]::Min($ui.SheetPanel.Children.Count, 8)
        $row.Opacity = 0
        $row.RenderTransform = New-Object Windows.Media.TranslateTransform
        Start-Fade $row 1 300 $delay
        if ($script:SheetWay) { $row.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From (20 * $script:SheetWay) -To 0 -Ms 440 -Delay $delay)) }
        else { Start-Slide $row 0 440 $delay 12 }
        Start-Scale $tile 1 650 $delay 0.5 $script:EaseElastic
    }
    [void]$ui.SheetPanel.Children.Add($row)
    if ($Below) { $row.FindName('Below').Visibility = 'Visible'; return $row.FindName('Below') }
    $row.FindName('Slot')
}

# Auswahlknopf in einer Einstellungszeile; der gewählte bekommt Tag "on"
function New-SettingChip([string]$Text, [string]$Id, $Dot) {
    $Text = T $Text
    $chip = New-Object Windows.Controls.Button
    $chip.Style = $window.FindResource('ChipButton')
    $chip.Uid = $Id
    $chip.Height = 32
    $chip.FontSize = 12.5
    $chip.Margin = '3'
    $line = New-Object Windows.Controls.StackPanel
    $line.Orientation = 'Horizontal'
    $line.Margin = '12,0,14,0'
    if ($Dot) {
        $circle = New-Object Windows.Shapes.Ellipse
        $circle.Width = 14; $circle.Height = 14
        $circle.Fill = $Dot
        $circle.Margin = '0,0,8,0'
        [void]$line.Children.Add($circle)
    }
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.VerticalAlignment = 'Center'
    [void]$line.Children.Add($label)
    $chip.Content = $line
    $chip
}

function Update-SettingChips($Panel, [string]$Selected) {
    foreach ($chip in $Panel.Children) {
        $on = $chip.Uid -eq $Selected
        # der neu gewählte Knopf springt kurz auf (nicht beim Aufbau der Seite)
        if ($on -and $chip.Tag -ne 'on' -and $chip.IsLoaded) {
            $chip.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $chip.RenderTransform = New-Object Windows.Media.ScaleTransform
            Start-Scale $chip 1 380 0 0.88 $script:EaseBack
        }
        $chip.Tag = if ($on) { 'on' } else { '' }
    }
}

function Add-SettingSwitch([string]$Key, [string]$Title, [string]$Text, [int]$Glyph) {
    $slot = Add-SettingRow $Title $Text $Glyph
    $toggle = New-Object Windows.Controls.CheckBox
    $toggle.Style = $window.FindResource('Switch')
    $toggle.IsChecked = [bool]$script:Settings[$Key]
    $toggle.Uid = $Key
    $toggle.Tag = $slot.Parent.FindName('Tile')
    $toggle.Add_Click({
            try {
                # das Symbol der Zeile nickt beim Umschalten
                Start-Scale $this.Tag 1 420 0 0.8 $script:EaseBack
                $script:Settings[$this.Uid] = [bool]$this.IsChecked
                Save-Settings
                Update-SettingEffects $this.Uid
            }
            catch { Write-AppError $_ }
        })
    [void]$slot.Children.Add($toggle)
}

# Wendet eine geänderte Einstellung sofort an
function Update-SettingEffects([string]$Key) {
    switch ($Key) {
        'Animations' { if ($script:Page -eq 'Home' -and -not $script:Busy) { Set-OrbIdle } }
        'Opacity' { $window.Opacity = [int]$script:Settings.Opacity / 100.0 }
        { $_ -in 'Firmware', 'ShowCurrent' } { if ($script:LastResult) { Show-Results $script:LastResult } }
        'Helper' {
            try { Update-Helper } catch { Write-AppError $_ }
            # der Zustand unten im Reiter zeigt das Ergebnis
            if ($script:Sheet -and $script:Sheet.Tab -eq 5) { Invoke-Later 1500 { if ($script:Sheet -and $script:Sheet.Tab -eq 5) { Show-SettingsTab } } }
        }
    }
}

function Show-SettingsTab {
    $script:Sheet.HueBar = $null; $script:Sheet.HueKnob = $null; $script:Sheet.ThemeChips = $null
    switch ($script:Sheet.Tab) {
        5 {
            Show-SheetPanel
            Add-SettingSwitch 'Helper' 'Helfer neben der Uhr' 'Startet mit Windows und bleibt klein neben der Uhr: Boost per Rechtsklick, Meldung bei neuen Treibern.' 0xE9F5
            Add-SettingSwitch 'WeeklyScan' 'Einmal pro Woche nach Treibern sehen' 'Der Helfer fragt im Hintergrund nach und meldet sich nur, wenn es neuere gibt.' 0xE895
            Add-SettingSwitch 'AutoBoost' 'Boost automatisch bei Spielen' 'Startet eines der Spiele aus Boost → Einrichten → Spiele, schaltet der Helfer den Boost ein und danach wieder aus. Programme schließt er dabei nicht.' 0xE7FC
            Add-SettingSwitch 'RecordGames' 'Spiele aufzeichnen' 'Läuft ein Boost-Spiel oder eines, das unter „Deine Spiele“ zum Aufzeichnen gewählt ist, schreibt der Helfer alle 5 Sekunden Temperaturen, Last und Takt mit. Ansehen unter Hardware → Sensoren → Spielsitzungen.' 0xE9D9
            [void](Add-SettingRow 'Zustand' (Get-HelperStatus) 0xE946)
        }
        0 {
            Show-SheetPanel
            # Schnellzugriff: die Einträge des früheren Menüs in der Seitenleiste
            $slot = Add-SettingRow 'Schnellzugriff' 'Treiberverlauf, Zielordner, Kurzanleitung und Infos zu PulsRig' 0xE8A9
            foreach ($entry in @(@{ Id = 'history'; Text = 'Treiberverlauf' }, @{ Id = 'folder'; Text = 'Zielordner öffnen' }, @{ Id = 'help'; Text = 'Kurzanleitung' }, @{ Id = 'about'; Text = 'Über PulsRig' })) {
                $chip = New-SettingChip $entry.Text $entry.Id
                $chip.Add_Click({
                        try {
                            switch ($this.Uid) {
                                'history' { Close-Sheet -Quick; Open-HistorySheet }
                                'folder' { Start-Process explorer.exe "`"$(Get-TargetDir)`"" }
                                'help' { Close-Sheet -Quick; Open-HelpSheet 0 }
                                'about' { Close-Sheet -Quick; Open-HelpSheet 1 }
                            }
                        }
                        catch { Write-AppError $_ }
                    })
                [void]$slot.Children.Add($chip)
            }
            # Bewegung in Stufen: "Aus" ist der frühere Schalter Animationen, die anderen ändern das Tempo
            $slot = Add-SettingRow 'Bewegung' 'Ring, Puls und Übergänge. Aus spart Rechenzeit auf schwächeren PCs.' 0xE768
            foreach ($level in 'Aus', 'Ruhig', 'Normal', 'Lebendig') {
                $chip = New-SettingChip $level $level
                $chip.Add_Click({
                        try {
                            if ($this.Uid -eq 'Aus') { $script:Settings.Animations = $false }
                            else { $script:Settings.Animations = $true; $script:Settings.Motion = $this.Uid }
                            Update-Motion
                            Save-Settings
                            Update-SettingEffects 'Animations'
                            Update-SettingChips $this.Parent $this.Uid
                        }
                        catch { Write-AppError $_ }
                    })
                [void]$slot.Children.Add($chip)
            }
            Update-SettingChips $slot $(if ($script:Settings.Animations) { "$($script:Settings.Motion)" } else { 'Aus' })
            Add-SettingSwitch 'RememberPosition' 'Fensterposition merken' 'Das Fenster öffnet sich beim nächsten Start dort, wo es zuletzt stand.' 0xE7F4
            Add-SettingSwitch 'UpdateCheck' 'Nach neuerer Fassung von PulsRig sehen' 'Fragt beim Start einmal bei GitHub nach. Geladen und installiert wird nichts von allein.' 0xE895
            $slot = Add-SettingRow 'Sprache' 'Deutsch oder Englisch. Ein Wechsel startet das Fenster kurz neu.' 0xE774
            foreach ($entry in @(@{ Id = 'de'; Text = 'Deutsch' }, @{ Id = 'en'; Text = 'English' })) {
                $chip = New-SettingChip $entry.Text $entry.Id
                $chip.Add_Click({ try { Set-Language $this.Uid } catch { Write-AppError $_ } })
                [void]$slot.Children.Add($chip)
            }
            Update-SettingChips $slot $script:Language
            $slot = Add-SettingRow 'Deckkraft des Fensters' 'Unter 100 % scheint durch, was hinter dem Fenster liegt.' 0xE706
            foreach ($percent in 100, 95, 90, 85) {
                $chip = New-SettingChip "$percent %" "$percent"
                $chip.Add_Click({
                        try {
                            $script:Settings.Opacity = [int]$this.Uid
                            Save-Settings
                            Update-SettingEffects 'Opacity'
                            Update-SettingChips $this.Parent $this.Uid
                        }
                        catch { Write-AppError $_ }
                    })
                [void]$slot.Children.Add($chip)
            }
            Update-SettingChips $slot "$([int]$script:Settings.Opacity)"
        }
        1 {
            # Farbdesign und Ring-Animation: dieselbe Auswahl wie unten im Seitenmenü
            Show-SheetPanel
            # Skin: das komplette Aussehen. Der Wechsel speichert und startet das Fenster neu.
            $panel = Add-SettingRow 'Skin' 'Komplettes Aussehen: Formen, Schrift, Karten und Bewegungen. Ein Wechsel startet das Fenster kurz neu.' 0xE771 -Below
            foreach ($name in $script:Skins.Keys) {
                $entry = $script:Skins[$name]
                $dot = if ($entry.ThemeDef) { New-ThemeGradient $entry.ThemeDef.A } else { New-ThemeGradient $script:Themes['Mitternacht'].A }
                $chip = New-SettingChip $entry.Text $name $dot
                $chip.Add_Click({ try { Set-Skin $this.Uid; if ($script:Sheet) { Update-SettingChips $this.Parent $script:Settings.Skin } } catch { Write-AppError $_ } })
                [void]$panel.Children.Add($chip)
            }
            Update-SettingChips $panel "$($script:Settings.Skin)"
            $panel = Add-SettingRow 'Farbdesign' 'Färbt das ganze Programm um, der Ring um SCAN bekommt die Gegenfarbe. Die Leiste stellt stufenlos einen eigenen Farbton ein.' 0xE790 -Below
            foreach ($name in (Get-ThemeNames)) {
                $chip = New-SettingChip $name $name (New-ThemeGradient $script:Themes[$name].A)
                $chip.Add_Click({
                        try {
                            Set-Theme $this.Uid
                            Save-Settings
                            Update-SettingChips $this.Parent $this.Uid
                        }
                        catch { Write-AppError $_ }
                    })
                [void]$panel.Children.Add($chip)
            }
            Update-SettingChips $panel $script:Theme.Name
            $themePanel = $panel
            $panel = Add-SettingRow 'Ring-Animation um den SCAN-Knopf' '' 0xE72C -Below
            foreach ($name in (Get-RingNames)) {
                # der Stil des Skins heißt hier kurz "Skin": mit seinem vollen Namen bräuchte die Zeile eine zweite Reihe
                $chip = New-SettingChip $(if ($name -eq "$($script:Skin.Ring)") { 'Skin' } else { $name }) $name
                $chip.Add_Click({
                        try {
                            Set-RingStyle $this.Uid
                            Update-ThemeControls
                            Save-Settings
                            Update-SettingChips $this.Parent $this.Uid
                        }
                        catch { Write-AppError $_ }
                    })
                [void]$panel.Children.Add($chip)
            }
            Update-SettingChips $panel "$($script:Settings.Ring)"
            $script:Sheet.ThemeChips = $themePanel
            # Farbleiste wie im Seitenmenü: Klicken oder Ziehen stellt einen eigenen Farbton ein
            # sie steht unter den Farbdesigns in derselben Zeile, damit der Reiter ohne Scrollen auskommt
            $panel = $themePanel
            $bar = New-Object Windows.Controls.Grid
            $bar.Width = 520; $bar.Height = 22
            $bar.Margin = '3,8,3,3'
            $bar.Background = [Windows.Media.Brushes]::Transparent
            $bar.Cursor = 'Hand'
            $rainbow = New-Object Windows.Media.LinearGradientBrush
            $rainbow.StartPoint = New-Object Windows.Point 0, 0
            $rainbow.EndPoint = New-Object Windows.Point 1, 0
            $stops = '#C0504A', '#C0A84A', '#63C04A', '#4AC0B4', '#4A6DC0', '#9A4AC0', '#C04A6A'
            for ($i = 0; $i -lt $stops.Count; $i++) {
                $rainbow.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($stops[$i])), ($i / ($stops.Count - 1))))
            }
            $track = New-Object Windows.Controls.Border
            $track.Height = 8
            $track.CornerRadius = (Get-SkinRadius 4)
            $track.VerticalAlignment = 'Center'
            $track.Background = $rainbow
            $knob = New-Object Windows.Shapes.Ellipse
            $knob.Width = 16; $knob.Height = 16
            $knob.Fill = [Windows.Media.Brushes]::White
            $knob.Stroke = New-Brush '#0A0F1E'
            $knob.StrokeThickness = 2
            $knob.HorizontalAlignment = 'Left'
            $knob.Margin = '-8,0,0,0'
            $knob.IsHitTestVisible = $false
            $knob.RenderTransform = New-Object Windows.Media.TranslateTransform ($bar.Width * ((($script:Theme.Hue % 360.0) + 360.0) % 360.0) / 360.0), 0
            [void]$bar.Children.Add($track)
            [void]$bar.Children.Add($knob)
            $bar.Add_MouseLeftButtonDown({
                    try {
                        if ($script:Settings.Animations) { Start-ThemeFade }
                        [void]$this.CaptureMouse()
                        Set-HueFromMouse $_ $this
                    }
                    catch { Write-AppError $_ }
                })
            $bar.Add_MouseMove({ try { if ($this.IsMouseCaptured) { Set-HueFromMouse $_ $this } } catch { Write-AppError $_ } })
            $bar.Add_MouseLeftButtonUp({
                    try {
                        if ($this.IsMouseCaptured) {
                            $this.ReleaseMouseCapture()
                            Save-Settings
                        }
                    }
                    catch { Write-AppError $_ }
                })
            [void]$panel.Children.Add($bar)
            $script:Sheet.HueBar = $bar
            $script:Sheet.HueKnob = $knob
        }
        2 {
            Show-SheetPanel
            Add-SettingSwitch 'AutoScan' 'Beim Start automatisch scannen' 'Der Scan beginnt, sobald das Fenster offen ist.' 0xE7E8
            Add-SettingSwitch 'Nvidia' 'Hersteller direkt fragen' 'NVIDIA nach dem Grafiktreiber, AMD nach dem Chipsatz-Treiber. Dort erscheinen neue Versionen früher als bei Windows Update.' 0xE950
            Add-SettingSwitch 'Catalog' 'Microsoft Update-Katalog durchsuchen' 'Liefert Hinweise auf neuere Treiber, die Windows Update nicht anbietet. Dieser Teil des Scans dauert am längsten.' 0xE721
            Add-SettingSwitch 'Firmware' 'Firmware-Updates anzeigen' 'Firmware bleibt in der Liste abgewählt, bis du sie ausdrücklich ankreuzt.' 0xE9F5
            Add-SettingSwitch 'ShowCurrent' 'Aktuelle Treiber auflisten' 'Zeigt unter den Ergebnissen auch alle Treiber, zu denen nichts Neueres gefunden wurde.' 0xE8FD
        }
        3 {
            Show-SheetPanel
            Add-SettingSwitch 'RestorePoint' 'Wiederherstellungspunkt vor der Installation' 'Windows kann damit zum Stand vor der Aktualisierung zurückkehren.' 0xE777
            Add-SettingSwitch 'AutoBackup' 'Ersetzte Treiber vorher sichern' 'Die bisherigen Treiberpakete landen im Zielordner und lassen sich über „Treiber wiederherstellen“ zurückspielen.' 0xE74E
            $slot = Add-SettingRow 'Zielordner' "Für Downloads, Sicherungen und Berichte:`n$(Format-ShownPath (Get-TargetDir))" 0xE8B7
            foreach ($entry in @(@{ Text = 'Öffnen'; Id = 'open' }, @{ Text = 'Ändern …'; Id = 'change' })) {
                $button = New-Object Windows.Controls.Button
                $button.Style = $window.FindResource('GhostButton')
                $button.Content = T $($entry.Text)
                $button.Uid = $entry.Id
                $button.Margin = '8,0,0,0'
                $button.Add_Click({ try { Invoke-FolderAction $this.Uid } catch { Write-AppError $_ } })
                [void]$slot.Children.Add($button)
            }
        }
        4 {
            $rows = @($script:Settings.Ignored | ForEach-Object { New-SheetRow -Title $_.Name -Sub 'wird in den Ergebnissen nicht mehr angeboten' -Action 'Wieder anbieten' -Data $_ })
            if ($rows.Count -eq 0) {
                $rows = @(New-SheetRow -Title 'Nichts ignoriert' -Sub 'In den Ergebnissen lässt sich eine Aktualisierung über die drei Punkte ihrer Zeile ignorieren.')
            }
            Show-SheetList $rows
        }
    }
}

function Invoke-FolderAction([string]$Action) {
    if ($Action -eq 'open') {
        Start-Process explorer.exe "`"$(Get-TargetDir)`""
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Ordner für Downloads, Sicherungen und Berichte wählen'
    $picker.SelectedPath = Get-TargetDir
    if ($picker.ShowDialog() -eq 'OK' -and $picker.SelectedPath) {
        $script:Settings.TargetDir = $picker.SelectedPath
        Save-Settings
        Show-SettingsTab
    }
}

function Open-SettingsSheet([int]$Tab = 0) {
    $opened = Open-Sheet @{
        Title    = 'Optionen'
        Sub      = 'Einstellungen, Design und Schnellzugriff · Änderungen gelten sofort'
        Glyph    = 0xE713
        Tabs     = 'Allgemein', 'Design', 'Suche', 'Treiber', 'Ignoriert', 'Hintergrund'
        Link     = 'Standard wiederherstellen'
        Show     = { param($tab) Show-SettingsTab }
        OnLink   = {
            foreach ($key in 'Animations', 'RememberPosition', 'Firmware', 'Nvidia', 'Catalog', 'ShowCurrent', 'RestorePoint', 'AutoBackup') { $script:Settings[$key] = $true }
            $script:Settings.Motion = 'Normal'; Update-Motion
            $script:Settings.AutoScan = $false
            $script:Settings.Opacity = 100
            $script:Settings.TargetDir = ''
            Save-Settings
            foreach ($key in 'Animations', 'Opacity', 'ShowCurrent') { Update-SettingEffects $key }
            Show-SettingsTab
            $ui.SheetState.Text = T $('Auf Standard zurückgesetzt (Design, Boost-Auswahl und Ignoriertes bleiben)')
        }
        OnAction = {
            param($item)
            $script:Settings.Ignored = @($script:Settings.Ignored | Where-Object { $_.Key -ne $item.Data.Key })
            Save-Settings
            Show-SettingsTab
            if ($script:LastResult) { Show-Results $script:LastResult }
        }
    }
    if ($opened -and $Tab -gt 0) { Select-SheetTab $Tab }
}

# --- Kurzanleitung und Über ---------------------------------------------------

function Add-SheetText([string]$Title, [string]$Text, [int]$Glyph) {
    $slot = Add-SettingRow $Title $Text $Glyph
    $slot.Visibility = 'Collapsed'
}

# Stellt die Zeilen der freien Fläche ab der Stelle $From in zwei gleich hohen Spalten nebeneinander
function Set-SheetColumns([int]$From = 0) {
    $rows = @($ui.SheetPanel.Children)
    if ($rows.Count -le $From) { return }
    $ui.SheetPanel.Children.RemoveRange($From, $rows.Count - $From)
    $grid = New-Object Windows.Controls.Primitives.UniformGrid
    $grid.Columns = 2
    $grid.Margin = '0,0,-8,0'
    for ($i = $From; $i -lt $rows.Count; $i++) {
        $rows[$i].Margin = '0,0,8,6'
        $rows[$i].Padding = '16,10,16,10'
        [void]$grid.Children.Add($rows[$i])
    }
    [void]$ui.SheetPanel.Children.Add($grid)
}

# Kopf des Reiters "Über": Logo, Name und Leitspruch
$aboutHeroXaml = ConvertTo-ThemedXaml @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,0,8" Padding="24,20" CornerRadius="16" BorderBrush="#3322D3EE" BorderThickness="1">
    <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#2422D3EE" Offset="0"/>
            <GradientStop Color="#14A855F7" Offset="1"/>
        </LinearGradientBrush>
    </Border.Background>
    <StackPanel Orientation="Horizontal">
        <Viewbox Width="60" Height="60" VerticalAlignment="Center">
            <Grid x:Name="Mark" Width="132" Height="132" RenderTransformOrigin="0.5,0.5">
                <Grid.RenderTransform>
                    <ScaleTransform/>
                </Grid.RenderTransform>
                <!-- der Ring zeichnet sich von oben im Uhrzeigersinn, danach die Pulslinie, zuletzt springt der Punkt auf -->
                <Ellipse x:Name="Ring" Width="120" Height="120" StrokeThickness="7" Stroke="{DynamicResource AccentGrad}" StrokeDashArray="50.8 50.8" StrokeDashCap="Round" RenderTransformOrigin="0.5,0.5">
                    <Ellipse.RenderTransform>
                        <RotateTransform Angle="-90"/>
                    </Ellipse.RenderTransform>
                </Ellipse>
                <Path x:Name="Pulse" Data="M 34,68 L 50,68 L 58,52 L 68,88 L 78,40 L 86,68 L 96,68" Stroke="White" StrokeThickness="7" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" StrokeDashArray="24 24"/>
                <Path x:Name="Dot" Data="M 101,68 A 5,5 0 1 1 111,68 A 5,5 0 1 1 101,68 Z" Fill="#22D3EE">
                    <Path.RenderTransform>
                        <ScaleTransform CenterX="106" CenterY="68"/>
                    </Path.RenderTransform>
                </Path>
            </Grid>
        </Viewbox>
        <StackPanel Margin="20,0,0,0" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="WordA" Text="Puls" FontSize="28" FontWeight="Light" Foreground="#E8EEFC"/>
                <TextBlock x:Name="WordB" Text="Rig" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource AccentGrad}"/>
                <Border x:Name="VersionPill" CornerRadius="8" Padding="9,3" Background="#14FFFFFF" BorderBrush="#1FFFFFFF" BorderThickness="1" VerticalAlignment="Center" Margin="14,4,0,0" RenderTransformOrigin="0.5,0.5">
                    <Border.RenderTransform>
                        <ScaleTransform/>
                    </Border.RenderTransform>
                    <TextBlock x:Name="Version" FontSize="11.5" FontWeight="SemiBold" Foreground="#E8EEFC"/>
                </Border>
            </StackPanel>
            <TextBlock x:Name="Tagline" Text="Treiber. Boost. Werkzeuge." FontSize="13" Foreground="#93A3C7" Margin="1,2,0,0"/>
        </StackPanel>
    </StackPanel>
</Border>
'@

# Der Kopf des Reiters "Über" baut sich auf wie der Vorspann im Kleinen: Ring, Pulslinie, Punkt, ein Herzschlag;
# daneben kommen Name, Versionsschild und Leitspruch
function Start-AboutHero($Hero) {
    if (-not $script:Settings.Animations) { return }
    Start-Reveal $Hero 40 12 320
    $Hero.FindName('Ring').StrokeDashOffset = 50.8
    $Hero.FindName('Ring').BeginAnimation($P.Dash, (New-DoubleAnim -From 50.8 -To 0 -Ms 750 -Delay 140 -Ease $script:EaseInOut))
    $pulse = $Hero.FindName('Pulse')
    $pulse.Opacity = 0
    Start-Fade $pulse 1 100 420
    $pulse.BeginAnimation($P.Dash, (New-DoubleAnim -From 24 -To 0 -Ms 520 -Delay 420 -Ease $script:EaseInOut))
    $dot = $Hero.FindName('Dot')
    $dot.Opacity = 0
    Start-Fade $dot 1 140 880
    Start-Scale $dot 1 380 880 0.1 $script:EaseBack
    # ein Herzschlag, sobald das Zeichen steht
    $kick = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $kick.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700))
    $kick.BeginTime = [TimeSpan]::FromMilliseconds(980)
    foreach ($frame in @(0.0, 1.0), @(0.16, 1.12), @(0.36, 1.0), @(0.5, 1.05), @(0.72, 1.0), @(1.0, 1.0)) {
        [void]$kick.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))))
    }
    $mark = $Hero.FindName('Mark')
    $mark.RenderTransform.BeginAnimation($P.ScaleX, $kick)
    $mark.RenderTransform.BeginAnimation($P.ScaleY, $kick)
    # "Puls" und "Rig" kommen von links und rechts zusammen
    $side = -1
    foreach ($name in 'WordA', 'WordB') {
        $word = $Hero.FindName($name)
        $word.RenderTransform = New-Object Windows.Media.TranslateTransform
        $word.Opacity = 0
        Start-Fade $word 1 320 260
        $word.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From (16 * $side) -To 0 -Ms 520 -Delay 260))
        $side = 1
    }
    Start-Reveal $Hero.FindName('Tagline') 480 6
    $pill = $Hero.FindName('VersionPill')
    $pill.Opacity = 0
    Start-Fade $pill 1 240 640
    Start-Scale $pill 1 440 640 0.7 $script:EaseBack
}

# --- Neue Fassung laden und installieren ----------------------------------------
# Ein Klick auf den Hinweis oben rechts öffnet dieses Fenster. Geladen wird nur auf Knopfdruck, und nur die
# Setup-Datei aus den Releases des eigenen Projekts, die version.json nennt. Gestartet wird sie nur, wenn Größe und
# Prüfsumme (SHA-256) zu den Angaben dort passen. Läuft PulsRig mit Adminrechten, landet die Datei im Programmordner
# unter "Programme": dort kann sie zwischen Prüfung und Start niemand ohne Adminrechte austauschen.

$script:UpdateJob = $null
$script:UpdateResult = ''

function Get-UpdateFolder {
    if ($script:IsAdmin -and $script:Installed) { Join-Path $script:Root 'Update' } else { Join-Path ([IO.Path]::GetTempPath()) 'PulsRig-Update' }
}

# räumt die Setup-Datei eines früheren Updates weg (beim Start; die gerade laufende lässt sich nicht löschen und bleibt bis zum nächsten Mal)
function Clear-UpdateFolder {
    foreach ($folder in (Join-Path $script:Root 'Update'), (Join-Path ([IO.Path]::GetTempPath()) 'PulsRig-Update')) {
        try { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force -Confirm:$false -ErrorAction Stop } } catch { }
    }
}

function Stop-UpdateDownload {
    $job = $script:UpdateJob
    if (-not $job) { return }
    $script:UpdateJob = $null
    try { $job.Timer.Stop(); $job.Client.CancelAsync(); $job.Client.Dispose() } catch { }
}

function Open-UpdateSheet {
    $note = $script:NewVersion
    if (-not $note) { return }
    $page = "https://github.com/$($script:UpdateRepo)/releases/latest"
    # ohne Angaben zur Setup-Datei (ältere version.json) bleibt nur die Webseite
    if (-not $note.Setup) { Open-WebLink $page; return }
    $opened = Open-Sheet @{
        Title     = 'Neue Fassung'
        Sub       = "PulsRig $($note.Version), gebaut am $("$($note.Built)".Substring(0, 10)) um $("$($note.Built)".Substring(11, 5)) Uhr"
        Glyph     = 0xE896
        Primary   = 'Laden und installieren'
        Link      = 'Seite im Browser öffnen'
        Show      = {
            param($tab)
            Show-SheetPanel
            Add-SheetText 'Was passiert' ('PulsRig lädt die Setup-Datei ({0:N1} MB) von GitHub, prüft sie und startet die Installation. Das Programm schließt sich dabei und öffnet sich danach wieder.' -f ($script:NewVersion.Bytes / 1MB)) 0xE896
            Add-SheetText 'Was bleibt' 'Einstellungen, Ergebnisse und gesicherte Treiber bleiben erhalten.' 0xE74E
            Add-SheetText 'Prüfung' 'Gestartet wird die Datei nur, wenn Größe und Prüfsumme zu den veröffentlichten Angaben passen.' 0xE72E
            Add-SheetText 'Windows fragt nach' $(if ($script:IsAdmin) { 'PulsRig läuft mit Adminrechten: Die Installation beginnt ohne weitere Rückfrage.' } else { 'Die Installation braucht Adminrechte. Windows fragt danach, mit dem Hinweis „Unbekannter Herausgeber“.' }) 0xE83D
            Set-SheetStateText $(if ($script:UpdateResult) { $script:UpdateResult } else { 'Noch nichts geladen' })
        }
        OnPrimary = { Start-UpdateDownload }
        OnLink    = { Open-WebLink "https://github.com/$($script:UpdateRepo)/releases/latest" }
        OnClose   = { Stop-UpdateDownload }
    }
    if (-not $opened) { return }
}

function Start-UpdateDownload {
    $note = $script:NewVersion
    if ($script:UpdateJob -or -not $note -or -not $note.Setup) { return }
    try {
        $folder = Get-UpdateFolder
        if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force -Confirm:$false }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $file = Join-Path $folder 'PulsRig-Setup.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.WebClient
        $client.Headers['User-Agent'] = 'PulsRig'
        # das Laden läuft nebenher; ein Zeitgeber sieht nach, wie weit es ist - das Fenster wartet nie darauf
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(600)
        $timer.Add_Tick({ try { Update-UpdateDownload } catch { Write-AppError $_ } })
        $script:UpdateJob = @{ Client = $client; File = $file; Note = $note; Since = Get-Date; Timer = $timer; Task = $client.DownloadFileTaskAsync($note.Setup, $file) }
        $ui.BtnSheetPrimary.IsEnabled = $false
        Set-SheetStateText 'Lade die Setup-Datei …'
        $timer.Start()
    }
    catch {
        $script:UpdateJob = $null
        Set-SheetStateText "Das Laden ließ sich nicht beginnen: $(@("$($_.Exception.Message)" -split "`r?`n")[0])"
    }
}

function Update-UpdateDownload {
    $job = $script:UpdateJob
    if (-not $job) { return }
    if (-not $job.Task.IsCompleted) {
        if (((Get-Date) - $job.Since).TotalSeconds -gt 300) { $job.Client.CancelAsync() }
        else {
            $have = 0.0
            try { $have = [double](Get-Item -LiteralPath $job.File -ErrorAction Stop).Length } catch { }
            Set-SheetStateText ('Lade die Setup-Datei: {0:N1} von {1:N1} MB' -f ($have / 1MB), ($job.Note.Bytes / 1MB))
        }
        return
    }
    $job.Timer.Stop()
    $script:UpdateJob = $null
    $ui.BtnSheetPrimary.IsEnabled = $true
    $done = $job.Task.Status -eq 'RanToCompletion'
    if (-not $done) { [void]$job.Task.Exception }
    try { $job.Client.Dispose() } catch { }
    if (-not $done) {
        $script:UpdateResult = 'Das Laden hat nicht geklappt. Später noch einmal versuchen oder die Seite im Browser öffnen.'
        Set-SheetStateText $script:UpdateResult
        return
    }
    $size = (Get-Item -LiteralPath $job.File).Length
    $hash = (Get-FileHash -LiteralPath $job.File -Algorithm SHA256).Hash
    if ($size -ne $job.Note.Bytes -or $hash -ne $job.Note.Sha256) {
        try { Remove-Item -LiteralPath $job.File -Force -Confirm:$false } catch { }
        $script:UpdateResult = 'Die geladene Datei passt nicht zu den veröffentlichten Angaben. Sie wurde gelöscht und nicht gestartet.'
        Set-SheetStateText $script:UpdateResult
        return
    }
    # im Probelauf wird nichts installiert
    if ($Snapshot) { $script:UpdateResult = 'Geladen und geprüft – im Probelauf wird nicht installiert'; Set-SheetStateText $script:UpdateResult; return }
    try { Start-Process -FilePath $job.File -ArgumentList '/SILENT', '/PULSRIGUPDATE=1' -ErrorAction Stop }
    catch {
        $script:UpdateResult = 'Die Installation wurde nicht gestartet – die Abfrage von Windows wurde abgelehnt oder die Datei ließ sich nicht öffnen.'
        Set-SheetStateText $script:UpdateResult
        return
    }
    Set-SheetStateText 'Geprüft. Die Installation läuft, PulsRig schließt sich …'
    # das Kennzeichen "PulsRig läuft" sofort freigeben: sonst bittet das Setup darum, das Programm zu schließen
    try { if ($script:RunningMark) { $script:RunningMark.Dispose(); $script:RunningMark = $null } } catch { }
    Invoke-Later 300 { $window.Close() }
}

Clear-UpdateFolder

function Open-HelpSheet([int]$Tab = 0) {
    $opened = Open-Sheet @{
        Title = 'Hilfe'
        Sub   = 'PulsRig in Kürze'
        Glyph = 0xE897
        Tabs  = 'Kurzanleitung', 'Über'
        Show  = {
            param($tab)
            Show-SheetPanel
            if ($script:Sheet.Tab -eq 0) {
                # kurze Texte in zwei Spalten: alles passt ohne Scrollen ins Fenster
                Add-SheetText 'Scan' 'Der große Knopf fragt Windows Update, NVIDIA, AMD und den Microsoft-Katalog nach neueren Treibern. Die Karten darunter führen zu den Ergebnissen.' 0xE721
                Add-SheetText 'Ergebnisse' 'Angekreuzte Treiber installiert der Knopf oben rechts – vorher entsteht ein Wiederherstellungspunkt. Fehlt einem Gerät der Treiber, hilft „Beheben“.' 0xE896
                Add-SheetText 'Boost' 'Schafft vor dem Spielen Platz. Unter „Einrichten“ wählst du Programme und Dienste aus. Ein zweiter Klick stellt alles zurück.' 0xEC4A
                Add-SheetText 'Werkzeuge' 'Jedes Werkzeug prüft zuerst nur und fragt nach, bevor es etwas ändert. Ohne Adminrechte laufen die meisten als Probelauf.' 0xE90F
                Add-SheetText 'Hardware' 'Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher und Prüfbericht. Das Diagnose-Paket sammelt Angaben für die Fehlersuche in einer Datei.' 0xE950
                Add-SheetText 'Menü und Design' 'Im Menü: Treiberverlauf, Zielordner und diese Hilfe. Skins, Farbdesigns, ein eigener Farbton und Ring-Animationen stehen in den Einstellungen unter „Design“.' 0xE790
                Set-SheetColumns 0
            }
            else {
                $hero = [Windows.Markup.XamlReader]::Parse($aboutHeroXaml)
                $hero.FindName('Version').Text = T $("Version $script:Version")
                [void]$ui.SheetPanel.Children.Add($hero)
                Start-AboutHero $hero
                Add-SheetText 'Was es tut' 'Sucht neuere Treiber, beschleunigt den PC fürs Spielen und bringt Werkzeuge für Treiber, Geräte und Spiele mit. Testversion: Fehler bitte mit dem Diagnose-Paket melden.' 0xE946
                Add-SheetText 'Quellen' 'Windows Update, NVIDIA, die Chipsatz-Seite von AMD und der Microsoft Update-Katalog. Von AMD und aus dem Katalog kommen Hinweise. Fehlt einem Gerät der Treiber, lädt PulsRig ihn auf Nachfrage aus dem Katalog.' 0xE774
                Add-SheetText 'Rechte' $(if ($script:IsAdmin) { 'Läuft mit Adminrechten: Installieren und Reparieren ist möglich.' } else { 'Läuft ohne Adminrechte: Scannen geht, Installieren und Reparieren nicht.' }) 0xE83D
                Add-SheetText 'Ordner' "Programm: $(Format-ShownPath $script:Root)`nZielordner: $(Format-ShownPath (Get-TargetDir))" 0xE8B7
                Set-SheetColumns 1
            }
        }
    }
    if ($opened -and $Tab -gt 0) { Select-SheetTab $Tab }
}

# --- Design wechseln ----------------------------------------------------------

$script:FadeToken = 0

# Legt ein Bild des bisherigen Aussehens über das Fenster und blendet es aus - so wechselt alles gleichzeitig und weich
function Start-ThemeFade {
    $shell = $ui.Shell
    $width = [int]$shell.ActualWidth; $height = [int]$shell.ActualHeight
    if ($width -le 0 -or $height -le 0) { return }
    $visual = New-Object Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $context.DrawRectangle((New-Object Windows.Media.VisualBrush $shell), $null, (New-Object Windows.Rect 0, 0, $width, $height))
    $context.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap $width, $height, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $ui.ThemeFade.Source = $bitmap
    $ui.ThemeFade.Visibility = 'Visible'
    Start-Fade $ui.ThemeFade 0 420 0 1
    $script:FadeToken++
    Invoke-Later 460 {
        param($token)
        if ($token -eq $script:FadeToken) {
            $ui.ThemeFade.Visibility = 'Collapsed'
            $ui.ThemeFade.Source = $null
            # das Standbild belegt Speicher außerhalb der Speicherverwaltung von .NET, bis sie einmal aufräumt -
            # von selbst täte sie das lange nicht, und jeder Farbwechsel ließe rund 7 MB liegen
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        }
    } $script:FadeToken
}

function Set-Theme([string]$Name, [double]$Hue = 224.0, [switch]$Instant) {
    $script:Theme = New-ThemeState $Name $Hue
    if (-not $Instant -and $script:Settings.Animations) { Start-ThemeFade }
    Update-ThemeDictionary
    $script:Settings.Theme = $script:Theme.Name
    $script:Settings.ThemeHue = [double]$script:Theme.Hue
    # Striche und Ring holen sich die neuen Ringfarben
    Update-TickBrushes
    if ($script:SplashDone -and $ui.RingLayer.Children.Count -gt 0) { Show-RingStyle -Still:(-not $script:Settings.Animations -or -not $script:RingRunning) }
    Update-ThemeControls
}

# Zieht die Auswahl im Reiter "Design" der Einstellungen nach, falls er gerade offen ist.
# (Früher stand dieselbe Auswahl noch einmal im Seitenmenü; seit 0.6 gibt es sie nur noch in den Einstellungen.)
function Update-ThemeControls {
    if ($script:Sheet -and $script:Sheet.HueKnob) {
        $script:Sheet.HueKnob.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To ($script:Sheet.HueBar.Width * ((($script:Theme.Hue % 360.0) + 360.0) % 360.0) / 360.0) -Ms 260))
        Update-SettingChips $script:Sheet.ThemeChips $script:Theme.Name
    }
}

# Farbton-Leiste: Klicken oder Ziehen stellt einen eigenen Farbton ein
function Set-HueFromMouse($EventArgs, $Bar) {
    $width = $Bar.ActualWidth
    if ($width -le 0) { return }
    $x = $EventArgs.GetPosition($Bar).X
    if ($x -lt 0) { $x = 0.0 }
    if ($x -gt $width) { $x = $width }
    $hue = [Math]::Round($x / $width * 359.0)
    if ($script:Theme.Name -eq 'Eigene' -and [Math]::Abs($hue - $script:Theme.Hue) -lt 3) { return }
    Set-Theme 'Eigene' $hue -Instant
}

# --- Seitenmenü ---------------------------------------------------------------
# Die Einstellungen stehen schon in der Seitenleiste und fehlen deshalb hier. "Design ändern" führt in ihren Reiter.
# Unten steht, welche Fassung läuft: danach fragt man als Erstes, wenn jemand einen Fehler meldet.
$ui.DrawerFoot.Text = T $("PulsRig $script:Version`nBau: $(("$script:Build" -split ' · ')[0])")

$script:DrawerOpen = $false
# kräftig abbremsen: das Menü schießt heraus und kommt weich zum Stehen
$script:EaseDrawer = New-Object Windows.Media.Animation.QuinticEase
$script:EaseDrawer.EasingMode = 'EaseOut'
$script:DrawerEntries = @(
    @{ Id = 'history'; Glyph = 0xE81C; Text = 'Treiberverlauf' },
    @{ Id = 'folder'; Glyph = 0xE8B7; Text = 'Zielordner öffnen' },
    @{ Id = 'design'; Glyph = 0xE790; Text = 'Design ändern' },
    @{ Id = 'help'; Glyph = 0xE897; Text = 'Kurzanleitung' },
    @{ Id = 'about'; Glyph = 0xE946; Text = 'Über PulsRig' }
)
foreach ($entry in $script:DrawerEntries) {
    $item = New-Object Windows.Controls.Button
    $item.Style = $window.FindResource('DrawerButton')
    $item.Tag = Get-Glyph $entry.Glyph
    $item.Content = T $entry.Text
    $item.Uid = $entry.Id
    $item.Margin = '0,0,0,2'
    $item.Opacity = 0
    $item.RenderTransform = New-Object Windows.Media.TranslateTransform
    $item.Add_Click({
            try {
                switch ($this.Uid) {
                    'settings' { Open-SettingsSheet }
                    'history' { Open-HistorySheet }
                    'folder' { Close-Drawer; Start-Process explorer.exe "`"$(Get-TargetDir)`"" }
                    'design' { Open-SettingsSheet 1 }
                    'help' { Open-HelpSheet 0 }
                    'about' { Open-HelpSheet 1 }
                }
            }
            catch { Write-AppError $_ }
        })
    [void]$ui.DrawerItems.Children.Add($item)
}

# Lässt ein Element nach einer Wartezeit aufspringen; bis dahin bleibt es unsichtbar
function Start-Pop($Element, [int]$Delay, [double]$From = 0.8) {
    $Element.BeginAnimation($P.Opacity, $null)
    if (-not $script:Settings.Animations) { $Element.Opacity = 1; return }
    $Element.Opacity = 0
    Start-Fade $Element 1 240 $Delay
    Start-Scale $Element 1 420 $Delay $From $script:EaseBack
}

function Open-Drawer {
    if ($script:DrawerOpen -or $script:Dialog -or $script:Sheet) { return }
    $ui.Drawer.Visibility = 'Visible'
    Start-Fade $ui.DrawerDim 1 260
    $ui.DrawerCard.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 0 -Ms 420 -Ease $script:EaseDrawer))
    # der Inhalt baut sich von oben nach unten auf: Kopf, Einträge, dann die Zeile mit der Fassung
    Start-Reveal $ui.DrawerHead 60 8
    Start-Reveal $ui.DrawerLabel 110 8
    $index = 0
    foreach ($item in $ui.DrawerItems.Children) {
        $delay = 140 + 50 * $index
        $item.BeginAnimation($P.Opacity, $null)
        $item.Opacity = if ($script:Settings.Animations) { 0 } else { 1 }
        Start-Fade $item 1 260 $delay
        $item.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -28 -To 0 -Ms 400 -Delay $delay))
        $index++
    }
    Start-Reveal $ui.DrawerFoot (160 + 50 * $index) 8
    $script:DrawerOpen = $true
}

function Close-Drawer {
    if (-not $script:DrawerOpen) { return }
    $script:DrawerOpen = $false
    Start-Fade $ui.DrawerDim 0 220
    $ui.DrawerCard.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To -304 -Ms 240 -Ease $script:EaseCubicIn))
    Invoke-Later 280 { if (-not $script:DrawerOpen) { $ui.Drawer.Visibility = 'Collapsed' } }
}

$ui.NavMenu.Add_MouseEnter({ Start-Fade $ui.NavMenuHover 0.06 160 })
$ui.NavMenu.Add_MouseLeave({ Start-Fade $ui.NavMenuHover 0 240 })
$ui.NavMenu.Add_MouseLeftButtonUp({ try { Open-Drawer } catch { Write-AppError $_ } })
$ui.BtnDrawerClose.Add_Click({ try { Close-Drawer } catch { Write-AppError $_ } })
$ui.DrawerDim.Add_MouseLeftButtonDown({ try { Close-Drawer } catch { Write-AppError $_ } })

# Esc schließt, was gerade obenauf liegt
$window.Add_PreviewKeyDown({
        try {
            if ($_.Key -ne 'Escape') { return }
            if ($ui.RowMenu.IsOpen) { $ui.RowMenu.IsOpen = $false }
            elseif ($script:Dialog) { if (-not $script:Busy) { Close-Dialog } }
            elseif ($script:Sheet) { Close-Sheet }
            elseif ($script:DrawerOpen) { Close-Drawer }
            else { return }
            $_.Handled = $true
        }
        catch { Write-AppError $_ }
    })
