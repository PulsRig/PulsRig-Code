# PulsRig - Nacht-Bento: der Umbau der Seiten für das Grunddesign ab 18.10.2026 (Entwurf P8, Reihe Q im Artifact).
# Nur im Skin "Bento" aktiv; alle anderen Skins (Klassisch und die übrigen) bleiben unberührt. Farben, Flächen und
# Fenster als Seiten legt der Skin-Eintrag in PulsRig-Skins.ps1 fest, hier entsteht, was nach dem Laden dazukommt:
#   Weg-Leiste   oben links der Weg zur aktuellen Ansicht ("Scan › Hardware › Arbeitsspeicher"), jeder Teil anklickbar
#   Zurück       führt genau eine Ebene zurück: aus einem Fenster auf die Seite darunter, von einer Seite zum Scan
#   Leiste       ein Klick in der Leiste schließt ein offenes Fenster und wechselt die Seite (sonst gesperrt)

if ("$($script:Settings.Skin)" -ne 'Bento') { return }
$script:Bento = $true

# --- Weg-Leiste und Zurück-Knopf ------------------------------------------------

$bentoCrumbXaml = @'
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="30,4,0,0">
    <Border x:Name="BentoBack" Height="30" CornerRadius="15" Padding="9,0,14,0" Background="#0B0710" BorderBrush="#2A1D3A" BorderThickness="1"
            Cursor="Hand" Margin="0,0,10,0" Visibility="Collapsed" ToolTip="Eine Ebene zurück">
        <Border.RenderTransform>
            <TranslateTransform/>
        </Border.RenderTransform>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock Text="&#xE76B;" FontFamily="Segoe MDL2 Assets" FontSize="10.5" Foreground="#E2DCEB" VerticalAlignment="Center"/>
            <TextBlock x:Name="BentoBackText" Text="Zurück" FontSize="12.5" FontWeight="SemiBold" Foreground="#E2DCEB" VerticalAlignment="Center" Margin="7,0,0,1"/>
        </StackPanel>
    </Border>
    <StackPanel x:Name="BentoCrumbs" Orientation="Horizontal" VerticalAlignment="Center"/>
</StackPanel>
'@
$bentoBar = [Windows.Markup.XamlReader]::Parse($bentoCrumbXaml)
[void]$ui.TitleBar.Children.Add($bentoBar)
$ui.BentoBack = $bentoBar.FindName('BentoBack')
$ui.BentoBackText = $bentoBar.FindName('BentoBackText')
$ui.BentoCrumbs = $bentoBar.FindName('BentoCrumbs')
$ui.BentoBackText.Text = T 'Zurück'

$script:BentoPageNames = @{ Home = 'Scan'; Results = 'Ergebnisse'; Boost = 'Boost'; Tools = 'Werkzeuge'; Hardware = 'Hardware' }

# Der Weg zur aktuellen Ansicht: Scan, dann die Seite (Ergebnisse liegen unter Scan), dann ein offenes Fenster
function Get-BentoTrail {
    $trail = @(@{ Text = 'Scan'; Go = 'Home' })
    if ($script:Page -ne 'Home') { $trail += @{ Text = $script:BentoPageNames[$script:Page]; Go = $script:Page } }
    # zweite Ebene einer Seite (Liste einer Absicht, Detailseite eines Bauteils)
    if ($script:BentoSub -and $script:BentoSubPage -eq $script:Page) { $trail += @{ Text = $script:BentoSub; Go = 'Sub' } }
    if ($script:Sheet -and $script:Sheet.Title) { $trail += @{ Text = $script:Sheet.Title; Go = 'Sheet' } }
    , $trail
}

function Update-BentoCrumbs {
    $trail = Get-BentoTrail
    if ($ui.BentoToolSearch) { $ui.BentoToolSearch.Visibility = if ($script:Page -eq 'Tools' -and -not $script:Sheet -and (-not $script:BentoSub -or $script:BentoSub -eq 'Suche')) { 'Visible' } else { 'Collapsed' } }
    $ui.BentoCrumbs.Children.Clear()
    for ($i = 0; $i -lt $trail.Count; $i++) {
        $last = $i -eq $trail.Count - 1
        if ($i -gt 0) {
            $sep = New-Object Windows.Controls.TextBlock
            $sep.Text = [string][char]0x203A
            $sep.FontSize = 14
            $sep.Margin = New-Object Windows.Thickness 2, 0, 2, 1
            $sep.VerticalAlignment = 'Center'
            $sep.Foreground = New-SolidBrush '#3E3150'
            [void]$ui.BentoCrumbs.Children.Add($sep)
        }
        $crumb = New-Object Windows.Controls.TextBlock
        $crumb.Text = T $trail[$i].Text
        $crumb.FontSize = 13.5
        $crumb.Padding = New-Object Windows.Thickness 5, 3, 5, 3
        $crumb.VerticalAlignment = 'Center'
        $crumb.FontWeight = if ($last) { 'SemiBold' } else { 'Normal' }
        $crumb.Foreground = New-SolidBrush $(if ($last) { '#FFFFFF' } else { '#8C819F' })
        if (-not $last) {
            $crumb.Cursor = 'Hand'
            $crumb.Tag = $trail[$i].Go
            $crumb.Add_MouseEnter({ $this.Foreground = New-SolidBrush '#FFFFFF' })
            $crumb.Add_MouseLeave({ $this.Foreground = New-SolidBrush '#8C819F' })
            $crumb.Add_MouseLeftButtonDown({ $_.Handled = $true })
            $crumb.Add_MouseLeftButtonUp({ try { Invoke-BentoJump ([string]$this.Tag) } catch { Write-AppError $_ } })
        }
        [void]$ui.BentoCrumbs.Children.Add($crumb)
    }
    $show = $trail.Count -gt 1
    if ($show -and $ui.BentoBack.Visibility -ne 'Visible') {
        $ui.BentoBack.Visibility = 'Visible'
        Start-Fade $ui.BentoBack 1 220 0 0
        $ui.BentoBack.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -8 -To 0 -Ms 320))
    }
    elseif (-not $show) { $ui.BentoBack.Visibility = 'Collapsed' }
}

# Springt zu einem Teil des Weges: ein offenes Fenster schließt sich, die Seite wechselt
function Invoke-BentoJump([string]$Go) {
    if ($script:Dialog) { return }
    if ($script:Sheet) { Close-Sheet }
    if ($Go -eq $script:Page -and $script:BentoSub) { Close-BentoSub }
    elseif ($Go -notin 'Sheet', 'Sub' -and $Go -ne $script:Page) { Show-Page $Go }
    Update-BentoCrumbs
}

# Genau eine Ebene zurück
function Invoke-BentoBack {
    if ($script:Dialog) { return }
    if ($script:Sheet) { Close-Sheet; Update-BentoCrumbs; return }
    if ($script:BentoSub) { Close-BentoSub; return }
    if ($script:Page -ne 'Home') { Show-Page 'Home' }
}

$ui.BentoBack.Add_MouseEnter({ $this.Background = New-SolidBrush '#1A1224'; $this.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To -2 -Ms 150)) })
$ui.BentoBack.Add_MouseLeave({ $this.Background = New-SolidBrush '#0B0710'; $this.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 0 -Ms 200)) })
$ui.BentoBack.Add_MouseLeftButtonDown({ $_.Handled = $true })
$ui.BentoBack.Add_MouseLeftButtonUp({ try { Invoke-BentoBack } catch { Write-AppError $_ } })

# Die Weg-Leiste folgt jedem Seitenwechsel und jedem Fenster
$script:BentoShowPage = ${function:Show-Page}
$script:BentoOpenSheet = ${function:Open-Sheet}
$script:BentoCloseSheet = ${function:Close-Sheet}
function Show-Page([string]$Name) {
    if ($Name -ne $script:Page -and $script:BentoSub) { Close-BentoSub -Quiet }
    & $script:BentoShowPage $Name
    Update-BentoNavSettings
    Update-BentoCrumbs
}

# "Optionen" unten in der Leiste: als Seite hell und mit der Marke daneben (die Marke rückt sonst nach Reihenfolge)
function Update-BentoNavSettings {
    $on = $script:Page -eq 'Options'
    $line = @($ui.NavSettings.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] })[0]
    Start-Fade $line $(if ($on) { 1 } else { 0.72 }) 240
    Set-Paint $line.Children[0] 'Foreground' $(if ($on) { 'Accent' } else { 'Text' })
    $line.Children[1].FontWeight = if ($on) { 'SemiBold' } else { 'Normal' }
    if ($on) {
        $spot = $ui.NavSettings.TranslatePoint((New-Object Windows.Point 0, 0), $ui.NavIndicator.Parent).Y
        foreach ($move in $ui.NavIndicator.RenderTransform, $script:NavBarMove) {
            $move.BeginAnimation($P.Y, (New-DoubleAnim -To $spot -Ms 420 -Ease $script:EaseBack))
        }
    }
}

# Schließt die zweite Ebene der aktuellen Seite
function Close-BentoSub([switch]$Quiet) {
    if (-not $script:BentoSub) { return }
    $hide = $script:BentoSubHide
    $script:BentoSub = $null; $script:BentoSubPage = $null; $script:BentoSubHide = $null
    if ($hide) { & $hide $Quiet.IsPresent }
    Update-BentoCrumbs
}
function Open-Sheet([hashtable]$Definition) { $opened = & $script:BentoOpenSheet $Definition; Update-BentoCrumbs; $opened }
function Close-Sheet([switch]$Quick) { & $script:BentoCloseSheet -Quick:$Quick; Update-BentoCrumbs }

# Leiste: mit offenem Fenster schließt ein Klick das Fenster und wechselt dann die Seite
foreach ($nav in $ui.NavHome, $ui.NavBoost, $ui.NavTools, $ui.NavHardware) {
    $nav.Add_MouseLeftButtonUp({
            try {
                if ($script:Dialog) { return }
                if (-not $script:Sheet) { if ($this.Tag -eq $script:Page -and $script:BentoSub) { Close-BentoSub }; return }
                Close-Sheet -Quick
                if ($this.Tag -ne $script:Page) { Show-Page $this.Tag }
            }
            catch { Write-AppError $_ }
        })
}
$ui.NavSettings.Add_MouseLeftButtonUp({ try { if (-not $script:Dialog -and $script:Sheet) { Close-Sheet -Quick; Show-Page 'Options' } } catch { Write-AppError $_ } })

# --- Kacheln mit eigenem Farbton --------------------------------------------------

# Farbtöne der Kacheln: Schrift-/Randfarbe und dunkler Grundton oben links (Entwurf P8)
$script:BentoTones = @{
    Lila   = @{ C = '#8C6BD6'; Tint = '#160D29' }
    Indigo = @{ C = '#7A66D0'; Tint = '#130B24' }
    Beere  = @{ C = '#C0608F'; Tint = '#1F0A19' }
    Rose   = @{ C = '#C0608F'; Tint = '#1B0916' }
    Gruen  = @{ C = '#5EE0A0'; Tint = '#10291F' }
    Bernst = @{ C = '#F2B661'; Tint = '#2A2112' }
    Grau   = @{ C = '#B3A8C4'; Tint = '#0B0710' }
}

# Hintergrund einer Kachel: oben links der Farbton, nach unten rechts in die dunkle Fläche
function New-BentoTint([string]$Tone) {
    $t = $script:BentoTones[$Tone]
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point 0, 0
    $brush.EndPoint = New-Object Windows.Point 0.55, 1
    $brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($t.Tint)), 0))
    $brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#09060D')), 0.75))
    $brush.Freeze()
    $brush
}

function New-BentoEdge([string]$Tone) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($script:BentoTones[$Tone].C)
    $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x38, $c.R, $c.G, $c.B))
    $brush.Freeze()
    $brush
}

# Färbt eine Kachel (Knopf mit Kachel-Vorlage oder Karte) in einem Farbton
function Set-BentoTone($Element, [string]$Tone) {
    $Element.Background = New-BentoTint $Tone
    $Element.BorderBrush = New-BentoEdge $Tone
}

# --- Startseite als Kachelmosaik --------------------------------------------------
# Die vorhandenen Bausteine (mit allen Namen, an denen die Funktionen hängen) ziehen in ein Raster aus sechs
# Spalten und drei Reihen: links groß der SCAN-Bereich, rechts Live-Werte, Gaming-Check und Änderungen, unten
# Gerätetreiber, Spielkomponenten, Boost und Werkzeuge.

$bentoTileXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="Auto" Height="Auto" Margin="0">
    <Grid Margin="2,0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid>
            <TextBlock x:Name="Kicker" FontSize="12.5" FontWeight="SemiBold"/>
            <TextBlock x:Name="Arrow" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="10" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#5C4F70"/>
        </Grid>
        <TextBlock x:Name="Value" Grid.Row="1" FontSize="22" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="Note" Grid.Row="3" FontSize="11.5" Foreground="#8C819F" TextWrapping="Wrap"/>
    </Grid>
</Button>
'@

function New-BentoTile([string]$Tone, [string]$Kicker, [string]$Value, [string]$Note, [scriptblock]$OnClick) {
    $tile = [Windows.Markup.XamlReader]::Parse($bentoTileXaml)
    $tile.Style = $window.FindResource('TileButton')
    $tile.Width = [double]::NaN
    $tile.Height = [double]::NaN
    $tile.Margin = New-Object Windows.Thickness 6
    Set-BentoTone $tile $Tone
    $tile.FindName('Kicker').Text = T $Kicker
    $tile.FindName('Kicker').Foreground = New-SolidBrush $script:BentoTones[$Tone].C
    $tile.FindName('Value').Text = T $Value
    $tile.FindName('Note').Text = T $Note
    $tile.Tag = $OnClick
    $tile.Add_Click({ try { & $this.Tag } catch { Write-AppError $_ } })
    $tile
}

function Set-BentoHome {
    $page = $ui.PageHome
    $scanCard = $page.Children[0]
    $right = $page.Children[1]
    foreach ($part in $ui.HomeLiveCard, $ui.HomeHistory, $ui.HomeGameCheck) { $right.Children.Remove($part) }
    $chips = $ui.ChipDrivers.Parent
    foreach ($part in $ui.ChipDrivers, $ui.ChipGames) { $chips.Children.Remove($part) }
    $chips.Visibility = 'Collapsed'
    $page.Children.Clear()

    # Raster: sechs gleiche Spalten; die erste Reihe etwas höher, die letzte etwas flacher
    $page.ColumnDefinitions.Clear()
    for ($i = 0; $i -lt 6; $i++) { $page.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
    foreach ($weight in 1.12, 1.0, 0.88) {
        $row = New-Object Windows.Controls.RowDefinition
        $row.Height = New-Object Windows.GridLength $weight, 'Star'
        $page.RowDefinitions.Add($row)
    }
    $page.Margin = New-Object Windows.Thickness -6, -6, -6, -6

    $place = {
        param($element, [int]$col, [int]$row, [int]$colSpan = 1, [int]$rowSpan = 1)
        $element.Margin = New-Object Windows.Thickness 6
        [Windows.Controls.Grid]::SetColumn($element, $col)
        [Windows.Controls.Grid]::SetRow($element, $row)
        [Windows.Controls.Grid]::SetColumnSpan($element, $colSpan)
        [Windows.Controls.Grid]::SetRowSpan($element, $rowSpan)
        [void]$page.Children.Add($element)
    }

    # SCAN-Bereich: groß links über zwei Reihen, der Knopf etwas kleiner, Rand leuchtet violett zu rosa
    & $place $scanCard 0 0 3 2
    $ui.Orb.LayoutTransform = New-Object Windows.Media.ScaleTransform 0.78, 0.78
    $ui.LastScanText.Margin = New-Object Windows.Thickness 0, 0, 0, 2
    # im schmaleren SCAN-Bereich darf das Statusschild den Text links nicht zusammendrücken
    $ui.StatusText.MaxWidth = 200
    $ui.StatusText.TextTrimming = 'CharacterEllipsis'
    $ui.HintText.Parent.MinWidth = 150

    # Live-Werte, Gaming-Check und Änderungen rechts
    & $place $ui.HomeLiveCard 3 0 2 1
    Set-BentoTone $ui.HomeLiveCard 'Lila'
    $ui.HomeLiveCard.Padding = New-Object Windows.Thickness 18, 14, 18, 10

    & $place $ui.HomeGameCheck 5 0
    Set-BentoTone $ui.HomeGameCheck 'Beere'
    $ui.HomeGameCheck.Height = [double]::NaN
    # Ring oben groß, Text darunter mittig
    $game = $ui.HomeGameCheck.Content
    $game.ColumnDefinitions.Clear()
    foreach ($h in 'Star', 'Auto') { $r = New-Object Windows.Controls.RowDefinition; $r.Height = New-Object Windows.GridLength 1, $h; $game.RowDefinitions.Add($r) }
    $ring = $game.Children[0]
    $ring.LayoutTransform = New-Object Windows.Media.ScaleTransform 1.45, 1.45
    $ring.HorizontalAlignment = 'Center'
    $text = $game.Children[1]
    [Windows.Controls.Grid]::SetColumn($text, 0)
    [Windows.Controls.Grid]::SetRow($text, 1)
    $text.Margin = New-Object Windows.Thickness 0, 8, 0, 0
    foreach ($line in $text.Children) { $line.HorizontalAlignment = 'Center'; $line.TextAlignment = 'Center' }
    $game.Children[2].Visibility = 'Collapsed'

    & $place $ui.HomeHistory 3 1 3 1
    Set-BentoTone $ui.HomeHistory 'Indigo'
    $ui.HomeHistory.Height = [double]::NaN

    # untere Reihe
    & $place $ui.ChipDrivers 0 2 2 1
    Set-BentoTone $ui.ChipDrivers 'Rose'
    & $place $ui.ChipGames 2 2 1 1
    Set-BentoTone $ui.ChipGames 'Bernst'
    foreach ($chip in $ui.ChipDrivers, $ui.ChipGames) { $chip.Height = [double]::NaN }
    # Spielkomponenten in schmaler Kachel: Symbol oben, Text darunter
    $gamesGrid = $ui.ChipGames.Content
    $gamesGrid.ColumnDefinitions.Clear()
    foreach ($h in 'Auto', 'Star') { $r = New-Object Windows.Controls.RowDefinition; $r.Height = New-Object Windows.GridLength 1, $h; $gamesGrid.RowDefinitions.Add($r) }
    $gamesGrid.Children[0].HorizontalAlignment = 'Left'
    [Windows.Controls.Grid]::SetColumn($gamesGrid.Children[1], 0)
    [Windows.Controls.Grid]::SetRow($gamesGrid.Children[1], 1)
    $gamesGrid.Children[1].Margin = New-Object Windows.Thickness 0, 8, 0, 0
    $gamesGrid.Children[1].VerticalAlignment = 'Top'
    [Windows.Controls.Grid]::SetRow($gamesGrid.Children[2], 0)
    [Windows.Controls.Grid]::SetColumn($gamesGrid.Children[2], 0)
    $gamesGrid.Children[2].HorizontalAlignment = 'Right'

    $ui.BentoBoostTile = New-BentoTile 'Gruen' 'Boost' 'AUS' 'vor dem Spielen Platz schaffen' { Show-Page 'Boost' }
    & $place $ui.BentoBoostTile 3 2
    $ui.BentoToolsTile = New-BentoTile 'Grau' 'Werkzeuge' 'Etwas reparieren' 'Aufräumen, Treiber verwalten, fürs Spielen' { Show-Page 'Tools' }
    $ui.BentoToolsTile.FindName('Value').FontSize = 16
    & $place $ui.BentoToolsTile 4 2 2 1
}

# Die Boost-Kachel der Startseite folgt dem Schalter
$script:BentoSetGauge = ${function:Set-Gauge}
function Set-Gauge([bool]$On) {
    & $script:BentoSetGauge $On
    if ($script:BentoBoostShown -ne $On) { Set-BentoBoostLook $On }
    if ($ui.BentoBoostTile) {
        $ui.BentoBoostTile.FindName('Value').Text = T $(if ($On) { 'AN' } else { 'AUS' })
        $ui.BentoBoostTile.FindName('Note').Text = T $(if ($On) { 'läuft – Platz fürs Spiel geschaffen' } else { 'vor dem Spielen Platz schaffen' })
    }
}

# --- Werkzeuge nach Absicht (Entwurf Q2/Q3) -------------------------------------
# Übersicht: vier Kacheln nach Absicht und eine Empfehlung. Ein Klick öffnet die Liste dieser Absicht als eigene
# Ebene (Weg-Leiste "Scan › Werkzeuge › Aufräumen", Zurück führt zur Übersicht). Die Suche sitzt in der Titelzeile.

$script:BentoIntents = [ordered]@{
    'Etwas reparieren'  = @{ Tone = 'Beere'; Glyph = 0xE90F; Span = 2; Sub = 'Kein Ton, kein Netz, falsches Bild, Gerät mit Warnzeichen oder der PC wacht nachts auf.'; Tools = 'FixAudio', 'FixNetwork', 'FixResolution', 'FixDevices', 'Standby' }
    'Aufräumen'         = @{ Tone = 'Gruen'; Glyph = 0xE74D; Span = 1; Sub = 'Speicherplatz, Autostart und alte Geräteeinträge.'; Tools = 'CleanDisk', 'Autostart', 'CleanDevices' }
    'Treiber verwalten' = @{ Tone = 'Lila'; Glyph = 0xE74E; Span = 1; Sub = 'Sichern, zurückholen, vor Windows Update schützen, Neuinstallation und Verlauf.'; Tools = 'DriverBackup', 'GpuShield', 'Reinstall', 'RescueStick', 'History', 'IncompatibleDrivers' }
    'Fürs Spielen'      = @{ Tone = 'Bernst'; Glyph = 0xE7FC; Span = 1; Sub = 'Spielkomponenten, Controller und Systeminfos.'; Tools = 'GameRuntimes', 'InputTest', 'Power', 'SystemInfo' }
}

$bentoIntentTileXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="Auto" Height="Auto" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Button.RenderTransform>
        <ScaleTransform ScaleX="0.9" ScaleY="0.9"/>
    </Button.RenderTransform>
    <Grid Margin="4,2,2,-2">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid>
            <Border x:Name="IconBox" Width="46" Height="46" CornerRadius="14" BorderThickness="1" HorizontalAlignment="Left" RenderTransformOrigin="0.5,0.5">
                <Border.RenderTransform>
                    <ScaleTransform/>
                </Border.RenderTransform>
                <TextBlock x:Name="Icon" FontFamily="Segoe MDL2 Assets" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="Hint" CornerRadius="10" Padding="10,3" HorizontalAlignment="Right" VerticalAlignment="Top" Visibility="Collapsed">
                <TextBlock x:Name="HintText" FontSize="11"/>
            </Border>
        </Grid>
        <TextBlock x:Name="Title" Grid.Row="1" FontSize="19" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,12,0,0"/>
        <TextBlock x:Name="Sub" Grid.Row="2" FontSize="12" Foreground="#8C819F" TextWrapping="Wrap" Margin="0,3,0,0"/>
        <WrapPanel x:Name="Chips" Grid.Row="3" VerticalAlignment="Bottom" Margin="0,10,0,0"/>
        <TextBlock x:Name="Count" Grid.Row="4" FontSize="11.5" FontWeight="SemiBold" Margin="0,8,0,0"/>
    </Grid>
</Button>
'@

$bentoListRowXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="18" Background="#0B0710" BorderBrush="#1A1224" BorderThickness="1" Padding="18,0,16,0" Margin="0,0,0,10" Height="74" Opacity="0">
    <Border.RenderTransform>
        <TranslateTransform/>
    </Border.RenderTransform>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border x:Name="Bar" Width="4" Height="34" CornerRadius="2" Background="#22172F" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="16,0,10,0">
            <TextBlock x:Name="Title" FontSize="14.5" FontWeight="SemiBold" Foreground="#E2DCEB" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="Desc" FontSize="12" Foreground="#8C819F" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
        </StackPanel>
        <Border x:Name="Badge" Grid.Column="2" CornerRadius="10" Padding="9,3" VerticalAlignment="Center" Margin="0,0,12,0" Visibility="Collapsed">
            <TextBlock x:Name="BadgeText" FontSize="11"/>
        </Border>
        <Button x:Name="Start" Grid.Column="3" Style="{DynamicResource PrimaryButton}" MinWidth="96" Height="36" VerticalAlignment="Center"/>
    </Grid>
</Border>
'@

$bentoListXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Visibility="Collapsed">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="1*"/>
        <ColumnDefinition Width="14"/>
        <ColumnDefinition Width="2*"/>
    </Grid.ColumnDefinitions>
    <Border x:Name="Lead" CornerRadius="24" BorderThickness="1" Padding="24">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border x:Name="LeadIconBox" Width="64" Height="64" CornerRadius="20" BorderThickness="1" HorizontalAlignment="Left">
                <TextBlock x:Name="LeadIcon" FontFamily="Segoe MDL2 Assets" FontSize="28" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock x:Name="LeadTitle" Grid.Row="1" FontSize="26" FontWeight="SemiBold" Foreground="#E2DCEB" TextWrapping="Wrap" Margin="0,20,0,0"/>
            <TextBlock x:Name="LeadSub" Grid.Row="2" FontSize="13" Foreground="#8C819F" TextWrapping="Wrap" Margin="0,8,0,0" LineHeight="19"/>
            <Border Grid.Row="4" CornerRadius="14" Background="#06FFFFFF" BorderBrush="#22172F" BorderThickness="1" Padding="14,11">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="&#xE83D;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#5EE0A0" VerticalAlignment="Top" Margin="0,2,10,0"/>
                    <TextBlock x:Name="LeadNote" Grid.Column="1" FontSize="12" Foreground="#B3A8C4" TextWrapping="Wrap"/>
                </Grid>
            </Border>
        </Grid>
    </Border>
    <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="Rows"/>
    </ScrollViewer>
</Grid>
'@

function Get-BentoArgb([string]$Hex, [byte]$Alpha) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B))
    $brush.Freeze()
    $brush
}

