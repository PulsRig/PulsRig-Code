# PulsRig - "Was ist los?": vom Problem zur Ursache. Wird von PulsRig.ps1 nach PulsRig-Startseite.ps1 eingebunden.
#
# Oben wählt man, was nicht stimmt (Spiele ruckeln, stürzt ab, langsam, kein Ton, Internet, Sonstiges); darunter
# stehen die passenden Prüfungen in der Reihenfolge, in der sie am häufigsten die Ursache finden. Jede Zeile sagt,
# was PulsRig schon weiß (letzte Prüfung), und führt mit einem Klick zur Prüfung, zum Werkzeug oder zur Seite.
# Bei "Spiele ruckeln" kommt eine Liste der erkannten Spiele dazu: liegt eins auf einer Festplatte statt einer SSD?

$script:Queries.ProblemGames = @'
param($a)
# Laufwerksbuchstabe -> Bauart (SSD, HDD, NVMe); dazu die Spiele, die Windows als Spiel kennt
$kinds = @{}
try {
    # Get-DiskList (Treiber-Werkzeuge.ps1) erkennt auch Festplatten, die Windows als "Unspecified" meldet
    $disks = @(Get-DiskList)
    foreach ($partition in @(Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })) {
        $disk = @($disks | Where-Object { "$($_.DeviceId)" -eq "$($partition.DiskNumber)" })[0]
        $kind = if (-not $disk) { '' } elseif ("$($disk.BusType)" -eq 'NVMe') { 'NVMe' } else { "$($disk.MediaType)" }
        $kinds["$($partition.DriveLetter)".ToUpper()] = $kind
    }
}
catch { }
$games = @()
foreach ($game in @(Get-KnownGames)) {
    $letter = if ("$($game.Path)" -match '^([A-Za-z]):') { $Matches[1].ToUpper() } else { '' }
    $games += @{ Name = "$($game.Name)"; Letter = $letter; Kind = "$($kinds[$letter])"; Exe = "$($game.Exe)"; Running = [bool]$game.Running }
}
@{ Games = $games }
'@

$script:ProblemTabs = 'Spiele ruckeln', 'Stürzt ab', 'Ist langsam', 'Kein Ton', 'Internet', 'Sonstiges'

function Open-ProblemSheet([int]$Tab = 0) {
    $opened = Open-Sheet @{
        Title    = 'Was ist los?'
        Sub      = 'Problem wählen: PulsRig zeigt, was es schon weiß, und was als Nächstes zu prüfen ist'
        Glyph    = 0xE9CE
        Tabs     = $script:ProblemTabs
        Show     = { param($tab) Show-ProblemTab }
        OnAction = { param($item) if ($item.Data) { Invoke-ProblemAction $item.Data.Do } }
    }
    if (-not $opened) { return }
    if ($Tab -gt 0) { Select-SheetTab $Tab }
    Start-Query 'ProblemGames' { param($result) if ($script:Sheet -and $script:Sheet.Title -eq 'Was ist los?') { $script:Sheet.Games = @($result.Games); if ([int]$script:Sheet.Tab -eq 0) { Show-ProblemTab } } }
}

# was PulsRig aus der letzten Prüfung weiß: Text fürs Schild und Ton (good/warn/bad, leer = unbekannt)
function Get-ProblemState([string]$Name) {
    switch ($Name) {
        'gamecheck' {
            $state = $script:CardState.GameCheck
            if ($state -and $state.Text) { return @{ Text = "$($state.Text) von 100"; Tone = "$($state.Tone)" } }
        }
        'stress' {
            $stress = $script:StressResult
            if ($stress -and $stress.Title) { return @{ Text = ("$($stress.Title)" -split ' – ')[0]; Tone = "$($stress.Tone)" } }
        }
        'scan' {
            if ($ui.NavHomeBadge.Visibility -eq 'Visible') { return @{ Text = "$($ui.NavHomeCount.Text) offen"; Tone = 'warn' } }
            if ($script:LastResult) { return @{ Text = 'aktuell'; Tone = 'good' } }
        }
        'probation' {
            if ($ui.ProbeWarn.Visibility -eq 'Visible') { return @{ Text = 'auffällig'; Tone = 'warn' } }
            if (@($script:History.Probation | Where-Object { $_ }).Count -gt 0) { return @{ Text = 'unauffällig'; Tone = 'good' } }
        }
        'space' {
            $bar = @($script:CardState.Drives.Bars | Where-Object { "$_" -match '^C\|(\d+)$' })[0]
            if ($bar -and "$bar" -match '^C\|(\d+)$') { $used = [int]$Matches[1]; return @{ Text = "C: $used % belegt"; Tone = $(if ($used -ge 90) { 'warn' } else { 'good' }) } }
        }
        'cooling' {
            if (Get-Command Get-CoolingState -ErrorAction SilentlyContinue) { $state = Get-CoolingState; if ($state.Text) { return $state } }
        }
        'crashes' {
            # ohne geöffnetes Abstürze-Fenster gilt der Stand der Prüfung beim Start (PulsRig-Probezeit.ps1)
            $state = $script:CardState.Crashes
            if ((-not $state -or -not $state.Text) -and $script:LastCrashes) { $state = Get-CrashCardState $script:LastCrashes }
            if ($state -and $state.Text) { return @{ Text = $(if ($state.Date) { Format-CardState $state } else { "$($state.Text)" }); Tone = "$($state.Tone)" } }
        }
        default {
            $key = @{ crashes = 'Crashes'; drives = 'Drives'; memory = 'Memory'; battery = 'Battery'; ping = 'Ping'; bench = 'Bench'; displays = 'Displays' }[$Name]
            $state = if ($key) { $script:CardState[$key] } else { $null }
            if ($state -and $state.Text) { return @{ Text = (Format-CardState $state); Tone = "$($state.Tone)" } }
        }
    }
    $null
}

