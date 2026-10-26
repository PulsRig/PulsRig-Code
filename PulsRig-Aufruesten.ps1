# PulsRig - Aufrüst-Berater. Wird von PulsRig.ps1 nach PulsRig-Strom.ps1 eingebunden.
#
# Misst eine Minute lang im laufenden Spiel, was bremst, und sagt in einem Satz, welches Bauteil sich zum Aufrüsten lohnt:
#   Prozessor    - der am stärksten belastete Kern (CpuCoreMax der Messschleife in PulsRig-Hardware.ps1). Die Gesamtlast
#                  täuscht: ein Spiel kann einen Kern voll auslasten, während der Mittelwert bei 30 % steht.
#   Grafikkarte  - Auslastung über nvidia-smi, also nur bei NVIDIA sicher; sonst sagt PulsRig das so
#   Speicher     - Belegung des Arbeitsspeichers und bei NVIDIA des Grafikspeichers
# Dazu die Bestandsaufnahme: Prozessor, Grafikkarte, RAM-Steckplätze (aus der Abfrage des Fensters Arbeitsspeicher)
# und ob ein laufendes Spiel auf einer Festplatte statt einer SSD liegt. Keine Kauf- oder Partner-Links.

$script:UpgradeLead = 10       # s Vorlauf, um ins Spiel zu wechseln
$script:UpgradeSeconds = 60    # s Messdauer
$script:Upgrade = $null        # das offene Fenster: Felder, Timer, laufende Messung
$script:UpgradeResult = $null  # letzte Messung, bleibt bis zum Beenden

$script:Queries.Upgrade = @'
param($a)
$r = @{ Cpu = ''; Cores = 0; Threads = 0; Gpus = @(); Memory = $null; Games = @(); Kinds = @{} }
try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $r.Cpu = ("$($cpu.Name)" -replace '\s+', ' ').Trim()
    $r.Cores = [int]$cpu.NumberOfCores
    $r.Threads = [int]$cpu.NumberOfLogicalProcessors
}
catch { }
try {
    # Bildschirmtreiber ohne eigene Hardware (Fernzugriff, virtuelle Anzeigen) zählen nicht
    $r.Gpus = @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.PNPDeviceID)" -like 'PCI\*' } | ForEach-Object { ("$($_.Name)" -replace '\s+', ' ').Trim() })
}
catch { }
if ($a -and $a.Memory) { try { $r.Memory = & ([scriptblock]::Create($a.Memory)) $null } catch { } }
# Laufwerksbuchstabe -> Bauart, für die Frage, ob das Spiel auf einer Festplatte liegt
try {
    $disks = @(Get-DiskList)
    foreach ($partition in @(Get-PartitionList | Where-Object { $_.DriveLetter })) {
        $disk = @($disks | Where-Object { "$($_.DeviceId)" -eq "$($partition.DiskNumber)" })[0]
        $r.Kinds["$($partition.DriveLetter)".ToUpper()] = if (-not $disk) { '' } elseif ("$($disk.BusType)" -eq 'NVMe') { 'NVMe' } else { "$($disk.MediaType)" }
    }
}
catch { }
foreach ($game in @(Get-KnownGames)) {
    $letter = if ("$($game.Path)" -match '^([A-Za-z]):') { $Matches[1].ToUpper() } else { '' }
    $r.Games += @{ Name = "$($game.Name)"; Exe = "$($game.Exe)"; Letter = $letter }
}
$r
'@

function Open-UpgradeSheet {
    $opened = Open-Sheet @{
        Title   = 'Aufrüst-Berater'
        Sub     = 'Im Spiel messen, was bremst, und was sich zum Aufrüsten lohnt'
        Glyph   = 0xE9F9
        Show    = { param($tab) Show-UpgradePanel }
        OnClose = { Stop-UpgradeSheet }
    }
    if (-not $opened) { return }
    Start-Sensors
    Start-Query 'Upgrade' { param($result) Complete-UpgradeQuery $result } @{ Memory = $script:Queries.Memory }
}

function Stop-UpgradeSheet {
    if ($script:Upgrade) { $script:Upgrade.Timer.Stop(); $script:Upgrade = $null }
    Stop-Sensors
}

