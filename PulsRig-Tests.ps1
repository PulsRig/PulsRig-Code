# PulsRig - Tests für die reinen Rechenfunktionen. Sie decken Fälle ab, die der eigene PC nie zeigt
# (andere Mainboards, falsch gesteckte Riegel, fremde Typenbezeichnungen).
#
# Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File PulsRig-Tests.ps1
# Die Funktionen werden einzeln aus den Programmdateien gelesen - das Programm selbst startet dabei nicht.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$script:Passed = 0
$script:Failures = @()

# Holt einzelne Funktionen aus einer Skriptdatei, ohne die Datei auszuführen
function Import-Functions([string]$File, [string[]]$Names) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $File), [ref]$null, [ref]$errors)
    foreach ($name in $Names) {
        $found = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        if (-not $found) { throw "Funktion $name fehlt in $File" }
        . ([scriptblock]::Create(($found.Extent.Text -replace ('^function\s+' + [regex]::Escape($name)), "function script:$name")))
    }
}

function Test-Equal([string]$Name, $Actual, $Expected) {
    if ("$Actual" -ceq "$Expected") { $script:Passed++ }
    else { $script:Failures += "$Name`n      erwartet: $Expected`n      erhalten: $Actual" }
}

Import-Functions 'Treiber-Scan.ps1' 'ConvertTo-NvidiaVersion', 'Get-CatalogQuery', 'Select-CatalogCandidate', 'Test-ChipsetDevice', 'Get-BoardDriverSearch', 'Select-MissingDriverRow', 'Format-UpdateTitle', 'Find-DeviceName', 'Get-RadeonPage'
Import-Functions 'PulsRig-Hardware.ps1' 'Get-MemoryRated', 'Get-MemoryProfile', 'Get-MemoryChannelKey', 'Get-MemoryChannels', 'Get-MemoryPlacement', 'Get-MemoryLayout'

# --- NVIDIA-Version ---
Test-Equal 'NVIDIA: 32.0.16.1742 ist 617.42' (ConvertTo-NvidiaVersion '32.0.16.1742') '617.42'
Test-Equal 'NVIDIA: 31.0.15.5222 ist 552.22' (ConvertTo-NvidiaVersion '31.0.15.5222') '552.22'
$radeonBase = 'https://www.amd.com/de/support/downloads/drivers.html/graphics/radeon-rx/'
Test-Equal 'Radeon: RX 7800 XT' (Get-RadeonPage 'AMD Radeon RX 7800 XT') "${radeonBase}radeon-rx-7000-series/amd-radeon-rx-7800-xt.html"
Test-Equal 'Radeon: RX 7900 XTX mit (TM)' (Get-RadeonPage 'AMD Radeon(TM) RX 7900 XTX') "${radeonBase}radeon-rx-7000-series/amd-radeon-rx-7900-xtx.html"
Test-Equal 'Radeon: RX 6600' (Get-RadeonPage 'AMD Radeon RX 6600') "${radeonBase}radeon-rx-6000-series/amd-radeon-rx-6600.html"
Test-Equal 'Radeon: Vega 56' (Get-RadeonPage 'Radeon RX Vega 56') "${radeonBase}radeon-rx-vega-series/radeon-rx-vega-56.html"
Test-Equal 'Radeon: RX 580 ohne Seite' "$(Get-RadeonPage 'Radeon RX 580 Series')" ''
Test-Equal 'Radeon: Prozessorgrafik ohne Seite' "$(Get-RadeonPage 'AMD Radeon(TM) Graphics')" ''
Test-Equal 'NVIDIA: zu kurze Angabe gibt nichts' (ConvertTo-NvidiaVersion '1.2') ''

