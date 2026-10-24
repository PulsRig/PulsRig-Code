<#
.SYNOPSIS
    PulsRig - grafische Oberfläche für die Treibersuche und die Werkzeuge.

.DESCRIPTION
    Zeigt Scan, Ergebnisse, Boost und Werkzeuge in einem eigenen Fenster. Die eigentliche Arbeit
    erledigen Treiber-Scan.ps1 und Treiber-Werkzeuge.ps1, die im selben Ordner liegen müssen:
    Sie laufen in einem Hintergrund-Arbeitsbereich, damit das Fenster währenddessen flüssig bleibt.

.PARAMETER NoElevate
    Keine Adminrechte anfordern. Scannen geht, Werkzeuge zeigen dann nur, was sie tun würden.

.PARAMETER Demo
    Beispieldaten statt eines echten Scans anzeigen.

.PARAMETER Snapshot
    Ordner für Bildschirmfotos: spielt die Oberfläche mit Beispieldaten durch, speichert Bilder
    der einzelnen Ansichten und beendet sich. Zum Prüfen des Aussehens gedacht.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoElevate,
    [switch]$Demo,
    [string]$Snapshot,
    # zusammen mit -Snapshot: echten Scan und echte Werkzeugläufe durchspielen statt Beispieldaten
    [switch]$Real,
    # vom Helfer: gleich nach dem Start scannen (Klick auf die Meldung "neuere Treiber")
    [switch]$StartScan
)

$ErrorActionPreference = 'Stop'
$script:Version = '0.7 Beta'
# Im installierten Programm stecken alle Dateien in PulsRig.exe: die Hülle (PulsRig-Start.cs) übergibt ihren Inhalt
# als $PulsRigEmbedded (Name der Datei -> Text) und ihren Ordner als $PulsRigRoot. In der Werkstatt und im
# ZIP-Paket liegen die Dateien lose daneben. Get-AppText und Get-AppCode liefern beides auf dieselbe Weise.
$script:Files = $PulsRigEmbedded
$script:Root = if ($PulsRigRoot) { "$PulsRigRoot" } else { Split-Path -Parent $PSCommandPath }
$script:Self = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $script:Root 'PulsRig.ps1' }
function Get-AppText([string]$Name) {
    if ($script:Files -and $script:Files.ContainsKey($Name)) { return $script:Files[$Name] }
    [IO.File]::ReadAllText((Join-Path $script:Root $Name), [Text.Encoding]::UTF8)
}
function Get-AppCode([string]$Name) { [scriptblock]::Create((Get-AppText $Name)) }
# Wann diese Fassung gebaut wurde: PulsRig-Paket.ps1 legt dem Paket die Datei PulsRig-Bau.txt bei. Die Versionsnummer
# allein sagt das nicht - dieselbe Version wird während einer Testphase mehrfach gebaut.
$script:Build = 'Werkstatt (nicht aus einem Paket)'
try {
    $buildFile = Join-Path $script:Root 'PulsRig-Bau.txt'
    if (($script:Files -and $script:Files.ContainsKey('PulsRig-Bau.txt')) -or (Test-Path -LiteralPath $buildFile)) {
        $script:Build = "$(@((Get-AppText 'PulsRig-Bau.txt') -split "`r?`n")[0])".Trim()
    }
}
catch { }
$script:Backend = Join-Path $script:Root 'Treiber-Scan.ps1'
# Daten (Einstellungen, Ergebnisse, geladene Treiber) liegen neben dem Programm. Ist es installiert - unter "Programme"
# darf nur ein Admin schreiben -, liegen sie im Benutzerordner. Siehe PulsRig-Installieren.ps1.
$script:Installed = $script:Root.StartsWith([Environment]::GetFolderPath('ProgramFiles'), [StringComparison]::OrdinalIgnoreCase)
$script:OutDir = if ($script:Installed) { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PulsRig' } else { Join-Path $script:Root 'Treiber' }
$script:ErrorLog = Join-Path $script:OutDir 'PulsRig-Fehler.log'
if ($Snapshot) { $Demo = -not $Real; $NoElevate = $true }

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script:Self`"")
}

$script:IsAdmin = Test-IsAdmin
if (-not $script:IsAdmin -and -not $NoElevate) {
    try {
        Restart-Elevated
        exit 0
    }
    catch { }   # Abfrage abgelehnt: eingeschränkt weiterlaufen
}

# Die Speicherverwaltung von .NET hält auf Prozessoren mit großem Zwischenspeicher über 100 MB auf Vorrat. Eine
# Obergrenze von 16 MB (Angabe hexadezimal) spart rund 70 MB; sie wirkt nur, wenn sie schon beim Start des Prozesses
# gesetzt ist. PulsRig.bat setzt sie - bei jedem anderen Start setzt das Programm sie selbst und startet sich einmal neu.
if (-not $env:COMPlus_GCgen0MaxBudget -and -not $Snapshot) {
    $env:COMPlus_GCgen0MaxBudget = '1000000'
    try {
        $again = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script:Self`"")
        if (-not $script:IsAdmin) { $again += '-NoElevate' }   # die Abfrage nach Adminrechten war schon dran
        if ($Demo) { $again += '-Demo' }
        Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -ArgumentList $again
        exit 0
    }
    catch { }   # Neustart nicht möglich: ohne die Obergrenze weiterlaufen
}

if (-not (Test-Path -LiteralPath $script:OutDir)) { New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null }

# Kennzeichen "PulsRig läuft": daran erkennt die Installationsdatei ein offenes Programm und bittet vor dem
# Aktualisieren oder Entfernen, es zu schließen (derselbe Name steht in PulsRig-Setup.iss unter AppMutex)
if (-not $Snapshot) { try { $script:RunningMark = New-Object Threading.Mutex $false, 'PulsRig-8B6C1F0E-Laeuft' } catch { } }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# 40 Bilder pro Sekunde genügen für die Animationen und halbieren fast die Rechenlast der Daueranimationen
try {
    [Windows.Media.Animation.Timeline]::DesiredFrameRateProperty.OverrideMetadata(
        [Windows.Media.Animation.Timeline], (New-Object Windows.FrameworkPropertyMetadata 40))
}
catch { }

# Mitschrift der Werkzeug- und Installationsläufe dieser Sitzung: was im Dialog stand, samt Rückfragen und Antworten.
# Sie kommt ins Diagnose-Paket - so lässt sich nachlesen, an welchem Schritt ein Lauf hing, ohne Bildschirmfoto.
$script:RunLog = New-Object Text.StringBuilder
function Add-RunLog([string]$Text, [bool]$NoNewline) {
    try {
        [void]$script:RunLog.Append($Text)
        if (-not $NoNewline) { [void]$script:RunLog.Append("`r`n") }
        # bei sehr langen Sitzungen das älteste Drittel fallen lassen
        if ($script:RunLog.Length -gt 300000) { [void]$script:RunLog.Remove(0, 100000) }
    }
    catch { }
}

# Speicherverlauf der Sitzung: nach jedem größeren Schritt eine Zeile mit dem Speicher des Programms. Er kommt ins
# Diagnose-Paket und zeigt, welcher Schritt wie viel kostet - auch auf PCs, an denen sich nichts nachmessen lässt.
$script:MemTrace = New-Object Collections.Generic.List[string]
function Add-MemTrace([string]$What) {
    try {
        $me = [Diagnostics.Process]::GetCurrentProcess()
        # "belegt" ist der Arbeitsspeicher, den das Programm wirklich nutzt (so zeigt ihn auch der Task-Manager);
        # "zugesagt" schwankt stark, weil die Oberfläche bei Übergängen kurz Platz vormerkt, ohne ihn zu benutzen
        $script:MemTrace.Add(('{0:HH:mm:ss}  {1,4:N0} MB belegt  {2,4:N0} MB zugesagt  {3,4:N0} MB .NET  {4}' -f (Get-Date), ($me.WorkingSet64 / 1MB), ($me.PrivateMemorySize64 / 1MB), ([GC]::GetTotalMemory($false) / 1MB), $What))
        while ($script:MemTrace.Count -gt 120) { $script:MemTrace.RemoveAt(0) }
    }
    catch { }
}

# Gibt Arbeitsspeicher zurück, den das Programm gerade nicht anfasst (vor allem Reste des Starts). Windows legt die
# Seiten nur beiseite und holt sie bei Bedarf zurück. Gemessen 24.10.2026: nach dem Start 270 -> 12 MB, nach einigen
# Seitenwechseln 185 statt 270 MB, minimiert 44 MB. Kurz Höchst- auf Mindestwert setzen leert den Arbeitsbereich wie
# EmptyWorkingSet, ohne eigenen C#-Code übersetzen zu müssen; danach gilt wieder der alte (weiche) Höchstwert.
function Clear-WorkingSet([string]$Why) {
    try {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        $me = [Diagnostics.Process]::GetCurrentProcess()
        $max = $me.MaxWorkingSet
        $me.MaxWorkingSet = $me.MinWorkingSet
        $me.MaxWorkingSet = $max
        Add-MemTrace "Speicher freigegeben: $Why"
    }
    catch { }
}

function Write-AppError($ErrorRecord) {
    $text = '{0:dd.MM. HH:mm:ss}  {1}{2}{3}' -f (Get-Date), $ErrorRecord.Exception.Message, [Environment]::NewLine, $ErrorRecord.ScriptStackTrace
    try { Add-Content -LiteralPath $script:ErrorLog -Value $text -Encoding UTF8 } catch { }
    if ($Snapshot) { Write-Host "FEHLER: $text" }
}

# Öffnet eine Webseite im Browser - nur echte https-Adressen, nie eine Datei oder ein anderes Programm
function Open-WebLink([string]$Url) {
    if ($Url -notmatch '^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9](/|$)') { throw "Keine Webadresse: $Url" }
    Start-Process $Url
}

# Pfade für die Anzeige: der eigene Benutzerordner erscheint als "Benutzerordner", damit der Kontoname nicht im
# Fenster steht (Bildschirmfotos werden weitergegeben). Geöffnet und gespeichert wird weiter am echten Ort.
function Format-ShownPath([string]$Text, [string]$UserFolder = $env:USERPROFILE) {
    if (-not $Text -or -not $UserFolder -or $UserFolder.Length -lt 4) { return $Text }
    [regex]::Replace($Text, [regex]::Escape($UserFolder.TrimEnd('\')) + '(?=\\|$|[\s"''])', 'Benutzerordner', 'IgnoreCase')
}

# --- Unterzeile der Startseite: welche Quellen ein Scan auf diesem PC fragt ---------
# Genannt wird nur, was der Scan hier wirklich fragt: NVIDIA nur mit NVIDIA-Karte, AMD nur mit AMD-Prozessor,
# beides nur, wenn "Hersteller direkt fragen" an ist, der Katalog nur, wenn er an ist (wie in PulsRig-Arbeit-Scan.ps1).
function Format-ScanHint([bool]$Nvidia, [bool]$Amd, [bool]$Catalog) {
    $names = @('Windows Update')
    if ($Nvidia) { $names += 'NVIDIA' }
    if ($Amd) { $names += 'AMD' }
    if ($Catalog) { $names += 'den Microsoft-Katalog' }
    $list = if ($names.Count -eq 1) { $names[0] } else { ($names[0..($names.Count - 2)] -join ', ') + ' und ' + $names[-1] }
    "Ein Klick auf SCAN prüft $list."
}

# Welche Hersteller im PC stecken, fragt das Programm einmal kurz nach dem Start; bis dahin steht ein allgemeiner Satz da
$script:ScanMakers = $null
function Get-ScanHint {
    if (-not $script:ScanMakers) { return 'Ein Klick auf SCAN sucht nach neueren Treibern.' }
    $ask = [bool]$script:Settings.Nvidia
    Format-ScanHint ($ask -and $script:ScanMakers.Nvidia) ($ask -and $script:ScanMakers.Amd) ([bool]$script:Settings.Catalog)
}

function Update-ScanHint {
    try {
        if (-not $script:ScanMakers) {
            $cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer)"
            $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name)" })
            $script:ScanMakers = @{ Nvidia = [bool]($gpus -match 'NVIDIA'); Amd = [bool]($cpu -match 'AMD') }
        }
        if ($script:Busy -ne 'scan') { $ui.HintText.Text = T (Get-ScanHint) }
    }
    catch { }
}

# --- Hinweis auf eine neuere Fassung --------------------------------------------
# Das Paketskript legt neben die Setup-Datei eine kleine Datei version.json (Version und Baudatum). Sie liegt im
# Projekt bei GitHub; das Programm liest sie beim Start einmal und vergleicht das Baudatum mit dem eigenen. Gibt es
# eine neuere Fassung, sagt es das Versionsschild oben rechts - ein Klick öffnet die Seite mit der Setup-Datei.
# Geladen oder installiert wird dabei nichts, und übertragen wird nichts außer der Anfrage selbst.
$script:UpdateRepo = 'PulsRig/PulsRig'   # "Konto/Projekt" bei GitHub; leer = kein Nachsehen
$script:VersionState = 'nicht geprüft'

# Baudatum aus der Zeile "13.10.2026 18:45 · Stand abc1234"; leer, wenn die Zeile keines enthält (Werkstatt)
function ConvertTo-BuildTime([string]$Text) {
    $time = [datetime]::MinValue
    if ($Text.Length -ge 16 -and [datetime]::TryParseExact($Text.Substring(0, 16), 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture, 'None', [ref]$time)) { return $time }
    $null
}

function Test-NewerBuild([string]$Mine, [string]$Theirs) {
    $own = ConvertTo-BuildTime $Mine; $other = ConvertTo-BuildTime $Theirs
    [bool]($own -and $other -and $other -gt $own)
}

# Liest die Antwort; alles Unerwartete (zu lang, kein JSON, seltsame Zeichen) zählt als "keine Angabe"
function Read-VersionNote([string]$Json) {
    if (-not $Json -or $Json.Length -gt 4000) { return $null }
    try { $note = $Json | ConvertFrom-Json } catch { return $null }
    $version = "$($note.Version)"; $built = "$($note.Gebaut)"
    if ($version -notmatch '^[\w .\-]{1,30}$' -or -not (ConvertTo-BuildTime $built)) { return $null }
    $result = @{ Version = $version; Built = $built; Setup = ''; Sha256 = ''; Bytes = 0 }
    # Selbst laden lässt sich die neue Fassung nur, wenn alles zusammenpasst: eine Setup-Datei aus den Releases des
    # eigenen Projekts, eine Prüfsumme und eine glaubhafte Größe. Sonst bleibt es beim Verweis auf die Webseite.
    $size = 0L
    if ($script:UpdateRepo -and "$($note.Setup)" -match ('^https://github\.com/' + [regex]::Escape($script:UpdateRepo) + '/releases/download/[\w.\-]{1,60}/PulsRig-Setup-[\w.\-]{1,40}\.exe$') -and
        "$($note.Sha256)" -match '^[0-9a-fA-F]{64}$' -and [long]::TryParse("$($note.Bytes)", [ref]$size) -and $size -ge 200KB -and $size -le 60MB) {
        $result.Setup = "$($note.Setup)"; $result.Sha256 = "$($note.Sha256)".ToUpper(); $result.Bytes = $size
    }
    $result
}

function Show-NewVersion($Note) {
    $script:NewVersion = $Note
    $ui.TitleVersion.Text = T $(if ($Note.Version -ne $script:Version) { "$($Note.Version) verfügbar" } else { 'Neue Fassung verfügbar' })
    Set-Paint $ui.TitleVersion 'Foreground' 'Accent'
    $box = $ui.TitleVersion.Parent
    $box.IsHitTestVisible = $true
    $box.Cursor = [Windows.Input.Cursors]::Hand
}

function Start-VersionCheck {
    if ($Snapshot -or -not $script:UpdateRepo -or -not $script:Settings.UpdateCheck -or -not (ConvertTo-BuildTime $script:Build)) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.WebClient
        $client.Headers['User-Agent'] = 'PulsRig'
        $client.Encoding = [Text.Encoding]::UTF8
        # die Anfrage läuft nebenher; ein Zeitgeber sieht nach, ob die Antwort da ist - das Fenster wartet nie darauf
        $script:VersionCheck = @{ Client = $client; Since = Get-Date
            Task = $client.DownloadStringTaskAsync("https://raw.githubusercontent.com/$($script:UpdateRepo)/main/version.json") }
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(400)
        $timer.Add_Tick({
                try {
                    $check = $script:VersionCheck
                    if (-not $check) { $this.Stop(); return }
                    if (-not $check.Task.IsCompleted) {
                        if (((Get-Date) - $check.Since).TotalSeconds -lt 20) { return }
                        $check.Client.CancelAsync()
                    }
                    $this.Stop()
                    $script:VersionCheck = $null
                    if ($check.Task.Status -eq 'RanToCompletion') {
                        $note = Read-VersionNote $check.Task.Result
                        if ($note -and (Test-NewerBuild $script:Build $note.Built)) { $script:VersionState = "neuere Fassung: $($note.Version), gebaut $($note.Built)"; Show-NewVersion $note }
                        elseif ($note) { $script:VersionState = 'aktuell' }
                        else { $script:VersionState = 'Antwort nicht lesbar' }
                    }
                    else { [void]$check.Task.Exception; $script:VersionState = 'nicht erreichbar' }   # kein Netz ist kein Fehler
                    $check.Client.Dispose()
                }
                catch { $script:VersionState = 'nicht erreichbar' }
            })
        $timer.Start()
    }
    catch { }
}

# Schreibt eine Datei in einem Zug: erst daneben, dann an ihren Platz. Bricht das Schreiben ab, bleibt die alte heil.
function Save-TextFile([string]$Path, [string]$Text) {
    $draft = "$Path.neu"
    [IO.File]::WriteAllText($draft, $Text, (New-Object Text.UTF8Encoding $true))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($draft, $Path, [NullString]::Value) } else { [IO.File]::Move($draft, $Path) }
}

# --- Einstellungen ------------------------------------------------------------

$script:SettingsPath = Join-Path $(if ($Snapshot) { $Snapshot } else { $script:OutDir }) 'PulsRig-Einstellungen.json'
# das Programm hieß früher driverdownloader: dessen Einstellungen einmalig übernehmen
$oldSettingsPath = Join-Path $script:OutDir 'driverdownloader-Einstellungen.json'
if (-not $Snapshot -and -not (Test-Path -LiteralPath $script:SettingsPath) -and (Test-Path -LiteralPath $oldSettingsPath)) {
    try { Copy-Item -LiteralPath $oldSettingsPath -Destination $script:SettingsPath } catch { }
}
$script:Settings = @{
    Animations       = $true
    Motion           = 'Normal'   # Stufe der Bewegung: Ruhig, Normal, Lebendig (aus = Animations aus)
    RememberPosition = $true
    AutoScan         = $false
    UpdateCheck      = $true      # beim Start einmal nachsehen, ob es eine neuere Fassung von PulsRig gibt
    Language         = 'de'       # Sprache der Oberfläche: 'de' oder 'en' (siehe PulsRig-Sprache.ps1)
    Helper           = $false     # Helfer neben der Uhr (PulsRig-Helfer.ps1)
    WeeklyScan       = $true      # der Helfer sieht einmal pro Woche nach Treibern
    AutoBoost        = $false     # der Helfer schaltet den Boost bei den gewählten Spielen ein
    BoostGames       = @()        # Programmdateien der Spiele ohne ".exe"
    RecordGames      = $true      # der Helfer zeichnet beim Spielen Temperaturen auf (PulsRig-Aufzeichnung.cs)
    RecordList       = @()        # nur aufzeichnen, ohne Boost: Programmdateien ohne ".exe" (die Boost-Spiele zählen auch)
    DriveWarnHidden  = ''         # weggeklickter Laufwerkshinweis der Startseite (Kennung, siehe PulsRig-Verlauf.ps1)
    ProbeWarnHidden  = ''         # weggeklickter Treiberhinweis der Startseite (Kennung, siehe PulsRig-Probezeit.ps1)
    PowerPrice       = 0.35       # Strompreis in €/kWh für die Stromkosten (PulsRig-Strom.ps1)
    PowerHours       = 4          # Stunden am Tag, die der PC läuft
    GameHours        = 2          # Stunden am Tag, die gespielt wird (FPS-Limit-Vergleich, PulsRig-Strom.ps1)
    Opacity          = 100
    Theme            = 'Lila-Nacht'
    ThemeHue         = 224.0
    Skin             = 'Bento'     # komplettes Aussehen: Formen, Schrift, Karten, Tempo (siehe PulsRig-Skins.ps1)
    LookVersion      = 0          # 1: einmal auf Nacht Puls umgestellt; 2: Namen entdoppelt; 3: einmal auf Nacht-Bento
    Ring             = 'Puls'     # Animation um den SCAN-Knopf
    SkinRing         = ''         # Skin, für den die Ring-Animation zuletzt umgestellt wurde (siehe PulsRig-Skins.ps1)
    Firmware         = $true      # Firmware-Updates in den Ergebnissen zeigen
    Nvidia           = $true      # NVIDIA direkt fragen
    Catalog          = $true      # Microsoft Update-Katalog durchsuchen
    ShowCurrent      = $true      # auch die aktuellen Treiber auflisten
    RestorePoint     = $true
    AutoBackup       = $true
    TargetDir        = ''         # leer = Ordner "Treiber" neben dem Programm
    Ignored          = @()        # @{ Key; Name }: Aktualisierungen, die nicht mehr angeboten werden
    Boost            = @{ Apps = @(); Services = $null; PowerPlan = $true; GameMode = $true; Clipboard = $false }
    Left             = $null
    Top              = $null
}

function Import-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) { return }
    try {
        $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @($script:Settings.Keys)) {
            $property = $saved.PSObject.Properties[$key]
            if (-not $property) { continue }
            $value = $property.Value
            switch ($key) {
                'BoostGames' { $script:Settings.BoostGames = @($value | Where-Object { $_ -is [string] -and $_ -match '^[\w .\-]{1,80}$' }) }
                'RecordList' { $script:Settings.RecordList = @($value | Where-Object { $_ -is [string] -and $_ -match '^[\w .\-]{1,80}$' }) }
                'Ignored' {
                    $script:Settings.Ignored = @($value | Where-Object { $_ -and $_.Key } | ForEach-Object { @{ Key = "$($_.Key)"; Name = "$($_.Name)" } })
                }
                'Boost' {
                    if ($value) {
                        $script:Settings.Boost = @{
                            Apps      = @($value.Apps | Where-Object { $_ })
                            # $null heißt: die vorgegebenen Dienste; eine leere Liste heißt: keine
                            # Das Komma hält eine leere Liste zusammen: ohne es käme aus dem "if" gar nichts heraus, und
                            # "keine Dienste" würde beim nächsten Start zu "die vorgegebenen". Nur Namen zählen - ein
                            # leeres Objekt aus einer so entstandenen Datei gilt als leere Liste.
                            Services  = $(if ($null -ne $value.Services) { , @($value.Services | Where-Object { $_ -is [string] -and $_ }) } else { $null })
                            PowerPlan = [bool]$value.PowerPlan
                            GameMode  = [bool]$value.GameMode
                            Clipboard = [bool]$value.Clipboard
                        }
                    }
                }
                default {
                    $default = $script:Settings[$key]
                    if ($default -is [bool]) { $script:Settings[$key] = [bool]$value }
                    elseif ($default -is [int]) { $script:Settings[$key] = [int]$value }
                    elseif ($default -is [double]) { $script:Settings[$key] = [double]$value }
                    elseif ($default -is [string]) { $script:Settings[$key] = "$value" }
                    else { $script:Settings[$key] = $value }
                }
            }
        }
    }
    catch { Write-AppError $_ }
}