function Complete-UpgradeQuery($Result) {
    if (-not $script:Sheet -or $script:Sheet.Title -ne 'Aufrüst-Berater') { return }
    $script:Sheet.Upgrade = $Result
    Show-UpgradePanel
}

function Show-UpgradePanel {
    $data = $script:Sheet.Upgrade
    if (-not $data) { Start-SheetLoader 'Lese Prozessor, Grafikkarte und Arbeitsspeicher …'; return }
    Show-SheetPanel
    $script:SensorTiles = @{}   # die Messschleife zeichnet hier keine Kacheln
    $fields = @{}

    $slot = Add-SettingRow 'Messung im Spiel' 'Spiel starten, hier „Messen“ und ins Spiel wechseln. PulsRig misst eine Minute lang.' 0xE7FC
    $chip = New-SettingChip 'Messen' 'measure'
    $chip.Add_Click({ try { Start-UpgradeMeasure } catch { Write-AppError $_ } })
    [void]$slot.Children.Add($chip)
    $fields.Run = @{ Text = $slot.Parent.FindName('Text'); Chip = $chip }

    $slot = Add-SettingRow 'Ergebnis' 'Noch nicht gemessen' 0xE9D9
    $fields.Verdict = @{ Text = $slot.Parent.FindName('Text'); Title = $slot.Parent.FindName('Title') }

    foreach ($part in @('Cpu', 'Prozessor · stärkster Kern', 0xE950), @('Gpu', 'Grafikkarte · Auslastung', 0xE7F4), @('Ram', 'Arbeitsspeicher · belegt', 0xE964)) {
        $slot = Add-SettingRow $part[1] '' $part[2]
        $value = New-PowerValue '–' 18
        [void]$slot.Children.Add($value)
        $text = $slot.Parent.FindName('Text')
        $text.Visibility = 'Visible'
        $fields[$part[0]] = @{ Value = $value; Text = $text }
    }

    # Bestandsaufnahme
    $cpuText = if ($data.Cores) { T $('{0} Kerne, {1} Threads' -f $data.Cores, $data.Threads) } else { '' }
    [void](Add-SettingRow $(if ($data.Cpu) { $data.Cpu } else { 'Prozessor unbekannt' }) $cpuText 0xE950)
    $gpus = @($data.Gpus)
    [void](Add-SettingRow $(if ($gpus.Count) { $gpus -join ' · ' } else { 'Grafikkarte unbekannt' }) $(if ($gpus | Where-Object { $_ -match 'NVIDIA' }) { 'NVIDIA: Auslastung messbar' } else { 'Keine NVIDIA-Karte: ihre Auslastung kann PulsRig nicht sicher messen' }) 0xE7F4)
    $memory = Get-UpgradeMemory $data.Memory
    $slot = Add-SettingRow $memory.Title $memory.Text 0xE964
    if ($memory.Chip) {
        $value = New-PowerValue $memory.Chip 15
        Set-Paint $value 'Foreground' $(if ($memory.Free) { 'Accent' } else { 'Text' })
        [void]$slot.Children.Add($value)
    }
    $slot = Add-SettingRow 'Laufwerk des Spiels' 'Wird beim Messen erkannt, wenn ein bekanntes Spiel läuft' 0xEDA2
    $fields.Drive = @{ Text = $slot.Parent.FindName('Text'); Title = $slot.Parent.FindName('Title') }

    if ($script:Upgrade) { $script:Upgrade.Timer.Stop() }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({ try { Update-UpgradePanel } catch { Write-AppError $_ } })
    $script:Upgrade = @{ Fields = $fields; Timer = $timer; Stamp = 0; Run = $null }
    $timer.Start()
    Update-UpgradePanel
    $ui.SheetState.Text = T 'PulsRig schließt nichts und stellt nichts um – es misst nur'
}

