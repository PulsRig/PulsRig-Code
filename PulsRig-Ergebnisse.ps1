# PulsRig - Ergebnisse des Scans: die Liste mit neueren Treibern, Hinweisen und aktuellen Treibern.
# Wird von PulsRig.ps1 eingebunden und nutzt dessen Fenster ($window, $ui) und Helfer.

$rowXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,0,8" Padding="14,11" CornerRadius="14" Background="#0AFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Opacity="0">
    <Border.RenderTransform>
        <TranslateTransform Y="18"/>
    </Border.RenderTransform>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <!-- angekreuzte Zeilen sind in der Akzentfarbe hinterlegt -->
        <Border x:Name="On" Grid.ColumnSpan="5" Margin="-15,-12" CornerRadius="14" Background="#1422D3EE" BorderBrush="#5922D3EE" BorderThickness="1" Opacity="0" IsHitTestVisible="False"/>
        <CheckBox x:Name="Check" Style="{DynamicResource Check}" VerticalAlignment="Center" Margin="2,0,12,0" Visibility="Collapsed"/>
        <Grid x:Name="IconBox" Grid.Column="1" Width="40" Height="40" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5">
            <Grid.RenderTransform>
                <ScaleTransform/>
            </Grid.RenderTransform>
            <Border x:Name="IconBack" CornerRadius="12" Opacity="0.16"/>
            <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <StackPanel Grid.Column="2" Margin="14,0,12,0" VerticalAlignment="Center">
            <TextBlock x:Name="Title" FontSize="14" FontWeight="SemiBold" Foreground="#E8EEFC" TextWrapping="Wrap"/>
            <TextBlock x:Name="Sub" FontSize="12" Foreground="#93A3C7" Margin="0,3,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <StackPanel Grid.Column="3" VerticalAlignment="Center" Margin="0,0,4,0">
            <Border x:Name="Badge" CornerRadius="9" Padding="9,3" HorizontalAlignment="Right" Background="#14FFFFFF">
                <TextBlock x:Name="BadgeText" FontSize="11" FontWeight="SemiBold" Foreground="#93A3C7"/>
            </Border>
            <TextBlock x:Name="Meta" FontSize="11.5" Foreground="#5E6E93" HorizontalAlignment="Right" Margin="0,4,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="Action" Style="{DynamicResource GhostButton}" VerticalAlignment="Center" Margin="10,0,0,0" Visibility="Collapsed"/>
            <Button x:Name="More" Style="{DynamicResource TitleButton}" Content="&#xE712;" FontSize="14" Width="34" Height="34" Margin="6,0,-4,0" Visibility="Collapsed"/>
        </StackPanel>
    </Grid>
</Border>
'@
$rowXaml = ConvertTo-ThemedXaml $rowXaml

# "vom 18.07.2026"; Platzhalter wie Intels 18.07.1968 (auch aus älteren gespeicherten Scans) und fehlende Daten als "ohne Datum"
function Get-DateLabel([string]$Date) {
    if (-not $Date -or $Date -eq '-' -or ($Date -match '^\d\d\.\d\d\.(\d{4})$' -and [int]$Matches[1] -lt 1990)) { return 'ohne Datum' }
    if ($Date -match '^\d\d\.\d\d\.\d{4}$') { "vom $Date" } else { $Date }
}

function Get-ClassGlyph([string]$Class) {
    switch -Regex ($Class) {
        'Display' { return Get-Glyph 0xE7F4 }
        'Net' { return Get-Glyph 0xE839 }
        'MEDIA|Audio' { return Get-Glyph 0xE767 }
        'USB' { return Get-Glyph 0xE88E }
        'Keyboard' { return Get-Glyph 0xE765 }
        'Mouse|HID' { return Get-Glyph 0xE962 }
        'Bluetooth' { return Get-Glyph 0xE702 }
        'Print' { return Get-Glyph 0xE749 }
        'Firmware' { return Get-Glyph 0xE950 }
        default { return Get-Glyph 0xE772 }
    }
}

$script:RowIndex = 0
$script:UpdateRows = @()

