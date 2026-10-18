# PulsRig - Benchmark mit Vorher/Nachher-Vergleich. Wird von PulsRig.ps1 nach PulsRig-Temperatur.ps1 eingebunden.
#
# Ein Lauf dauert rund eine Minute: Prozessor (ein Kern, alle Kerne), Arbeitsspeicher, Grafikkarte (PulsRig-Benchmark.cs)
# und das Windows-Laufwerk (derselbe Tempotest wie im Fenster Laufwerke). Dabei laufen die Sensoren mit; die Höchstwerte
# der Temperaturen gehören zum Ergebnis. Jeder Lauf wird mit seinen Umständen gespeichert (Grafiktreiber, Speichertakt,
# Energieplan, Windows-Stand, Boost), damit der Vergleich mit dem letzten Lauf auch sagen kann, was sich seitdem geändert hat.
# Gespeichert in der Ergebnisdatei unter History.Benchmarks, die letzten 30 Läufe.

# Punkte: Prozessor = erledigte Aufgaben pro Sekunde / 10, Grafikkarte = Füllrate in Gpx/s x 10.
# Geeicht am Ryzen 7 5800X3D mit RTX 3080 (17.10.2026): rund 1.150 / 8.800 / 1.550 Punkte.
$script:BenchCpuFactor = 0.1
$script:BenchGpuFactor = 10.0
$script:Bench = $null
# Unterschiede unterhalb dieser Schwelle sind Messschwankung. Gemessen am 5800X3D/RTX 3080 (vier Läufe am 18.10.2026):
# Prozessor und Speicher ±2 %, Laufwerk ±1 %, Grafikkarte ±4,5 % (1.461 bis 1.601 Punkte) - deshalb dort 10 %.
$script:BenchNoise = 5.0

# Kachel für ein Ergebnis: Name, großer Wert, Einzelheiten, Vergleich und kleine Säulen der letzten Läufe
$benchTileXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,8,8" Padding="14,12,14,10" CornerRadius="14" Background="#0AFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Height="132">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Horizontal">
            <Grid Width="26" Height="26" Margin="0,0,9,0">
                <Border CornerRadius="8" Background="#2422D3EE"/>
                <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="12.5" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock x:Name="Label" FontSize="12" Foreground="#93A3C7" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,5,0,0">
            <TextBlock x:Name="Value" Text="–" FontSize="24" FontWeight="SemiBold" Foreground="#E8EEFC"/>
            <TextBlock x:Name="Unit" FontSize="13" Foreground="#93A3C7" VerticalAlignment="Bottom" Margin="5,0,0,4"/>
        </StackPanel>
        <TextBlock x:Name="Detail" Grid.Row="2" FontSize="11" Foreground="#93A3C7" TextWrapping="Wrap" Margin="0,1,0,0"/>
        <TextBlock x:Name="Delta" Grid.Row="3" FontSize="11" FontWeight="SemiBold" Foreground="#5E6E93" TextWrapping="Wrap" Margin="0,2,0,0"/>
        <StackPanel x:Name="Bars" Grid.Row="4" Orientation="Horizontal" VerticalAlignment="Bottom" HorizontalAlignment="Right" Margin="0,4,0,0"/>
    </Grid>
</Border>
'@