# --- Suchbegriff für den Katalog ---
Test-Equal 'Katalog: PCI ohne SUBSYS und REV' (Get-CatalogQuery 'PCI\VEN_1022&DEV_790B&SUBSYS_FFFF1849&REV_59') 'VEN_1022&DEV_790B'
Test-Equal 'Katalog: USB ohne MI' (Get-CatalogQuery 'USB\VID_046D&PID_C52B&MI_00') 'VID_046D&PID_C52B'
Test-Equal 'Katalog: ACPI in Kurzform' (Get-CatalogQuery 'ACPI\VEN_AMDI&DEV_0030') 'AMDI0030'
Test-Equal 'Katalog: ROOT wird nicht gesucht' (Get-CatalogQuery 'ROOT\SYSTEM') ''
Test-Equal 'Katalog: ohne Bus kein Begriff' (Get-CatalogQuery 'irgendwas') ''
Test-Equal 'Katalog: zu kurzer Begriff entfällt' (Get-CatalogQuery 'HID\ABC') ''

# --- Auswahl des Katalogeintrags ---
$driver = [pscustomobject]@{ DriverVersion = '2.0.0.26'; DriverProviderName = 'Advanced Micro Devices, Inc'; ActualDate = [datetime]'2025-12-04' }
function New-Row($Title, $Version, $Date, $Products = 'Windows 11 Client, version 24H2 and later') {
    [pscustomobject]@{ Title = $Title; Products = $Products; Version = [version]$Version; Date = [datetime]$Date; Size = '17 KB'; Bytes = 17000 }
}
$rows = @(
    (New-Row 'Advanced Micro Devices, Inc System Driver Update (2.0.0.29)' '2.0.0.29' '2026-07-07'),
    (New-Row 'Advanced Micro Devices, Inc System Driver Update (2.0.0.27)' '2.0.0.27' '2026-01-10'),
    (New-Row 'Advanced Micro Devices, Inc System Driver Update (3.0.0.1)' '3.0.0.1' '2026-08-01'),
    (New-Row 'Realtek System Driver Update (2.0.0.40)' '2.0.0.40' '2026-08-01'),
    (New-Row 'Advanced Micro Devices, Inc System Driver Update (2.0.0.35)' '2.0.0.35' '2026-08-01' 'Windows 10, version 1903 and later')
)
Test-Equal 'Kandidat: neueste Version derselben Linie' (Select-CatalogCandidate $driver $rows 'Windows 11').Version '2.0.0.29'
Test-Equal 'Kandidat: andere Hauptversion zählt nicht' ([bool](Select-CatalogCandidate $driver @($rows[2]) 'Windows 11')) $false
Test-Equal 'Kandidat: anderer Hersteller zählt nicht' ([bool](Select-CatalogCandidate $driver @($rows[3]) 'Windows 11')) $false
Test-Equal 'Kandidat: anderes Windows zählt nicht' ([bool](Select-CatalogCandidate $driver @($rows[4]) 'Windows 11')) $false
$current = [pscustomobject]@{ DriverVersion = '2.0.0.29'; DriverProviderName = 'Advanced Micro Devices, Inc'; ActualDate = [datetime]'2026-07-07' }
Test-Equal 'Kandidat: gleiche Version ist kein Fund' ([bool](Select-CatalogCandidate $current $rows 'Windows 11')) $false
$odd = [pscustomobject]@{ DriverVersion = 'unbekannt'; DriverProviderName = 'Advanced Micro Devices, Inc'; ActualDate = $null }
Test-Equal 'Kandidat: unlesbare Version gibt nichts' ([bool](Select-CatalogCandidate $odd $rows 'Windows 11')) $false

# --- Takt, für den ein Riegel gebaut ist ---
Test-Equal 'Takt: G.Skill F4-3000C16' (Get-MemoryRated @{ Rated = 0; Part = 'F4-3000C16-16GISB'; Speed = 2800 }).Speed 3000
Test-Equal 'Takt: Corsair CMK16GX4M2B3200C16' (Get-MemoryRated @{ Rated = 0; Part = 'CMK16GX4M2B3200C16'; Speed = 2133 }).Speed 3200
Test-Equal 'Takt: Kingston KF432C16' (Get-MemoryRated @{ Rated = 0; Part = 'KF432C16BB/8'; Speed = 2400 }).Speed 3200
Test-Equal 'Takt: Crucial BL16G36C16' (Get-MemoryRated @{ Rated = 0; Part = 'BL16G36C16U4B.M16FE1'; Speed = 2666 }).Speed 3600
Test-Equal 'Takt: unbekannte Bezeichnung bleibt unbekannt' (Get-MemoryRated @{ Rated = 0; Part = 'M378A1K43CB2-CTD'; Speed = 2666 }).Known $false
Test-Equal 'Takt: Angabe von Windows zählt, wenn sie höher ist' (Get-MemoryRated @{ Rated = 3600; Part = ''; Speed = 2133 }).Speed 3600

