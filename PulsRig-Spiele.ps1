# PulsRig - "Deine Spiele": der Spiel-Check pro Spiel. Wird von PulsRig.ps1 nach PulsRig-Aufzeichnung.ps1 eingebunden.
#
# Oben, was für alle Spiele gilt (Bildwiederholrate, Gaming-Check, Grafiktreiber - dieselben Zeilen wie in "Was ist
# los?"), darunter jedes Spiel, das Windows kennt: auf welchem Laufwerk es liegt, die letzte aufgezeichnete Sitzung
# (Höchsttemperaturen, Drosseln) und ob es gerade läuft. Je Spiel ein Knopf: "Aufzeichnen" nimmt es in die Liste des
# Helfers auf, "Verlauf" zeigt die letzte Sitzung im Fenster Sensoren.
# Die Spiele und ihre Laufwerke liefert die Abfrage ProblemGames (PulsRig-Problem.ps1).

function Open-GamesSheet {
    $opened = Open-Sheet @{
        Title    = 'Deine Spiele'
        Sub      = 'Jedes Spiel einzeln: Laufwerk, Temperaturen beim Spielen und was für alle Spiele gilt'
        Glyph    = 0xE7FC
        Link     = 'Neu einlesen'
        Show     = { param($tab) Show-GamesTab }
        OnAction = { param($item) if ($item.Data) { Invoke-GamesAction $item.Data.Do $item.Data.Exe } }
        OnLink   = { $script:Sheet.Games = $null; Show-GamesTab; Start-GamesQuery }
    }
    if (-not $opened) { return }
    Start-GamesQuery
}

function Start-GamesQuery {
    Start-SheetLoader 'Suche die Spiele …'
    Start-Query 'ProblemGames' {
        param($result)
        # die Bildschirme kommen mit: so steht bei der Bildwiederholrate gleich ein Ergebnis
        if (@($result.Displays).Count) { Set-DisplayCardState @($result.Displays) }
        if ($script:Sheet -and $script:Sheet.Title -eq 'Deine Spiele') { $script:Sheet.Games = @($result.Games); Show-GamesTab }
    } @{ Displays = $script:Queries.Displays }
}

# die neueste Sitzung eines Spiels (Dateiname endet auf _<Programmdatei>.csv), sonst $null
function Get-GameRecording([string]$Exe) {
    if (-not $Exe) { return $null }
    @(Get-Recordings | Where-Object { $_.Name -like "*_$Exe.csv" })[0]
}

# eine Zeile je Spiel: Laufwerk, letzte Sitzung, Zustand und Knopf
function New-GameRow($Game) {
    $parts = @()
    $tone = 'good'; $state = 'in Ordnung'
    $where = if ($Game.Letter) { "$($Game.Letter):" } else { 'unbekanntes Laufwerk' }
    switch ("$($Game.Kind)") {
        'HDD' { $parts += "$where Festplatte (HDD): lädt langsamer, beim Nachladen sind Ruckler möglich"; $tone = 'warn'; $state = 'Festplatte' }
        'NVMe' { $parts += "$where NVMe-SSD" }
        'SSD' { $parts += "$where SSD" }
        default { $parts += $where }
    }
    if ($Game.Running) { $parts += 'läuft gerade' }
    $boost = @($script:Settings.BoostGames) -contains "$($Game.Exe)"
    $own = @($script:Settings.RecordList) -contains "$($Game.Exe)"
    $chosen = $boost -or $own
    $file = Get-GameRecording $Game.Exe
    $action = ''; $do = ''
    if ($file) {
        try {
            $recording = Read-Recording $file.FullName
            $summary = Get-RecordingSummary $recording
            $played = "zuletzt gespielt $($recording.Begin.ToString('dd.MM.')) ($(T (Format-Duration $recording.Seconds)))"
            $temps = @()
            if ($summary.Cpu) { $temps += ('Prozessor bis {0:N0} °C' -f $summary.Cpu.Max) }
            if ($summary.Gpu) { $temps += ('Grafikkarte bis {0:N0} °C' -f $summary.Gpu.Max) }
            $parts += $played
            $parts += $temps
            if ($summary.Tone -eq 'warn') { $parts += 'zu warm oder gedrosselt'; $tone = 'warn'; if ($state -eq 'in Ordnung') { $state = 'zu warm' } }
            else { $parts += 'kein Drosseln' }
        }
        catch { $parts += 'letzte Sitzung nicht lesbar' }
        $action = 'Verlauf'; $do = 'history'
    }
    elseif ($chosen) {
        $parts += 'wird beim nächsten Spielen aufgezeichnet'
        # nur aufgezeichnet (ohne Boost): lässt sich hier wieder abwählen; Boost-Spiele unter Boost → Einrichten → Spiele
        if ($own -and -not $boost) { $action = 'Nicht aufzeichnen'; $do = 'unrecord' }
    }
    else { $parts += 'wird nicht aufgezeichnet'; $action = 'Aufzeichnen'; $do = 'record' }
    if (-not $file -and $tone -eq 'good') { $state = 'ohne Messung'; $tone = '' }
    New-SheetRow -Title $Game.Name -Sub ($parts -join ' · ') -Glyph $(if ($Game.Running) { 0xE768 } else { 0xE7FC }) -Tone $tone -State $state -Action $action -Data @{ Do = $do; Exe = "$($Game.Exe)" }
}