# Überschrift eines Abschnitts mit farbigem Strich davor, wie auf der Werkzeuge-Seite
function Add-SectionTitle([string]$Text) {
    $Text = T $Text
    $title = New-Object Windows.Controls.StackPanel
    $title.Orientation = 'Horizontal'
    $title.Margin = '2,10,0,9'
    $bar = New-Object Windows.Controls.Border
    $bar.Width = 3; $bar.Height = 14; $bar.CornerRadius = (Get-SkinRadius 1.5); $bar.Margin = '0,0,9,0'
    $bar.Background = $window.FindResource('AccentGrad')
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text.ToUpper()
    $label.FontSize = 10.5
    $label.FontWeight = 'SemiBold'
    Set-Paint $label 'Foreground' 'TextFaint'
    [void]$title.Children.Add($bar)
    [void]$title.Children.Add($label)
    $title.Opacity = 0
    # die Überschrift kommt kurz vor ihrer ersten Zeile, der farbige Strich wächst dabei aus der Mitte
    $index = [Math]::Min($script:RowIndex, 12)
    $delay = [Math]::Max(0, [int](60 * $index + 1.5 * $index * $index) - 40)
    Start-Fade $title 1 300 $delay
    $bar.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $bar.RenderTransform = New-Object Windows.Media.ScaleTransform
    $bar.RenderTransform.BeginAnimation($P.ScaleY, (New-DoubleAnim -From 0 -To 1 -Ms 420 -Delay $delay -Ease $script:EaseBack))
    [void]$ui.ResultList.Children.Add($title)
    $title
}

# Schild in der Übersicht über der Ergebnisliste: farbiger Punkt und Text
function Add-ResultChip([string]$Text, [string]$Key, $Panel = $ui.ResultChips) {
    $Text = T $Text
    $chip = New-Object Windows.Controls.Border
    $chip.CornerRadius = (Get-SkinRadius 9)
    $chip.Padding = '10,5,12,5'
    $chip.Margin = '0,0,8,0'
    $chip.BorderThickness = 1
    $chip.Background = New-Brush '#0FFFFFFF'
    $chip.BorderBrush = New-Brush '#1FFFFFFF'
    $line = New-Object Windows.Controls.StackPanel
    $line.Orientation = 'Horizontal'
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 7; $dot.Height = 7
    $dot.VerticalAlignment = 'Center'
    $dot.Margin = '0,1,8,0'
    Set-Paint $dot 'Fill' $Key
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.FontSize = 12
    Set-Paint $label 'Foreground' 'Text'
    [void]$line.Children.Add($dot)
    [void]$line.Children.Add($label)
    $chip.Child = $line
    # die Schilder springen nacheinander auf
    $delay = 120 + 70 * $Panel.Children.Count
    $chip.Opacity = 0
    $chip.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $chip.RenderTransform = New-Object Windows.Media.ScaleTransform
    Start-Fade $chip 1 260 $delay 0
    Start-Scale $chip 1 420 $delay 0.8 $script:EaseBack
    [void]$Panel.Children.Add($chip)
}

# Eine Ergebniszeile; die Zeilen gleiten nacheinander von unten herein
function Add-Row {
    param([string]$Glyph, [string]$Title, [string]$Sub, [string]$Badge, [string]$BadgeKind = 'TextDim', [string]$Meta,
        [switch]$Checkable, [bool]$Checked = $true, [string]$ActionText, $ActionTag, [string]$IconKind = 'Accent',
        # Menu: Einträge für das Aufklappmenü; Compact: flachere Zeile für die lange Liste der aktuellen Treiber
        $Menu, [switch]$Compact)
    $Title = T $Title; $Sub = T $Sub; $Badge = T $Badge; $Meta = T $Meta; $ActionText = T $ActionText
    $row = [Windows.Markup.XamlReader]::Parse($rowXaml)
    $row.FindName('Glyph').Text = $Glyph
    Set-Paint $row.FindName('Glyph') 'Foreground' $IconKind
    Set-Paint $row.FindName('IconBack') 'Background' $IconKind
    $row.FindName('Title').Text = $Title
    $row.FindName('Sub').Text = $Sub
    $row.FindName('Meta').Text = $Meta
    # Text, in dem das Suchfeld sucht
    $row.Tag = "$Title $Sub $Badge".ToLower()
    if ($Badge) {
        $row.FindName('BadgeText').Text = $Badge
        Set-Paint $row.FindName('BadgeText') 'Foreground' $BadgeKind
    }
    else { $row.FindName('Badge').Visibility = 'Collapsed' }
    if ($Compact) {
        $row.Padding = '14,7'
        $row.Margin = '0,0,0,6'
        $row.FindName('Title').FontWeight = 'Normal'
    }
    if ($Menu) {
        $more = $row.FindName('More')
        $more.Tag = $Menu
        $more.Uid = $Title        # steht als Überschrift im Aufklappmenü
        $more.Visibility = 'Visible'
        $more.Add_Click({ try { Show-RowMenu $this } catch { Write-AppError $_ } })
    }
    $check = $row.FindName('Check')
    if ($Checkable) {
        $check.Visibility = 'Visible'
        $check.IsChecked = $Checked
        # die farbige Hinterlegung der Zeile folgt dem Haken
        $check.Tag = $row.FindName('On')
        $check.Tag.Opacity = [int]$Checked
        $check.DataContext = $row.FindName('IconBox')
        # die Hinterlegung blendet weich um, das Symbol nickt beim Ankreuzen kurz
        $check.Add_Click({
                try {
                    $on = [bool]$this.IsChecked
                    Start-Fade $this.Tag ([int]$on) $(if ($on) { 180 } else { 260 })
                    if ($on) { Start-Scale $this.DataContext 1 420 0 0.8 $script:EaseBack }
                    Update-UpdateButton
                }
                catch { Write-AppError $_ }
            })
    }
    # unter der Maus tritt das Symbolfeld der Zeile hervor
    $row.Add_MouseEnter({ try { Start-Fade $this.FindName('IconBack') 0.3 160 } catch { Write-AppError $_ } })
    $row.Add_MouseLeave({ try { Start-Fade $this.FindName('IconBack') 0.16 280 } catch { Write-AppError $_ } })
    if ($ActionText) {
        $action = $row.FindName('Action')
        $action.Content = $ActionText
        $action.Tag = $ActionTag
        $action.Visibility = 'Visible'
        $action.Add_Click({ Invoke-RowAction $this.Tag })
    }
    if ($script:RowIndex -lt 12) {
        # die ersten Zeilen dicht hintereinander, nach unten hin mit wachsendem Abstand - die Welle läuft aus
        $delay = [int](60 * $script:RowIndex + 1.5 * $script:RowIndex * $script:RowIndex)
        Start-Fade $row 1 340 $delay
        Start-Slide $row 0 480 $delay
        # das Symbol federt in jeder Zeile nach, das Schild rechts blendet etwas später ein
        Start-Scale $row.FindName('IconBox') 1 650 $delay 0.5 $script:EaseElastic
        if ($Badge) {
            $row.FindName('Badge').Opacity = 0
            Start-Fade $row.FindName('Badge') 1 320 ($delay + 180)
        }
    }
    else {
        # weiter unten liegende Zeilen sind beim Hereingleiten ohnehin nicht zu sehen
        $row.Opacity = 1
        $row.RenderTransform.Y = 0
    }
    $script:RowIndex++
    [void]$ui.ResultList.Children.Add($row)
    $check
}

