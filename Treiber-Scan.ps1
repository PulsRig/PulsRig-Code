<#
.SYNOPSIS
    Scannt die Hardware, sucht die neuesten Treiber und lädt sie herunter.

.DESCRIPTION
    1. Liest System, Geräte und installierte Treiber aus und meldet Geräte mit Treiberproblemen.
    2. Fragt Windows Update nach neueren Treibern (auch nach den "optionalen" Treiberupdates)
       und bei NVIDIA-Grafikkarten zusätzlich direkt NVIDIA nach der aktuellen Version.
       Zusätzlich durchsucht es den Microsoft-Katalog nach neueren Versionen, die Windows Update
       nicht von sich aus anbietet - diese werden nur als Hinweis mit Link gemeldet, nicht geladen.
    3. Lädt die gefundenen Treiber herunter und legt sie entpackt im Ordner "Treiber" ab.
    4. Installiert sie optional (-Install); vorher wird ein Wiederherstellungspunkt gesetzt.

    Quellen sind ausschließlich Microsoft (WHQL-signierte Herstellertreiber) und nvidia.com.
    Die NVIDIA-Datei wird nur behalten, wenn ihre digitale Signatur von NVIDIA stammt.

    Adminrechte fordert das Skript selbst an (UAC-Abfrage), sobald es sie braucht.

.PARAMETER ScanOnly
    Nur scannen und verfügbare Treiber anzeigen, nichts herunterladen (keine Adminrechte nötig).

.PARAMETER Install
    Heruntergeladene Treiber anschließend auch installieren.

.PARAMETER Backup
    Vorher alle installierten Treiber von Drittherstellern in den Zielordner sichern.

.PARAMETER IncludeFirmware
    Mit -Install auch Firmware-/BIOS-Updates installieren (werden sonst nur heruntergeladen).

.PARAMETER NoRestorePoint
    Vor der Installation keinen Wiederherstellungspunkt erstellen.

.PARAMETER NoAutoBackup
    Vor der Installation die Treiber, die ersetzt werden, nicht automatisch sichern.

.PARAMETER NoVendorCheck
    Nicht bei NVIDIA nachfragen, nur Windows Update verwenden.

.PARAMETER NoCatalogCheck
    Den Microsoft-Katalog nicht nach Versionen durchsuchen, die Windows Update nicht anbietet.

.PARAMETER Exclude
    Treiber überspringen, deren Titel den Text enthält (Platzhalter * und ? möglich), z.B. -Exclude Realtek,Bluetooth

.PARAMETER OutDir
    Zielordner für Bericht, Protokoll und Treiberdateien (Standard: Unterordner "Treiber").

.PARAMETER Tool
    Statt der Treibersuche eines der Werkzeuge starten:
      Backup               Treiber sichern
      Restore              Treiber aus einer Sicherung wieder einspielen (-BackupPath wählt den Ordner)
      FixAudio             Tonstörung beheben
      FixDevices           Gerätefehler beheben
      CleanDevices         Einträge nicht mehr angeschlossener Geräte entfernen
      FixNetwork           Netzwerkfehler beheben
      FixResolution        Schlechte Bildauflösung beheben
      GameRuntimes         Fehlende Spiel-DLLs (Visual C++, DirectX, XNA) prüfen und nachinstallieren
      IncompatibleDrivers  Treiber finden, die sich nicht mit der Kernisolierung vertragen
      OfflinePackage       Treiberpaket für einen PC ohne Internet erstellen
      SystemInfo           Ausführliche Systeminformationen anzeigen und speichern
      GameBoost            Spiel-Beschleunigung ein- bzw. wieder ausschalten (Energieplan, entbehrliche
                           Dienste, auf Wunsch speicherhungrige Programme schließen)
    Jedes Werkzeug prüft zuerst nur und fragt nach, bevor es etwas ändert.

.PARAMETER Menu
    Auswahlmenü mit Treibersuche und allen Werkzeugen anzeigen (so startet die .bat per Doppelklick).

.PARAMETER DryRun
    Probelauf: nur prüfen und anzeigen, was getan würde - nichts herunterladen oder verändern.

.PARAMETER Yes
    Rückfragen der Werkzeuge automatisch bejahen. Riskantere Zusatzschritte bleiben trotzdem aus.

.PARAMETER BackupPath
    Ordner der Sicherung für -Tool Restore (Standard: die neueste im Zielordner).

.PARAMETER WaitAtEnd
    Fenster am Ende offen halten, bis die Eingabetaste gedrückt wird.

.EXAMPLE
    .\Treiber-Scan.ps1 -ScanOnly
.EXAMPLE
    .\Treiber-Scan.ps1 -Install -Backup
.EXAMPLE
    .\Treiber-Scan.ps1 -Tool FixNetwork -DryRun
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ScanOnly,
    [switch]$Install,
    [switch]$Backup,
    [switch]$IncludeFirmware,
    [switch]$NoRestorePoint,
    [switch]$NoAutoBackup,
    [switch]$NoVendorCheck,
    [switch]$NoCatalogCheck,
    [string[]]$Exclude,
    [string]$OutDir,
    [ValidateSet('Backup', 'Restore', 'FixAudio', 'FixDevices', 'CleanDevices', 'FixNetwork', 'FixResolution',
        'GameRuntimes', 'IncompatibleDrivers', 'OfflinePackage', 'SystemInfo', 'GameBoost', 'CleanDisk')]
    [string]$Tool,
    [switch]$Menu,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$BackupPath,
    [switch]$WaitAtEnd,
    # intern: markiert den Neustart mit Adminrechten
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$script:BoundParameters = $PSBoundParameters
$script:ExitCode = 0

# --- Hilfsfunktionen ----------------------------------------------------------

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Get-ConsoleWidth {
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -ge 80) { return $width - 1 }
    }
    catch { }
    160
}

function Show-Table($Rows) {
    $Rows | Format-Table -AutoSize -Wrap | Out-String -Width ([math]::Max(110, (Get-ConsoleWidth))) |
        ForEach-Object { Write-Host $_.Trim("`r", "`n") }
}

# Die Auswertung (Texte, Titel, Seiten von Katalog, NVIDIA und AMD) steckt in PulsRig.Core.dll; Import-PulsRigCore
# steht in Treiber-Werkzeuge.ps1, das immer mitgeladen wird.
function Limit-Text([string]$Text, [int]$MaxLength) {
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::LimitText($Text, $MaxLength)
}

function Format-Date($Value) {
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::FormatDate($(if ($Value) { [datetime]$Value } else { $null }))
}

function Format-DriverText($Version, $Date) {
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::FormatDriverText("$Version", $(if ($Date) { [datetime]$Date } else { $null }))
}

function Get-SafeName([string]$Text, [int]$MaxLength = 80) {
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::SafeName($Text, $MaxLength)
}

function Get-RegistryValue([string]$Path, [string]$Name) {
    try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Baut die Parameter dieses Aufrufs für den Neustart mit Adminrechten wieder zusammen
function Get-ForwardArguments($Bound) {
    foreach ($key in $Bound.Keys) {
        $value = $Bound[$key]
        if ($value -is [switch]) {
            if ($value) { "-$key" }
            continue
        }
        $text = if ($value -is [array]) { $value -join ',' } else { [string]$value }
        # ein Backslash vor dem schließenden Anführungszeichen würde dieses sonst maskieren
        $text = $text -replace '(\\+)$', '$1$1'
        "-$key"
        '"{0}"' -f $text
    }
}

function Get-UpdateErrorText($ErrorRecord) {
    $exception = $ErrorRecord.Exception.GetBaseException()
    if ($exception -isnot [Runtime.InteropServices.COMException]) { return $exception.Message.Trim() }
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::UpdateError($exception.HResult, $exception.Message)
}

# --- 1. Hardware-Scan ---------------------------------------------------------

function Show-SystemInfo {
    $system = Get-CimInstance Win32_ComputerSystem
    $board = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })

    # Selbstbau-PCs tragen hier nur Platzhalter des Mainboard-Herstellers
    if ($system.Manufacturer -notmatch 'To Be Filled|System manufacturer|Default string') {
        Write-Host ("System:      {0} {1}" -f $system.Manufacturer, $system.Model)
    }
    Write-Host ("Mainboard:   {0} {1}" -f $board.Manufacturer, $board.Product)
    Write-Host ("BIOS:        {0} ({1})" -f $bios.SMBIOSBIOSVersion, (Format-Date $bios.ReleaseDate))
    Write-Host ("Prozessor:   {0}" -f $cpu.Name.Trim())
    Write-Host ("RAM:         {0} GB" -f [math]::Round($system.TotalPhysicalMemory / 1GB))
    Write-Host ("Grafik:      {0}" -f ($gpus -join ', '))
    Write-Host ("Windows:     {0} (Build {1})" -f $os.Caption, $os.BuildNumber)
}