# Ohne Adminrechte zeigen diese Werkzeuge nur, was sie tun würden (gleiche Regel wie die klassische Seite)
function Test-BentoDryRun([string]$Name) {
    -not $script:IsAdmin -and $script:NoAdminTools -notcontains $Name -and $Name -notin 'GameRuntimes', 'SystemInfo', 'History', 'Autostart', 'Standby', 'Power', 'DriverBackup', 'GpuShield', 'Reinstall', 'RescueStick', 'InputTest'
}

function Set-BentoTools {
    $page = $ui.PageTools
    $scroll = $ui.ToolGrid.Parent.Parent
    $head = $page.Children[0]
    # die Suche zieht in die Titelzeile; Überschrift und alte Liste bleiben unsichtbar im Baum
    $search = $ui.ToolSearch.Parent
    $search.Parent.Children.Remove($search)
    $search.Width = 220
    # das Eingabefeld braucht mit Rand und Innenabstand 34 Punkte, sonst schneidet es die Schrift unten ab
    $search.Height = 34
    $search.Margin = New-Object Windows.Thickness 18, 0, 0, 0
    $search.HorizontalAlignment = 'Left'
    $search.VerticalAlignment = 'Center'
    $ui.BentoToolSearch = $search
    $search.Visibility = 'Collapsed'
    [void]$ui.BentoCrumbs.Parent.Children.Add($search)
    $head.Visibility = 'Collapsed'
    $scroll.Visibility = 'Collapsed'

    # Übersicht: 3 Spalten × 2 Reihen
    $board = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRowSpan($board, 2)
    $board.Margin = New-Object Windows.Thickness -6, -6, -6, -6
    for ($i = 0; $i -lt 3; $i++) { $board.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
    for ($i = 0; $i -lt 2; $i++) { $board.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) }
    [void]$page.Children.Add($board)
    $ui.BentoToolBoard = $board

    $script:Tiles = @()
    $script:TileDelays = @()
    $places = @(@(0, 0), @(2, 0), @(0, 1), @(1, 1))
    $index = 0
    foreach ($intent in $script:BentoIntents.Keys) {
        $def = $script:BentoIntents[$intent]
        $tone = $script:BentoTones[$def.Tone]
        $tile = [Windows.Markup.XamlReader]::Parse($bentoIntentTileXaml)
        $tile.Style = $window.FindResource('TileButton')
        $tile.Width = [double]::NaN; $tile.Height = [double]::NaN
        $tile.Margin = New-Object Windows.Thickness 6
        Set-BentoTone $tile $def.Tone
        $tile.FindName('IconBox').Background = Get-BentoArgb $tone.C 0x1A
        $tile.FindName('IconBox').BorderBrush = Get-BentoArgb $tone.C 0x33
        $tile.FindName('Icon').Text = Get-Glyph $def.Glyph
        $tile.FindName('Icon').Foreground = New-SolidBrush $tone.C
        $tile.FindName('Title').Text = T $intent
        $tile.FindName('Sub').Text = T $def.Sub
        $tile.FindName('Count').Text = "$(T ('{0} Werkzeuge' -f $def.Tools.Count)) →"
        $tile.FindName('Count').Foreground = New-SolidBrush $tone.C
        $chips = $tile.FindName('Chips')
        foreach ($name in @($def.Tools | Select-Object -First $(if ($def.Span -eq 2) { 4 } else { 2 }))) {
            $chip = New-Object Windows.Controls.Border
            $chip.CornerRadius = New-Object Windows.CornerRadius 10
            $chip.Padding = New-Object Windows.Thickness 10, 4, 10, 5
            $chip.Margin = New-Object Windows.Thickness 0, 0, 6, 6
            $chip.Background = Get-BentoArgb '#FFFFFF' 0x08
            $chip.BorderBrush = New-SolidBrush '#22172F'
            $chip.BorderThickness = New-Object Windows.Thickness 1
            $text = New-Object Windows.Controls.TextBlock
            $text.Text = T $script:Tools[$name].Title
            $text.FontSize = 11.5
            $text.Foreground = New-SolidBrush '#B3A8C4'
            $chip.Child = $text
            [void]$chips.Children.Add($chip)
        }
        $tile.Tag = $intent
        $tile.Add_Click({ try { Show-BentoToolList ([string]$this.Tag) } catch { Write-AppError $_ } })
        [Windows.Controls.Grid]::SetColumn($tile, $places[$index][0])
        [Windows.Controls.Grid]::SetRow($tile, $places[$index][1])
        [Windows.Controls.Grid]::SetColumnSpan($tile, $def.Span)
        [void]$board.Children.Add($tile)
        $script:Tiles += $tile
        $script:TileDelays += 110 + 80 * $index
        $index++
    }

    # Empfehlung: Speicherplatz freigeben
    $reco = [Windows.Markup.XamlReader]::Parse($bentoRecoXaml)
    $reco.Margin = New-Object Windows.Thickness 6
    [Windows.Controls.Grid]::SetColumn($reco, 2)
    [Windows.Controls.Grid]::SetRow($reco, 1)
    [void]$board.Children.Add($reco)
    $reco.FindName('RecoKicker').Text = (T 'Empfohlen').ToUpper()
    $reco.FindName('RecoTitle').Text = T $script:Tools['CleanDisk'].Title
    $reco.FindName('RecoText').Text = T $script:Tools['CleanDisk'].Desc
    $reco.FindName('RecoGo').Content = T 'Jetzt aufräumen'
    $reco.FindName('RecoGo').Add_Click({ try { Open-Tool 'CleanDisk' } catch { Write-AppError $_ } })

    # Listenseite (zweite Ebene)
    $list = [Windows.Markup.XamlReader]::Parse($bentoListXaml)
    [Windows.Controls.Grid]::SetRowSpan($list, 2)
    [void]$page.Children.Add($list)
    $ui.BentoToolList = $list
    $list.FindName('LeadNote').Text = T 'Jedes Werkzeug prüft zuerst und fragt, bevor es etwas ändert.'
}

$bentoRecoXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="22" BorderThickness="1" Padding="20,18,20,18" Background="#F009060D">
    <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#806D43C9" Offset="0"/>
            <GradientStop Color="#2622172F" Offset="0.4"/>
            <GradientStop Color="#2622172F" Offset="0.7"/>
            <GradientStop Color="#55A8326F" Offset="1"/>
        </LinearGradientBrush>
    </Border.BorderBrush>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock x:Name="RecoKicker" FontFamily="Consolas" FontSize="10.5" Foreground="#8C819F"/>
        <TextBlock x:Name="RecoTitle" Grid.Row="1" FontSize="17" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,10,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="RecoText" Grid.Row="2" FontSize="12" Foreground="#8C819F" TextWrapping="Wrap" Margin="0,4,0,0"/>
        <Button x:Name="RecoGo" Grid.Row="4" Style="{DynamicResource PrimaryButton}" Height="40" HorizontalAlignment="Stretch"/>
    </Grid>
</Border>
'@

# Öffnet die Liste einer Absicht (oder das Suchergebnis) als eigene Ebene
function Show-BentoToolList([string]$Intent, [string[]]$Names) {
    $list = $ui.BentoToolList
    if ($Intent -and $script:BentoIntents.Contains($Intent)) {
        $def = $script:BentoIntents[$Intent]
        $Names = $def.Tools
        $toneName = $def.Tone
        $glyph = $def.Glyph
        $sub = $def.Sub
        $title = $Intent
    }
    else { $toneName = 'Lila'; $glyph = 0xE721; $title = 'Suche'; $sub = 'Werkzeuge, die zur Suche passen.' }
    $tone = $script:BentoTones[$toneName]
    $lead = $list.FindName('Lead')
    $lead.Background = New-BentoTint $toneName
    $lead.BorderBrush = New-BentoEdge $toneName
    $list.FindName('LeadIconBox').Background = Get-BentoArgb $tone.C 0x1A
    $list.FindName('LeadIconBox').BorderBrush = Get-BentoArgb $tone.C 0x33
    $list.FindName('LeadIcon').Text = Get-Glyph $glyph
    $list.FindName('LeadIcon').Foreground = New-SolidBrush $tone.C
    $list.FindName('LeadTitle').Text = T $title
    $list.FindName('LeadSub').Text = T $sub
    $rows = $list.FindName('Rows')
    $rows.Children.Clear()
    $i = 0
    foreach ($name in @($Names)) {
        $tool = $script:Tools[$name]
        if (-not $tool) { continue }
        $row = [Windows.Markup.XamlReader]::Parse($bentoListRowXaml)
        $row.FindName('Title').Text = T $tool.Title
        $row.FindName('Desc').Text = T $tool.Desc
        $row.FindName('Bar').Background = Get-BentoArgb $tone.C 0x55
        if (Test-BentoDryRun $name) {
            $row.FindName('Badge').Visibility = 'Visible'
            $row.FindName('Badge').Background = Get-BentoArgb $tone.C 0x1A
            $row.FindName('BadgeText').Text = T 'Probelauf'
            $row.FindName('BadgeText').Foreground = New-SolidBrush $tone.C
        }
        $start = $row.FindName('Start')
        $start.Content = T 'Starten'
        $start.Tag = $name
        $start.Add_Click({ try { Open-Tool ([string]$this.Tag) } catch { Write-AppError $_ } })
        $row.Tag = $tone.C
        $row.Add_MouseEnter({ $this.BorderBrush = Get-BentoArgb $this.Tag 0x55; $this.FindName('Bar').Background = New-SolidBrush $this.Tag })
        $row.Add_MouseLeave({ $this.BorderBrush = New-SolidBrush '#1A1224'; $this.FindName('Bar').Background = Get-BentoArgb $this.Tag 0x55 })
        [void]$rows.Children.Add($row)
        # die Zeilen kommen nacheinander von rechts herein
        Start-Fade $row 1 300 (80 + 60 * $i) 0
        $row.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From 18 -To 0 -Ms 420 -Delay (80 + 60 * $i)))
        $i++
    }
    $script:BentoSub = $title
    $script:BentoSubPage = 'Tools'
    $script:BentoSubHide = { param($quiet) Hide-BentoToolList $quiet }
    if ($ui.BentoToolBoard.Visibility -eq 'Visible') {
        $ui.BentoToolBoard.Visibility = 'Collapsed'
        $list.Visibility = 'Visible'
        Start-Fade $list 1 260 0 0
    }
    Update-BentoCrumbs
}

function Hide-BentoToolList([bool]$Quiet) {
    $ui.BentoToolList.Visibility = 'Collapsed'
    $ui.BentoToolBoard.Visibility = 'Visible'
    if (-not $Quiet) { Start-Fade $ui.BentoToolBoard 1 260 0 0; Show-Tiles }
}

# Suche in der Titelzeile: ein Wort zeigt die passenden Werkzeuge als Liste, leer führt zur Übersicht zurück
function Update-ToolFilter {
    $ui.ToolSearchHint.Visibility = if ($ui.ToolSearch.Text) { 'Collapsed' } else { 'Visible' }
    $words = @($ui.ToolSearch.Text.ToLower() -split '\s+' | Where-Object { $_ })
    if (-not $words.Count) { if ($script:BentoSub -eq 'Suche') { Close-BentoSub }; return }
    $hits = foreach ($intent in $script:BentoIntents.Keys) {
        foreach ($name in $script:BentoIntents[$intent].Tools) {
            $tool = $script:Tools[$name]
            $text = ("$(T $tool.Title) $(T $tool.Desc) $($tool.Title) $($tool.Desc) $($tool.Short) $($tool.ShortDesc) $($tool.Find) $intent").ToLower()
            $hit = $true
            foreach ($word in $words) { if (-not $text.Contains($word)) { $hit = $false; break } }
            if ($hit) { $name }
        }
    }
    Show-BentoToolList '' @($hits)
    $ui.BentoToolList.FindName('LeadSub').Text = if (@($hits).Count) { T 'Werkzeuge, die zur Suche passen.' } else { T 'Kein Werkzeug passt zu dieser Suche.' }
}

# --- Hardware: jede Karte in ihrem Farbton ----------------------------------------
# Reihenfolge der Karten wie in PulsRig-Hardware.ps1: Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher,
# Abstürze, Bildschirm, Bericht & Diagnose, BIOS
$script:BentoHardwareTones = 'Lila', 'Gruen', 'Bernst', 'Beere', 'Rose', 'Indigo', 'Beere', 'Grau'

function Set-BentoHardware {
    $i = 0
    foreach ($card in $ui.HardwareGrid.Children) {
        $tone = $script:BentoHardwareTones[$i % $script:BentoHardwareTones.Count]
        Set-BentoTone $card $tone
        $card.Resources['BentoTone'] = $tone
        # die Karte färbt ihren Rand beim Überfahren; danach bekommt sie ihren Farbton zurück
        $card.Add_MouseLeave({ try { $this.BorderBrush = New-BentoEdge $this.Resources['BentoTone'] } catch { Write-AppError $_ } })
        $i++
    }
}

# --- Boost: die beiden Karten in ihren Farbtönen ----------------------------------

function Get-BentoCards($Root) {
    $card = $window.FindResource('Card')
    $found = New-Object Collections.ArrayList
    $walk = {
        param($node)
        foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($node)) {
            if ($child -is [Windows.Controls.Border] -and $child.Style -eq $card) { [void]$found.Add($child) }
            if ($child -is [Windows.DependencyObject]) { & $walk $child }
        }
    }
    & $walk $Root
    , $found
}