# Die vier Ergebnisse: Schlüssel im gespeicherten Lauf, wie der Wert aussieht, ob größer besser ist
$script:BenchSpecs = @(
    @{ Key = 'M'; Label = 'Prozessor'; Unit = 'Punkte'; Glyph = 0xE950; Format = '{0:N0}'; Higher = $true
        Detail = { param($r) $(if ($r.S) { '1 Kern: {0:N0} Punkte' -f $r.S } else { '' }) } },
    @{ Key = 'G'; Label = 'Grafikkarte'; Unit = 'Punkte'; Glyph = 0xE7F4; Format = '{0:N0}'; Higher = $true; Noise = 10.0
        Detail = { param($r) $(if ($r.F) { 'Füllrate {0:N0} Gpx/s' -f $r.F } elseif ($r.GE) { 'nicht messbar' } else { '' }) } },
    @{ Key = 'C'; Label = 'Arbeitsspeicher'; Unit = 'GB/s'; Glyph = 0xE8FD; Format = '{0:N1}'; Higher = $true
        Detail = { param($r) $(if ($r.L) { 'Wartezeit {0:N0} ns' -f $r.L } else { '' }) } },
    @{ Key = 'R'; Label = 'Laufwerk'; Unit = 'MB/s'; Glyph = 0xEDA2; Format = '{0:N0}'; Higher = $true
        Detail = { param($r) $(if ($r.W) { '{0} lesen · schreiben {1:N0} MB/s' -f $r.DL, $r.W } elseif ($r.DE) { "$($r.DE)" } else { 'nicht gemessen' }) } }
)

function Get-BenchRuns { @($script:History.Benchmarks | Where-Object { $_ }) }

function Get-BenchNoise($Spec) { if ($Spec -and $Spec.Noise) { [double]$Spec.Noise } else { $script:BenchNoise } }

# Bezug auf den Lauf davor: am selben Tag die Uhrzeit ("um 02:50 Uhr"), sonst das Datum ("am 16.10." bzw. "am 16.10.2026")
function Get-BenchSince($Before, [switch]$Short) {
    $day, $time = "$($Before.D)" -split ' ', 2
    if ($day -eq (Get-Date).ToString('dd.MM.yyyy') -and $time) { return "um $time Uhr" }
    if ($Short) { "am $($day.Substring(0, 6))" } else { "am $day" }
}

function Open-BenchSheet {
    Initialize-CpuTemp
    $opened = Open-Sheet @{
        Title     = 'Benchmark'
        Sub       = 'Prozessor, Arbeitsspeicher, Grafikkarte und Laufwerk mit Punkten – und der Vergleich mit früher'
        Glyph     = 0xEC4A
        Tabs      = 'Messen', 'Verlauf'
        Primary   = 'Benchmark starten'
        Show      = { param($tab) Show-BenchTab }
        OnPrimary = { if ($script:Bench) { Stop-Bench 'Abgebrochen.' } else { Start-Bench } }
        OnClose   = { Stop-Bench ''; Stop-Sensors }
    }
    if (-not $opened) { return }
    Start-Sensors
}

function Show-BenchTab {
    if ([int]$script:Sheet.Tab -eq 1) { Show-BenchHistory; return }
    Show-SheetPanel
    $grid = New-Object Windows.Controls.Primitives.UniformGrid
    $grid.Columns = 4
    $grid.Margin = '0,0,-8,0'
    $grid.VerticalAlignment = 'Top'
    [void]$ui.SheetPanel.Children.Add($grid)
    $script:BenchTiles = @{}
    $index = 0
    foreach ($spec in $script:BenchSpecs) {
        $color = $script:ToolColors[$index % $script:ToolColors.Count]
        $tile = [Windows.Markup.XamlReader]::Parse((ConvertTo-ThemedXaml ($benchTileXaml.Replace('#2422D3EE', '#24' + $color.Substring(1)).Replace('#22D3EE', $color))))
        $tile.FindName('Glyph').Text = Get-Glyph $spec.Glyph
        $tile.FindName('Label').Text = T $($spec.Label)
        $tile.FindName('Unit').Text = T $($spec.Unit)
        $tile.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $tile.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Pop $tile (80 + 55 * $index) 0.9
        [void]$grid.Children.Add($tile)
        $script:BenchTiles[$spec.Key] = @{ Tile = $tile; Spec = $spec; Color = $color }
        $index++
    }
    # darunter die Sensoren: während des Laufs sieht man, wie warm es wird
    New-SensorGrid $(if ($script:CpuTempSeen) { 'CpuTemp', 'CpuClock', 'GpuTemp', 'GpuLoad' } else { 'CpuLoad', 'CpuClock', 'GpuTemp', 'GpuLoad' }) -Height 118
    $slot = Add-SettingRow 'Bereit' 'Dauert rund eine Minute. Ein Fenster für die Grafikkarte geht kurz auf, auf das Windows-Laufwerk wird 1 GB geschrieben und gleich wieder gelöscht. Andere Programme vorher schließen, sonst sinken die Punkte.' 0xE946
    $script:BenchRow = $slot.Parent.Parent
    $runs = @(Get-BenchRuns)
    if ($script:Bench) { Set-BenchRow 'Läuft …' '' 'run' }
    elseif ($runs.Count) {
        $last = $runs[-1]
        $before = if ($runs.Count -gt 1) { $runs[-2] } else { $null }
        Set-BenchTiles $last $before
        Set-BenchRow "Letzter Lauf: $($last.D) Uhr" (Get-BenchSummary $last $before) $(if ($before) { Get-BenchTone $last $before } else { 'good' })
    }
    $ui.BtnSheetPrimary.Content = T $(if ($script:Bench) { 'Stoppen' } else { 'Benchmark starten' })
    $ui.SheetState.Text = T $('Am besten vergleichbar: gleiche Uhrzeit, gleiche Programme offen, PC nicht gerade erst gestartet')
}