# WMI vertauscht bei deutschem Datumsformat Tag und Monat (aus 04/07 wird der 4. Juli) -
# das Treiberdatum deshalb direkt aus der Registry lesen
function Get-DriverDate($Driver) {
    try {
        $enumKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($Driver.DeviceID)"
        $driverKey = (Get-ItemProperty -LiteralPath $enumKey -Name Driver -ErrorAction Stop).Driver
        $values = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey" -ErrorAction Stop
        if ($values.DriverDateData) {
            return [datetime]::FromFileTimeUtc([BitConverter]::ToInt64($values.DriverDateData, 0))
        }
        if ($values.DriverDate) {
            return [datetime]::ParseExact($values.DriverDate, 'M-d-yyyy', [cultureinfo]::InvariantCulture)
        }
    }
    catch { }
    $Driver.DriverDate
}

function Get-InstalledDrivers {
    Get-CimInstance Win32_PnPSignedDriver |
        Where-Object { $_.DeviceName -and $_.DriverVersion } |
        ForEach-Object { $_ | Add-Member -NotePropertyName ActualDate -NotePropertyValue (Get-DriverDate $_) -PassThru } |
        Sort-Object DeviceClass, DeviceName
}

function Show-InstalledDrivers($Installed) {
    $thirdParty = @($Installed | Where-Object {
            $_.DriverProviderName -and $_.DriverProviderName -notlike 'Microsoft*' })
    Write-Host ''
    Write-Host ("Geräte mit Treiber: {0}, davon {1} mit Treibern von Drittherstellern:" -f
        @($Installed).Count, $thirdParty.Count)

    # gleiche Einträge (z.B. mehrere PCI-Brücken) zu einer Zeile zusammenfassen
    $rows = $thirdParty | Group-Object DeviceClass, DeviceName, DriverProviderName, DriverVersion |
        ForEach-Object {
            $driver = $_.Group[0]
            $name = $driver.DeviceName
            if ($_.Count -gt 1) { $name = '{0} (x{1})' -f $name, $_.Count }
            # bewusst schmal gehalten: zu breite Tabellen verlieren in der Konsole Spalten (Klasse steht im Bericht)
            [pscustomobject]@{
                'Gerät'    = Limit-Text $name 50
                Hersteller = Limit-Text $driver.DriverProviderName 24
                Version    = $driver.DriverVersion
                Datum      = Format-Date $driver.ActualDate
            }
        } | Sort-Object 'Gerät', Version
    Show-Table $rows
}

# Gehört ein Gerät ohne Treiber (Code 28) zum Chipsatz? Nach einer frischen Windows-Installation fehlt oft der
# Chipsatz-Treiber des Mainboards; im Geräte-Manager stehen dann namenlose Einträge wie "SM-Bus-Controller" oder
# "PCI-Gerät". Erkannt wird es am Hersteller in der Gerätekennung (Intel, AMD) und am allgemeinen Namen - Grafik,
# Netzwerk und Ton heißen anders und fallen nicht darunter.
function Test-ChipsetDevice([string]$Name, [int]$Code, [string]$DeviceId) {
    Import-PulsRigCore
    [PulsRig.Core.ScanGeraete]::IsChipsetDevice($Name, $Code, $DeviceId)
}

# Wo es den Chipsatz-Treiber gibt: beim Hersteller des Mainboards, bei Fertig-PCs und Notebooks beim Hersteller des
# Geräts. Deren Seiten sind je Modell verschieden - verlinkt wird deshalb eine Suche nach Modell und Treiber.
function Get-BoardDriverSearch([string]$SystemMaker, [string]$SystemModel, [string]$BoardMaker, [string]$BoardModel) {
    Import-PulsRigCore
    $search = [PulsRig.Core.ScanGeraete]::BoardDriverSearch($SystemMaker, $SystemModel, $BoardMaker, $BoardModel)
    if ($search) { @{ Name = $search.Name; Url = $search.Url } }
}

# Fehlercodes des Geräte-Managers: Bedeutung und wo die Abhilfe liegt (Tabelle in PulsRig.Core, Geraetefehler)
function Get-DeviceError([int]$Code) {
    Import-PulsRigCore
    [PulsRig.Core.Geraetefehler]::Get($Code)
}

function Show-ProblemDevices {
    $problems = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    if ($problems.Count -eq 0) {
        Write-Host 'Keine Geräte mit Treiberproblemen gefunden.' -ForegroundColor Green
        return
    }
    Write-Host 'Geräte mit Problemen:' -ForegroundColor Yellow
    $rows = $problems | ForEach-Object {
        $code = [int]$_.ConfigManagerErrorCode
        $issue = Get-DeviceError $code
        [pscustomobject]@{
            'Gerät' = Limit-Text $(if ($_.Name) { $_.Name } else { $_.DeviceID }) 40
            Code    = $code
            Problem = $issue.Text
            Abhilfe = $issue.Advice
        }
    }
    Show-Table $rows
}

function Export-HardwareReport($Installed, [string]$OutDir) {
    $path = Join-Path $OutDir 'Hardware-Bericht.csv'
    $Installed |
        Select-Object DeviceClass, DeviceName, Manufacturer, DriverProviderName, DriverVersion,
            @{ n = 'DriverDate'; e = { if ($_.ActualDate) { $_.ActualDate.ToString('yyyy-MM-dd') } } },
            HardWareID, InfName |
        Export-Csv -LiteralPath $path -NoTypeInformation -UseCulture -Encoding UTF8
    $path
}