function Set-BentoBoost {
    # Aufbau wie Entwurf Q4: links die große Kachel mit Kreis, Schritten und Ergebnis-Schildern, rechts sechs
    # Kacheln mit dem, was der Boost anfasst. Die alten Teile bleiben unsichtbar im Baum (der Code schreibt weiter hinein).
    $page = $ui.PageBoost
    foreach ($part in @($page.Children)) { $part.Visibility = 'Collapsed' }
    $board = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRowSpan($board, 2)
    $board.Margin = New-Object Windows.Thickness -6, -6, -6, -6
    for ($i = 0; $i -lt 4; $i++) { $board.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
    for ($i = 0; $i -lt 3; $i++) { $board.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) }
    [void]$page.Children.Add($board)

    # große Kachel links
    $hero = [Windows.Markup.XamlReader]::Parse($bentoBoostHeroXaml)
    $hero.Margin = New-Object Windows.Thickness 6
    [Windows.Controls.Grid]::SetColumnSpan($hero, 2)
    [Windows.Controls.Grid]::SetRowSpan($hero, 3)
    [void]$board.Children.Add($hero)
    foreach ($name in 'BentoBoostHead', 'BentoBoostSub', 'BentoBoostSpot', 'BentoBoostChipSpot', 'BentoBoostKicker', 'BentoBoostSetup') { $ui[$name] = $hero.FindName($name) }
    $ui.BentoBoostKicker.Text = (T 'Spiel-Beschleunigung').ToUpper()
    $ui.BentoBoostSetup.Content = T 'Einrichten'
    $ui.BentoBoostSetup.Add_Click({ try { Open-BoostSheet } catch { Write-AppError $_ } })
    $circle = [Windows.Markup.XamlReader]::Parse($bentoBoostXaml)
    [void]$ui.BentoBoostSpot.Children.Add($circle)
    foreach ($name in 'BentoBoostArc', 'BentoBoostDisc', 'BentoBoostBig', 'BentoBoostSmall', 'BentoBoostBolt', 'BentoBoostGlow', 'BentoBoostWaves') { $ui[$name] = $circle.FindName($name) }
    $ui.BentoBoostDisc.Add_MouseEnter({ Start-Scale $this 1.04 200 })
    $ui.BentoBoostDisc.Add_MouseLeave({ Start-Scale $this 1 260 })
    $ui.BentoBoostDisc.Add_MouseLeftButtonUp({ try { Open-ToolDialog 'GameBoost' } catch { Write-AppError $_ } })
    # die Schilder der Boost-Seite (was angefasst wurde bzw. wird) ziehen in die große Kachel
    $ui.BoostChips.Parent.Children.Remove($ui.BoostChips)
    [void]$ui.BentoBoostChipSpot.Children.Add($ui.BoostChips)

    # sechs Kacheln rechts
    $script:BentoBoostFacts = [ordered]@{}
    $defs = @(
        @{ Key = 'Plan'; Tone = 'Lila'; Kicker = 'Energieplan'; Go = { Open-BoostSheet; Select-SheetTab 2 } }
        @{ Key = 'Ram'; Tone = 'Beere'; Kicker = 'Arbeitsspeicher frei'; Go = { Open-BoostSheet } }
        @{ Key = 'Services'; Tone = 'Indigo'; Kicker = 'Dienste'; Go = { Open-BoostSheet; Select-SheetTab 1 } }
        @{ Key = 'Apps'; Tone = 'Rose'; Kicker = 'Speicherhungrige Programme'; Go = { Open-BoostSheet; Select-SheetTab 0 } }
        @{ Key = 'Games'; Tone = 'Bernst'; Kicker = 'Boost-Spiele'; Go = { Open-BoostSheet; Select-SheetTab 3 } }
        @{ Key = 'Check'; Tone = 'Gruen'; Kicker = 'Gaming-Check'; Go = { Open-GameCheckSheet } }
    )
    for ($i = 0; $i -lt $defs.Count; $i++) {
        $def = $defs[$i]
        $tile = New-BentoFact $def.Tone $def.Kicker $def.Go
        [Windows.Controls.Grid]::SetColumn($tile, 2 + ($i % 2))
        [Windows.Controls.Grid]::SetRow($tile, [Math]::Floor($i / 2))
        [void]$board.Children.Add($tile)
        $script:BentoBoostFacts[$def.Key] = $tile
    }
    Set-BentoBoostLook ([bool]$script:BoostOn) -Instant
    Update-BentoBoostFacts
}

$bentoBoostHeroXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="24" BorderThickness="1" Padding="24,20,24,18">
    <Border.Background>
        <RadialGradientBrush Center="0.5,0.56" GradientOrigin="0.5,0.56" RadiusX="0.48" RadiusY="0.4">
            <GradientStop Color="#146D43C9" Offset="0"/>
            <GradientStop Color="#F00B0710" Offset="0.7"/>
            <GradientStop Color="#F009060D" Offset="1"/>
        </RadialGradientBrush>
    </Border.Background>
    <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#806D43C9" Offset="0"/>
            <GradientStop Color="#2622172F" Offset="0.38"/>
            <GradientStop Color="#2622172F" Offset="0.7"/>
            <GradientStop Color="#55A8326F" Offset="1"/>
        </LinearGradientBrush>
    </Border.BorderBrush>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid>
            <TextBlock x:Name="BentoBoostKicker" FontFamily="Consolas" FontSize="10.5" Foreground="#8C819F"/>
            <Button x:Name="BentoBoostSetup" Style="{DynamicResource LinkButton}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock x:Name="BentoBoostHead" Grid.Row="1" FontSize="24" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="BentoBoostSub" Grid.Row="2" FontSize="12.5" Foreground="#8C819F" TextWrapping="Wrap" Margin="0,4,0,0"/>
        <Grid x:Name="BentoBoostSpot" Grid.Row="3" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        <Grid x:Name="BentoBoostChipSpot" Grid.Row="4" HorizontalAlignment="Center" MinHeight="30"/>
    </Grid>
</Border>
'@

$bentoFactXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="Auto" Height="Auto" Margin="6">
    <Grid Margin="2,-1,2,-3">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="Kicker" FontSize="12.5" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock x:Name="State" Grid.Column="1" FontSize="11" Foreground="#8C819F" Margin="8,1,0,0"/>
        </Grid>
        <TextBlock x:Name="Value" Grid.Row="1" FontSize="19" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="Note" Grid.Row="3" FontSize="11.5" Foreground="#8C819F" TextWrapping="Wrap" MaxHeight="32" TextTrimming="CharacterEllipsis"/>
    </Grid>
</Button>
'@

function New-BentoFact([string]$Tone, [string]$Kicker, [scriptblock]$OnClick) {
    $tile = [Windows.Markup.XamlReader]::Parse($bentoFactXaml)
    $tile.Style = $window.FindResource('TileButton')
    $tile.Width = [double]::NaN
    $tile.Height = [double]::NaN
    $tile.Margin = New-Object Windows.Thickness 6
    Set-BentoTone $tile $Tone
    $tile.FindName('Kicker').Text = T $Kicker
    $tile.FindName('Kicker').Foreground = New-SolidBrush $script:BentoTones[$Tone].C
    $tile.Tag = $OnClick
    $tile.Add_Click({ try { & $this.Tag } catch { Write-AppError $_ } })
    $tile
}

function Set-BentoFact([string]$Key, [string]$Value, [string]$Note, [string]$State, [string]$StateColor = '#8C819F') {
    $tile = $script:BentoBoostFacts[$Key]
    if (-not $tile) { return }
    $tile.FindName('Value').Text = T $Value
    $tile.FindName('Note').Text = T $Note
    $tile.FindName('State').Text = T $State
    $tile.FindName('State').Foreground = New-SolidBrush $StateColor
}

# Name des aktiven Energieplans (einmal je Seitenbesuch gelesen)
# powercfg ist ein eigener Prozess und hielt jeden Wechsel auf die Boost-Seite an: die Antwort gilt 30 Sekunden
# (schaltet sich der Boost ein oder aus, fragt Update-BentoBoostFacts sofort neu, denn dabei wechselt der Plan)
function Get-BentoPowerPlan {
    if ($script:BentoPlanCache -and ([DateTime]::UtcNow - $script:BentoPlanAt).TotalSeconds -lt 30) { return $script:BentoPlanCache }
    $name = 'Windows-Vorgabe'
    try {
        $line = "$(& powercfg.exe /getactivescheme 2>$null)"
        if ($line -match '\((.+)\)\s*$') { $name = $Matches[1] }
    }
    catch { }
    $script:BentoPlanCache = $name; $script:BentoPlanAt = [DateTime]::UtcNow
    $name
}

# Füllt die sechs Kacheln aus dem Zustand des Boosts und den Einstellungen unter "Einrichten"
function Update-BentoBoostFacts {
    if (-not $script:BentoBoostFacts) { return }
    $good = '#8FF0BE'
    $statePath = Join-Path $script:OutDir 'Spiel-Beschleunigung.json'
    $on = Test-Path -LiteralPath $statePath
    $state = $null
    if ($on) { try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { } }
    $plan = $script:Settings.Boost
    if ($on -ne $script:BentoPlanOn) { $script:BentoPlanCache = $null; $script:BentoPlanOn = $on }
    $ui.BentoBoostHead.Text = T $(if ($on) { 'Volle Leistung fürs Spiel' } else { 'Derzeit ausgeschaltet' })
    $ui.BentoBoostSub.Text = if ($on) { $ui.BoostInfo.Text } else { T 'Schafft vor dem Spielen Platz: Energieplan, entbehrliche Dienste und speicherhungrige Programme.' }

    $script:BentoPlanName = Get-BentoPowerPlan
    if ($on -and $state.PowerPlan) { Set-BentoFact 'Plan' $script:BentoPlanName 'wird beim Ausschalten zurückgestellt' 'umgestellt' $good }
    elseif ($plan.PowerPlan) { Set-BentoFact 'Plan' $script:BentoPlanName 'wird beim Einschalten umgestellt' 'bereit' }
    else { Set-BentoFact 'Plan' $script:BentoPlanName 'bleibt, wie er ist' 'aus' }

    if ($on -and $state.FreeBefore -and $state.FreeAfter) {
        $gain = ([double]$state.FreeAfter - [double]$state.FreeBefore) / 1GB
        Set-BentoFact 'Ram' $ui.RamFree.Text ('vorher {0:N1} GB · {1:N1} GB freigemacht' -f ([double]$state.FreeBefore / 1GB), $gain) ('+{0:N1} GB' -f $gain) $good
    }
    else { Set-BentoFact 'Ram' $ui.RamFree.Text $(if ($script:BentoRamTotal) { 'von {0:N0} GB' -f $script:BentoRamTotal } else { '' }) 'live' }

    if ($on) {
        $count = @($state.Services | Where-Object { $_ }).Count
        Set-BentoFact 'Services' $(if ($count -eq 1) { '1 angehalten' } else { "$count angehalten" }) 'laufen nach dem Ausschalten wieder' 'angehalten' $good
        $closed = @($state.ClosedApps | Where-Object { $_ })
        Set-BentoFact 'Apps' $(if ($closed.Count -eq 1) { '1 geschlossen' } else { "$($closed.Count) geschlossen" }) $(if ($closed.Count) { ($closed | Select-Object -First 3) -join ', ' } else { 'nichts geschlossen' }) 'beendet' $good
    }
    else {
        $count = @($plan.Services | Where-Object { $_ }).Count
        Set-BentoFact 'Services' $(if ($null -eq $plan.Services) { 'nach Vorgabe' } elseif ($count -eq 1) { '1 ausgewählt' } else { "$count ausgewählt" }) 'werden beim Einschalten angehalten' 'bereit'
        $apps = @($plan.Apps | Where-Object { $_ })
        Set-BentoFact 'Apps' $(if ($apps.Count -eq 1) { '1 ausgewählt' } else { "$($apps.Count) ausgewählt" }) $(if ($apps.Count) { ($apps | Select-Object -First 3) -join ', ' } else { 'unter Einrichten auswählen' }) 'bereit'
    }

    $games = @($script:Settings.BoostGames | Where-Object { $_ })
    Set-BentoFact 'Games' $(if ($games.Count -eq 1) { '1 Spiel' } else { "$($games.Count) Spiele" }) $(if ($games.Count) { ($games | Select-Object -First 4) -join ', ' } else { 'Boost startet beim Spielen von selbst' }) 'Liste' '#F6C989'

    $check = $script:CardState.GameCheck
    if ($check -and $check.Text) {
        $tone = switch ($check.Tone) { 'good' { $good } 'warn' { '#F6C989' } default { '#F08A9C' } }
        Set-BentoFact 'Check' ("$($check.Text) / 100") $ui.HomeGameText.Text $(switch ($check.Tone) { 'good' { 'gut' } 'warn' { 'Tipps' } default { 'prüfen' } }) $tone
    }
    else { Set-BentoFact 'Check' 'noch offen' 'Bildwiederholrate, Energieplan, Spielmodus und mehr' 'starten' }
}

$bentoBoostXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Width="236" Height="236">
    <Ellipse x:Name="BentoBoostGlow" Width="230" Height="230" Opacity="0.35" IsHitTestVisible="False">
        <Ellipse.Fill>
            <RadialGradientBrush>
                <GradientStop Color="#556D43C9" Offset="0.45"/>
                <GradientStop Color="#006D43C9" Offset="1"/>
            </RadialGradientBrush>
        </Ellipse.Fill>
    </Ellipse>
    <Grid x:Name="BentoBoostWaves" IsHitTestVisible="False"/>
    <Ellipse Width="210" Height="210" Stroke="#1C1229" StrokeThickness="10"/>
    <Ellipse x:Name="BentoBoostArc" Width="210" Height="210" StrokeThickness="10" StrokeDashArray="20.42 20.42" StrokeDashOffset="20.42" StrokeDashCap="Flat" RenderTransformOrigin="0.5,0.5">
        <Ellipse.Stroke>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#8C6BD6" Offset="0"/>
                <GradientStop Color="#C0608F" Offset="1"/>
            </LinearGradientBrush>
        </Ellipse.Stroke>
        <Ellipse.RenderTransform>
            <RotateTransform Angle="-90"/>
        </Ellipse.RenderTransform>
    </Ellipse>
    <Grid x:Name="BentoBoostDisc" Width="156" Height="156" Cursor="Hand" RenderTransformOrigin="0.5,0.5">
        <Grid.RenderTransform>
            <ScaleTransform/>
        </Grid.RenderTransform>
        <Ellipse Stroke="#2F2147" StrokeThickness="1">
            <Ellipse.Fill>
                <RadialGradientBrush GradientOrigin="0.35,0.3">
                    <GradientStop Color="#1F1331" Offset="0"/>
                    <GradientStop Color="#0A0610" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
            <TextBlock x:Name="BentoBoostBolt" Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="22" Foreground="#8C6BD6" HorizontalAlignment="Center"/>
            <TextBlock x:Name="BentoBoostBig" Text="AUS" FontSize="26" FontWeight="SemiBold" Foreground="White" HorizontalAlignment="Center" Margin="0,2,0,0"/>
            <TextBlock x:Name="BentoBoostSmall" Text="Tippen zum Starten" FontSize="11" Foreground="#8C819F" HorizontalAlignment="Center"/>
        </StackPanel>
    </Grid>
</Grid>
'@

# Länge des Rings in Strichstärken: Umfang der Mittellinie (Durchmesser 200) geteilt durch 10
$script:BentoArcLength = [Math]::PI * 200 / 10

function Set-BentoBoostLook([bool]$On, [switch]$Instant) {
    if (-not $ui.BentoBoostArc) { return }
    $script:BentoBoostShown = $On
    $length = $script:BentoArcLength
    $ui.BentoBoostArc.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@($length, $length))
    $ui.BentoBoostBig.Text = T $(if ($On) { 'AN' } else { 'AUS' })
    $ui.BentoBoostSmall.Text = T $(if ($On) { 'Tippen zum Beenden' } else { 'Tippen zum Starten' })
    $ui.BentoBoostBolt.Foreground = New-SolidBrush $(if ($On) { '#FFFFFF' } else { '#8C6BD6' })
    if ($Instant -or -not $script:Settings.Animations) {
        $ui.BentoBoostArc.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $null)
        $ui.BentoBoostArc.StrokeDashOffset = if ($On) { 0 } else { $length }
        $ui.BentoBoostGlow.Opacity = if ($On) { 0.85 } else { 0.35 }
        return
    }
    if ($On) {
        # Einschalten: der Knopf federt, der Ring füllt sich, Lichtwellen laufen nach außen
        Start-BentoBoostSteps
        $ui.BentoBoostArc.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-DoubleAnim -From $length -To 0 -Ms 2300 -Ease $script:EaseOut))
        Start-Fade $ui.BentoBoostGlow 0.85 900
        Start-Scale $ui.BentoBoostDisc 1 650 0 0.88 $script:EaseBack
        $ui.BentoBoostWaves.Children.Clear()
        for ($i = 0; $i -lt 3; $i++) {
            $wave = New-Object Windows.Shapes.Ellipse
            $wave.Width = 156; $wave.Height = 156
            $wave.StrokeThickness = 2
            $wave.Stroke = New-SolidBrush $(if ($i -eq 2) { '#C0608F' } else { '#8C6BD6' })
            $wave.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $wave.RenderTransform = New-Object Windows.Media.ScaleTransform
            $wave.Opacity = 0
            [void]$ui.BentoBoostWaves.Children.Add($wave)
            $delay = 220 * $i
            foreach ($axis in $P.ScaleX, $P.ScaleY) { $wave.RenderTransform.BeginAnimation($axis, (New-DoubleAnim -From 0.8 -To 1.9 -Ms 1500 -Delay $delay -Ease $script:EaseOut)) }
            $wave.BeginAnimation($P.Opacity, (New-DoubleAnim -From 0.95 -To 0 -Ms 1500 -Delay $delay))
        }
    }
    else {
        # Ausschalten: der Ring läuft rückwärts leer
        $ui.BentoBoostArc.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-DoubleAnim -To $length -Ms 1000 -Ease $script:EaseCubicIn))
        Start-Fade $ui.BentoBoostGlow 0.35 900
    }
}

# --- Scan als Ereignis --------------------------------------------------------------
# Während des Scans laufen Lichtwellen aus dem SCAN-Knopf. Am Ende ein Lichtstoß. Alles als durchgehende Animation (kein Takt in Schritten).

$script:BentoWaves = @()
function Start-BentoScanFx {
    if (-not $script:Settings.Animations) { return }
    Stop-BentoScanFx
    $colors = '#8C6BD6', '#8C6BD6', '#C0608F'
    for ($i = 0; $i -lt 3; $i++) {
        $wave = New-Object Windows.Shapes.Ellipse
        $wave.Width = 198; $wave.Height = 198
        $wave.StrokeThickness = 1.6
        $wave.Stroke = New-SolidBrush $colors[$i]
        $wave.IsHitTestVisible = $false
        $wave.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $scale = New-Object Windows.Media.ScaleTransform
        $wave.RenderTransform = $scale
        $wave.Opacity = 0
        [void]$ui.Orb.Children.Insert(1, $wave)
        $begin = [TimeSpan]::FromMilliseconds(700 * $i)
        foreach ($axis in $P.ScaleX, $P.ScaleY) {
            $grow = New-DoubleAnim -From 1 -To 1.75 -Ms 2100 -Forever
            $grow.BeginTime = $begin
            $scale.BeginAnimation($axis, $grow)
        }
        $fade = New-DoubleAnim -From 0.85 -To 0 -Ms 2100 -Forever
        $fade.BeginTime = $begin
        $wave.BeginAnimation($P.Opacity, $fade)
        $script:BentoWaves += $wave
    }
    # die Kacheln leuchten beim Scan nicht mehr nacheinander auf – das wirkte unruhig (25.10.2026)
}

function Stop-BentoScanFx {
    foreach ($wave in $script:BentoWaves) {
        $wave.BeginAnimation($P.Opacity, $null)
        $wave.RenderTransform.BeginAnimation($P.ScaleX, $null)
        $wave.RenderTransform.BeginAnimation($P.ScaleY, $null)
        $ui.Orb.Children.Remove($wave)
    }
    $script:BentoWaves = @()
}

# Kurzes Aufleuchten einer Kachel: heller Rand, leichtes Anheben
function Show-BentoPulse($Tile, [string]$Color) {
    if (-not $Tile) { return }
    $edge = $Tile.BorderBrush
    $Tile.BorderBrush = New-SolidBrush $Color
    Invoke-Later 520 { param($t) $t[0].BorderBrush = $t[1] } @($Tile, $edge)
    if ($Tile.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
        $Tile.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $Tile.RenderTransform = New-Object Windows.Media.ScaleTransform
    }
    Start-Scale $Tile 1.025 180
    Invoke-Later 200 { param($t) Start-Scale $t 1 420 } $Tile
}

# Lichtstoß am Ende: zwei schnelle Wellen, die Treiber-Kachel leuchtet in Rosa
function Show-BentoScanBurst {
    if (-not $script:Settings.Animations) { return }
    for ($i = 0; $i -lt 2; $i++) {
        $wave = New-Object Windows.Shapes.Ellipse
        $wave.Width = 198; $wave.Height = 198
        $wave.StrokeThickness = 2.2
        $wave.Stroke = New-SolidBrush $(if ($i) { '#C0608F' } else { '#B19FE0' })
        $wave.IsHitTestVisible = $false
        $wave.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $wave.RenderTransform = New-Object Windows.Media.ScaleTransform
        [void]$ui.Orb.Children.Insert(1, $wave)
        $delay = 250 * $i
        foreach ($axis in $P.ScaleX, $P.ScaleY) { $wave.RenderTransform.BeginAnimation($axis, (New-DoubleAnim -From 1 -To 1.9 -Ms 1100 -Delay $delay -Ease $script:EaseOut)) }
        $wave.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0 -Ms 1100 -Delay $delay))
        Invoke-Later (1200 + $delay) { param($w) $ui.Orb.Children.Remove($w) } $wave
    }
    Show-BentoPulse $ui.ChipDrivers '#C0608F'
}