# eine Prüfung als Zeile; ohne Wissen heißt das Schild "noch nicht geprüft"
function New-ProblemRow([string]$Title, [string]$Sub, [int]$Glyph, [string]$Do, [string]$Action = 'Öffnen', [string]$Known) {
    $state = if ($Known) { Get-ProblemState $Known } else { $null }
    $text = if ($state) { $state.Text } elseif ($Known) { 'noch nicht geprüft' } else { '' }
    $tone = if ($state) { $state.Tone } else { 'accent' }
    New-SheetRow -Title $Title -Sub $Sub -Glyph $Glyph -Tone $tone -State $text -Action $Action -Data @{ Do = $Do }
}

# was die Abstürze der letzten 30 Tage schon verraten, als Zeilen mit dem nächsten Schritt
function Get-ProblemCrashRows([switch]$Graphics) {
    if (-not $script:LastCrashes) { return @() }
    $found = @(Get-CrashFindings $script:LastCrashes | Where-Object { -not $Graphics -or $_.Graphics })
    @($found | Select-Object -First 4 | ForEach-Object { New-CrashRow $_ })
}

function Show-ProblemTab {
    $rows = @()
    switch ([int]$script:Sheet.Tab) {
        0 {
            $found = @(Get-ProblemCrashRows -Graphics)
            if ($found.Count) { $rows += New-SheetRow -Kind 'head' -Title 'SCHON GEFUNDEN'; $rows += $found }
            $rows += New-SheetRow -Kind 'head' -Title 'DIE HÄUFIGSTEN URSACHEN'
            $rows += New-ProblemRow 'Gaming-Check' 'Bildwiederholrate, Energieplan, voller Takt des Speichers: sieben Einstellungen, die fürs Spielen zählen' 0xE7FC 'gamecheck' 'Prüfen' 'gamecheck'
            $rows += New-ProblemRow 'Grafiktreiber aktuell?' 'Ein Scan prüft NVIDIA, AMD und Windows Update auf neuere Treiber' 0xE896 'scan' 'Scan starten' 'scan'
            $rows += New-ProblemRow 'Wird es zu heiß?' 'Der Stabilitätstest lastet Prozessor und Grafikkarte voll aus und misst, ob der Takt einbricht' 0xE945 'stress' 'Testen' 'stress'
            $rows += New-ProblemRow 'Wie warm wird es beim Spielen?' 'Der Helfer neben der Uhr zeichnet jede Spielsitzung auf: Temperaturen, Takt und ob etwas drosselt' 0xE9D9 'recordings' 'Ansehen'
            $rows += New-ProblemRow 'Lässt die Kühlung nach?' 'Vergleicht Temperaturen bei gleicher Leistung über Wochen: Wird es wärmer, ist es Zeit zum Entstauben' 0xE9CA 'wear' 'Ansehen' 'cooling'
            $rows += New-ProblemRow 'Programme im Hintergrund' 'Der Boost schaltet vor dem Spielen Dienste und speicherhungrige Programme ab' 0xEC4A 'boost' 'Zum Boost'
            $rows += New-ProblemRow 'Was startet mit Windows?' 'Jedes Programm im Autostart kostet Speicher und Rechenzeit, auch beim Spielen' 0xE7E8 'autostart' 'Ansehen'
            $rows += New-SheetRow -Kind 'head' -Title 'DEINE SPIELE'
            $games = $script:Sheet.Games
            if ($null -eq $games) { $rows += New-SheetRow -Title 'Suche die Spiele …' -Glyph 0xE895 -Tone '' }
            elseif (@($games).Count -eq 0) { $rows += New-SheetRow -Title 'Windows kennt noch keine Spiele' -Sub 'Sobald ein Spiel einmal gelaufen ist, steht es hier mit dem Laufwerk, auf dem es liegt.' -Glyph 0xE7FC -Tone '' }
            else {
                foreach ($game in @($games | Where-Object { $_.Kind -eq 'HDD' } | Sort-Object { $_.Name } | Select-Object -First 3)) {
                    $where = if ($game.Letter) { "$($game.Letter):" } else { 'unbekanntes Laufwerk' }
                    $rows += New-SheetRow -Title $game.Name -Sub "Liegt auf $where, einer Festplatte (HDD). Auf eine SSD verschoben lädt es schneller und ruckelt weniger beim Nachladen." -Glyph 0xEDA2 -Tone 'warn' -State 'Festplatte'
                }
                $count = @($games).Count
                $rows += New-ProblemRow $(if ($count -eq 1) { 'Das Spiel einzeln prüfen' } else { "Alle $count Spiele einzeln prüfen" }) 'Laufwerk, Temperaturen beim letzten Spielen und ob etwas gedrosselt hat' 0xE7FC 'games' 'Ansehen'
            }
        }
        1 {
            $found = @(Get-ProblemCrashRows)
            if ($found.Count) { $rows += New-SheetRow -Kind 'head' -Title 'SCHON GEFUNDEN'; $rows += $found }
            $rows += New-SheetRow -Kind 'head' -Title 'DER REIHE NACH'
            $rows += New-ProblemRow 'Abstürze verstehen' 'Bluescreens, plötzliches Ausgehen und Grafik-Aussetzer der letzten 30 Tage, jeweils mit Erklärung' 0xE7BA 'crashes' 'Ansehen' 'crashes'
            $rows += New-ProblemRow 'Neuer Treiber schuld?' 'Seit einem neuen Treiber mehr Abstürze? PulsRig vergleicht die Tage davor und danach' 0xE81C 'changes' 'Ansehen' 'probation'
            $rows += New-ProblemRow 'Arbeitsspeicher testen' 'Fehlerhafter Speicher ist eine häufige Ursache für Bluescreens' 0xE950 'memory' 'Prüfen' 'memory'
            $rows += New-ProblemRow 'Unter Last stabil?' 'Der Stabilitätstest zeigt, ob der PC bei voller Last abstürzt oder sich verrechnet' 0xE945 'stress' 'Testen' 'stress'
            $rows += New-ProblemRow 'Laufwerke in Ordnung?' 'Störungen und Zustand der Laufwerke aus dem Protokoll von Windows' 0xEDA2 'drives' 'Prüfen' 'drives'
        }
        2 {
            $rows += New-SheetRow -Kind 'head' -Title 'DER REIHE NACH'
            $rows += New-ProblemRow 'Was startet mit Windows?' 'Viele Programme im Autostart machen den Start und den Alltag langsam' 0xE7E8 'autostart' 'Ansehen'
            $rows += New-ProblemRow 'Ist das Laufwerk voll?' 'Unter 10 Prozent freiem Platz wird Windows spürbar langsamer' 0xE74D 'CleanDisk' 'Platz schaffen' 'space'
            $rows += New-ProblemRow 'Laufwerke in Ordnung?' 'Ein Laufwerk mit Störungen oder nachlassendem Tempo bremst alles aus' 0xEDA2 'drives' 'Prüfen' 'drives'
            $rows += New-ProblemRow 'Arbeitsspeicher voll?' 'Die Boost-Seite zeigt, wie viel belegt ist und welche Programme am meisten brauchen' 0xE950 'boost' 'Ansehen'
            $rows += New-ProblemRow 'Was hat sich geändert?' 'Seit wann ist es langsam? Neue Programme, Treiber und Windows-Updates der letzten Tage' 0xE81C 'changes' 'Ansehen'
            $rows += New-ProblemRow 'Wirklich langsamer als früher?' 'Der Benchmark misst Prozessor, Speicher, Grafikkarte und Laufwerk und vergleicht mit früheren Läufen' 0xEC4A 'bench' 'Messen' 'bench'
        }
        3 {
            $rows += New-SheetRow -Kind 'head' -Title 'DER REIHE NACH'
            $rows += New-ProblemRow 'Tonstörung beheben' 'Prüft Dienste, Stummschaltung und Ausgabegerät und repariert in Stufen' 0xE767 'FixAudio' 'Starten'
            $rows += New-ProblemRow 'Audiotreiber aktuell?' 'Ein Scan findet neuere Treiber für Soundkarte und Headset' 0xE896 'scan' 'Scan starten' 'scan'
            $rows += New-ProblemRow 'Gerät mit Fehler?' 'Erkennt Geräte, die Windows mit Fehler meldet, und richtet sie neu ein' 0xE7BA 'FixDevices' 'Starten'
        }
        4 {
            $rows += New-SheetRow -Kind 'head' -Title 'DER REIHE NACH'
            $rows += New-ProblemRow 'Ping-Test' 'Verzögerung, Schwankung und Verlust: zeigt, ob das Problem zu Hause (WLAN, Router) oder beim Anbieter liegt' 0xE916 'ping' 'Messen' 'ping'
            $rows += New-ProblemRow 'Netzwerkfehler beheben' 'Testet die Verbindung Schritt für Schritt und repariert in Stufen' 0xE774 'FixNetwork' 'Starten'
            $rows += New-ProblemRow 'Netzwerktreiber aktuell?' 'Ein Scan findet neuere Treiber für WLAN und Netzwerkkarte' 0xE896 'scan' 'Scan starten' 'scan'
            $rows += New-ProblemRow 'WLAN bricht im Standby ab?' 'Der Standby-Detektiv zeigt, welche Geräte den PC wecken dürfen' 0xE708 'standby' 'Ansehen'
        }
        5 {
            $rows += New-SheetRow -Kind 'head' -Title 'WEITERE PROBLEME'
            $rows += New-ProblemRow 'Bild unscharf oder falsche Auflösung' 'Prüft Grafiktreiber und empfohlene Auflösung' 0xE7F4 'FixResolution' 'Starten'
            $rows += New-ProblemRow 'Pixelfehler, Lichthof oder Schlieren?' 'Der Monitor-Test zeigt Farbflächen und ein Bewegungsbild im Vollbild' 0xE7F4 'monitor' 'Testen'
            $rows += New-ProblemRow 'Ein Gerät geht nicht' 'Erkennt fehlerhafte Geräte und richtet sie neu ein' 0xE7BA 'FixDevices' 'Starten'
            $rows += New-ProblemRow 'Controller oder Maus spinnt' 'Stick-Drift, Tasten, Abfragerate und ungewollte Doppelklicks prüfen' 0xE7FC 'input' 'Testen'
            $rows += New-ProblemRow 'PC wacht von selbst auf' 'Der Standby-Detektiv zeigt, was ihn weckt oder wach hält' 0xE708 'standby' 'Ansehen'
            $rows += New-ProblemRow 'BIOS veraltet?' 'Version, Alter und die Seite des Herstellers' 0xE713 'bios' 'Ansehen'
            if ($script:HasBattery) { $rows += New-ProblemRow 'Akku hält nicht mehr lange' 'Wie viel der Akku noch fasst, wie oft er geladen wurde und wie lange er laut Windows hält' 0xE83F 'battery' 'Ansehen' 'battery' }
            $rows += New-ProblemRow 'Hilfe holen' 'Ein Diagnose-Paket fasst alles für die Fehlersuche zusammen und geht per E-Mail an pulsrig.hilfe@gmail.com' 0xE9CE 'diagnose' 'Erstellen'
        }
    }
    Show-SheetList $rows
    Set-SheetStateText 'Am besten von oben nach unten: die ersten Punkte finden die häufigsten Ursachen'
}

