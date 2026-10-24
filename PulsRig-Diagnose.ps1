# PulsRig - Diagnose-Paket: sammelt Angaben zum PC, das Fehlerprotokoll und den letzten Scan in einer ZIP-Datei,
# die sich zur Fehlersuche verschicken lässt. Wird von PulsRig.ps1 eingebunden.
#
# Nicht enthalten: Seriennummern, Benutzername und Name des PCs. Wo sie in Pfaden oder Meldungen stehen,
# werden sie durch Platzhalter ersetzt. Das Paket bleibt auf dem PC, bis der Nutzer es selbst verschickt.

# Ersetzt Benutzername und Name des PCs in einem Text durch Platzhalter
function Hide-DiagnoseNames([string]$Text) {
    foreach ($pair in @(@($env:USERNAME, 'BENUTZER'), @($env:COMPUTERNAME, 'PC'))) {
        if ("$($pair[0])".Length -ge 3) { $Text = [regex]::Replace($Text, [regex]::Escape($pair[0]), $pair[1], 'IgnoreCase') }
    }
    $Text
}

# Angaben zu PulsRig und zum PC als Text. Jede Abfrage für sich: fällt eine aus, steht der Grund da und der Rest bleibt.
function Get-DiagnoseText {
    $lines = New-Object Collections.Generic.List[string]
    $part = {
        param([string]$Title, [scriptblock]$Read)
        $lines.Add(''); $lines.Add("== $Title ==")
        try { foreach ($line in @(& $Read)) { $lines.Add("$line") } }
        catch { $lines.Add("nicht lesbar: $($_.Exception.Message)") }
    }
    $lines.Add("PulsRig-Diagnose vom $((Get-Date).ToString('dd.MM.yyyy HH:mm'))")
    & $part 'PulsRig' {
        "Version: $script:Version"
        "Gebaut: $script:Build"
        "Neuere Fassung: $script:VersionState"
        "Adminrechte: $(if ($script:IsAdmin) { 'ja' } else { 'nein' })"
        "Installiert unter Programme: $(if ($script:Installed) { 'ja' } else { 'nein' })"
        "Programmordner: $script:Root"
        "Gestartet über: $(try { Split-Path -Leaf (Get-Process -Id $PID).Path } catch { 'unbekannt' }) · Programmdateien: $(if ($script:Files) { 'in PulsRig.exe' } else { 'lose im Ordner' })"
        "Skin: $($script:Settings.Skin) · Farbdesign: $($script:Theme.Name) · Ring: $($script:Settings.Ring) · Animationen: $($script:Settings.Animations)"
        $me = [Diagnostics.Process]::GetCurrentProcess()
        "Arbeitsspeicher des Programms: {0:N0} MB belegt, {1:N0} MB zugesagt" -f ($me.WorkingSet64 / 1MB), ($me.PrivateMemorySize64 / 1MB)
    }
    & $part 'Windows' {
        $os = Get-CimInstance Win32_OperatingSystem
        "$($os.Caption) · Build $($os.BuildNumber) · $($os.OSArchitecture)"
        "PowerShell $($PSVersionTable.PSVersion) · Sprache $([cultureinfo]::CurrentUICulture.Name) · Ausführungsrichtlinie $(Get-ExecutionPolicy)"
        $screen = [Windows.SystemParameters]::PrimaryScreenWidth, [Windows.SystemParameters]::PrimaryScreenHeight
        "Bildschirm (in Fenstereinheiten): {0:N0} x {1:N0}" -f $screen[0], $screen[1]
        "Akku vorhanden: $(if (Get-CimInstance Win32_Battery) { 'ja (Notebook)' } else { 'nein' })"
        if ($script:CardState.Battery) { "Akku-Zustand: $($script:CardState.Battery.Text) der ursprünglichen Kapazität$(if ($script:CardState.Battery.Detail) { ' · ' + $script:CardState.Battery.Detail }) (Stand $($script:CardState.Battery.Date))" }
    }
    & $part 'Virenschutz' {
        @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { "$($_.displayName)" })
    }
    & $part 'Prozessor und Mainboard' {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        "$(("$($cpu.Name)" -replace '\s+', ' ').Trim()) · $($cpu.Manufacturer) · $($cpu.NumberOfCores) Kerne, $($cpu.NumberOfLogicalProcessors) Threads · Sockel $($cpu.SocketDesignation)"
        $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
        "Mainboard: $($board.Manufacturer) $($board.Product)"
        $system = Get-CimInstance Win32_ComputerSystem
        "Gerät: $($system.Manufacturer) $($system.Model)"
        $bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
        "BIOS: $($bios.SMBIOSBIOSVersion)$(if ($bios.ReleaseDate) { " vom $($bios.ReleaseDate.ToString('dd.MM.yyyy'))" })"
        "Temperatur des Prozessors: $(Get-CpuTempReport)"
        "Controller und Maus: $(if ($script:CardState.Input) { Get-InputSummary } else { 'noch nicht getestet' })"
    }
    & $part 'Grafik' {
        Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) · Treiber $($_.DriverVersion) · $(("$($_.PNPDeviceID)" -split '&')[0])" }
        "nvidia-smi gefunden: $(if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) { 'ja' } else { 'nein' })"
    }
    & $part 'Arbeitsspeicher (Namen der Steckplätze, wie das BIOS sie meldet)' {
        "Steckplätze laut BIOS: $((Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum)"
        Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
            "Bank `"$($_.BankLabel)`" · Platz `"$($_.DeviceLocator)`" · {0:N0} GB · läuft mit $($_.ConfiguredClockSpeed) MHz · gemeldet $($_.Speed) MHz · $("$($_.Manufacturer)".Trim()) $("$($_.PartNumber)".Trim())" -f ($_.Capacity / 1GB)
        }
    }
    & $part 'Laufwerke' {
        # direkt bei Windows gefragt: Get-PhysicalDisk würde ein Modul laden, das rund 90 MB belegt
        $media = @{ 3 = 'HDD'; 4 = 'SSD' }; $bus = @{ 7 = 'USB'; 8 = 'RAID'; 10 = 'SAS'; 11 = 'SATA'; 17 = 'NVMe' }; $health = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy' }
        Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop | Sort-Object { [int]$_.DeviceId } | ForEach-Object {
            # Zahl oder - falls das Modul doch geladen ist - schon das Wort
            $word = { param($value, $map) $n = 0; if ([int]::TryParse("$value", [ref]$n)) { if ($map.ContainsKey($n)) { $map[$n] } else { 'Unspecified' } } else { "$value" } }
            $kind = & $word $_.MediaType $media
            # meldet Windows die Bauart nicht, gilt die genauere aus der Laufwerksprüfung beim Start (fragt das Laufwerk selbst)
            if ($kind -eq 'Unspecified') { $number = "$($_.DeviceId)"; $match = @(@($script:LastDrives.Disks) | Where-Object { $_ -and "$($_.Number)" -eq $number -and $_.Media -and $_.Media -ne 'Unspecified' })[0]; if ($match) { $kind = "$($match.Media)" } }
            "$("$($_.FriendlyName)".Trim()) · $kind · $(& $word $_.BusType $bus) · {0:N0} GB · $(& $word $_.HealthStatus $health)" -f ($_.Size / 1GB)
        }
    }
    & $part 'Speicherverlauf dieser Sitzung' {
        Add-MemTrace 'Diagnose-Paket'
        $script:MemTrace
    }
    & $part 'Geladene Bausteine' {
        "Im Fenster: $(@(Get-Module | ForEach-Object { $_.Name } | Sort-Object) -join ', ')"
        # der Arbeitsbereich hat seine eigenen; gefragt wird nur, wenn dort gerade nichts läuft
        if (-not (Test-WorkerBusy)) {
            $ask = [powershell]::Create()
            try {
                $ask.Runspace = $runspace
                "Im Arbeitsbereich: $(@($ask.AddScript('Get-Module | ForEach-Object { $_.Name } | Sort-Object').Invoke()) -join ', ')"
            }
            finally { $ask.Dispose() }
        }
        else { 'Im Arbeitsbereich: gerade beschäftigt, nicht abgefragt' }
        $assemblies = [AppDomain]::CurrentDomain.GetAssemblies()
        "Geladene .NET-Bibliotheken: $($assemblies.Count), davon zur Laufzeit erzeugt: $(@($assemblies | Where-Object { $_.IsDynamic }).Count)"
        $me = [Diagnostics.Process]::GetCurrentProcess()
        "Threads: $($me.Threads.Count) · Handles: $($me.HandleCount) · läuft seit $($me.StartTime.ToString('HH:mm:ss')) · Obergrenze der Speicherverwaltung gesetzt: $(if ($env:COMPlus_GCgen0MaxBudget) { 'ja' } else { 'nein' })"
    }
    & $part 'Helfer neben der Uhr' {
        "Eingeschaltet: $(if ($script:Settings.Helper) { 'ja' } else { 'nein' }) · Wochenprüfung: $(if ($script:Settings.WeeklyScan) { 'ja' } else { 'nein' }) · Boost automatisch: $(if ($script:Settings.AutoBoost) { 'ja' } else { 'nein' })"
        "Gewählte Spiele: $(if (@($script:Settings.BoostGames).Count) { @($script:Settings.BoostGames) -join ', ' } else { 'keine' })"
        "Nur aufzeichnen: $(if (@($script:Settings.RecordList).Count) { @($script:Settings.RecordList) -join ', ' } else { 'keine' })"
        $records = @(Get-Recordings)
        "Spiele aufzeichnen: $(if ($script:Settings.RecordGames -ne $false) { 'ja' } else { 'nein' }) · Aufzeichnungen: $($records.Count)$(if ($records.Count) { ', neueste ' + $records[0].Name + ' (' + [int]((Get-RecordingSize $records[0].FullName) / 1KB) + ' KB)' })"
        "Zustand: $(Get-HelperStatus)"
        "Boost gerade an: $(if (Test-Path -LiteralPath (Join-Path $script:OutDir 'Spiel-Beschleunigung.json')) { 'ja' } else { 'nein' })"
    }
    & $part 'Letzter Scan in dieser Sitzung' {
        $scan = $script:LastResult
        if (-not $scan) { return 'In dieser Sitzung wurde noch nicht gescannt.' }
        $extra = @(if ($scan.Nvidia -and $scan.Nvidia.IsNewer) { 'NVIDIA' }; if ($scan.Amd -and $scan.Amd.IsNewer) { 'AMD-Chipsatz' }; if ($scan.RadeonDriver -and $scan.RadeonDriver.IsNewer) { 'Radeon' })
        "Geräte: $($scan.Devices) · neuere Treiber: $(@($scan.Updates).Count) von Windows Update$(if ($extra.Count) { ' + ' + ($extra -join ' + ') }) · Gerätefehler: $(@($scan.Problems).Count) · Katalog-Hinweise: $(@($scan.Hints).Count)"
        $silent = @($scan.Failed | Where-Object { $_ })
        "Quellen ohne Antwort: $(if ($silent.Count -gt 0) { $silent -join ', ' } else { 'keine' })"
        if ($scan.SearchError) { "Windows Update: $($scan.SearchError)" }
        if ($scan.Nvidia) { "NVIDIA: installiert $($scan.Nvidia.Installed), neueste $($scan.Nvidia.Latest)" }
        if ($scan.RadeonDriver) { "Radeon ($($scan.RadeonDriver.Gpu)): installiert $($scan.RadeonDriver.Installed), neueste $($scan.RadeonDriver.Latest)" }
        if ($scan.Amd) { "AMD-Chipsatz ($($scan.Amd.Chipset)): installiert $($scan.Amd.Installed), neueste $($scan.Amd.Latest)" }
        foreach ($problem in @($scan.Problems)) { "Gerätefehler: $($problem.Name) (Code $($problem.Code)) · $(("$($problem.Id)" -split '&SUBSYS')[0])$(if ($problem.Chipset) { ' · als Chipsatz erkannt' })$(if ($problem.Catalog) { " · im Katalog: $($problem.Catalog)" })" }
    }
    Hide-DiagnoseNames ($lines -join "`r`n")
}