function Save-Settings {
    try { Save-TextFile $script:SettingsPath ($script:Settings | ConvertTo-Json -Depth 5) }
    catch { Write-AppError $_ }
}

# Ordner für Downloads, Sicherungen und Berichte
function Get-TargetDir {
    $folder = $script:Settings.TargetDir
    if ($folder -and (Test-Path -LiteralPath $folder)) { $folder } else { $script:OutDir }
}

Import-Settings   # beim Durchspielen mit -Snapshot liegt die Datei im Bildordner und fehlt normalerweise
# Neues Aussehen (Oktober 2026): jede Installation wechselt einmal auf Nacht Puls; danach gilt wieder die eigene Wahl
if ([int]$script:Settings.LookVersion -lt 1) {
    $script:Settings.Skin = 'NachtPuls'
    $script:Settings.Theme = 'Nachtblau'
    $script:Settings.LookVersion = 1
    if (-not $Snapshot) { Save-Settings }
}
# Farbdesign und Ring hießen bis zum 17.10.2026 wie der Skin "Nacht Puls": gespeicherte Namen umstellen
if ([int]$script:Settings.LookVersion -lt 2) {
    if ($script:Settings.Theme -eq 'Nacht Puls') { $script:Settings.Theme = 'Nachtblau' }
    if ($script:Settings.Ring -eq 'Nacht Puls') { $script:Settings.Ring = 'Herzmonitor' }
    $script:Settings.LookVersion = 2
    if (-not $Snapshot) { Save-Settings }
}
# Neues Grunddesign (18.10.2026): jede Installation wechselt einmal auf Nacht-Bento; das bisherige heißt Klassisch
if ([int]$script:Settings.LookVersion -lt 3) {
    $script:Settings.Skin = 'Bento'
    $script:Settings.Theme = 'Lila-Nacht'
    $script:Settings.LookVersion = 3
    if (-not $Snapshot) { Save-Settings }
}
# Sprache: stellt T (Text übersetzen) und Convert-XamlLanguage bereit; bei Deutsch tun beide nichts
. (Get-AppCode 'PulsRig-Sprache.ps1')

# --- Design -------------------------------------------------------------------
# Alle Flächen stammen aus einer Farbfamilie (Nachtblau). Ein Design dreht deren Farbton und ändert die
# Sättigung; Akzent- und Meldungsfarben bleiben. Dazu verweist jede Farbe der Familie auf einen Eintrag
# in einem Farbverzeichnis, das beim Wechsel als Ganzes getauscht wird.

# Jedes Design bringt außerdem drei Akzentfarben (A), drei Gegenfarben für den Ring um SCAN (R) und die
# Schriftfarbe auf Akzentflächen mit. Light hellt die Flächen auf (Graphit) oder dunkelt sie ab.
$script:Themes = [ordered]@{
    'Graphit'     = @{ Hue = 220.0; Sat = 0.12; Light = 0.155; A = '#2DD4BF', '#22C55E', '#A3E635'; R = '#F0ABFC', '#D946EF', '#8B5CF6'; OnAccent = '#06231C' }
    'Mitternacht' = @{ Hue = 224.0; Sat = 1.0; Light = 0.0; A = '#22D3EE', '#6366F1', '#A855F7'; R = '#FDE047', '#FB923C', '#F43F5E'; OnAccent = '#FFFFFF' }
    'Neon-Nacht'  = @{ Hue = 272.0; Sat = 0.55; Light = -0.07; A = '#A855F7', '#EC4899', '#F43F5E'; R = '#A3E635', '#22D3EE', '#38BDF8'; OnAccent = '#FFFFFF' }
    'Smaragd'     = @{ Hue = 160.0; Sat = 0.9; Light = -0.035; A = '#10B981', '#34D399', '#FACC15'; R = '#F9A8D4', '#F472B6', '#A78BFA'; OnAccent = '#03140D' }
    'Tiefsee'     = @{ Hue = 207.0; Sat = 1.05; Light = -0.015; A = '#2DD4BF', '#38BDF8', '#818CF8'; R = '#FDBA74', '#FB923C', '#F43F5E'; OnAccent = '#FFFFFF' }
    'Aurora'      = @{ Hue = 226.0; Sat = 0.7; Light = -0.037; A = '#4ADE80', '#22D3EE', '#C084FC'; R = '#FDE047', '#FBBF24', '#FB7185'; OnAccent = '#04140D' }
}

# Zustand eines Designs; ein eigener Farbton dreht nur die Flächen und behält die Farben von Mitternacht
function New-ThemeState([string]$Name, [double]$Hue = 224.0) {
    if ($script:Themes.Contains($Name)) {
        $entry = $script:Themes[$Name]
        return @{ Name = $Name; Hue = $entry.Hue; Sat = $entry.Sat; Light = $entry.Light; A = $entry.A; R = $entry.R; OnAccent = $entry.OnAccent }
    }
    $base = $script:Themes['Mitternacht']
    @{ Name = 'Eigene'; Hue = $Hue; Sat = 0.95; Light = 0.0; A = $base.A; R = $base.R; OnAccent = $base.OnAccent }
}

$script:Theme = New-ThemeState 'Mitternacht'
$script:ThemeKeys = @{ Text = '#E8EEFC'; TextDim = '#93A3C7'; TextFaint = '#5E6E93'; Panel = '#131C33'; Stroke = '#223052' }
$script:ThemeDict = $null
# Farben in der Oberfläche, die für einen Akzent (A1-A3) oder eine Ringfarbe (R1-R3) stehen: geschrieben
# sind sie in den Farben von Mitternacht, angezeigt wird die entsprechende Farbe des gewählten Designs
$script:AccentMap = @{
    '22D3EE' = 'A1'; '6366F1' = 'A2'; 'A855F7' = 'A3'; '8B5CF6' = 'A3'; '3B82F6' = 'A2'
    'FDE047' = 'R1'; 'FB923C' = 'R2'; 'F43F5E' = 'R3'
}

# Farbton (0-360), Sättigung und Helligkeit (0-1)
function ConvertTo-Hsl([double]$Red, [double]$Green, [double]$Blue) {
    # Groß- und Kleinschreibung unterscheidet PowerShell bei Namen nicht - deshalb eigene Namen für die Anteile
    $r1 = $Red / 255.0; $g1 = $Green / 255.0; $b1 = $Blue / 255.0
    $max = [Math]::Max($r1, [Math]::Max($g1, $b1)); $min = [Math]::Min($r1, [Math]::Min($g1, $b1))
    $light = ($max + $min) / 2.0
    $delta = $max - $min
    if ($delta -lt 0.0001) { return @(0.0, 0.0, $light) }
    $sat = if ($light -gt 0.5) { $delta / (2.0 - $max - $min) } else { $delta / ($max + $min) }
    $hue = if ($max -eq $r1) { (($g1 - $b1) / $delta) % 6.0 } elseif ($max -eq $g1) { ($b1 - $r1) / $delta + 2.0 } else { ($r1 - $g1) / $delta + 4.0 }
    $hue *= 60.0
    if ($hue -lt 0.0) { $hue += 360.0 }
    @($hue, $sat, $light)
}

function ConvertFrom-Hsl([double]$Hue, [double]$Sat, [double]$Light, [byte]$Alpha = 255) {
    $Hue = (($Hue % 360.0) + 360.0) % 360.0
    $chroma = (1.0 - [Math]::Abs(2.0 * $Light - 1.0)) * $Sat
    $x = $chroma * (1.0 - [Math]::Abs((($Hue / 60.0) % 2.0) - 1.0))
    $m = $Light - $chroma / 2.0
    $rgb = switch ([int][Math]::Floor($Hue / 60.0)) {
        0 { @($chroma, $x, 0.0) } 1 { @($x, $chroma, 0.0) } 2 { @(0.0, $chroma, $x) }
        3 { @(0.0, $x, $chroma) } 4 { @($x, 0.0, $chroma) } default { @($chroma, 0.0, $x) }
    }
    [Windows.Media.Color]::FromArgb($Alpha, [byte][Math]::Round(($rgb[0] + $m) * 255.0), [byte][Math]::Round(($rgb[1] + $m) * 255.0), [byte][Math]::Round(($rgb[2] + $m) * 255.0))
}

# Gehört eine Farbe zur Familie der Flächen? Kräftige mittlere Töne sind Akzente und bleiben unberührt.
function Test-ThemeFamily([string]$Hex) {
    $color = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $hsl = ConvertTo-Hsl $color.R $color.G $color.B
    if ($hsl[0] -lt 200.0 -or $hsl[0] -gt 250.0 -or $hsl[1] -lt 0.12) { return $false }
    -not ($hsl[1] -gt 0.6 -and $hsl[2] -gt 0.4 -and $hsl[2] -lt 0.8)
}

function Get-ThemeColor([string]$Hex) {
    # "@A1/66" = erste Akzentfarbe mit Deckkraft 66 (hex), "@R2/FF" = zweite Ringfarbe
    if ($Hex.StartsWith('@')) {
        $set = if ($Hex[1] -eq 'R') { $script:Theme.R } else { $script:Theme.A }
        $color = [Windows.Media.ColorConverter]::ConvertFromString($set[[int]"$($Hex[2])" - 1])
        return [Windows.Media.Color]::FromArgb([Convert]::ToByte($Hex.Substring(4, 2), 16), $color.R, $color.G, $color.B)
    }
    $color = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $hsl = ConvertTo-Hsl $color.R $color.G $color.B
    $sat = $hsl[1] * $script:Theme.Sat
    if ($sat -gt 1.0) { $sat = 1.0 }
    # dunkle Flächen verschieben sich stark, helle Schrift kaum
    $light = $hsl[2] + $script:Theme.Light * (1.0 - $hsl[2]) * (1.0 - $hsl[2])
    if ($light -lt 0.012) { $light = 0.012 }
    ConvertFrom-Hsl ($script:Theme.Hue + $hsl[0] - 224.0) $sat $light $color.A
}

function Add-ThemeEntry($Dictionary, [string]$Key) {
    $color = Get-ThemeColor $script:ThemeKeys[$Key]
    if ($Key.StartsWith('K_')) { $Dictionary.Add($Key, $color) }
    else {
        $brush = New-Object Windows.Media.SolidColorBrush $color
        $brush.Freeze()
        $Dictionary.Add($Key, $brush.PSObject.BaseObject)
    }
}

# Schlüssel im Farbverzeichnis für eine Farbe der Familie; legt ihn bei Bedarf an
function Get-ThemeKey([string]$Hex, [switch]$AsColor) {
    $key = $(if ($AsColor) { 'K_' } else { 'C_' }) + $Hex.TrimStart('#').ToUpper()
    if (-not $script:ThemeKeys.ContainsKey($key)) {
        $script:ThemeKeys[$key] = $Hex
        if ($script:ThemeDict) { Add-ThemeEntry $script:ThemeDict $key }
    }
    $key
}

$script:ThemeEvaluator = [Text.RegularExpressions.MatchEvaluator] {
    param($match)
    $hex = $match.Groups['hex'].Value
    $attribute = $match.Groups['attr'].Value
    $role = $script:AccentMap[$hex.Substring($hex.Length - 6).ToUpper()]
    if ($role) {
        $alpha = if ($hex.Length -eq 9) { $hex.Substring(1, 2).ToUpper() } else { 'FF' }
        $key = $(if ($attribute -eq 'Color') { 'K_' } else { 'C_' }) + $role + '_' + $alpha
        if (-not $script:ThemeKeys.ContainsKey($key)) {
            $script:ThemeKeys[$key] = '@' + $role + '/' + $alpha
            if ($script:ThemeDict) { Add-ThemeEntry $script:ThemeDict $key }
        }
        return '{0}="{{DynamicResource {1}}}"' -f $attribute, $key
    }
    if (-not (Test-ThemeFamily $hex)) { return $match.Value }
    '{0}="{{DynamicResource {1}}}"' -f $attribute, (Get-ThemeKey $hex -AsColor:($attribute -eq 'Color'))
}

# Ersetzt in einem XAML-Text jede Farbe der Familie durch einen Verweis ins Farbverzeichnis
function ConvertTo-ThemedXaml([string]$Text) {
    $Text = Convert-XamlLanguage $Text
    if (Get-Command ConvertTo-SkinXaml -ErrorAction SilentlyContinue) { $Text = ConvertTo-SkinXaml $Text }
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '<SolidColorBrush x:Key=') { continue }   # die Grundfarben selbst kommen aus dem Verzeichnis
        $line = [regex]::Replace($lines[$i], '\{StaticResource (Text|TextDim|TextFaint|Panel|Stroke|Accent|AccentGrad|RingGrad|Ring1|Ring2|Ring3|OnAccent)\}', '{DynamicResource $1}')
        $lines[$i] = [regex]::Replace($line, '(?<attr>[\w\.:]+)="(?<hex>#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}))"', $script:ThemeEvaluator)
    }
    $lines -join "`n"
}

# Skins: legt den gewählten Skin fest und schreibt jede Vorlage auf ihn um, bevor Oberfläche daraus wird
. (Get-AppCode 'PulsRig-Skins.ps1')

# --- Fenster laden ------------------------------------------------------------

$xamlText = ConvertTo-ThemedXaml (Get-AppText 'PulsRig.xaml')
$window = [Windows.Markup.XamlReader]::Parse($xamlText)
# die Grundfarben, den Akzent und den Verlauf liefert ab jetzt das Farbverzeichnis
foreach ($key in 'Text', 'TextDim', 'TextFaint', 'Panel', 'Stroke', 'Accent', 'AccentGrad') { $window.Resources.Remove($key) }

# Verlauf aus drei Farben, schräg von links oben nach rechts unten
function New-ThemeGradient([string[]]$Hex) {
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point 0, 0
    $brush.EndPoint = New-Object Windows.Point 1, 1
    $offsets = 0.0, 0.55, 1.0
    for ($i = 0; $i -lt 3; $i++) {
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($Hex[$i])), $offsets[$i]))
    }
    $brush.Freeze()
    $brush.PSObject.BaseObject
}

function New-SolidBrush([string]$Hex) {
    $brush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $brush.Freeze()
    $brush.PSObject.BaseObject
}

function Update-ThemeDictionary {
    $dictionary = New-Object Windows.ResourceDictionary
    foreach ($key in @($script:ThemeKeys.Keys)) { Add-ThemeEntry $dictionary $key }
    $dictionary.Add('Accent', (New-SolidBrush $script:Theme.A[0]))
    $dictionary.Add('AccentGrad', (New-ThemeGradient $script:Theme.A))
    $dictionary.Add('RingGrad', (New-ThemeGradient $script:Theme.R))
    for ($i = 0; $i -lt 3; $i++) { $dictionary.Add("Ring$($i + 1)", (New-SolidBrush $script:Theme.R[$i])) }
    $dictionary.Add('OnAccent', (New-SolidBrush $script:Theme.OnAccent))
    if ($window.Resources.MergedDictionaries.Count -eq 0) { $window.Resources.MergedDictionaries.Add($dictionary) }
    else { $window.Resources.MergedDictionaries[0] = $dictionary }
    $script:ThemeDict = $dictionary
}

if ($script:Themes.Contains($script:Settings.Theme)) { $script:Theme = New-ThemeState $script:Settings.Theme }
elseif ($script:Settings.Theme -eq 'Eigene') { $script:Theme = New-ThemeState 'Eigene' ([double]$script:Settings.ThemeHue) }
Update-ThemeDictionary

# Verknüpft eine Eigenschaft mit einem Eintrag des Farbverzeichnisses, damit sie dem Design folgt
function Set-Paint($Element, [string]$Property, [string]$Key) {
    $field = $Element.GetType().GetField("${Property}Property", [Reflection.BindingFlags]'Public, Static, FlattenHierarchy')
    $Element.SetResourceReference($field.GetValue($null), $Key)
}

$ui = @{}
foreach ($match in [regex]::Matches($xamlText, 'x:Name="(\w+)"')) {
    $name = $match.Groups[1].Value
    $element = $window.FindName($name)
    if ($element) { $ui[$name] = $element }
}

# Fenstersymbol für Taskleiste und Alt+Tab: das Logo, hier aus denselben Formen gezeichnet
function New-AppIcon {
    $visual = New-Object Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $gradient = $window.FindResource('AccentGrad')
    $white = New-Object Windows.Media.Pen ([Windows.Media.Brushes]::White), 4.5
    $white.StartLineCap = 'Round'; $white.EndLineCap = 'Round'; $white.LineJoin = 'Round'
    $cyan = New-Object Windows.Media.Pen (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(34, 211, 238))), 5.5
    $cyan.StartLineCap = 'Round'; $cyan.EndLineCap = 'Round'
    $context.DrawEllipse((New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(12, 19, 38))), (New-Object Windows.Media.Pen $gradient, 5), (New-Object Windows.Point 32, 32), 28, 28)
    # Pulslinie mit Punkt am Ende
    $context.DrawGeometry($null, $white, [Windows.Media.Geometry]::Parse('M 15,32 L 23,32 L 27,24 L 32,43 L 37,18 L 41,32 L 45,32'))
    $context.DrawEllipse($cyan.Brush, $null, (New-Object Windows.Point 51, 32), 3, 3)
    $context.Close()
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap 64, 64, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $bitmap
}
try { $window.Icon = New-AppIcon } catch { }

function Get-Brush([string]$Key) { $window.FindResource($Key) }
function New-Brush([string]$Hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($Hex) }
function Get-Glyph([int]$Code) { [string][char]$Code }

# --- Hintergrund-Arbeitsbereich -----------------------------------------------
# Die Skripte laufen in einem eigenen Arbeitsbereich. Alles, was sie ausgeben oder fragen,
# kommt als Nachricht in eine Warteschlange, die das Fenster regelmäßig leert.

$sync = [hashtable]::Synchronized(@{})
$sync.Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$sync.Reply = $null
$sync.ReplyEvent = New-Object System.Threading.AutoResetEvent $false

$runspace = [runspacefactory]::CreateRunspace()
$runspace.ApartmentState = 'STA'
$runspace.ThreadOptions = 'ReuseThread'
$runspace.Open()
$runspace.SessionStateProxy.SetVariable('sync', $sync)

$workerInit = Get-AppText 'PulsRig-Arbeit-Start.ps1'
# Probelauf auf einem vorgetäuschten fremden System (siehe PulsRig-Fremdsystem.ps1): gilt im Fenster und im Arbeitsbereich
$foreignPath = Join-Path $script:Root 'PulsRig-Fremdsystem.ps1'
if ($Snapshot -and $env:PULSRIG_FREMD -and (Test-Path -LiteralPath $foreignPath)) {
    . $foreignPath
    $script:ForeignCode = [IO.File]::ReadAllText($foreignPath, [Text.Encoding]::UTF8)
    $workerInit += "`n" + [IO.File]::ReadAllText($foreignPath, [Text.Encoding]::UTF8)
}

$jobWrapper = @'
param($ddJob, $ddCode, $ddArgument)
try {
    $ddResult = & ([scriptblock]::Create($ddCode)) $ddArgument
    $sync.Queue.Enqueue(@{ Type = 'done'; Job = $ddJob; Result = $ddResult })
}
catch {
    $sync.Queue.Enqueue(@{ Type = 'done'; Job = $ddJob; Error = $_.Exception.Message })
}
'@

$scanCode = Get-AppText 'PulsRig-Arbeit-Scan.ps1'

$updateCode = Get-AppText 'PulsRig-Arbeit-Update.ps1'

$toolCode = Get-AppText 'PulsRig-Arbeit-Werkzeug.ps1'

# sichert das Treiberpaket eines einzelnen Geräts (geht ohne Adminrechte)
$exportCode = Get-AppText 'PulsRig-Arbeit-Export.ps1'

# Abfragen für die Dialoge: laufen im Arbeitsbereich und liefern nur Daten zurück
$script:Queries = @{
    Boost   = 'param($a) @{ Choices = Get-BoostChoices; Games = @(Get-KnownGames) }'
    Runtime = 'param($a) @{ Components = @(Get-RuntimeStatus); Files = @(Get-RuntimeFiles) }'
    System  = 'param($a) @{ Rows = @(Get-SystemInfoData) }'
    History = 'param($a) Get-DriverHistory'
}

$script:CurrentPs = $null
$script:CurrentHandle = $null
$script:WorkerReady = $false

function Test-WorkerBusy {
    $script:CurrentHandle -and -not $script:CurrentHandle.IsCompleted
}

function Start-WorkerJob([string]$Name, [string]$Code, $Argument) {
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($jobWrapper).AddArgument($Name).AddArgument($Code).AddArgument($Argument)
    $script:CurrentPs = $ps
    $script:CurrentHandle = $ps.BeginInvoke()
}

function Stop-WorkerJob {
    # eine wartende Rückfrage zuerst beantworten, sonst hängt der Arbeitsbereich
    $sync.Reply = $false
    [void]$sync.ReplyEvent.Set()
    if (Test-WorkerBusy) {
        try { [void]$script:CurrentPs.BeginStop($null, $null) } catch { }
    }
    $drop = $null
    while ($sync.Queue.TryDequeue([ref]$drop)) { }
}

$initPs = [powershell]::Create()
$initPs.Runspace = $runspace
# stecken die Dateien in PulsRig.exe, bekommt der Arbeitsbereich die beiden Skripte als Text statt als Pfad
[void]$initPs.AddScript($workerInit).AddArgument($script:Backend).AddArgument($script:OutDir)
if ($script:Files) { [void]$initPs.AddArgument((Get-AppText 'Treiber-Scan.ps1')).AddArgument((Get-AppText 'Treiber-Werkzeuge.ps1')) }
$script:CurrentPs = $initPs
$script:CurrentHandle = $initPs.BeginInvoke()

# --- Animationen --------------------------------------------------------------

$script:EaseOut = New-Object Windows.Media.Animation.CubicEase
$script:EaseOut.EasingMode = 'EaseOut'
$script:EaseInOut = New-Object Windows.Media.Animation.CubicEase
$script:EaseInOut.EasingMode = 'EaseInOut'
$script:EaseBack = New-Object Windows.Media.Animation.BackEase
$script:EaseBack.EasingMode = 'EaseOut'
$script:EaseBack.Amplitude = 0.5
$script:EaseElastic = New-Object Windows.Media.Animation.ElasticEase
$script:EaseElastic.EasingMode = 'EaseOut'
$script:EaseElastic.Oscillations = 2
$script:EaseElastic.Springiness = 5
$script:EaseSine = New-Object Windows.Media.Animation.SineEase
$script:EaseSine.EasingMode = 'EaseInOut'
# der Skin bestimmt den Charakter der Bewegungen: ruhig (nichts federt) oder zackig (hart abbremsen)
if ($script:Skin.Calm) { $script:EaseBack = $script:EaseOut; $script:EaseElastic = $script:EaseOut }
if ($script:Skin.Snappy) {
    $script:EaseOut = New-Object Windows.Media.Animation.QuinticEase
    $script:EaseOut.EasingMode = 'EaseOut'
}

$P = @{
    Opacity = [Windows.UIElement]::OpacityProperty
    Angle   = [Windows.Media.RotateTransform]::AngleProperty
    ScaleX  = [Windows.Media.ScaleTransform]::ScaleXProperty
    ScaleY  = [Windows.Media.ScaleTransform]::ScaleYProperty
    X       = [Windows.Media.TranslateTransform]::XProperty
    Y       = [Windows.Media.TranslateTransform]::YProperty
    Dash    = [Windows.Shapes.Shape]::StrokeDashOffsetProperty
}