$script:BentoStartScan = ${function:Start-Scan}
$script:BentoStopScan = ${function:Stop-Scan}
$script:BentoCompleteScan = ${function:Complete-Scan}
function Start-Scan { & $script:BentoStartScan; if ($script:Busy -eq 'scan') { Start-BentoScanFx } }
function Stop-Scan { & $script:BentoStopScan; Stop-BentoScanFx }
function Complete-Scan($Message) {
    Stop-BentoScanFx
    & $script:BentoCompleteScan $Message
    if (-not $Message.Error) { Show-BentoScanBurst }
}

# --- Hardware-Detailseiten (Entwurf Q7–Q14) ----------------------------------------
# Ein Klick auf eine Hardware-Karte öffnet ihre Detailseite als zweite Ebene: links groß Modell, Wert und Verlauf
# (Kurve, Laufwerke, Riegel, 30 Tage oder Prüfliste), rechts vier Faktenkacheln, unten "Was du tun kannst" und
# "Kurz erklärt". Die Seite liest beim Öffnen die passende Abfrage neu ein; das ausführliche Fenster von früher
# bleibt über "Alle Einzelheiten" erreichbar.

$script:BentoData = @{}
$script:BentoDetailIndex = -1
$script:BentoDetailNames = 'Sensoren', 'Stabilitätstest', 'Laufwerke', 'Arbeitsspeicher', 'Abstürze', 'Bildschirm', 'Bericht & Diagnose', 'BIOS'
$script:BentoMono = 'Cascadia Mono, Consolas'

$bentoDetailXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Margin="-6" Visibility="Collapsed">
    <Grid.ColumnDefinitions>
        <ColumnDefinition/>
        <ColumnDefinition/>
        <ColumnDefinition/>
        <ColumnDefinition/>
    </Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
        <RowDefinition/>
        <RowDefinition/>
        <RowDefinition Height="0.78*"/>
    </Grid.RowDefinitions>
    <Border x:Name="Hero" Grid.ColumnSpan="2" Grid.RowSpan="2" Margin="6" CornerRadius="24" BorderThickness="1" Padding="22,18,22,14">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid>
                <TextBlock x:Name="Kicker" FontFamily="Consolas" FontSize="10.5" Foreground="#8C819F" VerticalAlignment="Center"/>
                <Border x:Name="StateBox" CornerRadius="10" Padding="9,3" HorizontalAlignment="Right">
                    <StackPanel Orientation="Horizontal">
                        <Ellipse x:Name="StateDot" Width="6" Height="6" VerticalAlignment="Center" Margin="0,1,6,0"/>
                        <TextBlock x:Name="State" FontSize="11"/>
                    </StackPanel>
                </Border>
            </Grid>
            <TextBlock x:Name="Model" Grid.Row="1" FontSize="19" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,8,0,0" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="Sub" Grid.Row="2" FontSize="12" Foreground="#8C819F" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
            <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0">
                <TextBlock x:Name="Big" FontSize="48" FontWeight="SemiBold" Foreground="#FFFFFF" VerticalAlignment="Bottom"/>
                <TextBlock x:Name="Unit" FontSize="13.5" Foreground="#B3A8C4" VerticalAlignment="Bottom" Margin="9,0,0,9"/>
            </StackPanel>
            <Grid x:Name="Chart" Grid.Row="4" Margin="0,10,0,0"/>
            <Grid Grid.Row="5" Margin="0,6,0,0">
                <TextBlock x:Name="AxisL" FontFamily="Consolas" FontSize="10" Foreground="#4A3D5E"/>
                <TextBlock x:Name="AxisR" FontFamily="Consolas" FontSize="10" Foreground="#4A3D5E" HorizontalAlignment="Right"/>
            </Grid>
        </Grid>
    </Border>
    <UniformGrid x:Name="Facts" Grid.Column="2" Grid.ColumnSpan="2" Grid.RowSpan="2" Columns="2" Rows="2"/>
    <Border x:Name="Actions" Grid.Row="2" Grid.ColumnSpan="2" Margin="6" CornerRadius="22" Background="#0B0710" BorderBrush="#22172F" BorderThickness="1" Padding="18,14,18,16">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="ActionsTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#B3A8C4"/>
            <UniformGrid x:Name="ActionRow" Grid.Row="1" Rows="1" VerticalAlignment="Bottom" Margin="-4,0,-4,0"/>
        </Grid>
    </Border>
    <Border x:Name="Tip" Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="2" Margin="6" CornerRadius="22" Background="#0B0710" BorderThickness="1" Padding="18,14">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="TipIcon" Width="38" Height="38" CornerRadius="12" BorderThickness="1" VerticalAlignment="Top">
                <TextBlock x:Name="TipGlyph" Text="&#xEA80;" FontFamily="Segoe MDL2 Assets" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel Grid.Column="1" Margin="14,0,0,0">
                <TextBlock x:Name="TipTitle" FontSize="12.5" FontWeight="SemiBold"/>
                <TextBlock x:Name="TipText" FontSize="12.5" Foreground="#B3A8C4" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="19"/>
            </StackPanel>
        </Grid>
    </Border>
</Grid>
'@

$bentoDetailFactXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="6" CornerRadius="22" BorderThickness="1" Padding="16,14,16,12">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="Title" FontSize="12.5" FontWeight="SemiBold" TextWrapping="Wrap"/>
            <TextBlock x:Name="State" Grid.Column="1" FontSize="11" Margin="8,1,0,0"/>
        </Grid>
        <TextBlock x:Name="Value" Grid.Row="1" FontSize="22" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
        <Grid x:Name="BarBox" Grid.Row="2" Height="5" Margin="0,8,0,0">
            <Border CornerRadius="2.5" Background="#0DFFFFFF"/>
            <Border x:Name="Bar" CornerRadius="2.5" HorizontalAlignment="Left" Width="0"/>
        </Grid>
        <TextBlock x:Name="Note" Grid.Row="3" FontSize="11.5" Foreground="#8C819F" TextWrapping="Wrap" VerticalAlignment="Bottom" TextTrimming="CharacterEllipsis"/>
    </Grid>
</Border>
'@

function New-BentoText([string]$Text, [double]$Size, [string]$Color, [string]$Weight = 'Normal') {
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $Text; $block.FontSize = $Size; $block.FontWeight = $Weight
    $block.Foreground = New-SolidBrush $Color
    $block.VerticalAlignment = 'Center'
    $block
}

function Set-BentoDetailShell {
    $detail = [Windows.Markup.XamlReader]::Parse($bentoDetailXaml)
    [Windows.Controls.Grid]::SetRowSpan($detail, 9)
    [Windows.Controls.Grid]::SetColumnSpan($detail, 9)
    [void]$ui.PageHardware.Children.Add($detail)
    $ui.BentoDetail = $detail
    $detail.FindName('ActionsTitle').Text = T 'Was du tun kannst'
    $detail.FindName('TipTitle').Text = T 'Kurz erklärt'
    # Karten öffnen die Detailseite statt des Fensters
    $i = 0
    foreach ($card in $ui.HardwareGrid.Children) {
        $card.Tag = [scriptblock]::Create("Show-BentoDetail $i")
        $i++
    }
}

# Öffnet die Detailseite einer Hardware-Karte
function Show-BentoDetail([int]$Index) {
    if ($script:Sheet -or $script:Dialog) { return }
    $script:BentoDetailIndex = $Index
    $script:BentoSub = T $script:BentoDetailNames[$Index]
    $script:BentoSubPage = 'Hardware'
    $script:BentoSubHide = { param($quiet) Hide-BentoDetail $quiet }
    $page = $ui.PageHardware
    $script:BentoHwHidden = @($page.Children | Where-Object { $_ -ne $ui.BentoDetail -and $_.Visibility -eq 'Visible' })
    foreach ($part in $script:BentoHwHidden) { $part.Visibility = 'Collapsed' }
    $ui.BentoDetail.Visibility = 'Visible'
    Start-Fade $ui.BentoDetail 1 260 0 0
    Update-BentoDetail -First
    Start-BentoDetailQuery $Index
    Update-BentoCrumbs
}

function Hide-BentoDetail([bool]$Quiet) {
    Stop-BentoDetailLive
    $script:BentoDetailIndex = -1
    $ui.BentoDetail.Visibility = 'Collapsed'
    foreach ($part in @($script:BentoHwHidden)) { $part.Visibility = 'Visible' }
    $script:BentoHwHidden = @()
    if (-not $Quiet) { Update-HardwareBadges; Show-HardwareCards }
}

# Liest die Abfrage der Seite neu ein; das Ergebnis zählt wie im Fenster auch für Karte und Bericht
function Start-BentoDetailQuery([int]$Index) {
    switch ($Index) {
        # die Temperatur des Prozessors lädt sonst erst das Fenster Sensoren bzw. Stabilitätstest
        0 { Initialize-CpuTemp; Start-BentoDetailLive }
        1 { Initialize-CpuTemp }
        2 { Start-Query 'Drives' { param($r) $script:BentoData.Drives = $r; Set-CardState 'Drives' (Get-DriveCardState $r); Update-BentoDetail } }
        3 { Start-Query 'Memory' { param($r) $script:BentoData.Memory = $r; Set-CardState 'Memory' (Get-MemoryCardState $r); Update-BentoDetail } }
        4 { Start-Query 'Crashes' { param($r) $script:BentoData.Crashes = $r; $script:LastCrashes = $r; Set-CardState 'Crashes' (Get-CrashCardState $r); Update-BentoDetail } }
        5 { Start-Query 'Displays' { param($r) $script:BentoData.Displays = @($r.Displays); Set-DisplayCardState @($r.Displays); Update-BentoDetail } }
        7 {
            Start-Query 'Bios' {
                param($r)
                $date = $null
                try { $date = [datetime]::ParseExact("$($r.Date)", 'yyyy-MM-dd', $null) } catch { }
                $r.Released = $date
                $script:BentoData.Bios = $r
                if ($date) {
                    $months = (Get-Date).Year * 12 + (Get-Date).Month - ($date.Year * 12 + $date.Month)
                    $short = if ($months -lt 12) { $(if ($months -le 1) { 'neu' } else { "$months Monate alt" }) } else { $(if ($months -lt 24) { '1 Jahr alt' } else { "$([Math]::Floor($months / 12)) Jahre alt" }) }
                    Set-CardState 'Bios' @{ Text = $short; Tone = $(if (((Get-Date) - $date).TotalDays -gt 3 * 365) { 'warn' } else { 'good' }); Detail = "$($r.Version) vom $($date.ToString('dd.MM.yyyy'))" }
                }
                Update-BentoDetail
            }
        }
    }
}

# Live-Werte für die Sensoren-Seite: eigene Messung, solange die Seite offen ist
$script:BentoLive = @{ Gpu = (New-Object 'System.Collections.Generic.List[double]'); Stamp = -1; Own = $false; Timer = $null }
function Start-BentoDetailLive {
    if (-not $script:SensorRun) { $script:SensorTiles = @{}; Start-Sensors; $script:BentoLive.Own = $true }
    if (-not $script:BentoLive.Timer) {
        $script:BentoLive.Timer = New-Object Windows.Threading.DispatcherTimer
        $script:BentoLive.Timer.Interval = [TimeSpan]::FromMilliseconds(1000)
        $script:BentoLive.Timer.Add_Tick({
                try {
                    if ($script:BentoDetailIndex -ne 0) { return }
                    $values = $sync.Sensors
                    if (-not $values -or $values.Stamp -eq $script:BentoLive.Stamp) { return }
                    $script:BentoLive.Stamp = $values.Stamp
                    if ($null -ne $values.GpuTemp) { $script:BentoLive.Gpu.Add([double]$values.GpuTemp); while ($script:BentoLive.Gpu.Count -gt 60) { $script:BentoLive.Gpu.RemoveAt(0) } }
                    Update-BentoDetail
                }
                catch { Write-AppError $_ }
            })
    }
    $script:BentoLive.Timer.Start()
}
function Stop-BentoDetailLive {
    if ($script:BentoLive.Timer) { $script:BentoLive.Timer.Stop() }
    if ($script:BentoLive.Own -and $script:SensorRun -and -not $script:Sheet) { Stop-Sensors }
    $script:BentoLive.Own = $false
}

