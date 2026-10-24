# PulsRig - Stromverbrauch und Stromkosten. Wird von PulsRig.ps1 nach PulsRig-Autostart.ps1 eingebunden.
#
# Nutzt die Messschleife der Sensoren (PulsRig-Hardware.ps1) und rechnet daraus Watt und Euro:
#   Grafikkarte  - gemessen über nvidia-smi (nur NVIDIA); sonst ein Pauschalwert
#   Prozessor    - gemessen über LibreHardwareMonitor ("CPU Package", braucht PawnIO und Adminrechte);
#                  sonst geschätzt aus Auslastung × Nennleistung
#   Rest         - Mainboard, Arbeitsspeicher, Laufwerke und Lüfter pauschal
# Dazu der Verlust im Netzteil. Das Ergebnis ist eine Schätzung und wird so gekennzeichnet; ein Messgerät an der
# Steckdose ist genauer. Die Kosten pro Tag und Jahr folgen aus dem Mittel seit dem Öffnen des Fensters.
# Dieselbe Rechnung gibt die Stromkosten einer aufgezeichneten Spielsitzung (Sensoren → Spielsitzungen).

$script:PowerRest = 35.0         # W für Mainboard, Arbeitsspeicher, Laufwerke, Lüfter
$script:PowerGpuGuess = 20.0     # W für eine Grafikkarte ohne Messwert (etwa im Leerlauf)
$script:PowerCpuRated = 65.0     # W Nennleistung, wenn der Prozessor nicht gemessen wird
$script:PowerEfficiency = 0.88   # Wirkungsgrad des Netzteils
$script:Power = $null            # das offene Fenster: Felder, Timer, Summe der Messungen
$script:PowerLimitLead = 10      # s Vorlauf, um ins Spiel zu wechseln, bevor der FPS-Limit-Vergleich misst
$script:PowerLimitSeconds = 30   # s Messdauer je Durchgang
$script:PowerLimit = @{}         # Ergebnisse des Vergleichs (Off/On: mittlere Watt), bleiben bis zum Beenden
$script:PowerLimitRun = $null    # laufender Durchgang: Kind, Start, End, Sum, Count

function Open-PowerSheet {
    Initialize-CpuTemp
    $opened = Open-Sheet @{
        Title   = 'Stromverbrauch'
        Sub     = 'Was der PC gerade zieht und was das im Jahr kostet'
        Glyph   = 0xE945
        Show    = { param($tab) Show-PowerPanel }
        OnClose = { Stop-PowerSheet }
    }
    if (-not $opened) { return }
    Start-Sensors
}

function Stop-PowerSheet {
    if ($script:Power) { $script:Power.Timer.Stop(); $script:Power = $null }
    $script:PowerLimitRun = $null   # ohne Fenster keine Messwerte: Durchgang abbrechen
    Stop-Sensors
}

# Großer Wert rechts in einer Zeile
function New-PowerValue([string]$Text = '–', [double]$Size = 20) {
    $value = New-Object Windows.Controls.TextBlock
    $value.Text = $Text
    $value.FontSize = $Size
    $value.FontWeight = 'SemiBold'
    $value.VerticalAlignment = 'Center'
    Set-Paint $value 'Foreground' 'Text'
    $value
}