function New-DoubleAnim {
    param($To, [int]$Ms = 300, $From = $null, [int]$Delay = 0, $Ease = $script:EaseOut, [switch]$Linear, [switch]$Forever, [switch]$AutoReverse)
    # Animationen abgeschaltet: Übergänge springen sofort ans Ziel; Laufanzeigen bleiben, sie zeigen Arbeit an
    if (-not $script:Settings.Animations -and -not $Forever) { $Ms = 1; $Delay = 0 }
    elseif (-not $Forever -and $script:SkinSpeed -ne 1.0) { $Ms = [int]($Ms * $script:SkinSpeed); $Delay = [int]($Delay * $script:SkinSpeed) }
    $animation = New-Object Windows.Media.Animation.DoubleAnimation
    if ($null -ne $From) { $animation.From = [double]$From }
    $animation.To = [double]$To
    $animation.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    if ($Delay -gt 0) { $animation.BeginTime = [TimeSpan]::FromMilliseconds($Delay) }
    if (-not $Linear -and $Ease) { $animation.EasingFunction = $Ease }
    if ($Forever) { $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever }
    if ($AutoReverse) { $animation.AutoReverse = $true }
    $animation
}

function Start-Fade($Element, [double]$To, [int]$Ms = 250, [int]$Delay = 0, $From = $null) {
    $Element.BeginAnimation($P.Opacity, (New-DoubleAnim -To $To -Ms $Ms -Delay $Delay -From $From))
}

function Start-Scale($Element, [double]$To, [int]$Ms = 250, [int]$Delay = 0, $From = $null, $Ease = $script:EaseOut) {
    $transform = $Element.RenderTransform
    $transform.BeginAnimation($P.ScaleX, (New-DoubleAnim -To $To -Ms $Ms -Delay $Delay -From $From -Ease $Ease))
    $transform.BeginAnimation($P.ScaleY, (New-DoubleAnim -To $To -Ms $Ms -Delay $Delay -From $From -Ease $Ease))
}

function Start-Slide($Element, [double]$To, [int]$Ms = 300, [int]$Delay = 0, $From = $null, $Ease = $script:EaseOut) {
    $Element.RenderTransform.BeginAnimation($P.Y, (New-DoubleAnim -To $To -Ms $Ms -Delay $Delay -From $From -Ease $Ease))
}

# Dreht gleichmäßig weiter, ausgehend vom aktuellen Winkel - so ruckt nichts beim Tempowechsel
function Start-Spin($Element, [double]$Seconds, [int]$Direction = 1) {
    $transform = $Element.RenderTransform
    $from = $transform.Angle
    $transform.BeginAnimation($P.Angle, (New-DoubleAnim -From $from -To ($from + 360 * $Direction) -Ms ($Seconds * 1000) -Linear -Forever))
}

function Invoke-Later([int]$Ms, [scriptblock]$Action, $Argument) {
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($Ms)
    $timer.Tag = @{ Action = $Action; Argument = $Argument }
    $timer.Add_Tick({
            $this.Stop()
            try { & $this.Tag.Action $this.Tag.Argument } catch { Write-AppError $_ }
        })
    $timer.Start()
}

# Farbe entlang des Ringverlaufs des Designs (0..1)
function Get-GradColor([double]$T) {
    $stops = @($script:Theme.R | ForEach-Object { $c = [Windows.Media.ColorConverter]::ConvertFromString($_); , @($c.R, $c.G, $c.B) })
    $scaled = $T * 2.0
    if ($scaled -lt 0.0) { $scaled = 0.0 }
    if ($scaled -gt 1.999) { $scaled = 1.999 }
    $index = [int][Math]::Floor($scaled)
    $part = $scaled - $index
    $a = $stops[$index]; $b = $stops[$index + 1]
    [Windows.Media.Color]::FromRgb([byte]($a[0] + ($b[0] - $a[0]) * $part), [byte]($a[1] + ($b[1] - $a[1]) * $part), [byte]($a[2] + ($b[2] - $a[2]) * $part))
}

# --- Scan-Knopf ---------------------------------------------------------------

$script:TickOffKey = Get-ThemeKey '#24325A'
$script:Ticks = @()
$script:TickBrushes = @()
$script:TicksLit = 0
$tickCount = 72
for ($i = 0; $i -lt $tickCount; $i++) {
    $tick = New-Object Windows.Shapes.Rectangle
    $tick.Width = 2.5; $tick.Height = 9; $tick.RadiusX = 1.25; $tick.RadiusY = 1.25
    Set-Paint $tick 'Fill' $script:TickOffKey
    [Windows.Controls.Canvas]::SetLeft($tick, 148.75)
    [Windows.Controls.Canvas]::SetTop($tick, 4)
    $tick.RenderTransform = New-Object Windows.Media.RotateTransform ($i * 360 / $tickCount), 1.25, 146
    [void]$ui.OrbTicks.Children.Add($tick)
    $script:Ticks += $tick
}

# Die Leuchtfarben der Striche folgen dem Ringverlauf des Designs
function Update-TickBrushes {
    $count = $script:Ticks.Count
    $script:TickBrushes = @(for ($i = 0; $i -lt $count; $i++) { New-Object Windows.Media.SolidColorBrush (Get-GradColor ($i / ($count - 1))) })
    for ($i = 0; $i -lt $script:TicksLit; $i++) { $script:Ticks[$i].Fill = $script:TickBrushes[$i] }
}
Update-TickBrushes

function Set-OrbProgress([double]$Fraction) {
    # ausdrücklich mit Kommazahlen rechnen: mit ganzen Zahlen als Grenzen rundet PowerShell den Wert auf 0 oder 1
    if ($Fraction -lt 0.0) { $Fraction = 0.0 }
    if ($Fraction -gt 1.0) { $Fraction = 1.0 }
    $lit = [int][Math]::Round($Fraction * $script:Ticks.Count)
    if ($lit -gt $script:TicksLit) {
        for ($i = $script:TicksLit; $i -lt $lit; $i++) { $script:Ticks[$i].Fill = $script:TickBrushes[$i] }
    }
    elseif ($lit -lt $script:TicksLit) {
        for ($i = $lit; $i -lt $script:TicksLit; $i++) { Set-Paint $script:Ticks[$i] 'Fill' $script:TickOffKey }
    }
    $script:TicksLit = $lit
    $ui.OrbProgress.StrokeDashOffset = 155.2 * (1 - $Fraction)
}

# --- Ring-Animationen um den Scan-Knopf: neun wählbare Stile -------------------
. (Get-AppCode 'PulsRig-Ringe.ps1')

# Wechselt die Beschriftung im Knopf: der Inhalt springt kurz auf, damit der Wechsel nicht hart umschaltet
function Start-OrbSwap {
    $content = $ui.OrbLabel.Parent
    if ($content.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
        $content.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $content.RenderTransform = New-Object Windows.Media.ScaleTransform
    }
    Start-Fade $content 1 280 0 0.1
    Start-Scale $content 1 460 0 0.84 $script:EaseBack
}

# Zeile unter dem großen Wort im Knopf; ein neuer Text gleitet von unten herein
function Set-OrbSub([string]$Text) {
    if ($ui.OrbSub.Text -eq $Text) { return }
    $ui.OrbSub.Text = $Text
    if ($ui.OrbSub.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $ui.OrbSub.RenderTransform = New-Object Windows.Media.TranslateTransform }
    Start-Fade $ui.OrbSub 1 280 0 0
    Start-Slide $ui.OrbSub 0 360 0 6
}

# Die kleine Pulslinie über "SCAN": zeichnet sich von links nach rechts und schlägt dann einmal
$script:OrbPulse = $ui.OrbIcon.Child.Children[0]
$script:OrbPulse.StrokeDashArray = New-Object Windows.Media.DoubleCollection
$script:OrbPulse.StrokeDashArray.Add(34); $script:OrbPulse.StrokeDashArray.Add(34)
$ui.OrbIcon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
$ui.OrbIcon.RenderTransform = New-Object Windows.Media.ScaleTransform
function Start-OrbBeat([int]$Delay = 0) {
    if (-not $script:Settings.Animations) { return }
    $kick = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $kick.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(620))
    $kick.BeginTime = [TimeSpan]::FromMilliseconds($Delay)
    foreach ($frame in @(0.0, 1.0), @(0.16, 1.22), @(0.36, 1.0), @(0.5, 1.1), @(0.72, 1.0), @(1.0, 1.0)) {
        [void]$kick.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))))
    }
    $ui.OrbIcon.RenderTransform.BeginAnimation($P.ScaleX, $kick)
    $ui.OrbIcon.RenderTransform.BeginAnimation($P.ScaleY, $kick)
}
function Start-OrbPulseDraw {
    $script:OrbPulse.BeginAnimation($P.Dash, (New-DoubleAnim -From 34 -To 0 -Ms 620 -Ease $script:EaseInOut))
    Start-OrbBeat 640
}

function Set-OrbIdle {
    Set-SkinMotion $true
    Start-Fade $ui.OrbProgress 0 300
    Start-Fade $ui.OrbTicks 0 300
    Start-Fade $ui.RingLayer 1 400
    # kommt der Knopf aus einem Scan zurück, springt "SCAN" auf und die Pulslinie zeichnet sich neu
    if ($ui.OrbLabel.Text -ne 'SCAN') {
        Start-OrbSwap
        Start-OrbPulseDraw
    }
    $ui.OrbLabel.Text = 'SCAN'
    $ui.OrbIcon.Visibility = 'Visible'
    if (-not $script:Settings.Animations) {
        # ohne Animationen steht der Ring still
        Show-RingStyle -Still
        $ui.OrbGlow.BeginAnimation($P.Opacity, $null)
        $ui.OrbGlow.Opacity = 0.5
        return
    }
    # läuft der Ring schon (Ende eines Scans), fährt er nur aufs ruhige Tempo zurück statt neu anzusetzen
    if ($script:RingRunning) { Set-RingSpeed 1 }
    else {
        Set-RingSpeed 1
        Show-RingStyle
    }
    $ui.OrbGlow.BeginAnimation($P.Opacity, (New-DoubleAnim -From 0.38 -To 0.62 -Ms 2600 -Ease $script:EaseSine -Forever -AutoReverse))
}

# Im Hintergrund ruhen die Daueranimationen - das Fenster kostet dann keine Rechenzeit
function Suspend-OrbIdle {
    Set-SkinMotion $false
    Suspend-RingStyle
    $ui.OrbGlow.BeginAnimation($P.Opacity, $null)
}

# Beim Scannen läuft allein die gewählte Ring-Animation weiter, nur zügiger; den Stand zeigt die Prozentzahl im Knopf
function Set-OrbScanning {
    Set-SkinMotion $false   # beim Scannen bewegt sich allein der Ring
    if (-not $script:RingRunning -and $script:Settings.Animations) { Show-RingStyle }
    Set-RingSpeed 1.5
    Start-Fade $ui.RingLayer 1 300
    $ui.OrbGlow.BeginAnimation($P.Opacity, (New-DoubleAnim -From 0.6 -To 0.95 -Ms 900 -Ease $script:EaseSine -Forever -AutoReverse))
    Start-Fade $ui.OrbTicks 0 300
    Start-Fade $ui.OrbProgress 0 300
    # beim Scan steht die Prozentzahl groß im Knopf, darunter der Hinweis zum Stoppen
    Start-OrbSwap
    $ui.OrbLabel.Text = '0 %'
    $ui.OrbIcon.Visibility = 'Collapsed'
}

# Wechselt den Text der Statusanzeige: der neue gleitet von unten herein
function Set-StatusText([string]$Text) {
    $Text = T $Text
    if ($ui.StatusText.Text -eq $Text) { return }
    $ui.StatusText.Text = $Text
    if ($ui.StatusText.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $ui.StatusText.RenderTransform = New-Object Windows.Media.TranslateTransform }
    Start-Fade $ui.StatusText 1 260 0 0
    Start-Slide $ui.StatusText 0 340 0 8
}

# $Glyph: eigenes Symbol; sonst eines je Zustand. Mit -Pulse dreht es sich (ein Scan läuft).
function Set-Status([string]$Text, [string]$Kind = 'Accent', [switch]$Pulse, [int]$Glyph) {
    Set-StatusText $Text
    Set-Paint $ui.StatusDot 'Fill' $Kind
    Set-Paint $ui.StatusGlyph 'Foreground' $Kind
    Set-Paint $ui.StatusEdge 'BorderBrush' $Kind
    if (-not $Glyph) {
        $Glyph = if ($Pulse) { 0xE895 } else { switch ($Kind) { 'Good' { 0xE73E } 'Warn' { 0xE7BA } 'Bad' { 0xE783 } default { 0xE768 } } }
    }
    $ui.StatusGlyph.Text = Get-Glyph $Glyph
    $spin = $ui.StatusGlyph.RenderTransform
    if ($Pulse) {
        $ui.StatusIcon.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.45 -Ms 700 -Ease $script:EaseSine -Forever -AutoReverse))
        if ($script:Settings.Animations) { Start-Spin $ui.StatusGlyph 1.8 }
    }
    else {
        $ui.StatusIcon.BeginAnimation($P.Opacity, $null)
        $ui.StatusIcon.Opacity = 1
        $spin.BeginAnimation($P.Angle, $null)
        $spin.Angle = 0
    }
    # der Pfeil zeigt, dass ein Klick zu den Ergebnissen führt
    $toResults = [bool]$script:LastResult -and -not $Pulse -and $script:Busy -ne 'scan'
    # der Pfeil rückt von links nach, wenn er neu erscheint
    if ($ui.StatusArrow.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $ui.StatusArrow.RenderTransform = New-Object Windows.Media.TranslateTransform }
    if ($toResults -and $ui.StatusArrow.Visibility -ne 'Visible') {
        $ui.StatusArrow.BeginAnimation($P.Opacity, $null)
        $ui.StatusArrow.Opacity = 0
        Start-Fade $ui.StatusArrow 1 300 200
        $ui.StatusArrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -8 -To 0 -Ms 420 -Delay 200))
    }
    $ui.StatusArrow.Visibility = if ($toResults) { 'Visible' } else { 'Collapsed' }
    $ui.StatusPill.Cursor = if ($toResults) { 'Hand' } else { 'Arrow' }
    # wechselt der Zustand, federt das Symbol auf und der farbige Rand leuchtet kurz nach
    $state = "$Kind|$([bool]$Pulse)|$Glyph"
    if ($state -ne $script:StatusState) {
        $script:StatusState = $state
        if ($ui.StatusIcon.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
            $ui.StatusIcon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $ui.StatusIcon.RenderTransform = New-Object Windows.Media.ScaleTransform
        }
        Start-Scale $ui.StatusIcon 1 560 0 0.4 $script:EaseElastic
        Start-Fade $ui.StatusEdge 0.45 900 0 1
    }
}

function Show-Badge($Badge, $Label, [int]$Count) {
    if ($Count -le 0) {
        $Badge.Visibility = 'Collapsed'
        return
    }
    $Label.Text = "$Count"
    $Badge.Visibility = 'Visible'
    Start-Scale $Badge 1 420 0 0 $script:EaseElastic
}

# --- Scan-Ablauf --------------------------------------------------------------

$script:Busy = $null          # 'scan', 'update', 'tool' oder nichts
$script:ShownPercent = 0.0
$script:TargetPercent = 0.0
$script:StageFrom = 0.0
$script:StageTo = 0.0
$script:LastResult = $null

$demoResult = @{
    Devices     = 188
    ThirdParty  = 42
    SearchError = $null
    Problems    = @(@{ Name = 'USB-Massenspeichergerät'; Code = 43; Text = 'Gerät hat einen Fehler gemeldet'; Advice = 'Treiber erneuern' },
        @{ Name = 'SM-Bus-Controller'; Code = 28; Text = 'kein Treiber installiert'; Advice = 'Treiber erneuern'; Id = 'PCI\VEN_8086&DEV_7A23'; Chipset = $true; Catalog = '10.1.46.5' })
    Board       = @{ Name = 'ASRock AB350 Pro4'; Url = 'https://www.bing.com/search?q=ASRock%20AB350%20Pro4%20Chipsatz%20Treiber%20Download' }
    Updates     = @(
        @{ Id = 'a'; Name = 'Realtek – Netzwerk – 10.81.12.0'; Title = 'Realtek - Net - 10.81.12.0'; Class = 'Net'; Installed = '10.80.50.407 vom 07.04.2026'; NewDate = '02.10.2026'; Size = '5,8 MB'; Optional = $false; Firmware = $false },
        @{ Id = 'b'; Name = 'Realtek Semiconductor Corp. – Audio – 6.0.10029.1'; Title = 'Realtek Semiconductor Corp. - MEDIA - 6.0.10029.1'; Class = 'MEDIA'; Installed = '6.0.9977.1 vom 14.04.2026'; NewDate = '10.08.2026'; Size = '12,7 MB'; Optional = $true; Firmware = $false },
        @{ Id = 'c'; Name = 'ASRock – Firmware – 10.60'; Device = 'Systemfirmware'; Title = 'ASRock - Firmware - 10.60'; Class = 'Firmware'; Installed = ''; NewDate = '21.09.2026'; Size = '9,1 MB'; Optional = $false; Firmware = $true }
    )
    Nvidia      = @{ Gpu = 'NVIDIA GeForce RTX 3080'; Kind = 'Game Ready'; Installed = '617.42'; Latest = '620.15'; Released = '08.10.2026'; Size = '992 MB'; IsNewer = $true }
    Amd         = @{ Chipset = 'B550'; Cpu = 'AMD Ryzen 7 5800X3D 8-Core Processor'; Installed = '8.08.12.551'; Latest = '8.08.12.551'; Released = '14.08.2026'; Size = '79 MB'; Url = 'https://www.amd.com/de/support/download/drivers.html'; IsNewer = $false }
    RadeonDriver = @{ Gpu = 'AMD Radeon RX 7800 XT'; Installed = '26.9.2'; Latest = '26.10.1'; Released = '20.10.2026'; Url = 'https://www.amd.com/de/support/downloads/drivers.html/graphics/radeon-rx/radeon-rx-7000-series/amd-radeon-rx-7800-xt.html'; IsNewer = $true }
    Hints       = @(@{ Title = 'Advanced Micro Devices, Inc System Driver Update (2.0.0.29)'; Date = '07.07.2026'; Size = '17 KB'; Device = 'AMD SMBUS, AMD GPIO Controller, AMD PSP 11.0 Device'; Installed = '2.0.0.26 vom 04.12.2025'; Url = 'https://www.catalog.update.microsoft.com/'; NoCode = $true })
    Runtimes    = @(@{ Name = 'OpenAL'; Status = 'fehlt'; CanInstall = $false }, @{ Name = 'Visual C++ 2013 (x64)'; Status = 'veraltet'; CanInstall = $true })
    Drivers     = @(
        @{ Name = 'NVIDIA GeForce RTX 3080'; Class = 'Display'; Version = '32.0.16.1742'; Date = '30.09.2026'; Provider = 'NVIDIA'; Inf = 'oem41.inf'; HardwareId = 'PCI\VEN_10DE&DEV_2206'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = 'https://www.catalog.update.microsoft.com/' },
        @{ Name = 'Realtek PCIe GbE Family Controller'; Class = 'Net'; Version = '10.80.50.407'; Date = '07.04.2026'; Provider = 'Realtek'; Inf = 'oem12.inf'; HardwareId = 'PCI\VEN_10EC&DEV_8168'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = 'https://www.catalog.update.microsoft.com/' },
        @{ Name = 'Realtek High Definition Audio'; Class = 'MEDIA'; Version = '6.0.9977.1'; Date = '14.04.2026'; Provider = 'Realtek Semiconductor Corp.'; Inf = 'oem7.inf'; HardwareId = 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0892'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = '' },
        @{ Name = 'AMD GPIO Controller'; Class = 'System'; Version = '2.2.0.134'; Date = '10.11.2025'; Provider = 'Advanced Micro Devices, Inc'; Inf = 'oem3.inf'; HardwareId = 'ACPI\AMDI0030'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 2; ThirdParty = $true; Catalog = '' },
        @{ Name = 'AMD SMBUS'; Class = 'System'; Version = '2.0.0.26'; Date = '04.12.2025'; Provider = 'Advanced Micro Devices, Inc'; Inf = 'oem5.inf'; HardwareId = 'PCI\VEN_1022&DEV_790B'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = '' },
        @{ Name = 'Intel(R) SMBus - 7A23'; Class = 'System'; Version = '10.1.46.5'; Date = '18.07.1968'; Provider = 'INTEL'; Inf = 'oem49.inf'; HardwareId = 'PCI\VEN_8086&DEV_7A23'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = '' },
        @{ Name = 'Razer Ornata V3 Tenkeyless'; Class = 'Keyboard'; Version = '6.2.9200.16545'; Date = '12.07.2024'; Provider = 'Razer Inc'; Inf = 'oem22.inf'; HardwareId = 'HID\VID_1532&PID_02A3'; Signer = 'Microsoft Windows Hardware Compatibility Publisher'; Count = 1; ThirdParty = $true; Catalog = '' },
        @{ Name = 'PCI Standard-Host-CPU-Brücke'; Class = 'System'; Version = '10.0.26300.1'; Date = '21.06.2006'; Provider = 'Microsoft'; Inf = 'machine.inf'; HardwareId = 'PCI\VEN_1022&DEV_1440'; Signer = 'Microsoft Windows'; Count = 18; ThirdParty = $false; Catalog = '' },
        @{ Name = 'USB-Root-Hub (USB 3.0)'; Class = 'USB'; Version = '10.0.26300.1'; Date = '17.09.2026'; Provider = 'Microsoft'; Inf = 'usbhub3.inf'; HardwareId = 'USB\ROOT_HUB30'; Signer = 'Microsoft Windows'; Count = 2; ThirdParty = $false; Catalog = '' },
        @{ Name = 'USB-Verbundgerät'; Class = 'USB'; Version = '10.0.26300.1'; Date = '21.06.2006'; Provider = 'Microsoft'; Inf = 'usb.inf'; HardwareId = 'USB\COMPOSITE'; Signer = 'Microsoft Windows'; Count = 5; ThirdParty = $false; Catalog = '' },
        @{ Name = 'WDC WD10EARS-00Y5B1'; Class = 'DiskDrive'; Version = '10.0.26300.1'; Date = '21.06.2006'; Provider = 'Microsoft'; Inf = 'disk.inf'; HardwareId = 'SCSI\DiskWDC_____WD10EARS'; Signer = 'Microsoft Windows'; Count = 1; ThirdParty = $false; Catalog = '' }
    )
}
$script:ScanNames = @()
$script:ScanTick = 0

function Start-Scan {
    if ($script:Busy) { return }
    if (-not $Demo -and (-not $script:WorkerReady -or (Test-WorkerBusy))) {
        # die kurze Prüfung der Laufwerke beim Start läuft noch: der Scan kommt direkt danach
        if ($script:DriveCheckRunning) { $script:ScanAfterCheck = $true; Set-Status 'Scan startet gleich …' 'Accent'; return }
        Set-Status 'Einen Moment, die Treibersuche wird vorbereitet …' 'Warn'
        return
    }
    $script:Busy = 'scan'
    $script:ScanNames = @(); $script:ScanTick = 0
    $script:TextBeforeScan = $ui.LastScanText.Text
    $ui.LastScanText.Text = ' '
    $script:ShownPercent = 0.0; $script:TargetPercent = 1.0; $script:StageFrom = 0.0; $script:StageTo = 16.0
    Set-OrbProgress 0
    Set-OrbScanning
    Set-Status 'Scan läuft …' 'Accent' -Pulse
    Set-OrbSub 'Klicken stoppt'
    $ui.HintText.Text = T $('Zum Abbrechen noch einmal auf den Knopf klicken.')
    if ($Demo) {
        $steps = @(
            @{ At = 100; Msg = @{ Type = 'stage'; Percent = 2; Next = 16; Text = 'Lese Geräte und installierte Treiber …' } },
            @{ At = 900; Msg = @{ Type = 'stage'; Percent = 16; Next = 58; Text = 'Frage Windows Update nach neueren Treibern …' } },
            @{ At = 2300; Msg = @{ Type = 'stage'; Percent = 58; Next = 66; Text = 'Frage NVIDIA nach dem neuesten Grafiktreiber …' } },
            @{ At = 2900; Msg = @{ Type = 'stage'; Percent = 66; Next = 93; Text = 'Durchsuche den Microsoft-Katalog …' } },
            @{ At = 3900; Msg = @{ Type = 'stage'; Percent = 93; Next = 99; Text = 'Prüfe Spielkomponenten …' } },
            @{ At = 4500; Msg = @{ Type = 'done'; Job = 'scan'; Result = $demoResult } }
        )
        $steps += @{ At = 500; Msg = @{ Type = 'devices'; Names = @($demoResult.Drivers | ForEach-Object { $_.Name }) } }
        foreach ($step in $steps) { Invoke-Later $step.At { param($m) if ($script:Busy -eq 'scan') { $sync.Queue.Enqueue($m) } } $step.Msg }
    }
    else {
        Start-WorkerJob 'scan' $scanCode @{ Nvidia = [bool]$script:Settings.Nvidia; Catalog = [bool]$script:Settings.Catalog }
    }
}

function Stop-Scan {
    if ($script:Busy -ne 'scan') { return }
    Stop-WorkerJob
    $script:Busy = $null
    Set-OrbProgress 0
    Set-OrbIdle
    Set-OrbSub 'Treiber prüfen'
    $ui.HintText.Text = T $(Get-ScanHint)
    $ui.LastScanText.Text = $script:TextBeforeScan
    Set-Status 'Scan abgebrochen' 'Warn'
}

function Complete-Scan($Message) {
    if ($Message.Error) {
        $script:Busy = $null
        Set-OrbProgress 0
        Set-OrbIdle
        Set-OrbSub 'Erneut versuchen'
        $ui.LastScanText.Text = $script:TextBeforeScan
        Set-Status "Scan fehlgeschlagen: $($Message.Error)" 'Bad'
        return
    }
    $script:LastResult = $Message.Result
    $script:ShownPercent = 100.0; $script:TargetPercent = 100.0
    Set-OrbProgress 1.0
    $ui.OrbLabel.Text = '100 %'
    # kurzer Lichtblitz zum Abschluss, dann die Ergebnisse
    $ui.OrbGlow.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.5 -Ms 700))
    Start-Scale $ui.Orb 1 520 0 1.06 $script:EaseBack
    Invoke-Later 650 {
        $script:Busy = $null
        Set-OrbProgress 0
        Set-OrbIdle
        Set-OrbSub 'Erneut prüfen'
        $ui.HintText.Text = T $(Get-ScanHint)
        Show-Results $script:LastResult
        Show-Page 'Results'
    }
}