function Backup-InstalledDrivers([string]$OutDir) {
    $target = Join-Path $OutDir ('Backup_{0:yyyy-MM-dd_HHmm}' -f (Get-Date))
    if ($DryRun) {
        Write-Host "  [Probelauf] Treiber exportieren nach $target" -ForegroundColor DarkGray
        return
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host 'Exportiere alle Treiber von Drittherstellern (kann einige Minuten dauern) ...'
    & pnputil.exe /export-driver * $target | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Die Sicherung ist fehlgeschlagen (pnputil-Code $LASTEXITCODE)." -ForegroundColor Red
        $script:ExitCode = 1
        return
    }
    Write-Host "Sicherung gespeichert: $target" -ForegroundColor Green
    Write-Host "Zurückspielen bei Bedarf: pnputil /add-driver `"$target\*.inf`" /subdirs /install"
}

# --- 2. Suche -----------------------------------------------------------------

function Get-DriverPolicyHint {
    $excluded = Get-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate'
    $searchOrder = Get-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'SearchOrderConfig'
    if ($null -eq $searchOrder) {
        $searchOrder = Get-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig'
    }
    if ($excluded -eq 1 -or $searchOrder -eq 0) {
        'Hinweis: Auf diesem PC sind Treiber über Windows Update per Einstellung/Richtlinie abgeschaltet - deshalb findet die Suche evtl. nichts.'
    }
}

function Invoke-UpdateSearch($Session, [string]$Criteria) {
    $firstError = $null
    # 2 = direkt bei Microsoft suchen (umgeht z.B. einen Firmen-WSUS), 0 = Standardquelle des Systems
    foreach ($selection in 2, 0) {
        try {
            $searcher = $Session.CreateUpdateSearcher()
            $searcher.ServerSelection = $selection
            return $searcher.Search($Criteria)
        }
        catch {
            if (-not $firstError) { $firstError = $_ }
        }
    }
    throw $firstError
}

function Find-DriverUpdates($Session) {
    $base = "IsInstalled=0 and IsHidden=0 and Type='Driver'"
    $queries = @(
        @{ Criteria = $base; Optional = $false },
        # die "optionalen Updates" aus den Windows-Einstellungen liefert nur eine eigene Abfrage
        @{ Criteria = "$base and DeploymentAction='OptionalInstallation'"; Optional = $true }
    )
    $seen = @{}
    foreach ($query in $queries) {
        try {
            $result = Invoke-UpdateSearch $Session $query.Criteria
        }
        catch {
            # ältere Windows-Versionen kennen das Kriterium für optionale Updates nicht
            if ($query.Optional) { continue }
            throw
        }
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            $update = $result.Updates.Item($i)
            $id = $update.Identity.UpdateID
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            [pscustomobject]@{ Update = $update; Optional = $query.Optional; Id = $id }
        }
    }
}

# --- Grafiktreiber vor Windows Update schützen ---------------------------------
# Gezielt und umkehrbar: Windows Update bekommt keine Sperre und keine Richtlinie, sondern seine Angebote für die
# geschützte Grafikkarte werden versteckt (wie mit Microsofts "Updates anzeigen oder ausblenden"). Versteckte
# Updates spielt Windows nicht von selbst ein; Freigeben macht sie wieder sichtbar. Treiber direkt von NVIDIA oder
# AMD und alle anderen Geräte bleiben unberührt. Neue Angebote versteckt der nächste Scan oder der Wochenscan.
# Schlüssel einer Grafikkarte: "PCI\VEN_xxxx&DEV_xxxx" aus ihrer Geräte-ID.
function Get-GpuShieldKey([string]$HardwareId) {
    Import-PulsRigCore
    [PulsRig.Core.ScanGeraete]::GpuShieldKey($HardwareId)
}

function Get-ShieldGpus {
    $seen = @{}
    foreach ($gpu in @(Get-CimInstance Win32_VideoController)) {
        $key = Get-GpuShieldKey "$($gpu.PNPDeviceID)"
        if (-not $key -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        @{ Key = $key; Name = "$($gpu.Name)"; Version = "$($gpu.DriverVersion)" }
    }
}

# Angebote von Windows Update für diese Grafikkarten (Klasse Display, Geräte-ID passt), versteckt oder sichtbar
function Find-GpuDriverOffers($Session, [string[]]$Keys, [bool]$Hidden) {
    if (-not @($Keys).Count) { return }
    $result = Invoke-UpdateSearch $Session "IsInstalled=0 and IsHidden=$([int]$Hidden) and Type='Driver'"
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        if ("$($update.DriverClass)" -notin 'Display', 'Video') { continue }
        if ($Keys -contains (Get-GpuShieldKey "$($update.DriverHardwareID)")) { $update }
    }
}

# versteckt (On) oder zeigt wieder (aus) alle passenden Angebote; Ergebnis: ihre Titel
function Set-GpuShield($Session, [string[]]$Keys, [bool]$On) {
    foreach ($update in @(Find-GpuDriverOffers $Session $Keys (-not $On))) {
        $update.IsHidden = $On
        "$($update.Title)"
    }
}

# Windows Update nennt Treiber in der Form "Hersteller - Art - Version" (manchmal mit einem Datum dazwischen), die Art
# in Kürzeln wie "LCD" oder "MEDIA". Für die Anzeige: Kürzel übersetzt, Datum weggelassen (es steht in der Zeile darunter).
function Format-UpdateTitle([string]$Title) {
    Import-PulsRigCore
    [PulsRig.Core.ScanText]::FormatUpdateTitle($Title)
}

# Name des Geräts zu einer Hardware-Kennung aus Windows Update. Die Kennung dort ist oft nur ein Teil der vollen
# ("vid_04f9&pid_04bb&netscn"), deshalb zählt auch, wenn eine Kennung des Geräts sie enthält.
function Find-DeviceName([string]$HardwareId, $Devices) {
    Import-PulsRigCore
    $list = @($Devices)
    $ids = New-Object 'System.Collections.Generic.List[string[]]'
    foreach ($device in $list) { $ids.Add([string[]]@($device.HardwareID | ForEach-Object { "$_" })) }
    [PulsRig.Core.Zuordnung]::DeviceName($HardwareId, $ids, [string[]]@($list | ForEach-Object { "$($_.Name)" }))
}

function Find-InstalledDriver([string]$HardwareId, $Installed) {
    Import-PulsRigCore
    $list = @($Installed)
    $index = [PulsRig.Core.Zuordnung]::InstalledDriver($HardwareId, [string[]]@($list | ForEach-Object { "$($_.HardWareID)" }))
    if ($index -ge 0) { $list[$index] }
}

function Test-IsFirmware($Update) {
    $Update.DriverClass -eq 'Firmware' -or $Update.Title -match 'Firmware|BIOS|UEFI'
}

function Test-Excluded([string]$Title, [string[]]$Patterns) {
    Import-PulsRigCore
    [PulsRig.Core.Zuordnung]::IsExcluded($Title, $Patterns)
}

function Show-Updates($Items, $Installed) {
    $number = 0
    foreach ($item in $Items) {
        $update = $item.Update
        $number++
        $notes = @()
        if ($item.Optional) { $notes += 'optional' }
        if (Test-IsFirmware $update) { $notes += 'Firmware' }
        $suffix = if ($notes) { '  [{0}]' -f ($notes -join ', ') } else { '' }

        $current = Find-InstalledDriver $update.DriverHardwareID $Installed
        $currentText = if ($current) { Format-DriverText $current.DriverVersion $current.ActualDate } else { 'unbekannt' }
        $sizeText = if ($update.MaxDownloadSize -gt 0) { '{0:N1} MB' -f ($update.MaxDownloadSize / 1MB) } else { 'unbekannt' }

        Write-Host ('{0,3}. {1}{2}' -f $number, $update.Title, $suffix)
        Write-Host ('     installiert: {0}   |   neu vom: {1}   |   Größe: {2}' -f
            $currentText, (Format-Date $update.DriverVerDate), $sizeText) -ForegroundColor DarkGray
    }
}

# Windows meldet z.B. 32.0.16.1742, NVIDIA nennt dieselbe Version 617.42 (die letzten fünf Ziffern)
function ConvertTo-NvidiaVersion([string]$WindowsVersion) {
    Import-PulsRigCore
    [PulsRig.Core.Hersteller]::NvidiaVersion($WindowsVersion)
}

function Get-NvidiaUpdate {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) { return }
    # NVIDIA führt neuere Karten (ab RTX 40) in der Liste mit "NVIDIA" davor, ältere ohne: auf beiden Seiten ohne vergleichen
    $plain = { param($name) ("$name" -replace '^\s*NVIDIA\s+', '' -replace '\s+', ' ').Trim() }
    $product = & $plain $gpu.Name
    $installed = ConvertTo-NvidiaVersion $gpu.DriverVersion

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $lookup = 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx'

    $response = Invoke-WebRequest -UseBasicParsing -Uri ($lookup + '?TypeID=3') -TimeoutSec 30
    $hits = @(([xml]$response.Content).LookupValueSearch.LookupValues.LookupValue |
            Where-Object { (& $plain $_.Name) -eq $product })
    if ($hits.Count -eq 0) { throw "Das Modell '$product' steht nicht in der NVIDIA-Produktliste." }
    $hit = $hits[0]
    if ($hits.Count -gt 1) {
        # gleicher Name in Desktop- und Notebook-Serie: der Akku entscheidet
        $response = Invoke-WebRequest -UseBasicParsing -Uri ($lookup + '?TypeID=2') -TimeoutSec 30
        $notebookSeries = @(([xml]$response.Content).LookupValueSearch.LookupValues.LookupValue |
                Where-Object { $_.Name -match 'Notebook' } | ForEach-Object { $_.Value })
        $isNotebook = [bool](Get-CimInstance Win32_Battery)
        $preferred = $hits | Where-Object { ($notebookSeries -contains $_.ParentID) -eq $isNotebook } |
            Select-Object -First 1
        if ($preferred) { $hit = $preferred }
    }

    $osId = if ([Environment]::OSVersion.Version.Build -ge 22000) { 135 } else { 57 }   # Windows 11 / 10 (64 Bit)
    $query = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
        "?func=DriverManualLookup&psid=$($hit.ParentID)&pfid=$($hit.Value)&osID=$osId" +
        '&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=0&sort1=0&numberOfResults=1'
    $result = Invoke-RestMethod -Uri $query -TimeoutSec 30
    if ("$($result.Success)" -ne '1' -or -not $result.IDS) { throw 'NVIDIA hat keinen passenden Treiber gemeldet.' }
    $info = $result.IDS[0].downloadInfo

    $released = $info.ReleaseDateTime
    try { $released = Format-Date ([datetime]::Parse($info.ReleaseDateTime, [cultureinfo]::InvariantCulture)) } catch { }
    $isNewer = $false
    try { $isNewer = $installed -and ([version]$info.Version -gt [version]$installed) } catch { }

    [pscustomobject]@{
        Gpu       = $gpu.Name
        # "Game Ready" ist NVIDIAs auf neue Spiele abgestimmte Treiberlinie - nach ihr wird gefragt (upCRD=0)
        Kind      = if ("$($info.Name)" -match 'Game(%20| )Ready') { 'Game Ready' } else { 'Treiber' }
        Installed = $installed
        Latest    = $info.Version
        Released  = $released
        Size      = $info.DownloadURLFileSize
        Url       = $info.DownloadURL
        IsNewer   = [bool]$isNewer
    }
}

# Chipsatz-Treiber von AMD: Sie gehören zu Mainboard und Prozessor (Energieverwaltung, PCI, SMBus, PSP, GPIO) und
# kommen als ein Paket, das Windows Update nur in Teilen und oft spät liefert. AMD nennt die neueste Version auf der
# Support-Seite des Chipsatzes; das Paket ist für alle aktuellen Sockel dasselbe. Nur Hinweis, nichts wird geladen.
function Get-AmdChipsetUpdate {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ("$($cpu.Manufacturer) $($cpu.Name)" -notmatch 'AMD') { return }
    $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    Import-PulsRigCore
    # der Chipsatz steht im Namen des Mainboards, sonst genügt der Sockel
    $found = [PulsRig.Core.Hersteller]::AmdChipset("$($board.Product)", "$($cpu.SocketDesignation)")
    if (-not $found) { return }
    $chipset = $found.Chipset
    $page = $found.Url

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # gelesen wird die englische Seite (feste Beschriftungen), gezeigt wird dem Nutzer die deutsche
    $response = Invoke-WebRequest -UseBasicParsing -Uri ($page -replace '/de/support/', '/en/support/') -TimeoutSec 30
    $latest = [PulsRig.Core.Hersteller]::AmdChipsetLatest("$($response.Content)")
    if (-not $latest) { throw 'Die Seite von AMD nennt keine Version - vermutlich wurde sie umgebaut.' }
    $size, $released = [PulsRig.Core.Hersteller]::AmdChipsetDetails("$($response.Content)", $latest)

    # installiert: das Paket trägt sich unter beiden Namen ein, ältere Einträge bleiben stehen - es zählt der höchste
    $installed = $null; $installedText = ''
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($entry in @(Get-ItemProperty $roots -ErrorAction SilentlyContinue | Where-Object { "$($_.DisplayName)" -match '^AMD[ _]Chipset[ _](Software|Drivers)$' })) {
        try { $version = [version]"$($entry.DisplayVersion)" } catch { continue }
        if (-not $installed -or $version -gt $installed) { $installed = $version; $installedText = "$($entry.DisplayVersion)" }
    }
    $isNewer = $false
    try { $isNewer = -not $installed -or ([version]$latest -gt $installed) } catch { }

    [pscustomobject]@{
        Chipset   = $chipset
        Board     = ("$($board.Manufacturer) $($board.Product)").Trim()
        Cpu       = ("$($cpu.Name)" -replace '\s+', ' ').Trim()
        Installed = $installedText
        Latest    = $latest
        Released  = $released
        Size      = $size
        Url       = $page
        IsNewer   = [bool]$isNewer
    }
}

# Grafiktreiber von AMD (Adrenalin): AMD nennt die neueste Fassung auf der Seite der Karte. Die Adresse folgt aus dem
# Namen (RX 5000 bis 9000, Vega); für ältere Karten und Prozessorgrafik gibt es kein festes Muster - dann $null und es
# bleibt beim Hinweis auf AMDs Software. Nur Hinweis, nichts wird geladen.
function Get-RadeonPage([string]$GpuName) {
    Import-PulsRigCore
    [PulsRig.Core.Hersteller]::RadeonPage($GpuName)
}

function Get-RadeonUpdate {
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Radeon' } |
        Where-Object { Get-RadeonPage $_.Name } | Select-Object -First 1
    if (-not $gpu) { return }
    $page = Get-RadeonPage $gpu.Name

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -UseBasicParsing -Uri ($page -replace '/de/support/', '/en/support/') -TimeoutSec 30
    $latest = [PulsRig.Core.Hersteller]::RadeonLatest("$($response.Content)")
    if (-not $latest) { throw 'Die Seite von AMD nennt keine Version - vermutlich wurde sie umgebaut.' }
    $released = [PulsRig.Core.Hersteller]::ReleaseDate("$($response.Content)")

    # installiert: Windows nennt nur die interne Treiberversion, die Adrenalin-Fassung steht im Schlüssel des Treibers
    $installed = ''
    try {
        $driverKey = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.PNPDeviceID)" -ErrorAction Stop).Driver
        $class = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey" -ErrorAction Stop
        $installed = "$($class.RadeonSoftwareVersion)".Trim()
    }
    catch { }
    $isNewer = $false
    try { $isNewer = $installed -and ([version]$latest -gt [version]$installed) } catch { }

    [pscustomobject]@{
        Gpu       = [PulsRig.Core.Hersteller]::GpuName("$($gpu.Name)")
        Installed = $installed
        Latest    = $latest
        Released  = $released
        Url       = $page
        IsNewer   = [bool]$isNewer
    }
}

# --- Microsoft-Katalog: nur Hinweise, nichts wird geladen ---------------------

# Macht aus der Hardware-ID eines Geräts den Suchbegriff für den Katalog, z.B.
# PCI\VEN_1022&DEV_790B&SUBSYS_FFFF1849&REV_59 -> VEN_1022&DEV_790B
function Get-CatalogQuery([string]$HardwareId) {
    Import-PulsRigCore
    [PulsRig.Core.Katalog]::Query($HardwareId)
}

function Get-CatalogUrl([string]$Query) {
    Import-PulsRigCore
    [PulsRig.Core.Katalog]::Url($Query)
}

# Liest die erste Trefferseite (neueste zuerst) aus der Katalog-Webseite
function Search-DriverCatalog([string]$Query) {
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -UseBasicParsing -Uri (Get-CatalogUrl $Query) -TimeoutSec 20 `
        -Headers @{ 'Accept-Language' = 'en-US' }
    Import-PulsRigCore
    [PulsRig.Core.Katalog]::ParseRows("$($response.Content)")
}

