# PulsRig - Controller- und Maus-Test. Wird von PulsRig.ps1 nach PulsRig-Verschleiss.ps1 eingebunden.
#
# Reiter Controller: Tasten leuchten beim Drücken auf (und bleiben als "getestet" markiert), beide Sticks als Punkt
# im Kreis, die Trigger als Balken; "Drift messen" misst 3 Sekunden, wie weit die losgelassenen Sticks von der Mitte
# abweichen; "Vibrieren" lässt beide Motoren eine Sekunde laufen.
# Reiter Maus: Abfragerate beim schnellen Kreisen, Klicks je Taste und ungewollte Doppelklicks (die Taste löst kurz
# nach dem Loslassen von selbst wieder aus - ein verschlissener Schalter).
# Die Messung selbst steckt in PulsRig-Eingabe.cs.

$script:InputTest = $null
$script:InputDemo = $null          # nur im Probelauf: gestellte Werte statt Controller und Maus

# Tasten des Controllers: Bit in XInput und Beschriftung
$script:PadButtons = @(
    @(0x1000, 'A'), @(0x2000, 'B'), @(0x4000, 'X'), @(0x8000, 'Y'), @(0x0100, 'LB'), @(0x0200, 'RB'),
    @(0x0020, 'Back'), @(0x0010, 'Start'), @(0x0040, 'LS'), @(0x0080, 'RS'),
    @(0x0001, '↑'), @(0x0002, '↓'), @(0x0004, '←'), @(0x0008, '→')
)
$script:MouseButtons = 'Links', 'Rechts', 'Mitte', 'Seite 1', 'Seite 2'

function Open-InputSheet([int]$Tab = 0) {
    if (-not ('PulsRigPad' -as [type])) { Add-Type -TypeDefinition (Get-AppText 'PulsRig-Eingabe.cs') -ReferencedAssemblies System.Windows.Forms }
    $opened = Open-Sheet @{
        Title   = 'Controller und Maus'
        Sub     = 'Tasten, Stick-Drift, Abfragerate und ungewollte Doppelklicks prüfen'
        Glyph   = 0xE7FC
        Tabs    = 'Controller', 'Maus'
        Show    = { param($tab) if ([int]$script:Sheet.Tab -eq 1) { Show-MouseTab } else { Show-PadTab } }
        OnClose = { Stop-InputTest }
    }
    if (-not $opened) { return }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(40)
    $timer.Add_Tick({ try { Update-InputTest } catch { Write-AppError $_ } })
    $script:InputTest.Timer = $timer
    if (-not $script:InputDemo) { try { [void][PulsRigMouse]::Start() } catch { Write-AppError $_ } }
    $timer.Start()
    if ($Tab -gt 0) { Select-SheetTab $Tab }
}

function Stop-InputTest {
    if ($script:InputTest -and $script:InputTest.Timer) { $script:InputTest.Timer.Stop() }
    try { Save-InputResult $script:InputTest } catch { Write-AppError $_ }
    try { [PulsRigPad]::Vibrate([int]$script:InputTest.Pad, $false) } catch { }
    try { [PulsRigMouse]::Stop() } catch { }
    $script:InputTest = $null
}

function New-InputCard {
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = 14; $card.Padding = '16,14,16,14'; $card.Margin = '0,0,0,8'; $card.BorderThickness = 1
    Set-Paint $card 'Background' 'Glass'; Set-Paint $card 'BorderBrush' 'GlassEdge'
    $card
}

function New-InputText([string]$Text, [double]$Size = 12, [string]$Paint = 'TextDim') {
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = T $Text; $block.FontSize = $Size; $block.TextWrapping = 'Wrap'
    Set-Paint $block 'Foreground' $Paint
    $block
}