function Show-PowerPanel {
    Show-SheetPanel
    $script:SensorTiles = @{}   # die Messschleife zeichnet hier keine Kacheln
    $fields = @{}
    foreach ($part in @('Gpu', 'Grafikkarte', 0xE7F4), @('Cpu', 'Prozessor', 0xE950), @('Rest', 'Mainboard, Speicher, Laufwerke, Lüfter', 0xE964)) {
        $slot = Add-SettingRow $part[1] 'Warte auf den ersten Messwert …' $part[2]
        $value = New-PowerValue
        [void]$slot.Children.Add($value)
        $fields[$part[0]] = @{ Value = $value; Text = $slot.Parent.FindName('Text') }
    }
    $slot = Add-SettingRow 'Zusammen' 'mit dem Verlust im Netzteil' 0xE945
    $total = New-PowerValue '–' 26
    Set-Paint $total 'Foreground' 'Accent'
    [void]$slot.Children.Add($total)
    $fields.Total = @{ Value = $total; Text = $slot.Parent.FindName('Text') }
    $slot = Add-SettingRow 'Kosten' 'Aus dem Mittel seit dem Öffnen dieses Fensters' 0xE9D2
    $cost = New-PowerValue '–' 20
    Set-Paint $cost 'Foreground' 'Accent'
    [void]$slot.Children.Add($cost)
    $fields.Cost = @{ Value = $cost; Text = $slot.Parent.FindName('Text') }

    $slot = Add-SettingRow 'Strompreis' 'Steht auf der Stromrechnung (Arbeitspreis je kWh)' 0xE8C7
    foreach ($step in @('down', '–'), @('up', '+')) {
        $chip = New-SettingChip $step[1] $step[0]
        $chip.Add_Click({ try { Set-PowerPrice $(if ($this.Uid -eq 'up') { 0.01 } else { -0.01 }) } catch { Write-AppError $_ } })
        [void]$slot.Children.Add($chip)
    }
    $price = New-PowerValue (Format-PowerPrice) 15
    $price.Margin = '8,0,4,0'
    $slot.Children.Insert(1, $price)
    $fields.Price = $price

    $slot = Add-SettingRow 'Nutzung am Tag' 'So lange läuft der PC im Schnitt' 0xE916
    foreach ($hours in 2, 4, 8, 12) {
        $chip = New-SettingChip "$hours Std." "$hours"
        $chip.Add_Click({
                try {
                    $script:Settings.PowerHours = [int]$this.Uid
                    Save-Settings
                    Update-SettingChips $this.Parent $this.Uid
                    Update-PowerPanel -Force
                }
                catch { Write-AppError $_ }
            })
        [void]$slot.Children.Add($chip)
    }
    Update-SettingChips $slot "$($script:Settings.PowerHours)"

    # FPS-Limit-Vergleich: zweimal im laufenden Spiel messen, einmal ohne und einmal mit Limit
    foreach ($kind in @('Off', 'Ohne FPS-Limit', 0xE7FC), @('On', 'Mit FPS-Limit', 0xE7FC)) {
        $slot = Add-SettingRow $kind[1] '' $kind[2]
        $value = New-PowerValue '–' 17
        $value.Margin = '0,0,10,0'
        [void]$slot.Children.Add($value)
        $chip = New-SettingChip 'Messen' $kind[0]
        $chip.Add_Click({ try { Start-PowerLimitMeasure $this.Uid } catch { Write-AppError $_ } })
        [void]$slot.Children.Add($chip)
        $text = $slot.Parent.FindName('Text')
        $text.Visibility = 'Visible'
        $fields["Limit$($kind[0])"] = @{ Value = $value; Text = $text }
    }
    $slot = Add-SettingRow 'Ersparnis durch das FPS-Limit' 'Erst ohne, dann mit Limit messen' 0xE9D2
    foreach ($hours in 1, 2, 4, 6) {
        $chip = New-SettingChip "$hours Std." "$hours"
        $chip.Add_Click({
                try {
                    $script:Settings.GameHours = [int]$this.Uid
                    Save-Settings
                    Update-SettingChips $this.Parent $this.Uid
                    Update-PowerLimit
                }
                catch { Write-AppError $_ }
            })
        [void]$slot.Children.Add($chip)
    }
    Update-SettingChips $slot "$($script:Settings.GameHours)"
    $saving = New-PowerValue '–' 20
    $saving.Margin = '0,0,10,0'
    Set-Paint $saving 'Foreground' 'Accent'
    $slot.Children.Insert(0, $saving)
    $fields.Saving = @{ Value = $saving; Text = $slot.Parent.FindName('Text') }

    # ohne gemessenen Prozessor: der Hinweis mit dem Knopf zum Freischalten (wie im Fenster Sensoren)
    if (-not $script:CpuTempSeen -or (-not $sync.CpuTempDemo -and "$([PulsRigCpuTemp]::Source)" -eq 'Core Temp')) { Add-CpuTempHint }

    if ($script:Power) { $script:Power.Timer.Stop() }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({ try { Update-PowerPanel; Update-PowerLimit } catch { Write-AppError $_ } })
    $script:Power = @{ Fields = $fields; Timer = $timer; Stamp = 0; Sum = 0.0; Count = 0; Last = $null }
    $timer.Start()
    Update-PowerLimit
    $ui.SheetState.Text = T 'Schätzung – ein Messgerät an der Steckdose ist genauer'
}