function Invoke-RowAction($Tag) {
    try {
        switch ($Tag.Kind) {
            'url' { Open-WebLink $Tag.Value }
            'tool' { Open-ToolDialog $Tag.Value }
            'details' { Open-DetailSheet $Tag.Value }
            'export' { Open-ExportDialog $Tag.Value }
            'ignore' { Add-Ignored $Tag.Value }
        }
    }
    catch { Write-AppError $_ }
}

# Aufklappmenü unter dem Knopf mit den drei Punkten
function Show-RowMenu($Button) {
    $ui.RowMenuItems.Children.Clear()
    $ui.RowMenuTitle.Text = $Button.Uid
    foreach ($entry in @($Button.Tag)) {
        $item = New-Object Windows.Controls.Button
        $item.Style = $window.FindResource('PopupButton')
        $item.Tag = Get-Glyph $entry.Glyph
        $item.Content = T $($entry.Text)
        $item.DataContext = $entry
        # "Ignorieren" nimmt etwas aus der Liste: sein Symbol ist gelb statt in der Akzentfarbe
        if ($entry.Kind -eq 'ignore') { Set-Paint $item 'BorderBrush' 'Warn' }
        $item.Add_Click({
                $ui.RowMenu.IsOpen = $false
                Invoke-RowAction $this.DataContext
            })
        [void]$ui.RowMenuItems.Children.Add($item)
    }
    $ui.RowMenu.PlacementTarget = $Button
    $ui.RowMenu.IsOpen = $true
    # das Menü klappt aus der Ecke am Knopf auf, die Einträge rücken nacheinander nach
    Start-Fade $ui.RowMenuCard 1 150 0 0
    Start-Scale $ui.RowMenuCard 1 320 0 0.82 $script:EaseBack
    if ($script:Settings.Animations) {
        $index = 0
        foreach ($item in $ui.RowMenuItems.Children) {
            $delay = 70 + 45 * $index
            $item.RenderTransform = New-Object Windows.Media.TranslateTransform
            $item.Opacity = 0
            Start-Fade $item 1 220 $delay
            $item.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From 12 -To 0 -Ms 320 -Delay $delay))
            $index++
        }
    }
}