# Stick: Kreis mit Totzone und Punkt; Ergebnis die Teile, die sich bewegen
function New-StickView([string]$Label) {
    $panel = New-Object Windows.Controls.StackPanel
    $panel.HorizontalAlignment = 'Center'
    $area = New-Object Windows.Controls.Grid
    $area.Width = 116; $area.Height = 116
    $ring = New-Object Windows.Shapes.Ellipse
    $ring.StrokeThickness = 2; Set-Paint $ring 'Stroke' 'TextDim'; $ring.Opacity = 0.5
    $dead = New-Object Windows.Shapes.Ellipse
    $dead.Width = 28; $dead.Height = 28; $dead.StrokeThickness = 1; $dead.StrokeDashArray = [Windows.Media.DoubleCollection]::Parse('2 3')
    Set-Paint $dead 'Stroke' 'TextDim'; $dead.Opacity = 0.6
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 16; $dot.Height = 16; Set-Paint $dot 'Fill' 'Accent'
    $dot.RenderTransform = New-Object Windows.Media.TranslateTransform
    [void]$area.Children.Add($ring); [void]$area.Children.Add($dead); [void]$area.Children.Add($dot)
    [void]$panel.Children.Add($area)
    $text = New-InputText $Label 12 'Text'
    $text.HorizontalAlignment = 'Center'; $text.Margin = '0,8,0,0'; $text.TextAlignment = 'Center'
    [void]$panel.Children.Add($text)
    @{ Panel = $panel; Dot = $dot; Text = $text; Label = $Label }
}

function New-InputChip([string]$Text) {
    $chip = New-Object Windows.Controls.Border
    $chip.CornerRadius = 8; $chip.Padding = '10,5,10,5'; $chip.Margin = '3'; $chip.MinWidth = 40; $chip.BorderThickness = 1
    Set-Paint $chip 'BorderBrush' 'GlassEdge'
    $label = New-InputText $Text 12.5 'Text'
    $label.HorizontalAlignment = 'Center'; $label.TextWrapping = 'NoWrap'
    $chip.Child = $label
    $chip
}

# eine Taste: gedrückt hell, schon einmal gedrückt grün umrandet
function Set-InputChip($Chip, [bool]$Pressed, [bool]$Seen) {
    if ($Pressed) { Set-Paint $Chip 'Background' 'Accent'; $Chip.Child.Foreground = [Windows.Media.Brushes]::Black }
    else { $Chip.Background = $null; Set-Paint $Chip.Child 'Foreground' 'Text' }
    Set-Paint $Chip 'BorderBrush' $(if ($Seen) { 'Good' } else { 'GlassEdge' })
}