function Format-PowerPrice { '{0:N2} €/kWh' -f [double]$script:Settings.PowerPrice }

function Set-PowerPrice([double]$Step) {
    $script:Settings.PowerPrice = [Math]::Round([Math]::Max(0.05, [Math]::Min(1.5, [double]$script:Settings.PowerPrice + $Step)), 2)
    Save-Settings
    if ($script:Power) { $script:Power.Fields.Price.Text = Format-PowerPrice; Update-PowerPanel -Force }
}

# Rechnet aus einem Satz Messwerte die Leistung der Teile; Measured sagt, welche gemessen sind
function Get-PowerParts($Values) {
    $gpu = if ($null -ne $Values.GpuPower) { [double]$Values.GpuPower } else { $null }
    $cpu = if ($null -ne $Values.CpuPower) { [double]$Values.CpuPower } else { $null }
    $load = if ($null -ne $Values.CpuLoad) { [double]$Values.CpuLoad } else { 10.0 }
    $parts = @{
        Gpu = $(if ($null -ne $gpu) { $gpu } else { $script:PowerGpuGuess })
        Cpu = $(if ($null -ne $cpu) { $cpu } else { $script:PowerCpuRated * (0.15 + 0.85 * $load / 100.0) })
        Rest = $script:PowerRest
        GpuMeasured = $null -ne $gpu
        CpuMeasured = $null -ne $cpu
        Load = $load
    }
    $parts.Total = ($parts.Gpu + $parts.Cpu + $parts.Rest) / $script:PowerEfficiency
    $parts
}

# Stromkosten einer aufgezeichneten Spielsitzung (PulsRig-Aufzeichnung.ps1): jede Zeile wie im Fenster Stromverbrauch
# gerechnet und mit dem Abstand zur vorigen Zeile gewichtet. $null ohne Zeilen.
function Get-RecordingEnergy($Recording) {
    $data = $Recording.Data
    $time = $data['Sekunde']
    if (-not $time -or $time.Count -lt 2) { return $null }
    $value = { param($name, $i) $list = $data[$name]; if ($list -and -not [double]::IsNaN($list[$i])) { $list[$i] } else { $null } }
    $wattSeconds = 0.0; $gpuSeconds = 0.0; $cpuSeconds = 0.0; $seconds = 0.0
    for ($i = 1; $i -lt $time.Count; $i++) {
        $step = $time[$i] - $time[$i - 1]
        if ([double]::IsNaN($step) -or $step -le 0 -or $step -gt 60) { continue }   # Lücke: nicht hochrechnen
        $parts = Get-PowerParts @{ GpuPower = (& $value 'GpuWatt' $i); CpuPower = (& $value 'CpuWatt' $i); CpuLoad = (& $value 'CpuLast' $i) }
        $wattSeconds += $parts.Total * $step
        $seconds += $step
        if ($parts.GpuMeasured) { $gpuSeconds += $step }
        if ($parts.CpuMeasured) { $cpuSeconds += $step }
    }
    if ($seconds -le 0) { return $null }
    $kwh = $wattSeconds / 3600.0 / 1000.0
    @{ Kwh = $kwh; Euro = $kwh * [double]$script:Settings.PowerPrice; Average = $wattSeconds / $seconds
        GpuMeasured = $gpuSeconds -ge $seconds / 2; CpuMeasured = $cpuSeconds -ge $seconds / 2 }
}