# Wählt den Katalogeintrag, der sicher zur selben Treiberlinie gehört und neuer ist - sonst nichts
function Select-CatalogCandidate($Driver, $Rows, [string]$OsName) {
    Import-PulsRigCore
    [PulsRig.Core.KatalogAuswahl]::Candidate("$($Driver.DriverVersion)", "$($Driver.DriverProviderName)",
        $(if ($Driver.ActualDate) { [datetime]$Driver.ActualDate } else { $null }), (ConvertTo-CatalogRows $Rows), $OsName)
}

# Treffer als PulsRig.Core.KatalogTreffer - auch solche aus dem Zwischenspeicher oder aus den Tests
function ConvertTo-CatalogRows($Rows) {
    Import-PulsRigCore
    $list = New-Object 'System.Collections.Generic.List[PulsRig.Core.KatalogTreffer]'
    foreach ($row in @($Rows | Where-Object { $_ })) {
        if ($row -is [PulsRig.Core.KatalogTreffer]) { $list.Add($row); continue }
        $list.Add((New-Object PulsRig.Core.KatalogTreffer -Property @{ Id = "$($row.Id)"; Title = "$($row.Title)"; Products = "$($row.Products)"
                    Date = [datetime]$row.Date; Version = $(if ($row.Version) { [version]"$($row.Version)" } else { $null }); Size = "$($row.Size)"; Bytes = [long]$row.Bytes }))
    }
    , $list
}