# Baut das Paket und gibt den Pfad der ZIP-Datei zurück. Vorgabe ist der Desktop.
# Extra: weitere Dateien für das Paket (Name = Inhalt), z. B. der Prüfbericht; Prefix: Anfang des Dateinamens.
function New-DiagnosePackage([string]$Folder = [Environment]::GetFolderPath('Desktop'), [hashtable]$Extra = @{}, [string]$Prefix = 'PulsRig-Diagnose') {
    $stamp = (Get-Date).ToString('yyyy-MM-dd-HHmm')
    $work = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Diagnose-$stamp-$PID"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $utf8 = New-Object Text.UTF8Encoding $true
        [IO.File]::WriteAllText((Join-Path $work 'Angaben.txt'), (Get-DiagnoseText), $utf8)
        foreach ($name in $Extra.Keys) { [IO.File]::WriteAllText((Join-Path $work $name), "$($Extra[$name])", $utf8) }
        # vorhandene Dateien des Programms: als Text mitnehmen, Namen ersetzt
        $copies = [ordered]@{
            'Fehlerprotokoll.txt'  = $script:ErrorLog
            'Einstellungen.json'   = $script:SettingsPath
            'Ergebnisse.json'      = $script:ResultsPath
            'Werkzeug-Protokoll.txt' = (Join-Path $script:OutDir 'Treiber-Scan.log')
            'Helfer-Protokoll.txt' = (Join-Path $script:OutDir 'PulsRig-Hintergrund.log')
        }
        foreach ($name in $copies.Keys) {
            $source = "$($copies[$name])"
            if (-not $source -or -not (Test-Path -LiteralPath $source)) { continue }
            try {
                $text = [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8)
                # die Tagesbilder für "Was hat sich geändert?" enthalten Programmlisten: die gehören nicht ins Paket
                if ($name -eq 'Ergebnisse.json') {
                    try {
                        $data = $text | ConvertFrom-Json
                        if ($data.History -and $data.History.PSObject.Properties['Snapshots']) {
                            $data.History.Snapshots = "$(@($data.History.Snapshots).Count) Tagesbilder (nicht im Paket)"
                            $text = $data | ConvertTo-Json -Depth 8
                        }
                    }
                    catch { }
                }
                # vom Fehlerprotokoll genügt das Ende: dort stehen die jüngsten Fehler
                if ($text.Length -gt 400000) { $text = "[gekürzt]`r`n" + $text.Substring($text.Length - 400000) }
                [IO.File]::WriteAllText((Join-Path $work $name), (Hide-DiagnoseNames $text), $utf8)
            }
            catch { }
        }
        # was in dieser Sitzung in den Dialogen der Werkzeuge und beim Installieren stand
        if ($script:RunLog.Length -gt 0) {
            try { [IO.File]::WriteAllText((Join-Path $work 'Werkzeug-Ausgabe.txt'), (Hide-DiagnoseNames $script:RunLog.ToString().Trim()), $utf8) } catch { }
        }
        if ($script:LastResult) {
            try { [IO.File]::WriteAllText((Join-Path $work 'Letzter-Scan.json'), (Hide-DiagnoseNames ($script:LastResult | ConvertTo-Json -Depth 6)), $utf8) } catch { }
        }
        # erst im Temp-Ordner packen, dann an den Zielort kopieren: so scheitert das Packen nicht am Zielordner
        $packed = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Paket-$stamp-$PID.zip"
        try {
            New-DiagnoseZip $work $packed
            Copy-DiagnoseZip $packed "$Prefix-$stamp.zip" $Folder
        }
        finally { Remove-Item -LiteralPath $packed -Force -Confirm:$false -ErrorAction SilentlyContinue }
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
}