function Set-BenchRow([string]$Title, [string]$Text, [string]$Tone) {
    if (-not $script:BenchRow) { return }
    try {
        $script:BenchRow.FindName('Title').Text = T $Title
        $script:BenchRow.FindName('Text').Text = T $Text
        $script:BenchRow.FindName('Text').Visibility = $(if ($Text) { 'Visible' } else { 'Collapsed' })
        Set-Paint $script:BenchRow.FindName('Glyph') 'Foreground' $(switch ($Tone) { 'good' { 'Good' } 'warn' { 'Warn' } 'bad' { 'Bad' } default { 'Accent' } })
        $script:BenchRow.FindName('Glyph').Text = Get-Glyph $(switch ($Tone) { 'good' { 0xE73E } 'warn' { 0xE7BA } 'bad' { 0xE783 } 'run' { 0xE768 } default { 0xE946 } })
    }
    catch { }
}

# Veränderung gegenüber dem Lauf davor in Prozent; positiv = besser
function Get-BenchChange($Now, $Before, [string]$Key) {
    if (-not $Before) { return $null }
    $a = [double]$Now[$Key]; $b = [double]$Before[$Key]
    if ($a -le 0 -or $b -le 0) { return $null }
    100.0 * ($a - $b) / $b
}

function Set-BenchTiles($Run, $Before) {
    $runs = @(Get-BenchRuns)
    foreach ($key in @($script:BenchTiles.Keys)) {
        $entry = $script:BenchTiles[$key]
        $spec = $entry.Spec
        $tile = $entry.Tile
        $value = [double]$Run[$key]
        $tile.FindName('Value').Text = $(if ($value -gt 0) { $spec.Format -f $value } else { '–' })
        $tile.FindName('Detail').Text = T "$(& $spec.Detail $Run)"
        $delta = $tile.FindName('Delta')
        $change = Get-BenchChange $Run $Before $key
        if ($null -eq $change) { $delta.Text = ''; }
        else {
            $since = Get-BenchSince $Before -Short
            if ([Math]::Abs($change) -lt (Get-BenchNoise $spec)) { $delta.Text = T "wie $since"; Set-Paint $delta 'Foreground' 'TextDim' }
            elseif ($change -gt 0) { $delta.Text = T ('{0:N0} % besser als {1}' -f $change, $since); Set-Paint $delta 'Foreground' 'Good' }
            else { $delta.Text = T ('{0:N0} % schlechter als {1}' -f (-$change), $since); Set-Paint $delta 'Foreground' 'Warn' }
        }
        # kleine Säulen: die letzten acht Läufe, der neueste rechts
        $bars = $tile.FindName('Bars')
        $bars.Children.Clear()
        $values = @($runs | Select-Object -Last 8 | ForEach-Object { [double]$_[$key] })
        $top = ($values | Measure-Object -Maximum).Maximum
        if ($values.Count -gt 1 -and $top -gt 0) {
            for ($i = 0; $i -lt $values.Count; $i++) {
                $bar = New-Object Windows.Controls.Border
                $bar.Width = 6; $bar.Margin = '2,0,0,0'; $bar.CornerRadius = 2; $bar.VerticalAlignment = 'Bottom'
                $bar.Height = [Math]::Max(2.0, 22.0 * $values[$i] / $top)
                $bar.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($entry.Color))
                $bar.Opacity = $(if ($i -eq $values.Count - 1) { 1.0 } else { 0.35 })
                [void]$bars.Children.Add($bar)
            }
        }
    }
}