# --- Treiber für Geräte ohne Treiber aus dem Microsoft-Katalog -----------------
# Für Geräte ohne Treiber (Code 28) bietet Windows Update oft nichts an, obwohl der Hersteller den Treiber im
# Microsoft-Katalog hinterlegt hat. Der Katalog nennt zu jedem Eintrag die Datei samt Prüfsumme; die Pakete sind
# von Microsoft signiert. Installiert wird nur auf ausdrückliche Bestätigung im Werkzeug "Gerätefehler beheben".

# Wählt unter den Treffern den neuesten, der zu dieser Windows-Fassung passt. $OsVersion ist z.B. "24H2":
# Einträge, die eine neuere Fassung verlangen ("version 24H2 and later" auf 22H2), scheiden aus.
function Select-MissingDriverRow($Rows, [string]$OsName, [string]$OsVersion) {
    # Firmware scheidet aus: sie wird nie nebenbei eingespielt. Reine Zusätze (Erweiterung, Zusatzsoftware) kommen
    # erst nach den eigentlichen Treibern - einem Gerät ohne Treiber helfen sie allein nicht.
    Import-PulsRigCore
    [PulsRig.Core.KatalogAuswahl]::MissingDriver((ConvertTo-CatalogRows $Rows), $OsName, $OsVersion)
}

function Find-MissingDriver([string]$HardwareId) {
    $query = Get-CatalogQuery $HardwareId
    if (-not $query) { return $null }
    $osName = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $osVersion = "$(Get-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion')"
    $row = Select-MissingDriverRow @(Search-DriverCatalog $query) $osName $osVersion
    if (-not $row) { return $null }
    [pscustomobject]@{ Id = $row.Id; Title = $row.Title; Version = "$($row.Version)"; Size = $row.Size; Query = $query }
}