function Show-PadTab {
    Show-SheetPanel
    $test = $script:InputTest
    if (-not $test) { $test = @{ Pad = 0; Seen = @{}; Drift = $null; Next = 0 }; $script:InputTest = $test }
    $test.View = 'pad'
    $card = New-InputCard
    $grid = New-Object Windows.Controls.Grid
    foreach ($w in '170', '*', '170') { $column = New-Object Windows.Controls.ColumnDefinition; $column.Width = $(if ($w -eq '*') { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength ([double]$w) }); $grid.ColumnDefinitions.Add($column) }
    $left = New-StickView 'Linker Stick'; $right = New-StickView 'Rechter Stick'
    [Windows.Controls.Grid]::SetColumn($right.Panel, 2)
    [void]$grid.Children.Add($left.Panel); [void]$grid.Children.Add($right.Panel)
    $middle = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($middle, 1)
    $middle.VerticalAlignment = 'Center'
    $buttons = New-Object Windows.Controls.WrapPanel
    $buttons.HorizontalAlignment = 'Center'
    $test.Chips = @{}
    foreach ($button in $script:PadButtons) {
        $chip = New-InputChip $button[1]
        [void]$buttons.Children.Add($chip)
        $test.Chips[[int]$button[0]] = $chip
    }
    [void]$middle.Children.Add($buttons)
    # Trigger als Balken
    $test.Triggers = @()
    foreach ($name in 'LT', 'RT') {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = '20,8,20,0'
        $label = New-InputText $name 12 'Text'; $label.Width = 28
        [void]$row.Children.Add($label)
        $track = New-Object Windows.Controls.Grid
        $track.Height = 8; $track.VerticalAlignment = 'Center'
        $back = New-Object Windows.Controls.Border; $back.CornerRadius = 4; Set-Paint $back 'Background' 'GlassEdge'
        $fill = New-Object Windows.Controls.Border; $fill.CornerRadius = 4; $fill.HorizontalAlignment = 'Left'; $fill.Width = 0; Set-Paint $fill 'Background' 'Accent'
        [void]$track.Children.Add($back); [void]$track.Children.Add($fill)
        [void]$row.Children.Add($track)
        [void]$middle.Children.Add($row)
        $test.Triggers += @{ Fill = $fill; Track = $track }
    }
    [void]$grid.Children.Add($middle)
    $card.Child = $grid
    [void]$ui.SheetPanel.Children.Add($card)
    $test.Left = $left; $test.Right = $right
    $slot = Add-SettingRow 'Suche einen Controller …' '' 0xE7FC
    $test.Row = $slot.Parent.Parent
    foreach ($entry in @(@('Drift messen', 'drift'), @('Vibrieren', 'rumble'))) {
        $chip = New-SettingChip $entry[0] $entry[1]
        $chip.Add_Click({ param($sender) try { Invoke-InputAction $sender.Uid } catch { Write-AppError $_ } })
        [void]$slot.Children.Add($chip)
    }
    Set-SheetStateText 'Xbox-kompatible Controller (XInput). PlayStation-Controller nur über Steam oder DS4Windows.'
}

function Show-MouseTab {
    Show-SheetPanel
    $test = $script:InputTest
    if (-not $test) { $test = @{ Pad = 0; Seen = @{}; Next = 0 }; $script:InputTest = $test }
    $test.View = 'mouse'
    $card = New-InputCard
    $card.Height = 190
    $stack = New-Object Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'; $stack.HorizontalAlignment = 'Center'
    $hint = New-InputText 'Maus jetzt ein paar Sekunden schnell und ohne Pause im Kreis bewegen' 13 'TextDim'
    $hint.HorizontalAlignment = 'Center'
    $rate = New-InputText '–' 40 'Text'
    $rate.FontWeight = 'SemiBold'; $rate.HorizontalAlignment = 'Center'; $rate.Margin = '0,6,0,0'
    $detail = New-InputText 'Abfragerate' 12 'TextDim'
    $detail.HorizontalAlignment = 'Center'
    [void]$stack.Children.Add($hint); [void]$stack.Children.Add($rate); [void]$stack.Children.Add($detail)
    $card.Child = $stack
    [void]$ui.SheetPanel.Children.Add($card)
    $test.Rate = $rate; $test.RateDetail = $detail
    # Tasten mit Zahl der Klicks
    $buttons = New-Object Windows.Controls.WrapPanel
    $buttons.Margin = '0,0,0,8'; $buttons.HorizontalAlignment = 'Center'
    $test.MouseChips = @()
    foreach ($name in $script:MouseButtons) { $chip = New-InputChip $name; $chip.MinWidth = 96; [void]$buttons.Children.Add($chip); $test.MouseChips += $chip }
    $wheel = New-InputChip 'Rad · 0'; $wheel.MinWidth = 96; [void]$buttons.Children.Add($wheel); $test.Wheel = $wheel
    [void]$ui.SheetPanel.Children.Add($buttons)
    $slot = Add-SettingRow 'Doppelklick-Fehler' 'Jede Taste 20- bis 30-mal schnell hintereinander klicken. Löst eine kurz nach dem Loslassen von selbst wieder aus, steht es hier.' 0xE962
    $test.MouseRow = $slot.Parent.Parent
    $chip = New-SettingChip 'Zurücksetzen' 'reset'
    $chip.Add_Click({ param($sender) try { Invoke-InputAction $sender.Uid } catch { Write-AppError $_ } })
    [void]$slot.Children.Add($chip)
    Set-SheetStateText 'Gemessen wird jede einzelne Meldung der Maus, auch außerhalb von PulsRig'
}

