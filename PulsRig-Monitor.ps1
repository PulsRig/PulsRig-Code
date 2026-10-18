# PulsRig - Monitor-Test: Farbflächen im Vollbild für tote und hängende Pixel, Lichthöfe, ungleichmäßige Ausleuchtung
# und Farbstufen, dazu ein Bewegungsbild für Schlieren. Wird von PulsRig.ps1 nach PulsRig-Akku.ps1 eingebunden.
#
# Zuerst ein Fenster mit den Bildschirmen (Auflösung, Bildwiederholrate jetzt und höchstens) und was jedes Bild zeigt.
# "Test starten" öffnet das Vollbild auf dem Bildschirm, auf dem PulsRig gerade steht. Weiter mit Leertaste, Pfeil
# rechts oder Klick, zurück mit Pfeil links, H zeigt den Hinweis wieder, Esc beendet. Geändert wird nichts.

$script:Queries.Displays = @'
param($a)
$list = @()
try {
    foreach ($d in @(Get-DisplayStatus)) {
        if (-not $d.Current) { continue }
        $rates = @($d.Modes | Where-Object { $_.Width -eq $d.Current.Width -and $_.Height -eq $d.Current.Height } | ForEach-Object { [int]$_.Frequency } | Sort-Object -Unique)
        $list += @{ Name = "$($d.Name)"; Width = [int]$d.Current.Width; Height = [int]$d.Current.Height; Hz = [int]$d.Current.Frequency
            Max = $(if ($rates.Count) { [int]$rates[-1] } else { [int]$d.Current.Frequency }); Primary = [bool]$d.Primary }
    }
}
catch { }
@{ Displays = $list }
'@

# Die Bilder der Reihe nach: Name, Farbe (oder Art), was man darauf sucht
$script:MonitorScreens = @(
    @{ Name = 'Schwarz'; Color = '#000000'; Hint = 'Leuchtende Punkte sind hängende Pixel. Helle Flecken an den Rändern sind Lichthöfe – im dunklen Raum am besten zu sehen.' },
    @{ Name = 'Weiß'; Color = '#FFFFFF'; Hint = 'Dunkle Punkte sind tote Pixel. Gelbliche oder fleckige Bereiche zeigen eine ungleichmäßige Ausleuchtung.' },
    @{ Name = 'Rot'; Color = '#FF0000'; Hint = 'Ein Punkt in einer anderen Farbe ist ein defektes Subpixel.' },
    @{ Name = 'Grün'; Color = '#00FF00'; Hint = 'Ein Punkt in einer anderen Farbe ist ein defektes Subpixel.' },
    @{ Name = 'Blau'; Color = '#0000FF'; Hint = 'Ein Punkt in einer anderen Farbe ist ein defektes Subpixel.' },
    @{ Name = 'Grau'; Color = '#7F7F7F'; Hint = 'Wolkige Flecken oder dunklere Ecken zeigen eine ungleichmäßige Ausleuchtung.' },
    @{ Name = 'Farbverlauf'; Color = 'gradient'; Hint = 'Der Verlauf sollte gleichmäßig sein. Deutliche Stufen oder Streifen deuten auf wenig Farbtiefe oder eine falsche Einstellung.' },
    @{ Name = 'Bewegung'; Color = 'motion'; Hint = 'Zieht der Block Schlieren oder einen Schatten hinter sich her? Ruckelt er, läuft der Bildschirm womöglich nicht mit seiner vollen Bildwiederholrate.' }
)

function Open-MonitorSheet {
    $opened = Open-Sheet @{
        Title     = 'Monitor-Test'
        Sub       = 'Tote Pixel, Lichthöfe und Schlieren im Vollbild prüfen'
        Glyph     = 0xE7F4
        Primary   = 'Test starten'
        Show      = { param($tab) Show-MonitorTab }
        OnPrimary = { Start-MonitorTest }
        OnAction  = { param($item) if ($item.Data -and $item.Data.Do -eq 'display') { try { Start-Process 'ms-settings:display-advanced' } catch { } } }
    }
    if (-not $opened) { return }
    Show-MonitorTab
    Start-Query 'Displays' {
        param($result)
        Set-DisplayCardState @($result.Displays)
        if ($script:Sheet -and $script:Sheet.Title -eq 'Monitor-Test') { $script:Sheet.Displays = @($result.Displays); Show-MonitorTab }
    }
}