function Show-GamesTab {
    $rows = @()
    $rows += New-SheetRow -Kind 'head' -Title 'FÜR ALLE SPIELE'
    $rows += New-ProblemRow 'Bildwiederholrate' 'Läuft der Monitor mit seiner höchsten Hz-Zahl? Sonst wirkt jedes Spiel weniger flüssig' 0xE7F4 'monitor' 'Prüfen' 'displays'
    $rows += New-ProblemRow 'Gaming-Check' 'Energieplan, voller Takt des Speichers, Spielmodus und mehr: sieben Einstellungen, die fürs Spielen zählen' 0xE7FC 'gamecheck' 'Prüfen' 'gamecheck'
    $rows += New-ProblemRow 'Grafiktreiber aktuell?' 'Ein Scan prüft NVIDIA, AMD und Windows Update auf neuere Treiber' 0xE896 'scan' 'Scan starten' 'scan'
    $rows += New-SheetRow -Kind 'head' -Title 'JEDES SPIEL EINZELN'
    $games = $script:Sheet.Games
    if ($null -eq $games) { $rows += New-SheetRow -Title 'Suche die Spiele …' -Glyph 0xE895 -Tone '' }
    elseif (@($games).Count -eq 0) { $rows += New-SheetRow -Title 'Windows kennt noch keine Spiele' -Sub 'Sobald ein Spiel einmal gelaufen ist, steht es hier.' -Glyph 0xE7FC -Tone '' }
    else {
        # zuerst, was laufen oder auffallen sollte, dann nach Namen
        $rows += @($games | Sort-Object { if ($_.Running) { 0 } else { 1 } }, { if ("$($_.Kind)" -eq 'HDD') { 0 } else { 1 } }, { $_.Name } | ForEach-Object { New-GameRow $_ })
    }
    Show-SheetList $rows
    $count = @($games).Count
    Set-SheetStateText $(if ($null -eq $games) { 'Suche die Spiele …' } else { "$count Spiele" + ' · aufgezeichnet werden die Boost-Spiele und die hier gewählten – „Aufzeichnen“ schaltet keinen Boost ein' })
}

function Invoke-GamesAction([string]$Do, [string]$Exe) {
    switch ($Do) {
        'record' {
            # in die eigene Liste der Aufzeichnung - nicht in die des Boosts; der Helfer liest sie im nächsten Takt
            if ($Exe -and @($script:Settings.RecordList) -notcontains $Exe) { $script:Settings.RecordList = @(@($script:Settings.RecordList) + $Exe) }
            if ($script:Settings.RecordGames -eq $false) { $script:Settings.RecordGames = $true }
            Save-Settings
            Show-GamesTab
            Set-SheetStateText $(if (-not $script:Settings.Helper) { 'Gemerkt. Aufgezeichnet wird im Helfer neben der Uhr: unter Optionen → Hintergrund einschalten.' } else { 'Gemerkt: Beim nächsten Spielen zeichnet der Helfer auf.' })
        }
        'unrecord' {
            $script:Settings.RecordList = @($script:Settings.RecordList | Where-Object { $_ -ne $Exe })
            Save-Settings
            Show-GamesTab
        }
        'history' {
            $file = Get-GameRecording $Exe
            if ($file) { $script:RecordPick = $file.FullName }
            Close-Sheet -Quick
            Open-SensorSheet 1
        }
        default { Invoke-ProblemAction $Do }
    }
}