function Invoke-InputAction([string]$Do) {
    $test = $script:InputTest
    if (-not $test) { return }
    switch ($Do) {
        'drift' { $test.Drift = @{ Until = (Get-Date).AddSeconds(3); L = 0.0; R = 0.0 }; Set-InputRow 'Sticks nicht berühren …' 'Gemessen wird 3 Sekunden lang, wie weit sie in Ruhe von der Mitte abweichen.' '' }
        'rumble' { try { [PulsRigPad]::Vibrate([int]$test.Pad, $true) } catch { }; Invoke-Later 1000 { try { [PulsRigPad]::Vibrate([int]$script:InputTest.Pad, $false) } catch { } } }
        'reset' { try { [PulsRigMouse]::Reset() } catch { } }
    }
}

function Set-InputRow([string]$Title, [string]$Text, [string]$Tone) {
    $row = $script:InputTest.Row
    if (-not $row) { return }
    $row.FindName('Title').Text = T $Title
    $row.FindName('Text').Text = T $Text
    $row.FindName('Text').Visibility = $(if ($Text) { 'Visible' } else { 'Collapsed' })
    Set-Paint $row.FindName('Glyph') 'Foreground' $(switch ($Tone) { 'good' { 'Good' } 'warn' { 'Warn' } 'bad' { 'Bad' } default { 'Accent' } })
}

# Was im Test herauskam, als Kartenzustand "Input": Abfragerate, Klicks und ungewollte Doppelklicks der Maus,
# Drift je Stick und getestete Tasten des Controllers. Ohne Messung bleibt der alte Stand stehen.
function Save-InputResult($Test) {
    if (-not $Test -or $script:InputDemo) { return }
    $old = $script:CardState.Input
    $state = @{}
    if ($old) { foreach ($key in @($old.Keys)) { $state[$key] = $old[$key] } }
    $changed = $false
    $clicks = 0; $bounces = @()
    try {
        $clicks = [int](([PulsRigMouse]::Clicks | Measure-Object -Sum).Sum)
        for ($b = 0; $b -lt 5; $b++) { if ([PulsRigMouse]::Bounces[$b] -gt 0) { $bounces += '{0} {1}×' -f $script:MouseButtons[$b], [PulsRigMouse]::Bounces[$b] } }
        $bounceMax = [int](([PulsRigMouse]::Bounces | Measure-Object -Maximum).Maximum)
    }
    catch { }
    if ($Test.Hz -gt 0) { $state.Hz = [int]$Test.Hz; $state.HzMin = [bool]$Test.HzMin; $changed = $true }
    if ($clicks -ge 20) { $state.Clicks = $clicks; $state.Bounces = (@($bounces | ForEach-Object { T $_ }) -join ', '); $state.BounceMax = $bounceMax; $changed = $true }
    if ($Test.DriftResult) {
        $state.DriftL = [int]$Test.DriftResult.L; $state.DriftR = [int]$Test.DriftResult.R; $state.DriftTone = "$($Test.DriftResult.Tone)"
        $changed = $true
    }
    # getestete Tasten zählen auch ohne Drift-Messung
    if ($Test.Seen -and @($Test.Seen.Keys).Count -gt 0) { $state.Buttons = "$(@($Test.Seen.Keys).Count) von $($script:PadButtons.Count)"; $changed = $true }
    if (-not $changed) { return }
    # Ton: ungewollte Doppelklicks oder Drift = auffällig
    $tone = 'good'
    # ältere Stände ohne BounceMax gelten wie bisher als auffällig
    if ($state.Bounces -and ($null -eq $state.BounceMax -or [int]$state.BounceMax -ge 2)) { $tone = 'warn' }
    if ($state.DriftTone -in 'warn', 'bad') { $tone = $(if ($state.DriftTone -eq 'bad') { 'bad' } else { 'warn' }) }
    $parts = @()
    if ($state.Hz) { $parts += ('Maus {0}{1:N0} Hz' -f $(if ($state.HzMin) { '≥ ' } else { '' }), $state.Hz) }
    if ($null -ne $state.DriftL) { $parts += ('Drift {0} / {1} %' -f $state.DriftL, $state.DriftR) }
    $state.Text = $(if ($tone -eq 'good') { 'in Ordnung' } else { 'auffällig' })
    $state.Tone = $tone
    $state.Detail = $parts -join ' · '
    Set-CardState 'Input' $state
}

