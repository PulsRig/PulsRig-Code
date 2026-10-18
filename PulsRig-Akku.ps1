# PulsRig - Akku-Bericht für Notebooks. Wird von PulsRig.ps1 nach PulsRig-Problem.ps1 eingebunden.
#
# Wie viel der Akku noch fasst (Kapazität heute im Vergleich zu neu), wie oft er geladen wurde, wie lange er laut
# Windows hält und wie die Kapazität über die Monate nachgelassen hat. Die Zahlen kommen aus dem Akku-Bericht von
# Windows (powercfg /batteryreport, als XML); fehlt er, aus den Akku-Klassen von WMI. Seriennummern bleiben draußen.
# Einstieg: Knopf oben auf der Hardware-Seite (nur wenn ein Akku da ist) und "Was ist los?" → Sonstiges.

$script:Queries.Battery = @'
param($a)
$r = @{ Has = $false; Charge = $null; OnPower = $null; Batteries = @(); Runtime = ''; RuntimeNew = ''; History = @(); Source = '' }
try {
    $batteries = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
    if ($batteries.Count -gt 0) {
        $r.Has = $true
        $r.Charge = [int]$batteries[0].EstimatedChargeRemaining
        # 2 = am Netzteil, 1 = entlädt (Win32_Battery.BatteryStatus)
        $r.OnPower = [int]$batteries[0].BatteryStatus -ne 1
    }
}
catch { }
if (-not $r.Has) { return $r }
$file = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Akku-$PID.xml"
try {
    $null = & powercfg.exe /batteryreport /xml /output $file 2>&1
    if (Test-Path -LiteralPath $file) {
        [xml]$xml = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        $report = $xml.BatteryReport
        foreach ($battery in @($report.Batteries.Battery)) {
            if (-not $battery) { continue }
            $r.Batteries += @{ Name = "$($battery.Id)".Trim(); Maker = "$($battery.Manufacturer)".Trim(); Chemistry = "$($battery.Chemistry)".Trim()
                Design = [double]"0$($battery.DesignCapacity)"; Full = [double]"0$($battery.FullChargeCapacity)"; Cycles = [int]"0$($battery.CycleCount)" }
        }
        $r.Runtime = "$($report.RuntimeEstimates.FullChargeCapacity.ActiveRuntime)"
        $r.RuntimeNew = "$($report.RuntimeEstimates.DesignCapacity.ActiveRuntime)"
        # Kapazität im Lauf der Zeit: ein Eintrag je Zeitraum, davon der erste jedes Monats
        $months = @{}
        foreach ($entry in @($report.History.HistoryEntry)) {
            if (-not $entry) { continue }
            $day = "$($entry.LocalStartDate)"; if (-not $day) { $day = "$($entry.StartDate)" }
            if ($day.Length -lt 7) { continue }
            $month = $day.Substring(0, 7)
            if (-not $months.ContainsKey($month)) { $months[$month] = @{ Month = $month; Full = [double]"0$($entry.FullChargeCapacity)"; Design = [double]"0$($entry.DesignCapacity)" } }
        }
        $r.History = @($months.Keys | Sort-Object | ForEach-Object { $months[$_] })
        $r.Source = 'report'
    }
}
catch { }
finally { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue } }
# ohne Bericht: Auslegungs- und volle Ladekapazität direkt aus WMI
if ($r.Batteries.Count -eq 0) {
    try {
        $design = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop)
        $full = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop)
        $cycles = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $design.Count; $i++) {
            $r.Batteries += @{ Name = "$($design[$i].DeviceName)".Trim(); Maker = "$($design[$i].ManufactureName)".Trim(); Chemistry = ''
                Design = [double]$design[$i].DesignedCapacity; Full = $(if ($i -lt $full.Count) { [double]$full[$i].FullChargedCapacity } else { 0.0 })
                Cycles = $(if ($i -lt $cycles.Count) { [int]$cycles[$i].CycleCount } else { 0 }) }
        }
        $r.Source = 'wmi'
    }
    catch { }
}
$r
'@

# ausführlicher Bericht von Windows als Seite im Browser (liegt danach im Ordner von PulsRig)
$script:Queries.BatteryPage = @'
param($a)
$file = Join-Path $a.Folder 'Akku-Bericht.html'
$null = & powercfg.exe /batteryreport /output $file 2>&1
if (Test-Path -LiteralPath $file) { $file } else { '' }
'@