# Was sich seit dem Lauf davor geändert hat, als kurze Liste
function Get-BenchContextChanges($Now, $Before) {
    if (-not $Before -or -not $Before.X -or -not $Now.X) { return @() }
    $changes = @()
    $a = $Before.X; $b = $Now.X
    if ($a.Gpu -and $b.Gpu -and $a.Gpu -ne $b.Gpu) { $changes += "$(T 'Grafiktreiber') $($a.Gpu) → $($b.Gpu)" }
    if ($a.Ram -and $b.Ram -and $a.Ram -ne $b.Ram) { $changes += "$(T 'Speichertakt') $($a.Ram) → $($b.Ram) MHz" }
    if ($a.Plan -and $b.Plan -and $a.Plan -ne $b.Plan) { $changes += "$(T 'Energieplan') $($a.Plan) → $($b.Plan)" }
    if ($a.Win -and $b.Win -and $a.Win -ne $b.Win) { $changes += "Windows $($a.Win) → $($b.Win)" }
    if ($null -ne $a.Boost -and $null -ne $b.Boost -and [bool]$a.Boost -ne [bool]$b.Boost) { $changes += "Boost $(T $(if ($a.Boost) { 'an' } else { 'aus' })) → $(T $(if ($b.Boost) { 'an' } else { 'aus' }))" }
    $changes
}

# Ein Satz zum Lauf: was besser oder schlechter wurde und was sich seitdem geändert hat
function Get-BenchSummary($Run, $Before) {
    $parts = @()
    $temps = @()
    if ($Run.CT -gt 0) { $temps += ('Prozessor bis {0:N0} °C' -f $Run.CT) }
    if ($Run.GT -gt 0) { $temps += ('Grafikkarte bis {0:N0} °C' -f $Run.GT) }
    # Ryzen ab 5000 und neuere Intel takten unter Volllast absichtlich bis an ihre Temperaturgrenze (90 bis 100 °C).
    # Gemessen am 5800X3D: binnen einer Sekunde 82-90 °C, eine Sekunde nach dem Ende wieder 55 °C.
    $limit = if ($Run.CT -ge 88) { 'Der Prozessor lief an seiner Temperaturgrenze. Viele Prozessoren takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt: Bei normalen Punkten ist das kein Fehler. Werden die Punkte mit der Zeit weniger, Kühler und Staub prüfen.' } else { '' }
    if (-not $Before) {
        $parts += 'Erster Lauf: Er ist ab jetzt der Vergleich für die nächsten.'
        if ($temps) { $parts += ($temps -join ' · ') + '.' }
        if ($limit) { $parts += $limit }
        return ($parts -join "`n")
    }
    $better = @(); $worse = @()
    foreach ($spec in $script:BenchSpecs) {
        $change = Get-BenchChange $Run $Before $spec.Key
        if ($null -eq $change -or [Math]::Abs($change) -lt (Get-BenchNoise $spec)) { continue }
        if ($change -gt 0) { $better += ('{0} +{1:N0} %' -f (T $spec.Label), $change) } else { $worse += ('{0} −{1:N0} %' -f (T $spec.Label), -$change) }
    }
    $since = Get-BenchSince $Before
    if (-not $better -and -not $worse) { $parts += "Alles wie $since." }
    else {
        if ($better) { $parts += "Besser als $($since): $($better -join ', ')." }
        if ($worse) { $parts += "Schlechter als $($since): $($worse -join ', ')." }
    }
    # Temperatur: 8 Grad mehr bei gleicher Leistung deutet auf Staub oder eingetrocknete Wärmeleitpaste (bis 5 Grad schwankt es schon zwischen zwei Läufen kurz nacheinander)
    if ($Run.CT -gt 0 -and $Before.CT -gt 0 -and $Run.CT - $Before.CT -ge 8) { $parts += ('Der Prozessor wurde {0:N0} °C wärmer als damals.' -f ($Run.CT - $Before.CT)) }
    elseif ($Run.GT -gt 0 -and $Before.GT -gt 0 -and $Run.GT - $Before.GT -ge 8) { $parts += ('Die Grafikkarte wurde {0:N0} °C wärmer als damals.' -f ($Run.GT - $Before.GT)) }
    $changes = @(Get-BenchContextChanges $Run $Before)
    if ($changes) { $parts += "Seitdem: $($changes -join ', ')." }
    elseif ($worse) { $parts += 'Seitdem hat sich an Treiber, Speichertakt, Energieplan und Windows nichts geändert: andere Programme im Hintergrund oder Wärme sind wahrscheinlicher.' }
    if ($temps) { $parts += ($temps -join ' · ') + '.' }
    # an der Grenze zu sein, ist nur dann eine Nachricht, wenn die Punkte nicht gesunken sind (sonst steht der Grund oben)
    if ($limit -and -not $worse) { $parts += $limit }
    $parts -join "`n"
}