# --- Urteil über den Takt ---
Test-Equal 'Profil: 2800 statt 3000 ist auffällig' (Get-MemoryProfile @(@{ Rated = 0; Part = 'F4-3000C16-16GISB'; Speed = 2800 })).Tone 'Warn'
Test-Equal 'Profil: 3000 von 3000 ist voller Takt' (Get-MemoryProfile @(@{ Rated = 0; Part = 'F4-3000C16-16GISB'; Speed = 3000 })).Badge 'voller Takt'
Test-Equal 'Profil: unbekannter Riegel ohne Urteil' (Get-MemoryProfile @(@{ Rated = 0; Part = 'M378A1K43CB2-CTD'; Speed = 2666 })).Tone 'TextDim'
Test-Equal 'Profil: ohne Taktangabe nichts' @(Get-MemoryProfile @(@{ Rated = 0; Part = ''; Speed = 0 }) | Where-Object { $_ }).Count 0

# --- Kanäle ---
$dual = @(@{ Bank = 'P0 CHANNEL A'; Slot = 'DIMM 1' }, @{ Bank = 'P0 CHANNEL B'; Slot = 'DIMM 1' })
$single = @(@{ Bank = 'P0 CHANNEL A'; Slot = 'DIMM 0' }, @{ Bank = 'P0 CHANNEL A'; Slot = 'DIMM 1' })
Test-Equal 'Kanäle: A und B ist Dual-Channel' (Get-MemoryChannels $dual 4).Name 'Dual-Channel'
Test-Equal 'Kanäle: zweimal A ist Single-Channel' (Get-MemoryChannels $single 4).Name 'Single-Channel'
Test-Equal 'Kanäle: zweimal A bekommt einen Hinweis' ([bool](Get-MemoryChannels $single 4).Hint) $true
Test-Equal 'Kanäle: Schreibweise DIMM_A2 / DIMM_B2' (Get-MemoryChannels @(@{ Bank = 'BANK 1'; Slot = 'DIMM_A2' }, @{ Bank = 'BANK 3'; Slot = 'DIMM_B2' }) 4).Name 'Dual-Channel'
Test-Equal 'Kanäle: Schreibweise ChannelA-DIMM0' (Get-MemoryChannels @(@{ Bank = 'BANK 0'; Slot = 'ChannelA-DIMM0' }) 2).Name 'Single-Channel'
Test-Equal 'Kanäle: Intel ab 12. Generation, zwei Controller sind Dual-Channel' (Get-MemoryChannels @(@{ Bank = 'BANK 0'; Slot = 'Controller0-ChannelA-DIMM1' }, @{ Bank = 'BANK 1'; Slot = 'Controller1-ChannelA-DIMM1' }) 4).Name 'Dual-Channel'
Test-Equal 'Kanäle: Intel ab 12. Generation, ein Controller ist Single-Channel' (Get-MemoryChannels @(@{ Bank = 'BANK 0'; Slot = 'Controller0-ChannelA-DIMM0' }, @{ Bank = 'BANK 0'; Slot = 'Controller0-ChannelA-DIMM1' }) 4).Name 'Single-Channel'
Test-Equal 'Kanäle: unbekannte Namen ohne Urteil' @(Get-MemoryChannels @(@{ Bank = 'BANK 0'; Slot = 'Slot 1' }) 2 | Where-Object { $_ }).Count 0