# --- Ergebnisse ---------------------------------------------------------------
. (Get-AppCode 'PulsRig-Ergebnisse.ps1')

# --- Seitenwechsel ------------------------------------------------------------

$script:Page = 'Home'
$script:NavIndex = @{ Home = 0; Results = 0; Boost = 1; Tools = 2; Hardware = 3 }

# Seitenleiste: der gewählte Eintrag ist hell mit farbigem Symbol, die anderen treten zurück
function Update-NavLook([string]$Name) {
    $active = if ($Name -eq 'Results') { 'Home' } else { $Name }
    foreach ($nav in $ui.NavHome, $ui.NavBoost, $ui.NavTools, $ui.NavHardware) {
        $on = $nav.Tag -eq $active
        $line = @($nav.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] })[0]
        # der gewählte Eintrag hellt weich auf, sein Symbol springt kurz auf
        Start-Fade $line $(if ($on) { 1 } else { 0.72 }) 240
        $icon = $line.Children[0]
        if ($icon.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
            $icon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $icon.RenderTransform = New-Object Windows.Media.ScaleTransform
        }
        if ($on -and $script:NavActive -and $script:NavActive -ne $active) { Start-Scale $icon 1 460 0 0.6 $script:EaseBack }
        Set-Paint $line.Children[0] 'Foreground' $(if ($on) { 'Accent' } else { 'Text' })
        $line.Children[1].FontWeight = if ($on) { 'SemiBold' } else { 'Normal' }
        if ($on) { $nav.Children[0].BeginAnimation($P.Opacity, $null); $nav.Children[0].Opacity = 0 }
    }
    $script:NavActive = $active
}

# Der farbige Strich der Marke: verschieben und strecken getrennt, damit er unterwegs länger werden kann
$script:NavBarStretch = New-Object Windows.Media.ScaleTransform 1, 1, 1.5, 13
$script:NavBarMove = New-Object Windows.Media.TranslateTransform
$navBarGroup = New-Object Windows.Media.TransformGroup
$navBarGroup.Children.Add($script:NavBarStretch)
$navBarGroup.Children.Add($script:NavBarMove)
$ui.NavBar.RenderTransform = $navBarGroup

# Hebt das Symbol eines Eintrags der Seitenleiste unter der Maus ein Stück an
function Set-NavNudge($Nav, [bool]$Over) {
    $line = @($Nav.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] })[0]
    if ($line.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $line.RenderTransform = New-Object Windows.Media.TranslateTransform }
    $line.RenderTransform.BeginAnimation($P.Y, (New-DoubleAnim -To $(if ($Over) { -2 } else { 0 }) -Ms $(if ($Over) { 180 } else { 260 })))
}

# Nach dem Vorspann rücken die Einträge der Seitenleiste nacheinander von links herein
function Show-NavItems {
    if (-not $script:Settings.Animations) { return }
    $index = 0
    foreach ($item in $ui.NavHead, $ui.NavHome, $ui.NavBoost, $ui.NavTools, $ui.NavHardware, $ui.NavSettings, $ui.NavMenu, $ui.AdminBadge) {
        $delay = 160 + 55 * $index
        $item.RenderTransform = New-Object Windows.Media.TranslateTransform
        $item.Opacity = 0
        Start-Fade $item 1 320 $delay
        $item.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -22 -To 0 -Ms 460 -Delay $delay))
        $index++
    }
    foreach ($marker in $ui.NavIndicator, $ui.NavBar) {
        $marker.Opacity = 0
        Start-Fade $marker 1 320 240
    }
}

function Show-Page([string]$Name) {
    if ($Name -eq $script:Page) { return }
    Add-MemTrace "Seite: $Name"
    Update-NavLook $Name
    $old = $ui["Page$($script:Page)"]
    $new = $ui["Page$Name"]
    # die Seiten folgen der Marke in der Seitenleiste: weiter unten im Menü kommt von unten, weiter oben von oben
    $way = if ($script:NavIndex[$Name] -lt $script:NavIndex[$script:Page]) { -1 } else { 1 }
    $script:Page = $Name

    # die alte Seite weicht in die Gegenrichtung aus, während sie verblasst
    Start-Fade $old 0 150
    Start-Slide $old (-12 * $way) 150 0 $null $script:EaseCubicIn
    Invoke-Later 160 { param($page) if ($page -ne $ui["Page$($script:Page)"]) { $page.Visibility = 'Collapsed' } } $old
    $new.Visibility = 'Visible'
    Start-Fade $new 1 300 110 0
    Start-Slide $new 0 1 0 0
    # Kopf und Inhalt der neuen Seite gleiten nacheinander herein, der Inhalt mit etwas mehr Weg
    $step = 0
    foreach ($part in $new.Children) {
        if ($part.RenderTransform -isnot [Windows.Media.TranslateTransform]) {
            if ($part.RenderTransform -ne [Windows.Media.Transform]::Identity) { continue }
            $part.RenderTransform = New-Object Windows.Media.TranslateTransform
        }
        Start-Slide $part 0 (440 + 60 * $step) (110 + 70 * $step) ((16 + 12 * $step) * $way)
        if ($step -lt 2) { $step++ }
    }

    $offset = 68 * $script:NavIndex[$Name]
    foreach ($move in $ui.NavIndicator.RenderTransform, $script:NavBarMove) {
        $move.BeginAnimation($P.Y, (New-DoubleAnim -To $offset -Ms 420 -Ease $script:EaseBack))
    }
    # unterwegs streckt sich der farbige Strich und zieht sich am Ziel wieder zusammen
    if ($script:Settings.Animations) {
        $stretch = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $stretch.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(460))
        foreach ($frame in @(0.35, 1.9), @(0.75, 0.8), @(1.0, 1.0)) {
            $key = New-Object Windows.Media.Animation.EasingDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))
            $key.EasingFunction = $script:EaseSineInOut
            [void]$stretch.KeyFrames.Add($key)
        }
        $script:NavBarStretch.BeginAnimation($P.ScaleY, $stretch)
    }

    Set-GaugeIdle
    if ($Name -ne 'Hardware') { $ui.HardwarePillDot.BeginAnimation($P.Opacity, $null) }
    switch ($Name) {
        'Home' { if ($script:HomeCardsFresh) { $script:HomeCardsFresh = $false; Show-HomeCardNews } }
        'Hardware' { Update-HardwareBadges; Show-HardwareCards }
        'Tools' { Show-Tiles }
        'Boost' { Update-Boost; Update-Ram -WithList }
    }
}

# --- Hardware -----------------------------------------------------------------

# Die Karten der Vorschau kommen als Welle von oben links nach unten rechts; in jeder federt das Symbol auf,
# die Trennlinie wächst von links und die geplanten Punkte erscheinen nacheinander
function Show-HardwareCards {
    if (-not $script:Settings.Animations) { return }
    $index = 0
    foreach ($card in $ui.HardwareGrid.Children) {
        $delay = 130 + 80 * (($index % 4) + [Math]::Floor($index / 4))
        $card.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $card.RenderTransform = New-Object Windows.Media.ScaleTransform
        $card.BeginAnimation($P.Opacity, $null)
        $card.Opacity = 0
        Start-Fade $card 1 300 $delay
        Start-Scale $card 1 480 $delay 0.92 $script:EaseBack
        # PulsRig-Hardware.ps1 setzt den Inhalt jeder Karte in ein Raster mit Fußzeile: der Inhalt ist dann dessen erstes Kind
        $stack = if ($card.Child -is [Windows.Controls.StackPanel]) { $card.Child } else { $card.Child.Children[0] }
        $parts = $stack.Children
        $icon = $parts[0].Children[0]
        $icon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $icon.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Scale $icon 1 700 $delay 0.5 $script:EaseElastic
        $step = 0
        for ($i = 3; $i -lt $parts.Count; $i++) {
            $part = $parts[$i]
            $wait = $delay + 220 + 70 * $step
            if ($i -eq 3) {
                $part.RenderTransformOrigin = New-Object Windows.Point 0, 0.5
                $part.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 1
                $part.RenderTransform.BeginAnimation($P.ScaleX, (New-DoubleAnim -From 0 -To 1 -Ms 480 -Delay ($delay + 160)))
                continue
            }
            $part.RenderTransform = New-Object Windows.Media.TranslateTransform
            $part.BeginAnimation($P.Opacity, $null)
            $part.Opacity = 0
            Start-Fade $part 1 300 $wait
            $part.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -10 -To 0 -Ms 380 -Delay $wait))
            $step++
        }
        $index++
    }
    # der Punkt im Hinweis "Vorschau" atmet, solange die Seite offen ist
    Start-Reveal $ui.HardwarePill 200 -8
    $ui.HardwarePillDot.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.3 -Ms 1100 -Ease $script:EaseSine -Forever -AutoReverse))
}

# --- Werkzeuge ----------------------------------------------------------------

$script:Tools = [ordered]@{
    FixAudio            = @{ Glyph = 0xE767; Title = 'Tonstörung beheben'; Desc = 'Dienste, Stummschaltung und Ausgabe prüfen'; Short = 'Ton'; ShortDesc = 'Kein Ton, falsche Ausgabe' }
    FixNetwork          = @{ Glyph = 0xE774; Title = 'Netzwerkfehler beheben'; Desc = 'Verbindung testen und in Stufen reparieren'; Short = 'Netzwerk'; ShortDesc = 'Langsam oder weg' }
    FixResolution       = @{ Glyph = 0xE7F4; Title = 'Bildauflösung beheben'; Desc = 'Grafiktreiber und empfohlene Auflösung prüfen'; Short = 'Bild'; ShortDesc = 'Auflösung stimmt nicht' }
    FixDevices          = @{ Glyph = 0xE7BA; Title = 'Gerätefehler beheben'; Desc = 'Fehlerhafte Geräte erkennen und neu einrichten'; Short = 'Geräte'; ShortDesc = 'Gelbes Warnzeichen' }
    CleanDevices        = @{ Glyph = 0xE772; Title = 'Gerätedaten bereinigen'; Desc = 'Einträge nicht mehr angeschlossener Hardware entfernen' }
    GameRuntimes        = @{ Glyph = 0xE7FC; Title = 'Spielkomponenten'; Desc = 'Visual C++, DirectX und XNA prüfen und nachinstallieren' }
    IncompatibleDrivers = @{ Glyph = 0xE83D; Title = 'Inkompatible Treiber'; Desc = 'Treiber finden, die die Kernisolierung blockieren' }
    Backup              = @{ Glyph = 0xE74E; Title = 'Treiber sichern'; Desc = 'Alle Treiber von Drittherstellern exportieren' }
    Restore             = @{ Glyph = 0xE7A7; Title = 'Treiber wiederherstellen'; Desc = 'Eine Sicherung wieder einspielen' }
    OfflinePackage      = @{ Glyph = 0xE7B8; Title = 'Offline-Paket'; Desc = 'Treiberpaket für eine Neuinstallation ohne Internet' }
    # Sichern, Wiederherstellen und Offline-Paket unter einem Eintrag (Auswahl in Open-DriverBackupSheet)
    DriverBackup        = @{ Glyph = 0xE74E; Title = 'Treiber-Sicherung'; Desc = 'Sichern, zurückholen oder als Offline-Paket'; Find = 'Treiber sichern wiederherstellen Offline-Paket' }
    SystemInfo          = @{ Glyph = 0xE946; Title = 'Systeminformationen'; Desc = 'Hardware und Windows im Überblick' }
    History             = @{ Glyph = 0xE81C; Title = 'Treiberverlauf'; Desc = 'Was Windows Update eingespielt hat und wann' }
    Autostart           = @{ Glyph = 0xE7E8; Title = 'Autostart'; Desc = 'Programme, die mit Windows starten' }
    CleanDisk           = @{ Glyph = 0xE74D; Title = 'Speicherplatz freigeben'; Desc = 'Temporäre Dateien, Shader-Cache und alte Treiberpakete löschen' }
    Standby             = @{ Glyph = 0xE708; Title = 'Standby-Detektiv'; Desc = 'Warum der PC aufwacht oder wach bleibt' }
    Power               = @{ Glyph = 0xE945; Title = 'Stromverbrauch'; Desc = 'Watt und Stromkosten im Jahr, geschätzt'; Find = 'Strom Stromkosten Watt Verbrauch Euro kWh FPS Limit Bildrate sparen' }
    InputTest           = @{ Glyph = 0xE7FC; Title = 'Controller und Maus'; Desc = 'Tasten, Stick-Drift, Abfragerate und Doppelklick-Fehler'; Find = 'Controller Gamepad Maus Drift Hz Doppelklick' }
    GameBoost           = @{ Glyph = 0xEC4A; Title = 'Spiel-Beschleunigung'; Desc = 'Energieplan, Dienste und speicherhungrige Programme' }
}
# Werkzeuge, die auch ohne Adminrechte wirklich arbeiten (alle anderen zeigen dann nur ihre Schritte)
$script:NoAdminTools = 'Backup', 'OfflinePackage', 'SystemInfo'

# Große Kachel für die schnellen Reparaturen; #22D3EE steht für die Symbolfarbe und wird je Kachel ersetzt
$tileXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{DynamicResource TileButton}" Width="220" Height="62" Margin="0,0,12,12" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Button.RenderTransform>
        <ScaleTransform ScaleX="0.9" ScaleY="0.9"/>
    </Button.RenderTransform>
    <Grid Margin="0,-8">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="IconBox" Width="36" Height="36" HorizontalAlignment="Left" RenderTransformOrigin="0.5,0.5">
            <Grid.RenderTransform>
                <ScaleTransform/>
            </Grid.RenderTransform>
            <Border CornerRadius="12" Background="#2422D3EE"/>
            <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <TextBlock x:Name="Arrow" Grid.Column="1" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="#5E6E94" HorizontalAlignment="Right" VerticalAlignment="Center">
            <TextBlock.RenderTransform>
                <TranslateTransform/>
            </TextBlock.RenderTransform>
        </TextBlock>
        <Border x:Name="Badge" Visibility="Collapsed"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,14,0">
            <TextBlock x:Name="Title" FontSize="13.5" FontWeight="SemiBold" Foreground="#E8EEFC" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="Desc" FontSize="11.5" Foreground="#93A3C7" TextTrimming="CharacterEllipsis" Margin="0,1,0,0"/>
        </StackPanel>
    </Grid>
</Button>
'@

# Flache Zeile für die übrigen Werkzeuge: Symbol links, Text daneben, Pfeil rechts
$toolRowXaml = @'
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{DynamicResource TileButton}" Width="452" Height="68" Margin="0,0,0,4" Opacity="0" RenderTransformOrigin="0.5,0.5">
    <Button.RenderTransform>
        <ScaleTransform ScaleX="0.9" ScaleY="0.9"/>
    </Button.RenderTransform>
    <Grid Margin="0,-7">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="IconBox" Width="38" Height="38" RenderTransformOrigin="0.5,0.5">
            <Grid.RenderTransform>
                <ScaleTransform/>
            </Grid.RenderTransform>
            <Border CornerRadius="11" Background="#2422D3EE"/>
            <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="13,0,10,0">
            <TextBlock x:Name="Title" FontSize="13.5" FontWeight="SemiBold" Foreground="#E8EEFC" TextWrapping="Wrap"/>
            <TextBlock x:Name="Desc" FontSize="11.5" Foreground="#93A3C7" TextWrapping="Wrap" MaxHeight="31" Margin="0,2,0,0"/>
        </StackPanel>
        <Border x:Name="Badge" Grid.Column="2" CornerRadius="8" Padding="8,3" Background="#14FFFFFF" VerticalAlignment="Center" Margin="0,0,10,0" Visibility="Collapsed">
            <TextBlock Text="Probelauf" FontSize="10.5" FontWeight="SemiBold" Foreground="#93A3C7"/>
        </Border>
        <TextBlock x:Name="Arrow" Grid.Column="3" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#5E6E94" VerticalAlignment="Center">
            <TextBlock.RenderTransform>
                <TranslateTransform/>
            </TextBlock.RenderTransform>
        </TextBlock>
    </Grid>
</Button>
'@

# Oben die schnellen Reparaturen als schmale Reihe, darunter zwei Spalten mit je vier flachen Zeilen
# (GameBoost hat seine eigene Seite)
$script:ToolGroups = [ordered]@{
    'Schnelle Reparaturen' = 'FixAudio', 'FixNetwork', 'FixResolution', 'FixDevices'
    # der Treiberverlauf ist über "Was hat sich geändert?" und Optionen → Schnellzugriff erreichbar
    'Treiber und Komponenten' = 'DriverBackup', 'IncompatibleDrivers', 'CleanDevices', 'GameRuntimes'
    'System'                  = 'Autostart', 'CleanDisk', 'Standby', 'Power', 'SystemInfo', 'InputTest'
}
# Symbolfarben der Reihe nach: Akzent- und Ringfarben des Designs
$script:ToolColors = '#22D3EE', '#FB923C', '#A855F7', '#F43F5E', '#FDE047'

# Spielkomponenten, Systeminformationen und Treiberverlauf haben eine eigene Ansicht mit Listen statt des Protokolls
function Open-Tool([string]$Name) {
    switch ($Name) {
        'GameRuntimes' { Open-RuntimeSheet }
        'SystemInfo' { Open-SystemSheet }
        'History' { Open-HistorySheet }
        'Autostart' { Open-AutostartSheet }
        'Standby' { Open-StandbySheet }
        'Power' { Open-PowerSheet }
        'InputTest' { Open-InputSheet }
        'DriverBackup' { Open-DriverBackupSheet }
        default { Open-ToolDialog $Name }
    }
}

function Open-DriverBackupSheet {
    $opened = Open-Sheet @{
        Title    = 'Treiber-Sicherung'
        Sub      = 'Sichern, zurückholen oder als Offline-Paket'
        Glyph    = 0xE74E
        Show     = {
            param($tab)
            $rows = @()
            foreach ($name in 'Backup', 'Restore', 'OfflinePackage') {
                $tool = $script:Tools[$name]
                $dry = -not $script:IsAdmin -and $script:NoAdminTools -notcontains $name
                $rows += New-SheetRow -Title $tool.Title -Sub $tool.Desc -Glyph $tool.Glyph -Tone 'accent' -State $(if ($dry) { 'Probelauf' } else { '' }) -Action 'Öffnen' -Data @{ Tool = $name }
            }
            Show-SheetList $rows
            Set-SheetStateText 'Sicherungen landen im Zielordner (Optionen → Treiber)'
        }
        OnAction = { param($item) if ($item.Data -and $item.Data.Tool) { $tool = $item.Data.Tool; Close-Sheet -Quick; Open-ToolDialog $tool } }
    }
    if (-not $opened) { return }
}

function New-ToolHeader([string]$Text) {
    $Text = T $Text
    $header = New-Object Windows.Controls.StackPanel
    $header.Orientation = 'Horizontal'
    $header.Margin = '2,2,0,8'
    $bar = New-Object Windows.Controls.Border
    $bar.Width = 3; $bar.Height = 14; $bar.CornerRadius = (Get-SkinRadius 1.5); $bar.Margin = '0,0,9,0'
    $bar.Background = $window.FindResource('AccentGrad')
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text.ToUpper(); $label.FontSize = 10.5; $label.FontWeight = 'SemiBold'
    Set-Paint $label 'Foreground' 'TextFaint'
    [void]$header.Children.Add($bar)
    [void]$header.Children.Add($label)
    $header
}