# Packt einen Ordner in eine ZIP-Datei. Zuerst direkt mit .NET; Compress-Archive nur als Ersatz, denn das braucht ein
# eigenes Modul, das auf manchen PCs fehlt oder sich nicht laden lässt, und stolpert über [ ] im Pfad.
function New-DiagnoseZip([string]$Source, [string]$Zip) {
    if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force -Confirm:$false }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($Source, $Zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    }
    catch {
        Write-AppError $_
        if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force -Confirm:$false -ErrorAction SilentlyContinue }
        Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $Source | ForEach-Object { $_.FullName }) -DestinationPath $Zip
    }
}

# Wo ein Paket landen kann, in dieser Reihenfolge: der gewünschte Ordner (meist der Desktop), Downloads, der Datenordner
# von PulsRig. Der Desktop fällt z. B. aus, wenn der überwachte Ordnerzugriff von Windows ihn sperrt, OneDrive ihn
# verschoben hat oder es ihn nicht gibt.
function Get-DiagnoseFolders([string]$Folder) {
    $downloads = $null
    try { $downloads = [Environment]::ExpandEnvironmentVariables("$((Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}')") } catch { }
    if (-not $downloads) { $downloads = Join-Path $env:USERPROFILE 'Downloads' }
    @($Folder, $downloads, $script:OutDir) | Where-Object { "$_".Trim() } | Select-Object -Unique
}

