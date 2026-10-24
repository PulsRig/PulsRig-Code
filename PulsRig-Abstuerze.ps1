# PulsRig - Abstürze und BIOS: zwei Karten der Hardware-Seite. Wird von PulsRig.ps1 nach PulsRig-Hardware.ps1 eingebunden.
#
# Abstürze: liest das Ereignisprotokoll der letzten 30 Tage und erklärt in einfachen Worten, was passiert ist:
#   Bluescreens (Ereignis 1001 der Fehlerberichterstattung, sonst der Fehlercode aus Kernel-Power 41),
#   plötzliches Ausschalten (Kernel-Power 41 ohne Fehlercode: Strom weg, Netzteil, Einfrieren, Ausschalter gehalten),
#   Aussetzer des Grafiktreibers (Display 4101) und Programmabstürze, die im Grafiktreiber passiert sind
#   (Application Error 1000 mit einem Modul von NVIDIA, AMD oder Intel), dazu Hardwarefehler (WHEA).
#   Zu jedem Befund gibt es den nächsten Schritt: Treiber suchen, ältere Fassung zurückholen, Speicher, Laufwerke
#   oder Stabilitätstest. Welcher Treiber einen Bluescreen ausgelöst hat, steht nur im Speicherabbild; das liest
#   PulsRig nicht aus, es schließt aus dem Fehlercode auf die Art der Ursache.
# BIOS: Version, Datum und Alter, Mainboard, Link zur Seite des Herstellers. PulsRig spielt nie selbst ein BIOS ein.
# Alles ohne Adminrechte lesbar.

# --- Abstürze -------------------------------------------------------------------

$script:Queries.Crashes = @'
param($a)
$since = (Get-Date).AddDays(-30)
$state = @{ Log = $true }
function Read-Events($Filter) {
    try { @(Get-WinEvent -FilterHashtable $Filter -ErrorAction Stop) }
    catch {
        # "nichts gefunden" meldet Windows als Fehler; alles andere heißt, dass das Protokoll nicht lesbar ist
        if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $state.Log = $false }
        @()
    }
}
function Get-Stamp($Time) { @{ Text = $Time.ToString('dd.MM. HH:mm'); Ticks = $Time.Ticks } }
function Get-Code($Value) {
    $text = "$Value"
    $number = [uint64]0
    if ($text -match '0x([0-9a-fA-F]+)') { $hex = $Matches[1]; $number = [Convert]::ToUInt64($hex.Substring([Math]::Max(0, $hex.Length - 8)), 16) }
    elseif ($text -match '^\d+$') { $number = [uint64]$text }
    [uint32]($number -band 0xFFFFFFFF)
}

$blue = @()
foreach ($e in (Read-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since })) {
    $code = Get-Code $e.Properties[0].Value
    $blue += @{ When = Get-Stamp $e.TimeCreated; Code = $code; Dump = "$($e.Properties[1].Value)" }
}
$off = @()
foreach ($e in (Read-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })) {
    $code = [uint32]0; $button = $false; $sleep = $false
    try { $code = Get-Code $e.Properties[0].Value } catch { }
    try { $sleep = [int64]"$($e.Properties[5].Value)" -ne 0 } catch { }
    try { $button = [int64]"$($e.Properties[6].Value)" -ne 0 } catch { }
    if ($code -ne 0) {
        # mit Fehlercode war es ein Bluescreen; meist steht er schon als Ereignis 1001 da
        $near = @($blue | Where-Object { [Math]::Abs($_.When.Ticks - $e.TimeCreated.Ticks) -lt [TimeSpan]::FromMinutes(15).Ticks })
        if ($near.Count -eq 0) { $blue += @{ When = Get-Stamp $e.TimeCreated; Code = $code; Dump = '' } }
        continue
    }
    $off += @{ When = Get-Stamp $e.TimeCreated; Button = $button; Sleep = $sleep }
}
$tdr = @()
foreach ($e in (Read-Events @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101; StartTime = $since })) {
    $driver = "$($e.Properties[0].Value)"
    if ($driver -notmatch '^\w+$' -and "$($e.Message)" -match '\b(nvlddmkm|amdkmdag|atikmdag|igdkmd\w*)\b') { $driver = $Matches[1] }
    $tdr += @{ When = Get-Stamp $e.TimeCreated; Driver = $driver }
}
# Programmabstürze, die im Grafiktreiber passiert sind: Hinweis auf den Treiber, nicht auf das Spiel
$apps = @()
foreach ($e in (Read-Events @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since })) {
    $module = "$($e.Properties[3].Value)"
    if ($module -match '^(nv\w*|ati\w*|amd\w*|ig\w*)\.dll$' -and $module -match 'umd|um\d|d3d|ogl|vlk|dxx|cuda|igc|nvapi|wgf') {
        $apps += @{ When = Get-Stamp $e.TimeCreated; App = "$($e.Properties[0].Value)"; Module = $module }
    }
}
$whea = @(Read-Events @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since; Level = 1, 2, 3 })