# Inhalt einer Detailseite aus dem, was gerade bekannt ist
function Get-BentoDetailModel([int]$Index) {
    $good = '#8FF0BE'; $warn = '#F6C989'; $bad = '#F08A9C'
    $m = @{ Tone = 'Lila'; Kicker = ''; State = ''; StateColor = '#B19FE0'; Model = ''; Sub = ''; Big = '–'; Unit = ''; Chart = $null; AxisL = ''; AxisR = ''; Facts = @(); Actions = @(); Tip = '' }
    $fact = { param($t, $v, $n, $tone, $bar, $s, $sc) @{ T = $t; V = $v; N = $n; Tone = $tone; Bar = $bar; S = $s; SC = $sc } }
    $toneColor = { param($t) switch ($t) { 'good' { $good } 'warn' { $warn } 'bad' { $bad } default { '#B19FE0' } } }
    switch ($Index) {
        0 {
            $v = $sync.Sensors
            $m.Tone = 'Lila'; $m.Kicker = 'LEISTUNG · SENSOREN'; $m.State = 'live'
            $m.Model = if ($v -and $v.GpuName) { "$($v.GpuName)" } else { T 'Grafikkarte und Prozessor' }
            $m.Sub = T 'Temperaturen, Auslastung und Lüfter in Echtzeit'
            if ($v -and $null -ne $v.GpuTemp) { $m.Big = '{0:N0}' -f $v.GpuTemp; $m.Unit = T '°C Grafikkarte' }
            elseif ($v -and $null -ne $v.CpuClock) { $m.Big = '{0:N2}' -f $v.CpuClock; $m.Unit = T 'GHz Prozessor' }
            $m.Chart = @{ Kind = 'line'; Values = @($script:BentoLive.Gpu); Color = '#8C6BD6' }
            $m.AxisL = T 'vor einer Minute'; $m.AxisR = T 'jetzt'
            $m.Facts = @(
                (& $fact 'Grafikkarte' $(if ($v -and $null -ne $v.GpuLoad) { '{0:N0} %' -f $v.GpuLoad } else { '–' }) $(if ($v -and $null -ne $v.GpuFan) { T ('Lüfter {0:N0} %' -f $v.GpuFan) } else { T 'Auslastung' }) 'Lila' $(if ($v) { [double]$v.GpuLoad / 100 } else { 0 }) '' ''),
                (& $fact 'Prozessor' $(if ($v -and $null -ne $v.CpuLoad) { '{0:N0} %' -f $v.CpuLoad } else { '–' }) $(if ($v -and $null -ne $v.CpuClock) { '{0:N2} GHz' -f $v.CpuClock } else { T 'Auslastung' }) 'Indigo' $(if ($v) { [double]$v.CpuLoad / 100 } else { 0 }) '' ''),
                (& $fact 'Prozessor-Temperatur' $(if ($v -and $null -ne $v.CpuTemp) { '{0:N0} °C' -f $v.CpuTemp } else { '–' }) $(if ($v -and $null -ne $v.CpuTemp) { T 'kühl genug unter 85 °C' } else { T 'unter Alle Messwerte freischalten' }) 'Beere' $(if ($v -and $null -ne $v.CpuTemp) { [double]$v.CpuTemp / 100 } else { 0 }) '' ''),
                (& $fact 'Arbeitsspeicher' $(if ($v -and $null -ne $v.Ram) { '{0:N0} %' -f $v.Ram } else { '–' }) (T 'belegt') 'Rose' $(if ($v) { [double]$v.Ram / 100 } else { 0 }) '' '')
            )
            $m.Actions = @(@{ L = 'Alle Messwerte'; S = 'alle Sensoren'; Do = { Open-SensorSheet } }, @{ L = 'Spielsitzungen'; S = 'beim Spielen'; Do = { Open-SensorSheet 1 } }, @{ L = 'Stabilitätstest'; S = 'Volllast prüfen'; Do = { Close-BentoSub -Quiet; Show-BentoDetail 1 } })
            $m.Tip = T 'Im Spiel sind bei der Grafikkarte bis etwa 80 °C normal, beim Prozessor bis etwa 85 °C. Ohne Last sollten beide deutlich kühler sein.'
        }
        1 {
            $s = $script:StressResult
            $m.Tone = 'Gruen'; $m.Kicker = 'LEISTUNG · STABILITÄTSTEST'
            $m.Model = T 'Volllast für Prozessor und Grafikkarte'
            if ($s -and $s.Title) {
                $m.State = ("$($s.Title)" -split ' – ')[0]; $m.StateColor = & $toneColor "$($s.Tone)"
                $m.Sub = "$($s.Time)"
                $top = [Math]::Max([double]$s.MaxGpuTemp, [double]$s.MaxCpuTemp)
                if ($top -gt 0) { $m.Big = '{0:N0}' -f $top; $m.Unit = T '°C höchste Temperatur' }
                $m.Chart = @{ Kind = 'meters'; Rows = @(@{ L = 'Prozessor'; V = [double]$s.MaxCpuTemp; Max = 95 }, @{ L = 'Grafikkarte'; V = [double]$s.MaxGpuTemp; Max = 90 }) }
                $clock = if ("$($s.Text)" -match 'Takt bis ([\d.,]+) GHz') { "$($Matches[1]) GHz" } else { '–' }
                $samples = if ("$($s.Text)" -match '([\d.]+) Rechenproben') { $Matches[1] } else { '–' }
                $m.Facts = @(
                    (& $fact 'Prozessor max.' $(if ($s.MaxCpuTemp -gt 0) { '{0:N0} °C' -f $s.MaxCpuTemp } else { '–' }) (T 'auffällig ab 95 °C') 'Lila' ([double]$s.MaxCpuTemp / 100) '' ''),
                    (& $fact 'Grafikkarte max.' $(if ($s.MaxGpuTemp -gt 0) { '{0:N0} °C' -f $s.MaxGpuTemp } else { '–' }) (T 'auffällig ab 85 °C') 'Indigo' ([double]$s.MaxGpuTemp / 100) '' ''),
                    (& $fact 'Rechenproben' $samples (T 'jede Probe wird bitgenau geprüft') 'Gruen' 1 $(if ($s.Tone -eq 'good') { 'ohne Fehler' } else { '' }) $good),
                    (& $fact 'Takt gehalten' $clock (T 'höchster Takt unter Last') 'Beere' 0.9 '' '')
                )
            }
            else {
                $m.State = T 'noch nicht gelaufen'; $m.StateColor = '#8C819F'
                $m.Sub = T 'Lastet den PC voll aus und misst, ob er stabil und kühl genug bleibt.'
                $m.Chart = @{ Kind = 'note'; Text = T 'Starte den Test – nach einer Minute steht hier, wie warm Prozessor und Grafikkarte unter Volllast werden.' }
                $m.Facts = @(
                    (& $fact 'Prozessor' '–' (T 'Volllast auf allen Kernen') 'Lila' 0 '' ''),
                    (& $fact 'Grafikkarte' '–' (T 'Volllast mit Shadern') 'Indigo' 0 '' ''),
                    (& $fact 'Fehler' '–' (T 'jede Rechenprobe wird geprüft') 'Gruen' 0 '' ''),
                    (& $fact 'Dauer' (T '1–30 Min.') (T 'für Hitze lieber 15 Minuten') 'Beere' 0 '' '')
                )
            }
            $m.Actions = @(@{ L = 'Test öffnen'; S = 'Dauer wählen'; Do = { Open-StressSheet } }, @{ L = 'Sensoren'; S = 'live ansehen'; Do = { Close-BentoSub -Quiet; Show-BentoDetail 0 } }, @{ L = 'Benchmark'; S = 'in Punkten'; Do = { Open-BenchSheet } })
            $m.Tip = T 'Der Test rechnet bekannte Aufgaben und prüft jedes Ergebnis. Rechnet der PC unter Hitze falsch oder stürzt ab, zeigt der Test das, bevor es im Spiel passiert.'
        }
        2 {
            $d = $script:BentoData.Drives; $c = $script:CardState.Drives
            $m.Tone = 'Bernst'; $m.Kicker = 'SPEICHER · LAUFWERKE'
            if ($c) { $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)" } else { $m.State = T 'wird gelesen'; $m.StateColor = '#8C819F' }
            $disks = @($d.Disks | Where-Object { $_ }); $vols = @($d.Volumes | Where-Object { $_ -and $_.Size -gt 0 })
            $m.Model = if ($disks.Count -eq 1) { "$($disks[0].Name)" } elseif ($disks.Count) { T "$($disks.Count) Laufwerke" } else { T 'Laufwerke' }
            $m.Sub = T 'Zustand, Belegung und Störungen'
            if ($vols.Count) {
                $free = [double]($vols | ForEach-Object { $_.Free } | Measure-Object -Sum).Sum
                $m.Big = Format-DriveSize $free; $m.Unit = T 'frei'
                $m.Chart = @{ Kind = 'volumes'; Rows = @($vols | Select-Object -First 5 | ForEach-Object { @{ L = "$($_.Letter):"; F = 1.0 - $_.Free / $_.Size; T = "$(Format-DriveSize $_.Free) frei" } }) }
            }
            else { $m.Chart = @{ Kind = 'note'; Text = T 'Lese die Laufwerke …' } }
            $m.Facts = @()
            $tones = 'Bernst', 'Lila', 'Indigo', 'Beere'
            $k = 0
            foreach ($disk in @($disks | Select-Object -First 4)) {
                $ok = "$($disk.Health)" -eq 'Healthy' -and -not ($disk.Faults -gt 0)
                $note = (@($(if ($disk.Temperature) { "$($disk.Temperature) °C" }), $(if ($disk.Faults -gt 0) { T "$($disk.Faults) Störungen in 30 Tagen" } else { T 'keine Störungen' })) | Where-Object { $_ }) -join ' · '
                $m.Facts += & $fact (@("$($disk.Letters)" -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { "$($_.TrimEnd(':')):" }) -join ' ') "$($disk.Name)" $note $tones[$k] 0 $(if ($ok) { 'gesund' } else { 'ansehen' }) $(if ($ok) { $good } else { $warn })
                $k++
            }
            $m.Actions = @(@{ L = 'Alle Einzelheiten'; S = 'Tempo, Verlauf'; Do = { Open-DriveSheet } }, @{ L = 'Speicherplatz'; S = 'aufräumen'; Do = { Open-Tool 'CleanDisk' } }, @{ L = 'Bericht'; S = 'als ZIP'; Do = { Close-BentoSub -Quiet; Show-BentoDetail 6 } })
            $m.Tip = T 'Störungen sind kurze Aussetzer beim Lesen oder Schreiben. Einzelne sind harmlos; häufen sie sich, zuerst Kabel und Anschluss prüfen und wichtige Daten sichern.'
        }
        3 {
            $d = $script:BentoData.Memory; $c = $script:CardState.Memory
            $m.Tone = 'Beere'; $m.Kicker = 'LEISTUNG · ARBEITSSPEICHER'
            if ($c) { $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)" } else { $m.State = T 'wird gelesen'; $m.StateColor = '#8C819F' }
            $modules = @($d.Modules | Where-Object { $_ })
            if ($d -and $modules.Count) {
                $layout = @(Get-MemoryLayout $d)
                $placement = Get-MemoryPlacement $layout
                $channels = Get-MemoryChannels $modules $layout.Count
                $profile = Get-MemoryProfile $modules
                $size = [double](($modules | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
                $m.Model = (@(('{0:N0} GB' -f ($size / 1GB)), "$($modules[0].Type)") | Where-Object { $_ }) -join ' '
                $m.Sub = (@($(if ($modules.Count -eq 1) { T '1 Riegel' } else { T "$($modules.Count) × $('{0:N0} GB' -f ($modules[0].Bytes / 1GB))" }), $(if ($placement.State -eq 'good') { T 'richtig gesteckt' } elseif ($placement.State -eq 'bad') { T 'falsch gesteckt' })) | Where-Object { $_ }) -join ' · '
                if ($d.Total -gt 0) { $m.Big = '{0:N1}' -f (($d.Total - $d.Free) / 1GB); $m.Unit = T ('GB von {0:N0} GB belegt' -f ($d.Total / 1GB)) }
                $m.Chart = @{ Kind = 'slots'; Layout = $layout; Modules = $modules; Placement = $placement }
                $m.AxisL = if ($d.MaxBytes -gt 0) { T ('{0} Steckplätze · Ausbau bis {1:N0} GB' -f $layout.Count, ($d.MaxBytes / 1GB)) } else { T "$($layout.Count) Steckplätze" }
                $m.AxisR = if ($channels) { T $channels.Name } else { '' }
                $m.Facts = @(
                    (& $fact 'Tempo' $(if ($profile) { '{0:N0} MHz' -f $profile.Now } else { '–' }) $(if ($profile -and $profile.Tone -eq 'Good') { T 'XMP ist an – volles Tempo' } elseif ($profile -and $profile.Rated) { T ('die Riegel können {0:N0} MHz' -f $profile.Rated) } else { T 'laut Windows' }) 'Gruen' 1 $(if ($profile) { T $profile.Badge } else { '' }) $(if ($profile -and $profile.Tone -eq 'Warn') { $warn } else { $good })),
                    (& $fact 'Kanäle' $(if ($channels) { ($channels.Name -replace '-Channel', '') } else { '–' }) $(if ($channels -and $channels.Hint) { T 'auf zwei Kanäle verteilen' } else { T 'Riegel arbeiten zusammen' }) 'Lila' 1 $(if ($channels -and -not $channels.Hint) { 'gut' } else { '' }) $good),
                    (& $fact 'Frei' $(if ($d.Total -gt 0) { '{0:N1} GB' -f ($d.Free / 1GB) } else { '–' }) (T 'jetzt gerade') 'Beere' $(if ($d.Total -gt 0) { $d.Free / $d.Total } else { 0 }) '' ''),
                    (& $fact 'Riegel' "$($modules.Count)" $(if ($modules[0].Maker -or $modules[0].Part) { "$($modules[0].Maker) $($modules[0].Part)".Trim() } else { T 'Hersteller unbekannt' }) 'Rose' ($modules.Count / [Math]::Max(1, $layout.Count)) '' '')
                )
            }
            else {
                $m.Model = T 'Arbeitsspeicher'; $m.Sub = T 'Riegel, Steckplätze und Takt'
                $m.Chart = @{ Kind = 'note'; Text = T 'Lese den Arbeitsspeicher …' }
            }
            $m.Actions = @(@{ L = 'Speicher frei'; S = 'per Boost'; Do = { Show-Page 'Boost' } }, @{ L = 'Speichertest'; S = 'von Windows'; Do = { Open-MemorySheet; Select-SheetTab 1 } }, @{ L = 'Alle Einzelheiten'; S = 'Riegel und Test'; Do = { Open-MemorySheet } })
            $m.Tip = if ($d -and $modules.Count -and (Get-MemoryPlacement @(Get-MemoryLayout $d)).State -eq 'bad') { T 'Die gelb markierten Riegel stecken im falschen Steckplatz. PC ausschalten und wie markiert umstecken – dann laufen sie zusammen und schneller.' } else { T 'Stecken die Riegel in A2 und B2, arbeiten sie zusammen im Dual-Channel. Mit eingeschaltetem XMP laufen sie so schnell, wie sie gebaut sind.' }
        }
        4 {
            $c = $script:CardState.Crashes; $data = if ($script:BentoData.Crashes) { $script:BentoData.Crashes } else { $script:LastCrashes }
            $m.Tone = 'Gruen'; $m.Kicker = 'GESUNDHEIT · ABSTÜRZE'
            if ($c) { $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)" } else { $m.State = T 'wird gelesen'; $m.StateColor = '#8C819F' }
            $days = @($c.Days | ForEach-Object { [int]$_ })
            $quiet = if ($days.Count) { ($days | Measure-Object -Minimum).Minimum } else { 30 }
            $m.Model = if ($days.Count) { T "$quiet Tage ohne Absturz" } else { T '30 Tage ohne Absturz' }
            $m.Sub = if ($c.Detail) { T "$($c.Detail)" } else { T 'Bluescreens, Ausschalten und Aussetzer' }
            $m.Big = "$quiet"; $m.Unit = T 'Tage stabil'
            $m.Chart = @{ Kind = 'days'; Days = $days; Tone = "$($c.Tone)" }
            $m.AxisL = T 'vor 30 Tagen'; $m.AxisR = T 'heute'
            $blue = @($data.Blue | Where-Object { $_ }).Count; $off = @($data.Off | Where-Object { $_ }).Count; $tdr = @($data.Tdr | Where-Object { $_ }).Count; $apps = @($data.Apps | Where-Object { $_ }).Count
            $m.Facts = @(
                (& $fact 'Bluescreens' "$blue" (T 'in 30 Tagen') 'Rose' ([Math]::Min(1, $blue / 5)) $(if ($blue) { '' } else { 'gut' }) $good),
                (& $fact 'Grafik-Aussetzer' "$tdr" (T 'Grafiktreiber kurz ausgesetzt') 'Beere' ([Math]::Min(1, $tdr / 5)) '' ''),
                (& $fact 'App-Abstürze' "$apps" (T 'im Grafiktreiber') 'Bernst' ([Math]::Min(1, $apps / 5)) '' ''),
                (& $fact 'Ausgegangen' "$off" (T 'ohne Herunterfahren') 'Gruen' ([Math]::Min(1, $off / 5)) $(if ($off) { '' } else { 'gut' }) $good)
            )
            $m.Actions = @(@{ L = 'Alle Einzelheiten'; S = 'Ursachen'; Do = { Open-CrashSheet } }, @{ L = 'Treiber prüfen'; S = 'Scan starten'; Do = { Close-BentoSub -Quiet; Show-Page 'Home'; Invoke-Later 450 { Start-Scan } } }, @{ L = 'Arbeitsspeicher'; S = 'Riegel prüfen'; Do = { Close-BentoSub -Quiet; Show-BentoDetail 3 } })
            $finding = @(Get-CrashFindings $data | Select-Object -First 1)
            $m.Tip = if ($finding.Count -and $finding[0].Sub) { T "$($finding[0].Title): $($finding[0].Sub)" } else { T 'Keine Bluescreens und kein plötzliches Ausschalten in den letzten 30 Tagen. Gelegentliche Programmabstürze sind normal.' }
        }
        5 {
            $list = @($script:BentoData.Displays | Where-Object { $_ }); $c = $script:CardState.Displays
            $m.Tone = 'Indigo'; $m.Kicker = 'ANZEIGE · BILDSCHIRM'
            if ($c) { $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)" } else { $m.State = T 'wird gelesen'; $m.StateColor = '#8C819F' }
            $main = @($list | Where-Object { $_.Primary }) + $list | Select-Object -First 1
            if ($main) {
                $m.Model = if ($main.Name) { "$($main.Name)" } else { T 'Bildschirm' }
                $m.Sub = "$($main.Width) × $($main.Height)$(if ($list.Count -gt 1) { T " · $($list.Count) Bildschirme" })"
                $m.Big = "$($main.Hz)"; $m.Unit = if ($main.Max -gt $main.Hz) { T "Hz – er kann $($main.Max) Hz" } else { T 'Hz · volle Bildrate' }
                $rows = @()
                foreach ($dsp in $list) {
                    $slow = $dsp.Max -gt $dsp.Hz
                    $rows += @{ N = "$(if ($dsp.Name) { $dsp.Name } else { T 'Bildschirm' }) · $($dsp.Width) × $($dsp.Height)"; Ok = $true }
                    $rows += @{ N = $(if ($slow) { T "$($dsp.Hz) von $($dsp.Max) Hz" } else { T "$($dsp.Hz) Hz eingestellt" }); Ok = -not $slow }
                }
                $m.Chart = @{ Kind = 'list'; Rows = $rows }
                $m.Facts = @(
                    (& $fact 'Auflösung' "$($main.Width) × $($main.Height)" (T 'Hauptbildschirm') 'Lila' 1 '' ''),
                    (& $fact 'Bildrate' "$($main.Hz) Hz" $(if ($main.Max -gt $main.Hz) { T "möglich wären $($main.Max) Hz" } else { T 'das Maximum bei dieser Auflösung' }) 'Indigo' $(if ($main.Max) { $main.Hz / $main.Max } else { 1 }) $(if ($main.Max -gt $main.Hz) { 'zu langsam' } else { 'gut' }) $(if ($main.Max -gt $main.Hz) { $warn } else { $good })),
                    (& $fact 'Bildschirme' "$($list.Count)" $(if ($list.Count -gt 1) { T 'getestet wird der mit PulsRig' } else { T 'ein Anzeigegerät' }) 'Beere' 1 '' ''),
                    (& $fact 'Testbilder' '8' (T 'tote Pixel, Lichthöfe, Schlieren') 'Rose' 1 '' '')
                )
            }
            else { $m.Model = T 'Bildschirm'; $m.Sub = T 'Bildwiederholrate und Testbilder'; $m.Chart = @{ Kind = 'note'; Text = T 'Lese die Bildschirme …' } }
            $m.Actions = @(@{ L = 'Monitor-Test'; S = 'acht Testbilder'; Do = { Open-MonitorSheet } }, @{ L = 'Anzeige'; S = 'Hz einstellen'; Do = { try { Start-Process 'ms-settings:display-advanced' } catch { } } }, @{ L = 'Gaming-Check'; S = 'Einstellungen'; Do = { Open-GameCheckSheet } })
            $m.Tip = T 'Viele Bildschirme laufen nach dem Anschließen nur mit 60 Hz. Kann deiner mehr, wirken Bewegungen nach dem Umstellen deutlich flüssiger.'
        }
        6 {
            $c = $script:CardState.Report
            $m.Tone = 'Beere'; $m.Kicker = 'GESUNDHEIT · BERICHT & DIAGNOSE'
            $m.Model = T 'Prüfbericht und Diagnose-Paket'
            $m.Sub = T 'Prüft alle Bereiche und packt alles in eine ZIP-Datei'
            if ($c) {
                $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)"
                $okN = if ("$($c.Detail)" -match '(\d+) gut') { [int]$Matches[1] } else { 0 }
                $warnN = if ("$($c.Detail)" -match '(\d+) auffällig') { [int]$Matches[1] } else { 0 }
                $open = if ("$($c.Detail)" -match '(\d+) offen') { [int]$Matches[1] } else { 0 }
                $m.Big = "$okN/$($okN + $warnN + $open)"; $m.Unit = T 'Bereiche in Ordnung'
            }
            else { $m.State = T 'noch nicht erstellt'; $m.StateColor = '#8C819F' }
            $rows = @()
            foreach ($pair in @(@('Treiber', 'Drivers'), @('Laufwerke', 'Drives'), @('Arbeitsspeicher', 'Memory'), @('Abstürze', 'Crashes'), @('Bildschirm', 'Displays'), @('BIOS', 'Bios'), @('Gaming-Check', 'GameCheck'))) {
                $state = $script:CardState[$pair[1]]
                if ($pair[1] -eq 'Drivers') { $rows += @{ N = T 'Treiber'; Ok = $(if ($script:LastResult) { @($script:LastResult.Drivers).Count -eq 0 } else { $null }) }; continue }
                $rows += @{ N = T $pair[0]; Ok = $(if ($state) { "$($state.Tone)" -eq 'good' } else { $null }) }
            }
            $m.Chart = @{ Kind = 'list'; Rows = $rows }
            $pack = $script:CardState.Diagnose
            $m.Facts = @(
                (& $fact 'Letzter Bericht' $(if ($c) { "$($c.Date)".Substring(0, [Math]::Min(6, "$($c.Date)".Length)) } else { '–' }) $(if ($c) { T "$($c.Detail)" } else { T 'noch keiner' }) 'Lila' 1 '' ''),
                (& $fact 'Hinweise' $(if ($c -and "$($c.Detail)" -match '(\d+) auffällig') { $Matches[1] } else { '0' }) (T 'auffällige Bereiche') 'Bernst' 0.5 '' ''),
                (& $fact 'ZIP-Datei' $(if ($pack) { "$($pack.Text)" } else { '–' }) $(if ($pack) { T $(if ($pack.Place) { "$($pack.Place)" } else { 'auf dem Desktop' }) } else { T 'Bericht und Diagnose in einem' }) 'Beere' 1 '' ''),
                (& $fact 'Inhalt' (T 'ohne Dateien') (T 'keine persönlichen Dateien, keine Namen') 'Indigo' 1 '' '')
            )
            $m.Actions = @(@{ L = 'Bericht erstellen'; S = 'als ZIP'; Do = { Open-ReportSheet } }, @{ L = 'Was ist los?'; S = 'Ursache finden'; Do = { Open-ProblemSheet } }, @{ L = 'Ordner öffnen'; S = $(if ($pack -and $pack.Place) { "$($pack.Place)" } else { 'auf dem Desktop' }); Do = { try { $made = $script:CardState.Diagnose; if ($made -and $made.File -and (Test-Path -LiteralPath $made.File)) { Start-Process explorer.exe "/select,`"$($made.File)`"" } else { Start-Process ([Environment]::GetFolderPath('Desktop')) } } catch { } } })
            $m.Tip = T 'Die ZIP-Datei enthält Prüfbericht und Diagnose in einem. Bei Fragen kannst du sie einfach weitergeben – persönliche Dateien sind nicht dabei.'
        }
        7 {
            $d = $script:BentoData.Bios; $c = $script:CardState.Bios
            $m.Tone = 'Grau'; $m.Kicker = 'SYSTEM · BIOS'
            if ($c) { $m.State = "$($c.Text)"; $m.StateColor = & $toneColor "$($c.Tone)" } else { $m.State = T 'wird gelesen'; $m.StateColor = '#8C819F' }
            $boardMaker, $boardModel = "$($d.Board)" -split '\|', 2
            $m.Model = if ($boardModel) { "$boardMaker $boardModel".Trim() } else { T 'Mainboard' }
            $m.Sub = if ($d) { T "BIOS $($d.Version)$(if ($d.Maker) { " · $($d.Maker)" })" } else { T 'Version, Alter und Seite des Herstellers' }
            if ($d -and $d.Released) {
                $months = [Math]::Max(0, ((Get-Date) - $d.Released).TotalDays / 30.44)
                $m.Big = if ($months -lt 24) { '{0:N0}' -f $months } else { '{0:N1}' -f ($months / 12) }
                $m.Unit = if ($months -lt 24) { T 'Monate alt' } else { T 'Jahre alt' }
                $m.Chart = @{ Kind = 'meters'; Rows = @(@{ L = T 'Alter'; V = [Math]::Min($months, 48); Max = 48; Text = $d.Released.ToString('dd.MM.yyyy') }) }
            }
            else { $m.Chart = @{ Kind = 'note'; Text = T 'Lese das BIOS …' } }
            $m.Facts = @(
                (& $fact 'Version' $(if ($d) { "$($d.Version)" } else { '–' }) $(if ($d -and $d.Released) { T "vom $($d.Released.ToString('dd.MM.yyyy'))" } else { '' }) 'Grau' 1 '' ''),
                (& $fact 'Hersteller' $(if ($d -and $d.Maker) { "$($d.Maker)" } else { '–' }) (T 'des BIOS') 'Lila' 1 '' ''),
                (& $fact 'Mainboard' $(if ($boardModel) { "$boardModel" } else { '–' }) "$boardMaker" 'Indigo' 1 '' ''),
                (& $fact 'Einspielen' (T 'nie automatisch') (T 'nur mit dem Werkzeug des Herstellers') 'Bernst' 1 '' '')
            )
            $m.Actions = @(@{ L = 'Neueres suchen'; S = 'beim Hersteller'; Do = { Open-BiosSheet } }, @{ L = 'Alle Einzelheiten'; S = 'Version, Gerät'; Do = { Open-BiosSheet } }, @{ L = 'Systeminfos'; S = 'im Überblick'; Do = { Open-Tool 'SystemInfo' } })
            $m.Tip = T 'Ein BIOS muss nicht das neueste sein, solange alles stabil läuft. Ein Update lohnt sich bei Abstürzen, für einen neuen Prozessor oder bei Sicherheitslücken.'
        }
    }
    $m
}

# Zeichnet die Detailseite neu (beim Öffnen mit -First: Kacheln kommen nacheinander herein)
function Update-BentoDetail([switch]$First) {
    $index = $script:BentoDetailIndex
    if ($index -lt 0 -or -not $ui.BentoDetail) { return }
    $m = Get-BentoDetailModel $index
    $page = $ui.BentoDetail
    $tone = $script:BentoTones[$m.Tone]
    $hero = $page.FindName('Hero')
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point 0, 0; $brush.EndPoint = New-Object Windows.Point 1, 1
    $c = [Windows.Media.ColorConverter]::ConvertFromString($tone.C)
    foreach ($stop in @(@([Windows.Media.Color]::FromArgb(0x88, $c.R, $c.G, $c.B), 0), @([Windows.Media.ColorConverter]::ConvertFromString('#1A1224'), 0.4), @([Windows.Media.ColorConverter]::ConvertFromString('#1A1224'), 0.7), @([Windows.Media.ColorConverter]::ConvertFromString('#55A8326F'), 1))) {
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop $stop[0], $stop[1]))
    }
    $hero.BorderBrush = $brush
    $hero.Background = New-BentoTint $m.Tone
    # Überschrift in Großbuchstaben: jeden Teil erst übersetzen (die Wortliste kennt die Wörter normal geschrieben)
    $title = (Get-Culture).TextInfo
    $page.FindName('Kicker').Text = (@($m.Kicker -split ' · ' | ForEach-Object { if ($_ -eq 'BIOS') { $_ } else { (T $title.ToTitleCase($_.ToLower())).ToUpper() } }) -join ' · ')
    $page.FindName('State').Text = T $m.State
    $page.FindName('State').Foreground = New-SolidBrush $m.StateColor
    $page.FindName('StateDot').Fill = New-SolidBrush $m.StateColor
    $page.FindName('StateBox').Background = Get-BentoArgb $m.StateColor 0x1A
    $page.FindName('StateBox').Visibility = if ($m.State) { 'Visible' } else { 'Collapsed' }
    $page.FindName('Model').Text = $m.Model
    $page.FindName('Sub').Text = $m.Sub
    $big = $page.FindName('Big')
    $big.Text = $m.Big
    $big.Parent.Visibility = if ($m.Big -and $m.Big -ne '–') { 'Visible' } else { 'Collapsed' }
    $big.FontFamily = New-Object Windows.Media.FontFamily $script:BentoMono
    $bigBrush = New-Object Windows.Media.LinearGradientBrush
    $bigBrush.StartPoint = New-Object Windows.Point 0, 0; $bigBrush.EndPoint = New-Object Windows.Point 1, 0
    $bigBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Colors]::White), 0))
    $bigBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($tone.C)), 1))
    $big.Foreground = $bigBrush
    $page.FindName('Unit').Text = $m.Unit
    $page.FindName('AxisL').Text = $m.AxisL
    $page.FindName('AxisR').Text = $m.AxisR

    # Verlauf: bei der Live-Kurve nur neu zeichnen, sonst neu aufbauen
    $chart = $page.FindName('Chart')
    if ($m.Chart) { Set-BentoChart $chart $m.Chart $tone.C -Animate:$First } else { $chart.Children.Clear() }

    # Fakten
    $facts = $page.FindName('Facts')
    if ($facts.Children.Count -ne 4) {
        $facts.Children.Clear()
        for ($i = 0; $i -lt 4; $i++) { [void]$facts.Children.Add([Windows.Markup.XamlReader]::Parse($bentoDetailFactXaml)) }
    }
    for ($i = 0; $i -lt 4; $i++) {
        $tile = $facts.Children[$i]
        $f = if ($i -lt @($m.Facts).Count) { $m.Facts[$i] } else { $null }
        $tile.Visibility = if ($f) { 'Visible' } else { 'Hidden' }
        if (-not $f) { continue }
        $ft = $script:BentoTones[$f.Tone]
        $tile.Background = New-BentoTint $f.Tone
        $tile.BorderBrush = New-BentoEdge $f.Tone
        $tile.FindName('Title').Text = T $f.T
        $tile.FindName('Title').Foreground = New-SolidBrush $ft.C
        $value = $tile.FindName('Value')
        $value.Text = "$($f.V)"
        $value.FontFamily = New-Object Windows.Media.FontFamily $script:BentoMono
        $value.FontSize = if ("$($f.V)".Length -gt 12) { 16 } else { 22 }
        $tile.FindName('Note').Text = "$($f.N)"
        $tile.FindName('State').Text = T "$($f.S)"
        $tile.FindName('State').Foreground = New-SolidBrush $(if ($f.SC) { $f.SC } else { '#8C819F' })
        $bar = $tile.FindName('Bar')
        $fillBrush = New-Object Windows.Media.LinearGradientBrush
        $fillBrush.StartPoint = New-Object Windows.Point 0, 0; $fillBrush.EndPoint = New-Object Windows.Point 1, 0
        $fillBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($ft.C)), 0))
        $fillBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#A8326F')), 1))
        $bar.Background = $fillBrush
        $box = $tile.FindName('BarBox')
        $box.Tag = [Math]::Max(0.0, [Math]::Min(1.0, [double]$f.Bar))
        $box.Visibility = if ([double]$f.Bar -gt 0) { 'Visible' } else { 'Hidden' }
        if ($box.ActualWidth -gt 0) { $bar.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-DoubleAnim -To ($box.ActualWidth * [double]$box.Tag) -Ms 600 -Ease $script:EaseOut)) }
        else { $box.Add_SizeChanged({ try { $this.Children[1].Width = $this.ActualWidth * [double]$this.Tag } catch { } }) }
    }

    # Aktionen
    $row = $page.FindName('ActionRow')
    if ($First -or $row.Children.Count -eq 0) {
    $row.Children.Clear()
    $k = 0
    foreach ($a in @($m.Actions)) {
        $button = New-Object Windows.Controls.Button
        $button.Style = $window.FindResource($(if ($k -eq 0) { 'PrimaryButton' } else { 'GhostButton' }))
        $button.Height = 58
        $button.Margin = New-Object Windows.Thickness 4, 0, 4, 0
        $button.HorizontalContentAlignment = 'Left'
        $content = New-Object Windows.Controls.StackPanel
        [void]$content.Children.Add((New-BentoText (T $a.L) 12.5 '#FFFFFF' 'SemiBold'))
        [void]$content.Children.Add((New-BentoText (T $a.S) 11 $(if ($k -eq 0) { '#E8DDF5' } else { '#8C819F' })))
        $button.Content = $content
        $button.Tag = $a.Do
        $button.Add_Click({ try { & $this.Tag } catch { Write-AppError $_ } })
        [void]$row.Children.Add($button)
        $k++
    }
    }

    # Kurz erklärt
    $tip = $page.FindName('Tip')
    $tip.BorderBrush = Get-BentoArgb $tone.C 0x22
    $page.FindName('TipIcon').Background = Get-BentoArgb $tone.C 0x1A
    $page.FindName('TipIcon').BorderBrush = Get-BentoArgb $tone.C 0x33
    $page.FindName('TipGlyph').Foreground = New-SolidBrush $tone.C
    $page.FindName('TipTitle').Foreground = New-SolidBrush $tone.C
    $page.FindName('TipText').Text = $m.Tip

    if ($First -and $script:Settings.Animations) {
        $parts = @($hero) + @($facts.Children) + @($page.FindName('Actions'), $tip)
        $n = 0
        foreach ($part in $parts) {
            $part.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $part.RenderTransform = New-Object Windows.Media.ScaleTransform
            $part.BeginAnimation($P.Opacity, $null); $part.Opacity = 0
            Start-Fade $part 1 300 (60 * $n)
            Start-Scale $part 1 460 (60 * $n) 0.94 $script:EaseBack
            $n++
        }
    }
}

# Der Verlauf in der großen Kachel
function Set-BentoChart($Target, $Chart, [string]$Color, [switch]$Animate) {
    if ($Chart.Kind -eq 'line' -and $Target.Tag -eq 'line') {
        Set-BentoLine $Target $Chart.Values $Color
        return
    }
    $Target.Children.Clear()
    $Target.Tag = $Chart.Kind
    switch ($Chart.Kind) {
        'line' {
            $Target.VerticalAlignment = 'Stretch'
            $area = New-Object Windows.Shapes.Path
            $line = New-Object Windows.Shapes.Path
            $line.StrokeThickness = 2; $line.StrokeLineJoin = 'Round'
            $line.Stroke = New-SolidBrush $Color
            $fill = New-Object Windows.Media.LinearGradientBrush
            $fill.StartPoint = New-Object Windows.Point 0, 0; $fill.EndPoint = New-Object Windows.Point 0, 1
            $c = [Windows.Media.ColorConverter]::ConvertFromString($Color)
            $fill.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0x55, $c.R, $c.G, $c.B)), 0))
            $fill.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B)), 1))
            $area.Fill = $fill
            # auf einer Zeichenfläche: die Kurve verlangt so keinen Platz und kann die Kachel nicht aufweiten
            $canvas = New-Object Windows.Controls.Canvas
            [void]$canvas.Children.Add($area); [void]$canvas.Children.Add($line)
            $Target.ClipToBounds = $true
            [void]$Target.Children.Add($canvas)
            $Target.Add_SizeChanged({ try { if ($this.Tag -eq 'line') { Set-BentoLine $this $script:BentoLive.Gpu.ToArray() '' } } catch { } })
            Set-BentoLine $Target $Chart.Values $Color
        }
        'volumes' {
            $stack = New-Object Windows.Controls.StackPanel
            $stack.VerticalAlignment = 'Center'
            foreach ($r in $Chart.Rows) {
                $grid = New-Object Windows.Controls.Grid
                $grid.Margin = New-Object Windows.Thickness 0, 0, 0, 12
                foreach ($w in 34, 0, 110) { $col = New-Object Windows.Controls.ColumnDefinition; if ($w) { $col.Width = New-Object Windows.GridLength $w }; $grid.ColumnDefinitions.Add($col) }
                $label = New-BentoText $r.L 13 '#B3A8C4' 'SemiBold'
                $label.FontFamily = New-Object Windows.Media.FontFamily $script:BentoMono
                $bar = New-HwBar $r.F $(if ($r.F -ge 0.9) { 'Warn' } else { 'grad' }) 9
                [Windows.Controls.Grid]::SetColumn($bar, 1)
                $text = New-BentoText $r.T 11.5 '#8C819F'
                $text.HorizontalAlignment = 'Right'
                [Windows.Controls.Grid]::SetColumn($text, 2)
                foreach ($e in $label, $bar, $text) { [void]$grid.Children.Add($e) }
                [void]$stack.Children.Add($grid)
            }
            [void]$Target.Children.Add($stack)
        }
        'slots' { [void]$Target.Children.Add((New-BentoSlots $Chart -Animate:$Animate)) }
        'days' {
            $grid = New-Object Windows.Controls.Primitives.UniformGrid
            $grid.Rows = 2; $grid.Columns = 15
            $grid.VerticalAlignment = 'Bottom'
            $hit = if ($Chart.Tone -eq 'bad') { '#C0608F' } else { '#F2B661' }
            for ($i = 29; $i -ge 0; $i--) {
                $day = New-Object Windows.Controls.Border
                $day.Height = 22; $day.Margin = New-Object Windows.Thickness 3
                $day.CornerRadius = New-Object Windows.CornerRadius 5
                if ($Chart.Days -contains $i) {
                    $day.Background = New-SolidBrush $hit
                    $glow = New-Object Windows.Media.Effects.DropShadowEffect
                    $glow.Color = [Windows.Media.ColorConverter]::ConvertFromString($hit); $glow.BlurRadius = 12; $glow.ShadowDepth = 0; $glow.Opacity = 0.8
                    $day.Effect = $glow
                }
                else { $day.Background = Get-BentoArgb '#5EE0A0' 0x33 }
                [void]$grid.Children.Add($day)
            }
            [void]$Target.Children.Add($grid)
        }
        'list' {
            $grid = New-Object Windows.Controls.Primitives.UniformGrid
            $grid.Columns = 2
            $grid.VerticalAlignment = 'Bottom'
            foreach ($r in $Chart.Rows) {
                $line = New-Object Windows.Controls.Border
                $line.BorderBrush = New-SolidBrush '#1A1224'
                $line.BorderThickness = New-Object Windows.Thickness 0, 0, 0, 1
                $line.Margin = New-Object Windows.Thickness 0, 0, 14, 4
                $line.Padding = New-Object Windows.Thickness 0, 5, 0, 5
                $inner = New-Object Windows.Controls.StackPanel
                $inner.Orientation = 'Horizontal'
                $mark = New-Object Windows.Controls.Border
                $mark.Width = 18; $mark.Height = 18; $mark.CornerRadius = New-Object Windows.CornerRadius 9
                $sign = if ($null -eq $r.Ok) { '–' } elseif ($r.Ok) { [string][char]0x2713 } else { '!' }
                $col = if ($null -eq $r.Ok) { '#8C819F' } elseif ($r.Ok) { '#8FF0BE' } else { '#F6C989' }
                $mark.Background = Get-BentoArgb $col 0x22
                $markText = New-BentoText $sign 10.5 $col 'Bold'
                $markText.HorizontalAlignment = 'Center'
                $mark.Child = $markText
                $name = New-BentoText "$($r.N)" 12 '#B3A8C4'
                $name.Margin = New-Object Windows.Thickness 9, 0, 0, 0
                $name.TextTrimming = 'CharacterEllipsis'
                [void]$inner.Children.Add($mark); [void]$inner.Children.Add($name)
                $line.Child = $inner
                [void]$grid.Children.Add($line)
            }
            [void]$Target.Children.Add($grid)
        }
        'meters' {
            $stack = New-Object Windows.Controls.StackPanel
            $stack.VerticalAlignment = 'Center'
            foreach ($r in $Chart.Rows) {
                $head = New-Object Windows.Controls.Grid
                $head.Margin = New-Object Windows.Thickness 0, 0, 0, 6
                [void]$head.Children.Add((New-BentoText (T $r.L) 12.5 '#B3A8C4' 'SemiBold'))
                $val = New-BentoText $(if ($r.Text) { $r.Text } elseif ($r.V -gt 0) { '{0:N0} °C von {1:N0} °C' -f $r.V, $r.Max } else { '–' }) 11.5 '#8C819F'
                $val.HorizontalAlignment = 'Right'
                [void]$head.Children.Add($val)
                [void]$stack.Children.Add($head)
                $bar = New-HwBar ($r.V / $r.Max) $(if ($r.V / $r.Max -ge 0.92) { 'Warn' } else { 'grad' }) 12
                $bar.Margin = New-Object Windows.Thickness 0, 0, 0, 18
                [void]$stack.Children.Add($bar)
            }
            [void]$Target.Children.Add($stack)
        }
        'note' {
            $text = New-BentoText $Chart.Text 13 '#8C819F'
            $text.TextWrapping = 'Wrap'
            $text.VerticalAlignment = 'Center'
            [void]$Target.Children.Add($text)
        }
    }
}

function Set-BentoLine($Target, $Values, [string]$Color) {
    $values = @($Values)
    if ($Target.Children.Count -lt 1 -or $Target.Children[0] -isnot [Windows.Controls.Canvas]) { return }
    $paths = $Target.Children[0].Children
    $width = $Target.ActualWidth; $height = $Target.ActualHeight
    if ($values.Count -lt 2 -or $width -lt 10 -or $height -lt 10) { return }
    $low = ($values | Measure-Object -Minimum).Minimum; $high = ($values | Measure-Object -Maximum).Maximum
    if ($high - $low -lt 8) { $mid = ($high + $low) / 2; $low = $mid - 4; $high = $mid + 4 }
    $culture = [cultureinfo]::InvariantCulture
    $step = $width / 59.0
    $start = $width - $step * ($values.Count - 1)
    $points = for ($i = 0; $i -lt $values.Count; $i++) {
        $x = $start + $step * $i
        $y = $height - 4 - ($values[$i] - $low) / ($high - $low) * ($height - 10)
        '{0},{1}' -f $x.ToString('0.0', $culture), $y.ToString('0.0', $culture)
    }
    $paths[1].Data = [Windows.Media.Geometry]::Parse('M ' + ($points -join ' L '))
    $paths[0].Data = [Windows.Media.Geometry]::Parse('M ' + $start.ToString('0.0', $culture) + ',' + $height.ToString('0.0', $culture) + ' L ' + ($points -join ' L ') + ' L ' + $width.ToString('0.0', $culture) + ',' + $height.ToString('0.0', $culture) + ' Z')
}

# Die Riegel in ihren Steckplätzen (wie im Entwurf: lila Platine, Bausteine, goldene Kontaktleiste, leere gestrichelt)
function New-BentoSlots($Chart, [switch]$Animate) {
    $stack = New-Object Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'
    $modules = @($Chart.Modules)
    $number = 0
    foreach ($place in @($Chart.Layout)) {
        $row = New-Object Windows.Controls.Grid
        $row.Height = 40
        $row.Margin = New-Object Windows.Thickness 0, 0, 0, 6
        foreach ($w in 66, 0, 158) { $col = New-Object Windows.Controls.ColumnDefinition; if ($w) { $col.Width = New-Object Windows.GridLength $w }; $row.ColumnDefinitions.Add($col) }
        $module = if ($place.Module -ge 0 -and $place.Module -lt $modules.Count) { $modules[$place.Module] } else { $null }
        $nameBox = New-Object Windows.Controls.StackPanel
        $nameBox.VerticalAlignment = 'Center'
        $slotName = New-BentoText ("$($place.Slot)" -replace '(?i)^(channel\s*[a-h]\s*-?\s*)', '') 12.5 $(if ($module) { '#E2DCEB' } else { '#4A3D5E' }) 'SemiBold'
        $slotName.FontFamily = New-Object Windows.Media.FontFamily $script:BentoMono
        $slotName.TextTrimming = 'CharacterEllipsis'
        $bank = ("$($place.Bank)" -replace '^P\d+\s+', '') -replace '(?i)channel', 'Kanal'
        [void]$nameBox.Children.Add($slotName)
        if ($bank) { [void]$nameBox.Children.Add((New-BentoText (T $bank) 10.5 '#8C819F')) }
        [void]$row.Children.Add($nameBox)
        $wrong = $Chart.Placement.Wrong -contains $number
        $better = $Chart.Placement.Better -contains $number
        if ($module) {
            $stick = New-Object Windows.Controls.Grid
            $stick.Height = 36
            $board = New-Object Windows.Controls.Border
            $board.CornerRadius = New-Object Windows.CornerRadius 6, 6, 2, 2
            $board.BorderThickness = New-Object Windows.Thickness $(if ($wrong) { 1.6 } else { 1 })
            $board.BorderBrush = if ($wrong) { New-SolidBrush '#F2B661' } else { Get-BentoArgb '#8C6BD6' 0xAA }
            $boardFill = New-Object Windows.Media.LinearGradientBrush
            $boardFill.StartPoint = New-Object Windows.Point 0, 0; $boardFill.EndPoint = New-Object Windows.Point 1, 0
            $boardFill.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#666D43C9')), 0))
            $boardFill.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#55A8326F')), 1))
            $board.Background = $boardFill
            $glow = New-Object Windows.Media.Effects.DropShadowEffect
            $glow.Color = [Windows.Media.ColorConverter]::ConvertFromString('#6D43C9'); $glow.BlurRadius = 16; $glow.ShadowDepth = 0; $glow.Opacity = 0.45
            $board.Effect = $glow
            [void]$stick.Children.Add($board)
            $chips = New-Object Windows.Controls.Primitives.UniformGrid
            $chips.Rows = 1; $chips.Margin = New-Object Windows.Thickness 12, 6, 12, 11
            for ($i = 0; $i -lt 8; $i++) {
                $chip = New-Object Windows.Controls.Border
                $chip.Margin = New-Object Windows.Thickness $(if ($i -eq 4) { 7 } else { 3 }), 0, 3, 0
                $chip.CornerRadius = New-Object Windows.CornerRadius 2
                $chip.Background = New-SolidBrush '#0A0610'
                $chip.BorderBrush = Get-BentoArgb '#FFFFFF' 0x14
                $chip.BorderThickness = New-Object Windows.Thickness 1
                [void]$chips.Children.Add($chip)
            }
            [void]$stick.Children.Add($chips)
            $pins = New-Object Windows.Shapes.Line
            $pins.X1 = 0; $pins.X2 = 1; $pins.Stretch = 'Fill'
            $pins.Stroke = New-SolidBrush '#E9C46A'; $pins.StrokeThickness = 4; $pins.Opacity = 0.85
            $pins.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@(0.6, 0.45))
            $pins.VerticalAlignment = 'Bottom'; $pins.Margin = New-Object Windows.Thickness 10, 0, 10, 1
            [void]$stick.Children.Add($pins)
            [Windows.Controls.Grid]::SetColumn($stick, 1)
            [void]$row.Children.Add($stick)
            if ($Animate -and $script:Settings.Animations) {
                # der Riegel schiebt sich von links in seinen Steckplatz
                $stick.RenderTransformOrigin = New-Object Windows.Point 0, 0.5
                $stick.RenderTransform = New-Object Windows.Media.ScaleTransform 0, 1
                $stick.RenderTransform.BeginAnimation($P.ScaleX, (New-DoubleAnim -To 1 -Ms 520 -Delay (220 + 90 * $number) -Ease $script:EaseOut))
            }
            $title = (@(('{0:N0} GB' -f ($module.Bytes / 1GB)), "$($module.Type)") | Where-Object { $_ }) -join ' '
            if ($module.Speed) { $title += ' · {0:N0}' -f $module.Speed }
            $sub = if ($wrong) { T 'falscher Steckplatz' } else { (@("$($module.Maker)", "$($module.Part)") | Where-Object { $_ }) -join ' ' }
        }
        else {
            $empty = New-Object Windows.Shapes.Rectangle
            $empty.Height = 32; $empty.RadiusX = 6; $empty.RadiusY = 6
            $empty.Stroke = New-SolidBrush $(if ($better) { '#8C6BD6' } else { '#3E3150' })
            $empty.StrokeThickness = $(if ($better) { 1.6 } else { 1.2 })
            $empty.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@(4, 3))
            [Windows.Controls.Grid]::SetColumn($empty, 1)
            [void]$row.Children.Add($empty)
            $freeText = New-BentoText (T 'frei') 11 '#4A3D5E'
            $freeText.HorizontalAlignment = 'Center'
            [Windows.Controls.Grid]::SetColumn($freeText, 1)
            [void]$row.Children.Add($freeText)
            $title = if ($better) { T 'hierhin umstecken' } else { T 'leer' }
            $sub = T 'nichts eingesteckt'
        }
        $info = New-Object Windows.Controls.StackPanel
        $info.VerticalAlignment = 'Center'; $info.Margin = New-Object Windows.Thickness 14, 0, 0, 0
        $infoTitle = New-BentoText $title 12.5 $(if ($module) { '#E2DCEB' } elseif ($better) { '#B19FE0' } else { '#4A3D5E' }) 'SemiBold'
        $infoTitle.TextTrimming = 'CharacterEllipsis'
        $infoSub = New-BentoText $sub 10.5 $(if ($wrong) { '#F6C989' } else { '#8C819F' })
        $infoSub.TextTrimming = 'CharacterEllipsis'
        [void]$info.Children.Add($infoTitle); [void]$info.Children.Add($infoSub)
        [Windows.Controls.Grid]::SetColumn($info, 2)
        [void]$row.Children.Add($info)
        [void]$stack.Children.Add($row)
        $number++
    }
    $stack
}

# --- Optionen als Kachelseite (Entwurf Q5) ------------------------------------------
# Eigene Seite statt des Fensters: Aussehen (Nacht-Bento oder Klassisch), Sprache, Bewegung mit Vorschau,
# Überwachung (Schalter des Helfers) und Schnellzugriff. Alles Weitere steht unter "Alle Einstellungen"
# (das bisherige Fenster mit Reitern); Stellen, die einen bestimmten Reiter öffnen, öffnen weiter das Fenster.

$bentoOptionsXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      x:Name="PageOptions" Visibility="Collapsed">
    <Grid.RenderTransform>
        <TranslateTransform/>
    </Grid.RenderTransform>
    <Grid Margin="-6">
        <Grid.ColumnDefinitions>
            <ColumnDefinition/>
            <ColumnDefinition/>
            <ColumnDefinition/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition/>
            <RowDefinition/>
            <RowDefinition/>
        </Grid.RowDefinitions>
        <Border x:Name="OptLook" Grid.ColumnSpan="2" Margin="6" CornerRadius="22" BorderThickness="1" Padding="18,16,18,16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid>
                    <TextBlock x:Name="OptLookTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#8C6BD6"/>
                    <Button x:Name="OptLookMore" Style="{DynamicResource LinkButton}" HorizontalAlignment="Right"/>
                </Grid>
                <UniformGrid x:Name="OptLookCards" Grid.Row="1" Columns="2" Margin="-5,10,-5,0"/>
            </Grid>
        </Border>
        <Border x:Name="OptLang" Grid.Column="2" Margin="6" CornerRadius="22" BorderThickness="1" Padding="18,16,18,16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock x:Name="OptLangTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#C0608F"/>
                <StackPanel x:Name="OptLangList" Grid.Row="1" VerticalAlignment="Bottom"/>
            </Grid>
        </Border>
        <Border x:Name="OptMotion" Grid.Row="1" Grid.ColumnSpan="2" Margin="6" CornerRadius="22" BorderThickness="1" Padding="18,16,18,16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid>
                    <TextBlock x:Name="OptMotionTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#8C6BD6"/>
                    <TextBlock x:Name="OptMotionNote" FontSize="11" Foreground="#8C819F" HorizontalAlignment="Right"/>
                </Grid>
                <Grid x:Name="OptMotionPreview" Grid.Row="1" Margin="0,8,0,8" ClipToBounds="True"/>
                <Border Grid.Row="2" CornerRadius="14" Background="#06FFFFFF" BorderBrush="#1A1224" BorderThickness="1" Padding="4">
                    <UniformGrid x:Name="OptMotionChoices" Rows="1"/>
                </Border>
            </Grid>
        </Border>
        <Border x:Name="OptWatch" Grid.Row="1" Grid.RowSpan="2" Grid.Column="2" Margin="6" CornerRadius="22" BorderThickness="1" Padding="18,16,18,12">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock x:Name="OptWatchTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#5EE0A0"/>
                <StackPanel x:Name="OptWatchList" Grid.Row="1" Margin="0,8,0,0"/>
            </Grid>
        </Border>
        <Border x:Name="OptQuick" Grid.Row="2" Grid.ColumnSpan="2" Margin="6" CornerRadius="22" Background="#0B0710" BorderBrush="#22172F" BorderThickness="1" Padding="18,16,18,16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid>
                    <TextBlock x:Name="OptQuickTitle" FontSize="12.5" FontWeight="SemiBold" Foreground="#B3A8C4"/>
                    <TextBlock x:Name="OptVersion" FontFamily="Consolas" FontSize="11" Foreground="#8C819F" HorizontalAlignment="Right"/>
                </Grid>
                <UniformGrid x:Name="OptQuickList" Grid.Row="1" Rows="1" VerticalAlignment="Bottom" Margin="-4,0,-4,0"/>
            </Grid>
        </Border>
    </Grid>
</Grid>
'@

$bentoSwitchXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Background="Transparent" Cursor="Hand" Margin="0,0,0,2">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    <Border BorderBrush="#1A1224" BorderThickness="0,0,0,1" Grid.ColumnSpan="2"/>
    <StackPanel Margin="0,9,10,10" VerticalAlignment="Center">
        <TextBlock x:Name="Title" FontSize="13" FontWeight="SemiBold" Foreground="#E2DCEB" TextWrapping="Wrap"/>
        <TextBlock x:Name="Sub" FontSize="11" Foreground="#8C819F" TextWrapping="Wrap" Margin="0,2,0,0"/>
    </StackPanel>
    <Grid Grid.Column="1" Width="40" Height="22" VerticalAlignment="Center">
        <Border x:Name="Track" CornerRadius="11"/>
        <Ellipse x:Name="Knob" Width="16" Height="16" Fill="White" HorizontalAlignment="Left" Margin="3,0,0,0">
            <Ellipse.RenderTransform>
                <TranslateTransform/>
            </Ellipse.RenderTransform>
        </Ellipse>
    </Grid>
</Grid>
'@

# Schlichter Knopf für die Auswahlen der Seite: Hintergrund und Rand kommen vom Knopf (gewählt = heller)
$bentoChoiceXaml = @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Foreground" Value="#E2DCEB"/>
    <Setter Property="Background" Value="#0BFFFFFF"/>
    <Setter Property="BorderBrush" Value="#22172F"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="HorizontalContentAlignment" Value="Center"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Button">
                <Grid>
                    <Border CornerRadius="12" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"/>
                    <Border x:Name="Hover" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="12" Background="White" Opacity="0"/>
                    <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                </Grid>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Hover" Property="Opacity" Value="0.05"/>
                    </Trigger>
                    <Trigger Property="IsPressed" Value="True">
                        <Setter TargetName="Hover" Property="Opacity" Value="0.1"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
'@

function Set-BentoOptions {
    $window.Resources['BentoChoice'] = [Windows.Markup.XamlReader]::Parse($bentoChoiceXaml)
    $page = [Windows.Markup.XamlReader]::Parse($bentoOptionsXaml)
    [void]$ui.Pages.Children.Add($page)
    $ui.PageOptions = $page
    $script:NavIndex.Options = 4
    $script:BentoPageNames.Options = 'Optionen'
    foreach ($pair in @(@('OptLook', 'Lila'), @('OptLang', 'Beere'), @('OptMotion', 'Indigo'), @('OptWatch', 'Gruen'))) { Set-BentoTone $page.FindName($pair[0]) $pair[1] }
    $page.FindName('OptLookTitle').Text = T 'Aussehen'
    $page.FindName('OptLookMore').Content = T 'Alle Einstellungen'
    $page.FindName('OptLookMore').Add_Click({ try { Open-SettingsSheet 1 } catch { Write-AppError $_ } })
    $page.FindName('OptLangTitle').Text = T 'Sprache'
    $page.FindName('OptMotionTitle').Text = T 'Bewegung'
    $page.FindName('OptWatchTitle').Text = T 'Überwachung'
    $page.FindName('OptQuickTitle').Text = T 'Schnellzugriff'
    $page.FindName('OptVersion').Text = "PulsRig $($script:Version)"

    # Aussehen: zwei Karten mit kleiner Vorschau
    $cards = $page.FindName('OptLookCards')
    foreach ($look in @(@{ Key = 'Bento'; Name = 'Nacht-Bento'; Sub = 'neu · Lila & Pink'; Back = '#0B0710'; A = '#6D43C9'; B = '#A8326F' }, @{ Key = 'NachtPuls'; Name = 'Klassisch'; Sub = 'das bisherige Aussehen'; Back = '#0F1626'; A = '#5CC8FF'; B = '#9B7BFF' })) {
        $button = New-Object Windows.Controls.Button
        $button.Style = $window.FindResource('BentoChoice')
        $button.Margin = New-Object Windows.Thickness 5, 0, 5, 0
        $button.Height = [double]::NaN
        $button.VerticalAlignment = 'Stretch'
        $button.HorizontalContentAlignment = 'Left'
        $button.Padding = New-Object Windows.Thickness 12, 10, 12, 10
        $row = New-Object Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $preview = [Windows.Markup.XamlReader]::Parse(@"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="66" Height="46" CornerRadius="8" Background="$($look.Back)" Padding="5">
    <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="9"/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
        <Border Grid.RowSpan="2" CornerRadius="2" Background="#14FFFFFF" Margin="0,0,3,0"/>
        <Border Grid.Column="1" CornerRadius="3" Background="$($look.A)" Margin="0,0,2,2"/>
        <Border Grid.Column="2" CornerRadius="3" Background="#12FFFFFF" Margin="0,0,0,2"/>
        <Border Grid.Column="1" Grid.Row="1" CornerRadius="3" Background="#12FFFFFF" Margin="0,0,2,0"/>
        <Border Grid.Column="2" Grid.Row="1" CornerRadius="3" Background="$($look.B)"/>
    </Grid>
</Border>
"@)
        [void]$row.Children.Add($preview)
        $text = New-Object Windows.Controls.StackPanel
        $text.Margin = New-Object Windows.Thickness 12, 0, 0, 0
        $text.VerticalAlignment = 'Center'
        [void]$text.Children.Add((New-BentoText (T $look.Name) 14 '#E2DCEB' 'SemiBold'))
        [void]$text.Children.Add((New-BentoText (T $look.Sub) 11.5 '#8C819F'))
        [void]$row.Children.Add($text)
        $button.Content = $row
        $button.Tag = $look.Key
        $chosen = $script:Settings.Skin -eq $look.Key -or ($look.Key -eq 'NachtPuls' -and $script:Settings.Skin -notin 'Bento', 'NachtPuls')
        if ($chosen) { $button.BorderBrush = New-SolidBrush '#8C6BD6'; $button.Background = New-SolidBrush '#140C1D' }
        $button.Add_Click({ try { Set-Skin ([string]$this.Tag) } catch { Write-AppError $_ } })
        [void]$cards.Children.Add($button)
    }

    # Sprache
    $langs = $page.FindName('OptLangList')
    foreach ($lang in @(@{ Id = 'de'; Text = 'Deutsch' }, @{ Id = 'en'; Text = 'English' })) {
        $button = New-Object Windows.Controls.Button
        $button.Style = $window.FindResource('BentoChoice')
        $button.Height = 38
        $button.Margin = New-Object Windows.Thickness 0, 6, 0, 0
        $button.HorizontalContentAlignment = 'Stretch'
        $grid = New-Object Windows.Controls.Grid
        [void]$grid.Children.Add((New-BentoText $lang.Text 13 $(if ($script:Language -eq $lang.Id) { '#FFFFFF' } else { '#B3A8C4' }) 'SemiBold'))
        if ($script:Language -eq $lang.Id) {
            $dot = New-Object Windows.Shapes.Ellipse
            $dot.Width = 7; $dot.Height = 7; $dot.Fill = New-SolidBrush '#C0608F'; $dot.HorizontalAlignment = 'Right'
            [void]$grid.Children.Add($dot)
            $button.BorderBrush = Get-BentoArgb '#A8326F' 0x66
            $button.Background = New-SolidBrush '#1B0916'
        }
        $button.Content = $grid
        $button.Tag = $lang.Id
        $button.Add_Click({ try { Set-Language ([string]$this.Tag) } catch { Write-AppError $_ } })
        [void]$langs.Children.Add($button)
    }

    # Bewegung: Vorschau-Puls und vier Stufen
    $preview = $page.FindName('OptMotionPreview')
    $line = New-Object Windows.Shapes.Path
    $line.Data = [Windows.Media.Geometry]::Parse('M 0,17 L 200,17 L 210,7 L 224,31 L 236,11 L 244,17 L 600,17')
    $line.Stretch = 'Fill'
    $line.Height = 34
    $line.StrokeThickness = 2.4
    $line.StrokeLineJoin = 'Round'
    $line.Stroke = New-SolidBrush '#8C6BD6'
    $line.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@(18, 400))
    $glow = New-Object Windows.Media.Effects.DropShadowEffect
    $glow.Color = [Windows.Media.ColorConverter]::ConvertFromString('#6D43C9'); $glow.BlurRadius = 10; $glow.ShadowDepth = 0
    $line.Effect = $glow
    $base = New-Object Windows.Shapes.Path
    $base.Data = $line.Data; $base.Stretch = 'Fill'; $base.Height = 34; $base.StrokeThickness = 2; $base.Stroke = New-SolidBrush '#1C1229'
    [void]$preview.Children.Add($base); [void]$preview.Children.Add($line)
    $ui.OptMotionLine = $line
    $choices = $page.FindName('OptMotionChoices')
    foreach ($level in 'Aus', 'Ruhig', 'Normal', 'Lebendig') {
        $button = New-Object Windows.Controls.Button
        $button.Style = $window.FindResource('BentoChoice')
        $button.Height = 32
        $button.Margin = New-Object Windows.Thickness 2, 0, 2, 0
        $button.BorderThickness = New-Object Windows.Thickness 0
        $button.Content = T $level
        $button.Tag = $level
        $button.Add_Click({
                try {
                    if ($this.Tag -eq 'Aus') { $script:Settings.Animations = $false }
                    else { $script:Settings.Animations = $true; $script:Settings.Motion = [string]$this.Tag }
                    Update-Motion
                    Save-Settings
                    Update-SettingEffects 'Animations'
                    Update-BentoMotion
                }
                catch { Write-AppError $_ }
            })
        [void]$choices.Children.Add($button)
    }
    Update-BentoMotion

    # Überwachung: die Schalter des Helfers
    $list = $page.FindName('OptWatchList')
    foreach ($entry in @(
            @{ Key = 'Helper'; Title = 'Helfer neben der Uhr'; Sub = 'startet mit Windows, leise im Infobereich' },
            @{ Key = 'WeeklyScan'; Title = 'Neue Treiber melden'; Sub = 'einmal pro Woche nachsehen' },
            @{ Key = 'AutoBoost'; Title = 'Boost bei Spielen'; Sub = 'schaltet sich beim Spielen selbst ein' },
            @{ Key = 'RecordGames'; Title = 'Spiele aufzeichnen'; Sub = 'Temperaturen beim Spielen mitschreiben' })) {
        $row = [Windows.Markup.XamlReader]::Parse($bentoSwitchXaml)
        $row.FindName('Title').Text = T $entry.Title
        $row.FindName('Sub').Text = T $entry.Sub
        $row.Tag = $entry.Key
        $row.Add_MouseLeftButtonUp({
                try {
                    $key = [string]$this.Tag
                    $script:Settings[$key] = -not [bool]$script:Settings[$key]
                    Save-Settings
                    Update-SettingEffects $key
                    Set-BentoSwitch $this
                }
                catch { Write-AppError $_ }
            })
        Set-BentoSwitch $row -Instant
        [void]$list.Children.Add($row)
    }

    # Schnellzugriff
    $quick = $page.FindName('OptQuickList')
    foreach ($entry in @(
            @{ Text = 'Treiberverlauf'; Glyph = 0xE81C; Do = { Open-HistorySheet } },
            @{ Text = 'Zielordner'; Glyph = 0xE8B7; Do = { Start-Process explorer.exe "`"$(Get-TargetDir)`"" } },
            @{ Text = 'Kurzanleitung'; Glyph = 0xE897; Do = { Open-HelpSheet 0 } },
            @{ Text = 'Über PulsRig'; Glyph = 0xE946; Do = { Open-HelpSheet 1 } })) {
        $button = New-Object Windows.Controls.Button
        $button.Style = $window.FindResource('BentoChoice')
        $button.Height = 58
        $button.Margin = New-Object Windows.Thickness 4, 0, 4, 0
        $stack = New-Object Windows.Controls.StackPanel
        $icon = New-BentoText (Get-Glyph $entry.Glyph) 16 '#8C6BD6'
        $icon.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'
        $icon.HorizontalAlignment = 'Center'
        $label = New-BentoText (T $entry.Text) 12 '#E2DCEB' 'SemiBold'
        $label.HorizontalAlignment = 'Center'
        $label.Margin = New-Object Windows.Thickness 0, 5, 0, 0
        [void]$stack.Children.Add($icon); [void]$stack.Children.Add($label)
        $button.Content = $stack
        $button.Tag = $entry.Do
        $button.Add_Click({ try { & $this.Tag } catch { Write-AppError $_ } })
        [void]$quick.Children.Add($button)
    }
}

# Schalter: Spur grün und Knopf rechts, wenn an
function Set-BentoSwitch($Row, [switch]$Instant) {
    $on = [bool]$script:Settings[[string]$Row.Tag]
    $Row.FindName('Track').Background = if ($on) { New-SolidBrush '#5EE0A0' } else { Get-BentoArgb '#FFFFFF' 0x1F }
    $move = $Row.FindName('Knob').RenderTransform
    if ($Instant) { $move.X = if ($on) { 18 } else { 0 } }
    else { $move.BeginAnimation($P.X, (New-DoubleAnim -To $(if ($on) { 18 } else { 0 }) -Ms 300 -Ease $script:EaseBack)) }
}

# Bewegung: gewählte Stufe hervorheben, Vorschau im passenden Tempo
function Update-BentoMotion {
    $page = $ui.PageOptions
    if (-not $page) { return }
    $level = if ($script:Settings.Animations) { "$($script:Settings.Motion)" } else { 'Aus' }
    if ($level -notin 'Ruhig', 'Normal', 'Lebendig', 'Aus') { $level = 'Normal' }
    foreach ($button in $page.FindName('OptMotionChoices').Children) {
        $on = $button.Tag -eq $level
        if ($on) {
            $grad = New-Object Windows.Media.LinearGradientBrush
            $grad.StartPoint = New-Object Windows.Point 0, 0; $grad.EndPoint = New-Object Windows.Point 1, 1
            $grad.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#6D43C9')), 0))
            $grad.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#A8326F')), 1))
            $button.Background = $grad
            $button.Foreground = New-SolidBrush '#FFFFFF'
        }
        else { $button.Background = [Windows.Media.Brushes]::Transparent; $button.Foreground = New-SolidBrush '#8C819F' }
    }
    $page.FindName('OptMotionNote').Text = T $(switch ($level) { 'Aus' { 'keine Animationen' } 'Ruhig' { 'langsamer, weniger Glühen' } 'Lebendig' { 'schneller, mehr Glühen' } default { 'Standard' } })
    # der Lichtkopf läuft die Linie entlang; seine Dauer folgt der Stufe, bei "Aus" steht er still
    $line = $ui.OptMotionLine
    $seconds = switch ($level) { 'Ruhig' { 4.0 } 'Lebendig' { 1.5 } default { 2.4 } }
    $run = New-Object Windows.Media.Animation.DoubleAnimation
    $run.From = 18; $run.To = -400
    $run.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($seconds))
    $run.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    Set-IdleFps $run
    if ($level -eq 'Aus') { $line.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $null); $line.StrokeDashOffset = -120 }
    else { $line.BeginAnimation([Windows.Shapes.Shape]::StrokeDashOffsetProperty, $run) }
}

# "Optionen" in der Leiste öffnet die Seite; mit Reiter (z. B. Hintergrund) weiter das Fenster
$script:BentoOpenSettingsSheet = ${function:Open-SettingsSheet}
function Open-SettingsSheet([int]$Tab = -1) {
    if ($Tab -lt 0) {
        if ($script:Dialog) { return }
        if ($script:Sheet) { Close-Sheet -Quick }
        Show-Page 'Options'
        return
    }
    & $script:BentoOpenSettingsSheet $Tab
    # die Seite heißt schon "Optionen": das Fenster trägt den Namen des Links, der es öffnet
    if ($script:Sheet -and $script:Sheet.Title -eq 'Optionen') {
        $script:Sheet.Title = T 'Alle Einstellungen'
        $ui.SheetTitle.Text = $script:Sheet.Title
        Update-BentoCrumbs
    }
}

# --- "Alle Einstellungen" im Kachel-Look ------------------------------------------
# Das Fenster baut seine Zeilen wie gehabt; danach wird jede Zeile zur getönten Kachel mit farbiger Überschrift
# (ohne Symbolkasten), und die Auswahlknöpfe bekommen den Lila-Pink-Verlauf der Optionen-Seite.

$script:BentoChipStyle = [Windows.Markup.XamlReader]::Parse(@'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Setter Property="Foreground" Value="#8C819F"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Button">
                <Grid>
                    <Border x:Name="Back" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="10" Background="#0DFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1"/>
                    <Border x:Name="On" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="10" Opacity="0">
                        <Border.Background>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                <GradientStop Color="#6D43C9" Offset="0"/>
                                <GradientStop Color="#A8326F" Offset="1"/>
                            </LinearGradientBrush>
                        </Border.Background>
                    </Border>
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Back" Property="Background" Value="#1AFFFFFF"/>
                        <Setter Property="Foreground" Value="#E2DCEB"/>
                    </Trigger>
                    <Trigger Property="Tag" Value="on">
                        <Setter TargetName="On" Property="Opacity" Value="1"/>
                        <Setter TargetName="Back" Property="BorderBrush" Value="Transparent"/>
                        <Setter Property="Foreground" Value="White"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
'@)

$script:BentoShowSettingsTab = ${function:Show-SettingsTab}
function Show-SettingsTab {
    & $script:BentoShowSettingsTab
    $tones = 'Lila', 'Beere', 'Indigo', 'Gruen', 'Bernst', 'Rose'
    $i = 0
    foreach ($row in @($ui.SheetPanel.Children)) {
        if ($row -isnot [Windows.Controls.Border] -or -not $row.FindName('Title')) { continue }
        $tone = $tones[$i % $tones.Count]; $i++
        Set-BentoTone $row $tone
        $row.CornerRadius = 18
        $row.Padding = '20,16,20,16'
        $row.Margin = '0,0,0,10'
        $row.FindName('Tile').Visibility = 'Collapsed'
        $title = $row.FindName('Title')
        $title.FontSize = 12.5
        $title.Foreground = New-SolidBrush $script:BentoTones[$tone].C
        $row.FindName('Text').Foreground = New-SolidBrush '#8C819F'
        foreach ($panel in $row.FindName('Below'), $row.FindName('Slot')) {
            foreach ($chip in $panel.Children) {
                if ($chip -is [Windows.Controls.Button] -and $chip.Style -eq $window.FindResource('ChipButton')) { $chip.Style = $script:BentoChipStyle; $chip.Height = 34 }
            }
        }
    }
}

# --- Hardware-Übersicht als Kachelmosaik (Entwurf Q6) --------------------------------
# Acht Kacheln statt der Karten mit Stichpunkten: oben Gruppe und Zustand, dann Name, großer Wert, Balken und eine
# kurze Notiz. Ein Klick öffnet die Detailseite. Die alten Karten bleiben unsichtbar im Baum (der Code pflegt sie weiter).

$bentoHwTileXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="Auto" Height="Auto" Margin="6" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Button.RenderTransform>
        <ScaleTransform ScaleX="0.92" ScaleY="0.92"/>
    </Button.RenderTransform>
    <Grid Margin="4,2,2,0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="Group" FontSize="12" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="State" Grid.Column="1" FontSize="11" Margin="8,1,0,0"/>
        </Grid>
        <TextBlock x:Name="Name" Grid.Row="1" FontSize="16" FontWeight="SemiBold" Foreground="#E2DCEB" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
        <TextBlock x:Name="Value" Grid.Row="3" FontSize="28" FontWeight="SemiBold" Foreground="#E2DCEB" TextTrimming="CharacterEllipsis"/>
        <Grid x:Name="BarBox" Grid.Row="4" Height="6" Margin="0,8,0,0">
            <Border CornerRadius="3" Background="#10FFFFFF"/>
            <Border x:Name="Bar" CornerRadius="3" HorizontalAlignment="Left" Width="0"/>
        </Grid>
        <TextBlock x:Name="Note" Grid.Row="5" FontSize="11.5" Foreground="#8C819F" Margin="0,7,0,0" TextTrimming="CharacterEllipsis"/>
    </Grid>
</Button>
'@

$script:BentoHwDefs = @(
    @{ Group = 'Leistung'; Name = 'Sensoren'; Tone = 'Lila' }
    @{ Group = 'Leistung'; Name = 'Stabilitätstest'; Tone = 'Gruen' }
    @{ Group = 'Speicher & Anzeige'; Name = 'Laufwerke'; Tone = 'Bernst' }
    @{ Group = 'Leistung'; Name = 'Arbeitsspeicher'; Tone = 'Beere' }
    @{ Group = 'Gesundheit'; Name = 'Abstürze'; Tone = 'Gruen' }
    @{ Group = 'Speicher & Anzeige'; Name = 'Bildschirm'; Tone = 'Indigo' }
    @{ Group = 'Gesundheit'; Name = 'Bericht & Diagnose'; Tone = 'Rose' }
    @{ Group = 'System'; Name = 'BIOS'; Tone = 'Grau' }
)

function Set-BentoHardwareBoard {
    $page = $ui.PageHardware
    foreach ($part in @($page.Children)) { $part.Visibility = 'Collapsed' }
    $board = New-Object Windows.Controls.Primitives.UniformGrid
    $board.Columns = 4; $board.Rows = 2
    $board.Margin = New-Object Windows.Thickness -6
    [Windows.Controls.Grid]::SetRowSpan($board, 9)
    [Windows.Controls.Grid]::SetColumnSpan($board, 9)
    [void]$page.Children.Add($board)
    $ui.BentoHwBoard = $board
    $script:BentoHwTiles = @()
    for ($i = 0; $i -lt $script:BentoHwDefs.Count; $i++) {
        $def = $script:BentoHwDefs[$i]
        $tile = [Windows.Markup.XamlReader]::Parse($bentoHwTileXaml)
        $tile.Style = $window.FindResource('TileButton')
        $tile.Width = [double]::NaN; $tile.Height = [double]::NaN
        $tile.Margin = New-Object Windows.Thickness 6
        Set-BentoTone $tile $def.Tone
        $tile.FindName('Group').Text = T $def.Group
        $tile.FindName('Group').Foreground = New-SolidBrush $script:BentoTones[$def.Tone].C
        $tile.FindName('Name').Text = T $def.Name
        $tile.FindName('Value').FontFamily = New-Object Windows.Media.FontFamily $script:BentoMono
        $bar = New-Object Windows.Media.LinearGradientBrush
        $bar.StartPoint = New-Object Windows.Point 0, 0; $bar.EndPoint = New-Object Windows.Point 1, 0
        $bar.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($script:BentoTones[$def.Tone].C)), 0))
        $bar.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#A8326F')), 1))
        $tile.FindName('Bar').Background = $bar
        $tile.FindName('BarBox').Add_SizeChanged({ try { $this.Children[1].Width = $this.ActualWidth * [double]$this.Tag } catch { } })
        $tile.Tag = $i
        $tile.Add_Click({ try { Show-BentoDetail ([int]$this.Tag) } catch { Write-AppError $_ } })
        [void]$board.Children.Add($tile)
        $script:BentoHwTiles += $tile
    }
    # Akku (nur auf Notebooks): eigene Zeile in der Sensoren-Kachel; die alte Zeile hängt an den versteckten Karten.
    # PreviewMouseLeftButtonDown fängt den Klick ab, bevor die Kachel ihn als eigenen Klick nimmt.
    $chip = New-Object Windows.Controls.Border
    $chip.Cursor = 'Hand'; $chip.Padding = '8,3'; $chip.CornerRadius = 8
    $chip.HorizontalAlignment = 'Left'; $chip.VerticalAlignment = 'Center'
    $chip.Background = New-SolidBrush '#14FFFFFF'
    $chipText = New-Object Windows.Controls.TextBlock
    $chipText.FontSize = 11.5
    $chip.Child = $chipText
    [Windows.Controls.Grid]::SetRow($chip, 2)
    $chip.Add_PreviewMouseLeftButtonDown({ param($sender, $e) try { $e.Handled = $true; Open-BatterySheet } catch { Write-AppError $_ } })
    [void]$script:BentoHwTiles[0].Content.Children.Add($chip)
    $script:BentoBatteryChip = @{ Chip = $chip; Text = $chipText }
    Update-BentoHardwareBoard
}

# Werte der acht Kacheln aus dem, was das Programm zuletzt gemessen hat
function Update-BentoHardwareBoard {
    if (-not $script:BentoHwTiles) { return }
    $good = '#8FF0BE'; $warn = '#F6C989'; $bad = '#F08A9C'
    $tone = { param($t) switch ("$t") { 'good' { $good } 'warn' { $warn } 'bad' { $bad } default { '#8C819F' } } }
    $card = { param($name) $script:CardState[$name] }
    $rows = @()
    # 0 Sensoren: letzter Live-Wert der Startseite
    $live = if ($script:HomeLive) { $script:HomeLive[0] } else { $null }
    $temp = if ($live -and $live.History.Count) { [double]$live.History[$live.History.Count - 1] } else { $null }
    $rows += @{ V = $(if ($live -and $live.Text) { $live.Text -replace ' ', '' } else { '–' }); N = $(if ($script:HomeLive -and $script:HomeLive[1].Text) { T "Prozessor $($script:HomeLive[1].Text)" } else { T 'Temperaturen, Lüfter und Auslastung' }); S = 'live'; SC = '#B19FE0'; B = $(if ($null -ne $temp) { $temp / 100 } else { 0 }) }
    # 1 Stabilitätstest
    $s = $script:StressResult
    if ($s -and $s.Title) {
        $top = [Math]::Max([double]$s.MaxGpuTemp, [double]$s.MaxCpuTemp)
        $rows += @{ V = $(if ($top -gt 0) { '{0:N0}°' -f $top } else { '–' }); N = (Format-CardState @{ Text = ("$($s.Title)" -split ' – ')[0]; Date = ("$($s.Time)" -split ' ')[0] }); S = $(if ($s.Tone -eq 'good') { 'ok' } else { 'ansehen' }); SC = (& $tone $s.Tone); B = $top / 100 }
    }
    else { $rows += @{ V = '–'; N = T 'Volllast für Prozessor und Grafikkarte'; S = 'noch offen'; SC = '#8C819F'; B = 0 } }
    # 2 Laufwerke
    $c = & $card 'Drives'
    $free = if ($c -and "$($c.Detail)" -match '·\s*(.+)\s+frei') { $Matches[1] } else { '–' }
    $used = @($c.Bars | Where-Object { "$_" -match '^\w\|\d+$' } | ForEach-Object { [double]("$_" -split '\|')[1] })
    $rows += @{ V = $free; N = $(if ($c) { T "frei · $($c.Detail -replace '\s*·.*$', '')" } else { T 'Zustand, Belegung, Tempo' }); S = $(if ($c) { "$($c.Text)" } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($used.Count) { ($used | Measure-Object -Average).Average / 100 } else { 0 }) }
    # 3 Arbeitsspeicher
    $c = & $card 'Memory'
    $rows += @{ V = $(if ($c -and $c.Size) { "$($c.Size)" } else { '–' }); N = $(if ($c) { T "$($c.Detail)" } else { T 'Riegel, Steckplätze und Takt' }); S = $(if ($c) { $(if ($c.Tone -eq 'good') { 'ok' } else { "$($c.Text)" }) } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($c -and [int]$c.Slots -gt 0) { [int]$c.Used / [int]$c.Slots } else { 0 }) }
    # 4 Abstürze: Tage ohne Absturz
    $c = & $card 'Crashes'
    $days = @($c.Days | ForEach-Object { [int]$_ })
    $quiet = if ($days.Count) { ($days | Measure-Object -Minimum).Minimum } else { 30 }
    $rows += @{ V = $(if ($c) { T "$quiet T" } else { '–' }); N = $(if ($c) { T 'ohne Absturz' } else { T 'Bluescreens und Aussetzer' }); S = $(if ($c) { "$($c.Text)" } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($c) { $quiet / 30 } else { 0 }) }
    # 5 Bildschirm
    $c = & $card 'Displays'
    $rows += @{ V = $(if ($c) { ("$($c.Detail)" -split ' · ')[0] } else { '–' }); N = $(if ($c) { T "$($c.Detail)" } else { T 'Bildwiederholrate und Testbilder' }); S = $(if ($c) { $(if ($c.Tone -eq 'good') { 'ok' } else { "$($c.Text)" }) } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($c) { 1 } else { 0 }) }
    # 6 Bericht & Diagnose
    $c = & $card 'Report'
    $okN = if ($c -and "$($c.Detail)" -match '(\d+) gut') { [int]$Matches[1] } else { 0 }
    $all = if ($c) { @([regex]::Matches("$($c.Detail)", '(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum } else { 0 }
    $rows += @{ V = $(if ($all) { "$okN/$all" } else { '–' }); N = $(if ($c) { T 'als ZIP speichern' } else { T 'Prüfbericht und Diagnose in einem' }); S = $(if ($c) { "$($c.Text)" } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($all) { $okN / $all } else { 0 }) }
    # 7 BIOS
    $c = & $card 'Bios'
    $ver = if ($c -and "$($c.Detail)" -match '^(.+) vom ') { $Matches[1] } else { '–' }
    $rows += @{ V = $ver; N = $(if ($c) { T "$($c.Text)" } else { T 'Version, Alter und Hersteller' }); S = $(if ($c) { $(if ($c.Tone -eq 'good') { 'ok' } else { 'alt' }) } else { 'noch offen' }); SC = (& $tone $c.Tone); B = $(if ($c) { 1 } else { 0 }) }

    for ($i = 0; $i -lt $script:BentoHwTiles.Count; $i++) {
        $tile = $script:BentoHwTiles[$i]; $r = $rows[$i]
        $value = $tile.FindName('Value')
        $value.Text = "$($r.V)"
        $value.FontSize = if ("$($r.V)".Length -gt 8) { 20 } else { 28 }
        $tile.FindName('Note').Text = "$($r.N)"
        $tile.FindName('State').Text = T "$($r.S)"
        $tile.FindName('State').Foreground = New-SolidBrush $r.SC
        $box = $tile.FindName('BarBox')
        $box.Tag = [Math]::Max(0.0, [Math]::Min(1.0, [double]$r.B))
        $box.Visibility = if ([double]$r.B -gt 0) { 'Visible' } else { 'Hidden' }
        if ($box.ActualWidth -gt 0) { $box.Children[1].BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-DoubleAnim -To ($box.ActualWidth * [double]$box.Tag) -Ms 600 -Ease $script:EaseOut)) }
    }
    if ($script:BentoBatteryChip) {
        $script:BentoBatteryChip.Chip.Visibility = if ($script:HasBattery) { 'Visible' } else { 'Collapsed' }
        $b = & $card 'Battery'
        $script:BentoBatteryChip.Text.Text = if ($b -and $b.Text) { T "Akku $($b.Text) · ansehen" } else { T 'Akku ansehen' }
        $script:BentoBatteryChip.Text.Foreground = New-SolidBrush $(if ($b) { & $tone $b.Tone } else { '#B19FE0' })
    }
}

# Die Kacheln kommen als Welle von oben links nach unten rechts (statt der alten Karten)
function Show-HardwareCards {
    Update-BentoHardwareBoard
    if (-not $script:BentoHwTiles) { return }
    $i = 0
    foreach ($tile in $script:BentoHwTiles) {
        $delay = 110 + 70 * (($i % 4) + [Math]::Floor($i / 4))
        if ($script:Settings.Animations) {
            $tile.BeginAnimation($P.Opacity, $null); $tile.Opacity = 0
            Start-Fade $tile 1 320 $delay
        }
        else { $tile.Opacity = 1; $tile.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 1 }
        $i++
    }
}

$script:BentoUpdateHardwareBadges = ${function:Update-HardwareBadges}
function Update-HardwareBadges { & $script:BentoUpdateHardwareBadges; Update-BentoHardwareBoard }

# Die Boost-Kacheln folgen dem Zustand, dem Arbeitsspeicher und dem Gaming-Check
$script:BentoUpdateBoost = ${function:Update-Boost}
function Update-Boost { & $script:BentoUpdateBoost; Update-BentoBoostFacts }
$script:BentoSetRamNumbers = ${function:Set-RamNumbers}
function Set-RamNumbers([double]$Used, [double]$TotalGb) {
    & $script:BentoSetRamNumbers $Used $TotalGb
    $first = -not $script:BentoRamTotal
    $script:BentoRamTotal = $TotalGb
    if ($first) { Update-BentoBoostFacts }
    if ($script:BentoBoostFacts) { $script:BentoBoostFacts['Ram'].FindName('Value').Text = $ui.RamFree.Text }
}
$script:BentoUpdateGameCheckPill = ${function:Update-GameCheckPill}
function Update-GameCheckPill { & $script:BentoUpdateGameCheckPill; Update-BentoBoostFacts }

# Beim Einschalten erzählt die Überschrift die Schritte, die Kacheln leuchten nacheinander auf (wie im Entwurf)
function Start-BentoBoostSteps {
    if (-not $script:Settings.Animations -or -not $ui.BentoBoostHead) { return }
    $steps = @(
        @{ At = 0; Text = 'Boost startet …'; Tile = $null }
        @{ At = 460; Text = 'Energieplan auf Höchstleistung …'; Tile = 'Plan' }
        @{ At = 1035; Text = 'Arbeitsspeicher wird frei …'; Tile = 'Ram' }
        @{ At = 1495; Text = 'Dienste werden pausiert …'; Tile = 'Services' }
        @{ At = 1955; Text = 'Programme werden beendet …'; Tile = 'Apps' }
        @{ At = 2350; Text = 'Volle Leistung fürs Spiel'; Tile = $null }
    )
    foreach ($step in $steps) {
        Invoke-Later $step.At {
            param($s)
            if (-not $script:BoostOn) { return }
            $ui.BentoBoostHead.Text = T $s.Text
            if ($s.Tile -and $script:BentoBoostFacts) { Show-BentoPulse $script:BentoBoostFacts[$s.Tile] '#8C6BD6' }
        } $step
    }
}

Set-BentoHome
Set-BentoTools
Set-BentoHardware
Set-BentoDetailShell
Set-BentoHardwareBoard
Set-BentoBoost
Set-BentoOptions
Update-BentoCrumbs