# ein Satz zum gespeicherten Stand - für Diagnose-Paket und Prüfbericht
function Get-InputSummary {
    $state = $script:CardState.Input
    if (-not $state) { return '' }
    $parts = @()
    if ($state.Hz) { $parts += ('Maus mit {0}{1:N0} Hz' -f $(if ($state.HzMin) { 'mindestens ' } else { '' }), [int]$state.Hz) }
    if ($state.Clicks) {
        $parts += $(if (-not $state.Bounces) { "kein ungewollter Doppelklick bei $($state.Clicks) Klicks" }
            elseif ($null -ne $state.BounceMax -and [int]$state.BounceMax -lt 2) { "einmal nachgeprellt: $($state.Bounces) (bei $($state.Clicks) Klicks)" }
            else { "ungewollte Doppelklicks: $($state.Bounces) (bei $($state.Clicks) Klicks)" })
    }
    if ($null -ne $state.DriftL) { $parts += ('Sticks in Ruhe {0} % und {1} % aus der Mitte' -f $state.DriftL, $state.DriftR) }
    if ($state.Buttons) { $parts += "$($state.Buttons) Tasten getestet" }
    $parts += "getestet am $($state.Date)"
    # mit " · " verbunden: so übersetzt T jedes Stück einzeln
    $parts -join ' · '
}

# Auslenkung eines Sticks in Prozent (0 = Mitte, 100 = Rand)
function Get-StickShare([double]$X, [double]$Y) { [Math]::Min(100.0, 100.0 * [Math]::Sqrt($X * $X + $Y * $Y) / 32767.0) }

# Urteil zur Ruhelage: die üblichen Totzonen der Spiele liegen um 20 bis 25 %
function Get-DriftVerdict([double]$Share) {
    if ($Share -lt 8) { @{ Text = 'in Ordnung'; Tone = 'good' } }
    elseif ($Share -lt 20) { @{ Text = 'leichter Drift'; Tone = 'warn' } }
    else { @{ Text = 'Drift'; Tone = 'bad' } }
}

function Update-InputTest {
    $test = $script:InputTest
    if (-not $test -or -not $script:Sheet -or $script:Sheet.Title -ne 'Controller und Maus') { return }
    if ($test.View -eq 'pad') { Update-PadView $test } else { Update-MouseView $test }
}