# Kopiert die fertige ZIP-Datei in den ersten Ordner, der sie annimmt, und gibt den Pfad zurück
function Copy-DiagnoseZip([string]$Packed, [string]$Name, [string]$Folder) {
    $last = $null
    foreach ($place in @(Get-DiagnoseFolders $Folder)) {
        try {
            if (-not (Test-Path -LiteralPath $place)) { [IO.Directory]::CreateDirectory($place) | Out-Null }
            $target = Join-Path $place $Name
            [IO.File]::Copy($Packed, $target, $true)
            return $target
        }
        catch { $last = $_; Write-AppError $_ }
    }
    if ($last) { throw $last }
    throw 'Kein Ordner nimmt die ZIP-Datei an.'
}

# Wo die Datei liegt, für die Meldung im Fenster: "auf dem Desktop", "im Ordner Downloads" oder "im Datenordner von PulsRig"
function Get-DiagnosePlace([string]$File) {
    $folder = try { Split-Path -Parent $File } catch { '' }
    $desktop = try { [Environment]::GetFolderPath('Desktop') } catch { '' }
    if ($desktop -and $folder -eq $desktop.TrimEnd('\')) { return 'auf dem Desktop' }
    if ($script:OutDir -and $folder -eq "$($script:OutDir)".TrimEnd('\')) { return 'im Datenordner von PulsRig' }
    if ((Split-Path -Leaf $folder) -eq 'Downloads' -or $folder -eq (@(Get-DiagnoseFolders '')[0])) { return 'im Ordner Downloads' }
    'im gewählten Ordner'
}

# Adresse für Diagnose-Pakete und Fehlermeldungen (steht auch auf der Webseite)
$script:SupportMail = 'pulsrig.hilfe@gmail.com'

# Öffnet eine fertige Mail an die Adresse und zeigt das Paket im Ordner, damit es sich anhängen lässt.
# Eine Mail-Adresse kann kein Programm von selbst anhängen; ohne Mailprogramm bleibt die Adresse in der Zwischenablage.
function Send-DiagnoseMail([string]$File) {
    try { Set-Clipboard -Value $script:SupportMail } catch { }
    $subject = [Uri]::EscapeDataString("PulsRig $($script:Version): Diagnose-Paket")
    $text = if ($script:Language -eq 'en') { "Hello,`r`n`r`nthis does not work for me:`r`n`r`n`r`nThe diagnostics package is attached: $(Split-Path -Leaf $File)`r`n" }
    else { "Hallo,`r`n`r`nbei mir klappt Folgendes nicht:`r`n`r`n`r`nDas Diagnose-Paket hängt an: $(Split-Path -Leaf $File)`r`n" }
    $body = [Uri]::EscapeDataString($text)
    $mailOpened = $true
    try { Start-Process "mailto:$($script:SupportMail)?subject=$subject&body=$body" } catch { $mailOpened = $false }
    try { Start-Process explorer.exe "/select,`"$File`"" } catch { }
    Set-SheetStateText $(if ($mailOpened) { "Mail an $($script:SupportMail) geöffnet – die ZIP-Datei aus dem Ordner anhängen" } else { "Kein Mailprogramm gefunden. Die Adresse $($script:SupportMail) ist kopiert – im Browser eine Mail schreiben und die ZIP-Datei anhängen" })
}

function Open-DiagnoseSheet {
    $opened = Open-Sheet @{
        Title     = 'Diagnose-Paket'
        Sub       = 'Angaben für die Fehlersuche in einer Datei'
        Glyph     = 0xE74E
        Primary   = 'Paket erstellen'
        Link      = 'Im Ordner zeigen'
        Show      = {
            param($tab)
            Show-SheetPanel
            Add-SheetText 'Wozu' "Läuft etwas nicht, wie es soll, hilft diese Datei bei der Suche nach dem Grund. Sie landet auf dem Desktop; verschickt wird nichts von allein. Schick sie mit ein paar Worten zum Fehler an $($script:SupportMail)." 0xE946
            Add-SheetText 'Angaben zum PC' 'Windows-Version, Prozessor, Mainboard, Grafikkarte samt Treiber, Riegel und Namen der Steckplätze, Laufwerke, Virenschutz.' 0xE950
            Add-SheetText 'Aus PulsRig' 'Version, Einstellungen, Testergebnisse, das Fehlerprotokoll, der letzte Scan und die Ausgabe der Werkzeuge dieser Sitzung.' 0xE9D9
            Add-SheetText 'Nicht enthalten' 'Seriennummern, dein Benutzername und der Name des PCs. Wo sie in Pfaden stehen, werden sie durch Platzhalter ersetzt.' 0xE72E
            Add-SheetText 'Tipp' 'Vorher einmal scannen und den Fehler noch einmal auslösen, ohne PulsRig dazwischen zu schließen – dann steht beides im Paket.' 0xE82F
            Set-SheetStateText $(if ($script:Sheet.File) { "Gespeichert: $(Split-Path -Leaf $script:Sheet.File)" } else { 'Noch kein Paket erstellt' })
        }
        OnPrimary = {
            try {
                $window.Cursor = [Windows.Input.Cursors]::Wait
                $script:Sheet.File = if ($Snapshot) { New-DiagnosePackage $Snapshot } else { New-DiagnosePackage }
                $place = Get-DiagnosePlace $script:Sheet.File
                Set-SheetStateText "Gespeichert $($place): $(Split-Path -Leaf $script:Sheet.File)"
                Set-CardState 'Diagnose' @{ Text = "erstellt $((Get-Date).ToString('HH:mm'))"; Place = $place; File = $script:Sheet.File }
                # danach schickt derselbe Knopf das Paket per Mail
                $ui.BtnSheetPrimary.Content = T 'Per E-Mail schicken'
                $script:Sheet.OnPrimary = { Send-DiagnoseMail $script:Sheet.File }
            }
            catch { Write-AppError $_; Set-SheetStateText "Das Paket ließ sich nicht erstellen: $(@("$($_.Exception.Message)" -split "`r?`n")[0])" }
            finally { $window.Cursor = $null }
        }
        OnLink    = { if ($script:Sheet.File) { Start-Process explorer.exe "/select,`"$($script:Sheet.File)`"" } else { Set-SheetStateText 'Erst ein Paket erstellen' } }
    }
    if (-not $opened) { return }
}