# --- Steckplätze: vier Plätze, zwei Kanäle; Module = -1 heißt leer ---
function New-Layout([int[]]$Filled) {
    $names = @(@('P0 CHANNEL A', 'DIMM 0'), @('P0 CHANNEL A', 'DIMM 1'), @('P0 CHANNEL B', 'DIMM 0'), @('P0 CHANNEL B', 'DIMM 1'))
    for ($i = 0; $i -lt 4; $i++) { @{ Bank = $names[$i][0]; Slot = $names[$i][1]; Module = $(if ($Filled -contains $i) { $i } else { -1 }) } }
}
Test-Equal 'Stecken: A2 und B2 ist richtig' (Get-MemoryPlacement @(New-Layout 1, 3)).State 'good'
Test-Equal 'Stecken: alle vier ist richtig' (Get-MemoryPlacement @(New-Layout 0, 1, 2, 3)).State 'good'
$wrong = Get-MemoryPlacement @(New-Layout 0, 2)
Test-Equal 'Stecken: A1 und B1 ist falsch' $wrong.State 'bad'
Test-Equal 'Stecken: A1 und B1 gehören nach A2 und B2' ($wrong.Better -join ',') '1,3'
$crowded = Get-MemoryPlacement @(New-Layout 0, 1)
Test-Equal 'Stecken: beide in Kanal A ist falsch' $crowded.State 'bad'
Test-Equal 'Stecken: einer aus Kanal A gehört nach B2' ($crowded.Better -join ',') '3'
Test-Equal 'Stecken: ein Riegel in A2 ist richtig' (Get-MemoryPlacement @(New-Layout 1)).State 'good'
Test-Equal 'Stecken: ein Riegel in A1 ist falsch' (Get-MemoryPlacement @(New-Layout 0)).State 'bad'
Test-Equal 'Stecken: unbekannte Namen ohne Urteil' (Get-MemoryPlacement @(@{ Bank = ''; Slot = 'Slot 1'; Module = 0 }, @{ Bank = ''; Slot = 'Slot 2'; Module = -1 })).State ''
Test-Equal 'Stecken: nur zwei Steckplätze ohne Urteil' (Get-MemoryPlacement @(@{ Bank = 'CHANNEL A'; Slot = 'DIMM 0'; Module = 0 }, @{ Bank = 'CHANNEL B'; Slot = 'DIMM 0'; Module = 1 })).State ''

# --- Reihenfolge der Steckplätze, wenn das BIOS keine liefert ---
$layout = @(Get-MemoryLayout @{ Modules = @(@{ Slot = 'DIMM 1'; Bank = 'A' }, @{ Slot = 'DIMM 1'; Bank = 'B' }); Layout = @(); Slots = 4 })
Test-Equal 'Reihenfolge: zwei Riegel, vier Plätze' $layout.Count 4
Test-Equal 'Reihenfolge: freie Plätze stehen hinten' $layout[3].Module -1

