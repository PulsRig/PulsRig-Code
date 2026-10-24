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

    # ohne gemessenen Prozessor: der Hinweis mit dem Knopf zum Freischalten (wie im Fenster Sensoren)
    if (-not $script:CpuTempSeen -or (-not $sync.CpuTempDemo -and "$([PulsRigCpuTemp]::Source)" -eq 'Core Temp')) { Add-CpuTempHint }

    if ($script:Power) { $script:Power.Timer.Stop() }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({ try { Update-PowerPanel } catch { Write-AppError $_ } })
    $script:Power = @{ Fields = $fields; Timer = $timer; Stamp = 0; Sum = 0.0; Count = 0; Last = $null }
    $timer.Start()
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