$script:Tiles = @()
$script:TileDelays = @()      # Wartezeit je Kachel beim Einblenden, nach ihrem Platz auf der Seite
$script:ToolFind = @()        # je Werkzeug: Kachel, Überschrift ihrer Gruppe und der Text, in dem die Suche sucht
$toolIndex = 0
foreach ($group in $script:ToolGroups.Keys) {
    $big = $group -eq 'Schnelle Reparaturen'
    $header = New-ToolHeader $group
    if ($big) {
        $header.Width = 920      # volle Breite: erzwingt im Umbruch-Raster eine eigene Zeile
        [void]$ui.ToolGrid.Children.Add($header)
        $target = $ui.ToolGrid
    }
    else {
        $target = New-Object Windows.Controls.StackPanel
        $target.Width = 452
        $target.Margin = '0,2,12,0'
        [void]$target.Children.Add($header)
        [void]$ui.ToolGrid.Children.Add($target)
    }
    $slot = 0
    foreach ($name in $script:ToolGroups[$group]) {
        $tool = $script:Tools[$name]
        $color = $script:ToolColors[$toolIndex % $script:ToolColors.Count]
        $toolIndex++
        $xaml = $(if ($big) { $tileXaml } else { $toolRowXaml }).Replace('#2422D3EE', '#24' + $color.Substring(1)).Replace('#22D3EE', $color)
        $tile = [Windows.Markup.XamlReader]::Parse((ConvertTo-ThemedXaml $xaml))
        $tile.FindName('Glyph').Text = Get-Glyph $tool.Glyph
        $tile.FindName('Title').Text = T $(if ($big -and $tool.Short) { $tool.Short } else { $tool.Title })
        $tile.FindName('Desc').Text = T $(if ($big -and $tool.ShortDesc) { $tool.ShortDesc } else { $tool.Desc })
        if ($big) { $tile.ToolTip = T $tool.Title }
        # ohne Adminrechte zeigen diese Werkzeuge nur, was sie tun würden
        if (-not $script:IsAdmin -and $script:NoAdminTools -notcontains $name -and $name -notin 'GameRuntimes', 'SystemInfo', 'History', 'Autostart', 'Standby', 'Power', 'DriverBackup', 'InputTest') {
            $tile.FindName('Badge').Visibility = 'Visible'
            # in der schmalen Reihe ist für das Schild kein Platz: der Hinweis steht im Tooltip
            if ($big) { $tile.ToolTip = "$(T $tool.Title) – $(T 'Probelauf ohne Adminrechte')" }
        }
        $tile.Tag = $name
        $tile.Add_Click({ try { Open-Tool $this.Tag } catch { Write-AppError $_ } })
        # unter der Maus wächst das Symbol ein wenig und der Pfeil rückt nach rechts
        $tile.Add_MouseEnter({
                try {
                    Start-Scale $this.FindName('IconBox') 1.12 220 0 $null $script:EaseBack
                    $this.FindName('Arrow').RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 4 -Ms 200))
                }
                catch { Write-AppError $_ }
            })
        $tile.Add_MouseLeave({
                try {
                    Start-Scale $this.FindName('IconBox') 1 300
                    $this.FindName('Arrow').RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 0 -Ms 300))
                }
                catch { Write-AppError $_ }
            })
        [void]$target.Children.Add($tile)
        $script:Tiles += $tile
        $script:ToolFind += @{ Tile = $tile; Header = $header; Text = ("$(T $tool.Title) $(T $tool.Desc) $($tool.Title) $($tool.Desc) $($tool.Short) $($tool.ShortDesc) $($tool.Find)").ToLower() }
        # die großen Kacheln von links nach rechts, danach beide Spalten gemeinsam Zeile für Zeile
        $script:TileDelays += if ($big) { 130 + 55 * $slot } else { 320 + 60 * $slot + $(if ($group -eq 'System') { 45 } else { 0 }) }
        $slot++
    }
}

# Suche auf der Werkzeug-Seite: zeigt nur passende Werkzeuge; Gruppen ohne Treffer verschwinden samt Überschrift
function Update-ToolFilter {
    $words = @($ui.ToolSearch.Text.ToLower() -split '\s+' | Where-Object { $_ })
    $ui.ToolSearchHint.Visibility = if ($ui.ToolSearch.Text) { 'Collapsed' } else { 'Visible' }
    $shown = @{}
    $any = $false
    foreach ($entry in $script:ToolFind) {
        $hit = $true
        foreach ($word in $words) { if (-not $entry.Text.Contains($word)) { $hit = $false; break } }
        $entry.Tile.Visibility = if ($hit) { 'Visible' } else { 'Collapsed' }
        if ($hit) { $shown[$entry.Header] = $true; $any = $true }
    }
    foreach ($entry in $script:ToolFind) {
        $header = $entry.Header
        $visible = if ($shown[$header]) { 'Visible' } else { 'Collapsed' }
        # bei den flachen Zeilen steht die Überschrift mit ihnen in einer eigenen Spalte
        if ($header.Parent -is [Windows.Controls.StackPanel] -and $header.Parent -ne $ui.ToolGrid) { $header.Parent.Visibility = $visible } else { $header.Visibility = $visible }
    }
    $ui.ToolSearchNone.Visibility = if ($any) { 'Collapsed' } else { 'Visible' }
}
$ui.ToolSearch.Add_TextChanged({ try { Update-ToolFilter } catch { Write-AppError $_ } })

# Die Kacheln kommen als Welle von oben links nach unten rechts; das Symbol federt in jeder kurz nach
function Show-Tiles {
    for ($i = 0; $i -lt $script:Tiles.Count; $i++) {
        $tile = $script:Tiles[$i]
        $delay = $script:TileDelays[$i]
        $wide = $tile.Width -gt 300      # die flachen Zeilen wachsen weniger, sonst wirkt es bei ihrer Breite unruhig
        Start-Fade $tile 1 280 $delay 0
        Start-Scale $tile 1 460 $delay $(if ($wide) { 0.95 } else { 0.86 }) $script:EaseBack
        Start-Scale $tile.FindName('IconBox') 1 700 $delay 0.5 $script:EaseElastic
    }
}

# --- Dialog -------------------------------------------------------------------

$script:Dialog = $null        # @{ Kind = 'tool' | 'update'; Name = ... }
$script:LogOpenLine = $null
$script:LogLastBlank = $true
$script:PromptMode = $null
$script:LogColors = @{
    Green = 'Good'; Yellow = 'Warn'; Red = 'Bad'; Cyan = 'Accent'; DarkGray = 'TextFaint'; Gray = 'TextDim'
}

function Reset-Log {
    $ui.LogPanel.Children.Clear()
    $script:LogCounts = @{ Ok = 0; Warn = 0; Failed = 0 }
    $script:LogOpenLine = $null
    $script:LogLastBlank = $true
}

function Set-LogMark($Mark, [int]$Glyph, [string]$Key) {
    # das Symbol springt kurz auf, wenn es erscheint oder ein Schritt sein Ergebnis bekommt
    if ($Mark.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
        $Mark.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $Mark.RenderTransform = New-Object Windows.Media.ScaleTransform
    }
    Start-Scale $Mark 1 380 0 0.4 $script:EaseBack
    $Mark.Children[1].Text = Get-Glyph $Glyph
    Set-Paint $Mark.Children[0] 'Fill' $Key
    Set-Paint $Mark.Children[1] 'Foreground' $Key
}

function Add-LogRun($Block, [string]$Text, [string]$Key) {
    $run = New-Object Windows.Documents.Run $Text
    Set-Paint $run 'Foreground' $Key
    [void]$Block.Inlines.Add($run)
}

# Eine Zeile der Werkzeugausgabe als Listenzeile: Prüfungen und Schritte bekommen ein Symbol,
# Wertepaare eine rechtsbündige Zahl; nur echte Tabellen bleiben in Schreibmaschinenschrift
function New-LogRow([string]$Line, [string]$Key, [bool]$Open) {
    $row = New-Object Windows.Controls.Grid
    $row.Margin = '0,3,0,3'
    foreach ($width in 'Auto', '*', 'Auto') {
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = $width
        [void]$row.ColumnDefinitions.Add($column)
    }
    $block = New-Object Windows.Controls.TextBlock
    $block.FontSize = 13.5
    $block.TextWrapping = 'Wrap'
    $block.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($block, 1)
    [void]$row.Children.Add($block)

    $glyph = 0; $markKey = $Key; $text = $Line.Trim(); $value = ''
    if ($Line -match '^\s*\[ ok \]\s*(.*)$') { $glyph = 0xE73E; $markKey = 'Good'; $text = $Matches[1]; $script:LogCounts.Ok++ }
    elseif ($Line -match '^\s*\[ !! \]\s*(.*)$') { $glyph = 0xE7BA; $markKey = 'Warn'; $text = $Matches[1]; $script:LogCounts.Warn++ }
    elseif ($Line -match '^\s*\[Probelauf\]\s*(.*)$') { $glyph = 0xE768; $markKey = 'TextDim'; $text = $Matches[1]; $value = 'Probelauf' }
    elseif ($Open -and $Line -match '^\s*(.*?)\s*\.\.\.\s*$') { $glyph = 0xE72A; $markKey = 'Accent'; $text = $Matches[1] }
    elseif ($Line -match '^\s+(?:\d+\.\s+)?(\S.*?)\s{2,}([\d.,]+ MB)$') { $glyph = 0xE915; $markKey = 'TextFaint'; $text = $Matches[1]; $value = $Matches[2] }
    elseif ($Line -match '^\s+-\s+(.*)$') { $glyph = 0xE915; $markKey = 'TextFaint'; $text = $Matches[1] }
    elseif ($Line -match '\S\s{2,}\S') {
        # ausgerichtete Spalten
        $block.FontFamily = 'Consolas, Cascadia Mono'
        $block.FontSize = 13
        $text = $Line
    }

    if ($glyph) {
        $mark = New-Object Windows.Controls.Grid
        $mark.Width = 20; $mark.Height = 20
        $mark.Margin = '0,0,10,0'
        $mark.VerticalAlignment = 'Top'
        $disc = New-Object Windows.Shapes.Ellipse
        $disc.Opacity = 0.16
        $icon = New-Object Windows.Controls.TextBlock
        $icon.FontFamily = 'Segoe MDL2 Assets'
        $icon.FontSize = 10
        $icon.HorizontalAlignment = 'Center'
        $icon.VerticalAlignment = 'Center'
        [void]$mark.Children.Add($disc)
        [void]$mark.Children.Add($icon)
        Set-LogMark $mark $glyph $markKey
        [void]$row.Children.Add($mark)
        # "Bezeichnung - Einzelheit": die Einzelheit tritt zurück
        $parts = $text -split ' - ', 2
        Add-LogRun $block $parts[0] $(if ($markKey -in 'TextDim', 'TextFaint' -and -not $value) { 'TextDim' } else { 'Text' })
        if ($parts.Count -gt 1) { Add-LogRun $block "   $($parts[1])" 'TextDim' }
        if ($Open) { $script:LogOpenMark = $mark }
    }
    else {
        Add-LogRun $block $text $(if ($Key -eq 'Text' -and $Line -match '^\s') { 'TextDim' } else { $Key })
        if ($Open) { $script:LogOpenMark = $null }
    }
    if ($value) {
        $tag = New-Object Windows.Controls.TextBlock
        $tag.Text = $value
        $tag.FontSize = 12
        $tag.Margin = '14,0,0,0'
        $tag.VerticalAlignment = 'Center'
        Set-Paint $tag 'Foreground' 'TextFaint'
        [Windows.Controls.Grid]::SetColumn($tag, 2)
        [void]$row.Children.Add($tag)
    }
    $script:LogOpenLine = $block
    $row
}

function Add-Log([string]$Text, [string]$Color, [bool]$NoNewline) {
    $lines = @((Format-ShownPath $Text) -split "\r?\n")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd()
        $isLast = $i -eq $lines.Count - 1
        if ($line -match '^\s*===\s.*===\s*$') { continue }   # Überschrift steht schon im Dialogkopf
        if (-not $line.Trim() -and -not $script:LogOpenLine) {
            # Leerzeilen als kleinen Abstand, nie doppelt
            if (-not $script:LogLastBlank) {
                $gap = New-Object Windows.Controls.Border
                $gap.Height = 8
                [void]$ui.LogPanel.Children.Add($gap)
                $script:LogLastBlank = $true
            }
            continue
        }
        $brushKey = if ($script:LogColors.ContainsKey($Color)) { $script:LogColors[$Color] } else { 'Text' }
        if ($script:LogOpenLine) {
            # Fortsetzung eines Schritts: das Ergebnis färbt sein Symbol, nur Fehler stehen ausgeschrieben da
            if ($script:LogOpenMark -and $line.Trim() -eq 'ok') { Set-LogMark $script:LogOpenMark 0xE73E 'Good' }
            else {
                if ($script:LogOpenMark) { Set-LogMark $script:LogOpenMark 0xE711 $brushKey }
                # ein Schritt, der nicht geklappt hat, gehört in die Bilanz am Fuß des Dialogs
                if ($line.Trim() -like 'fehlgeschlagen*') { $script:LogCounts.Failed++ }
                $run = New-Object Windows.Documents.Run "  $(T $line.Trim())"
                Set-Paint $run 'Foreground' $brushKey
                [void]$script:LogOpenLine.Inlines.Add($run)
            }
        }
        else {
            $row = New-LogRow (TL $line) $brushKey ($NoNewline -and $isLast)
            # neue Zeilen gleiten von links herein
            $row.RenderTransform = New-Object Windows.Media.TranslateTransform
            $row.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -12 -To 0 -Ms 300))
            Start-Fade $row 1 240 0 0
            [void]$ui.LogPanel.Children.Add($row)
        }
        $script:LogLastBlank = $false
        if (-not ($NoNewline -and $isLast)) { $script:LogOpenLine = $null }
    }
    while ($ui.LogPanel.Children.Count -gt 400) { $ui.LogPanel.Children.RemoveAt(0) }
    $ui.LogScroll.ScrollToEnd()
}

function Set-DialogRunning([bool]$Running) {
    if ($Running) {
        $ui.DialogBar.Opacity = 1
        $ui.DialogBar.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From -200 -To 680 -Ms 1300 -Ease $script:EaseInOut -Forever))
    }
    else {
        $ui.DialogBar.RenderTransform.BeginAnimation($P.X, $null)
        Start-Fade $ui.DialogBar 0 300
    }
}

function Show-DoneMark([bool]$Success) {
    $color = if ($Success) { '#34D399' } else { '#FBBF24' }
    $ui.DoneCheck.Stroke = New-Brush $color
    $ui.DoneCircle.Stroke = New-Brush $color
    $ui.DoneCircle.Fill = New-Brush ($color -replace '^#', '#26')
    $ui.DoneCheck.StrokeDashOffset = 9
    Start-Fade $ui.DoneMark 1 200
    Start-Scale $ui.DoneMark 1 520 0 0.4 $script:EaseElastic
    $ui.DoneCheck.BeginAnimation($P.Dash, (New-DoubleAnim -From 9 -To 0 -Ms 420 -Delay 180 -Ease $script:EaseInOut))
}

# Karte im Einstieg eines Dialogs: Symbol, großer Wert, Bezeichnung
function New-IntroCard([int]$Glyph, [string]$Value, [string]$Label, [string]$Key = 'Accent') {
    $Value = T $Value; $Label = T $Label
    $card = New-Object Windows.Controls.Border
    $card.Style = $window.FindResource('Card')
    $card.Padding = '14,13'
    $card.Margin = '5,0'
    $grid = New-Object Windows.Controls.Grid
    foreach ($width in 'Auto', '*') {
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = $width
        [void]$grid.ColumnDefinitions.Add($column)
    }
    $tile = New-Object Windows.Controls.Grid
    $tile.Width = 36; $tile.Height = 36
    $tile.Margin = '0,0,12,0'
    $back = New-Object Windows.Controls.Border
    $back.CornerRadius = (Get-SkinRadius 11)
    $back.Opacity = 0.16
    Set-Paint $back 'Background' $Key
    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = Get-Glyph $Glyph
    $icon.FontFamily = 'Segoe MDL2 Assets'
    $icon.FontSize = 16
    $icon.HorizontalAlignment = 'Center'
    $icon.VerticalAlignment = 'Center'
    Set-Paint $icon 'Foreground' $Key
    [void]$tile.Children.Add($back)
    [void]$tile.Children.Add($icon)
    $texts = New-Object Windows.Controls.StackPanel
    $texts.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($texts, 1)
    $big = New-Object Windows.Controls.TextBlock
    $big.Text = $Value
    $big.FontSize = 16
    $big.FontWeight = 'SemiBold'
    $big.TextTrimming = 'CharacterEllipsis'
    Set-Paint $big 'Foreground' 'Text'
    $small = New-Object Windows.Controls.TextBlock
    $small.Text = $Label
    $small.FontSize = 11.5
    $small.TextWrapping = 'Wrap'
    Set-Paint $small 'Foreground' 'TextDim'
    [void]$texts.Children.Add($big)
    [void]$texts.Children.Add($small)
    [void]$grid.Children.Add($tile)
    [void]$grid.Children.Add($texts)
    $card.Child = $grid
    $card
}

# Blendet ein Element nach einer Wartezeit ein und lässt es ein Stück heraufgleiten; bis dahin bleibt es unsichtbar
function Start-Reveal($Element, [int]$Delay, [double]$Rise = 10, [int]$Ms = 320) {
    $Element.BeginAnimation($P.Opacity, $null)
    if ($Element.RenderTransform -isnot [Windows.Media.TranslateTransform]) { $Element.RenderTransform = New-Object Windows.Media.TranslateTransform }
    $Element.RenderTransform.BeginAnimation($P.Y, $null)
    if (-not $script:Settings.Animations) { $Element.Opacity = 1; return }
    $Element.Opacity = 0
    Start-Fade $Element 1 $Ms $Delay
    Start-Slide $Element 0 ($Ms + 140) $Delay $Rise
}

# $Intro: erster Absatz groß, alles nach der ersten Leerzeile als Hinweis darunter; $Cards: Karten von New-IntroCard
function Open-Dialog([string]$Title, [string]$Sub, [int]$Glyph, [string]$Intro, [string]$StartText, $Cards) {
    $Title = T $Title; $Sub = T $Sub; $Intro = T $Intro; $StartText = T $StartText
    Reset-Log
    Hide-Prompt
    $ui.DialogTitle.Text = $Title
    $ui.DialogSub.Text = $Sub
    $ui.DialogGlyph.Text = Get-Glyph $Glyph
    $ui.DialogIntroGlyph.Text = Get-Glyph $Glyph
    $introParts = $Intro -split "`n`n", 2
    $ui.DialogIntroText.Text = $introParts[0]
    $ui.DialogIntroNoteText.Text = if ($introParts.Count -gt 1) { $introParts[1] -replace "`n`n", "`n" } else { '' }
    $ui.DialogIntroNote.Visibility = if ($introParts.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    $ui.DialogIntroCards.Children.Clear()
    foreach ($card in @($Cards | Where-Object { $_ })) { [void]$ui.DialogIntroCards.Children.Add($card) }
    $ui.DialogIntroCards.Visibility = if ($ui.DialogIntroCards.Children.Count) { 'Visible' } else { 'Collapsed' }
    $ui.DialogBadge.Visibility = if ($script:Dialog -and $script:Dialog.DryRun) { 'Visible' } else { 'Collapsed' }
    $ui.LogFrame.BeginAnimation($P.Opacity, $null)
    $ui.LogFrame.Opacity = 0
    $ui.DialogIntro.Visibility = 'Visible'
    # die Ausblend-Animation des letzten Laufs lösen, sonst bliebe der Einstieg beim zweiten Öffnen unsichtbar
    $ui.DialogIntro.BeginAnimation($P.Opacity, $null)
    $ui.DialogIntro.Opacity = 1
    $ui.DialogState.Text = ''
    $ui.DoneMark.BeginAnimation($P.Opacity, $null)
    $ui.DoneMark.Opacity = 0
    $ui.BtnDialogStart.Content = $StartText
    $ui.BtnDialogStart.Visibility = 'Visible'
    $ui.BtnDialogStart.IsEnabled = $true
    $ui.BtnDialogSecondary.Content = T $('Schließen')
    Set-DialogRunning $false

    $ui.Overlay.Visibility = 'Visible'
    Start-Fade $ui.OverlayDim 1 220
    Start-Fade $ui.DialogCard 1 240 40 0
    Start-Scale $ui.DialogCard 1 420 40 0.92 $script:EaseBack
    # der Einstieg baut sich nacheinander auf: das Symbol federt auf, dann folgen Text, Karten und Hinweis
    $ui.DialogIntro.RenderTransform = New-Object Windows.Media.TranslateTransform
    $ui.LogFrame.RenderTransform = New-Object Windows.Media.TranslateTransform
    $symbol = $ui.DialogIntroGlyph.Parent
    $symbol.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $symbol.RenderTransform = New-Object Windows.Media.ScaleTransform
    Start-Scale $symbol 1 750 40 0.5 $script:EaseElastic
    Start-Reveal $ui.DialogIntroText 170
    $wait = 250
    foreach ($card in $ui.DialogIntroCards.Children) {
        Start-Reveal $card $wait 14
        $wait += 75
    }
    Start-Reveal $ui.DialogIntroNote ($wait + 30)
    # der Schein hinter dem Symbol im Einstieg atmet sanft
    if ($script:Settings.Animations) {
        $ui.DialogIntroHalo.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.45 -Ms 1600 -Ease $script:EaseSine -Forever -AutoReverse))
    }
    else { $ui.DialogIntroHalo.BeginAnimation($P.Opacity, $null) }
}

function Close-Dialog {
    if ($script:Busy -in 'tool', 'update') {
        Stop-WorkerJob
        $script:Busy = $null
    }
    $closed = $script:Dialog
    $script:Dialog = $null
    Set-DialogRunning $false
    $ui.DialogIntroHalo.BeginAnimation($P.Opacity, $null)
    Start-Fade $ui.OverlayDim 0 200
    Start-Fade $ui.DialogCard 0 160
    Start-Scale $ui.DialogCard 0.95 200
    Invoke-Later 220 { if (-not $script:Dialog) { $ui.Overlay.Visibility = 'Collapsed' } }
    if ($closed -and $closed.Name -eq 'GameBoost') { Update-Boost; Update-Ram -WithList }
}

function Open-ToolDialog([string]$Name) {
    if ($script:Busy) { return }
    $tool = $script:Tools[$Name]
    $dryRun = -not $script:IsAdmin -and $script:NoAdminTools -notcontains $Name
    $intro = $tool.Desc + '.'
    if ($dryRun) { $intro += "`n`nOhne Adminrechte läuft das Werkzeug als Probelauf: Es prüft alles und zeigt, was es tun würde." }
    else { $intro += "`n`nDas Werkzeug prüft zuerst nur und fragt nach, bevor es etwas verändert." }
    $script:Dialog = @{ Kind = 'tool'; Name = $Name; DryRun = $dryRun }
    $start = if ($dryRun) { 'Probelauf starten' } else { 'Starten' }
    $cards = @()
    if ($Name -eq 'GameBoost') {
        # der Einstieg zeigt als Karten, was in "Einrichten" ausgewählt ist
        $boostOn = Test-Path -LiteralPath (Join-Path $script:OutDir 'Spiel-Beschleunigung.json')
        $plan = $script:Settings.Boost
        if ($boostOn) {
            $intro = $intro -replace '^[^\n]*', 'Die Spiel-Beschleunigung ist eingeschaltet. Ausschalten stellt Energieplan und Dienste wieder zurück.'
            if (-not $dryRun) { $start = 'Ausschalten' }
        }
        else {
            $intro = $intro -replace '^[^\n]*', 'Das fasst der Boost beim Einschalten an:'
            if (-not $dryRun) { $start = 'Einschalten' }
            $apps = @($plan.Apps | Where-Object { $_ }).Count
            $services = if ($null -eq $plan.Services) { 'Vorgabe' } else { "$(@($plan.Services | Where-Object { $_ }).Count)" }
            $extras = @($(if ($plan.PowerPlan) { 'Energieplan' }), $(if ($plan.GameMode) { 'Spielmodus' }), $(if ($plan.Clipboard) { 'Zwischenablage' }) | Where-Object { $_ })
            $cards = @(
                New-IntroCard 0xE8FC "$apps" $(if ($apps -eq 1) { 'Programm schließen' } else { 'Programme schließen' }) 'Accent'
                New-IntroCard 0xE9F5 $services 'Dienste anhalten' 'Ring2'
                New-IntroCard 0xE945 "$($extras.Count)" $(if ($extras.Count) { $extras -join ', ' } else { 'keine Extras' }) 'Ring1'
            )
        }
    }
    else {
        # der Ablauf in drei Schritten; ohne Adminrechte endet er beim Anzeigen
        $cards = @(
            New-IntroCard 0xE721 '1 · Prüfen' 'liest nur den Zustand' 'Accent'
            $(if ($dryRun) { New-IntroCard 0xE890 '2 · Anzeigen' 'was zu tun wäre' 'Ring2' } else { New-IntroCard 0xE897 '2 · Nachfragen' 'vor jeder Änderung' 'Ring2' })
            $(if ($dryRun) { New-IntroCard 0xE72E '3 · Beheben' 'nur mit Adminrechten' 'TextFaint' } else { New-IntroCard 0xE90F '3 · Beheben' 'nur nach deinem Ja' 'Ring1' })
        )
        if (-not $dryRun) { $intro = $tool.Desc + '.' }
    }
    Open-Dialog $tool.Title $tool.Desc $tool.Glyph $intro $start $cards
}