function Update-PadView($Test) {
    $state = if ($script:InputDemo) { $script:InputDemo.Pad } else { [PulsRigPad]::Read([int]$Test.Pad) }
    if (-not $script:InputDemo -and $state[0] -eq 0) {
        # nicht verbunden: einmal pro Sekunde die vier Plätze absuchen
        if ([Environment]::TickCount -ge $Test.Next) {
            $Test.Next = [Environment]::TickCount + 1000
            for ($i = 0; $i -lt 4; $i++) { if (([PulsRigPad]::Read($i))[0]) { $Test.Pad = $i; break } }
        }
        Set-InputRow 'Kein Controller gefunden' 'Controller per Kabel, Funk oder Bluetooth verbinden. Erkannt werden Xbox-kompatible Controller (XInput).' ''
        return
    }
    $buttons = [int]$state[1]
    foreach ($key in @($Test.Chips.Keys)) {
        $pressed = ($buttons -band $key) -ne 0
        if ($pressed) { $Test.Seen[$key] = $true }
        Set-InputChip $Test.Chips[$key] $pressed ([bool]$Test.Seen[$key])
    }
    for ($t = 0; $t -lt 2; $t++) {
        $track = $Test.Triggers[$t].Track
        if ($track.ActualWidth -gt 0) { $Test.Triggers[$t].Fill.Width = $track.ActualWidth * [double]$state[2 + $t] / 255.0 }
    }
    $sticks = @(@($Test.Left, [double]$state[4], [double]$state[5]), @($Test.Right, [double]$state[6], [double]$state[7]))
    foreach ($stick in $sticks) {
        $view = $stick[0]
        $view.Dot.RenderTransform.X = 50 * $stick[1] / 32767.0
        $view.Dot.RenderTransform.Y = -50 * $stick[2] / 32767.0
        $view.Text.Text = '{0} · {1:N0} %' -f (T $view.Label), (Get-StickShare $stick[1] $stick[2])
    }
    $drift = $Test.Drift
    if ($drift) {
        $drift.L = [Math]::Max($drift.L, (Get-StickShare $state[4] $state[5]))
        $drift.R = [Math]::Max($drift.R, (Get-StickShare $state[6] $state[7]))
        if ((Get-Date) -ge $drift.Until) {
            $Test.Drift = $null
            $left = Get-DriftVerdict $drift.L; $right = Get-DriftVerdict $drift.R
            $worst = @($left, $right | Sort-Object { @{ good = 0; warn = 1; bad = 2 }[$_.Tone] })[-1]
            $text = ('Linker Stick in Ruhe {0:N0} % aus der Mitte ({1}), rechter {2:N0} % ({3}).' -f $drift.L, (T $left.Text), $drift.R, (T $right.Text))
            $text += "`n" + $(switch ($worst.Tone) {
                    'good' { 'Beide kehren sauber in die Mitte zurück.' }
                    'warn' { 'Die meisten Spiele gleichen das mit ihrer Totzone aus. Wird es schlimmer: Stick mit Druckluft reinigen.' }
                    default { 'Der Stick bewegt die Figur von selbst. Reinigen hilft manchmal; sonst muss das Stick-Modul getauscht werden.' }
                })
            $Test.DriftResult = @{ Title = $(if ($worst.Tone -eq 'good') { 'Kein Stick-Drift' } else { 'Stick-Drift gemessen' }); Text = $text; Tone = $worst.Tone
                L = [Math]::Round($drift.L); R = [Math]::Round($drift.R) }
        }
        else { return }
    }
    $count = @($Test.Seen.Keys).Count
    if ($Test.DriftResult) { Set-InputRow $Test.DriftResult.Title ($Test.DriftResult.Text + "`n" + ('{0} von {1} Tasten getestet.' -f $count, $script:PadButtons.Count)) $Test.DriftResult.Tone }
    else { Set-InputRow ('Controller {0} verbunden' -f ($Test.Pad + 1)) ('Jede Taste einmal drücken: getestete werden grün umrandet ({0} von {1}). Für den Drift die Sticks loslassen und „Drift messen“ wählen.' -f $count, $script:PadButtons.Count) 'good' }
}

