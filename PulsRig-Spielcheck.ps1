# PulsRig - Gaming-Check "Ist mein PC richtig eingestellt?". Wird von PulsRig.ps1 nach PulsRig-Aenderungen.ps1 eingebunden.
#
# Eine Ampel-Liste mit sieben Prüfungen, die fürs Spielen zählen, und ein Wert von 0 bis 100:
#   Bildwiederholrate (läuft der 144-Hz-Bildschirm mit 60 Hz?), Resizable BAR (nur bei NVIDIA auslesbar),
#   hardwarebeschleunigte GPU-Planung, Kernisolierung, Energieplan, voller Takt des Arbeitsspeichers (XMP), Spielmodus.
# Grün zählt 2, Gelb 1, Rot 0; was sich nicht prüfen lässt (grau), zählt nicht mit. Die Kernisolierung ist an gelb,
# nie rot: sie kostet in manchen Spielen etwas Leistung, schützt aber - abschalten ist eine Abwägung.
# Geändert wird hier nichts: jede Zeile führt zur Stelle, an der man es selbst einstellt.
# Knopf oben rechts auf der Boost-Seite; der letzte Wert steht in der Ergebnisdatei (Kartenzustand "GameCheck").

$script:Queries.GameCheck = @'
param($a)
$r = @{ Displays = @(); Bar = $null; Gpu = ''; Hags = $null; Hvci = $null; PlanGuid = ''; Plan = ''; Battery = $false; GameMode = $true; Memory = $null }
try {
    foreach ($d in @(Get-DisplayStatus)) {
        if (-not $d.Current) { continue }
        $rates = @($d.Modes | Where-Object { $_.Width -eq $d.Current.Width -and $_.Height -eq $d.Current.Height } | ForEach-Object { [int]$_.Frequency } | Sort-Object -Unique)
        $r.Displays += @{ Name = "$($d.Name)"; Width = [int]$d.Current.Width; Height = [int]$d.Current.Height; Hz = [int]$d.Current.Frequency
            Max = $(if ($rates.Count) { [int]$rates[-1] } else { [int]$d.Current.Frequency }); Primary = [bool]$d.Primary }
    }
}
catch { }
try { $r.Gpu = "$(@(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { "$($_.PNPDeviceID)" -like 'PCI*' })[0].Name)" } catch { }
# Resizable BAR: bei NVIDIA ist das Fenster BAR1 dann so groß wie der Grafikspeicher, sonst 256 MB
$exe = Join-Path $env:WINDIR 'System32\nvidia-smi.exe'
if (-not (Test-Path -LiteralPath $exe)) { $exe = $(try { (Get-Command nvidia-smi.exe -ErrorAction Stop).Source } catch { $null }) }
if ($exe) {
    try { if (((& $exe -q -d MEMORY) -join "`n") -match 'BAR1 Memory Usage\s+Total\s*:\s*(\d+)\s*MiB') { $r.Bar = [int]$Matches[1] } } catch { }
}
try { $r.Hags = [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction Stop).HwSchMode } catch { }
try { $r.Hvci = @((Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop).SecurityServicesRunning) -contains 2 }
catch {
    try { $r.Hvci = [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction Stop).Enabled -eq 1 } catch { }
}
try { if ("$(powercfg /getactivescheme)" -match '([0-9a-fA-F\-]{36})\s+\((.+)\)') { $r.PlanGuid = $Matches[1].ToLower(); $r.Plan = $Matches[2].Trim() } } catch { }
try { $r.Battery = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop) } catch { }
# fehlt der Wert, ist der Spielmodus an (Vorgabe von Windows)
try { $r.GameMode = [int](Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -ErrorAction Stop).AutoGameModeEnabled -ne 0 } catch { }
if ($a.Memory) { try { $r.Memory = & ([scriptblock]::Create($a.Memory)) @{} } catch { } }
$r
'@