# Blendet in den Ergebnissen alles aus, was nicht zum Suchtext passt
function Update-ResultFilter {
    $text = $ui.ResultSearch.Text.Trim().ToLower()
    $ui.ResultSearchHint.Visibility = if ($ui.ResultSearch.Text) { 'Collapsed' } else { 'Visible' }
    $title = $null
    foreach ($child in $ui.ResultList.Children) {
        if ($child -isnot [Windows.Controls.Border]) {
            # Überschrift eines Abschnitts: bleibt nur stehen, wenn darunter eine Zeile passt
            $title = $child
            $title.Visibility = if ($text) { 'Collapsed' } else { 'Visible' }
            continue
        }
        $match = -not $text -or "$($child.Tag)".Contains($text)
        # Zeilen, die durch die Suche wieder auftauchen, blenden kurz ein statt hereinzuspringen
        if ($match -and $child.Visibility -ne 'Visible') { Start-Fade $child 1 200 0 0 }
        $child.Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
        if ($match -and $title) { $title.Visibility = 'Visible' }
    }
}

function Test-Ignored([string]$Key) {
    [bool]($script:Settings.Ignored | Where-Object { $_.Key -eq $Key })
}

function Add-Ignored($Entry) {
    if (-not (Test-Ignored $Entry.Key)) {
        $script:Settings.Ignored = @($script:Settings.Ignored) + @{ Key = "$($Entry.Key)"; Name = "$($Entry.Name)" }
        Save-Settings
    }
    if ($script:LastResult) { Show-Results $script:LastResult }
}