$gpu = $null
try {
    $card = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { "$($_.PNPDeviceID)" -like 'PCI*' } | Select-Object -First 1)[0]
    if ($card) { $gpu = @{ Name = "$($card.Name)"; Version = "$($card.DriverVersion)"; Date = $(if ($card.DriverDate) { $card.DriverDate.ToString('dd.MM.yyyy') } else { '' }) } }
}
catch { }

@{
    Blue  = @($blue | Sort-Object { $_.When.Ticks } -Descending)
    Off   = @($off | Sort-Object { $_.When.Ticks } -Descending)
    Tdr   = @($tdr | Sort-Object { $_.When.Ticks } -Descending)
    Apps  = @($apps | Sort-Object { $_.When.Ticks } -Descending)
    Whea  = $whea.Count
    LastWhea = $(if ($whea.Count) { $whea[0].TimeCreated.ToString('dd.MM. HH:mm') } else { '' })
    Gpu   = $gpu
    Log   = $state.Log
    Time  = (Get-Date).ToString('HH:mm')
}
'@

# Fehlercodes der Bluescreens: Name in Worten und Art der Ursache.
# Die Art bestimmt Erklärung und nächsten Schritt (siehe $script:CrashKinds).
$script:BugChecks = @{
    0x0A  = @('Ein Treiber griff auf falschen Speicher zu', 'driver')
    0xD1  = @('Ein Treiber griff auf falschen Speicher zu', 'driver')
    0x1E  = @('Ein Treiber hat einen Fehler nicht abgefangen', 'driver')
    0x7E  = @('Ein Treiber hat einen Fehler nicht abgefangen', 'driver')
    0x3B  = @('Fehler in einem Systemaufruf', 'driver')
    0xC2  = @('Ein Treiber hat Speicher falsch angefordert', 'driver')
    0x19  = @('Speicherverwaltung durcheinander', 'driver')
    0xFC  = @('Ein Treiber wollte geschützten Speicher ausführen', 'driver')
    0x139 = @('Sicherheitsprüfung im Windows-Kern', 'driver')
    0x133 = @('Ein Treiber hat das System zu lange blockiert', 'driver')
    0x9F  = @('Ein Treiber hing beim Standby oder Aufwachen', 'driver')
    0x1A  = @('Fehler in der Speicherverwaltung', 'memory')
    0x50  = @('Zugriff auf Speicher, den es nicht gibt', 'memory')
    0x116 = @('Grafiktreiber reagierte nicht mehr', 'graphics')
    0x117 = @('Grafiktreiber reagierte nicht mehr', 'graphics')
    0x119 = @('Fehler im Grafiktreiber', 'graphics')
    0x10E = @('Fehler im Grafikspeicher', 'graphics')
    0x124 = @('Die Hardware hat einen schweren Fehler gemeldet', 'hardware')
    0x101 = @('Ein Prozessorkern hat nicht mehr geantwortet', 'hardware')
    0x7A  = @('Daten vom Laufwerk ließen sich nicht lesen', 'disk')
    0x24  = @('Fehler im Dateisystem', 'disk')
    0x154 = @('Unerwarteter Fehler beim Laufwerkszugriff', 'disk')
    0xEF  = @('Ein wichtiger Windows-Prozess wurde beendet', 'disk')
}
$script:CrashKinds = @{
    driver   = @{ Text = 'Meist ein Treiber. Treiber aktualisieren hilft oft.'; State = 'Treiber'; Action = 'Treiber suchen'; Do = 'scan' }
    graphics = @{ Text = 'Grafiktreiber oder Grafikkarte. Eine neuere oder die vorige Treiberfassung hilft oft.'; State = 'Grafik'; Action = 'Treiber suchen'; Do = 'scan' }
    memory   = @{ Text = 'Oft der Arbeitsspeicher: ein zu scharfes XMP-Profil oder ein defekter Riegel.'; State = 'Speicher'; Action = 'Speicher prüfen'; Do = 'memory' }
    hardware = @{ Text = 'Hardware: Übertaktung, Spannung, Hitze oder Netzteil.'; State = 'Hardware'; Action = 'Stabilitätstest'; Do = 'stress' }
    disk     = @{ Text = 'Laufwerk, Kabel oder Anschluss, manchmal beschädigte Windows-Dateien.'; State = 'Laufwerk'; Action = 'Laufwerke prüfen'; Do = 'drives' }
    unknown  = @{ Text = 'Seltener Fehlercode, meist steckt ein Treiber dahinter.'; State = 'Treiber'; Action = 'Treiber suchen'; Do = 'scan' }
}