function Open-GameCheckSheet {
    $opened = Open-Sheet @{
        Title    = 'Gaming-Check'
        Sub      = 'Ist der PC richtig eingestellt? Sieben Punkte, die fürs Spielen zählen'
        Glyph    = 0xE7FC
        Link     = 'Neu prüfen'
        Show     = { param($tab) Show-GameCheckTab }
        OnAction = { param($item) if ($item.Data) { Invoke-GameCheckAction $item.Data.Do } }
        OnLink   = {
            $script:Sheet.GameCheck = $null
            $ui.SheetChips.Children.Clear()
            Show-GameCheckTab
            Start-Query 'GameCheck' { param($result) Complete-GameCheck $result } @{ Memory = $script:Queries.Memory }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Prüfe die Einstellungen …'
    Start-Query 'GameCheck' { param($result) Complete-GameCheck $result } @{ Memory = $script:Queries.Memory }
}

function Invoke-GameCheckAction([string]$Do) {
    $page = switch ($Do) {
        'display' { 'ms-settings:display-advanced' }
        'graphics' { 'ms-settings:display-advancedgraphics' }
        'coreiso' { 'windowsdefender://coreisolation' }
        'gamemode' { 'ms-settings:gaming-gamemode' }
        default { '' }
    }
    if ($page) { try { Start-Process $page } catch { Set-SheetStateText 'Die Einstellungen von Windows ließen sich nicht öffnen' }; return }
    switch ($Do) {
        'boost' { Open-BoostSheet }
        'bios' { Open-BiosSheet }
        'memory' { Open-MemorySheet }
    }
}

# Bewertung: Name, Ampel (good/warn/bad, leer = nicht prüfbar), Schild, Erklärung, Knopf
function Get-GameChecks($Data) {
    $checks = @()

    $displays = @($Data.Displays)
    if ($displays.Count) {
        $slow = @($displays | Where-Object { $_.Max -gt $_.Hz + 1 } | Sort-Object { -$_.Max })
        if ($slow.Count) {
            $d = $slow[0]
            $checks += @{ Name = 'Bildwiederholrate'; Tone = 'bad'; State = "$($d.Hz) Hz"; Glyph = 0xE7F4; Action = 'Anzeige öffnen'; Do = 'display'
                Text = "$($d.Name) läuft mit $($d.Hz) statt $($d.Max) Hz" + ': unter „Erweiterte Anzeige“ umstellen.' }
        }
        else {
            $d = @($displays | Where-Object { $_.Primary })[0]; if (-not $d) { $d = $displays[0] }
            $checks += @{ Name = 'Bildwiederholrate'; Tone = 'good'; State = "$($d.Hz) Hz"; Glyph = 0xE7F4
                Text = $(if ($displays.Count -gt 1) { 'Alle Bildschirme laufen mit der höchsten Rate, die sie bei dieser Auflösung können.' } else { "$($d.Name) läuft mit der höchsten Rate, die er bei dieser Auflösung kann." }) }
        }
    }
    else { $checks += @{ Name = 'Bildwiederholrate'; Tone = ''; State = 'nicht lesbar'; Glyph = 0xE7F4; Text = 'Windows nennt die Bildschirmmodi nicht.' } }

    if ($null -ne $Data.Bar) {
        if ($Data.Bar -gt 256) {
            $checks += @{ Name = 'Resizable BAR'; Tone = 'good'; State = 'an'; Glyph = 0xE950
                Text = "Die Grafikkarte erreicht ihren ganzen Speicher auf einmal ($([Math]::Round($Data.Bar / 1024)) GB). Das bringt in vielen neuen Spielen ein paar Prozent." }
        }
        else {
            $checks += @{ Name = 'Resizable BAR'; Tone = 'warn'; State = 'aus'; Glyph = 0xE950; Action = 'BIOS'; Do = 'bios'
                Text = 'Im BIOS „Above 4G Decoding“ und „Re-Size BAR“ einschalten: bringt in neuen Spielen ein paar Prozent.' }
        }
    }
    else { $checks += @{ Name = 'Resizable BAR'; Tone = ''; State = 'nicht prüfbar'; Glyph = 0xE950; Text = 'Lässt sich nur bei NVIDIA-Grafikkarten auslesen.' } }

    switch ($Data.Hags) {
        2 { $checks += @{ Name = 'GPU-Planung'; Tone = 'good'; State = 'an'; Glyph = 0xEC4A; Text = 'Die hardwarebeschleunigte GPU-Planung ist an. Sie ist Voraussetzung für Frame Generation (DLSS 3 und neuer).' } }
        1 { $checks += @{ Name = 'GPU-Planung'; Tone = 'warn'; State = 'aus'; Glyph = 0xEC4A; Action = 'Einstellungen'; Do = 'graphics'
                Text = 'Unter Grafikeinstellungen einschalten und neu starten. Nötig für Frame Generation (DLSS 3 und neuer).' } }
        default { $checks += @{ Name = 'GPU-Planung'; Tone = ''; State = 'Vorgabe'; Glyph = 0xEC4A; Action = 'Einstellungen'; Do = 'graphics'
                Text = 'Nicht festgelegt: Windows entscheidet selbst. Unter Grafikeinstellungen steht, ob sie an ist.' } }
    }

    if ($true -eq $Data.Hvci) {
        $checks += @{ Name = 'Kernisolierung'; Tone = 'warn'; State = 'an'; Glyph = 0xE72E; Action = 'Einstellungen'; Do = 'coreiso'
            Text = 'Schützt vor Schadtreibern, kostet in manchen Spielen 5–10 %. Abschalten ist eine Abwägung.' }
    }
    elseif ($false -eq $Data.Hvci) {
        $checks += @{ Name = 'Kernisolierung'; Tone = 'good'; State = 'aus'; Glyph = 0xE72E
            Text = 'Keine Bremse durch die Speicher-Integrität. Dafür fehlt dieser zusätzliche Schutz vor Schadtreibern.' }
    }
    else { $checks += @{ Name = 'Kernisolierung'; Tone = ''; State = 'nicht lesbar'; Glyph = 0xE72E; Text = 'Windows gibt den Zustand auf diesem PC nicht heraus.' } }

    $plan = "$($Data.Plan)"
    $guid = "$($Data.PlanGuid)"
    if ($guid -in '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61' -or $plan -match 'Höchstleistung|Ultimat|High performance|Ultimate|Hohe Leistung|Bitsum') {
        $checks += @{ Name = 'Energieplan'; Tone = 'good'; State = $plan; Glyph = 0xE945; Text = 'Der Prozessor darf jederzeit voll takten.' }
    }
    elseif ($guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a' -or $plan -match 'Energiespar|Power saver') {
        $checks += @{ Name = 'Energieplan'; Tone = 'bad'; State = $plan; Glyph = 0xE945; Action = 'Boost einrichten'; Do = 'boost'
            Text = 'Bremst Prozessor und Grafik. Der Boost stellt fürs Spielen auf Höchstleistung um.' }
    }
    elseif ($plan) {
        $checks += @{ Name = 'Energieplan'; Tone = $(if ($Data.Battery) { 'good' } else { 'warn' }); State = $plan; Glyph = 0xE945; Action = $(if (-not $Data.Battery) { 'Boost einrichten' }); Do = 'boost'
            Text = $(if ($Data.Battery) { 'Für ein Notebook die richtige Wahl; zum Spielen ans Netzteil.' } else { 'Für Spiele in Ordnung, taktet aber träger hoch. Der Boost stellt beim Spielen um.' }) }
    }
    else { $checks += @{ Name = 'Energieplan'; Tone = ''; State = 'nicht lesbar'; Glyph = 0xE945; Text = 'Windows nennt den aktiven Energieplan nicht.' } }

    $memory = if ($Data.Memory) { Get-MemoryProfile @($Data.Memory.Modules) } else { $null }
    if ($memory -and $memory.Tone -eq 'Good') { $checks += @{ Name = 'Arbeitsspeicher (XMP)'; Tone = 'good'; State = 'voller Takt'; Glyph = 0xE9D9; Text = $memory.Title } }
    elseif ($memory -and $memory.Tone -eq 'Warn') {
        $checks += @{ Name = 'Arbeitsspeicher (XMP)'; Tone = $(if ($memory.Rated - $memory.Now -ge 400) { 'bad' } else { 'warn' }); State = ('{0:N0} MHz' -f $memory.Now); Glyph = 0xE9D9; Action = 'Ansehen'; Do = 'memory'
            Text = ('Läuft mit {0:N0} statt {1:N0} MHz: im BIOS XMP, DOCP oder EXPO einschalten.' -f $memory.Now, $memory.Rated) }
    }
    else { $checks += @{ Name = 'Arbeitsspeicher (XMP)'; Tone = ''; State = $(if ($memory) { '{0:N0} MHz' -f $memory.Now } else { 'nicht lesbar' }); Glyph = 0xE9D9; Action = 'Ansehen'; Do = 'memory'; Text = 'Für welchen Takt die Riegel gebaut sind, verrät Windows bei diesem Modell nicht.' } }

    if ($Data.GameMode) { $checks += @{ Name = 'Spielmodus'; Tone = 'good'; State = 'an'; Glyph = 0xE7FC; Text = 'Windows gibt laufenden Spielen Vorrang und hält Updates zurück.' } }
    else { $checks += @{ Name = 'Spielmodus'; Tone = 'warn'; State = 'aus'; Glyph = 0xE7FC; Action = 'Einstellungen'; Do = 'gamemode'; Text = 'Einschalten: Windows gibt laufenden Spielen dann Vorrang.' } }
    $checks
}

# Wert von 0 bis 100: grün 2, gelb 1, rot 0; graue Punkte zählen nicht
function Get-GameScore($Checks) {
    $rated = @($Checks | Where-Object { $_.Tone })
    if ($rated.Count -eq 0) { return $null }
    $points = 0; foreach ($check in $rated) { $points += switch ($check.Tone) { 'good' { 2 } 'warn' { 1 } default { 0 } } }
    [int][Math]::Round($points * 100.0 / ($rated.Count * 2))
}

function Complete-GameCheck($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.GameCheck = $Result
    $checks = @(Get-GameChecks $Result)
    $score = Get-GameScore $checks
    $hints = @($checks | Where-Object { $_.Tone -and $_.Tone -ne 'good' }).Count
    if ($null -ne $score) { Set-CardState 'GameCheck' @{ Text = "$score"; Hints = $hints; Tone = $(if ($score -ge 85) { 'good' } elseif ($score -ge 60) { 'warn' } else { 'bad' }) } }
    Update-GameCheckPill
    Show-GameCheckTab
}

function Show-GameCheckTab {
    $data = $script:Sheet.GameCheck
    if (-not $data) { Start-SheetLoader 'Prüfe die Einstellungen …'; return }
    $checks = @(Get-GameChecks $data)
    $rows = @()
    foreach ($check in $checks) {
        $rows += New-SheetRow -Title $check.Name -Sub $check.Text -Glyph $check.Glyph -Tone $check.Tone -State $check.State -Action $check.Action -Data @{ Do = $check.Do }
    }
    $ui.SheetChips.Children.Clear()
    $score = Get-GameScore $checks
    if ($null -ne $score) { Add-ResultChip "$score von 100" $(if ($score -ge 85) { 'Good' } elseif ($score -ge 60) { 'Warn' } else { 'Bad' }) $ui.SheetChips }
    $good = @($checks | Where-Object { $_.Tone -eq 'good' }).Count
    $todo = @($checks | Where-Object { $_.Tone -in 'warn', 'bad' }).Count
    Add-ResultChip "$good grün" 'Good' $ui.SheetChips
    if ($todo) { Add-ResultChip $(if ($todo -eq 1) { '1 zu prüfen' } else { "$todo zu prüfen" }) 'Warn' $ui.SheetChips }
    Show-SheetList $rows
    Set-SheetStateText 'PulsRig ändert hier nichts: jede Zeile führt zur Stelle, an der man es einstellt'
}

# Knopf oben rechts auf der Boost-Seite: letzter Wert mit farbigem Punkt
function Update-GameCheckPill {
    if (-not $ui.GameCheckText) { return }
    $state = $script:CardState.GameCheck
    if ($state -and $state.Text) {
        $ui.GameCheckText.Text = T "Gaming-Check: $($state.Text) von 100"
        Set-Paint $ui.GameCheckDot 'Fill' $(switch ($state.Tone) { 'good' { 'Good' } 'warn' { 'Warn' } default { 'Bad' } })
    }
    else {
        $ui.GameCheckText.Text = T 'Gaming-Check starten'
        Set-Paint $ui.GameCheckDot 'Fill' 'Accent'
    }
    if (Get-Command Update-HomeGameCard -ErrorAction SilentlyContinue) { Update-HomeGameCard }
}

$ui.GameCheckPill.Add_MouseLeftButtonUp({ try { Open-GameCheckSheet } catch { Write-AppError $_ } })
Update-GameCheckPill