# Zeile "Stromkosten" unter der Zusammenfassung einer Spielsitzung
function Add-RecordingEnergyRow($Recording) {
    $energy = Get-RecordingEnergy $Recording
    if (-not $energy) { return }
    $measured = if ($energy.GpuMeasured -and $energy.CpuMeasured) { 'Grafikkarte und Prozessor gemessen, der Rest geschätzt' }
    elseif ($energy.GpuMeasured) { 'Grafikkarte gemessen, Prozessor und Rest geschätzt' }
    elseif ($energy.CpuMeasured) { 'Prozessor gemessen, Grafikkarte und Rest geschätzt' }
    else { 'Geschätzt: weder Grafikkarte noch Prozessor gemessen' }
    $text = (T $('Im Mittel {0:N0} W · {1:N2} kWh bei {2}' -f $energy.Average, $energy.Kwh, (Format-PowerPrice))) + "`n" + (T $measured)
    $slot = Add-SettingRow 'Stromkosten dieser Sitzung' $text 0xE945
    $cost = New-PowerValue $(if ($energy.Euro -lt 1) { T $('{0:N0} Cent' -f ($energy.Euro * 100)) } else { '{0:N2} €' -f $energy.Euro }) 20
    Set-Paint $cost 'Foreground' 'Accent'
    [void]$slot.Children.Add($cost)
}

function Update-PowerPanel([switch]$Force) {
    $power = $script:Power
    $values = $sync.Sensors
    if (-not $power -or -not $script:Sheet -or $script:Sheet.Title -ne 'Stromverbrauch') { return }
    if ($values -and $values.Stamp -ne $power.Stamp) {
        $power.Stamp = $values.Stamp
        $power.Last = Get-PowerParts $values
        $power.Sum += $power.Last.Total
        $power.Count++
        $run = $script:PowerLimitRun
        if ($run -and [DateTime]::Now -ge $run.Start) {
            $run.Sum += $power.Last.Total
            $run.Count++
            if (-not $power.Last.GpuMeasured) { $run.GpuGuessed = $true }
        }
    }
    elseif (-not $Force) { return }
    $parts = $power.Last
    if (-not $parts) { return }
    $fields = $power.Fields
    $fields.Gpu.Value.Text = '{0:N0} W' -f $parts.Gpu
    $fields.Gpu.Text.Text = T $(if ($parts.GpuMeasured) { "Gemessen · $($values.GpuName)" } else { 'Geschätzt: keine NVIDIA-Grafikkarte, deren Verbrauch PulsRig messen kann' })
    $fields.Cpu.Value.Text = '{0:N0} W' -f $parts.Cpu
    $fields.Cpu.Text.Text = T $(if ($parts.CpuMeasured) { 'Gemessen über LibreHardwareMonitor' } else { 'Geschätzt aus {0:N0} % Auslastung × {1:N0} W Nennleistung' -f $parts.Load, $script:PowerCpuRated })
    $fields.Rest.Value.Text = '{0:N0} W' -f $parts.Rest
    $fields.Rest.Text.Text = T 'Pauschal geschätzt'
    $fields.Total.Value.Text = '{0:N0} W' -f $parts.Total
    $fields.Total.Text.Text = T $('mit dem Verlust im Netzteil · {0:N1} Cent pro Stunde' -f ($parts.Total / 1000.0 * [double]$script:Settings.PowerPrice * 100.0))

    $average = $power.Sum / [Math]::Max(1, $power.Count)
    $day = $average / 1000.0 * [double]$script:Settings.PowerHours * [double]$script:Settings.PowerPrice
    $fields.Cost.Value.Text = T $('{0:N0} € im Jahr' -f ($day * 365))
    $fields.Cost.Text.Text = T $('Im Mittel {0:N0} W · {1:N2} € am Tag bei {2} Std.' -f $average, $day, $script:Settings.PowerHours)
}