# --- Fehlender Chipsatz-Treiber ---
Test-Equal 'Chipsatz: SM-Bus-Controller von Intel ohne Treiber' (Test-ChipsetDevice 'SM-Bus-Controller' 28 'PCI\VEN_8086&DEV_7A23&SUBSYS_86941043&REV_11\3&11583659&0&FC') $true
Test-Equal 'Chipsatz: PCI-Gerät von Intel ohne Treiber' (Test-ChipsetDevice 'PCI-Gerät' 28 'PCI\VEN_8086&DEV_7A27&SUBSYS_86941043') $true
Test-Equal 'Chipsatz: englischer Name bei AMD' (Test-ChipsetDevice 'SM Bus Controller' 28 'PCI\VEN_1022&DEV_790B') $true
Test-Equal 'Chipsatz: anderer Fehlercode zählt nicht' (Test-ChipsetDevice 'SM-Bus-Controller' 43 'PCI\VEN_8086&DEV_7A23') $false
Test-Equal 'Chipsatz: Netzwerkcontroller zählt nicht' (Test-ChipsetDevice 'Netzwerkcontroller' 28 'PCI\VEN_8086&DEV_7AF0') $false
Test-Equal 'Chipsatz: PCI-Gerät eines anderen Herstellers zählt nicht' (Test-ChipsetDevice 'PCI-Gerät' 28 'PCI\VEN_10EC&DEV_8168') $false
Test-Equal 'Chipsatz: USB-Gerät zählt nicht' (Test-ChipsetDevice 'Unbekanntes Gerät' 28 'USB\VID_1532&PID_02A3') $false
# --- Hinweis auf eine neuere Fassung ---
Import-Functions 'PulsRig.ps1' 'ConvertTo-BuildTime', 'Test-NewerBuild', 'Read-VersionNote', 'Format-ScanHint', 'Format-ShownPath'
Test-Equal 'Fassung: späteres Baudatum ist neuer' (Test-NewerBuild '13.10.2026 18:45 · Stand abc1234' '14.10.2026 09:00 · Stand def5678') $true
Test-Equal 'Fassung: gleiches Baudatum ist nicht neuer' (Test-NewerBuild '13.10.2026 18:45 · Stand abc1234' '13.10.2026 18:45') $false
Test-Equal 'Fassung: älteres Baudatum ist nicht neuer' (Test-NewerBuild '13.10.2026 18:45' '01.10.2026 08:00') $false
Test-Equal 'Fassung: Werkstatt vergleicht nicht' (Test-NewerBuild 'Werkstatt (nicht aus einem Paket)' '14.10.2026 09:00') $false
Test-Equal 'Fassung: Antwort wird gelesen' (Read-VersionNote '{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00 · Stand def5678" }').Version '0.6 Beta'
$script:UpdateRepo = 'PulsRig/PulsRig'
$goodSetup = '"Setup": "https://github.com/PulsRig/PulsRig/releases/download/v0.6-beta-20261014-0900/PulsRig-Setup-0.6-Beta.exe", "Bytes": 2264519, "Sha256": "4457ed2b0693d3105e7d284bbb302abaa71f834c1b53d0245ee02ce5340902ce"'
Test-Equal 'Fassung: Setup-Datei aus dem eigenen Projekt wird angenommen' (Read-VersionNote ('{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00", ' + $goodSetup + ' }')).Bytes 2264519
Test-Equal 'Fassung: Prüfsumme in Großbuchstaben' (Read-VersionNote ('{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00", ' + $goodSetup + ' }')).Sha256 '4457ED2B0693D3105E7D284BBB302ABAA71F834C1B53D0245EE02CE5340902CE'
Test-Equal 'Fassung: Setup-Datei von fremder Adresse zählt nicht' (Read-VersionNote ('{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00", ' + $goodSetup.Replace('PulsRig/PulsRig/releases', 'Fremd/PulsRig/releases') + ' }')).Setup ''
Test-Equal 'Fassung: Setup-Datei ohne https zählt nicht' (Read-VersionNote ('{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00", ' + $goodSetup.Replace('https://', 'http://') + ' }')).Setup ''
Test-Equal 'Fassung: Setup-Datei ohne Prüfsumme zählt nicht' (Read-VersionNote ('{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00", ' + $goodSetup.Replace('4457ed2b', 'zzzzzzzz') + ' }')).Setup ''
Test-Equal 'Fassung: Angaben ohne Setup-Datei bleiben gültig' (Read-VersionNote '{ "Version": "0.6 Beta", "Gebaut": "14.10.2026 09:00" }').Setup ''
Test-Equal 'Fassung: Antwort ohne Baudatum zählt nicht' ([bool](Read-VersionNote '{ "Version": "0.6" }')) $false
Test-Equal 'Fassung: kein JSON zählt nicht' ([bool](Read-VersionNote '<html>404</html>')) $false
Test-Equal 'Fassung: seltsame Zeichen in der Version zählen nicht' ([bool](Read-VersionNote '{ "Version": "<b>x</b>", "Gebaut": "14.10.2026 09:00" }')) $false