# Karte "Bildschirm" auf der Hardware-Seite: Hz oder Zahl der Bildschirme, gelb wenn einer unter seiner höchsten Rate läuft
function Set-DisplayCardState($Displays) {
    $list = @($Displays | Where-Object { $_ })
    if ($list.Count -eq 0) { return }
    $slow = @($list | Where-Object { $_.Max -gt $_.Hz }).Count
    $text = if ($slow -gt 0) { "$slow zu langsam" } elseif ($list.Count -eq 1) { "$($list[0].Hz) Hz" } else { "$($list.Count) Bildschirme" }
    Set-CardState 'Displays' @{ Text = $text; Tone = $(if ($slow -gt 0) { 'warn' } else { 'good' }); Detail = (@($list | ForEach-Object { "$($_.Hz) Hz" }) -join ' · ') }
}

function Show-MonitorTab {
    $rows = @()
    $rows += New-SheetRow -Kind 'head' -Title 'BILDSCHIRME'
    $displays = $script:Sheet.Displays
    if ($null -eq $displays) { $rows += New-SheetRow -Title 'Lese die Bildschirme …' -Glyph 0xE7F4 -Tone '' }
    else {
        foreach ($display in @($displays)) {
            $slow = $display.Max -gt $display.Hz
            $name = if ($display.Name) { $display.Name } else { 'Bildschirm' }
            $rows += New-SheetRow -Title "$name$(if ($display.Primary -and @($displays).Count -gt 1) { ' (Hauptbildschirm)' })" `
                -Sub $(if ($slow) { "$($display.Width) × $($display.Height) mit $($display.Hz) Hz – er kann aber $($display.Max) Hz. In den Anzeigeeinstellungen umstellen." } else { "$($display.Width) × $($display.Height) mit $($display.Hz) Hz, der höchsten Rate bei dieser Auflösung" }) `
                -Glyph 0xE7F4 -Tone $(if ($slow) { 'warn' } else { 'good' }) -State "$($display.Hz) Hz" -Action $(if ($slow) { 'Einstellen' } else { '' }) -Data @{ Do = 'display' }
        }
    }
    if (@($displays).Count -gt 1) { $rows += New-SheetRow -Title 'Getestet wird der Bildschirm, auf dem PulsRig steht' -Sub 'Für einen anderen Bildschirm das Fenster von PulsRig vorher dorthin schieben.' -Glyph 0xE946 -Tone '' }
    $rows += New-SheetRow -Kind 'head' -Title 'DIE BILDER DES TESTS'
    $index = 1
    foreach ($screen in $script:MonitorScreens) {
        $rows += New-SheetRow -Title "$index. $($screen.Name)" -Sub $screen.Hint -Glyph $(if ($screen.Color -eq 'motion') { 0xE768 } else { 0xE790 }) -Tone 'accent'
        $index++
    }
    Show-SheetList $rows
    Set-SheetStateText 'Weiter mit Leertaste oder Klick, zurück mit Pfeil links, Esc beendet'
}

# Vollbild: eine Fläche je Bild, ein Block für das Bewegungsbild und ein Hinweis unten, der nach ein paar Sekunden verblasst
$monitorXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" ResizeMode="NoResize" Topmost="True" ShowInTaskbar="False" Background="Black" Cursor="None"
        WindowStartupLocation="Manual" FontFamily="Segoe UI Variable Display, Segoe UI">
    <Grid>
        <Rectangle x:Name="Plane" Fill="Black"/>
        <Canvas x:Name="Motion" Visibility="Collapsed" ClipToBounds="True">
            <Border x:Name="Block" Width="160" Height="160" Background="White">
                <Border.RenderTransform>
                    <TranslateTransform/>
                </Border.RenderTransform>
            </Border>
        </Canvas>
        <Border x:Name="Hint" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,60" MaxWidth="760" Padding="22,16" CornerRadius="16" Background="#E6101828" BorderBrush="#40FFFFFF" BorderThickness="1">
            <StackPanel>
                <TextBlock x:Name="HintTitle" FontSize="17" FontWeight="SemiBold" Foreground="White"/>
                <TextBlock x:Name="HintText" FontSize="14" Foreground="#C8D2E6" TextWrapping="Wrap" Margin="0,6,0,0"/>
                <TextBlock x:Name="HintKeys" FontSize="12" Foreground="#8B97B0" TextWrapping="Wrap" Margin="0,10,0,0"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