function Invoke-ProblemAction([string]$Do) {
    switch ($Do) {
        'gamecheck' { Open-GameCheckSheet }
        'stress' { Open-StressSheet }
        'crashes' { Open-CrashSheet }
        'memory' { Open-MemorySheet }
        'drives' { Open-DriveSheet }
        'autostart' { Open-AutostartSheet }
        'changes' { Open-ChangesSheet }
        'standby' { Open-StandbySheet }
        'bios' { Open-BiosSheet }
        'battery' { Open-BatterySheet }
        'monitor' { Open-MonitorSheet }
        'ping' { Open-PingSheet }
        'bench' { Open-BenchSheet }
        'recordings' { Open-SensorSheet 1 }
        'wear' { Open-SensorSheet 2 }
        'input' { Close-Sheet -Quick; Open-InputSheet }
        'games' { Close-Sheet -Quick; Open-GamesSheet }
        'diagnose' { Open-ReportSheet }
        'boost' { Close-Sheet; Show-Page 'Boost' }
        'scan' { Close-Sheet; Show-Page 'Home'; Invoke-Later 450 { Start-Scan } }
        'restore' { Close-Sheet; Invoke-Later 350 { Open-ToolDialog 'Restore' } }
        default {
            # Werkzeuge laufen im Dialog: erst dieses Fenster schließen
            if ($script:Tools.Contains($Do)) { Close-Sheet; Invoke-Later 350 { param($name) Open-Tool $name } $Do }
        }
    }
}