function Update-MouseView($Test) {
    if ($script:InputDemo) { $mouse = $script:InputDemo.Mouse }
    else {
        $mouse = @{ Rate = [PulsRigMouse]::Rate(); Limited = [PulsRigMouse]::SpeedLimited; Samples = [PulsRigMouse]::Samples; Clicks = [PulsRigMouse]::Clicks; Bounces = [PulsRigMouse]::Bounces
            Down = [PulsRigMouse]::Down; Wheel = [PulsRigMouse]::Wheel; Devices = [PulsRigMouse]::Devices }
    }
    if ($mouse.Rate -gt 0) {
        if ($mouse.Limited) {
            # die Bewegung war zu langsam für die Rate der Maus: Mindestwert, auf 100 abgerundet
            $value = [Math]::Max(100, [Math]::Floor($mouse.Rate / 100) * 100)
            $Test.Rate.Text = T ('mindestens {0:N0} Hz' -f $value)
            $Test.RateDetail.Text = T 'Die Maus meldet nur, wenn sie sich bewegt: Für eine höhere Rate schneller kreisen oder die DPI erhöhen.'
        }
        else {
            # auf die übliche Stufe runden, wenn sie nah genug liegt
            $standard = @(125, 250, 500, 1000, 2000, 4000, 8000 | Sort-Object { [Math]::Abs($_ - $mouse.Rate) })[0]
            $value = if ([Math]::Abs($standard - $mouse.Rate) / $standard -lt 0.15) { $standard } else { [Math]::Round($mouse.Rate) }
            $Test.Rate.Text = '{0:N0} Hz' -f $value
            $Test.RateDetail.Text = T ('Abfragerate · aus {0} Meldungen{1}' -f $mouse.Samples, $(if ($mouse.Devices -gt 1) { " · $($mouse.Devices) Mäuse gefunden" } else { '' }))
        }
        $Test.Hz = [int]$value
        $Test.HzMin = [bool]$mouse.Limited
    }
    for ($b = 0; $b -lt 5; $b++) {
        $chip = $Test.MouseChips[$b]
        $chip.Child.Text = '{0} · {1}' -f (T $script:MouseButtons[$b]), $mouse.Clicks[$b]
        Set-InputChip $chip ([bool]$mouse.Down[$b]) ($mouse.Clicks[$b] -gt 0)
    }
    $Test.Wheel.Child.Text = '{0} · {1}' -f (T 'Rad'), $mouse.Wheel
    $row = $Test.MouseRow
    # ab zwei Fällen bei derselben Taste ist es ein verschlissener Schalter; ein einzelner kann vorkommen (etwa beim Mausrad)
    $bad = @(for ($b = 0; $b -lt 5; $b++) { if ($mouse.Bounces[$b] -ge 2) { '{0} {1}×' -f (T $script:MouseButtons[$b]), $mouse.Bounces[$b] } })
    $once = @(for ($b = 0; $b -lt 5; $b++) { if ($mouse.Bounces[$b] -eq 1) { T $script:MouseButtons[$b] } })
    $total = ($mouse.Clicks | Measure-Object -Sum).Sum
    if (-not $bad -and $once) {
        $row.FindName('Title').Text = T 'Einmal nachgeprellt'
        $row.FindName('Text').Text = T ("Bei $total Klicks hat diese Taste einmal kurz nach dem Loslassen nachgeprellt: $($once -join ', '). Das kann einmal vorkommen, etwa beim Mausrad; passiert es öfter, ist der Schalter verschlissen.")
        Set-Paint $row.FindName('Glyph') 'Foreground' 'Accent'
    }
    elseif ($bad) {
        $row.FindName('Title').Text = T 'Ungewollte Doppelklicks'
        $row.FindName('Text').Text = T ("Kurz nach dem Loslassen wieder ausgelöst: $($bad -join ', '). Das ist meist ein verschlissener Schalter; tritt es öfter auf, hilft nur ein neuer Schalter oder eine neue Maus.")
        Set-Paint $row.FindName('Glyph') 'Foreground' 'Warn'
    }
    elseif (($mouse.Clicks | Measure-Object -Sum).Sum -ge 20) {
        $row.FindName('Title').Text = T 'Kein Doppelklick-Fehler'
        $row.FindName('Text').Text = T ('{0} Klicks, keiner hat von selbst doppelt ausgelöst.' -f ($mouse.Clicks | Measure-Object -Sum).Sum)
        Set-Paint $row.FindName('Glyph') 'Foreground' 'Good'
    }
}