# Spielkomponenten mit fester Auswahl aus der Liste installieren
function Open-RuntimeInstall([string[]]$Names) {
    if ($script:Busy -or $Names.Count -eq 0) { return }
    $tool = $script:Tools['GameRuntimes']
    $dryRun = -not $script:IsAdmin
    # je Komponente eine Zeile; ab der vierten nur noch die Anzahl
    $list = (@($Names | Select-Object -First 3 | ForEach-Object { "• $_" }) + $(if ($Names.Count -gt 3) { "• und $($Names.Count - 3) weitere" })) -join "`n"
    # im Probelauf wird nichts installiert - dann sagt der Einstieg das auch nicht
    $intro = $(if ($dryRun) { if ($Names.Count -eq 1) { 'Eine Komponente ist ausgewählt.' } else { "$($Names.Count) Komponenten sind ausgewählt." } }
        elseif ($Names.Count -eq 1) { 'Eine Komponente wird installiert.' } else { "$($Names.Count) Komponenten werden installiert." }) + "`n`n$list"
    if ($dryRun) {
        $intro += "`nOhne Adminrechte läuft das als Probelauf: Es wird nichts geladen und nichts installiert."
        $cards = @(
            New-IntroCard 0xE721 '1 · Prüfen' 'liest nur den Zustand' 'Accent'
            New-IntroCard 0xE890 '2 · Anzeigen' 'was zu tun wäre' 'Ring2'
            New-IntroCard 0xE72E '3 · Installieren' 'nur mit Adminrechten' 'TextFaint'
        )
    }
    else {
        $intro += "`nDie Installer öffnen sich nacheinander – dort jeweils selbst bestätigen."
        $cards = @(
            New-IntroCard 0xE896 '1 · Laden' 'direkt von Microsoft' 'Accent'
            New-IntroCard 0xE8FB '2 · Bestätigen' 'im Installer von Microsoft' 'Ring2'
            New-IntroCard 0xE73E '3 · Fertig' 'für alle Spiele nutzbar' 'Good'
        )
    }
    $script:Dialog = @{ Kind = 'tool'; Name = 'GameRuntimes'; DryRun = $dryRun; RuntimePlan = $Names }
    Open-Dialog 'Spielkomponenten installieren' "$($Names.Count) ausgewählt" $tool.Glyph $intro $(if ($dryRun) { 'Probelauf starten' } else { 'Installieren' }) $cards
}

# Treiberpaket eines einzelnen Geräts sichern
function Open-ExportDialog($Driver) {
    if ($script:Busy) { return }
    $target = Get-TargetDir
    $script:Dialog = @{ Kind = 'custom'; Name = 'Export'; DryRun = $false; Code = $exportCode
        Argument = @{ Inf = $Driver.Inf; Name = $Driver.Name; TargetDir = $target } }
    # die Karten nennen Paket, Version und Zielordner; der volle Pfad steht im Hinweis darunter
    $cards = @(
        New-IntroCard 0xE7B8 "$($Driver.Inf)" 'Treiberpaket' 'Accent'
        $(if ("$($Driver.Version)") { New-IntroCard 0xE8D7 "$($Driver.Version)" 'Version' 'Ring2' })
        New-IntroCard 0xE8B7 (Split-Path -Leaf $target) 'Zielordner' 'Ring1'
    )
    Open-Dialog 'Treiber sichern' $Driver.Name 0xE74E "Das Treiberpaket wird in einen eigenen Ordner kopiert.`n`nZiel: $target`nAm installierten Treiber ändert sich nichts." 'Sichern' $cards
}

function Open-UpdateDialog {
    $chosen = @($script:UpdateRows | Where-Object { $_.Check.IsChecked })
    $ids = @($chosen | Where-Object { $_.Kind -eq 'wu' } | ForEach-Object { $_.Id })
    $nvidia = [bool]($chosen | Where-Object { $_.Kind -eq 'nvidia' })
    $total = $ids.Count + [int]$nvidia
    if ($total -eq 0) { return }
    $script:Dialog = @{ Kind = 'update'; Ids = $ids; Nvidia = $nvidia }
    # der Einstieg nennt, was ausgewählt ist und welche Sicherungen laut Einstellungen vorher laufen
    $restore = [bool]$script:Settings.RestorePoint; $backup = [bool]$script:Settings.AutoBackup
    $safety = if ($restore -and $backup) { 'Punkt und Sicherung' } elseif ($restore) { 'Wiederherstellungspunkt' } elseif ($backup) { 'bisherige Treiber' } else { 'ausgeschaltet' }
    $cards = @(
        New-IntroCard 0xE777 '1 · Sichern' $safety $(if ($restore -or $backup) { 'Good' } else { 'Warn' })
        New-IntroCard 0xE896 '2 · Laden' $(if ($total -eq 1) { '1 Treiber' } else { "$total Treiber" }) 'Accent'
        New-IntroCard 0xE8FB '3 · Installieren' 'danach evtl. Neustart' 'Ring2'
    )
    $names = @($chosen | ForEach-Object { "$($_.Title)" } | Where-Object { $_ })
    # je Treiber eine Zeile; ab dem vierten nur noch die Anzahl
    $list = (@($names | Select-Object -First 3 | ForEach-Object { "• $_" }) + $(if ($names.Count -gt 3) { "• und $($names.Count - 3) weitere" })) -join "`n"
    $intro = $(if ($total -eq 1) { 'Ein Treiber wird heruntergeladen und installiert.' } else { "$total Treiber werden heruntergeladen und installiert." })
    $intro += "`n`n$list"
    if ($nvidia) { $intro += "`nDer NVIDIA-Installer öffnet sich als eigenes Fenster." }
    if (-not $restore -and -not $backup) { $intro += "`nWiederherstellungspunkt und Treibersicherung sind in den Einstellungen ausgeschaltet." }
    Open-Dialog 'Treiber aktualisieren' "$total ausgewählt" 0xE896 $intro 'Jetzt aktualisieren' $cards
}

# $TestCode ersetzt beim Selbsttest den eigentlichen Werkzeuglauf
function Start-DialogJob([string]$TestCode) {
    if ($script:Busy -or -not $script:Dialog) { return }
    if (-not $script:WorkerReady -or (Test-WorkerBusy)) {
        $ui.DialogState.Text = T $('Einen Moment, der Arbeitsbereich ist noch beschäftigt …')
        return
    }
    # der Einstieg weicht nach oben, die Ausgabe kommt von unten nach
    Start-Fade $ui.DialogIntro 0 180
    Start-Slide $ui.DialogIntro -18 180 0 $null $script:EaseCubicIn
    Invoke-Later 190 { $ui.DialogIntro.Visibility = 'Collapsed'; $ui.DialogIntroHalo.BeginAnimation($P.Opacity, $null) }
    Start-Fade $ui.LogFrame 1 280 190
    Start-Slide $ui.LogFrame 0 420 190 18
    $ui.BtnDialogStart.Visibility = 'Collapsed'
    $ui.BtnDialogSecondary.Content = T $('Abbrechen')
    $ui.DialogState.Text = T $('Läuft …')
    Set-DialogRunning $true
    $what = if ($script:Dialog.Kind -eq 'update') { 'Treiber installieren' } elseif ($script:Dialog.Name) { "Werkzeug $($script:Dialog.Name)" } else { 'Werkzeug' }
    Add-RunLog ("`r`n=== {0:HH:mm:ss}  {1}{2} ===" -f (Get-Date), $what, $(if ($script:Dialog.DryRun) { ' (Probelauf)' })) $false
    if ($script:Dialog.Kind -eq 'update') {
        $script:Busy = 'update'
        Start-WorkerJob 'update' $updateCode @{ Ids = $script:Dialog.Ids; Nvidia = $script:Dialog.Nvidia; TargetDir = (Get-TargetDir)
            RestorePoint = [bool]$script:Settings.RestorePoint; AutoBackup = [bool]$script:Settings.AutoBackup }
    }
    elseif ($script:Dialog.Kind -eq 'custom') {
        $script:Busy = 'tool'
        Start-WorkerJob 'tool' $script:Dialog.Code $script:Dialog.Argument
    }
    else {
        $script:Busy = 'tool'
        $code = if ($TestCode) { $TestCode } else { $toolCode }
        # eine Kopie der Boost-Auswahl mitgeben: der Arbeitsbereich ergänzt darin die vorgegebenen Dienste
        $boost = $script:Settings.Boost
        Start-WorkerJob 'tool' $code @{ Name = $script:Dialog.Name; DryRun = $script:Dialog.DryRun; TargetDir = (Get-TargetDir)
            RuntimePlan = $script:Dialog.RuntimePlan
            BoostPlan   = @{ Apps = @($boost.Apps); Services = $boost.Services; PowerPlan = [bool]$boost.PowerPlan; GameMode = [bool]$boost.GameMode; Clipboard = [bool]$boost.Clipboard } }
    }
}

function Complete-DialogJob($Message) {
    $kind = $script:Busy
    $script:Busy = $null
    Hide-Prompt
    Set-DialogRunning $false
    $ui.BtnDialogSecondary.Content = T $('Schließen')
    if ($Message.Error) {
        Add-Log "Fehler: $($Message.Error)" 'Red' $false
        Add-RunLog "Fehler: $($Message.Error)`r`n--- Ende: mit Fehler beendet" $false
        $ui.DialogState.Text = T $('Mit Fehler beendet')
        Show-DoneMark $false
        return
    }
    $result = $Message.Result
    if ($kind -eq 'update') {
        $ui.DialogState.Text = T ("Geladen: $($result.Downloaded) · Installiert: $($result.Installed) · Fehlgeschlagen: $($result.Failed)" +
            $(if ($result.Reboot) { ' · Neustart nötig' }))
        Show-DoneMark ($result.Failed -eq 0)
        Set-Status 'Aktualisierung abgeschlossen - für den neuen Stand erneut scannen' 'Good'
        # für die Probezeit: ein Treiberwechsel um diese Zeit kam von PulsRig
        if ($result.Installed -gt 0) { $script:History.LastInstall = (Get-Date).Ticks; Save-HardwareResults }
    }
    else {
        $failed = $result -and $result.Failed
        Add-MemTrace "Werkzeug fertig: $($script:Dialog.Name)$(if ($script:Dialog.DryRun) { ' (Probelauf)' })"
        $ui.DialogState.Text = T $(if ($failed) { 'Fertig, aber nicht alle Schritte haben geklappt' } elseif ($script:Dialog.DryRun) { 'Probelauf beendet – nichts verändert' } else { 'Fertig' })
        # Bilanz der Prüfungen aus der Ausgabe
        if ($script:LogCounts.Ok + $script:LogCounts.Warn + $script:LogCounts.Failed -gt 0) {
            $ui.DialogState.Text += " · $($script:LogCounts.Ok) in Ordnung · $($script:LogCounts.Warn) auffällig"
            if ($script:LogCounts.Failed -gt 0) { $ui.DialogState.Text += " · $($script:LogCounts.Failed) nicht geklappt" }
        }
        Show-DoneMark (-not $failed)
    }
    Add-RunLog "--- Ende: $($ui.DialogState.Text)" $false
    # das Ergebnis in der Fußzeile blendet auf, damit der Abschluss auffällt
    Start-Fade $ui.DialogState 1 420 0 0
}

function Show-Prompt([string]$Text, [string]$Mode) {
    $Text = T $Text
    $script:PromptMode = $Mode
    $ui.PromptText.Text = $Text
    if ($Mode -eq 'input') {
        $ui.PromptInput.Text = ''
        $ui.PromptInput.Visibility = 'Visible'
        $ui.BtnPromptYes.Content = T $('OK')
        $ui.BtnPromptNo.Content = T $('Überspringen')
        $ui.PromptLabel.Text = T $('DEINE EINGABE')
        $ui.PromptGlyph.Text = Get-Glyph 0xE70F
        $ui.PromptHint.Text = T $('Die Eingabetaste bestätigt. Das Werkzeug wartet so lange.')
    }
    else {
        $ui.PromptInput.Visibility = 'Collapsed'
        $ui.BtnPromptYes.Content = T $('Ja')
        $ui.BtnPromptNo.Content = T $('Nein')
        $ui.PromptLabel.Text = T $('DEINE ENTSCHEIDUNG')
        $ui.PromptGlyph.Text = Get-Glyph 0xE897
        $ui.PromptHint.Text = T $('Erst mit „Ja“ wird etwas verändert. Das Werkzeug wartet so lange.')
    }
    $ui.PromptPanel.Visibility = 'Visible'
    Start-Fade $ui.PromptPanel 1 240 0 0
    Start-Slide $ui.PromptPanel 0 340 0 14 $script:EaseBack
    # der Inhalt baut sich nacheinander auf: Symbol federt auf, dann Überschrift, Frage, Hinweis und die Knöpfe
    $symbol = $ui.PromptGlyph.Parent
    $symbol.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $symbol.RenderTransform = New-Object Windows.Media.ScaleTransform
    Start-Scale $symbol 1 700 0 0.4 $script:EaseElastic
    $wait = 90
    foreach ($part in $ui.PromptLabel, $ui.PromptText, $ui.PromptInput, $ui.PromptHint) {
        if ($part.Visibility -ne 'Visible') { continue }
        Start-Reveal $part $wait 8 280
        $wait += 55
    }
    foreach ($button in $ui.BtnPromptNo, $ui.BtnPromptYes) {
        $button.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $button.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Pop $button $wait 0.85
        $wait += 70
    }
    # die Ausgabe rückt nach oben, damit die letzte Zeile über der Rückfrage sichtbar bleibt
    Invoke-Later 60 { $ui.LogScroll.ScrollToEnd() }
    if ($script:Settings.Animations) {
        $ui.PromptGlow.BeginAnimation($P.Opacity, (New-DoubleAnim -From 0.15 -To 0.9 -Ms 900 -Ease $script:EaseSine -Forever -AutoReverse))
    }
    else { $ui.PromptGlow.Opacity = 0.6 }
    $ui.DialogState.Text = T $('Wartet auf deine Antwort')
    if ($Mode -eq 'input') { [void]$ui.PromptInput.Focus() }
}

function Hide-Prompt {
    $script:PromptMode = $null
    $ui.PromptGlow.BeginAnimation($P.Opacity, $null)
    $ui.PromptGlow.Opacity = 0
    $ui.PromptPanel.BeginAnimation($P.Opacity, $null)
    $ui.PromptPanel.Opacity = 0
    $ui.PromptPanel.Visibility = 'Collapsed'
}

function Send-Reply([bool]$Yes) {
    if (-not $script:PromptMode) { return }
    $sync.Reply = if ($script:PromptMode -eq 'input') { if ($Yes) { $ui.PromptInput.Text } else { '' } } else { $Yes }
    Add-RunLog ("  Antwort: " + $(if ($script:PromptMode -eq 'input') { "$($sync.Reply)" } elseif ($Yes) { 'ja' } else { 'nein' })) $false
    if ($script:Settings.Animations) {
        # nach der Antwort gleitet die Rückfrage weg, statt zu verschwinden; kommt gleich die nächste, bleibt sie stehen
        $script:PromptMode = $null
        $ui.PromptGlow.BeginAnimation($P.Opacity, $null)
        $ui.PromptGlow.Opacity = 0
        Start-Fade $ui.PromptPanel 0 170
        Start-Slide $ui.PromptPanel 12 170 0 $null $script:EaseCubicIn
        Invoke-Later 180 { if (-not $script:PromptMode) { Hide-Prompt } }
    }
    else { Hide-Prompt }
    $ui.DialogState.Text = T $('Läuft …')
    [void]$sync.ReplyEvent.Set()
}

# --- Boost --------------------------------------------------------------------

$script:GaugeLit = @()
for ($i = 0; $i -le 27; $i++) {
    # jeder Strich doppelt: der blasse steht immer da, der leuchtende darüber blendet mit dem Zeiger ein
    foreach ($lit in $false, $true) {
        $mark = New-Object Windows.Shapes.Rectangle
        $mark.Width = 2; $mark.Height = if ($i % 3 -eq 0) { 8 } else { 5 }
        Set-Paint $mark 'Fill' $(if ($lit) { 'Accent' } else { Get-ThemeKey '#2C3C68' })
        [Windows.Controls.Canvas]::SetLeft($mark, 104)
        [Windows.Controls.Canvas]::SetTop($mark, 22)
        $mark.RenderTransform = New-Object Windows.Media.RotateTransform (-135 + $i * 10), 1, 83
        if ($lit) { $mark.Opacity = 0; $script:GaugeLit += $mark }
        [void]$ui.GaugeTicks.Children.Add($mark)
    }
}

$script:BoostOn = $null
$script:GaugeOnAngle = 112.0     # hier steht der Zeiger bei eingeschaltetem Boost
$script:EaseSineInOut = New-Object Windows.Media.Animation.SineEase
$script:EaseSineInOut.EasingMode = 'EaseInOut'
$script:EaseCubicIn = New-Object Windows.Media.Animation.CubicEase
$script:EaseCubicIn.EasingMode = 'EaseIn'

$ramRowXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,0,11" Opacity="0">
    <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="Name" FontSize="13" Foreground="#E8EEFC" TextTrimming="CharacterEllipsis" Margin="0,0,90,0"/>
    <TextBlock x:Name="Size" FontSize="13" Foreground="#93A3C7" HorizontalAlignment="Right"/>
    <Grid Grid.Row="1" Height="5" Margin="0,6,0,0">
        <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="FillColumn" Width="*"/>
            <ColumnDefinition x:Name="RestColumn" Width="0"/>
        </Grid.ColumnDefinitions>
        <Border Grid.ColumnSpan="2" CornerRadius="2.5" Background="#14FFFFFF"/>
        <Border x:Name="Fill" CornerRadius="2.5" RenderTransformOrigin="0,0.5">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#22D3EE" Offset="0"/>
                    <GradientStop Color="#8B5CF6" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
            <Border.RenderTransform>
                <ScaleTransform ScaleX="0"/>
            </Border.RenderTransform>
            <!-- heller Punkt am Balkenende, passend zum Lichtpunkt am Ring -->
            <Ellipse Width="5" Height="5" Fill="White" Opacity="0.9" HorizontalAlignment="Right"/>
        </Border>
    </Grid>
</Grid>
'@
$ramRowXaml =ConvertTo-ThemedXaml $ramRowXaml

# Bewegung über Stützstellen: Liste aus @(Anteil der Dauer, Wert, Verlauf); $Map rechnet den Wert um
function New-GaugeKeys([int]$Ms, $Keys, [scriptblock]$Map) {
    $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animation.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    foreach ($key in $Keys) {
        $value = if ($Map) { & $Map $key[1] } else { $key[1] }
        $frame = New-Object Windows.Media.Animation.EasingDoubleKeyFrame ([double]$value), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$key[0]))
        $frame.EasingFunction = $key[2]
        [void]$animation.KeyFrames.Add($frame)
    }
    $animation
}

# Solange der Boost an ist und die Seite zu sehen, zittert der Zeiger leicht und der Schein atmet -
# wie ein Motor unter Last. Auf anderen Seiten und im Hintergrund ruht beides.
function Set-GaugeIdle {
    $run = $script:BoostOn -and $script:Page -eq 'Boost' -and $script:Settings.Animations -and $window.IsActive
    $shake = $ui.GaugeHand.RenderTransform
    if ($run) {
        if ($script:GaugeIdle) { return }
        $script:GaugeIdle = $true
        $tremble = New-GaugeKeys 1700 @(@(0.0, 0.0, $null), @(0.14, 1.3, $script:EaseSineInOut), @(0.3, -0.9, $script:EaseSineInOut), @(0.47, 0.7, $script:EaseSineInOut),
            @(0.62, -1.4, $script:EaseSineInOut), @(0.8, 0.5, $script:EaseSineInOut), @(1.0, 0.0, $script:EaseSineInOut))
        $tremble.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $tremble.BeginTime = [TimeSpan]::FromMilliseconds(1500)      # erst, wenn der Zeiger angekommen ist
        $shake.BeginAnimation($P.Angle, $tremble)
        $ui.GaugeGlow.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.62 -Ms 2200 -Delay 1500 -Ease $script:EaseSine -Forever -AutoReverse), [Windows.Media.Animation.HandoffBehavior]::Compose)
    }
    elseif ($script:GaugeIdle) {
        $script:GaugeIdle = $false
        $shake.BeginAnimation($P.Angle, $null)
        $shake.Angle = 0
        if ($script:BoostOn) { $ui.GaugeGlow.BeginAnimation($P.Opacity, $null); $ui.GaugeGlow.Opacity = 1 }
    }
}

function Set-Gauge([bool]$On) {
    $full = 135.0; $rest = $script:GaugeOnAngle
    $toOffset = { param($angle) 59.5 * (1 - ($angle + 135) / 270) }
    $rise = 630        # so lange braucht der Zeiger beim Einschalten bis zum Anschlag
    $fall = 600
    if (-not $script:Settings.Animations) {
        # ohne Animationen springt alles ans Ziel
        $angle = if ($On) { $rest } else { -135.0 }
        $ui.GaugeNeedle.RenderTransform.BeginAnimation($P.Angle, (New-DoubleAnim -To $angle -Ms 1))
        $ui.GaugeValue.BeginAnimation($P.Dash, (New-DoubleAnim -To (& $toOffset $angle) -Ms 1))
        for ($i = 0; $i -lt $script:GaugeLit.Count; $i++) {
            $script:GaugeLit[$i].BeginAnimation($P.Opacity, $null)
            $script:GaugeLit[$i].Opacity = if ($On -and (-135 + $i * 10) -le $rest) { 1 } else { 0 }
        }
    }
    elseif ($On) {
        # wie ein Drehzahlmesser beim Gasgeben: hoch bis zum Anschlag, zurückfedern, einpendeln.
        # Bogen und Zeiger laufen über dieselben Stützstellen, das Bogenende bleibt an der Zeigerspitze.
        $keys = @(@(0.42, $full, $script:EaseSineInOut), @(0.62, ($rest - 12), $script:EaseSineInOut), @(0.82, ($rest + 4), $script:EaseSineInOut), @(1.0, $rest, $script:EaseSineInOut))
        $ui.GaugeNeedle.RenderTransform.BeginAnimation($P.Angle, (New-GaugeKeys 1500 $keys))
        $ui.GaugeValue.BeginAnimation($P.Dash, (New-GaugeKeys 1500 $keys $toOffset))
        # die Striche leuchten auf, wenn der Zeiger sie überfährt; die jenseits der Ruhestellung blitzen nur kurz
        for ($i = 0; $i -lt $script:GaugeLit.Count; $i++) {
            $delay = [int]($rise * [Math]::Acos(1 - 2 * ($i * 10 / 270.0)) / [Math]::PI)
            $light = New-DoubleAnim -From 0 -To 1 -Ms 140 -Delay $delay
            if ((-135 + $i * 10) -gt $rest) { $light.AutoReverse = $true }
            $script:GaugeLit[$i].BeginAnimation($P.Opacity, $light)
        }
    }
    else {
        # der Zeiger fällt zurück und federt einmal am Anschlag
        $keys = @(@(0.6, -135.0, $script:EaseCubicIn), @(0.76, -126.0, $script:EaseOut), @(1.0, -135.0, $script:EaseCubicIn))
        $ui.GaugeNeedle.RenderTransform.BeginAnimation($P.Angle, (New-GaugeKeys 1000 $keys))
        $ui.GaugeValue.BeginAnimation($P.Dash, (New-GaugeKeys 1000 @(, @(0.6, -135.0, $script:EaseCubicIn)) $toOffset))
        for ($i = 0; $i -lt $script:GaugeLit.Count; $i++) {
            $left = [Math]::Max(0.0, 1 - ($i * 10) / ($rest + 135))
            $script:GaugeLit[$i].BeginAnimation($P.Opacity, (New-DoubleAnim -To 0 -Ms 160 -Delay ([int]($fall * [Math]::Pow($left, 1 / 3.0)))))
        }
    }
    # ausgeblendet, wenn leer: das runde Linienende bliebe sonst als Punkt am Anfang stehen
    Start-Fade $ui.GaugeValue $(if ($On) { 1 } else { 0 }) $(if ($On) { 150 } else { 700 })
    Start-Fade $ui.GaugeGlow $(if ($On) { 1 } else { 0 }) 700
    $ui.GaugeState.Text = T $(if ($On) { 'AN' } else { 'AUS' })
    Set-Paint $ui.GaugeState 'Foreground' $(if ($On) { 'Good' } else { 'TextFaint' })
    # das Wort springt kurz auf, damit der Wechsel auffällt
    Start-Scale $ui.GaugeState 1 420 0 1.25 $script:EaseBack
    $ui.BtnBoost.Content = T $(if ($On) { 'Ausschalten' } else { 'Einschalten' })
    $script:GaugeIdle = $false
    $ui.GaugeHand.RenderTransform.BeginAnimation($P.Angle, $null)
    $script:BoostOn = $On
    Set-GaugeIdle
}