$script:HasBattery = $false

function Open-BatterySheet {
    $opened = Open-Sheet @{
        Title    = 'Akku'
        Sub      = 'Wie viel der Akku noch fasst und wie lange er hält'
        Glyph    = 0xE83F
        Link     = 'Ausführlicher Bericht von Windows'
        Show     = { param($tab) Show-BatteryTab }
        OnLink   = {
            Set-SheetStateText 'Erstelle den Bericht …'
            Start-Query 'BatteryPage' {
                param($result)
                if ("$result" -and (Test-Path -LiteralPath "$result")) { try { Start-Process "$result" } catch { } ; Set-SheetStateText 'Der Bericht liegt jetzt auch im Ordner von PulsRig' }
                else { Set-SheetStateText 'Windows hat keinen Bericht erstellt' }
            } @{ Folder = (Get-TargetDir) }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese den Akku …'
    Start-Query 'Battery' { param($result) Complete-BatteryQuery $result }
}

# "PT3H4M5S" (so schreibt Windows Zeitspannen) → "3 Std. 4 Min."
function Format-BatteryTime([string]$Text) {
    if (-not $Text) { return '' }
    try { $span = [Xml.XmlConvert]::ToTimeSpan($Text) } catch { return '' }
    if ($span.TotalMinutes -lt 1) { return '' }
    if ($span.TotalHours -ge 1) { '{0} Std. {1} Min.' -f [int][Math]::Floor($span.TotalHours), $span.Minutes } else { '{0} Min.' -f $span.Minutes }
}

# Zustand: volle Ladekapazität im Verhältnis zur ursprünglichen
function Get-BatteryHealth($Battery) {
    if (-not $Battery -or $Battery.Design -le 0 -or $Battery.Full -le 0) { return $null }
    $percent = [Math]::Min(100, [int][Math]::Round(100.0 * $Battery.Full / $Battery.Design))
    $tone = if ($percent -ge 80) { 'good' } elseif ($percent -ge 60) { 'warn' } else { 'bad' }
    @{ Percent = $percent; Tone = $tone }
}

function Complete-BatteryQuery($Result) {
    if (-not $script:Sheet -or $script:Sheet.Title -ne 'Akku') { return }
    $script:Sheet.Battery = $Result
    $first = @($Result.Batteries)[0]
    $health = Get-BatteryHealth $first
    if ($health) {
        Set-CardState 'Battery' @{ Text = "$($health.Percent) %"; Tone = $health.Tone; Detail = $(if ($first.Cycles -gt 0) { "$($first.Cycles) Ladezyklen" } else { '' }) }
        Update-BatteryPill
    }
    Show-BatteryTab
}

function Show-BatteryTab {
    $data = $script:Sheet.Battery
    if (-not $data) { Start-SheetLoader 'Lese den Akku …'; return }
    $ui.SheetChips.Children.Clear()
    $rows = @()
    if (-not $data.Has) {
        $rows += New-SheetRow -Title 'Kein Akku gefunden' -Sub 'Dieser PC läuft am Netz - ein Akku-Bericht gibt es nur bei Notebooks und Tablets.' -Glyph 0xE83F -Tone ''
        Show-SheetList $rows
        Set-SheetStateText ''
        return
    }
    $batteries = @($data.Batteries)
    if ($batteries.Count -eq 0) {
        $rows += New-SheetRow -Title 'Windows gibt die Kapazität nicht heraus' -Sub 'Der Akku ist da, aber Windows meldet nicht, wie viel er noch fasst. Der ausführliche Bericht von Windows zeigt, was es weiß.' -Glyph 0xE83F -Tone 'warn'
    }
    foreach ($battery in $batteries) {
        $health = Get-BatteryHealth $battery
        if ($batteries.Count -gt 1) { $rows += New-SheetRow -Kind 'head' -Title ("AKKU " + $battery.Name).ToUpper() }
        if ($health) {
            Add-ResultChip "Zustand $($health.Percent) %" $(switch ($health.Tone) { 'good' { 'Good' } 'warn' { 'Warn' } default { 'Bad' } }) $ui.SheetChips
            $verdict = switch ($health.Tone) {
                'good' { 'Der Akku ist gut in Schuss.' }
                'warn' { 'Der Akku hat merklich nachgelassen; das ist nach einigen Jahren normal.' }
                default { 'Der Akku fasst nur noch wenig. Ein Tausch lohnt sich, wenn das Notebook oft ohne Netzteil laufen soll.' }
            }
            $rows += New-SheetRow -Title "Fasst noch $($health.Percent) % von neu" -Sub ('{0} Heute {1:N0} mWh, neu waren es {2:N0} mWh.' -f $verdict, $battery.Full, $battery.Design) -Glyph 0xE83F -Tone $health.Tone -Bar ($health.Percent / 100.0) -State "$($health.Percent) %"
        }
        if ($battery.Cycles -gt 0) {
            Add-ResultChip "$($battery.Cycles) Ladezyklen" 'Accent' $ui.SheetChips
            $rows += New-SheetRow -Title "$($battery.Cycles) Ladezyklen" -Sub 'Ein Zyklus ist einmal ganz leer und wieder voll, auch in Teilen. Übliche Akkus sind für 300 bis 1.000 Zyklen gebaut.' -Glyph 0xE895 -Tone $(if ($battery.Cycles -ge 800) { 'warn' } else { 'accent' })
        }
        $about = @($battery.Maker, $(switch ("$($battery.Chemistry)") { 'LION' { 'Lithium-Ionen' } 'LiP' { 'Lithium-Polymer' } 'Li-I' { 'Lithium-Ionen' } default { "$($battery.Chemistry)" } })) | Where-Object { $_ }
        if ($about) { $rows += New-SheetRow -Title "$($battery.Name)" -Sub ($about -join ' · ') -Glyph 0xE946 -Tone '' }
    }
    if ($null -ne $data.Charge) {
        $rows += New-SheetRow -Title "Gerade $($data.Charge) % geladen" -Sub $(if ($data.OnPower) { 'Das Netzteil ist angeschlossen.' } else { 'Das Notebook läuft gerade mit Akku.' }) -Glyph 0xE945 -Tone 'accent' -Bar ($data.Charge / 100.0)
    }
    $now = Format-BatteryTime $data.Runtime
    $new = Format-BatteryTime $data.RuntimeNew
    if ($now) { $rows += New-SheetRow -Title "Hält etwa $now" -Sub $(if ($new) { "Schätzung von Windows bei voller Ladung und üblicher Nutzung. Neu wären es etwa $new gewesen." } else { 'Schätzung von Windows bei voller Ladung und üblicher Nutzung.' }) -Glyph 0xE916 -Tone 'accent' }
    $history = @($data.History | Where-Object { $_.Full -gt 0 -and $_.Design -gt 0 })
    if ($history.Count -ge 2) {
        $rows += New-SheetRow -Kind 'head' -Title 'VERLAUF DER KAPAZITÄT'
        $pick = if ($history.Count -le 6) { $history } else { @($history[0]) + @($history[-5..-1]) }
        foreach ($month in $pick) {
            $percent = [Math]::Min(100, [int][Math]::Round(100.0 * $month.Full / $month.Design))
            $label = try { ([datetime]::ParseExact($month.Month, 'yyyy-MM', [cultureinfo]::InvariantCulture)).ToString('MM.yyyy') } catch { $month.Month }
            $rows += New-SheetRow -Title $label -State "$percent %" -Bar ($percent / 100.0) -Tone $(if ($percent -ge 80) { 'good' } elseif ($percent -ge 60) { 'warn' } else { 'bad' })
        }
    }
    $rows += New-SheetRow -Kind 'head' -Title 'AKKU SCHONEN'
    $rows += New-SheetRow -Title 'Nicht dauernd auf 100 %' -Sub 'Viele Hersteller-Programme (Lenovo Vantage, MyASUS, Dell Power Manager, Acer Care Center) können das Laden bei 80 % stoppen. Das verlängert die Lebensdauer deutlich.' -Glyph 0xE8FB -Tone 'accent'
    $rows += New-SheetRow -Title 'Hitze meiden' -Sub 'Beim Spielen auf dem Schoß oder auf der Bettdecke wird es unter dem Notebook heiß; Wärme altert den Akku am stärksten.' -Glyph 0xE706 -Tone 'accent'
    Show-SheetList $rows
    Set-SheetStateText $(if ($data.Source -eq 'wmi') { 'Werte aus der Akku-Schnittstelle von Windows' } else { 'Werte aus dem Akku-Bericht von Windows' })
}

# Knopf oben auf der Hardware-Seite: erscheint nur, wenn ein Akku da ist, und zeigt den letzten Zustand
# Seit 17.10.2026 steht der Akku als Zeile unten in der Sensoren-Karte (nur auf Notebooks); ein Klick darauf öffnet
# das Akku-Fenster statt der Messung. Der Knopf über den Karten bleibt unsichtbar.
function Update-BatteryPill {
    if (-not $ui.HardwareBatteryPill) { return }
    $ui.HardwareBatteryPill.Visibility = 'Collapsed'
    $card = $script:HardwareCards[0]
    if ($card -and $card.Stack) {
        if (-not $script:BatteryRow) {
            $row = New-Object Windows.Controls.Border
            $row.Cursor = 'Hand'; $row.Margin = '0,8,0,0'; $row.Padding = '10,5'
            $row.CornerRadius = (Get-SkinRadius 10); $row.Background = New-Brush '#0DFFFFFF'
            $line = New-Object Windows.Controls.DockPanel
            $glyph = New-Object Windows.Controls.TextBlock
            $glyph.Text = Get-Glyph 0xE83F; $glyph.FontFamily = 'Segoe MDL2 Assets'; $glyph.FontSize = 13; $glyph.Margin = '0,1,8,0'; $glyph.VerticalAlignment = 'Center'
            $value = New-Object Windows.Controls.TextBlock
            $value.FontSize = 12; $value.VerticalAlignment = 'Center'; $value.HorizontalAlignment = 'Right'
            [Windows.Controls.DockPanel]::SetDock($glyph, 'Left')
            [Windows.Controls.DockPanel]::SetDock($value, 'Right')
            $label = New-Object Windows.Controls.TextBlock
            $label.FontSize = 12; $label.VerticalAlignment = 'Center'; $label.Text = T 'Akku'
            Set-Paint $label 'Foreground' 'Text'
            foreach ($part in $glyph, $value, $label) { [void]$line.Children.Add($part) }
            $row.Child = $line
            $row.Add_MouseLeftButtonUp({ param($sender, $e) try { $e.Handled = $true; Open-BatterySheet } catch { Write-AppError $_ } })
            $script:BatteryRow = @{ Row = $row; Glyph = $glyph; Value = $value }
            [void]$card.Stack.Children.Add($row)
        }
        # Tag "keep": Update-HardwareVisuals lässt die Zeile stehen und rückt sie unter das Bild der Karte
        $script:BatteryRow.Row.Tag = if ($script:HasBattery) { 'keep' } else { '' }
        $script:BatteryRow.Row.Visibility = if ($script:HasBattery) { 'Visible' } else { 'Collapsed' }
        $now = $script:CardState.Battery
        $script:BatteryRow.Value.Text = if ($now -and $now.Text) { T "Zustand $($now.Text)" } else { T 'ansehen' }
        $tone = if ($now) { switch ("$($now.Tone)") { 'good' { 'Good' } 'warn' { 'Warn' } 'bad' { 'Bad' } default { 'Accent' } } } else { 'Accent' }
        Set-Paint $script:BatteryRow.Glyph 'Foreground' $tone
        Set-Paint $script:BatteryRow.Value 'Foreground' $tone
        # das Bild der Sensoren-Karte hängt davon ab, ob die Zeile da ist (ohne Kurve, damit beides passt)
        if (-not $script:BatteryRowShown -or $script:BatteryRowShown -ne "$($script:HasBattery)") { $script:BatteryRowShown = "$($script:HasBattery)"; Update-HardwareVisuals }
    }
}

$ui.HardwareBatteryPill.Add_MouseLeftButtonUp({ try { Open-BatterySheet } catch { Write-AppError $_ } })
# Ob ein Akku da ist, fragt das Fenster einmal kurz selbst (Win32_Battery antwortet schnell)
try { $script:HasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop) } catch { $script:HasBattery = $false }
if ($env:PULSRIG_AKKU) { $script:HasBattery = $true }   # Probelauf: Knopf auch auf einem PC ohne Akku zeigen
Update-BatteryPill