# Fragt den Katalog nach Adresse und Prüfsumme der Datei zu einem Eintrag
function Get-CatalogDownload([string]$UpdateId) {
    if ($UpdateId -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') { throw 'Unerwartete Kennung im Katalog.' }
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $body = @{ updateIDs = '[{"size":0,"languages":"","uidInfo":"' + $UpdateId + '","updateID":"' + $UpdateId + '"}]' }
    $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Body $body -TimeoutSec 30
    $url = [regex]::Match($response.Content, "downloadInformation\[0\]\.files\[0\]\.url = '([^']+)'").Groups[1].Value
    $sha = [regex]::Match($response.Content, "downloadInformation\[0\]\.files\[0\]\.sha256 = '([^']+)'").Groups[1].Value
    if (-not $url) { throw 'Der Katalog nennt zu diesem Treiber keine Datei.' }
    @{ Url = $url; Sha256 = $sha }
}

# Lädt das Paket, prüft Adresse, Prüfsumme, Signatur und ob es zum Gerät gehört, und übergibt es Windows zum Installieren.
# Gearbeitet wird in einem eigenen Ordner, in den nur Administratoren und das System schreiben dürfen: so kann zwischen
# Prüfung und Installation niemand ohne Adminrechte etwas austauschen. Die Treibersignatur prüft Windows selbst noch einmal.
# Ist PulsRig unter "Programme" installiert, liegt der Ordner dort - da darf ohnehin nur ein Administrator schreiben.
# Sonst liegt er unter ProgramData; dort könnte jemand in dem Augenblick zwischen Anlegen und Sperren etwas hineinlegen,
# deshalb muss der Ordner nach dem Sperren leer sein.
function Install-CatalogDriver($Found) {
    $info = Get-CatalogDownload $Found.Id
    $uri = [uri]$info.Url
    $hosts = '*.windowsupdate.com', '*.delivery.mp.microsoft.com', 'download.microsoft.com'
    if ($uri.Scheme -ne 'https' -or -not ($hosts | Where-Object { $uri.Host -like $_ }) -or $uri.AbsolutePath -notlike '*.cab') {
        throw "Unerwartete Adresse: $($info.Url)"
    }
    # der Ordner des Programms: der dieses Skripts oder, wenn es in PulsRig.exe steckt, der von PulsRig-Arbeit-Start.ps1 genannte
    $own = if ("$PSScriptRoot") { "$PSScriptRoot" } else { "$global:DD_ProgramDir" }
    $base = if ($own -and $own.StartsWith("$env:ProgramFiles\", [StringComparison]::OrdinalIgnoreCase)) { $own } else { Join-Path $env:ProgramData 'PulsRig' }
    $folder = Join-Path $base ('Katalog-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    try {
        Invoke-Native icacls.exe @($folder, '/inheritance:r', '/grant:r', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F') | Out-Null
        if (@(Get-ChildItem -LiteralPath $folder -Force).Count -gt 0) { throw 'Im Arbeitsordner liegt etwas, das nicht von PulsRig stammt - abgebrochen.' }
        $cab = Join-Path $folder 'Treiber.cab'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $uri.AbsoluteUri -OutFile $cab -TimeoutSec 600
        $stream = [IO.File]::OpenRead($cab)
        try { $hash = [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($stream)) } finally { $stream.Dispose() }
        if (-not $info.Sha256 -or $hash -cne $info.Sha256) { throw 'Die geladene Datei ist nicht die, die der Katalog nennt (Prüfsumme weicht ab).' }
        if (-not (Test-FileSigner $cab 'O=Microsoft Corporation')) { throw 'Die geladene Datei trägt keine gültige Signatur von Microsoft und wurde verworfen.' }
        $files = Join-Path $folder 'Dateien'
        New-Item -ItemType Directory -Path $files -Force | Out-Null
        & (Join-Path $env:SystemRoot 'System32\expand.exe') $cab '-F:*' $files | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Das Paket ließ sich nicht entpacken (Code $LASTEXITCODE)." }
        $infs = @(Get-ChildItem -LiteralPath $files -Filter '*.inf' -File -Recurse)
        if (-not ($infs | Where-Object { [IO.File]::ReadAllText($_.FullName) -match [regex]::Escape($Found.Query) })) {
            throw 'Das Paket nennt dieses Gerät nicht und wurde verworfen.'
        }
        # 3010 = Neustart nötig, 259 = hinzugefügt, aber kein Gerät hat ihn übernommen (zeigt die Prüfung danach)
        Invoke-Native pnputil.exe @('/add-driver', (Join-Path $files '*.inf'), '/subdirs', '/install') @(0, 3010, 259) | Out-Null
    }
    finally { Remove-Item -LiteralPath $folder -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
}

function Find-CatalogHints($Installed) {
    $osName = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    $services = @{}
    Get-CimInstance Win32_PnPEntity | ForEach-Object { $services[$_.DeviceID] = $_.Service }

    $groups = @{}
    foreach ($driver in $Installed) {
        if (-not $driver.HardWareID -or -not $driver.DriverProviderName -or $driver.DriverProviderName -like 'Microsoft*') { continue }
        $query = Get-CatalogQuery $driver.HardWareID
        if (-not $query) { continue }
        if (-not $groups.ContainsKey($query)) { $groups[$query] = @() }
        $groups[$query] += $driver
    }

    # Antworten des Katalogs gelten einen Tag: ein zweiter Scan am selben Tag fragt nur noch nach, was fehlt.
    # Die Datei enthält nur Titel, Datum, Version und Größe der Treffer - die Adressen baut das Programm selbst.
    $cachePath = Join-Path $env:TEMP 'PulsRig-Katalog.json'
    $cache = @{}
    try {
        if (Test-Path -LiteralPath $cachePath) {
            $saved = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $saved.PSObject.Properties) {
                $stamp = [datetime]::ParseExact("$($property.Value.Time)", 'yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
                if ($stamp -gt (Get-Date) -or ((Get-Date) - $stamp).TotalHours -ge 24) { continue }
                $cache[$property.Name] = @{ Time = "$($property.Value.Time)"; Rows = (ConvertTo-CatalogRows @($property.Value.Rows | Where-Object { $_ } | ForEach-Object {
                                [pscustomobject]@{ Title = "$($_.Title)"; Products = "$($_.Products)"; Size = "$($_.Size)"; Bytes = [long]$_.Bytes
                                    Date = [datetime]::ParseExact("$($_.Date)", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture); Version = [version]"$($_.Version)" }
                            }))
                }
            }
        }
    }
    catch { $cache = @{} }

    $index = 0
    $failures = 0
    $rowsSeen = 0
    foreach ($query in @($groups.Keys | Sort-Object)) {
        $index++
        Write-Progress -Activity 'Microsoft-Katalog' -Status "$index von $($groups.Count): $query" `
            -PercentComplete (($index - 1) / $groups.Count * 100)
        if ($cache.ContainsKey($query)) { $rows = @($cache[$query].Rows) }
        else {
            try {
                $rows = @(Search-DriverCatalog $query)
                $failures = 0
                $cache[$query] = @{ Time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Rows = $rows }
            }
            catch {
                $failures++
                if ($failures -ge 3) {
                    Write-Progress -Activity 'Microsoft-Katalog' -Completed
                    throw "Der Katalog antwortet nicht ($($_.Exception.Message))."
                }
                continue
            }
        }
        $rowsSeen += $rows.Count
        foreach ($driver in $groups[$query]) {
            $entry = Select-CatalogCandidate $driver $rows $osName
            if ($entry) {
                [pscustomobject]@{
                    Driver     = $driver
                    Entry      = $entry
                    Url        = Get-CatalogUrl "$($entry.Version) $query"
                    HasService = [bool]$services[$driver.DeviceID]
                }
            }
        }
    }
    Write-Progress -Activity 'Microsoft-Katalog' -Completed
    try {
        $keep = @{}
        foreach ($key in $cache.Keys) {
            $keep[$key] = @{ Time = $cache[$key].Time; Rows = @($cache[$key].Rows | ForEach-Object {
                        @{ Title = "$($_.Title)"; Products = "$($_.Products)"; Size = "$($_.Size)"; Bytes = [long]$_.Bytes; Date = $_.Date.ToString('yyyy-MM-dd'); Version = "$($_.Version)" }
                    })
            }
        }
        $keep | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8
    }
    catch { }
    if ($groups.Count -gt 0 -and $rowsSeen -eq 0) {
        throw 'Der Katalog lieferte keine auswertbaren Treffer - vermutlich wurde die Webseite umgebaut.'
    }
}

function Show-CatalogHints($Hints) {
    if (@($Hints).Count -eq 0) {
        Write-Host 'Microsoft-Katalog: keine neueren Versionen gefunden.' -ForegroundColor Green
        return
    }
    # ein Paket deckt oft mehrere Geräte ab - je Paket nur ein Eintrag
    $packages = @($Hints | Group-Object { '{0}|{1}' -f $_.Entry.Title, $_.Entry.Version })
    Write-Host ("Microsoft-Katalog: {0} neuere(s) Paket(e), die Windows Update nicht anbietet (nur Hinweis, nichts wird geladen):" -f
        $packages.Count) -ForegroundColor Yellow
    $number = 0
    foreach ($package in $packages) {
        $number++
        $entry = $package.Group[0].Entry
        Write-Host ('{0,3}. {1} vom {2}, {3}' -f $number, $entry.Title, (Format-Date $entry.Date), $entry.Size)
        foreach ($hint in $package.Group | Sort-Object { $_.Driver.DeviceName } -Unique) {
            Write-Host ('     für: {0} (installiert {1})' -f
                $hint.Driver.DeviceName, (Format-DriverText $hint.Driver.DriverVersion $hint.Driver.ActualDate)) -ForegroundColor DarkGray
        }
        # winziges Paket für ein Gerät ohne Treiberdienst = reine Gerätebeschreibung (INF ohne Treibercode)
        $isDescriptionOnly = $entry.Bytes -gt 0 -and $entry.Bytes -lt 200KB -and
            -not ($package.Group | Where-Object { $_.HasService })
        if ($isDescriptionOnly) {
            Write-Host '     Enthält keinen Treibercode - ein Update ändert voraussichtlich nur den Eintrag im Geräte-Manager.' -ForegroundColor DarkGray
        }
        Write-Host ('     {0}' -f $package.Group[0].Url) -ForegroundColor DarkGray
    }
    Write-Host '  Vor einer Installation prüfen, ob der Eintrag zu Gerät und Windows-Version passt.'
}

function Show-VendorHints {
    $gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name })
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $board = Get-CimInstance Win32_BaseBoard

    $hints = @()
    if ($cpu.Manufacturer -match 'AMD' -or ($gpus -match 'AMD|Radeon')) {
        $hints += 'AMD (Chipsatz, Radeon):  https://www.amd.com/de/support/download/drivers.html'
    }
    if ($cpu.Manufacturer -match 'Intel' -or ($gpus -match 'Intel')) {
        $hints += 'Intel (Chipsatz, Grafik, WLAN):  https://www.intel.de/content/www/de/de/support/detect.html'
    }
    $hints += '{0} {1} (Audio, LAN, BIOS):  Support-Seite des Mainboard-Herstellers' -f $board.Manufacturer, $board.Product

    Write-Host ''
    Write-Host 'Dort erscheinen neue Versionen oft früher als bei Windows Update (manuell prüfen):'
    $hints | ForEach-Object { Write-Host "  - $_" }
}

# --- 3. Download --------------------------------------------------------------

function Expand-CabFiles([string]$Folder) {
    foreach ($cab in @(Get-ChildItem -LiteralPath $Folder -Filter '*.cab' -File)) {
        $destination = Join-Path $Folder $cab.BaseName
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        & (Join-Path $env:SystemRoot 'System32\expand.exe') $cab.FullName '-F:*' $destination | Out-Null
        $extracted = @(Get-ChildItem -LiteralPath $destination)
        # ein Paket mit nur einer Datei legt expand.exe unter dem Namen der .cab ab - dann lieber das Original behalten
        if ($LASTEXITCODE -ne 0 -or $extracted.Count -eq 0 -or ($extracted.Count -eq 1 -and $extracted[0].Name -eq $cab.Name)) {
            Remove-Item -LiteralPath $destination -Recurse -Confirm:$false
            continue
        }
        Remove-Item -LiteralPath $cab.FullName -Confirm:$false
    }
}

# Kopiert das Treiberpaket aus dem Windows-Update-Cache in den Zielordner und entpackt es
function Export-UpdateFiles($Item, [string]$OutDir) {
    $folder = '{0}_{1}' -f (Get-SafeName $Item.Update.Title), $Item.Id.Substring(0, 8)
    $target = Join-Path $OutDir $folder
    if ((Test-Path -LiteralPath $target) -and @(Get-ChildItem -LiteralPath $target).Count -gt 0) {
        return $target   # schon bei einem früheren Lauf abgelegt
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $Item.Update.CopyFromCache($target, $false)
    Expand-CabFiles $target
    $target
}

function Save-DriverUpdates($Session, $Items, [string]$OutDir, $Stats) {
    $total = @($Items).Count
    $index = 0
    foreach ($item in $Items) {
        $update = $item.Update
        $index++
        Write-Progress -Activity 'Treiber-Download' -Status "$index von ${total}: $($update.Title)" `
            -PercentComplete (($index - 1) / $total * 100)

        if (-not $update.EulaAccepted) {
            Write-Host "Übersprungen (Lizenzvertrag muss in Windows Update bestätigt werden): $($update.Title)" -ForegroundColor Yellow
            continue
        }
        try {
            if (-not $update.IsDownloaded) {
                $collection = New-Object -ComObject Microsoft.Update.UpdateColl
                [void]$collection.Add($update)
                $downloader = $Session.CreateUpdateDownloader()
                $downloader.Updates = $collection
                $result = $downloader.Download()
                if (-not $update.IsDownloaded) {
                    throw ('Ergebniscode {0}, Fehler 0x{1:X8}' -f $result.ResultCode, $result.GetUpdateResult(0).HResult)
                }
            }
        }
        catch {
            Write-Host "Download fehlgeschlagen: $($update.Title) - $(Get-UpdateErrorText $_)" -ForegroundColor Red
            $Stats.Failed++
            continue
        }

        $Stats.Downloaded++
        Write-Host "Geladen: $($update.Title)" -ForegroundColor Green
        try {
            $folder = Export-UpdateFiles $item $OutDir
            Write-Host "         -> $folder"
        }
        catch {
            Write-Host '         (liegt nur im Windows-Update-Cache, die Kopie in den Zielordner ist fehlgeschlagen)' -ForegroundColor Yellow
        }
        $item   # bereit zur Installation
    }
    Write-Progress -Activity 'Treiber-Download' -Completed
}

function Test-NvidiaSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match 'O=NVIDIA Corporation'
}

# Startet einen geladenen Installer und wartet auf sein Ende. Die Datei ist dabei für andere gesperrt, und die
# Signatur wird erst unter dieser Sperre geprüft: so lässt sie sich zwischen Prüfung und Start nicht austauschen.
function Start-SignedInstaller([string]$Path, [string]$SignerPattern) {
    $lock = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $SignerPattern) {
            throw "Die Datei $(Split-Path -Leaf $Path) trägt keine gültige Signatur des Herstellers und wird nicht gestartet."
        }
        if ($Path -like '*.msi') { Start-Process -FilePath msiexec.exe -ArgumentList '/i', "`"$Path`"" -Wait }
        else { Start-Process -FilePath $Path -Wait }
    }
    finally { $lock.Dispose() }
}

function Save-NvidiaDriver($Info, [string]$OutDir) {
    $uri = [uri]$Info.Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -notlike '*.nvidia.com') {
        Write-Host "NVIDIA-Download abgelehnt: unerwartete Adresse $($Info.Url)" -ForegroundColor Red
        return
    }
    $file = Join-Path $OutDir ([IO.Path]::GetFileName($uri.LocalPath))
    if ((Test-Path -LiteralPath $file) -and (Test-NvidiaSignature $file)) {
        Write-Host "NVIDIA-Treiber $($Info.Latest) liegt bereits vor: $file" -ForegroundColor Green
        return $file
    }

    Write-Host "Lade NVIDIA-Treiber $($Info.Latest) ($($Info.Size)) ..."
    try {
        Start-BitsTransfer -Source $uri.AbsoluteUri -Destination $file -DisplayName "NVIDIA-Treiber $($Info.Latest)"
    }
    catch {
        # BITS steht z.B. in nicht-interaktiven Sitzungen nicht zur Verfügung
        $previous = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try { Invoke-WebRequest -UseBasicParsing -Uri $uri.AbsoluteUri -OutFile $file }
        finally { $ProgressPreference = $previous }
    }

    if (-not (Test-NvidiaSignature $file)) {
        Remove-Item -LiteralPath $file -Confirm:$false
        Write-Host 'Die geladene Datei trägt keine gültige NVIDIA-Signatur und wurde verworfen.' -ForegroundColor Red
        return
    }
    Write-Host "Geladen und Signatur geprüft: $file" -ForegroundColor Green
    $file
}

# --- 4. Installation ----------------------------------------------------------

function New-DriverRestorePoint {
    try {
        $warnings = @()
        Checkpoint-Computer -Description 'Treiber-Scan (vor Treiberinstallation)' `
            -RestorePointType DEVICE_DRIVER_INSTALL -WarningVariable warnings -WarningAction SilentlyContinue
        if ($warnings) {
            Write-Host 'Kein neuer Wiederherstellungspunkt: Windows hat in den letzten 24 Stunden bereits einen erstellt.' -ForegroundColor Yellow
        }
        else {
            Write-Host 'Wiederherstellungspunkt erstellt.' -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Wiederherstellungspunkt konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host 'Vermutlich ist der Computerschutz für Laufwerk C: abgeschaltet. Die Installation läuft trotzdem weiter.' -ForegroundColor Yellow
    }
}

# Gibt zurück, ob danach ein Neustart nötig ist
function Install-DriverUpdates($Session, $Items, $Stats) {
    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($item in $Items) { [void]$collection.Add($item.Update) }
    $installer = $Session.CreateUpdateInstaller()
    $installer.Updates = $collection

    Write-Host 'Installiere Treiber (der Bildschirm kann kurz flackern, Geräte können sich kurz abmelden) ...'
    $result = $installer.Install()

    $resultText = @{ 2 = 'Installiert'; 3 = 'Installiert mit Warnungen'; 4 = 'Fehlgeschlagen'; 5 = 'Abgebrochen' }
    for ($i = 0; $i -lt $collection.Count; $i++) {
        $single = $result.GetUpdateResult($i)
        $code = [int]$single.ResultCode
        $text = if ($resultText.ContainsKey($code)) { $resultText[$code] } else { "Code $code" }
        if ($code -eq 2 -or $code -eq 3) {
            $Stats.Installed++
            Write-Host "${text}: $($collection.Item($i).Title)" -ForegroundColor Green
        }
        else {
            $Stats.Failed++
            Write-Host ('{0}: {1} (0x{2:X8})' -f $text, $collection.Item($i).Title, $single.HResult) -ForegroundColor Red
        }
    }
    [bool]$result.RebootRequired
}

# --- Ablauf -------------------------------------------------------------------

function Invoke-Main {
    $stats = @{ Found = 0; Downloaded = 0; Installed = 0; Failed = 0 }
    $excludePatterns = @($Exclude | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })

    Write-Step 'Hardware-Scan'
    Show-SystemInfo
    $installed = @(Get-InstalledDrivers)
    Show-InstalledDrivers $installed
    Show-ProblemDevices
    $report = Export-HardwareReport $installed $OutDir
    Write-Host "Bericht gespeichert: $report"

    if ($Backup) {
        Write-Step 'Sicherung der installierten Treiber'
        Backup-InstalledDrivers $OutDir
    }

    Write-Step 'Suche nach neueren Treibern'
    $items = @()
    $session = $null
    try {
        $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($service -and $service.StartType -eq 'Disabled') {
            throw 'Der Dienst "Windows Update" ist deaktiviert. Er muss mindestens auf "Manuell" stehen.'
        }
        Write-Host 'Frage Windows Update ab (dauert bis zu einer Minute) ...'
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Treiber-Scan'
        $items = @(Find-DriverUpdates $session)
    }
    catch {
        Write-Host "Die Suche bei Windows Update ist fehlgeschlagen: $(Get-UpdateErrorText $_)" -ForegroundColor Red
        $script:ExitCode = 1
    }

    $nvidia = $null
    if (-not $NoVendorCheck) {
        try { $nvidia = Get-NvidiaUpdate }
        catch { Write-Host "Die Abfrage bei NVIDIA ist fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    if ($excludePatterns.Count -gt 0) {
        foreach ($item in @($items | Where-Object { Test-Excluded $_.Update.Title $excludePatterns })) {
            Write-Host "Ausgeschlossen (-Exclude): $($item.Update.Title)" -ForegroundColor DarkGray
        }
        $items = @($items | Where-Object { -not (Test-Excluded $_.Update.Title $excludePatterns) })
    }
    if ($nvidia) {
        # den Grafiktreiber liefert NVIDIA selbst immer mindestens so aktuell wie Windows Update (dort heißt die Klasse mal Display, mal Video)
        $items = @($items | Where-Object {
                -not ($_.Update.DriverClass -in 'Display', 'Video' -and "$($_.Update.Title) $($_.Update.DriverProvider)" -match 'NVIDIA') })
    }

    if ($items.Count -gt 0) {
        Write-Host ("Windows Update: {0} neuere(r) Treiber gefunden:" -f $items.Count) -ForegroundColor Green
        Show-Updates $items $installed
    }
    elseif ($session -and $script:ExitCode -eq 0) {
        Write-Host 'Windows Update: alle Treiber sind aktuell.' -ForegroundColor Green
        $policyHint = Get-DriverPolicyHint
        if ($policyHint) { Write-Host $policyHint -ForegroundColor Yellow }
    }

    $nvidiaIsNewer = $false
    if ($nvidia) {
        $nvidiaIsNewer = $nvidia.IsNewer -and -not (Test-Excluded 'NVIDIA' $excludePatterns)
        $state = if ($nvidia.IsNewer) { 'neuere Version verfügbar' } else { 'aktuell' }
        $color = if ($nvidia.IsNewer) { 'Yellow' } else { 'Green' }
        Write-Host ("NVIDIA {0} ({1}): installiert {2}, neueste {3} vom {4} - {5}" -f
            $nvidia.Kind, ($nvidia.Gpu -replace '^NVIDIA\s+', ''), $nvidia.Installed, $nvidia.Latest, $nvidia.Released, $state) -ForegroundColor $color
    }

    if (-not $NoVendorCheck) {
        try {
            $amd = Get-AmdChipsetUpdate
            if ($amd) {
                $state = if (-not $amd.Installed) { 'nicht installiert' } elseif ($amd.IsNewer) { 'neuere Version verfügbar' } else { 'aktuell' }
                Write-Host ("AMD Chipsatz-Treiber ({0}, {1}): installiert {2}, neueste {3} vom {4} - {5}" -f
                    $amd.Chipset, $amd.Cpu, $(if ($amd.Installed) { $amd.Installed } else { '-' }), $amd.Latest, $amd.Released, $state) -ForegroundColor $(if ($amd.IsNewer) { 'Yellow' } else { 'Green' })
                if ($amd.IsNewer) { Write-Host "     $($amd.Url)" -ForegroundColor DarkGray }
            }
        }
        catch { Write-Host "Die Abfrage bei AMD ist fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    $hints = @()
    if (-not $NoCatalogCheck) {
        Write-Host 'Durchsuche den Microsoft-Katalog ...'
        try {
            $hints = @(Find-CatalogHints $installed | Where-Object {
                    $hint = $_
                    # was Windows Update oder NVIDIA oben schon liefern, nicht doppelt melden
                    $offered = $items | Where-Object { $_.Update.Title -like "*$($hint.Entry.Version)*" }
                    $isNvidiaGpu = $nvidia -and $hint.Driver.DeviceClass -eq 'DISPLAY' -and $hint.Driver.DriverProviderName -match 'NVIDIA'
                    -not $offered -and -not $isNvidiaGpu -and
                    -not (Test-Excluded "$($hint.Entry.Title) $($hint.Driver.DeviceName)" $excludePatterns)
                })
            Show-CatalogHints $hints
        }
        catch {
            Write-Host "Die Abfrage des Microsoft-Katalogs ist fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Show-VendorHints

    $stats.Found = $items.Count + [int]$nvidiaIsNewer
    $rebootRequired = $false

    if ($stats.Found -eq 0) {
        # nichts zu tun
    }
    elseif ($ScanOnly) {
        Write-Host ''
        Write-Host 'Nur-Scan-Modus: es wurde nichts heruntergeladen. Ohne -ScanOnly starten, um zu laden.'
    }
    else {
        Write-Step 'Download'
        $ready = @()
        if ($items.Count -gt 0) { $ready = @(Save-DriverUpdates $session $items $OutDir $stats) }
        $nvidiaFile = $null
        if ($nvidiaIsNewer) {
            try { $nvidiaFile = Save-NvidiaDriver $nvidia $OutDir }
            catch { Write-Host "NVIDIA-Download fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red }
            if ($nvidiaFile) { $stats.Downloaded++ } else { $stats.Failed++ }
        }

        if ($Install) {
            Write-Step 'Installation'
            $firmware = @($ready | Where-Object { Test-IsFirmware $_.Update })
            if ($firmware.Count -gt 0 -and -not $IncludeFirmware) {
                $firmware | ForEach-Object {
                    Write-Host "Nicht installiert (Firmware/BIOS, nur mit -IncludeFirmware): $($_.Update.Title)" -ForegroundColor Yellow
                }
                $ready = @($ready | Where-Object { -not (Test-IsFirmware $_.Update) })
            }

            if ($ready.Count -eq 0 -and -not $nvidiaFile) {
                Write-Host 'Nichts zu installieren.'
            }
            else {
                if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) {
                    Write-Host 'Achtung: Von einem früheren Update steht noch ein Neustart aus.' -ForegroundColor Yellow
                }
                if (-not $NoRestorePoint) { New-DriverRestorePoint }
                if ($ready.Count -gt 0) {
                    if (-not $NoAutoBackup -and (Get-Command Backup-ReplacedDrivers -ErrorAction SilentlyContinue)) {
                        try { Backup-ReplacedDrivers $ready $installed $OutDir }
                        catch { Write-Host "Die automatische Sicherung ist fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow }
                    }
                    $rebootRequired = Install-DriverUpdates $session $ready $stats
                }
                if ($nvidiaFile) {
                    Write-Host 'Starte den NVIDIA-Installer - bitte dem Assistenten folgen ...'
                    Start-SignedInstaller $nvidiaFile 'O=NVIDIA Corporation'
                    $stats.Installed++
                }
            }
        }
        elseif ($stats.Downloaded -gt 0) {
            Write-Host ''
            Write-Host 'Zum Installieren das Skript mit -Install starten.'
        }
    }

    Write-Step 'Zusammenfassung'
    if ($stats.Found -eq 0 -and $script:ExitCode -eq 0) {
        if ($hints.Count -gt 0) {
            Write-Host 'Nichts zu laden. Die Hinweise aus dem Microsoft-Katalog stehen oben.' -ForegroundColor Green
        }
        else {
            Write-Host 'Alles aktuell - nichts zu tun.' -ForegroundColor Green
        }
    }
    else {
        Write-Host ("Gefunden: {0}   Geladen: {1}   Installiert: {2}   Fehlgeschlagen: {3}" -f
            $stats.Found, $stats.Downloaded, $stats.Installed, $stats.Failed)
    }
    Write-Host "Ordner:    $OutDir"
    if ($rebootRequired) {
        Write-Host 'Bitte den PC neu starten, um die Installation abzuschließen.' -ForegroundColor Yellow
    }
    if ($stats.Failed -gt 0) { $script:ExitCode = 1 }
}

# steckt das Skript in PulsRig.exe, gibt es keinen eigenen Pfad: die Werkzeuge lädt dann PulsRig-Arbeit-Start.ps1
if ($PSCommandPath) {
    $toolsFile = Join-Path (Split-Path -Parent $PSCommandPath) 'Treiber-Werkzeuge.ps1'
    if (Test-Path -LiteralPath $toolsFile) { . $toolsFile }
}

# beim Einbinden per ". .\Treiber-Scan.ps1" nur die Funktionen laden
if ($MyInvocation.InvocationName -eq '.' -or $global:DD_Embedded) { return }

if (-not $OutDir) {
    $OutDir = Join-Path (Split-Path -Parent $PSCommandPath) 'Treiber'
}
if (($Tool -or $Menu) -and -not $script:ToolList) {
    Write-Host "Die Werkzeuge fehlen: $toolsFile muss neben diesem Skript liegen." -ForegroundColor Red
    exit 1
}
# ein Probelauf der Treibersuche ist dasselbe wie -ScanOnly
if ($DryRun -and -not $Tool -and -not $Menu) { $ScanOnly = $true }

# Download, Installation und Reparaturen gehen nur mit Adminrechten - ein Probelauf ändert nichts und braucht keine
$needsAdmin = if ($DryRun) { $false }
elseif ($Menu) { $true }
elseif ($Tool) { $script:ToolList[$Tool].Admin }
else { -not $ScanOnly }
if ($needsAdmin -and -not (Test-IsAdmin)) {
    $handedOver = $false
    if ($Elevated) {
        Write-Host 'Trotz Neustart fehlen die Adminrechte - bitte als Administrator ausführen.' -ForegroundColor Red
    }
    else {
        Write-Host 'Adminrechte nötig - bitte die Windows-Abfrage bestätigen ...' -ForegroundColor Yellow
        $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated') +
            @(Get-ForwardArguments $script:BoundParameters)
        try {
            Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argumentList
            $handedOver = $true
        }
        catch {
            Write-Host 'Die Abfrage wurde abgelehnt - ohne Adminrechte ist nur -ScanOnly möglich.' -ForegroundColor Red
        }
    }
    if ($handedOver) { exit 0 }   # das neue Fenster übernimmt
    if ($WaitAtEnd) {
        Write-Host 'Zum Beenden die Eingabetaste drücken ...'
        [void][Console]::ReadLine()
    }
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    $logPath = Join-Path $OutDir 'Treiber-Scan.log'
    try { Start-Transcript -LiteralPath $logPath | Out-Null } catch { $logPath = $null }

    if ($Menu) { Invoke-Menu }
    elseif ($Tool) { Invoke-Tool $Tool }
    else { Invoke-Main }
    if ($logPath) { Write-Host "Protokoll: $logPath" }
}
catch {
    Write-Host ''
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    $script:ExitCode = 1
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}

# das Menü wurde bewusst über "Beenden" verlassen - dort nicht noch einmal warten
if (($WaitAtEnd -or $Elevated) -and -not $Menu) {
    Write-Host ''
    Write-Host 'Zum Beenden die Eingabetaste drücken ...'
    [void][Console]::ReadLine()
}
exit $script:ExitCode