# Kleines Schild auf der Boost-Seite: Symbol und Text
function Add-BoostChip([int]$Glyph, [string]$Text, [string]$Key = 'Accent') {
    $Text = T $Text
    $chip = New-Object Windows.Controls.Border
    $chip.CornerRadius = (Get-SkinRadius 9)
    $chip.Padding = '10,5,11,5'
    $chip.Margin = '3'
    $chip.BorderThickness = 1
    $chip.Background = New-Brush '#0FFFFFFF'
    $chip.BorderBrush = New-Brush '#1FFFFFFF'
    $line = New-Object Windows.Controls.StackPanel
    $line.Orientation = 'Horizontal'
    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = Get-Glyph $Glyph
    $icon.FontFamily = 'Segoe MDL2 Assets'
    $icon.FontSize = 12
    $icon.VerticalAlignment = 'Center'
    $icon.Margin = '0,0,7,0'
    Set-Paint $icon 'Foreground' $Key
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $Text
    $label.FontSize = 12
    Set-Paint $label 'Foreground' 'Text'
    [void]$line.Children.Add($icon)
    [void]$line.Children.Add($label)
    $chip.Child = $line
    [void]$ui.BoostChips.Children.Add($chip)
}

function Update-Boost {
    $statePath = Join-Path $script:OutDir 'Spiel-Beschleunigung.json'
    $on = Test-Path -LiteralPath $statePath
    $ui.BoostChips.Children.Clear()
    if ($on) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $ui.BoostInfo.Text = T $(if ($state.Game) { "Eingeschaltet für $($state.Game) seit $($state.Time)" } else { "Eingeschaltet seit $($state.Time)" })
            # vorher und nachher: wie viel Arbeitsspeicher das Einschalten freigemacht hat
            if ($state.FreeBefore -and $state.FreeAfter) {
                $gain = ([double]$state.FreeAfter - [double]$state.FreeBefore) / 1GB
                $ui.BoostInfo.Text += [Environment]::NewLine + (T ('Arbeitsspeicher frei: vorher {0:N1} GB, danach {1:N1} GB' -f ([double]$state.FreeBefore / 1GB), ([double]$state.FreeAfter / 1GB)))
                Add-BoostChip 0xE9D9 $(if ($gain -ge 0.05) { '{0:N1} GB freigemacht' -f $gain } else { 'kaum Speicher freigemacht' }) $(if ($gain -ge 0.05) { 'Good' } else { 'TextDim' })
            }
            $serviceCount = @($state.Services | Where-Object { $_ }).Count
            Add-BoostChip 0xE9F5 $(if ($serviceCount -eq 1) { '1 Dienst angehalten' } else { "$serviceCount Dienste angehalten" }) 'Ring2'
            $closedCount = @($state.ClosedApps | Where-Object { $_ }).Count
            Add-BoostChip 0xE8FC $(if ($closedCount -eq 1) { '1 Programm geschlossen' } else { "$closedCount Programme geschlossen" }) 'Accent'
            if ($state.PowerPlan) { Add-BoostChip 0xE945 'Energieplan umgestellt' 'Ring1' }
        }
        catch { $ui.BoostInfo.Text = T 'Eingeschaltet' }
    }
    else {
        # ausgeschaltet: zeigen, was unter "Einrichten" ausgewählt ist
        $ui.BoostInfo.Text = T $('Derzeit ausgeschaltet. Das fasst der Boost an:')
        $plan = $script:Settings.Boost
        $apps = @($plan.Apps | Where-Object { $_ }).Count
        Add-BoostChip 0xE8FC $(if ($apps -eq 1) { '1 Programm' } else { "$apps Programme" }) 'Accent'
        Add-BoostChip 0xE9F5 $(if ($null -eq $plan.Services) { 'Dienste nach Vorgabe' } else { "$(@($plan.Services | Where-Object { $_ }).Count) Dienste" }) 'Ring2'
        if ($plan.PowerPlan) { Add-BoostChip 0xE945 'Energieplan' 'Ring1' }
        if ($plan.GameMode) { Add-BoostChip 0xE7FC 'Spielmodus' 'Ring1' }
        if ($plan.Clipboard) { Add-BoostChip 0xE77F 'Zwischenablage' 'Ring1' }
    }
    # das Schild "AN" in der Seitenleiste springt auf, wenn der Boost eingeschaltet wurde
    if ($on -and $ui.NavBoostOn.Visibility -ne 'Visible' -and $null -ne $script:BoostOn) {
        $ui.NavBoostOn.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $ui.NavBoostOn.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Scale $ui.NavBoostOn 1 520 0 0.3 $script:EaseElastic
    }
    $ui.NavBoostOn.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
    if ($on -ne $script:BoostOn) {
        $script:BoostOn = $on
        Set-Gauge $on
    }
}

function Set-RamNumbers([double]$Used, [double]$TotalGb) {
    $script:RamNow = $Used
    $ui.RamPercent.Text = '{0:N0} %' -f ($Used * 100)
    $ui.RamUsed.Text = '{0:N1} GB' -f ($TotalGb * $Used)
    $ui.RamFree.Text = '{0:N1} GB' -f ($TotalGb * (1 - $Used))
}

# Zählt Prozent und GB-Werte im Gleichlauf mit dem Ring auf den neuen Stand (gleicher Verlauf wie EaseInOut)
function Start-RamCount([double]$From, [double]$To, [double]$TotalGb, [int]$Ms) {
    $script:RamCount = @{ From = $From; To = $To; Total = $TotalGb; Ms = $Ms; Start = [DateTime]::UtcNow }
    if (-not $script:RamCountTimer) {
        $script:RamCountTimer = New-Object Windows.Threading.DispatcherTimer
        $script:RamCountTimer.Interval = [TimeSpan]::FromMilliseconds(33)
        $script:RamCountTimer.Add_Tick({
                try {
                    $count = $script:RamCount
                    $t = [Math]::Min(1.0, ([DateTime]::UtcNow - $count.Start).TotalMilliseconds / $count.Ms)
                    $eased = if ($t -lt 0.5) { 4 * $t * $t * $t } else { 1 - [Math]::Pow(2 - 2 * $t, 3) / 2 }
                    Set-RamNumbers ($count.From + ($count.To - $count.From) * $eased) $count.Total
                    if ($t -ge 1) { $script:RamCountTimer.Stop() }
                }
                catch { $script:RamCountTimer.Stop(); Write-AppError $_ }
            })
    }
    $script:RamCountTimer.Start()
}

# Zählt die MB-Werte der größten Verbraucher hoch, jede Zeile im Gleichlauf mit ihrem Balken
function Start-RamListCount($Rows) {
    $script:RamListCount = @{ Rows = @($Rows); Start = [DateTime]::UtcNow }
    if (-not $script:RamListTimer) {
        $script:RamListTimer = New-Object Windows.Threading.DispatcherTimer
        $script:RamListTimer.Interval = [TimeSpan]::FromMilliseconds(33)
        $script:RamListTimer.Add_Tick({
                try {
                    $elapsed = ([DateTime]::UtcNow - $script:RamListCount.Start).TotalMilliseconds
                    $done = $true
                    foreach ($row in $script:RamListCount.Rows) {
                        $t = [Math]::Max(0.0, [Math]::Min(1.0, ($elapsed - $row.Delay) / 800))
                        if ($t -lt 1) { $done = $false }
                        $eased = if ($t -lt 0.5) { 4 * $t * $t * $t } else { 1 - [Math]::Pow(2 - 2 * $t, 3) / 2 }
                        $row.Label.Text = '{0:N0} MB' -f ($row.Mb * $eased)
                    }
                    if ($done) { $script:RamListTimer.Stop() }
                }
                catch { $script:RamListTimer.Stop(); Write-AppError $_ }
            })
    }
    $script:RamListTimer.Start()
}

function Update-Ram([switch]$WithList) {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $free = [double]$os.FreePhysicalMemory * 1KB
        $used = 1 - $free / $total
        # beim Betreten der Seite füllt sich der Ring von null, die Zahlen zählen mit; später gleitet er nur nach.
        # Der Lichtpunkt an der Spitze dreht im selben Verlauf mit und bleibt so am Ende des Bogens.
        $ms = if ($WithList) { 1200 } else { 900 }
        $from = if ($WithList -or $null -eq $script:RamNow) { 0.0 } else { $null }
        $ui.RamRing.BeginAnimation($P.Dash, (New-DoubleAnim -From $(if ($null -ne $from) { 56.2 }) -To (56.2 * (1 - $used)) -Ms $ms -Ease $script:EaseInOut))
        $ui.RamTip.RenderTransform.BeginAnimation($P.Angle, (New-DoubleAnim -From $from -To (360 * $used) -Ms $ms -Ease $script:EaseInOut))
        if ($null -ne $from) { Start-Fade $ui.RamTip 1 300 0 0 }
        if ($script:Settings.Animations) { Start-RamCount $(if ($null -ne $from) { 0.0 } else { $script:RamNow }) $used ($total / 1GB) $ms }
        else { Set-RamNumbers $used ($total / 1GB) }
        $ui.RamInfo.Text = T $('{0:N1} GB verbaut' -f ($total / 1GB))

        if ($WithList) {
            $ui.RamList.Children.Clear()
            $session = (Get-Process -Id $PID).SessionId
            $top = Get-Process | Where-Object { $_.SessionId -eq $session } | Group-Object ProcessName |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Bytes = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum } } |
                Sort-Object Bytes -Descending | Select-Object -First 5
            $largest = [double]($top | Select-Object -First 1).Bytes
            $index = 0
            $counts = New-Object Collections.ArrayList
            foreach ($entry in $top) {
                $line = [Windows.Markup.XamlReader]::Parse($ramRowXaml)
                $line.FindName('Name').Text = $entry.Name
                # die Zahl zählt hoch, während der Balken wächst
                $line.FindName('Size').Text = if ($script:Settings.Animations) { '0 MB' } else { '{0:N0} MB' -f ($entry.Bytes / 1MB) }
                [void]$counts.Add(@{ Label = $line.FindName('Size'); Mb = $entry.Bytes / 1MB; Delay = 90 * $index })
                # der Balken zeigt den Anteil am größten Verbraucher und wächst von links herein
                $share = [double]$entry.Bytes / $largest
                $line.FindName('FillColumn').Width = New-Object Windows.GridLength $share, 'Star'
                $line.FindName('RestColumn').Width = New-Object Windows.GridLength (1.0001 - $share), 'Star'
                $line.FindName('Fill').RenderTransform.BeginAnimation($P.ScaleX, (New-DoubleAnim -From 0 -To 1 -Ms 800 -Delay (90 * $index) -Ease $script:EaseInOut))
                # die Zeilen kommen nacheinander von unten herein
                $line.RenderTransform = New-Object Windows.Media.TranslateTransform
                Start-Slide $line 0 420 (90 * $index) 12
                Start-Fade $line 1 320 (90 * $index) 0
                [void]$ui.RamList.Children.Add($line)
                $index++
            }
            if ($script:Settings.Animations) { Start-RamListCount $counts }
        }
    }
    catch { Write-AppError $_ }
}

# --- Nachrichten aus dem Arbeitsbereich ---------------------------------------

function Invoke-Message($Message) {
    switch ($Message.Type) {
        'ready' { $script:WorkerReady = $true }
        'devices' { if ($script:Busy -eq 'scan') { $script:ScanNames = @($Message.Names) } }
        'stage' {
            if ($script:Busy -eq 'scan') {
                $script:StageFrom = [double]$Message.Percent
                $script:StageTo = [double]$Message.Next
                if ($script:StageFrom -gt $script:TargetPercent) { $script:TargetPercent = $script:StageFrom }
                Set-StatusText $Message.Text
            }
        }
        'progress' {
            if ($script:Busy -eq 'scan') {
                if ($Message.Percent -ge 0 -and -not $Message.Completed) {
                    $within = $script:StageFrom + ($script:StageTo - $script:StageFrom) * [double]$Message.Percent / 100.0
                    if ($within -gt $script:TargetPercent) { $script:TargetPercent = $within }
                }
            }
            elseif ($script:Dialog -and -not $Message.Completed -and $Message.Status) {
                $ui.DialogState.Text = T $("$($Message.Activity): $($Message.Status)")
            }
        }
        'log' { if ($script:Busy -in 'tool', 'update') { Add-RunLog $Message.Text ([bool]$Message.NoNewline); Add-Log $Message.Text $Message.Color $Message.NoNewline } }
        'confirm' { Add-RunLog "  Rückfrage: $($Message.Text)" $false; if ($script:Dialog) { Show-Prompt $Message.Text 'confirm' } else { $sync.Reply = $false; [void]$sync.ReplyEvent.Set() } }
        'input' { Add-RunLog "  Eingabe verlangt: $($Message.Text)" $false; if ($script:Dialog) { Show-Prompt $Message.Text 'input' } else { $sync.Reply = ''; [void]$sync.ReplyEvent.Set() } }
        'done' {
            if ($Message.Job -eq 'scan') { if ($script:Busy -eq 'scan') { Complete-Scan $Message } }
            elseif ("$($Message.Job)" -like 'query:*') { Complete-Query $Message }
            elseif ($script:Busy -in 'tool', 'update') { Complete-DialogJob $Message }
        }
    }
}

$pump = New-Object Windows.Threading.DispatcherTimer
$pump.Interval = [TimeSpan]::FromMilliseconds(50)
$pump.Add_Tick({
        try {
            $message = $null
            $handled = 0
            while ($handled -lt 80 -and $sync.Queue.TryDequeue([ref]$message)) {
                $handled++
                Invoke-Message $message
            }
            if ($script:Busy -eq 'scan' -and $script:ShownPercent -lt 100) {
                # innerhalb eines Abschnitts langsam weiterkriechen, damit die Anzeige nie stillsteht
                $ceiling = $script:StageTo - 1
                if ($script:TargetPercent -lt $ceiling) { $script:TargetPercent += ($ceiling - $script:TargetPercent) * 0.006 }
                $script:ShownPercent += ($script:TargetPercent - $script:ShownPercent) * 0.12
                Set-OrbProgress ($script:ShownPercent / 100)
                $ui.OrbLabel.Text = '{0:N0} %' -f [Math]::Floor($script:ShownPercent)
                # unter der Statuszeile laufen die Namen der geprüften Geräte durch
                $script:ScanTick++
                if ($script:ScanNames.Count -gt 0 -and $script:ScanTick % 3 -eq 0) {
                    $index = [int][Math]::Floor($script:ShownPercent / 100.0 * $script:ScanNames.Count * 3 + $script:ScanTick / 3) % $script:ScanNames.Count
                    $ui.LastScanText.Text = $script:ScanNames[$index]
                }
            }
            Step-CurrentRows
            Step-Query
            # im Leerlauf genügt ein langsamer Takt: das spart Rechenzeit, solange nichts läuft
            $quiet = $handled -eq 0 -and -not $script:Busy -and -not $script:CurrentBuild -and -not $script:Query -and -not $script:Dialog -and -not $script:Sheet
            $want = if ($quiet) { 250 } else { 50 }
            if ($this.Interval.TotalMilliseconds -ne $want) { $this.Interval = [TimeSpan]::FromMilliseconds($want) }
        }
        catch { Write-AppError $_ }
    })

$ramTimer = New-Object Windows.Threading.DispatcherTimer
$ramTimer.Interval = [TimeSpan]::FromSeconds(3)
$ramTimer.Add_Tick({ if ($script:Page -eq 'Boost' -and -not $script:Dialog) { Update-Ram } })

# --- Vorspann -----------------------------------------------------------------

# Herzschlag des Logos: großer Ausschlag, kleiner Nachschlag, dazu zwei Wellen, die sich vom Ring lösen
function Start-SplashBeat([int]$Delay) {
    $kick = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $kick.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700))
    $kick.BeginTime = [TimeSpan]::FromMilliseconds($Delay)
    foreach ($frame in @(0.0, 1.0), @(0.16, 1.09), @(0.36, 1.0), @(0.5, 1.04), @(0.72, 1.0), @(1.0, 1.0)) {
        [void]$kick.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))))
    }
    $ui.SplashMark.RenderTransform.BeginAnimation($P.ScaleX, $kick)
    $ui.SplashMark.RenderTransform.BeginAnimation($P.ScaleY, $kick)
    foreach ($offset in 80, 300) {
        $wave = New-Object Windows.Shapes.Ellipse
        $wave.Width = 120; $wave.Height = 120
        $wave.StrokeThickness = 1.5
        $wave.Stroke = $window.FindResource('AccentGrad')
        $wave.Opacity = 0
        $wave.IsHitTestVisible = $false
        $wave.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $wave.RenderTransform = New-Object Windows.Media.ScaleTransform
        $ui.SplashMark.Children.Insert(0, $wave)
        Start-Scale $wave 2.1 1000 ($Delay + $offset) 1
        Start-Fade $wave 0 1000 ($Delay + $offset) 0.55
    }
    # mit jedem Schlag läuft ein Lichtpunkt auf beiden Linien nach außen und verglimmt
    $canvas = $ui.SplashLineL.Parent
    foreach ($side in -1, 1) {
        $spark = New-Object Windows.Shapes.Ellipse
        $spark.Width = 7; $spark.Height = 7
        $spark.Fill = [Windows.Media.Brushes]::White
        $spark.Opacity = 0
        $spark.IsHitTestVisible = $false
        [Windows.Controls.Canvas]::SetLeft($spark, $(if ($side -lt 0) { 2 } else { 123 }))
        [Windows.Controls.Canvas]::SetTop($spark, 64.5)
        $spark.RenderTransform = New-Object Windows.Media.TranslateTransform
        [void]$canvas.Children.Add($spark)
        $spark.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From 0 -To (300 * $side) -Ms 750 -Delay ($Delay + 90) -Ease $script:EaseOut))
        Start-Fade $spark 0 750 ($Delay + 90) 0.95
    }
    # der Schein hinter dem Logo zuckt mit
    Invoke-Later $Delay {
        $throb = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        $throb.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700))
        foreach ($frame in @(0.16, 1.12), @(0.4, 1.0), @(0.55, 1.05), @(0.8, 1.0)) {
            [void]$throb.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))))
        }
        $ui.SplashGlow.RenderTransform.BeginAnimation($P.ScaleX, $throb)
        $ui.SplashGlow.RenderTransform.BeginAnimation($P.ScaleY, $throb)
    }
}

function Start-Splash {
    $ui.SplashVersion.Text = T $("Version $script:Version")
    Start-Fade $ui.SplashGlow 1 900
    Start-Scale $ui.SplashGlow 1 1600 0 0.6
    $ui.SplashRing.BeginAnimation($P.Dash, (New-DoubleAnim -From 72.3 -To 0 -Ms 950 -Delay 150 -Ease $script:EaseInOut))
    Start-Fade $ui.SplashPulse 1 120 520
    $ui.SplashPulse.BeginAnimation($P.Dash, (New-DoubleAnim -From 28 -To 0 -Ms 620 -Delay 520 -Ease $script:EaseInOut))
    Start-Fade $ui.SplashDot 1 160 1050
    Start-Scale $ui.SplashDot 1 380 1050 0.1 $script:EaseBack
    # erster Schlag, sobald die Linie steht; sie läuft dabei links und rechts aus dem Ring hinaus
    Start-SplashBeat 1150
    foreach ($line in $ui.SplashLineL, $ui.SplashLineR) {
        Start-Fade $line 1 200 1180
        $line.RenderTransform.BeginAnimation($P.ScaleX, (New-DoubleAnim -From 0 -To 1 -Ms 700 -Delay 1180 -Ease $script:EaseOut))
    }
    Start-Fade $ui.SplashWord 1 480 1250
    Start-Slide $ui.SplashWord 0 560 1250 16
    # "Puls" und "Rig" kommen von links und rechts zusammen
    $side = -1
    foreach ($part in $ui.SplashWord.Children) {
        $part.RenderTransform = New-Object Windows.Media.TranslateTransform
        $part.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From (22 * $side) -To 0 -Ms 640 -Delay 1250))
        $side = 1
    }
    # die drei Wörter des Leitspruchs erscheinen nacheinander
    $index = 0
    foreach ($word in $ui.SplashTag.Children) {
        $word.RenderTransform = New-Object Windows.Media.TranslateTransform
        Start-Fade $word 1 360 (1500 + 170 * $index)
        Start-Slide $word 0 420 (1500 + 170 * $index) 6
        $index++
    }
    # der Balken füllt sich einmal und ist voll, wenn die Startseite kommt
    Start-Fade $ui.SplashTrack 1 300 1700
    $ui.SplashBar.RenderTransform.BeginAnimation($P.X, $null)
    $ui.SplashBar.RenderTransform.X = 0
    $ui.SplashBar.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-DoubleAnim -From 0 -To 180 -Ms 1150 -Delay 1700 -Ease $script:EaseInOut))
    Start-Fade $ui.SplashVersion 1 400 1800
    # zweiter Schlag kurz vor dem Übergang zur Startseite
    Start-SplashBeat 2150
    Invoke-Later 3000 { Stop-Splash }
}