function Get-BenchTone($Run, $Before) {
    foreach ($spec in $script:BenchSpecs) {
        $change = Get-BenchChange $Run $Before $spec.Key
        if ($null -ne $change -and $change -le -(Get-BenchNoise $spec)) { return 'warn' }
    }
    'good'
}

# Umstände des Laufs: alles, was die Punkte verschieben kann
function Get-BenchContext {
    $context = @{ Boost = [bool]$script:BoostOn }
    try {
        $card = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { "$($_.PNPDeviceID)" -like 'PCI*' } | Select-Object -First 1)[0]
        if ($card) { $context.Gpu = "$($card.DriverVersion)" }
    }
    catch { }
    try {
        $module = Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Select-Object -First 1
        $context.Ram = [int]$(if ($module.ConfiguredClockSpeed) { $module.ConfiguredClockSpeed } else { $module.Speed })
    }
    catch { }
    try { if ("$(powercfg /getactivescheme)" -match '\(([^)]+)\)') { $context.Plan = $Matches[1] } } catch { }
    try {
        $key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $context.Win = "$($key.CurrentBuild).$($key.UBR)"
    }
    catch { }
    $context
}

function Start-Bench([double]$Scale = 1.0, [switch]$NoDrive) {
    if ($script:Bench -or -not $script:Sheet) { return }
    if ($script:Stress) { Set-BenchRow 'Erst den Stabilitätstest beenden' '' 'warn'; return }
    if (-not ('PulsRigBench' -as [type])) { Add-Type -TypeDefinition (Get-AppText 'PulsRig-Benchmark.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing }
    Start-Sensors
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({ try { Update-Bench } catch { Write-AppError $_ } })
    $script:Bench = @{ Phase = 'core'; Timer = $timer; MaxCpu = 0.0; MaxGpu = 0.0; NoDrive = [bool]$NoDrive; Stamp = 0
        Letter = "$($env:SystemDrive)".TrimEnd(':').Substring(0, 1).ToUpper() }
    # ein langer Lauf darf nicht am Energiesparen scheitern; das hält der Lastbaustein bereit
    try { if (-not ('PulsRigStress' -as [type])) { Add-Type -TypeDefinition (Get-AppText 'PulsRig-Last.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing }; [PulsRigStress]::KeepAwake($true) } catch { }
    Add-MemTrace 'Benchmark gestartet'
    [PulsRigBench]::Start($Scale, $true)
    $ui.BtnSheetPrimary.Content = T $('Stoppen')
    Set-BenchRow 'Läuft …' 'Prozessor, ein Kern' 'run'
    $timer.Start()
}

function Update-Bench {
    $bench = $script:Bench
    if (-not $bench) { return }
    $values = $sync.Sensors
    if ($values -and $values.Stamp -ne $bench.Stamp) {
        $bench.Stamp = $values.Stamp
        if ($values.CpuTemp -gt $bench.MaxCpu) { $bench.MaxCpu = [double]$values.CpuTemp }
        if ($values.GpuTemp -gt $bench.MaxGpu) { $bench.MaxGpu = [double]$values.GpuTemp }
    }
    if ($bench.Phase -eq 'core') {
        $stage = [PulsRigBench]::Stage
        if ($stage -eq 'stopped') { Stop-Bench 'Abgebrochen.'; return }
        if ($stage -ne 'done') {
            $what = switch ($stage) { 'single' { 'Prozessor, ein Kern' } 'multi' { 'Prozessor, alle Kerne' } 'memory' { 'Arbeitsspeicher' } 'gpu' { 'Grafikkarte (eigenes Fenster)' } default { '' } }
            Set-BenchRow ('Läuft – {0} %' -f [int]([PulsRigBench]::Percent * $(if ($bench.NoDrive) { 1.0 } else { 0.8 }))) $what 'run'
            return
        }
        if ($bench.NoDrive) { Complete-Bench $null; return }
        $bench.Phase = 'drive'
        Set-BenchRow 'Läuft – 80 %' "Laufwerk $($bench.Letter): schreiben und lesen" 'run'
        Start-Query 'DriveSpeed' { param($result) Complete-Bench $result } @{ Letter = $bench.Letter; TargetDir = (Get-TargetDir) }
    }
}

function Stop-Bench([string]$Text) {
    $bench = $script:Bench
    if (-not $bench) { return }
    $script:Bench = $null
    $bench.Timer.Stop()
    try { [PulsRigBench]::Stop() } catch { }
    try { [PulsRigStress]::KeepAwake($false) } catch { }
    if ($Text -and $script:Sheet -and $script:Sheet.Title -eq 'Benchmark') {
        Set-BenchRow 'Nicht fertig geworden' $Text 'warn'
        $ui.BtnSheetPrimary.Content = T $('Benchmark starten')
    }
}

function Complete-Bench($Drive) {
    $bench = $script:Bench
    if (-not $bench) { return }
    $script:Bench = $null
    $bench.Timer.Stop()
    try { [PulsRigStress]::KeepAwake($false) } catch { }
    $now = Get-Date
    $run = @{
        D  = $now.ToString('dd.MM.yyyy HH:mm')
        S  = [Math]::Round([PulsRigBench]::Single * $script:BenchCpuFactor)
        M  = [Math]::Round([PulsRigBench]::Multi * $script:BenchCpuFactor)
        C  = [Math]::Round([PulsRigBench]::Copy, 1)
        L  = [Math]::Round([PulsRigBench]::Latency, 1)
        F  = [Math]::Round([PulsRigBench]::Fill, 1)
        G  = [Math]::Round([PulsRigBench]::Fill * $script:BenchGpuFactor)
        GN = "$([PulsRigBench]::GpuName)"
        GE = "$([PulsRigBench]::GpuError)"
        CT = [Math]::Round($bench.MaxCpu)
        GT = [Math]::Round($bench.MaxGpu)
        X  = Get-BenchContext
    }
    if ($Drive -and -not $Drive.Error) { $run.R = [Math]::Round([double]$Drive.Read); $run.W = [Math]::Round([double]$Drive.Write); $run.DL = "$($Drive.Letter):" }
    elseif ($Drive -and $Drive.Error) { $run.DE = "$($Drive.Error)" }
    $runs = @(Get-BenchRuns)
    $before = if ($runs.Count) { $runs[-1] } else { $null }
    $script:History.Benchmarks = @(@($runs) + $run | Select-Object -Last 30)
    Set-CardState 'Bench' @{ Text = ('{0:N0} Punkte' -f $run.M); Tone = $(if ($before) { Get-BenchTone $run $before } else { 'good' }); Detail = "Prozessor $('{0:N0}' -f $run.M) · Grafik $('{0:N0}' -f $run.G)" }
    Save-HardwareResults
    Update-BenchPill
    Add-MemTrace 'Benchmark fertig'
    if (-not $script:Sheet -or $script:Sheet.Title -ne 'Benchmark') { return }
    $ui.BtnSheetPrimary.Content = T $('Benchmark starten')
    if ([int]$script:Sheet.Tab -ne 0) { return }
    Set-BenchTiles $run $before
    Set-BenchRow $(if ($run.GE) { 'Fertig – die Grafikkarte ließ sich nicht messen' } else { 'Fertig' }) (Get-BenchSummary $run $before) $(if ($before) { Get-BenchTone $run $before } else { 'good' })
}

function Show-BenchHistory {
    $runs = @(Get-BenchRuns)
    $rows = @()
    if ($runs.Count -eq 0) {
        $rows += New-SheetRow -Title 'Noch kein Lauf' -Sub 'Der erste Benchmark ist der Vergleich für alle späteren: nach einem Treiber-Update, mit XMP oder mit Boost.' -Glyph 0xEC4A
    }
    for ($i = $runs.Count - 1; $i -ge 0; $i--) {
        $run = $runs[$i]
        $before = if ($i -gt 0) { $runs[$i - 1] } else { $null }
        $parts = @(('Prozessor {0:N0} (1 Kern {1:N0})' -f $run.M, $run.S))
        if ($run.G) { $parts += ('Grafik {0:N0}' -f $run.G) }
        if ($run.C) { $parts += ('Speicher {0:N1} GB/s, {1:N0} ns' -f $run.C, $run.L) }
        if ($run.R) { $parts += ('{0} {1:N0}/{2:N0} MB/s' -f $run.DL, $run.R, $run.W) }
        if ($run.CT -gt 0) { $parts += ('CPU {0:N0} °C' -f $run.CT) }
        if ($run.GT -gt 0) { $parts += ('GPU {0:N0} °C' -f $run.GT) }
        $changes = @(Get-BenchContextChanges $run $before)
        if ($changes) { $parts += "$(T 'seit dem Lauf davor'): $($changes -join ', ')" }
        $tone = if ($before) { Get-BenchTone $run $before } else { '' }
        $state = if (-not $before) { 'erster Lauf' } elseif ($tone -eq 'warn') { 'schlechter' } else {
            $up = @($script:BenchSpecs | Where-Object { $c = Get-BenchChange $run $before $_.Key; $null -ne $c -and $c -ge (Get-BenchNoise $_) }).Count
            $(if ($up) { 'besser' } else { 'gleich' })
        }
        $rows += New-SheetRow -Title "$($run.D) Uhr" -Sub ($parts -join ' · ') -Glyph 0xEC4A -State $state -Tone $(if ($state -eq 'besser') { 'good' } elseif ($state -eq 'schlechter') { 'warn' } else { '' })
    }
    Show-SheetList $rows
    Set-SheetStateText "$($runs.Count) von höchstens 30 Läufen gespeichert"
}

# Knopf oben rechts auf der Hardware-Seite: letzter Wert
function Update-BenchPill {
    if (-not $ui.HardwareBenchText) { return }
    $state = $script:CardState.Bench
    $ui.HardwareBenchText.Text = T $(if ($state -and $state.Text) { "Benchmark: $($state.Text)" } else { 'Benchmark' })
}

$ui.HardwareBenchPill.Add_MouseLeftButtonUp({ try { Open-BenchSheet } catch { Write-AppError $_ } })
Update-BenchPill