# Zeile Arbeitsspeicher: Größe, Art, Takt und wie viele Steckplätze frei sind
function Get-UpgradeMemory($Memory) {
    if (-not $Memory) { return @{ Title = 'Arbeitsspeicher'; Text = 'Ließ sich nicht lesen'; Chip = ''; Free = $false } }
    $modules = @($Memory.Modules)
    $installed = [double](($modules | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
    if ($installed -le 0) { $installed = [double]$Memory.Total }
    $first = @($modules | Select-Object -First 1)[0]
    $kind = (@($(if ($first.Type) { $first.Type }), $(if ($first.Speed) { "$($first.Speed) MT/s" })) | Where-Object { $_ }) -join ' · '
    $title = (@(('{0:N0} GB Arbeitsspeicher' -f ($installed / 1GB)), $kind) | Where-Object { $_ }) -join ' · '
    $slots = [int]$Memory.Slots
    if ($slots -le 0 -or $slots -lt $modules.Count) {
        return @{ Title = $title; Text = T $('{0} Riegel eingebaut; wie viele Steckplätze es gibt, meldet das BIOS nicht' -f $modules.Count); Chip = ''; Free = $false }
    }
    $free = $slots - $modules.Count
    $parts = @(T $('{0} von {1} Steckplätzen belegt' -f $modules.Count, $slots))
    if ($Memory.MaxBytes -gt 0) { $parts += T $('höchstens {0:N0} GB laut BIOS' -f ($Memory.MaxBytes / 1GB)) }
    if (@($modules | Where-Object { $_.Laptop }).Count) { $parts += T 'Laptop-Riegel (SO-DIMM); manche sind fest verlötet' }
    elseif ($free -gt 0 -and $modules.Count -eq 1) { $parts += T 'ein zweiter gleicher Riegel bringt Dual-Channel' }
    elseif ($free -gt 0) { $parts += T 'zum Aufrüsten möglichst gleiche Riegel nehmen' }
    @{ Title = $title; Text = $parts -join ' · '; Chip = $(if ($free -eq 1) { T '1 Platz frei' } elseif ($free -gt 1) { T "$free Plätze frei" } else { T 'alle belegt' }); Free = $free -gt 0 }
}

# PulsRig stellt nichts um: der Nutzer startet die Messung, wechselt ins Spiel, nach dem Vorlauf sammelt PulsRig
# eine Minute lang die Werte der Messschleife. Das Fenster bleibt dabei offen.
function Start-UpgradeMeasure {
    if (-not $script:Upgrade) { return }
    $start = [DateTime]::Now.AddSeconds($script:UpgradeLead)
    $script:Upgrade.Run = @{ Start = $start; End = $start.AddSeconds($script:UpgradeSeconds); Samples = New-Object Collections.ArrayList }
    Update-UpgradePanel
}

function Update-UpgradePanel {
    $upgrade = $script:Upgrade
    if (-not $upgrade -or -not $script:Sheet -or $script:Sheet.Title -ne 'Aufrüst-Berater') { return }
    $fields = $upgrade.Fields
    $values = $sync.Sensors
    $run = $upgrade.Run
    $now = [DateTime]::Now
    if ($values -and $values.Stamp -ne $upgrade.Stamp) {
        $upgrade.Stamp = $values.Stamp
        if ($run -and $now -ge $run.Start) { [void]$run.Samples.Add($values) }
    }
    if ($run -and $now -ge $run.End) {
        $samples = @($run.Samples)
        $upgrade.Run = $run = $null
        $script:UpgradeResult = Get-UpgradeResult $samples $script:Sheet.Upgrade
    }
    if ($run) {
        $fields.Run.Chip.IsEnabled = $false
        $fields.Run.Text.Text = if ($now -lt $run.Start) { T $('Jetzt ins Spiel wechseln – Messung beginnt in {0:N0} s' -f [Math]::Ceiling(($run.Start - $now).TotalSeconds)) }
        else { T $('Misst im Spiel … noch {0:N0} s' -f [Math]::Ceiling(($run.End - $now).TotalSeconds)) }
    }
    else {
        $fields.Run.Chip.IsEnabled = $true
        $fields.Run.Text.Text = T $(if ($script:UpgradeResult) { 'Gemessen um {0:HH:mm}. Für ein anderes Spiel oder andere Einstellungen erneut messen.' -f $script:UpgradeResult.Time } else { 'Spiel starten, hier „Messen“ und ins Spiel wechseln. PulsRig misst eine Minute lang.' })
    }
    Show-UpgradeResult $script:UpgradeResult
    # ohne Ergebnis zeigen die Zeilen die Werte von gerade
    if (-not $script:UpgradeResult -and $values) {
        $fields.Cpu.Value.Text = if ($null -ne $values.CpuCoreMax) { '{0:N0} %' -f $values.CpuCoreMax } else { '–' }
        $fields.Cpu.Text.Text = T $(if ($null -ne $values.CpuLoad) { 'Gerade · alle Kerne zusammen {0:N0} %' -f $values.CpuLoad } else { 'Gerade' })
        $fields.Gpu.Value.Text = if ($null -ne $values.GpuLoad) { '{0:N0} %' -f $values.GpuLoad } else { '–' }
        $fields.Gpu.Text.Text = T $(if ($null -ne $values.GpuLoad) { 'Gerade' } else { 'Nur bei NVIDIA messbar' })
        $fields.Ram.Value.Text = if ($null -ne $values.Ram) { '{0:N0} %' -f $values.Ram } else { '–' }
        $fields.Ram.Text.Text = T 'Gerade'
    }
}

# Mittel und Anteil der Sekunden am Anschlag; $null ohne Werte
function Get-UpgradeStat($Samples, [string]$Key, [double]$Limit) {
    $list = @($Samples | ForEach-Object { $_[$Key] } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if (-not $list.Count) { return $null }
    @{ Mean = ($list | Measure-Object -Average).Average; Busy = @($list | Where-Object { $_ -ge $Limit }).Count / $list.Count }
}

function Get-UpgradeResult($Samples, $Data) {
    $samples = @($Samples)
    $r = @{ Time = [DateTime]::Now; Count = $samples.Count
        Core = (Get-UpgradeStat $samples 'CpuCoreMax' 90); Cpu = (Get-UpgradeStat $samples 'CpuLoad' 90)
        Gpu = (Get-UpgradeStat $samples 'GpuLoad' 95); Ram = (Get-UpgradeStat $samples 'Ram' 90); Vram = $null; Game = $null }
    $vram = @($samples | Where-Object { $_.GpuMemoryTotal -gt 0 } | ForEach-Object { 100.0 * $_.GpuMemory / $_.GpuMemoryTotal })
    if ($vram.Count) { $r.Vram = ($vram | Measure-Object -Average).Average }
    # welches bekannte Spiel lief gerade, und auf welchem Laufwerk liegt es?
    foreach ($game in @($Data.Games)) {
        if (Get-Process -Name $game.Exe -ErrorAction SilentlyContinue) { $r.Game = @{ Name = $game.Name; Letter = $game.Letter; Kind = "$($Data.Kinds[$game.Letter])" }; break }
    }
    $r
}

# Satz und Werte zu einer Messung; die Schwellen sind bewusst grob, die Messung dauert nur eine Minute
function Get-UpgradeVerdict($Result) {
    if (-not $Result.Count) { return @{ Title = 'Keine Messwerte'; Text = 'Die Messschleife hat in dieser Minute nichts geliefert. Bitte erneut messen.' } }
    $gpu = $Result.Gpu; $core = $Result.Core; $ram = $Result.Ram
    $tips = @()
    if ($ram -and $ram.Mean -ge 90) { $tips += 'Der Arbeitsspeicher war fast voll: Windows lagert aus, das ruckelt. Mehr RAM hilft.' }
    if ($null -ne $Result.Vram -and $Result.Vram -ge 95) { $tips += 'Der Grafikspeicher war voll: Texturdetails eine Stufe senken oder eine Karte mit mehr Speicher.' }
    if ($gpu -and $gpu.Mean -ge 90) {
        $main = @{ Title = 'Die Grafikkarte bremst'; Text = 'Sie war fast die ganze Zeit voll ausgelastet. Eine stärkere Grafikkarte bringt am meisten; der Prozessor hätte noch Luft.' }
        if ($core -and $core.Mean -ge 90) { $main.Text = 'Sie war voll ausgelastet, aber auch ein Prozessorkern stand am Anschlag: beide liegen gleichauf, eine neue Grafikkarte allein bringt weniger als gedacht.' }
    }
    elseif ($core -and $core.Mean -ge 85 -and (-not $gpu -or $gpu.Mean -lt 80)) {
        $main = @{ Title = 'Der Prozessor bremst'; Text = 'Ein Kern war fast ständig am Anschlag, obwohl der Prozessor insgesamt weniger zeigt. Spiele hängen an ihrem Hauptkern: ein Prozessor mit mehr Leistung je Kern hilft, mehr Kerne allein nicht.' }
        if (-not $gpu) { $main.Text += ' Die Grafikkarte konnte PulsRig nicht messen.' }
    }
    elseif (-not $gpu) {
        $main = @{ Title = 'Der Prozessor bremst eher nicht'; Text = 'Kein Kern stand dauernd am Anschlag. Die Grafikkarte kann PulsRig ohne NVIDIA nicht messen – dann ist sie der wahrscheinliche Engpass.' }
    }
    else {
        $main = @{ Title = 'Nichts stand am Anschlag'; Text = 'Weder Grafikkarte noch Prozessor waren voll ausgelastet. Meist begrenzt ein FPS-Limit oder V-Sync – dann ist der PC schnell genug. Oder das Spiel lief nicht im Vordergrund.' }
    }
    if ($tips.Count) { $main.Text = "$($main.Text) $($tips -join ' ')" }
    $main
}

function Show-UpgradeResult($Result) {
    $fields = $script:Upgrade.Fields
    if (-not $Result) { return }
    $verdict = Get-UpgradeVerdict $Result
    $fields.Verdict.Title.Text = T $verdict.Title
    $fields.Verdict.Text.Text = T $verdict.Text
    $fields.Verdict.Text.Visibility = 'Visible'
    Set-Paint $fields.Verdict.Title 'Foreground' 'Accent'
    $core = $Result.Core; $cpu = $Result.Cpu; $gpu = $Result.Gpu; $ram = $Result.Ram
    $fields.Cpu.Value.Text = if ($core) { '{0:N0} %' -f $core.Mean } else { '–' }
    $fields.Cpu.Text.Text = if ($core) { T $('Mittel im Spiel, {0:N0} % der Zeit über 90 % · alle Kerne zusammen nur {1:N0} %' -f ($core.Busy * 100), $(if ($cpu) { $cpu.Mean } else { 0 })) } else { T 'Nicht messbar' }
    $fields.Gpu.Value.Text = if ($gpu) { '{0:N0} %' -f $gpu.Mean } else { '–' }
    $fields.Gpu.Text.Text = if ($gpu) { T $('Mittel im Spiel, {0:N0} % der Zeit über 95 %' -f ($gpu.Busy * 100)) } else { T 'Nur bei NVIDIA messbar' }
    $fields.Ram.Value.Text = if ($ram) { '{0:N0} %' -f $ram.Mean } else { '–' }
    $fields.Ram.Text.Text = if ($null -ne $Result.Vram) { T $('Mittel im Spiel · Grafikspeicher {0:N0} % belegt' -f $Result.Vram) } else { T 'Mittel im Spiel' }
    $game = $Result.Game
    if ($game) {
        $fields.Drive.Title.Text = T "Laufwerk von $($game.Name)"
        $fields.Drive.Text.Text = T $(switch ($game.Kind) {
                'HDD' { 'Liegt auf {0}: – einer Festplatte. Auf einer SSD lädt es viel schneller und ruckelt beim Nachladen weniger.' -f $game.Letter }
                'NVMe' { 'Liegt auf {0}: – einer NVMe-SSD. Da gibt es nichts zu verbessern.' -f $game.Letter }
                'SSD' { 'Liegt auf {0}: – einer SSD. Das passt.' -f $game.Letter }
                default { 'Liegt auf {0}:; die Bauart des Laufwerks meldet Windows nicht.' -f $game.Letter }
            })
    }
    else { $fields.Drive.Text.Text = T 'Beim Messen lief kein Spiel, das Windows als Spiel kennt' }
}