function Stop-Splash {
    Start-Fade $ui.Splash 0 480
    Start-Scale $ui.SplashMark 1.25 520
    Start-Scale $ui.SplashGlow 1.5 520
    Invoke-Later 500 {
        $ui.Splash.Visibility = 'Collapsed'
        $ui.SplashBar.RenderTransform.BeginAnimation($P.X, $null)
    }
    # die Startseite kommt dem Blick entgegen
    Start-Scale $ui.Orb 1 900 120 0.82 $script:EaseBack
    Start-Fade $ui.PageHome 1 500 120 0
    Show-NavItems
    # Versionsschild und Fensterknöpfe kommen von oben herein
    $index = 0
    foreach ($item in $ui.TitleVersion.Parent, $ui.BtnMinimize, $ui.BtnClose) {
        Start-Reveal $item (320 + 70 * $index) -8
        $index++
    }
    Show-HomeCards
    Show-AdminHint
    # die Pulslinie im Knopf zeichnet sich, während die Startseite hereinkommt
    if ($script:Settings.Animations) {
        $script:OrbPulse.StrokeDashOffset = 34
        $script:OrbPulse.BeginAnimation($P.Dash, (New-DoubleAnim -To 0 -Ms 700 -Delay 500 -Ease $script:EaseInOut))
        Start-OrbBeat 1250
        # danach gilt wieder der feste Wert: die Linie bleibt sichtbar, auch wenn später keine Animation mehr läuft
        Invoke-Later 1300 { $script:OrbPulse.BeginAnimation($P.Dash, $null); $script:OrbPulse.StrokeDashOffset = 0 }
    }
    Set-OrbIdle
    $script:SplashDone = $true
    Add-MemTrace 'Start fertig'
    # erst wenn die Einblendung durch ist; läuft dann schon ein Scan, braucht er den Speicher ohnehin
    Invoke-Later 6000 { if (-not $script:Busy) { Clear-WorkingSet 'nach dem Start' } }
    Invoke-Later 2500 { Start-VersionCheck }
    Invoke-Later 600 { Update-ScanHint }
    if (($script:Settings.AutoScan -or $StartScan) -and -not $Snapshot) { Invoke-Later 900 { if (-not $script:Busy -and -not $script:Sheet -and -not $script:Dialog) { Start-Scan } } }
}

# --- Bedienung ----------------------------------------------------------------

$ui.TitleBar.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch { } })
$ui.NavHead.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch { } })
Update-NavLook 'Home'
$ui.NavBoostOn.Visibility = if (Test-Path -LiteralPath (Join-Path $script:OutDir 'Spiel-Beschleunigung.json')) { 'Visible' } else { 'Collapsed' }
$ui.TitleVersion.Text = $script:Version
# das Versionsschild lässt sich erst anklicken, wenn es eine neuere Fassung meldet (siehe Show-NewVersion)
$ui.TitleVersion.Parent.Add_MouseLeftButtonDown({
        try { $_.Handled = $true; if ($script:NewVersion -and $script:UpdateRepo) { Open-UpdateSheet } } catch { Write-AppError $_ }
    })
# Blendet das ganze Fenster aus und führt danach $Then aus (Schließen oder Minimieren)
function Start-WindowFade([scriptblock]$Then) {
    if (-not $script:Settings.Animations -or $script:WindowFading) { & $Then; return }
    $script:WindowFading = $true
    $window.BeginAnimation([Windows.Window]::OpacityProperty, (New-DoubleAnim -To 0 -Ms 170 -Ease $script:EaseCubicIn))
    Invoke-Later 185 { param($then) $script:WindowFading = $false; & $then } $Then
}
$ui.BtnMinimize.Add_Click({
        try {
            Start-WindowFade {
                $window.WindowState = 'Minimized'
                # die Animation lösen: die Deckkraft aus den Einstellungen gilt wieder
                $window.BeginAnimation([Windows.Window]::OpacityProperty, $null)
            }
        }
        catch { Write-AppError $_ }
    })
$ui.BtnClose.Add_Click({ try { Start-WindowFade { $window.Close() } } catch { Write-AppError $_ } })
# beim Zurückholen aus der Taskleiste blendet das Fenster wieder ein
$script:WindowWas = 'Normal'
$window.Add_StateChanged({
        try {
            if ($window.WindowState -eq 'Normal' -and $script:WindowWas -eq 'Minimized' -and $script:Settings.Animations) {
                $window.BeginAnimation([Windows.Window]::OpacityProperty, (New-DoubleAnim -From 0 -To $window.Opacity -Ms 240))
                Invoke-Later 270 { $window.BeginAnimation([Windows.Window]::OpacityProperty, $null) }
            }
            # minimiert (etwa während eines Spiels) braucht die Oberfläche fast nichts; Messwerte laufen weiter
            if ($window.WindowState -eq 'Minimized' -and $script:WindowWas -ne 'Minimized') {
                Invoke-Later 1500 { if ($window.WindowState -eq 'Minimized') { Clear-WorkingSet 'minimiert' } }
            }
            $script:WindowWas = "$($window.WindowState)"
        }
        catch { Write-AppError $_ }
    })

# unter der Maus dreht sich das Zahnrad ein Stück und der Text rückt nach rechts
$gear = @($ui.NavSettings.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] })[0].Children[0]
$gear.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
$gear.RenderTransform = New-Object Windows.Media.RotateTransform
$ui.NavSettings.Tag = $gear
$ui.NavSettings.Add_MouseEnter({
        Start-Fade $ui.NavSettingsHover 0.06 160
        $this.Tag.RenderTransform.BeginAnimation($P.Angle, (New-DoubleAnim -To 90 -Ms 420))
        Set-NavNudge $this $true
    })
$ui.NavSettings.Add_MouseLeave({
        Start-Fade $ui.NavSettingsHover 0 240
        $this.Tag.RenderTransform.BeginAnimation($P.Angle, (New-DoubleAnim -To 0 -Ms 420))
        Set-NavNudge $this $false
    })
$ui.NavMenu.Add_MouseEnter({ Set-NavNudge $this $true })
$ui.NavMenu.Add_MouseLeave({ Set-NavNudge $this $false })
$ui.NavSettings.Add_MouseLeftButtonUp({ try { if (-not $script:Dialog -and -not $script:Sheet) { Open-SettingsSheet } } catch { Write-AppError $_ } })

foreach ($nav in $ui.NavHome, $ui.NavBoost, $ui.NavTools, $ui.NavHardware) {
    # nicht gewählte Einträge hellen sich beim Überfahren leicht auf
    $nav.Add_MouseEnter({ if ($this.Tag -ne $(if ($script:Page -eq 'Results') { 'Home' } else { $script:Page })) { Start-Fade $this.Children[0] 0.05 160 }; Set-NavNudge $this $true })
    $nav.Add_MouseLeave({ Start-Fade $this.Children[0] 0 240; Set-NavNudge $this $false })
    $nav.Add_MouseLeftButtonUp({
            try {
                if ($script:Dialog -or $script:Sheet) { return }
                $target = $this.Tag
                # von den Ergebnissen aus führt "Scan" zurück zum Knopf
                if ($target -eq 'Home' -and $script:Page -eq 'Home' -and $script:LastResult -and -not $script:Busy) { $target = 'Results' }
                Show-Page $target
            }
            catch { Write-AppError $_ }
        })
}

# unter der Maus wächst der Knopf leicht, und die Pulslinie schlägt einmal (nur im Ruhezustand, nicht beim Scan)
$ui.OrbHit.Add_MouseEnter({
        Start-Scale $ui.Orb 1.035 220
        try { if ($script:Busy -ne 'scan') { Start-OrbBeat } } catch { Write-AppError $_ }
    })
$ui.OrbHit.Add_MouseLeave({ Start-Scale $ui.Orb 1 260 })
$ui.OrbHit.Add_MouseLeftButtonDown({ Start-Scale $ui.Orb 0.97 90 })
$ui.OrbHit.Add_MouseLeftButtonUp({
        try {
            Start-Scale $ui.Orb 1.035 320 0 $null $script:EaseBack
            if ($script:Busy -eq 'scan') { Stop-Scan } else { Start-Scan }
        }
        catch { Write-AppError $_ }
    })

# führt ein Klick zu den Ergebnissen, rückt der Pfeil unter der Maus nach rechts und der Rand wird kräftiger
$ui.StatusPill.Add_MouseEnter({
        try {
            if ($ui.StatusArrow.Visibility -ne 'Visible') { return }
            $ui.StatusArrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 4 -Ms 180))
            Start-Fade $ui.StatusEdge 0.9 180
        }
        catch { Write-AppError $_ }
    })
$ui.StatusPill.Add_MouseLeave({
        try {
            if ($ui.StatusArrow.RenderTransform -is [Windows.Media.TranslateTransform]) { $ui.StatusArrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 0 -Ms 260)) }
            Start-Fade $ui.StatusEdge 0.45 280
        }
        catch { Write-AppError $_ }
    })
$ui.StatusPill.Add_MouseLeftButtonUp({ try { if ($script:LastResult -and -not $script:Busy -and $ui.StatusArrow.Visibility -eq 'Visible') { Show-Page 'Results' } } catch { Write-AppError $_ } })
# Die Karten der Startseite mit Symbol: Symbolfeld und Pfeil bekommen eigene Bewegungen
$script:HomeCards = $ui.ChipDrivers, $ui.ChipGames, $ui.HomeGameCheck
function Get-HomeCardArrow($Card) {
    $last = $Card.Content.Children[$Card.Content.Children.Count - 1]
    if ($last -is [Windows.Controls.TextBlock]) { $last }
}
foreach ($card in $script:HomeCards) {
    $icon = $card.Content.Children[0]
    $icon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $icon.RenderTransform = New-Object Windows.Media.ScaleTransform
    $arrow = Get-HomeCardArrow $card
    if ($arrow) { $arrow.RenderTransform = New-Object Windows.Media.TranslateTransform }
    # unter der Maus wächst das Symbol ein wenig und der Pfeil rückt nach rechts
    $card.Add_MouseEnter({
            try {
                Start-Scale $this.Content.Children[0] 1.12 220 0 $null $script:EaseBack
                $arrow = Get-HomeCardArrow $this
                if ($arrow) { $arrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 4 -Ms 200)) }
            }
            catch { Write-AppError $_ }
        })
    $card.Add_MouseLeave({
            try {
                Start-Scale $this.Content.Children[0] 1 300
                $arrow = Get-HomeCardArrow $this
                if ($arrow) { $arrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To 0 -Ms 300)) }
            }
            catch { Write-AppError $_ }
        })
}

# Nach dem Vorspann steigen die Karten nacheinander von unten auf, das Symbol federt in jeder nach
function Show-HomeCards {
    if (-not $script:Settings.Animations) { return }
    $index = 0
    foreach ($card in $script:HomeCards) {
        $delay = 420 + 90 * $index
        Start-Reveal $card $delay 20 360
        Start-Scale $card.Content.Children[0] 1 700 $delay 0.5 $script:EaseElastic
        $index++
    }
    Start-Reveal $ui.LastScanText 380 6
    # rechte Spalte: Live-Werte und Änderungen gleiten nacheinander herein
    $index = 0
    foreach ($part in $ui.HomeLiveCard, $ui.HomeHistory) {
        Start-Reveal $part (300 + 110 * $index) 16 380
        $index++
    }
}

# Nach einem Scan: Symbol, Zustandspunkt und Text der beiden Ergebnis-Karten zeigen den neuen Stand
function Show-HomeCardNews {
    if (-not $script:Settings.Animations) { return }
    $index = 0
    foreach ($set in @($ui.ChipDrivers, $ui.HomeDriversDot, $ui.HomeDriversText), @($ui.ChipGames, $ui.HomeGamesDot, $ui.HomeGamesText)) {
        $delay = 320 + 140 * $index
        Start-Scale $set[0].Content.Children[0] 1 700 $delay 0.6 $script:EaseElastic
        $set[1].RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $set[1].RenderTransform = New-Object Windows.Media.ScaleTransform 0, 0
        Start-Scale $set[1] 1 600 ($delay + 120) $null $script:EaseElastic
        Start-Reveal $set[2] ($delay + 80) 7 300
        $index++
    }
    Start-Reveal $ui.LastScanText 300 6
}

$ui.ChipDrivers.Add_Click({ try { if ($script:LastResult -and -not $script:Busy) { Show-Page 'Results' } } catch { Write-AppError $_ } })
$ui.ChipGames.Add_Click({ try { Open-RuntimeSheet } catch { Write-AppError $_ } })
$ui.HomeHistory.Add_Click({ try { Open-ChangesSheet } catch { Write-AppError $_ } })
$ui.HomeGameCheck.Add_Click({ try { Open-GameCheckSheet } catch { Write-AppError $_ } })
$ui.ChipProblem.Add_Click({ try { Open-ProblemSheet } catch { Write-AppError $_ } })
$ui.ResultSearch.Add_TextChanged({ try { Update-ResultFilter } catch { Write-AppError $_ } })
$ui.BtnBoostSetup.Add_Click({ try { Open-BoostSheet } catch { Write-AppError $_ } })
$ui.BtnResultsBack.Add_Click({ Show-Page 'Home' })
$ui.BtnUpdateAll.Add_Click({
        try {
            if (-not $script:IsAdmin) {
                try { Restart-Elevated; $window.Close() } catch { }
                return
            }
            Open-UpdateDialog
        }
        catch { Write-AppError $_ }
    })
$ui.BtnBoost.Add_Click({ try { Open-ToolDialog 'GameBoost' } catch { Write-AppError $_ } })

$ui.BtnDialogStart.Add_Click({ try { Start-DialogJob } catch { Write-AppError $_ } })
$ui.BtnDialogSecondary.Add_Click({ try { Close-Dialog } catch { Write-AppError $_ } })
$ui.BtnDialogClose.Add_Click({ try { Close-Dialog } catch { Write-AppError $_ } })
$ui.BtnPromptYes.Add_Click({ try { Send-Reply $true } catch { Write-AppError $_ } })
$ui.BtnPromptNo.Add_Click({ try { Send-Reply $false } catch { Write-AppError $_ } })
$ui.PromptInput.Add_KeyDown({ if ($_.Key -eq 'Return') { try { Send-Reply $true } catch { Write-AppError $_ } } })

if (-not $script:IsAdmin) {
    $ui.AdminIcon.Foreground = Get-Brush 'Warn'
    $ui.AdminIconBack.Background = New-Brush '#24FBBF24'
    $ui.AdminText.Text = T $('Ohne Adminrechte')
    $ui.AdminSub.Text = T $('Scannen und Probeläufe')
    $ui.AdminBadge.Background = New-Brush '#12FBBF24'
    $ui.AdminBadge.BorderBrush = New-Brush '#33FBBF24'
    $ui.AdminBadge.Cursor = 'Hand'
    $ui.AdminAction.Visibility = 'Visible'
    # eigene Pinsel für Schaltfläche und Rand: ihre Farbe lässt sich weich überblenden
    $script:AdminFill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#1FFBBF24'))
    $script:AdminEdge = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#33FBBF24'))
    $ui.AdminAction.Background = $script:AdminFill
    $ui.AdminBadge.BorderBrush = $script:AdminEdge
    $ui.AdminAction.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $ui.AdminAction.RenderTransform = New-Object Windows.Media.ScaleTransform
    $script:AdminArrow = $ui.AdminAction.Child.Children[1]
    $script:AdminArrow.RenderTransform = New-Object Windows.Media.TranslateTransform
    function Set-AdminHover([bool]$Over) {
        $ms = if ($Over) { 180 } else { 300 }
        foreach ($pair in @($script:AdminFill, $(if ($Over) { '#3DFBBF24' } else { '#1FFBBF24' })), @($script:AdminEdge, $(if ($Over) { '#66FBBF24' } else { '#33FBBF24' }))) {
            $fade = New-Object Windows.Media.Animation.ColorAnimation
            $fade.To = [Windows.Media.ColorConverter]::ConvertFromString($pair[1])
            $fade.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($(if ($script:Settings.Animations) { $ms } else { 1 })))
            $pair[0].BeginAnimation([Windows.Media.SolidColorBrush]::ColorProperty, $fade)
        }
        # der Pfeil rückt nach rechts, das Schild wächst ein wenig
        $script:AdminArrow.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -To $(if ($Over) { 4 } else { 0 }) -Ms $ms))
        Start-Scale $ui.AdminIcon.Parent $(if ($Over) { 1.12 } else { 1 }) $ms 0 $null $(if ($Over) { $script:EaseBack } else { $script:EaseOut })
    }
    $ui.AdminBadge.Add_MouseEnter({ try { Set-AdminHover $true } catch { Write-AppError $_ } })
    $ui.AdminBadge.Add_MouseLeave({ try { Set-AdminHover $false; Start-Scale $ui.AdminAction 1 200 } catch { Write-AppError $_ } })
    # gedrückt gibt die Schaltfläche nach
    $ui.AdminBadge.Add_MouseLeftButtonDown({ try { Start-Scale $ui.AdminAction 0.96 90 } catch { Write-AppError $_ } })
    $ui.AdminBadge.Add_MouseLeftButtonUp({ try { Restart-Elevated; $window.Close() } catch { } })
}
$ui.AdminIcon.Parent.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
$ui.AdminIcon.Parent.RenderTransform = New-Object Windows.Media.ScaleTransform
$ui.AdminIcon.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
$ui.AdminIcon.RenderTransform = New-Object Windows.Media.RotateTransform

# Nach dem Start: das Schild federt auf; ohne Adminrechte wackelt es danach einmal kurz und die Schaltfläche steigt auf
function Show-AdminHint {
    if (-not $script:Settings.Animations) { return }
    Start-Scale $ui.AdminIcon.Parent 1 750 620 0.5 $script:EaseElastic
    if ($script:IsAdmin) { return }
    $ui.AdminAction.BeginAnimation($P.Opacity, $null)
    $ui.AdminAction.Opacity = 0
    Start-Fade $ui.AdminAction 1 360 760
    Start-Scale $ui.AdminAction 1 460 760 0.9 $script:EaseBack
    $wiggle = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $wiggle.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700))
    $wiggle.BeginTime = [TimeSpan]::FromMilliseconds(1700)
    foreach ($frame in @(0.0, 0), @(0.15, -14), @(0.35, 12), @(0.55, -8), @(0.75, 5), @(1.0, 0)) {
        $key = New-Object Windows.Media.Animation.EasingDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))
        $key.EasingFunction = $script:EaseSineInOut
        [void]$wiggle.KeyFrames.Add($key)
    }
    $ui.AdminIcon.RenderTransform.BeginAnimation($P.Angle, $wiggle)
}

$window.Add_ContentRendered({
        try {
            $shell = $ui.Shell
            $shell.Clip = New-Object Windows.Media.RectangleGeometry (New-Object Windows.Rect 0, 0, $shell.ActualWidth, $shell.ActualHeight), 18, 18
            $ui.PageHome.Opacity = 0
            $window.Opacity = [Math]::Max(70, [Math]::Min(100, [int]$script:Settings.Opacity)) / 100.0
            $pump.Start()
            $ramTimer.Start()
            Start-Splash
            if ($Snapshot) { Start-SnapshotTour }
        }
        catch { Write-AppError $_ }
    })

$script:SplashDone = $false
$window.Add_Deactivated({ try { Set-GaugeIdle; $ui.HardwarePillDot.BeginAnimation($P.Opacity, $null) } catch { Write-AppError $_ } })
$window.Add_Activated({
        try {
            Set-GaugeIdle
            if ($script:Page -eq 'Hardware' -and $script:Settings.Animations) {
                $ui.HardwarePillDot.BeginAnimation($P.Opacity, (New-DoubleAnim -From 1 -To 0.3 -Ms 1100 -Ease $script:EaseSine -Forever -AutoReverse))
            }
        }
        catch { Write-AppError $_ }
    })
$window.Add_Deactivated({ try { if ($script:SplashDone -and -not $script:Busy -and -not $Snapshot) { Suspend-OrbIdle } } catch { Write-AppError $_ } })
$window.Add_Activated({ try { if ($script:SplashDone -and -not $script:Busy -and -not $Snapshot) { Set-OrbIdle } } catch { Write-AppError $_ } })

$window.Dispatcher.Add_UnhandledException({
        Write-AppError ([Management.Automation.ErrorRecord]::new($_.Exception, 'Dispatcher', 'NotSpecified', $null))
        $_.Handled = $true
    })

# Fensterposition merken und beim nächsten Start wiederherstellen, solange sie noch auf einem Bildschirm liegt
if ($script:Settings.RememberPosition -and $null -ne $script:Settings.Left -and $null -ne $script:Settings.Top -and -not $Snapshot) {
    $left = [double]$script:Settings.Left; $top = [double]$script:Settings.Top
    $visible = $left -ge [Windows.SystemParameters]::VirtualScreenLeft - 100 -and $top -ge [Windows.SystemParameters]::VirtualScreenTop -and
        $left -le [Windows.SystemParameters]::VirtualScreenLeft + [Windows.SystemParameters]::VirtualScreenWidth - 300 -and
        $top -le [Windows.SystemParameters]::VirtualScreenTop + [Windows.SystemParameters]::VirtualScreenHeight - 200
    if ($visible) {
        $window.WindowStartupLocation = 'Manual'
        $window.Left = $left
        $window.Top = $top
    }
}
$window.Add_Closing({
        try {
            if (-not $Snapshot -and $window.WindowState -eq 'Normal') {
                $script:Settings.Left = [int]$window.Left
                $script:Settings.Top = [int]$window.Top
                Save-Settings
            }
        }
        catch { Write-AppError $_ }
    })

# --- Ansichten: Seitenmenü, Einstellungen und die Dialoge mit Listen -----------
. (Get-AppCode 'PulsRig-Ansichten.ps1')
. (Get-AppCode 'PulsRig-Diagnose.ps1')
. (Get-AppCode 'PulsRig-Hardware.ps1')
. (Get-AppCode 'PulsRig-Temperatur.ps1')
. (Get-AppCode 'PulsRig-Benchmark.ps1')
. (Get-AppCode 'PulsRig-Aufzeichnung.ps1')
. (Get-AppCode 'PulsRig-Spiele.ps1')
. (Get-AppCode 'PulsRig-Verschleiss.ps1')
. (Get-AppCode 'PulsRig-Eingabe.ps1')
. (Get-AppCode 'PulsRig-Verlauf.ps1')
. (Get-AppCode 'PulsRig-Abstuerze.ps1')
. (Get-AppCode 'PulsRig-Probezeit.ps1')
. (Get-AppCode 'PulsRig-Aenderungen.ps1')
. (Get-AppCode 'PulsRig-Spielcheck.ps1')
. (Get-AppCode 'PulsRig-Standby.ps1')
. (Get-AppCode 'PulsRig-Startseite.ps1')
. (Get-AppCode 'PulsRig-Problem.ps1')
. (Get-AppCode 'PulsRig-Akku.ps1')
. (Get-AppCode 'PulsRig-Monitor.ps1')
. (Get-AppCode 'PulsRig-Ping.ps1')
. (Get-AppCode 'PulsRig-Autostart.ps1')
. (Get-AppCode 'PulsRig-Strom.ps1')
. (Get-AppCode 'PulsRig-Helfer.ps1')
. (Get-AppCode 'PulsRig-Bento.ps1')   # Nacht-Bento: Weg-Leiste, Zurück-Knopf, Seitenumbau (nur in diesem Skin)
# Dauerbewegungen des Skins beginnen, sobald das Fenster zu sehen ist
if ($script:Skin.Start) { $window.Add_ContentRendered({ try { & $script:Skin.Start } catch { Write-AppError $_ } }) }

# --- Probelauf: Bildschirmfotos und Rundgang durch das Programm ----------------
if ($Snapshot) { . (Get-AppCode 'PulsRig-Probelauf.ps1') }

# --- Start --------------------------------------------------------------------

if ($Snapshot) {
    if (-not (Test-Path -LiteralPath $Snapshot)) { New-Item -ItemType Directory -Path $Snapshot -Force | Out-Null }
    # außerhalb des sichtbaren Bereichs, damit das Durchspielen niemanden stört
    $window.WindowStartupLocation = 'Manual'
    $window.Left = -4000
    $window.Top = 100
    $window.ShowInTaskbar = $false
}

try { [void]$window.ShowDialog() }
catch { Write-AppError $_ }
finally {
    $pump.Stop()
    $ramTimer.Stop()
    try { Stop-WorkerJob } catch { }
    try { $runspace.Dispose() } catch { }
}
# nach einem Skin-Wechsel gleich wieder da sein
if ($script:RestartAfterClose) { try { Start-AppAgain } catch { Write-AppError $_ } }
[Environment]::Exit(0)