# --- Pfade ohne Kontonamen ---
Test-Equal 'Pfad: Benutzerordner ersetzt' (Format-ShownPath 'C:\Users\maxmuster\AppData\Local\PulsRig' 'C:\Users\maxmuster') 'Benutzerordner\AppData\Local\PulsRig'
Test-Equal 'Pfad: Groß und klein egal, mitten im Satz' (Format-ShownPath 'Gespeichert: c:\users\MAXMUSTER\Desktop\x.zip fertig' 'C:\Users\maxmuster') 'Gespeichert: Benutzerordner\Desktop\x.zip fertig'
Test-Equal 'Pfad: anderer Ordner bleibt' (Format-ShownPath 'C:\Program Files\PulsRig' 'C:\Users\maxmuster') 'C:\Program Files\PulsRig'
Test-Equal 'Pfad: ähnlicher Name eines anderen Kontos bleibt' (Format-ShownPath 'C:\Users\maxmuster2\Desktop' 'C:\Users\maxmuster') 'C:\Users\maxmuster2\Desktop'

# --- Unterzeile der Startseite ---
Test-Equal 'Unterzeile: alle Quellen' (Format-ScanHint $true $true $true) 'Ein Klick auf SCAN prüft Windows Update, NVIDIA, AMD und den Microsoft-Katalog.'
Test-Equal 'Unterzeile: Intel mit NVIDIA-Karte' (Format-ScanHint $true $false $true) 'Ein Klick auf SCAN prüft Windows Update, NVIDIA und den Microsoft-Katalog.'
Test-Equal 'Unterzeile: ohne NVIDIA und AMD' (Format-ScanHint $false $false $true) 'Ein Klick auf SCAN prüft Windows Update und den Microsoft-Katalog.'
Test-Equal 'Unterzeile: nur Windows Update' (Format-ScanHint $false $false $false) 'Ein Klick auf SCAN prüft Windows Update.'

# --- Titel und Gerätenamen der Treiber von Windows Update ---
Test-Equal 'Titel: Monitor' (Format-UpdateTitle 'BenQ - LCD - BenQ GW2760HS') 'BenQ – Monitor – BenQ GW2760HS'
Test-Equal 'Titel: Datum fällt weg' (Format-UpdateTitle 'SteelSeries - System - 5/14/2019 12:00:00 AM - 1.1.10.3') 'SteelSeries – Systemgerät – 1.1.10.3'
Test-Equal 'Titel: unbekannte Art bleibt' (Format-UpdateTitle 'Acme - Gizmo - 1.2') 'Acme – Gizmo – 1.2'
Test-Equal 'Titel: andere Form bleibt unverändert' (Format-UpdateTitle 'Intel Driver Update (12.19.2.66)') 'Intel Driver Update (12.19.2.66)'
$pnp = @([pscustomobject]@{ Name = 'Generic PnP Monitor'; HardwareID = @('MONITOR\BNQ78CA') }, [pscustomobject]@{ Name = 'Brother MFC Scanner'; HardwareID = @('USB\VID_04F9&PID_04BB&NETSCN&MI_01', 'USB\VID_04F9&PID_04BB') })
Test-Equal 'Gerätename: genaue Kennung' (Find-DeviceName 'monitor\bnq78ca' $pnp) 'Generic PnP Monitor'
Test-Equal 'Gerätename: Teil der Kennung' (Find-DeviceName 'vid_04f9&pid_04bb&netscn' $pnp) 'Brother MFC Scanner'
Test-Equal 'Gerätename: unbekannt bleibt leer' (Find-DeviceName 'root\ssdevfactory' $pnp) ''

# --- Treiber für Geräte ohne Treiber aus dem Katalog ---
$rows = @(
    [pscustomobject]@{ Id = 'a'; Title = 'INTEL Driver Update (10.1.46.5)'; Products = 'Windows 11 Client, version 24H2 and later, Servicing Drivers'; Version = [version]'10.1.46.5'; Date = [datetime]'1968-07-17' },
    [pscustomobject]@{ Id = 'b'; Title = 'INTEL Driver Update (10.1.46.3)'; Products = 'Windows 11 Client, version 22H2 and later, Servicing Drivers'; Version = [version]'10.1.46.3'; Date = [datetime]'1968-07-17' },
    [pscustomobject]@{ Id = 'c'; Title = 'INTEL Driver Update (10.1.40.0)'; Products = 'Windows 10, version 1903 and later, Servicing Drivers'; Version = [version]'10.1.40.0'; Date = [datetime]'1968-07-17' },
    [pscustomobject]@{ Id = ''; Title = 'INTEL Driver Update (10.1.99.0)'; Products = 'Windows 11 Client, version 22H2 and later'; Version = [version]'10.1.99.0'; Date = [datetime]'1968-07-17' })