function Get-BugCheck([uint32]$Code) {
    # 0x1000007E und ähnliche sind dieselben Fehler wie 0x7E, nur anders gemeldet
    $base = if ($Code -band 0x10000000) { $Code -band 0x0FFFFFFF } else { $Code }
    $known = $script:BugChecks[[int]$base]
    $hex = '0x{0:X}' -f $base
    if ($known) { @{ Name = $known[0]; Kind = $known[1]; Hex = $hex } } else { @{ Name = 'Bluescreen'; Kind = 'unknown'; Hex = $hex } }
}

function Format-Times([int]$Count) { if ($Count -eq 1) { '1-mal' } else { "$Count-mal" } }

# gibt es Treibersicherungen, aus denen sich eine ältere Fassung zurückholen lässt?
function Test-DriverBackups {
    foreach ($folder in @((Get-TargetDir), $script:OutDir) | Select-Object -Unique) {
        try { if (@(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction Stop | Where-Object { $_.Name -like 'Backup_*' -or $_.Name -like 'Auto-Sicherung_*' }).Count) { return $true } } catch { }
    }
    $false
}

function Open-CrashSheet {
    $opened = Open-Sheet @{
        Title    = 'Abstürze'
        Sub      = 'Bluescreens, plötzliches Ausschalten und Aussetzer der letzten 30 Tage'
        Glyph    = 0xE7BA
        Link     = 'Neu einlesen'
        Show     = { param($tab) Show-CrashTab }
        OnAction = { param($item) if ($item.Data) { Invoke-CrashAction $item.Data.Do } }
        OnLink   = {
            $script:Sheet.Crashes = $null
            $ui.SheetChips.Children.Clear()
            Show-CrashTab
            Start-Query 'Crashes' { param($result) Complete-CrashQuery $result }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese das Ereignisprotokoll …'
    Start-Query 'Crashes' { param($result) Complete-CrashQuery $result }
}

function Invoke-CrashAction([string]$Do) {
    switch ($Do) {
        'scan' { Close-Sheet; Show-Page 'Home'; Invoke-Later 450 { Start-Scan } }
        'restore' { Close-Sheet; Invoke-Later 350 { Open-ToolDialog 'Restore' } }
        'memory' { Open-MemorySheet }
        'drives' { Open-DriveSheet }
        'stress' { Open-StressSheet }
        'rollback' { Invoke-ProbeRollback }
    }
}

# Zustand für die Karte und den Prüfbericht
function Get-CrashCardState($Data) {
    $blue = @($Data.Blue).Count; $off = @($Data.Off).Count; $tdr = @($Data.Tdr).Count + @($Data.Apps).Count
    $times = @(@($Data.Blue) + @($Data.Off) + @($Data.Tdr) + @($Data.Apps) | ForEach-Object { $_.When } | Sort-Object { $_.Ticks } -Descending)
    $detail = if ($times.Count) { "Zuletzt $($times[0].Text) Uhr" } else { 'Keine in 30 Tagen' }
    # vor wie vielen Tagen etwas war (0 = heute): für die 30 Kästchen auf der Karte
    $today = (Get-Date).Date
    $days = @($times | Where-Object { $_.Ticks } | ForEach-Object { [int][Math]::Floor(($today - ([datetime][long]$_.Ticks).Date).TotalDays) } | Where-Object { $_ -ge 0 -and $_ -lt 30 } | Sort-Object -Unique)
    if ($blue -gt 0) { @{ Text = $(if ($blue -eq 1) { '1 Bluescreen' } else { "$blue Bluescreens" }); Tone = 'bad'; Detail = $detail; Days = $days } }
    elseif ($off + $tdr -gt 0) { @{ Text = $(if ($off + $tdr -eq 1) { '1 Vorfall' } else { "$($off + $tdr) Vorfälle" }); Tone = 'warn'; Detail = $detail; Days = $days } }
    elseif ($false -eq $Data.Log) { $null }
    else { @{ Text = 'in Ordnung'; Tone = 'good'; Detail = $detail; Days = $days } }
}

function Complete-CrashQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Crashes = $Result
    # auch "Was ist los?" und "Was hat sich geändert?" kennen danach den neuesten Stand
    $script:LastCrashes = $Result
    Set-CardState 'Crashes' (Get-CrashCardState $Result)
    $ui.SheetChips.Children.Clear()
    $blue = @($Result.Blue).Count; $off = @($Result.Off).Count; $tdr = @($Result.Tdr).Count
    if ($blue) { Add-ResultChip $(if ($blue -eq 1) { '1 Bluescreen' } else { "$blue Bluescreens" }) 'Bad' $ui.SheetChips }
    if ($off) { Add-ResultChip "$(Format-Times $off) ausgegangen" 'Warn' $ui.SheetChips }
    if ($tdr) { Add-ResultChip "Grafik $(Format-Times $tdr) ausgesetzt" 'Warn' $ui.SheetChips }
    if (-not ($blue + $off + $tdr + @($Result.Apps).Count + [int]$Result.Whea)) { Add-ResultChip 'keine Abstürze' 'Good' $ui.SheetChips }
    Show-CrashTab
}

# Die Befunde aus den Abstürzen als Zeilen (Title, Sub, Glyph, Tone, State, Action, Do) - für das Fenster,
# den Prüfbericht und "Was ist los?". Ohne Befund leer.
function Get-CrashFindings($Data) {
    $items = @()
    if (-not $Data) { return $items }

    # Bluescreens, nach Fehlercode zusammengefasst
    foreach ($group in @(@($Data.Blue) | Where-Object { $_ } | Group-Object { (Get-BugCheck $_.Code).Hex })) {
        $check = Get-BugCheck $group.Group[0].Code
        $kind = $script:CrashKinds[$check.Kind]
        $items += @{ Title = "Bluescreen: $($check.Name)"; Glyph = 0xE783; Tone = 'bad'; State = $kind.State; Action = $kind.Action; Do = $kind.Do
            Sub = "$(Format-Times $group.Count), zuletzt $($group.Group[0].When.Text) Uhr · Code $($check.Hex) · $($kind.Text)"
            Short = "$(Format-Times $group.Count), zuletzt $($group.Group[0].When.Text) Uhr · $($kind.State)" }
    }

    # Grafiktreiber: Aussetzer und Programmabstürze im Treiber
    $tdr = @(@($Data.Tdr) | Where-Object { $_ }); $apps = @(@($Data.Apps) | Where-Object { $_ })
    if ($tdr.Count + $apps.Count -gt 0) {
        $parts = @()
        $last = @(@($tdr) + @($apps) | ForEach-Object { $_.When } | Sort-Object { $_.Ticks } -Descending)[0]
        $parts += "zuletzt $($last.Text) Uhr"
        if ($apps.Count) {
            $names = @($apps | Group-Object { $_.App } | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) $($_.Count)×" })
            $parts += "Programme im Grafiktreiber abgestürzt: $($names -join ', ')"
        }
        if ($Data.Gpu -and $Data.Gpu.Version) { $parts += "Treiber $($Data.Gpu.Version)$(if ($Data.Gpu.Date) { " vom $($Data.Gpu.Date)" })" }
        $title = if ($tdr.Count) { "Grafiktreiber ist $(Format-Times $tdr.Count) ausgesetzt" } else { "$(Format-Times $apps.Count) im Grafiktreiber abgestürzt" }
        $items += @{ Title = $title; Sub = ($parts -join ' · '); Short = "zuletzt $($last.Text) Uhr · Grafik"; Glyph = 0xE7F4; Tone = 'warn'; State = 'Grafik'; Action = 'Treiber suchen'; Do = 'scan'; Graphics = $true }
        if (Test-DriverBackups) {
            $items += @{ Title = 'Vorige Treiberfassung zurückholen'; Sub = 'Fingen die Aussetzer nach einem Treiber-Update an, hilft oft die vorige Fassung. PulsRig hat Sicherungen davon.'
                Glyph = 0xE777; Tone = 'accent'; Action = 'Zurückholen'; Do = 'restore'; Graphics = $true; Hint = $true }
        }
    }

    # plötzliches Ausschalten ohne Bluescreen
    $off = @(@($Data.Off) | Where-Object { $_ })
    if ($off.Count) {
        $button = @($off | Where-Object { $_.Button }).Count
        $sleep = @($off | Where-Object { $_.Sleep }).Count
        $sub = "$(Format-Times $off.Count), zuletzt $($off[0].When.Text) Uhr"
        if ($button) { $sub += " · $(Format-Times $button) am Ausschalter ausgemacht, der PC hing also vorher" }
        if ($sleep) { $sub += " · $(Format-Times $sleep) beim Standby" }
        $short = "$(Format-Times $off.Count), zuletzt $($off[0].When.Text) Uhr · Strom"
        $sub += ' · Ursachen: Strom weg, Netzteil, Hitze oder ein eingefrorener PC. Passiert es beim Spielen, zeigt der Stabilitätstest, ob die Hardware durchhält.'
        $items += @{ Title = 'PC ist plötzlich ausgegangen'; Sub = $sub; Short = $short; Glyph = 0xE7E8; Tone = 'warn'; State = 'Strom'; Action = 'Stabilitätstest'; Do = 'stress' }
    }

    if ($Data.Whea -gt 0) {
        $items += @{ Title = $(if ($Data.Whea -eq 1) { '1 Hardwarefehler gemeldet' } else { "$($Data.Whea) Hardwarefehler gemeldet" }); Whea = $true
            Sub = "Zuletzt $($Data.LastWhea) Uhr · Prozessor, Speicher oder Mainboard haben Windows einen Fehler gemeldet. Oft hilft es, Übertaktung und XMP zurückzunehmen."
            Glyph = 0xE9D9; Tone = 'warn'; State = 'Hardware'; Action = 'Stabilitätstest'; Do = 'stress' }
    }
    $items
}

function New-CrashRow($Item) {
    New-SheetRow -Title $Item.Title -Sub $Item.Sub -Glyph $Item.Glyph -Tone $Item.Tone -State $Item.State -Action $Item.Action -Data @{ Do = $Item.Do }
}

# Die Zeile des Prüfberichts. Hardwarefehler (WHEA) hat der Bericht schon als eigene Zeile, sie zählen hier nicht mit.
function Get-CrashReportCheck($Data) {
    $base = @{ Name = 'Abstürze in 30 Tagen'; Go = 'crashes'; Glyph = 0xE7BA }
    if (-not $Data) { return $base + @{ Text = 'Das Ereignisprotokoll ließ sich nicht lesen.'; Kind = 'open' } }
    $found = @(Get-CrashFindings $Data | Where-Object { -not $_.Whea -and -not $_.Hint })
    if ($found.Count -eq 0) {
        if ($false -eq $Data.Log) { return $base + @{ Text = 'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus.'; Kind = 'open' } }
        # Go nicht per + überschreiben: doppelte Schlüssel wirft Hashtable-Addition als Fehler (Prüfbericht brach ab)
        $base.Go = $null
        return $base + @{ Text = 'Kein Bluescreen, kein plötzliches Ausschalten und keine Aussetzer des Grafiktreibers.'; Kind = 'good' }
    }
    $kind = if (@($found | Where-Object { $_.Tone -eq 'bad' }).Count) { 'bad' } else { 'warn' }
    # mit " · " verbunden: so übersetzt T jedes Stück einzeln wie im Fenster
    $text = (@($found | ForEach-Object { "$($_.Title) · $($_.Sub)" }) -join ' · ')
    # kurz für das Fenster: wie oft was, dazu der letzte Vorfall (dieselben Wörter wie die Schilder im Abstürze-Fenster)
    $blue = @(@($Data.Blue) | Where-Object { $_ }).Count; $tdr = @(@($Data.Tdr) | Where-Object { $_ }).Count
    $apps = @(@($Data.Apps) | Where-Object { $_ }).Count; $off = @(@($Data.Off) | Where-Object { $_ }).Count
    $parts = @()
    if ($blue) { $parts += $(if ($blue -eq 1) { '1 Bluescreen' } else { "$blue Bluescreens" }) }
    if ($tdr) { $parts += "Grafik $(Format-Times $tdr) ausgesetzt" } elseif ($apps) { $parts += "$(Format-Times $apps) im Grafiktreiber abgestürzt" }
    if ($off) { $parts += "$(Format-Times $off) ausgegangen" }
    $last = @(@($Data.Blue) + @($Data.Off) + @($Data.Tdr) + @($Data.Apps) | Where-Object { $_ } | ForEach-Object { $_.When } | Sort-Object { $_.Ticks } -Descending)[0]
    if ($last) { $parts += "zuletzt $($last.Text) Uhr" }
    $short = $parts -join ' · '
    $base + @{ Text = $text; Short = $short; Kind = $kind }
}

function Show-CrashTab {
    $data = $script:Sheet.Crashes
    if (-not $data) { Start-SheetLoader 'Lese das Ereignisprotokoll …'; return }
    $rows = @(Get-CrashFindings $data | ForEach-Object { New-CrashRow $_ })

    if ($rows.Count -eq 0) {
        if ($false -eq $data.Log) {
            $rows += New-SheetRow -Title 'Das Ereignisprotokoll ist nicht lesbar' -Sub 'Windows gibt es auf diesem PC nicht heraus. PulsRig einmal als Admin starten und neu einlesen.' -Glyph 0xE946
        }
        else {
            $rows += New-SheetRow -Title 'Keine Abstürze in 30 Tagen' -Sub 'Kein Bluescreen, kein plötzliches Ausschalten, keine Aussetzer des Grafiktreibers und keine Hardwarefehler.' `
                -Glyph 0xE73E -Tone 'good' -State 'in Ordnung'
        }
    }
    # laufende Probezeiten neuer Treiber (PulsRig-Probezeit.ps1) stehen darunter
    $rows += @(Get-ProbeRows)
    Show-SheetList $rows
    Set-SheetStateText "Ereignisprotokoll von Windows · letzte 30 Tage · Stand: $($data.Time) Uhr"
}

# --- BIOS -----------------------------------------------------------------------

$script:Queries.Bios = @'
param($a)
$bios = Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object -First 1
$board = $null
try { $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1 } catch { }
$system = $null
try { $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }
@{
    Version = "$($bios.SMBIOSBIOSVersion)".Trim()
    Maker   = "$($bios.Manufacturer)".Trim()
    Date    = $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { '' })
    Board   = $(if ($board) { "$($board.Manufacturer)".Trim() + '|' + "$($board.Product)".Trim() } else { '|' })
    System  = $(if ($system) { "$($system.Manufacturer)".Trim() + '|' + "$($system.Model)".Trim() } else { '|' })
}
'@

# Alter in Worten: "7 Monate", "2 Jahre und 3 Monate"
function Format-Age([datetime]$Date) {
    $months = (Get-Date).Year * 12 + (Get-Date).Month - ($Date.Year * 12 + $Date.Month)
    if ($months -lt 1) { return 'weniger als einen Monat' }
    if ($months -lt 12) { return $(if ($months -eq 1) { '1 Monat' } else { "$months Monate" }) }
    $years = [Math]::Floor($months / 12); $rest = $months % 12
    $text = if ($years -eq 1) { '1 Jahr' } else { "$years Jahre" }
    if ($rest) { $text += $(if ($rest -eq 1) { ' und 1 Monat' } else { " und $rest Monate" }) }
    $text
}

# Hersteller und Modell, nach denen man sucht: bei Komplett-PCs und Notebooks das Gerät, sonst das Mainboard
function Get-BiosTarget($Data) {
    $boardMaker, $boardModel = "$($Data.Board)" -split '\|', 2
    $sysMaker, $sysModel = "$($Data.System)" -split '\|', 2
    $generic = 'To Be Filled|System Product|Default string|O\.E\.M\.|^$'
    if ($sysModel -and $sysModel -notmatch $generic -and $sysMaker -notmatch $generic -and $sysModel -ne $boardModel) {
        @{ Maker = $sysMaker; Model = $sysModel; What = 'Gerät' }
    }
    else { @{ Maker = $boardMaker; Model = $boardModel; What = 'Mainboard' } }
}

function Open-BiosSheet {
    $opened = Open-Sheet @{
        Title    = 'BIOS'
        Sub      = 'Version, Alter und die Seite des Herstellers'
        Glyph    = 0xE713
        Show     = { param($tab) Show-BiosTab }
        OnAction = {
            param($item)
            if ($item.Data -and $item.Data.Url) { try { Start-Process $item.Data.Url } catch { Set-SheetStateText 'Der Browser ließ sich nicht öffnen' } }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese das BIOS …'
    Start-Query 'Bios' { param($result) Complete-BiosQuery $result }
}

function Complete-BiosQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Bios = $Result
    $date = $null
    try { $date = [datetime]::ParseExact("$($Result.Date)", 'yyyy-MM-dd', $null) } catch { }
    $Result.Released = $date
    if ($date) {
        $old = ((Get-Date) - $date).TotalDays -gt 3 * 365
        $months = (Get-Date).Year * 12 + (Get-Date).Month - ($date.Year * 12 + $date.Month)
        $short = if ($months -lt 12) { $(if ($months -le 1) { 'neu' } else { "$months Monate alt" }) } else { $(if ($months -lt 24) { '1 Jahr alt' } else { "$([Math]::Floor($months / 12)) Jahre alt" }) }
        Set-CardState 'Bios' @{ Text = $short; Tone = $(if ($old) { 'warn' } else { 'good' }); Detail = "$($Result.Version) vom $($date.ToString('dd.MM.yyyy'))" }
    }
    $ui.SheetChips.Children.Clear()
    if ($date) { Add-ResultChip "$(Format-Age $date) alt" $(if (((Get-Date) - $date).TotalDays -gt 3 * 365) { 'Warn' } else { 'Good' }) $ui.SheetChips }
    Show-BiosTab
}

function Show-BiosTab {
    $data = $script:Sheet.Bios
    if (-not $data) { Start-SheetLoader 'Lese das BIOS …'; return }
    $target = Get-BiosTarget $data
    $boardMaker, $boardModel = "$($data.Board)" -split '\|', 2
    $rows = @()
    $rows += New-SheetRow -Kind 'pair' -Title 'Version' -Value "$($data.Version)"
    if ($data.Released) {
        $rows += New-SheetRow -Kind 'pair' -Title 'Datum' -Value $data.Released.ToString('dd.MM.yyyy')
        $rows += New-SheetRow -Kind 'pair' -Title 'Alter' -Value (Format-Age $data.Released)
    }
    if ($data.Maker) { $rows += New-SheetRow -Kind 'pair' -Title 'BIOS-Hersteller' -Value "$($data.Maker)" }
    if ($boardModel) { $rows += New-SheetRow -Kind 'pair' -Title 'Mainboard' -Value "$boardMaker $boardModel".Trim() }
    if ($target.What -eq 'Gerät') { $rows += New-SheetRow -Kind 'pair' -Title 'Gerät' -Value "$($target.Maker) $($target.Model)".Trim() }
    if ($target.Model) {
        $query = [Uri]::EscapeDataString("$($target.Maker) $($target.Model) BIOS download")
        $rows += New-SheetRow -Title 'Nach neuerem BIOS sehen' -Glyph 0xE774 -Tone 'accent' -Action 'Seite öffnen' -Data @{ Url = "https://www.google.com/search?q=$query" } `
            -Sub "Sucht im Browser nach der Download-Seite für $($target.Maker) $($target.Model). Dort steht die neueste Version mit Datum."
    }
    $rows += New-SheetRow -Title 'Einspielen nur mit dem Werkzeug des Herstellers' -Glyph 0xE7BA -Tone 'warn' `
        -Sub 'PulsRig spielt nie selbst ein BIOS ein. Ein Update lohnt sich bei Abstürzen, für einen neuen Prozessor oder bei Sicherheitslücken. Währenddessen darf der Strom nicht ausfallen.'
    Show-SheetList $rows
    Set-SheetStateText $(if ($data.Released -and ((Get-Date) - $data.Released).TotalDays -gt 3 * 365) { 'Älter als drei Jahre: ein Blick auf die Seite des Herstellers lohnt sich' } else { 'Ein BIOS muss nicht immer das neueste sein, solange alles stabil läuft' })
}