function Update-UpdateButton {
    $selected = @($script:UpdateRows | Where-Object { $_.Check.IsChecked }).Count
    if (-not $script:IsAdmin) {
        $ui.BtnUpdateAll.Content = T $('Als Admin neu starten')
        $ui.BtnUpdateAll.IsEnabled = $script:UpdateRows.Count -gt 0
        $ui.BtnUpdateAll.Visibility = if ($script:UpdateRows.Count -gt 0) { 'Visible' } else { 'Collapsed' }
        return
    }
    $ui.BtnUpdateAll.Visibility = if ($script:UpdateRows.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $ui.BtnUpdateAll.IsEnabled = $selected -gt 0
    $ui.BtnUpdateAll.Content = T $(if ($selected -gt 0) { "$selected ausgewählte aktualisieren" } else { 'Nichts ausgewählt' })
}

# Baut die nächsten Zeilen der Liste "Aktuell"; der Nachrichtentakt ruft das auf, bis alle stehen
$script:CurrentBuild = $null
function Step-CurrentRows {
    $build = $script:CurrentBuild
    if (-not $build) { return }
    $end = [Math]::Min($build.Index + 12, $build.Items.Count)
    for ($i = $build.Index; $i -lt $end; $i++) {
        $driver = $build.Items[$i]
        $title = if ($driver.Count -gt 1) { "$($driver.Name)   ×$($driver.Count)" } else { $driver.Name }
        $menu = @(@{ Text = 'Einzelheiten anzeigen'; Glyph = 0xE946; Kind = 'details'; Value = $driver })
        if ($driver.Catalog) { $menu += @{ Text = 'Im Microsoft-Katalog suchen'; Glyph = 0xE721; Kind = 'url'; Value = $driver.Catalog } }
        if ($driver.Inf -like 'oem*.inf') { $menu += @{ Text = 'Diesen Treiber sichern'; Glyph = 0xE74E; Kind = 'export'; Value = $driver } }
        $hinted = $build.Hinted -contains $driver.Name
        [void](Add-Row -Glyph (Get-ClassGlyph $driver.Class) -IconKind 'TextDim' -Title $title -Sub "$($driver.Provider) · Version $($driver.Version)" `
                -Badge $(if ($hinted) { 'Hinweis im Katalog' } elseif ($build.Unchecked) { 'nicht geprüft' } else { 'aktuell' }) `
                -BadgeKind $(if ($hinted) { 'Warn' } elseif ($build.Unchecked) { 'TextDim' } else { 'Good' }) `
                -Meta (Get-DateLabel "$($driver.Date)") -Menu $menu -Compact)
    }
    $build.Index = $end
    if ($end -ge $build.Items.Count) { $script:CurrentBuild = $null }
    if ($ui.ResultSearch.Text) { Update-ResultFilter }
}

function Show-Results($Data) {
    Add-MemTrace "Scan-Ergebnis: $(@($Data.Drivers).Count) Treiber, $(@($Data.Updates).Count) neuere"
    $ui.ResultList.Children.Clear()
    $script:RowIndex = 0
    $script:UpdateRows = @()
    $script:CurrentBuild = $null
    # Firmware lässt sich in den Einstellungen ausblenden, einzelne Aktualisierungen über "Ignorieren"
    $updates = @($Data.Updates | Where-Object { $_ -and ($script:Settings.Firmware -or -not $_.Firmware) -and -not (Test-Ignored "wu:$($_.Key)|$($_.Title)") })
    $hints = @($Data.Hints)
    $problems = @($Data.Problems)
    $nvidiaNew = $Data.Nvidia -and $Data.Nvidia.IsNewer -and -not (Test-Ignored "nvidia:$($Data.Nvidia.Latest)")
    $count = $updates.Count + [int][bool]$nvidiaNew
    # der Chipsatz-Treiber von AMD ist ein Hinweis: er zählt nicht zu den Treibern, die das Programm selbst lädt
    $amd = $Data.Amd
    $amdNew = [bool]($amd -and $amd.IsNewer -and -not (Test-Ignored "amd:$($amd.Latest)"))

    if ($count -gt 0) {
        [void](Add-SectionTitle "Neuere Treiber ($count)")
        if ($nvidiaNew) {
            $n = $Data.Nvidia
            $title = "{0} {1} {2}" -f ($n.Gpu -replace '^NVIDIA\s+', 'NVIDIA '), $n.Kind, $n.Latest
            $menu = @(@{ Text = 'Diese Version ignorieren'; Glyph = 0xE8D8; Kind = 'ignore'; Value = @{ Key = "nvidia:$($n.Latest)"; Name = $title } })
            $check = Add-Row -Glyph (Get-Glyph 0xE7F4) -Title $title `
                -Sub "installiert $($n.Installed)  →  neu $($n.Latest) vom $($n.Released)" -Badge 'direkt von NVIDIA' -BadgeKind 'Good' -Meta $n.Size -Checkable -Menu $menu
            $script:UpdateRows += @{ Check = $check; Kind = 'nvidia'; Title = $title }
        }
        foreach ($update in $updates) {
            $badge = if ($update.Firmware) { 'Firmware' } elseif ($update.Optional) { 'optional' } else { 'Windows Update' }
            $badgeKind = if ($update.Firmware) { 'Warn' } elseif ($update.Optional) { 'TextDim' } else { 'Accent' }
            $sub = if ($update.Installed) { "installiert $($update.Installed)  →  neu vom $($update.NewDate)" }
            elseif ($update.Device) { "für $($update.Device) · neu vom $($update.NewDate)" } else { "neu vom $($update.NewDate)" }
            # Anzeige mit übersetzter Geräteart; der Schlüssel zum Ignorieren bleibt der Titel von Windows Update
            $shown = if ($update.Name) { $update.Name } else { $update.Title }
            $menu = @(@{ Text = 'Diese Aktualisierung ignorieren'; Glyph = 0xE8D8; Kind = 'ignore'; Value = @{ Key = "wu:$($update.Key)|$($update.Title)"; Name = $update.Title } })
            # Firmware nur auf ausdrücklichen Wunsch: der Haken ist anfangs aus
            $check = Add-Row -Glyph (Get-ClassGlyph $update.Class) -Title $shown -Sub $sub -Badge $badge -BadgeKind $badgeKind -Meta $update.Size `
                -Checkable -Checked (-not $update.Firmware) -Menu $menu
            $script:UpdateRows += @{ Check = $check; Kind = 'wu'; Id = $update.Id; Title = $update.Title }
        }
    }
    if ($problems.Count -gt 0) {
        [void](Add-SectionTitle 'Geräte mit Fehlern')
        # namenlose Geräte ohne Treiber, die zum Chipsatz gehören: die Ursache und den Weg zum Treiber voranstellen
        $chipset = @($problems | Where-Object { $_.Chipset })
        if ($chipset.Count -gt 0) {
            # kurz halten: die Zeile darf neben Marke und Knopf nicht abgeschnitten werden
            $what = if ($chipset.Count -eq 1) { 'Betrifft 1 Gerät' } else { "Betrifft $($chipset.Count) Geräte" }
            $where = if ($Data.Board) { "Treiber für $($Data.Board.Name)" } else { 'Treiber vom Hersteller des Mainboards' }
            if (@($chipset | Where-Object { $_.Catalog }).Count -gt 0) {
                # der Microsoft-Katalog hat ihn: das Werkzeug installiert ihn auf Bestätigung, ein Paket deckt meist alle Geräte ab
                [void](Add-Row -Glyph (Get-Glyph 0xE950) -IconKind 'Warn' -Title 'Der Chipsatz-Treiber fehlt' -Sub "$what · Treiber im Microsoft-Katalog gefunden" `
                        -Badge 'Ursache' -BadgeKind 'Warn' -ActionText 'Installieren' -ActionTag @{ Kind = 'tool'; Value = 'FixDevices' })
            }
            elseif ($Data.Board) {
                [void](Add-Row -Glyph (Get-Glyph 0xE950) -IconKind 'Warn' -Title 'Der Chipsatz-Treiber fehlt' -Sub "$what · $where" `
                        -Badge 'Ursache' -BadgeKind 'Warn' -ActionText 'Treiber suchen' -ActionTag @{ Kind = 'url'; Value = $Data.Board.Url })
            }
            else { [void](Add-Row -Glyph (Get-Glyph 0xE950) -IconKind 'Warn' -Title 'Der Chipsatz-Treiber fehlt' -Sub "$what · $where" -Badge 'Ursache' -BadgeKind 'Warn') }
        }
        foreach ($problem in $problems) {
            [void](Add-Row -Glyph (Get-Glyph 0xE7BA) -IconKind 'Bad' -Title $problem.Name -Sub "$($problem.Text) (Code $($problem.Code))$(if ($problem.Catalog) { " · im Microsoft-Katalog: $($problem.Catalog)" })" `
                    -Badge $(if ($problem.Chipset) { 'Chipsatz-Treiber' } else { $problem.Advice }) -BadgeKind 'Warn' -ActionText 'Beheben' -ActionTag @{ Kind = 'tool'; Value = 'FixDevices' })
        }
    }
    # Intel-Systeme: Chipsatz, Grafik und WLAN von Intel lassen sich nicht direkt abfragen - Hinweis auf Intels Assistenten
    $intelHint = [bool]($Data.Intel -and -not (Test-Ignored 'intel:assistent'))
    $radeonHint = [bool]($Data.Radeon -and -not (Test-Ignored 'amd:grafik'))
    if ($hints.Count -gt 0 -or $amdNew -or $intelHint -or $radeonHint) {
        [void](Add-SectionTitle $(if ($amdNew -or $intelHint -or $radeonHint) { 'Hinweise der Hersteller und aus dem Microsoft-Katalog (werden nicht automatisch geladen)' } else { 'Hinweise aus dem Microsoft-Katalog (werden nicht automatisch geladen)' }))
        if ($intelHint) {
            $title = 'Intel: Chipsatz, Grafik und WLAN'
            $menu = @(@{ Text = 'Diesen Hinweis nicht mehr zeigen'; Glyph = 0xE8D8; Kind = 'ignore'; Value = @{ Key = 'intel:assistent'; Name = $title } })
            [void](Add-Row -Glyph (Get-Glyph 0xE950) -IconKind 'TextDim' -Title $title -Sub 'Das prüft Intels eigener Assistent, nicht PulsRig' `
                    -Badge 'Hinweis' -ActionText 'Bei Intel prüfen' -ActionTag @{ Kind = 'url'; Value = 'https://www.intel.de/content/www/de/de/support/detect.html' } -Menu $menu)
        }
        if ($radeonHint) {
            $title = 'AMD: Grafiktreiber für Radeon'
            $menu = @(@{ Text = 'Diesen Hinweis nicht mehr zeigen'; Glyph = 0xE8D8; Kind = 'ignore'; Value = @{ Key = 'amd:grafik'; Name = $title } })
            [void](Add-Row -Glyph (Get-Glyph 0xE7F4) -IconKind 'TextDim' -Title $title -Sub 'Das prüft AMDs eigene Software, nicht PulsRig' `
                    -Badge 'Hinweis' -ActionText 'Bei AMD prüfen' -ActionTag @{ Kind = 'url'; Value = 'https://www.amd.com/de/support/download/drivers.html' } -Menu $menu)
        }
        if ($amdNew) {
            $title = "AMD Chipsatz-Treiber $($amd.Latest)"
            $sub = "für $($amd.Chipset) und $($amd.Cpu -replace '\s+\d+-Core Processor$', '') · " + $(if ($amd.Installed) { "installiert $($amd.Installed)" } else { 'noch nicht installiert' })
            $menu = @(@{ Text = 'Diese Version ignorieren'; Glyph = 0xE8D8; Kind = 'ignore'; Value = @{ Key = "amd:$($amd.Latest)"; Name = $title } })
            [void](Add-Row -Glyph (Get-Glyph 0xE950) -IconKind 'Warn' -Title $title -Sub $sub -Badge $(if ($amd.Released) { "vom $($amd.Released)" } else { 'direkt von AMD' }) -BadgeKind 'Warn' -Meta $amd.Size `
                    -ActionText 'Bei AMD ansehen' -ActionTag @{ Kind = 'url'; Value = $amd.Url } -Menu $menu)
        }
        foreach ($hint in $hints) {
            # kurz halten, damit die Zeile nicht abgeschnitten wird: nur die Version, das Datum steht in den Einzelheiten des Treibers
            # gilt ein Hinweis für mehrere Geräte, steht nur das erste da und wie viele es noch sind
            $names = @("$($hint.Device)" -split ', ' | Where-Object { $_ })
            $for = if ($names.Count -gt 1) { "$($names[0]) und $($names.Count - 1) $(if ($names.Count -eq 2) { 'weiteres' } else { 'weitere' })" } else { "$($hint.Device)" }
            $sub = "für $for · installiert $($hint.Installed -replace '\s+vom\s.*$', '')"
            if ($hint.NoCode) { $sub += ' · enthält keinen Treibercode' }
            [void](Add-Row -Glyph (Get-Glyph 0xE946) -IconKind 'TextDim' -Title $hint.Title -Sub $sub -Badge (Get-DateLabel "$($hint.Date)") -Meta $hint.Size `
                    -ActionText 'Im Katalog ansehen' -ActionTag @{ Kind = 'url'; Value = $hint.Url })
        }
    }
    if ($count -eq 0 -and $problems.Count -eq 0 -and $hints.Count -eq 0 -and -not $amdNew -and -not $intelHint) {
        [void](Add-Row -Glyph (Get-Glyph 0xE73E) -IconKind 'Good' -Title 'Alle Treiber sind auf dem neuesten Stand' `
                -Sub "$($Data.Devices) Geräte geprüft, davon $($Data.ThirdParty) mit Treibern von Drittherstellern")
    }

    # Alle übrigen Treiber: Dritthersteller zuerst. Die Zeilen entstehen portionsweise, damit das Fenster flüssig bleibt.
    # Geräte, für die oben eine Aktualisierung steht, gehören nicht in diese Liste.
    $updateKeys = @($updates | ForEach-Object { "$($_.Key)".ToUpper() } | Where-Object { $_ })
    $drivers = @($Data.Drivers | Where-Object {
            if (-not $_) { return $false }
            if ($nvidiaNew -and $_.Class -eq 'Display' -and $_.Name -match 'NVIDIA') { return $false }
            $id = "$($_.HardwareId)".ToUpper()
            -not ($id -and ($updateKeys | Where-Object { $id -eq $_ -or $id.StartsWith("$_&") }))
        })
    # bei AMD geprüft und aktuell: das Paket steht mit in der Liste, damit zu sehen ist, dass es geprüft wurde
    if ($amd -and $amd.Installed -and -not $amd.IsNewer) {
        $drivers += @{ Name = "AMD Chipsatz-Treiber (Paket für $($amd.Chipset))"; Class = 'System'; Version = $amd.Installed; Date = $(if ($amd.Installed -eq $amd.Latest -and $amd.Released) { $amd.Released } else { 'AMD geprüft' })
            Provider = 'direkt bei AMD geprüft'; Inf = ''; HardwareId = ''; Signer = ''; Count = 1; ThirdParty = $true; Catalog = $amd.Url }
    }
    if ($script:Settings.ShowCurrent -and $drivers.Count -gt 0) {
        $sorted = @($drivers | Sort-Object @{ Expression = { -not $_.ThirdParty } }, @{ Expression = { $_.Name } })
        [void](Add-SectionTitle $(if ($Data.SearchError) { "Installiert ($($sorted.Count)) – nicht geprüft" } else { "Aktuell ($($sorted.Count)) – kein neuerer Treiber gefunden" }))
        $script:CurrentBuild = @{ Items = $sorted; Index = 0; Unchecked = [bool]$Data.SearchError; Hinted = @($hints | ForEach-Object { $_.Device -split ', ' }) }
        Step-CurrentRows
    }
    $ui.ResultSearch.Text = ''
    Update-ResultFilter

    # Übersicht in Zahlen
    $ui.ResultChips.Children.Clear()
    if ($count -gt 0) { Add-ResultChip $(if ($count -eq 1) { '1 neuerer Treiber' } else { "$count neuere Treiber" }) 'Warn' }
    if ($problems.Count -gt 0) { Add-ResultChip "$($problems.Count) Gerätefehler" 'Bad' }
    $hintCount = $hints.Count + [int]$amdNew + [int]$intelHint + [int]$radeonHint
    if ($hintCount -gt 0) { Add-ResultChip $(if ($hintCount -eq 1) { '1 Hinweis' } else { "$hintCount Hinweise" }) 'Accent' }
    if ($Data.SearchError) { Add-ResultChip "$($drivers.Count) nicht geprüft" 'Bad' } else { Add-ResultChip "$($drivers.Count) aktuell" 'Good' }

    # Kopfzeile
    $silent = @($Data.Failed | Where-Object { $_ })
    # genannt werden nur die Quellen, die auf diesem PC gefragt wurden (kein NVIDIA ohne NVIDIA-Karte, kein AMD auf Intel)
    $asked = @($Data.Sources | Where-Object { $_ })
    if ($asked.Count -eq 0) { $asked = @('Windows Update', 'NVIDIA', 'AMD', 'Katalog') }
    $sources = "$($Data.Devices) Geräte geprüft · $($asked -join ', ')" + $(if ($silent.Count -gt 0) { " · ohne Antwort: $($silent -join ', ')" })
    if ($Data.SearchError) {
        $ui.ResultTitle.Text = T $('Windows Update war nicht erreichbar')
        $ui.ResultSub.Text = (T "$($Data.SearchError)") + $(if ($silent.Count -gt 0) { ' ' + (T "Ebenfalls ohne Antwort: $($silent -join ', ').") })
        $kind = 'Bad'; $glyph = 0xE783
    }
    elseif ($count -gt 0) {
        $ui.ResultTitle.Text = T $(if ($count -eq 1) { 'Ein neuerer Treiber gefunden' } else { "$count neuere Treiber gefunden" })
        $ui.ResultSub.Text = T $($sources)
        $kind = 'Warn'; $glyph = 0xE896
    }
    elseif ($amdNew) {
        $ui.ResultTitle.Text = T $('Neuer Chipsatz-Treiber bei AMD')
        $ui.ResultSub.Text = T $($sources)
        $kind = 'Warn'; $glyph = 0xE896
    }
    elseif ($problems.Count -gt 0) {
        # kein neuerer Treiber, aber Geräte mit Fehlern: das ist nicht "alles aktuell"
        $ui.ResultTitle.Text = T $(if ($problems.Count -eq 1) { 'Ein Gerät meldet einen Fehler' } else { "$($problems.Count) Geräte melden Fehler" })
        $ui.ResultSub.Text = T $($sources)
        $kind = 'Bad'; $glyph = 0xE7BA
    }
    else {
        $ui.ResultTitle.Text = T $('Alles aktuell')
        $ui.ResultSub.Text = T $($sources)
        $kind = 'Good'; $glyph = 0xE73E
    }
    $ui.ResultIcon.Text = Get-Glyph $glyph
    $ui.ResultIcon.Foreground = Get-Brush $kind
    $back = (Get-Brush $kind).Color
    $ui.ResultIconBack.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(40, $back.R, $back.G, $back.B))
    Update-UpdateButton

    # Startseite mitziehen
    $gameCount = @($Data.Runtimes | Where-Object { $_.Status -ne 'vorhanden' -and $_.CanInstall }).Count
    Show-Badge $ui.ChipDriversBadge $ui.ChipDriversCount ($count + $problems.Count)
    Show-Badge $ui.NavHomeBadge $ui.NavHomeCount ($count + $problems.Count)
    Show-Badge $ui.ChipGamesBadge $ui.ChipGamesCount $gameCount
    # kurz halten: die Karte auf der Startseite ist schmal
    $faults = if ($problems.Count -eq 1) { '1 Gerätefehler' } elseif ($problems.Count -gt 1) { "$($problems.Count) Gerätefehler" } else { '' }
    $driverText = if ($count -gt 0 -and $faults) { "$count neuere · $faults" } elseif ($faults) { $faults }
    elseif ($count -eq 1) { '1 neuerer Treiber' } elseif ($count -gt 1) { "$count neuere Treiber" } elseif ($Data.SearchError) { 'Nicht geprüft' } else { 'Alles aktuell' }
    $ui.HomeDriversText.Text = T $($driverText)
    # Punkt und Schrift der Karten zeigen den Zustand; die Treiber-Karte führt ab jetzt zu den Ergebnissen
    Set-Paint $ui.HomeDriversDot 'Fill' $(if ($count -gt 0) { 'Warn' } elseif ($faults -or $Data.SearchError) { 'Bad' } else { 'Good' })
    Set-Paint $ui.HomeGamesDot 'Fill' $(if ($gameCount -gt 0) { 'Warn' } else { 'Good' })
    foreach ($element in $ui.HomeDriversDot, $ui.HomeGamesDot, $ui.HomeDriversArrow) { $element.Visibility = 'Visible' }
    foreach ($element in $ui.HomeDriversText, $ui.HomeGamesText) { Set-Paint $element 'Foreground' 'Text' }
    $ui.ChipDrivers.Cursor = 'Hand'
    $ui.HomeGamesText.Text = T $(if ($gameCount -eq 1) { '1 Komponente fehlt' } elseif ($gameCount -gt 1) { "$gameCount Komponenten fehlen" } else { 'Vollständig' })
    # beim nächsten Blick auf die Scan-Seite zeigen die Karten den neuen Stand mit einer kleinen Bewegung
    $script:HomeCardsFresh = $true
    $ui.LastScanText.Text = T $("Letzter Scan: heute um $((Get-Date).ToString('HH:mm')) Uhr · $($Data.Devices) Geräte geprüft")
    if ($Data.SearchError) { Set-Status 'Windows Update war nicht erreichbar' 'Bad' }
    elseif ($count -gt 0) { Set-Status $ui.ResultTitle.Text 'Warn' -Glyph 0xE896 }
    else { Set-Status 'Alle Treiber sind aktuell' 'Good' }
}