Test-Equal 'Katalog-Treiber: neuester passender für Windows 11 25H2' (Select-MissingDriverRow $rows 'Windows 11' '25H2').Id 'a'
Test-Equal 'Katalog-Treiber: auf 23H2 scheidet der für 24H2 aus' (Select-MissingDriverRow $rows 'Windows 11' '23H2').Id 'b'
Test-Equal 'Katalog-Treiber: Windows 10 bekommt den für Windows 10' (Select-MissingDriverRow $rows 'Windows 10' '22H2').Id 'c'
$mixed = @(
    [pscustomobject]@{ Id = 'f'; Title = 'Acme - Firmware - 9.0.0.0'; Products = 'Windows 11 Client, version 22H2 and later'; Version = [version]'9.0.0.0'; Date = [datetime]'2026-01-01' },
    [pscustomobject]@{ Id = 'e'; Title = 'Acme - Extension - 5.0.0.0'; Products = 'Windows 11 Client, version 22H2 and later'; Version = [version]'5.0.0.0'; Date = [datetime]'2026-01-01' },
    [pscustomobject]@{ Id = 'd'; Title = 'Acme - System - 2.0.0.0'; Products = 'Windows 11 Client, version 22H2 and later'; Version = [version]'2.0.0.0'; Date = [datetime]'2025-01-01' })
Test-Equal 'Katalog-Treiber: Firmware scheidet aus, der Treiber geht vor dem Zusatz' (Select-MissingDriverRow $mixed 'Windows 11' '25H2').Id 'd'
Test-Equal 'Katalog-Treiber: nur Firmware heißt nichts' ([bool](Select-MissingDriverRow @($mixed[0]) 'Windows 11' '25H2')) $false
Test-Equal 'Katalog-Treiber: ohne passenden Eintrag nichts' ([bool](Select-MissingDriverRow @($rows[2]) 'Windows 11' '25H2')) $false
$search = Get-BoardDriverSearch 'ASUS' 'System Product Name' 'ASUSTeK COMPUTER INC.' 'PRIME B760-PLUS D4'
Test-Equal 'Treibersuche: Eigenbau nimmt das Mainboard' $search.Name 'ASUSTeK PRIME B760-PLUS D4'
Test-Equal 'Treibersuche: Adresse ist https und kodiert' $search.Url 'https://www.bing.com/search?q=ASUSTeK%20PRIME%20B760-PLUS%20D4%20Chipsatz%20Treiber%20Download'
Test-Equal 'Treibersuche: Fertig-PC nimmt das Gerät' (Get-BoardDriverSearch 'LENOVO' '82RG' 'LENOVO' 'LNVNB161216').Name 'LENOVO 82RG'
Test-Equal 'Treibersuche: MSI gekürzt' (Get-BoardDriverSearch 'Micro-Star International Co., Ltd.' 'MS-7D43' 'Micro-Star International Co., Ltd.' 'PRO B660M-A DDR4 (MS-7D43)').Name 'MSI MS-7D43'
Test-Equal 'Treibersuche: ohne Modell keine Suche' ([bool](Get-BoardDriverSearch 'To Be Filled By O.E.M.' 'To Be Filled By O.E.M.' '' '')) $false

Write-Host ''
if ($script:Failures.Count -eq 0) { Write-Host "Alle $($script:Passed) Tests bestanden." -ForegroundColor Green; exit 0 }
Write-Host "$($script:Failures.Count) von $($script:Passed + $script:Failures.Count) Tests fehlgeschlagen:" -ForegroundColor Red
$script:Failures | ForEach-Object { Write-Host "  - $_" }
exit 1