# FPS-Limit-Vergleich: PulsRig stellt das Limit nicht selbst um. Der Nutzer startet einen Durchgang, wechselt ins
# Spiel, und nach dem Vorlauf mittelt PulsRig den Verbrauch eine halbe Minute lang. Das Fenster bleibt dabei offen.
function Start-PowerLimitMeasure([string]$Kind) {
    $now = [DateTime]::Now
    $start = $now.AddSeconds($script:PowerLimitLead)
    $script:PowerLimitRun = @{ Kind = $Kind; Start = $start; End = $start.AddSeconds($script:PowerLimitSeconds); Sum = 0.0; Count = 0; GpuGuessed = $false }
    Update-PowerLimit
}

function Update-PowerLimit {
    $power = $script:Power
    if (-not $power -or -not $power.Fields.Saving) { return }
    $fields = $power.Fields
    $run = $script:PowerLimitRun
    $now = [DateTime]::Now
    if ($run -and $now -ge $run.End) {
        if ($run.Count -gt 0) {
            $script:PowerLimit[$run.Kind] = @{ Watt = $run.Sum / $run.Count; GpuGuessed = $run.GpuGuessed; Time = $run.End }
        }
        $script:PowerLimitRun = $run = $null
    }
    foreach ($kind in 'Off', 'On') {
        $field = $fields["Limit$kind"]
        $result = $script:PowerLimit[$kind]
        if ($run -and $run.Kind -eq $kind) {
            $field.Value.Text = '…'
            $field.Text.Text = if ($now -lt $run.Start) { T $('Jetzt ins Spiel wechseln – Messung beginnt in {0:N0} s' -f [Math]::Ceiling(($run.Start - $now).TotalSeconds)) }
            else { T $('Misst im Spiel … noch {0:N0} s' -f [Math]::Ceiling(($run.End - $now).TotalSeconds)) }
        }
        elseif ($result) {
            $field.Value.Text = '{0:N0} W' -f $result.Watt
            $field.Text.Text = T $(if ($result.GpuGuessed) { 'Gemessen um {0:HH:mm} – Grafikkarte nur geschätzt, der Vergleich sagt so wenig' -f $result.Time } else { 'Gemessen um {0:HH:mm}, Mittel über {1} s im Spiel' -f $result.Time, $script:PowerLimitSeconds })
        }
        else {
            $field.Value.Text = '–'
            $field.Text.Text = T $(if ($kind -eq 'Off') { 'Spiel ohne Limit starten, hier „Messen“ und ins Spiel wechseln' } else { 'Limit im Spiel oder Treiber setzen, dann erneut messen' })
        }
    }
    $off = $script:PowerLimit['Off']; $on = $script:PowerLimit['On']
    if (-not $off -or -not $on) {
        $fields.Saving.Value.Text = '–'
        $fields.Saving.Text.Text = T 'Erst ohne, dann mit Limit messen'
        return
    }
    $diff = $off.Watt - $on.Watt
    $year = $diff / 1000.0 * [double]$script:Settings.GameHours * 365 * [double]$script:Settings.PowerPrice
    if ($diff -lt 1) {
        $fields.Saving.Value.Text = '0 €'
        $fields.Saving.Text.Text = T 'Kein Unterschied gemessen – das Limit greift wohl nicht oder liegt über der erreichten Bildrate'
        return
    }
    $fields.Saving.Value.Text = T $('{0:N0} € im Jahr' -f $year)
    $fields.Saving.Text.Text = T $('{0:N0} W weniger ({1:N0} %) bei {2} Std. Spielen am Tag' -f $diff, ($diff / $off.Watt * 100), $script:Settings.GameHours)
}