'@

function Start-MonitorTest {
    $test = [Windows.Markup.XamlReader]::Parse($monitorXaml)
    $script:MonitorTest = @{ Window = $test; Index = 0; Plane = $test.FindName('Plane'); Motion = $test.FindName('Motion'); Block = $test.FindName('Block')
        Hint = $test.FindName('Hint'); Title = $test.FindName('HintTitle'); Text = $test.FindName('HintText'); Keys = $test.FindName('HintKeys') }
    $script:MonitorTest.Keys.Text = T 'Leertaste oder Klick: weiter · Pfeil links: zurück · H: Hinweis · Esc: beenden'
    # auf dem Bildschirm, auf dem PulsRig steht: dorthin setzen und dort ganz aufziehen
    $test.Left = $window.Left + 40; $test.Top = $window.Top + 40; $test.Width = 400; $test.Height = 300
    $test.Add_Loaded({ $this.WindowState = 'Maximized'; Show-MonitorScreen })
    $test.Add_KeyDown({
            try {
                switch ("$($_.Key)") {
                    { $_ -in 'Space', 'Right', 'Return', 'Enter', 'PageDown' } { Step-MonitorTest 1 }
                    { $_ -in 'Left', 'Back', 'PageUp' } { Step-MonitorTest -1 }
                    'H' { Show-MonitorHint }
                    'Escape' { $this.Close() }
                }
            }
            catch { Write-AppError $_ }
        })
    $test.Add_MouseLeftButtonUp({ try { Step-MonitorTest 1 } catch { Write-AppError $_ } })
    $test.Add_MouseRightButtonUp({ try { Step-MonitorTest -1 } catch { Write-AppError $_ } })
    $test.Add_Closed({ try { $script:MonitorTest = $null; $window.Activate() | Out-Null } catch { } })
    $test.Show()
    $test.Activate() | Out-Null
}

function Step-MonitorTest([int]$Way) {
    $run = $script:MonitorTest
    if (-not $run) { return }
    $next = $run.Index + $Way
    if ($next -lt 0) { return }
    if ($next -ge $script:MonitorScreens.Count) { $run.Window.Close(); return }
    $run.Index = $next
    Show-MonitorScreen
}

function Show-MonitorScreen {
    $run = $script:MonitorTest
    $screen = $script:MonitorScreens[$run.Index]
    $run.Block.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null)
    $run.Motion.Visibility = 'Collapsed'
    switch ($screen.Color) {
        'gradient' {
            $brush = New-Object Windows.Media.LinearGradientBrush ([Windows.Media.Colors]::Black), ([Windows.Media.Colors]::White), 0.0
            $run.Plane.Fill = $brush
        }
        'motion' {
            $run.Plane.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(64, 64, 64))
            $run.Motion.Visibility = 'Visible'
            # der Block gleitet gleichmäßig von links nach rechts und wieder zurück, in der Mitte der Höhe
            $width = [Math]::Max(800.0, $run.Window.ActualWidth)
            [Windows.Controls.Canvas]::SetTop($run.Block, [Math]::Max(0.0, ($run.Window.ActualHeight - 160) / 2))
            $slide = New-Object Windows.Media.Animation.DoubleAnimation 0.0, ($width - 160), (New-Object Windows.Duration ([TimeSpan]::FromSeconds(2.2)))
            $slide.AutoReverse = $true
            $slide.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            $run.Block.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $slide)
        }
        default { $run.Plane.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($screen.Color)) }
    }
    $run.Title.Text = T "$($run.Index + 1) von $($script:MonitorScreens.Count): $($screen.Name)"
    $run.Text.Text = T $screen.Hint
    Show-MonitorHint
}

# Hinweis einblenden und nach ein paar Sekunden verblassen lassen, damit er beim Suchen nicht stört
function Show-MonitorHint {
    $hint = $script:MonitorTest.Hint
    $hint.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $hint.Opacity = 1
    $fade = New-Object Windows.Media.Animation.DoubleAnimation 1.0, 0.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700)))
    $fade.BeginTime = [TimeSpan]::FromSeconds(3.5)
    $hint.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
}

$ui.HardwareMonitorPill.Add_MouseLeftButtonUp({ try { Open-MonitorSheet } catch { Write-AppError $_ } })
