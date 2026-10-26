# Werkzeuge für Treiber-Scan.ps1. Wird von dort eingebunden - nicht einzeln starten.
#
# Jedes Werkzeug prüft zuerst nur (ohne etwas zu ändern), zeigt dann die geplanten Schritte
# und fragt nach, bevor es ins System eingreift. Mit -DryRun bleibt es beim Anzeigen.

$script:ToolList = [ordered]@{
    Backup              = @{ Title = 'Treiber sichern';                  Admin = $false }
    Restore             = @{ Title = 'Treiber wiederherstellen';         Admin = $true }
    FixAudio            = @{ Title = 'Tonstörung beheben';               Admin = $true }
    FixDevices          = @{ Title = 'Gerätefehler beheben';             Admin = $true }
    CleanDevices        = @{ Title = 'Ungültige Gerätedaten bereinigen'; Admin = $true }
    FixNetwork          = @{ Title = 'Netzwerkfehler beheben';           Admin = $true }
    FixResolution       = @{ Title = 'Schlechte Bildauflösung beheben';  Admin = $true }
    GameRuntimes        = @{ Title = 'Fehlende Spiel-DLLs beheben';      Admin = $true }
    IncompatibleDrivers = @{ Title = 'Inkompatible Treiber reparieren';  Admin = $true }
    OfflinePackage      = @{ Title = 'Offline-Treiberpaket erstellen';   Admin = $false }
    SystemInfo          = @{ Title = 'Systeminformationen';              Admin = $false }
    GameBoost           = @{ Title = 'Spiel-Beschleunigung ein/aus';     Admin = $true }
    CleanDisk           = @{ Title = 'Speicherplatz freigeben';          Admin = $true }
}

# --- Gemeinsame Bausteine -----------------------------------------------------

# Führt einen ändernden Schritt aus; im Probelauf wird er nur angezeigt
function Invoke-Step([string]$Description, [scriptblock]$Action, [object[]]$Arguments) {
    if ($DryRun) {
        Write-Host "  [Probelauf] $Description" -ForegroundColor DarkGray
        return
    }
    Write-Host "  $Description ... " -NoNewline
    try {
        & $Action @Arguments | Out-Null
        Write-Host 'ok' -ForegroundColor Green
    }
    catch {
        Write-Host "fehlgeschlagen ($($_.Exception.Message.Trim()))" -ForegroundColor Red
        $script:ExitCode = 1
    }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$OkCodes = @(0)) {
    $output = & $File @Arguments
    $script:LastNativeCode = $LASTEXITCODE
    if ($OkCodes -notcontains $LASTEXITCODE) {
        throw "$File meldet Code $LASTEXITCODE"
    }
    $output
}

# -Optional: Fragen, die -Yes nicht automatisch bejahen soll (riskantere Zusatzschritte)
function Confirm-Action([string]$Question, [switch]$Optional) {
    if ($DryRun) { return -not $Optional }
    if ($Yes) { return -not $Optional }
    try { $answer = Read-Host "$Question (j/N)" } catch { return $false }
    "$answer" -match '^\s*(j|ja|y|yes)\s*$'
}

function Format-State($Value) {
    switch ("$Value") {
        'Up' { 'verbunden' }
        'Disconnected' { 'getrennt' }
        'Disabled' { 'deaktiviert' }
        'Running' { 'läuft' }
        'Stopped' { 'gestoppt' }
        'Automatic' { 'automatisch' }
        'Manual' { 'manuell' }
        default { "$Value" }
    }
}

function Write-Check([string]$Label, [bool]$Ok, [string]$Detail) {
    $mark = if ($Ok) { '[ ok ]' } else { '[ !! ]' }
    $color = if ($Ok) { 'Green' } else { 'Yellow' }
    $text = if ($Detail) { "$Label - $Detail" } else { $Label }
    Write-Host "  $mark $text" -ForegroundColor $color
}

function New-SafetyPoint {
    if ($NoRestorePoint) { return }
    if ($DryRun) {
        Write-Host '  [Probelauf] Wiederherstellungspunkt erstellen' -ForegroundColor DarkGray
        return
    }
    New-DriverRestorePoint
}

# --- Laufwerke und Netzwerk ohne die Windows-Module ---------------------------
# Get-PhysicalDisk, Get-Volume, Get-NetAdapter und Verwandte kommen aus Modulen, die beim ersten Aufruf je rund
# 90 MB Arbeitsspeicher belegen und nicht wieder hergeben. Dieselben Angaben liefert Windows auch direkt - das
# kostet nichts. Die Funktionen hier geben sie mit denselben Namen und Wörtern zurück wie die Befehle.

# Die Umwandlung der Rohwerte steckt in PulsRig.Core.dll (C#, Ordner CSharp). Sie liegt neben dem Programm; in der
# Werkstatt kommt sie aus dem Ordner, in den "dotnet build" sie legt.
function Import-PulsRigCore {
    if ('PulsRig.Core.Laufwerke' -as [type]) { return }
    $dirs = @($global:DD_ProgramDir, $script:Root, $PSScriptRoot, [IO.Path]::GetDirectoryName([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)) | Where-Object { $_ }
    foreach ($dir in $dirs) {
        foreach ($file in (Join-Path $dir 'PulsRig.Core.dll'), (Join-Path $dir 'CSharp\PulsRig.Core\bin\Release\net48\PulsRig.Core.dll'), (Join-Path $dir 'CSharp\PulsRig.Core\bin\Debug\net48\PulsRig.Core.dll')) {
            if (Test-Path -LiteralPath $file) { Add-Type -LiteralPath $file; return }
        }
    }
    throw 'PulsRig.Core.dll fehlt - im Ordner CSharp einmal "dotnet build" ausführen.'
}

function Get-DiskList([switch]$Counters) {
    Import-PulsRigCore
    foreach ($disk in @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop)) {
        $counter = $null
        # Temperatur, Betriebsstunden und Abnutzung gibt Windows nur mit Adminrechten heraus
        if ($Counters) { try { $counter = Get-CimAssociatedInstance -InputObject $disk -ResultClassName MSFT_StorageReliabilityCounter -ErrorAction Stop | Select-Object -First 1 } catch { } }
        [pscustomobject]@{
            DeviceId          = "$($disk.DeviceId)"
            FriendlyName      = "$($disk.FriendlyName)"
            MediaType         = [PulsRig.Core.Laufwerke]::ResolveMedia([PulsRig.Core.Laufwerke]::MediaType($disk.MediaType), $disk.DeviceId)
            BusType           = [PulsRig.Core.Laufwerke]::BusType($disk.BusType)
            Size              = [double]$disk.Size
            HealthStatus      = [PulsRig.Core.Laufwerke]::Health($disk.HealthStatus)
            OperationalStatus = [PulsRig.Core.Laufwerke]::OperationalStatus($disk.OperationalStatus)
            FirmwareVersion   = "$($disk.FirmwareVersion)"
            SerialNumber      = "$($disk.SerialNumber)"
            Counter           = $counter
        }
    }
}

function Get-PartitionList {
    Import-PulsRigCore
    foreach ($partition in @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Partition -ErrorAction Stop)) {
        [pscustomobject]@{ DriveLetter = [PulsRig.Core.Laufwerke]::DriveLetter($partition.DriveLetter); DiskNumber = "$($partition.DiskNumber)" }
    }
}

function Get-VolumeList {
    Import-PulsRigCore
    foreach ($volume in @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Volume -ErrorAction Stop)) {
        [pscustomobject]@{
            DriveLetter     = [PulsRig.Core.Laufwerke]::DriveLetter($volume.DriveLetter)
            FileSystemLabel = "$($volume.FileSystemLabel)"
            FileSystem      = "$($volume.FileSystem)"
            HealthStatus    = [PulsRig.Core.Laufwerke]::Health($volume.HealthStatus)
            Size            = [double]$volume.Size
            SizeRemaining   = [double]$volume.SizeRemaining
        }
    }
}

# Die eingebauten Netzwerkadapter (mit Anschluss, nicht versteckt) wie bei "Get-NetAdapter -Physical"
function Get-NetAdapterList {
    Import-PulsRigCore
    $adapters = @()
    try { $adapters = @(Get-CimInstance -Namespace 'root/StandardCimv2' -ClassName MSFT_NetAdapter -ErrorAction Stop | Where-Object { $_.ConnectorPresent -and -not $_.Hidden }) } catch { }
    foreach ($adapter in $adapters) {
        [pscustomobject]@{
            Name                 = "$($adapter.Name)"
            InterfaceDescription = "$($adapter.InterfaceDescription)"
            ifIndex              = [int]$adapter.InterfaceIndex
            Status               = [PulsRig.Core.Netzwerk]::Status($adapter.InterfaceAdminStatus, $adapter.MediaConnectState)
            LinkSpeed            = [PulsRig.Core.Netzwerk]::LinkSpeed([double]$adapter.Speed)
            MacAddress           = [PulsRig.Core.Netzwerk]::MacAddress($adapter.PermanentAddress)
        }
    }
}

function Get-NetIPv4List([int]$InterfaceIndex) {
    try {
        Import-PulsRigCore
        @(Get-CimInstance -Namespace 'root/StandardCimv2' -ClassName MSFT_NetIPAddress -ErrorAction Stop |
                Where-Object { [PulsRig.Core.Netzwerk]::IsIPv4($_.AddressFamily) -and [int]$_.InterfaceIndex -eq $InterfaceIndex } | ForEach-Object { "$($_.IPAddress)" })
    }
    catch { @() }
}

function Test-FileSigner([string]$Path, [string]$SignerPattern) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match $SignerPattern
}

# Lädt eine Datei nur von erlaubten Adressen und behält sie nur mit passender Signatur
function Save-SignedDownload([string]$Url, [string]$File, [string]$SignerPattern, [string[]]$AllowedHosts) {
    $uri = [uri]$Url
    Import-PulsRigCore
    if (-not [PulsRig.Core.Downloads]::IsAllowed($Url, [string[]]@($AllowedHosts))) {
        throw "Unerwartete Adresse: $Url"
    }
    # immer frisch laden: eine liegengebliebene Datei mit irgendeiner gültigen Signatur wäre kein Beweis, dass es die richtige ist
    if (Test-Path -LiteralPath $File) { Remove-Item -LiteralPath $File -Confirm:$false }
    try {
        Start-BitsTransfer -Source $uri.AbsoluteUri -Destination $File -DisplayName (Split-Path -Leaf $File)
    }
    catch {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $uri.AbsoluteUri -OutFile $File
    }
    if (-not (Test-FileSigner $File $SignerPattern)) {
        Remove-Item -LiteralPath $File -Confirm:$false
        throw 'Die geladene Datei trägt keine gültige Signatur des Herstellers und wurde verworfen.'
    }
}

# --- Sichern & Wiederherstellen -----------------------------------------------

function Invoke-RestoreTool {
    Import-PulsRigCore
    $path = $BackupPath
    if (-not $path) {
        $backups = @(Get-ChildItem -LiteralPath $OutDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { [PulsRig.Core.Sicherung]::IsBackupFolder($_.Name) } |
                Sort-Object LastWriteTime -Descending)
        if ($backups.Count -eq 0) {
            Write-Host 'Keine Sicherung gefunden. Zuerst "Treiber sichern" ausführen oder mit -BackupPath einen Ordner angeben.' -ForegroundColor Yellow
            return
        }
        for ($i = 0; $i -lt $backups.Count; $i++) {
            Write-Host ('{0,3}  {1}  ({2:dd.MM.yyyy HH:mm})' -f ($i + 1), $backups[$i].Name, $backups[$i].LastWriteTime)
        }
        $index = 0
        if ($backups.Count -gt 1 -and -not $Yes -and -not $DryRun) {
            $index = [PulsRig.Core.Sicherung]::PickIndex("$(Read-Host 'Nummer der Sicherung (Eingabetaste = neueste)')", $backups.Count)
        }
        $path = $backups[$index].FullName
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Ordner nicht gefunden: $path" -ForegroundColor Red
        return
    }
    $infCount = @(Get-ChildItem -LiteralPath $path -Recurse -Filter '*.inf' -File).Count
    if ($infCount -eq 0) {
        Write-Host "In $path liegen keine Treiberpakete." -ForegroundColor Red
        return
    }

    Write-Host "Sicherung: $path ($infCount Treiberpakete)"
    Write-Host 'Windows übernimmt daraus nur Treiber, die besser passen als die installierten. Ein neuerer Treiber'
    Write-Host 'wird so nicht ersetzt - um ein Update zurückzunehmen, den Wiederherstellungspunkt verwenden.'
    if (-not (Confirm-Action 'Treiber aus dieser Sicherung einspielen?')) { return }

    New-SafetyPoint
    Invoke-Step 'Spiele Treiber ein (kann einige Minuten dauern)' {
        # 259 = nichts Neueres dabei, 3010 = Neustart nötig
        Invoke-Native pnputil.exe @('/add-driver', (Join-Path $path '*.inf'), '/subdirs', '/install') @(0, 259, 3010)
    }
    if ($script:LastNativeCode -eq 3010) {
        Write-Host 'Bitte den PC neu starten, um die Wiederherstellung abzuschließen.' -ForegroundColor Yellow
    }
}

# Sichert vor einer Installation genau die Treiberpakete, die dabei ersetzt werden.
# Sehr große Pakete (Grafiktreiber) bleiben außen vor - ältere Fassungen davon gibt es beim Hersteller.
function Backup-ReplacedDrivers($Items, $Installed, [string]$OutDir, [long]$MaxBytes = 300MB) {
    Import-PulsRigCore
    $packages = @([PulsRig.Core.Sicherung]::PackagesToBackup([string[]]@($Items | ForEach-Object { Find-InstalledDriver $_.Update.DriverHardwareID $Installed } |
                    Where-Object { $_ } | ForEach-Object { "$($_.InfName)" })))
    if ($packages.Count -eq 0) { return }

    $originals = @{}
    Get-DriverPackages | ForEach-Object { $originals[$_.Published.ToLower()] = $_.Original }
    $target = Join-Path $OutDir ([PulsRig.Core.Sicherung]::AutoFolderName((Get-Date)))
    $saved = 0
    foreach ($package in $packages) {
        $original = $originals[$package]
        if (-not $original) { continue }
        # der Treiberspeicher kann mehrere Fassungen enthalten - die größte entscheidet, ob sich das Sichern lohnt
        $bytes = 0
        Get-ChildItem -LiteralPath "$env:windir\System32\DriverStore\FileRepository" -Directory -Filter "${original}_*" -ErrorAction SilentlyContinue | ForEach-Object {
            $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            if ($size -gt $bytes) { $bytes = $size }
        }
        if ($bytes -gt $MaxBytes) {
            Write-Host ("  Nicht gesichert ({0:N0} MB, zu groß für die automatische Sicherung): {1}" -f ($bytes / 1MB), $original) -ForegroundColor DarkGray
            continue
        }
        $folder = Join-Path $target ([PulsRig.Core.Sicherung]::FolderName($original))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        & pnputil.exe /export-driver $package $folder | Out-Null
        if ($LASTEXITCODE -eq 0) { $saved++ }
    }
    if ($saved -gt 0) {
        Write-Host "Bisherige Treiber gesichert ($saved Paket(e)): $target" -ForegroundColor Green
        Write-Host '  Zurückholen: Geräte-Manager > Gerät > Treiber aktualisieren > "Auf meinem Computer suchen" und diesen Ordner wählen.' -ForegroundColor DarkGray
    }
}

# --- Tonstörung beheben -------------------------------------------------------

function Invoke-FixAudioTool {
    $steps = New-Object System.Collections.Generic.List[object]

    $services = @(Get-Service -Name AudioEndpointBuilder, Audiosrv)
    foreach ($service in $services) {
        $ok = $service.Status -eq 'Running' -and $service.StartType -ne 'Disabled'
        Write-Check "Dienst `"$($service.DisplayName)`"" $ok "$(Format-State $service.Status), Starttyp $(Format-State $service.StartType)"
        if (-not $ok) {
            $steps.Add(@{
                    Text      = "Dienst $($service.Name) auf automatischen Start stellen und starten"
                    Arguments = @($service.Name)
                    Action    = {
                        param($name)
                        Set-Service -Name $name -StartupType Automatic
                        Start-Service -Name $name
                    }
                })
        }
    }

    # {0.0.0...} = Wiedergabe, {0.0.1...} = Aufnahme
    $outputs = @(Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like '*{0.0.0.*' })
    Write-Check 'Wiedergabegeräte' ($outputs.Count -gt 0) ("{0} gefunden: {1}" -f $outputs.Count, (($outputs | ForEach-Object { $_.FriendlyName }) -join ', '))

    $audioDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -in 'MEDIA', 'AudioEndpoint' })
    $broken = @($audioDevices | Where-Object { $_.ConfigManagerErrorCode -notin 0, 22 })
    $disabled = @($audioDevices | Where-Object { $_.ConfigManagerErrorCode -eq 22 })
    Write-Check 'Audiogeräte ohne Fehler' ($broken.Count -eq 0) $(if ($broken.Count) { ($broken | ForEach-Object { "$($_.Name) (Code $($_.ConfigManagerErrorCode))" }) -join ', ' })
    foreach ($device in $broken) {
        $steps.Add(@{
                Text      = "Gerät neu starten: $($device.Name)"
                Arguments = @($device.DeviceID)
                Action    = { param($id) Invoke-Native pnputil.exe @('/restart-device', $id) @(0, 3010) }
            })
    }
    if ($disabled.Count -gt 0) {
        Write-Host ("         Deaktiviert (im Geräte-Manager wieder einschaltbar): {0}" -f (($disabled | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor DarkGray
    }

    try {
        Import-PulsRigCore
        $muted = [PulsRig.Core.Audio]::GetMute()
        $level = [PulsRig.Core.Audio]::GetVolume()
        Write-Check 'Standardgerät nicht stumm' (-not $muted) $(if ($muted) { 'ist stummgeschaltet' })
        Write-Check 'Lautstärke' ($level -ge 0.05) ('{0:N0} %' -f ($level * 100))
        if ($muted) {
            $steps.Add(@{ Text = 'Stummschaltung des Standardgeräts aufheben'; Action = { [PulsRig.Core.Audio]::SetMute($false) } })
        }
        if ($level -lt 0.05) {
            $steps.Add(@{ Text = 'Lautstärke auf 30 % stellen'; Action = { [PulsRig.Core.Audio]::SetVolume(0.3) } })
        }
    }
    catch {
        Write-Check 'Standard-Wiedergabegerät' $false 'keines festgelegt oder nicht ansprechbar'
    }

    Write-Host ''
    if ($steps.Count -eq 0) {
        Write-Host 'Keine Ursache gefunden. Prüfe, ob in Windows das richtige Wiedergabegerät gewählt ist (Klick auf das Lautsprechersymbol).'
        if (-not (Confirm-Action 'Audiodienste trotzdem neu starten (hilft bei hängendem Ton)?' -Optional)) { return }
    }
    else {
        Write-Host 'Geplante Schritte:'
        $steps | ForEach-Object { Write-Host "  - $($_.Text)" }
        if (-not (Confirm-Action 'Jetzt ausführen?')) { return }
        foreach ($step in $steps) { Invoke-Step $step.Text $step.Action $step.Arguments }
    }
    Invoke-Step 'Audiodienste neu starten' {
        Restart-Service -Name AudioEndpointBuilder -Force
        Start-Service -Name Audiosrv
    }
}

# --- Gerätefehler beheben -----------------------------------------------------

function Get-ProblemDevices {
    @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
}

# Welche der Geräte melden weiterhin einen Fehler? (Im Probelauf ändert sich nichts.)
function Get-StillBroken($Devices) {
    $ids = @($Devices | ForEach-Object { $_.DeviceID })
    @(Get-ProblemDevices | Where-Object { $ids -contains $_.DeviceID -and $_.ConfigManagerErrorCode -ne 22 })
}

function Invoke-FixDevicesTool {
    $problems = Get-ProblemDevices
    if ($problems.Count -eq 0) {
        Write-Host 'Kein Gerät meldet einen Fehler.' -ForegroundColor Green
        return
    }
    Show-ProblemDevices

    Import-PulsRigCore
    $fix = { [PulsRig.Core.Geraetefehler]::Get([int]$_.ConfigManagerErrorCode).Fix }
    $disabled = @($problems | Where-Object { (& $fix) -eq 'Disabled' })
    $needReboot = @($problems | Where-Object { (& $fix) -eq 'Reboot' })
    $needFirmware = @($problems | Where-Object { (& $fix) -eq 'Firmware' })
    # nur Fehler, die am Treiber liegen, lassen sich von hier aus beheben
    $broken = @($problems | Where-Object { (& $fix) -eq 'Driver' })
    if ($needReboot.Count -gt 0) {
        Write-Host "$($needReboot.Count) Gerät(e) brauchen nur einen Neustart des PCs (bei USB-Geräten: ab- und wieder anstecken)."
    }
    if ($needFirmware.Count -gt 0) {
        Write-Host "$($needFirmware.Count) Gerät(e): Die Ursache liegt im BIOS oder an der Hardware - BIOS-Einstellungen prüfen, BIOS aktualisieren, Gerät umstecken."
    }
    if ($disabled.Count -gt 0) {
        Write-Host "$($disabled.Count) Gerät(e) sind deaktiviert - das ist meist Absicht."
        if (Confirm-Action 'Deaktivierte Geräte wieder aktivieren?' -Optional) {
            foreach ($device in $disabled) {
                Invoke-Step "Aktiviere $($device.Name)" { Invoke-Native pnputil.exe @('/enable-device', $device.DeviceID) @(0, 3010) }
            }
        }
    }
    if ($broken.Count -eq 0) { return }
    if (-not (Confirm-Action "Reparatur für $($broken.Count) Gerät(e) versuchen (Treiber suchen, Gerät neu starten)?")) { return }

    New-SafetyPoint
    Invoke-Step 'Hardware neu erkennen' { Invoke-Native pnputil.exe @('/scan-devices') }

    Write-Host '  Suche passende Treiber bei Windows Update ...'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Treiber-Scan'
        $hardwareIds = @($broken | ForEach-Object { $_.HardwareID } | Where-Object { $_ })
        $matching = @(Find-DriverUpdates $session | Where-Object { $hardwareIds -contains $_.Update.DriverHardwareID })
        if ($matching.Count -eq 0) {
            Write-Host '  Windows Update hat für diese Geräte keinen Treiber.'
        }
        elseif ($DryRun) {
            $matching | ForEach-Object { Write-Host "  [Probelauf] Treiber installieren: $($_.Update.Title)" -ForegroundColor DarkGray }
        }
        else {
            $stats = @{ Found = 0; Downloaded = 0; Installed = 0; Failed = 0 }
            $ready = @(Save-DriverUpdates $session $matching $OutDir $stats)
            if ($ready.Count -gt 0) { [void](Install-DriverUpdates $session $ready $stats) }
        }
    }
    catch {
        Write-Host "  Die Treibersuche ist fehlgeschlagen: $(Get-UpdateErrorText $_)" -ForegroundColor Yellow
    }

    # Geräte ohne Treiber (Code 28), für die Windows Update nichts hatte: im Microsoft-Katalog nachsehen.
    # Ein Paket deckt oft mehrere Geräte ab (z.B. der Chipsatz-Treiber) - deshalb vor jedem Gerät neu prüfen.
    $missing = @(Get-StillBroken $broken | Where-Object { $_.ConfigManagerErrorCode -eq 28 })
    if ($missing.Count -gt 0) {
        Write-Host '  Suche im Microsoft-Katalog nach Treibern für Geräte ohne Treiber ...'
        $asked = @{}; $without = @()
        foreach ($device in $missing) {
            if (@(Get-StillBroken @($device)).Count -eq 0) { continue }
            try {
                $found = Find-MissingDriver "$(@($device.HardwareID)[0])"
                if (-not $found) { $without += $device; continue }
                if ($asked.ContainsKey($found.Id)) { continue }
                $asked[$found.Id] = $true
                $label = "$($found.Title), $($found.Size)"
                if ($DryRun) { Write-Host "  [Probelauf] Aus dem Microsoft-Katalog installieren: $label (für $($device.Name))" -ForegroundColor DarkGray; continue }
                if (-not (Confirm-Action "Für `"$($device.Name)`" steht im Microsoft-Katalog der Treiber `"$label`". Laden und installieren?")) { continue }
                Invoke-Step "Installiere $($found.Title) aus dem Microsoft-Katalog" { param($package) Install-CatalogDriver $package } @($found)
            }
            catch { Write-Host "  $($device.Name): Die Suche im Katalog ist fehlgeschlagen ($($_.Exception.Message.Trim()))." -ForegroundColor Yellow }
        }
        # erst jetzt melden, wofür der Katalog nichts hatte: das Paket eines anderen Geräts kann es mit behoben haben
        foreach ($device in $(if ($DryRun) { $without } else { Get-StillBroken $without })) { Write-Host "  $($device.Name): im Katalog steht dazu kein eigener Treiber." }
    }

    foreach ($device in (Get-StillBroken $broken)) {
        Invoke-Step "Starte Gerät neu: $($device.Name)" { Invoke-Native pnputil.exe @('/restart-device', $device.DeviceID) @(0, 3010) }
    }

    # Ohne Treiber (Code 28) bringt Entfernen nichts - das Gerät käme genauso zurück
    $removable = @(Get-StillBroken $broken | Where-Object { $_.ConfigManagerErrorCode -ne 28 })
    if ($removable.Count -gt 0 -and
        (Confirm-Action "$($removable.Count) Gerät(e) melden weiter Fehler. Aus Windows entfernen und neu erkennen lassen?" -Optional)) {
        foreach ($device in $removable) {
            Invoke-Step "Entferne $($device.Name)" { Invoke-Native pnputil.exe @('/remove-device', $device.DeviceID) @(0, 3010) }
        }
        Invoke-Step 'Hardware neu erkennen' { Invoke-Native pnputil.exe @('/scan-devices') }
    }

    $remaining = Get-StillBroken $broken
    Write-Host ''
    if ($DryRun) { return }
    if ($remaining.Count -eq 0) {
        Write-Host 'Alle Geräte arbeiten wieder.' -ForegroundColor Green
        return
    }
    Write-Host "$($remaining.Count) Gerät(e) melden weiterhin einen Fehler:" -ForegroundColor Yellow
    foreach ($device in $remaining) {
        Write-Host ("  - {0} (Code {1}), Hardware-ID: {2}" -f $device.Name, $device.ConfigManagerErrorCode, @($device.HardwareID)[0])
    }
    Write-Host 'Dafür den Treiber beim Hersteller suchen (die Hardware-ID hilft bei der Suche) oder den PC neu starten.'
}

# --- Ungültige Gerätedaten bereinigen -----------------------------------------

# Einträge nicht mehr angeschlossener Hardware. Bewusst eng gefasst: Bluetooth-Kopplungen,
# Drucker und (virtuelle) Netzwerkadapter sind oft nur gerade aus und bleiben unangetastet.
function Select-CleanableDevices($Devices) {
    Import-PulsRigCore
    $Devices | Where-Object { [PulsRig.Core.Geraete]::IsCleanable([bool]$_.Present, "$($_.InstanceId)", "$($_.Class)") }
}

function Invoke-CleanDevicesTool {
    $all = @(Get-PnpDevice -ErrorAction SilentlyContinue)
    $absent = @($all | Where-Object { -not $_.Present })
    $cleanable = @(Select-CleanableDevices $all)

    Write-Host ("Geräteeinträge: {0}, davon {1} zu nicht mehr angeschlossener Hardware." -f $all.Count, $absent.Count)
    if ($cleanable.Count -eq 0) {
        Write-Host 'Nichts zu bereinigen.' -ForegroundColor Green
        return
    }
    Write-Host "$($cleanable.Count) Einträge lassen sich gefahrlos entfernen (Windows legt sie beim erneuten Anschließen neu an):"
    foreach ($group in ($cleanable | Group-Object Class | Sort-Object Count -Descending)) {
        $examples = @($group.Group | ForEach-Object { $_.FriendlyName } | Where-Object { $_ } | Select-Object -Unique -First 3) -join ', '
        Write-Host ('  {0,4}  {1,-16} {2}' -f $group.Count, $group.Name, $examples)
    }
    if ($absent.Count -gt $cleanable.Count) {
        Write-Host ("Unangetastet bleiben {0} Einträge (Bluetooth, Drucker, Netzwerk und andere, die oft nur ausgeschaltet sind)." -f
            ($absent.Count - $cleanable.Count)) -ForegroundColor DarkGray
    }
    if (-not (Confirm-Action "$($cleanable.Count) Einträge entfernen?")) { return }

    New-SafetyPoint
    if ($DryRun) {
        Write-Host "  [Probelauf] $($cleanable.Count) Einträge entfernen" -ForegroundColor DarkGray
        return
    }
    $removed = 0
    $index = 0
    foreach ($device in $cleanable) {
        $index++
        Write-Progress -Activity 'Gerätedaten bereinigen' -Status "$index von $($cleanable.Count)" -PercentComplete ($index / $cleanable.Count * 100)
        try {
            Invoke-Native pnputil.exe @('/remove-device', $device.InstanceId) @(0, 3010) | Out-Null
            $removed++
        }
        catch { }
    }
    Write-Progress -Activity 'Gerätedaten bereinigen' -Completed
    $color = if ($removed -eq $cleanable.Count) { 'Green' } else { 'Yellow' }
    Write-Host "$removed von $($cleanable.Count) Einträgen entfernt." -ForegroundColor $color
}

# --- Netzwerkfehler beheben ---------------------------------------------------

function Test-TcpPort([string]$Address, [int]$Port, [int]$TimeoutMs = 3000) {
    Import-PulsRigCore
    [PulsRig.Core.Netzwerk]::TcpPort($Address, $Port, $TimeoutMs)
}

# Die Prüfung fragt Windows direkt (siehe Get-NetAdapterList): die Netzwerk-Befehle von Windows würden Module laden,
# die zusammen rund 90 MB belegen. Nur der Neustart eines Adapters in der Reparatur braucht noch einen davon.
function Get-NetworkState {
    Import-PulsRigCore
    $space = 'root/StandardCimv2'
    $adapters = @(Get-NetAdapterList)
    $up = @($adapters | Where-Object { $_.Status -eq 'Up' })
    # Schnittstellen mit Standardgateway, ihre Adressen und ob sie die Adresse automatisch beziehen
    $routed = @(); $addresses = @(); $dhcp = $false; $dnsServer = $null
    try {
        $routed = @(Get-CimInstance -Namespace $space -ClassName MSFT_NetRoute -ErrorAction Stop | Where-Object { [PulsRig.Core.Netzwerk]::IsDefaultRoute($_.DestinationPrefix) } | ForEach-Object { [int]$_.InterfaceIndex } | Select-Object -Unique)
        $addresses = @($routed | ForEach-Object { Get-NetIPv4List $_ } | Where-Object { [PulsRig.Core.Netzwerk]::IsUsableAddress("$_") })
        $dhcp = [bool](Get-CimInstance -Namespace $space -ClassName MSFT_NetIPInterface -ErrorAction Stop |
                Where-Object { [PulsRig.Core.Netzwerk]::IsIPv4($_.AddressFamily) -and $routed -contains [int]$_.InterfaceIndex -and [PulsRig.Core.Netzwerk]::IsDhcp($_.Dhcp) })
        $dnsServer = @(Get-CimInstance -Namespace $space -ClassName MSFT_DNSClientServerAddress -ErrorAction Stop |
                Where-Object { [PulsRig.Core.Netzwerk]::IsIPv4($_.AddressFamily) } | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ }) | Select-Object -First 1
    }
    catch { }

    $internet = (Test-TcpPort '1.1.1.1' 443) -or (Test-TcpPort '8.8.8.8' 443)
    $dns = $false
    if ($dnsServer) {
        # direkt beim eingestellten Server fragen, damit kein Zwischenspeicher antwortet; "Name:" steht nur bei einer Antwort da
        try { $dns = [PulsRig.Core.Netzwerk]::IsDnsAnswer([string[]]@(& nslookup.exe '-type=A' '-timeout=4' 'www.microsoft.com' "$dnsServer" 2>$null)) } catch { }
    }
    $web = $false
    try {
        $ProgressPreference = 'SilentlyContinue'
        $web = (Invoke-WebRequest -UseBasicParsing -Uri 'http://www.msftconnecttest.com/connecttest.txt' -TimeoutSec 8).Content
        $web = [PulsRig.Core.Netzwerk]::IsConnectTest("$web")
    }
    catch { }

    [pscustomobject]@{
        Adapters = $adapters
        Dhcp     = $dhcp
        Checks   = [ordered]@{
            'Netzwerkadapter verbunden'   = $up.Count -gt 0
            'IP-Adresse und Gateway'      = $addresses.Count -gt 0
            'Internet erreichbar'         = $internet
            'Namensauflösung (DNS)'       = $dns
            'Webseiten abrufbar'          = $web
        }
    }
}

function Show-NetworkState($State) {
    foreach ($check in $State.Checks.GetEnumerator()) { Write-Check $check.Key $check.Value }
    -not ($State.Checks.Values -contains $false)
}

function Invoke-FixNetworkTool {
    Write-Host 'Prüfe die Verbindung ...'
    $state = Get-NetworkState
    foreach ($adapter in $state.Adapters) {
        Write-Host ("  Adapter: {0} ({1}) - {2}, {3}" -f $adapter.Name, $adapter.InterfaceDescription, (Format-State $adapter.Status), $adapter.LinkSpeed) -ForegroundColor DarkGray
    }
    $healthy = Show-NetworkState $state
    Write-Host ''

    if (@($state.Adapters).Count -eq 0) {
        Write-Host 'Windows kennt keinen Netzwerkadapter - vermutlich fehlt der Treiber. Dafür "Gerätefehler beheben" oder das Offline-Paket verwenden.' -ForegroundColor Yellow
        return
    }
    if ($healthy) {
        Write-Host 'Die Verbindung funktioniert.' -ForegroundColor Green
        if (-not (Confirm-Action 'Trotzdem DNS-Zwischenspeicher leeren und die Adresse erneuern?' -Optional)) { return }
    }
    elseif (-not $state.Checks['Netzwerkadapter verbunden']) {
        Write-Host 'Kein Adapter ist verbunden - zuerst Kabel bzw. WLAN prüfen.' -ForegroundColor Yellow
        if (-not (Confirm-Action 'Reparatur trotzdem versuchen?')) { return }
    }
    elseif (-not (Confirm-Action 'Reparatur starten (die Verbindung bricht dabei kurz ab)?')) { return }

    # Stufe 1: harmlos
    Invoke-Step 'DNS-Zwischenspeicher leeren' { Invoke-Native ipconfig.exe @('/flushdns') }
    if ($state.Dhcp) {
        Invoke-Step 'IP-Adresse freigeben und neu anfordern' {
            # /release meldet Code 1, wenn ein Adapter gerade getrennt ist - das ist kein Fehler
            Invoke-Native ipconfig.exe @('/release') @(0, 1)
            Invoke-Native ipconfig.exe @('/renew') @(0, 1)
        }
    }
    if (-not $DryRun -and (Show-NetworkState (Get-NetworkState))) {
        Write-Host 'Die Verbindung funktioniert wieder.' -ForegroundColor Green
        return
    }

    # Stufe 2: Adapter neu starten
    foreach ($adapter in $state.Adapters) {
        Invoke-Step "Adapter neu starten: $($adapter.Name)" { Restart-NetAdapter -Name $adapter.Name -Confirm:$false }
    }
    if (-not $DryRun) {
        Start-Sleep -Seconds 8
        if (Show-NetworkState (Get-NetworkState)) {
            Write-Host 'Die Verbindung funktioniert wieder.' -ForegroundColor Green
            return
        }
    }

    # Stufe 3: nur auf ausdrückliche Zustimmung
    Write-Host ''
    Write-Host 'Letzte Stufe: Netzwerkeinstellungen von Windows zurücksetzen (Winsock und TCP/IP).'
    Write-Host 'Dabei gehen fest eingetragene IP-Adressen verloren, und der PC muss neu gestartet werden.'
    if (-not (Confirm-Action 'Netzwerkeinstellungen zurücksetzen?' -Optional)) {
        Write-Host 'Nicht zurückgesetzt. Hilft auch das nicht, liegt es meist am Router, am Anbieter oder am Treiber.'
        return
    }
    New-SafetyPoint
    Invoke-Step 'Winsock zurücksetzen' { Invoke-Native netsh.exe @('winsock', 'reset') }
    Invoke-Step 'TCP/IP zurücksetzen' { Invoke-Native netsh.exe @('int', 'ip', 'reset') @(0, 1) }
    Write-Host 'Bitte den PC jetzt neu starten.' -ForegroundColor Yellow
}

# --- Schlechte Bildauflösung beheben ------------------------------------------

function Get-DisplayStatus {
    Import-PulsRigCore
    $names = @{}
    $native = @{}
    try {
        Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object {
            $names[($_.InstanceName -split '\\')[1]] = -join ($_.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
        }
        Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction Stop | ForEach-Object {
            $preferred = $_.MonitorSourceModes[$_.PreferredMonitorSourceModeIndex]
            $native[($_.InstanceName -split '\\')[1]] = @{ Width = [int]$preferred.HorizontalActivePixels; Height = [int]$preferred.VerticalActivePixels }
        }
    }
    catch { }

    foreach ($display in [PulsRig.Core.Display]::GetDisplays()) {
        $code = ("$($display.MonitorId)" -split '\\')[1]
        $best = $null
        if ($code -and $native.ContainsKey($code)) { $best = $native[$code] }
        if (-not $best) {
            # ohne Angabe des Monitors gilt der größte Modus des Treibers als empfohlen
            $largest = $display.Modes | Sort-Object { $_.Width * $_.Height } -Descending | Select-Object -First 1
            if ($largest) { $best = @{ Width = $largest.Width; Height = $largest.Height } }
        }
        $current = $display.Current
        # hochkant gedrehte Bildschirme melden Breite und Höhe vertauscht
        $isNative = $best -and $current -and (
            ($current.Width -eq $best.Width -and $current.Height -eq $best.Height) -or
            ($current.Width -eq $best.Height -and $current.Height -eq $best.Width))
        [pscustomobject]@{
            Device   = $display.Device
            Name     = if ($code -and $names[$code]) { $names[$code] } else { 'Bildschirm' }
            Primary  = $display.Primary
            Current  = $current
            Native   = $best
            IsNative = [bool]$isNative
            Modes    = $display.Modes
        }
    }
}

# Bildwiederholrate für die empfohlene Auflösung: die aktuelle, sonst 60 Hz, sonst die höchste
function Select-RefreshRate($Display) {
    Import-PulsRigCore
    $rates = [int[]]@($Display.Modes | Where-Object { $_.Width -eq $Display.Native.Width -and $_.Height -eq $Display.Native.Height } | ForEach-Object { $_.Frequency })
    $rate = [PulsRig.Core.Anzeige]::SelectRefreshRate($rates, $(if ($Display.Current) { [int]$Display.Current.Frequency } else { 0 }))
    if ($rate -gt 0) { $rate } else { $null }
}

function Invoke-FixResolutionTool {
    $adapters = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Display' })
    $withoutDriver = @($adapters | Where-Object { $_.Service -eq 'BasicDisplay' -or $_.ConfigManagerErrorCode -notin 0, 22 })
    foreach ($adapter in $adapters) {
        $ok = $withoutDriver -notcontains $adapter
        $detail = if ($adapter.Service -eq 'BasicDisplay') { 'läuft nur mit dem Windows-Standardtreiber' }
        elseif (-not $ok) { "meldet Fehlercode $($adapter.ConfigManagerErrorCode)" }
        else { 'Treiber geladen' }
        Write-Check "Grafikkarte $($adapter.Name)" $ok $detail
    }

    $displays = @()
    try { $displays = @(Get-DisplayStatus) }
    catch { Write-Host "  Die Bildschirmmodi ließen sich nicht auslesen: $($_.Exception.Message)" -ForegroundColor Yellow }
    foreach ($display in $displays) {
        $text = '{0}x{1} bei {2} Hz, empfohlen {3}x{4}' -f $display.Current.Width, $display.Current.Height,
            $display.Current.Frequency, $display.Native.Width, $display.Native.Height
        Write-Check "Bildschirm $($display.Name)" $display.IsNative $text
    }
    Write-Host ''

    if ($withoutDriver.Count -gt 0) {
        Write-Host 'Ursache: Der Grafikkarte fehlt ihr Treiber - ohne ihn bietet Windows nur niedrige Auflösungen an.' -ForegroundColor Yellow
        if (-not (Confirm-Action 'Grafiktreiber jetzt suchen und installieren?')) { return }
        if ($DryRun) {
            Write-Host '  [Probelauf] Treibersuche mit Installation starten' -ForegroundColor DarkGray
            return
        }
        $script:ScanOnly = $false
        $script:Install = $true
        Invoke-Main
        return
    }

    $wrong = @($displays | Where-Object { -not $_.IsNative -and $_.Native })
    if ($wrong.Count -eq 0) {
        Write-Host 'Alle Bildschirme laufen in ihrer empfohlenen Auflösung.' -ForegroundColor Green
        Write-Host 'Wirkt das Bild trotzdem unscharf oder zu groß, liegt es meist an der Skalierung.'
        if (Confirm-Action 'Anzeigeeinstellungen von Windows öffnen?' -Optional) { Start-Process 'ms-settings:display' }
        return
    }
    foreach ($display in $wrong) {
        $rate = Select-RefreshRate $display
        if (-not $rate) {
            Write-Host "  $($display.Name): Der Treiber bietet die empfohlene Auflösung nicht an - Kabel und Anschluss prüfen." -ForegroundColor Yellow
            continue
        }
        $target = '{0}x{1} bei {2} Hz' -f $display.Native.Width, $display.Native.Height, $rate
        if (-not (Confirm-Action "$($display.Name) auf $target stellen?")) { continue }
        Invoke-Step "Stelle $($display.Name) auf $target" {
            # erst nur prüfen lassen, ob der Treiber den Modus annimmt
            $test = [PulsRig.Core.Display]::SetMode($display.Device, $display.Native.Width, $display.Native.Height, $rate, $true)
            if ($test -ne 0) { throw "der Treiber lehnt den Modus ab (Code $test)" }
            $result = [PulsRig.Core.Display]::SetMode($display.Device, $display.Native.Width, $display.Native.Height, $rate, $false)
            if ($result -ne 0) { throw "Windows meldet Code $result" }
        }
    }
}

# --- Fehlende Spiel-DLLs beheben ----------------------------------------------

$script:VcRuntimes = @(
    # Latest nur dort, wo Microsoft die letzte Fassung veröffentlicht hat und sie sich aus der Registry ablesen lässt
    @{ Name = 'Visual C++ 2005';      Pattern = 'Visual C\+\+ 2005 Redistributable'; Latest = $null
       x64 = 'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.EXE'
       x86 = 'https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE' }
    @{ Name = 'Visual C++ 2008';      Pattern = 'Visual C\+\+ 2008 Redistributable'; Latest = $null
       x64 = 'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe'
       x86 = 'https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe' }
    @{ Name = 'Visual C++ 2010';      Pattern = 'Visual C\+\+ 2010\s+x\d\d Redistributable'; Latest = $null
       x64 = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe'
       x86 = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe' }
    @{ Name = 'Visual C++ 2012';      Pattern = 'Visual C\+\+ 2012 Redistributable'; Latest = '11.0.61030'
       x64 = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe'
       x86 = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe' }
    @{ Name = 'Visual C++ 2013';      Pattern = 'Visual C\+\+ 2013 Redistributable'; Latest = '12.0.40664'
       x64 = 'https://aka.ms/highdpimfc2013x64enu'
       x86 = 'https://aka.ms/highdpimfc2013x86enu' }
    @{ Name = 'Visual C++ 2015-2022'; Pattern = 'Visual C\+\+ (2015|2017|2019|2022|v14)\S* Redistributable'; Latest = $null
       x64 = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
       x86 = 'https://aka.ms/vs/17/release/vc_redist.x86.exe' }
)

function Get-RuntimeStatus {
    Import-PulsRigCore
    $installed = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
            Where-Object { [PulsRig.Core.Laufzeiten]::IsRuntimeEntry("$($_.DisplayName)") })

    $names = @($installed | ForEach-Object { "$($_.DisplayName)" })
    $versions = @($installed | ForEach-Object { "$($_.DisplayVersion)" })
    foreach ($runtime in $script:VcRuntimes) {
        foreach ($arch in 'x64', 'x86') {
            $found = [PulsRig.Core.Laufzeiten]::Evaluate([string[]]$names, [string[]]$versions, $runtime.Pattern, $arch -eq 'x64', "$($runtime.Latest)")
            [pscustomobject]@{
                Name    = "$($runtime.Name) ($arch)"
                Status  = $found.Status
                Version = $found.Version
                Url     = $runtime[$arch]
                File    = 'vcredist_{0}_{1}.exe' -f ($runtime.Name -replace '\D', ''), $arch
            }
        }
    }

    # DirectX 9 bis 11: die Zusatzbibliotheken alter Spiele (Stand Juni 2010)
    $directX = 'd3dx9_43.dll', 'd3dx10_43.dll', 'd3dx11_43.dll', 'D3DCompiler_43.dll', 'xinput1_3.dll', 'XAudio2_7.dll', 'X3DAudio1_7.dll'
    $missing = @($directX | Where-Object {
            -not (Test-Path "$env:windir\System32\$_") -or
            ((Test-Path "$env:windir\SysWOW64") -and -not (Test-Path "$env:windir\SysWOW64\$_")) })
    [pscustomobject]@{
        Name    = 'DirectX-Zusatzbibliotheken (9 bis 11)'
        Status  = if ($missing.Count -eq 0) { 'vorhanden' } else { 'fehlt' }
        Version = if ($missing.Count -gt 0) { "es fehlen: $($missing -join ', ')" } else { '' }
        Url     = 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe'
        File    = 'dxwebsetup.exe'
    }

    $xna = [bool](Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\XNA\Framework\v4.0', 'HKLM:\SOFTWARE\Microsoft\XNA\Framework\v4.0' -ErrorAction SilentlyContinue |
            Where-Object { $_.Installed -eq 1 })
    [pscustomobject]@{
        Name    = 'XNA Framework 4.0'
        Status  = if ($xna) { 'vorhanden' } else { 'fehlt' }
        Version = ''
        Url     = 'https://download.microsoft.com/download/A/C/2/AC2C903B-E6E8-42C2-9FD7-BEBAC362A930/xnafx40_redist.msi'
        File    = 'xnafx40_redist.msi'
    }

    $openAl = (Test-Path "$env:windir\System32\OpenAL32.dll") -or (Test-Path "$env:windir\SysWOW64\OpenAL32.dll")
    [pscustomobject]@{
        Name    = 'OpenAL'
        Status  = if ($openAl) { 'vorhanden' } else { 'fehlt' }
        Version = if ($openAl) { '' } else { 'nicht von Microsoft - nur von Hand: https://www.openal.org/downloads/' }
        Url     = $null
        File    = $null
    }
}

function Invoke-GameRuntimesTool {
    $status = @(Get-RuntimeStatus)
    $number = 0
    $candidates = @()
    foreach ($item in $status) {
        $label = '   '
        if ($item.Status -ne 'vorhanden' -and $item.Url) {
            $number++
            $label = '{0,2}.' -f $number
            $candidates += $item
        }
        $color = switch ($item.Status) { 'vorhanden' { 'Green' } 'veraltet' { 'Yellow' } default { 'DarkGray' } }
        Write-Host ('  {0} {1,-40} {2,-10} {3}' -f $label, $item.Name, $item.Status, $item.Version) -ForegroundColor $color
    }
    Write-Host ''
    Write-Host 'Fehlende Bibliotheken sind kein Fehler: Sie werden nur gebraucht, wenn ein Spiel sie verlangt,'
    Write-Host 'und die meisten Spiele bringen sie selbst mit.'
    # vom Fenster vorgegebene Auswahl: genau diese Einträge, auch zum erneuten Installieren
    $plan = @($global:RuntimePlan | Where-Object { $_ })
    if ($candidates.Count -eq 0 -and $plan.Count -eq 0) { return }

    $selected = @()
    if ($plan.Count -gt 0) {
        $selected = @($status | Where-Object { $_.Url -and $plan -contains $_.Name })
    }
    elseif ($Yes -or $DryRun) {
        # ohne Rückfrage nur das, was wirklich überholt ist - Fehlendes bleibt eine bewusste Entscheidung
        $selected = @($candidates | Where-Object { $_.Status -eq 'veraltet' })
    }
    else {
        try { $answer = "$(Read-Host 'Welche installieren? Nummern mit Komma, "alle" oder Eingabetaste für keine')".Trim() } catch { $answer = '' }
        if ($answer -match '^(alle|all)$') { $selected = $candidates }
        elseif ($answer) {
            foreach ($part in ($answer -split '[,\s]+')) {
                if ($part -match '^\d+$' -and [int]$part -ge 1 -and [int]$part -le $candidates.Count) { $selected += $candidates[[int]$part - 1] }
            }
        }
    }
    if ($selected.Count -eq 0) { return }

    $folder = Join-Path $OutDir 'Laufzeiten'
    if (-not $DryRun -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    Write-Host 'Die Installer kommen direkt von Microsoft und öffnen sich nacheinander - dort jeweils selbst bestätigen.'
    foreach ($item in $selected) {
        $file = Join-Path $folder $item.File
        Invoke-Step "Lade und starte $($item.Name)" {
            Save-SignedDownload $item.Url $file 'O=Microsoft Corporation' @('aka.ms', 'download.microsoft.com')
            Start-SignedInstaller $file 'O=Microsoft Corporation'
        }
    }
}

# Einzelne Bibliotheken, nach denen Spiele fragen, und die Komponente, die sie mitbringt.
# Visual C++ 2005 und 2008 fehlen hier: Ihre Dateien liegen nicht im Systemordner, sondern im Komponentenspeicher.
$script:RuntimeFiles = [ordered]@{
    'Visual C++ 2010'      = 'msvcr100.dll', 'msvcp100.dll', 'mfc100.dll', 'mfc100u.dll', 'atl100.dll', 'vcomp100.dll'
    'Visual C++ 2012'      = 'msvcr110.dll', 'msvcp110.dll', 'mfc110.dll', 'mfc110u.dll', 'atl110.dll', 'vcomp110.dll', 'vccorlib110.dll'
    'Visual C++ 2013'      = 'msvcr120.dll', 'msvcp120.dll', 'mfc120.dll', 'mfc120u.dll', 'vcomp120.dll', 'vccorlib120.dll'
    'Visual C++ 2015-2022' = 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
        'concrt140.dll', 'vcomp140.dll', 'vccorlib140.dll', 'mfc140.dll', 'mfc140u.dll'
    'DirectX-Zusatzbibliotheken (9 bis 11)' = @(
        24..43 | ForEach-Object { "d3dx9_$_.dll" }
        33..43 | ForEach-Object { "d3dx10_$_.dll" }
        'd3dx11_42.dll', 'd3dx11_43.dll', 'd3dcsx_43.dll'
        33..43 | ForEach-Object { "D3DCompiler_$_.dll" }
        'xinput1_1.dll', 'xinput1_2.dll', 'xinput1_3.dll'
        0..7 | ForEach-Object { "XAudio2_$_.dll" }
        0..7 | ForEach-Object { "X3DAudio1_$_.dll" }
        0..5 | ForEach-Object { "XAPOFX1_$_.dll" }
        0..7 | ForEach-Object { "xactengine3_$_.dll" })
    'OpenAL'               = 'OpenAL32.dll', 'wrap_oal.dll'
}

# Prüft jede Bibliothek für 64 und 32 Bit; Component nennt den passenden Eintrag aus Get-RuntimeStatus
function Get-RuntimeFiles {
    $folders = [ordered]@{ x64 = "$env:windir\System32" }
    if (Test-Path "$env:windir\SysWOW64") { $folders['x86'] = "$env:windir\SysWOW64" }
    foreach ($group in $script:RuntimeFiles.Keys) {
        foreach ($file in $script:RuntimeFiles[$group]) {
            foreach ($arch in $folders.Keys) {
                if ($file -eq 'vcruntime140_1.dll' -and $arch -eq 'x86') { continue }   # gibt es nur für 64 Bit
                [pscustomobject]@{
                    Name      = $file
                    Arch      = $arch
                    Group     = $group
                    Component = if ($group -like 'Visual C++*') { "$group ($arch)" } else { $group }
                    Status    = if (Test-Path -LiteralPath (Join-Path $folders[$arch] $file)) { 'vorhanden' } else { 'fehlt' }
                }
            }
        }
    }
}

# --- Inkompatible Treiber reparieren ------------------------------------------

# Prüft den Aufbau einer Treiberdatei gegen die Regeln der Kernisolierung (Speicher-Integrität):
# kein Abschnitt darf zugleich beschreibbar und ausführbar sein, und alle müssen seitenweise ausgerichtet sein.
# Das ist eine Prüfung der Datei, nicht des laufenden Treibers - was ein Treiber erst zur Laufzeit falsch
# macht, findet sie nicht.
function Get-HvciIssues([string]$Path) {
    Import-PulsRigCore
    [PulsRig.Core.Treiber]::HvciIssues($Path)
}

function Resolve-DriverPath([string]$PathName) {
    Import-PulsRigCore
    [PulsRig.Core.Treiber]::ResolveDriverPath($PathName, $env:windir)
}

# oemNN.inf -> ursprünglicher Name, aus der (übersetzten) Ausgabe von pnputil nach Position gelesen
function Get-DriverPackages {
    Import-PulsRigCore
    [PulsRig.Core.Sicherung]::ParsePackages([string[]]@(& pnputil.exe /enum-drivers))
}

function Find-IncompatibleDrivers {
    $services = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.PathName })
    $files = @{}
    Get-ChildItem -LiteralPath "$env:windir\System32\drivers" -Filter '*.sys' -File | ForEach-Object { $files[$_.FullName.ToLower()] = $_.FullName }
    foreach ($service in $services) {
        $path = Resolve-DriverPath $service.PathName
        if ($path -like '*.sys' -and (Test-Path -LiteralPath $path)) { $files[$path.ToLower()] = $path }
    }

    $packages = $null
    foreach ($path in ($files.Values | Sort-Object)) {
        $issues = @()
        try { $issues = @(Get-HvciIssues $path) } catch { continue }
        if ($issues.Count -eq 0) { continue }

        $name = Split-Path -Leaf $path
        $service = $services | Where-Object { (Split-Path -Leaf (Resolve-DriverPath $_.PathName)) -eq $name } | Select-Object -First 1
        # der Ordner im Treiberspeicher trägt den Namen der INF-Datei, zu der die Treiberdatei gehört
        if ($null -eq $packages) { $packages = @(Get-DriverPackages) }
        $folder = Get-ChildItem -LiteralPath "$env:windir\System32\DriverStore\FileRepository" -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $name) } | Select-Object -First 1
        $package = $null
        if ($folder) {
            $original = $folder.Name -replace '\.inf_.*$', '.inf'
            $package = $packages | Where-Object { $_.Original -eq $original } | Select-Object -First 1
        }
        [pscustomobject]@{
            File    = $path
            Company = (Get-Item -LiteralPath $path).VersionInfo.CompanyName
            Issues  = $issues
            Running = [bool]($service -and $service.State -eq 'Running')
            Service = if ($service) { $service.Name } else { $null }
            Package = $package
        }
    }
}

function Invoke-IncompatibleDriversTool {
    $integrity = $false
    try {
        $guard = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        $integrity = @($guard.SecurityServicesRunning) -contains 2
    }
    catch { }
    Write-Host ("Kernisolierung (Speicher-Integrität): {0}" -f $(if ($integrity) { 'eingeschaltet' } else { 'ausgeschaltet' }))
    Write-Host 'Prüfe alle Treiberdateien gegen die Regeln der Kernisolierung ...'

    $found = @(Find-IncompatibleDrivers)
    if ($found.Count -eq 0) {
        Write-Host 'Keine inkompatiblen Treiber gefunden.' -ForegroundColor Green
        return
    }
    $inUse = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.InfName } | ForEach-Object { $_.InfName.ToLower() })
    $headline = if ($found.Count -eq 1) { 'Ein Treiber verträgt sich nicht mit der Kernisolierung:' }
    else { "$($found.Count) Treiber vertragen sich nicht mit der Kernisolierung:" }
    Write-Host $headline -ForegroundColor Yellow
    $removable = @()
    foreach ($driver in $found) {
        Write-Host ("  - {0} ({1})" -f (Split-Path -Leaf $driver.File), $driver.Company)
        $driver.Issues | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        $used = $driver.Running -or ($driver.Package -and $inUse -contains $driver.Package.Published.ToLower())
        if ($used) {
            Write-Host '      Wird gerade verwendet - beim Hersteller nach einer neueren Version suchen.' -ForegroundColor DarkGray
        }
        elseif ($driver.Package) {
            Write-Host ("      Derzeit unbenutzt, Treiberpaket {0} ({1})." -f $driver.Package.Published, $driver.Package.Original) -ForegroundColor DarkGray
            $removable += $driver
        }
        else {
            Write-Host '      Kein eigenes Treiberpaket - gehört zu Windows oder zu einem installierten Programm.' -ForegroundColor DarkGray
        }
    }
    if (-not $integrity) {
        Write-Host 'Solange solche Treiber installiert sind, lässt sich die Speicher-Integrität in Windows-Sicherheit nicht einschalten.'
    }

    $packages = @($removable | ForEach-Object { $_.Package } | Sort-Object Published -Unique)
    if ($packages.Count -eq 0) { return }
    Write-Host 'Unbenutzte Pakete lassen sich entfernen. Wird das zugehörige Gerät später wieder angeschlossen,'
    Write-Host 'braucht es dann einen neuen (aktuelleren) Treiber.'
    if (-not (Confirm-Action "$($packages.Count) unbenutzte(s) Treiberpaket(e) entfernen?")) { return }
    New-SafetyPoint
    foreach ($package in $packages) {
        Invoke-Step "Entferne $($package.Published) ($($package.Original))" {
            Invoke-Native pnputil.exe @('/delete-driver', $package.Published, '/uninstall') @(0, 3010)
        }
    }
}

# --- Offline-Treiberpaket -----------------------------------------------------

# Ungefähre Größe des Offline-Pakets in Bytes: die Ordner der Drittanbieter-Treiber im DriverStore.
# Liegen dort mehrere Fassungen eines Treibers, zählen alle mit - die Schätzung liegt eher zu hoch.
function Get-OfflinePackageSize {
    Import-PulsRigCore
    $repository = Join-Path $env:windir 'System32\DriverStore\FileRepository'
    $names = [PulsRig.Core.OfflinePaket]::OriginalNames([string[]]@(& pnputil.exe /enum-drivers))
    $size = 0
    foreach ($name in $names) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $repository -Directory -Filter "$($name)_*" -ErrorAction SilentlyContinue)) {
            $size += (Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        }
    }
    [long]$size
}

# $Package: '*' für alle Treiber von Drittherstellern oder ein einzelnes Paket wie oem12.inf
function New-OfflinePackage([string]$TargetRoot, [string]$Package = '*') {
    $target = Join-Path $TargetRoot ('Offline-Paket_{0:yyyy-MM-dd_HHmm}' -f (Get-Date))
    $drivers = Join-Path $target 'Treiber'
    Write-Host 'Das Paket enthält alle installierten Treiber von Drittherstellern samt Startdatei zum Einspielen -'
    Write-Host 'gedacht für diesen PC nach einer Neuinstallation von Windows, auch ohne Internet.'
    if ($DryRun) {
        Write-Host "  [Probelauf] Treiber exportieren nach $target" -ForegroundColor DarkGray
        return
    }

    Import-PulsRigCore
    New-Item -ItemType Directory -Path $drivers -Force | Out-Null
    Write-Host 'Exportiere Treiber (kann einige Minuten dauern) ...'
    & pnputil.exe /export-driver $Package $drivers | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        # ein halbes Paket hilft niemandem und belegt nur Platz
        Remove-Item -LiteralPath $target -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        # 112: Datenträger voll
        Write-Host ([PulsRig.Core.OfflinePaket]::ExportError($code)) -ForegroundColor Red
        $script:ExitCode = 1
        return
    }

    Set-Content -LiteralPath (Join-Path $target 'Treiber-installieren.bat') -Value ([PulsRig.Core.OfflinePaket]::Starter()) -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $target 'LIESMICH.txt') -Value ([PulsRig.Core.OfflinePaket]::Readme((Get-Date))) -Encoding UTF8
    [void](Export-HardwareReport @(Get-InstalledDrivers) $target)

    $files = @(Get-ChildItem -LiteralPath $drivers -Recurse -File)
    $size = ($files | Measure-Object Length -Sum).Sum
    $count = @($files | Where-Object { $_.Extension -eq '.inf' }).Count
    Write-Host ("Paket fertig: {0} Treiberpakete, {1:N0} MB" -f $count, ($size / 1MB)) -ForegroundColor Green
    Write-Host "Ordner: $target"
}

# --- Systeminformationen ------------------------------------------------------

function Get-SystemInfoLines {
    Import-PulsRigCore
    $system = Get-CimInstance Win32_ComputerSystem
    $board = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $release = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    'WINDOWS'
    '  {0}, Version {1} (Build {2}.{3})' -f $os.Caption, $release.DisplayVersion, $os.BuildNumber, $release.UBR
    '  Installiert am {0}, läuft seit {1}' -f (Format-Date $os.InstallDate), $os.LastBootUpTime.ToString('dd.MM.yyyy HH:mm')
    ''
    'GERÄT'
    if (-not [PulsRig.Core.Systeminfo]::IsPlaceholder("$($system.Manufacturer)")) {
        '  System:     {0} {1}' -f $system.Manufacturer, $system.Model
    }
    '  Mainboard:  {0} {1}' -f $board.Manufacturer, $board.Product
    '  BIOS:       {0} vom {1}' -f $bios.SMBIOSBIOSVersion, (Format-Date $bios.ReleaseDate)
    ''
    'PROZESSOR'
    '  {0}' -f $cpu.Name.Trim()
    '  {0} Kerne, {1} Threads, bis {2:N1} GHz' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, ($cpu.MaxClockSpeed / 1000)
    ''
    'ARBEITSSPEICHER'
    '  Gesamt {0:N0} GB' -f ($system.TotalPhysicalMemory / 1GB)
    foreach ($module in @(Get-CimInstance Win32_PhysicalMemory)) {
        '  {0}: {1:N0} GB, {2} MHz, {3}' -f ("$($module.BankLabel) $($module.DeviceLocator)".Trim()), ($module.Capacity / 1GB),
            $module.ConfiguredClockSpeed, "$($module.PartNumber)".Trim()
    }
    ''
    'GRAFIK'
    # Win32_VideoController kennt höchstens 4 GB Speicher - die echte Größe steht in der Registry
    $memory = @{}
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DriverDesc -and $_.'HardwareInformation.qwMemorySize') { $memory[$_.DriverDesc] = [long]$_.'HardwareInformation.qwMemorySize' }
    }
    foreach ($gpu in @(Get-CimInstance Win32_VideoController)) {
        $bytes = [PulsRig.Core.Systeminfo]::GpuMemory([long]$memory[$gpu.Name], [long]$gpu.AdapterRAM)
        '  {0}, {1:N0} GB, Treiber {2}' -f $gpu.Name, ($bytes / 1GB), $gpu.DriverVersion
    }
    try {
        foreach ($display in @(Get-DisplayStatus)) {
            '  Bildschirm {0}: {1}x{2} bei {3} Hz{4}' -f $display.Name, $display.Current.Width, $display.Current.Height,
                $display.Current.Frequency, $(if ($display.Primary) { ' (Hauptbildschirm)' })
        }
    }
    catch { }
    ''
    'DATENTRÄGER'
    try {
        foreach ($disk in @(Get-DiskList | Sort-Object { [int]$_.DeviceId })) {
            $type = [PulsRig.Core.Systeminfo]::DiskType("$($disk.MediaType)", 'Laufwerk')
            $health = [PulsRig.Core.Systeminfo]::Health("$($disk.HealthStatus)")
            '  {0}: {1:N0} GB, {2} über {3}, Zustand {4}' -f $disk.FriendlyName, ($disk.Size / 1GB), $type, $disk.BusType, $health
        }
    }
    catch { }
    foreach ($volume in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        '  Laufwerk {0} {1:N0} GB, davon {2:N0} GB frei' -f $volume.DeviceID, ($volume.Size / 1GB), ($volume.FreeSpace / 1GB)
    }
    ''
    'NETZWERK'
    foreach ($adapter in @(Get-NetAdapterList)) {
        '  {0}: {1}, {2}{3}' -f $adapter.Name, $adapter.InterfaceDescription, (Format-State $adapter.Status), $(if ($adapter.Status -eq 'Up') { ", $($adapter.LinkSpeed)" })
    }
    ''
    'AUDIO'
    foreach ($sound in @(Get-CimInstance Win32_SoundDevice)) { '  {0}' -f $sound.Name }
    ''
    'TREIBER'
    $installed = @(Get-InstalledDrivers)
    '  {0} Geräte mit Treiber, {1} davon von Drittherstellern' -f $installed.Count,
        @($installed | Where-Object { [PulsRig.Core.Systeminfo]::IsThirdParty("$($_.DriverProviderName)") }).Count
    '  Geräte mit Fehlern: {0}' -f @(Get-ProblemDevices).Count
}

function Invoke-SystemInfoTool {
    $lines = @(Get-SystemInfoLines)
    foreach ($line in $lines) {
        if ($line -cmatch '^[A-ZÄÖÜ]+$') { Write-Host $line -ForegroundColor Cyan } else { Write-Host $line }
    }
    if ($DryRun) { return }
    $file = Join-Path $OutDir 'Systeminformationen.txt'
    Set-Content -LiteralPath $file -Value $lines -Encoding UTF8
    Write-Host ''
    Write-Host "Gespeichert: $file"
}

# Dieselben Angaben, geordnet nach Bereichen - für die Ansicht mit Reitern im Fenster.
# Jede Zeile nennt ihren Bereich (Category) und ist Überschrift (head) oder Schlüssel mit Wert (pair).
function Get-SystemInfoData {
    Import-PulsRigCore
    $rows = New-Object System.Collections.Generic.List[object]
    $category = ''
    function Head([string]$Text) { $rows.Add([pscustomobject]@{ Category = $category; Kind = 'head'; Title = $Text; Value = '' }) }
    function Pair([string]$Key, $Value) {
        $text = "$Value".Trim()
        if ($text) { $rows.Add([pscustomobject]@{ Category = $category; Kind = 'pair'; Title = $Key; Value = $text }) }
    }

    $system = Get-CimInstance Win32_ComputerSystem
    $board = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $release = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $gpus = @(Get-CimInstance Win32_VideoController)
    $modules = @(Get-CimInstance Win32_PhysicalMemory)
    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')
    $sounds = @(Get-CimInstance Win32_SoundDevice)
    $keyboards = @(Get-CimInstance Win32_Keyboard)
    $mice = @(Get-CimInstance Win32_PointingDevice)
    $displays = @()
    try { $displays = @(Get-DisplayStatus) } catch { }
    # Speichergröße und Treiberdatum der Grafikkarten stehen verlässlich nur in der Registry
    $gpuInfo = @{}
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DriverDesc) {
            $gpuInfo[$_.DriverDesc] = @{ Memory = [long]$_.'HardwareInformation.qwMemorySize'; Date = [PulsRig.Core.Systeminfo]::DriverDate("$($_.DriverDate)") }
        }
    }
    $freeBytes = [double]$os.FreePhysicalMemory * 1KB
    $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB

    $category = 'Übersicht'
    Pair 'Windows' ('{0}, Version {1}' -f $os.Caption, $release.DisplayVersion)
    Pair 'Prozessor' $cpu.Name
    foreach ($gpu in $gpus) {
        $bytes = [PulsRig.Core.Systeminfo]::GpuMemory([long]$gpuInfo[$gpu.Name].Memory, [long]$gpu.AdapterRAM)
        Pair 'Grafikkarte' ('{0} ({1:N0} GB)' -f $gpu.Name, ($bytes / 1GB))
    }
    Pair 'Arbeitsspeicher' ('{0:N1} GB frei von {1:N1} GB' -f ($freeBytes / 1GB), ($totalBytes / 1GB))
    foreach ($display in $displays) {
        Pair 'Bildschirm' ('{0} ({1} x {2} bei {3} Hz)' -f $display.Name, $display.Current.Width, $display.Current.Height, $display.Current.Frequency)
    }
    if ($volumes.Count -gt 0) {
        Pair 'Datenträger' ('{0:N0} GB frei von {1:N0} GB' -f (($volumes | Measure-Object FreeSpace -Sum).Sum / 1GB), (($volumes | Measure-Object Size -Sum).Sum / 1GB))
    }
    Pair 'Audio' (@($sounds | ForEach-Object { $_.Name } | Select-Object -Unique -First 3) -join ', ')
    Pair 'Mainboard' ('{0} {1}' -f $board.Manufacturer, $board.Product)
    Pair 'Tastatur' ($keyboards | Select-Object -First 1).Description
    Pair 'Maus' ($mice | Select-Object -First 1).Name

    $category = 'Windows'
    Head 'Computer'

    if (-not [PulsRig.Core.Systeminfo]::IsPlaceholder("$($system.Manufacturer)")) {
        Pair 'Hersteller und Modell' ('{0} {1}' -f $system.Manufacturer, $system.Model)
    }
    Head 'Betriebssystem'
    Pair 'Edition' $os.Caption
    Pair 'Version' ('{0} (Build {1}.{2})' -f $release.DisplayVersion, $os.BuildNumber, $release.UBR)
    Pair 'Architektur' $os.OSArchitecture
    Pair 'Installiert am' (Format-Date $os.InstallDate)
    Pair 'Läuft seit' $os.LastBootUpTime.ToString('dd.MM.yyyy HH:mm')
    Pair 'Startmodus' $env:firmware_type
    $integrity = Get-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    Pair 'Kernisolierung (Speicher-Integrität)' $(if ($integrity -eq 1) { 'eingeschaltet' } else { 'ausgeschaltet' })
    Pair 'Sprache' (Get-Culture).DisplayName
    Pair 'Zeitzone' ([TimeZoneInfo]::Local.DisplayName)

    $category = 'Prozessor'
    Head 'Prozessor'
    Pair 'Name' $cpu.Name
    Pair 'Hersteller' $cpu.Manufacturer
    Pair 'Kerne und Threads' ('{0} Kerne, {1} Threads' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    Pair 'Takt' ('bis {0:N1} GHz' -f ($cpu.MaxClockSpeed / 1000))
    Pair 'Sockel' $cpu.SocketDesignation
    if ($cpu.L3CacheSize) { Pair 'Zwischenspeicher' ('L2 {0:N0} MB, L3 {1:N0} MB' -f ($cpu.L2CacheSize / 1024), ($cpu.L3CacheSize / 1024)) }
    Head 'Mainboard'
    Pair 'Hersteller' $board.Manufacturer
    Pair 'Modell' $board.Product
    Pair 'BIOS-Version' $bios.SMBIOSBIOSVersion
    Pair 'BIOS-Datum' (Format-Date $bios.ReleaseDate)

    $category = 'Speicher'
    Head 'Arbeitsspeicher'
    Pair 'Gesamt' ('{0:N1} GB' -f ($totalBytes / 1GB))
    Pair 'Frei' ('{0:N1} GB' -f ($freeBytes / 1GB))
    foreach ($module in $modules) {
        Head ("Riegel in $("$($module.BankLabel) $($module.DeviceLocator)".Trim())")
        Pair 'Größe' ('{0:N0} GB' -f ($module.Capacity / 1GB))
        if ($module.ConfiguredClockSpeed) { Pair 'Takt' "$($module.ConfiguredClockSpeed) MHz" }
        Pair 'Hersteller' $module.Manufacturer
        Pair 'Teilenummer' $module.PartNumber
    }

    $category = 'Grafik'
    foreach ($gpu in $gpus) {
        $info = $gpuInfo[$gpu.Name]
        $bytes = [PulsRig.Core.Systeminfo]::GpuMemory([long]$info.Memory, [long]$gpu.AdapterRAM)
        Head $gpu.Name
        Pair 'Speicher' ('{0:N0} GB' -f ($bytes / 1GB))
        Pair 'Treiberversion' $gpu.DriverVersion
        if ($info.Date) { Pair 'Treiberdatum' (Format-Date $info.Date) }
        Pair 'Hersteller' $gpu.AdapterCompatibility
    }
    foreach ($display in $displays) {
        Head "Bildschirm $($display.Name)"
        Pair 'Auflösung' ('{0} x {1}' -f $display.Current.Width, $display.Current.Height)
        Pair 'Bildwiederholrate' "$($display.Current.Frequency) Hz"
        Pair 'Hauptbildschirm' $(if ($display.Primary) { 'ja' } else { 'nein' })
    }

    $category = 'Laufwerke'
    try {
        foreach ($disk in @(Get-DiskList | Sort-Object { [int]$_.DeviceId })) {
            Head $disk.FriendlyName
            Pair 'Größe' ('{0:N0} GB' -f ($disk.Size / 1GB))
            Pair 'Art' ([PulsRig.Core.Systeminfo]::DiskType("$($disk.MediaType)", 'unbekannt'))
            Pair 'Anschluss' $disk.BusType
            Pair 'Zustand' ([PulsRig.Core.Systeminfo]::Health("$($disk.HealthStatus)"))
        }
    }
    catch { }
    if ($volumes.Count -gt 0) {
        Head 'Partitionen'
        foreach ($volume in $volumes) {
            $label = if ($volume.VolumeName) { "Laufwerk $($volume.DeviceID) ($($volume.VolumeName))" } else { "Laufwerk $($volume.DeviceID)" }
            Pair $label ('{0:N0} GB, davon {1:N0} GB frei' -f ($volume.Size / 1GB), ($volume.FreeSpace / 1GB))
        }
    }

    $category = 'Netzwerk'
    foreach ($adapter in @(Get-NetAdapterList)) {
        Head $adapter.Name
        Pair 'Gerät' $adapter.InterfaceDescription
        Pair 'Status' (Format-State $adapter.Status)
        if ($adapter.Status -eq 'Up') {
            Pair 'Geschwindigkeit' $adapter.LinkSpeed
            $address = @(Get-NetIPv4List $adapter.ifIndex) -join ', '
            Pair 'IPv4-Adresse' $address
        }
        Pair 'MAC-Adresse' $adapter.MacAddress
    }

    $category = 'Geräte'
    if ($sounds.Count -gt 0) {
        Head 'Audio'
        foreach ($sound in $sounds) { Pair $sound.Name $(if ($sound.Manufacturer) { $sound.Manufacturer } else { 'vorhanden' }) }
    }
    Head 'Eingabegeräte'
    foreach ($keyboard in $keyboards) { Pair 'Tastatur' $keyboard.Description }
    foreach ($mouse in $mice) { Pair 'Maus' $mouse.Name }
    $controllers = @(Get-CimInstance Win32_USBController)
    if ($controllers.Count -gt 0) {
        Head 'USB-Controller'
        foreach ($controller in $controllers) { Pair $controller.Name $(if ($controller.Manufacturer) { $controller.Manufacturer } else { 'vorhanden' }) }
    }
    Head 'Treiber'
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -Property DeviceName, DriverVersion, DriverProviderName | Where-Object { $_.DeviceName -and $_.DriverVersion })
    Pair 'Geräte mit Treiber' $drivers.Count
    Pair 'davon von Drittherstellern' @($drivers | Where-Object { [PulsRig.Core.Systeminfo]::IsThirdParty("$($_.DriverProviderName)") }).Count
    Pair 'Geräte mit Fehlern' @(Get-ProblemDevices).Count

    $rows
}

# Was Windows Update an Treibern eingespielt hat, und wann welches Treiberpaket ins System kam
function Get-DriverHistory {
    Import-PulsRigCore
    $updates = @()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        if ($total -gt 0) {
            foreach ($entry in $searcher.QueryHistory(0, [Math]::Min($total, 400))) {
                $title = "$($entry.Title)"
                if (-not $title) { continue }
                if (-not [PulsRig.Core.Verlauf]::IsDriverUpdate($title)) { continue }
                $date = ([datetime]$entry.Date).ToLocalTime()
                $updates += [pscustomobject]@{
                    Title    = $title
                    Date     = $date
                    DateText = $date.ToString('dd.MM.yyyy HH:mm')
                    Result   = [PulsRig.Core.Verlauf]::Result([int]$entry.ResultCode)
                    Removed  = [int]$entry.Operation -eq 2
                }
            }
        }
    }
    catch { }

    $packages = @()
    $drivers = @(Get-CimInstance Win32_PnPSignedDriver -Property InfName, DeviceName, DriverProviderName, DriverVersion |
            Where-Object { $_.InfName -like 'oem*.inf' })
    foreach ($group in ($drivers | Group-Object InfName)) {
        $file = Join-Path "$env:windir\INF" $group.Name
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $first = $group.Group[0]
        $names = @($group.Group | ForEach-Object { $_.DeviceName } | Select-Object -Unique)
        $added = (Get-Item -LiteralPath $file).CreationTime
        $packages += [pscustomobject]@{
            Inf      = $group.Name
            Added    = $added
            DateText = $added.ToString('dd.MM.yyyy')
            Provider = "$($first.DriverProviderName)"
            Version  = "$($first.DriverVersion)"
            Devices  = [PulsRig.Core.Verlauf]::Devices([string[]]$names)
        }
    }
    @{ Updates = @($updates | Sort-Object Date -Descending); Packages = @($packages | Sort-Object Added -Descending) }
}

# --- Spiel-Beschleunigung -----------------------------------------------------

# Dienste, die beim Spielen nichts beitragen: Suchindex, Vorabladen, Drucken, Telemetrie, Karten, Fax,
# Fehlerberichte, Scanner, Update-Verteilung. Sie werden nur angehalten, nicht deaktiviert.
$script:BoostServices = 'WSearch', 'SysMain', 'Spooler', 'DiagTrack', 'MapsBroker', 'Fax', 'WerSvc', 'stisvc', 'DoSvc'

# Programme, die nie zum Schließen angeboten werden: Windows selbst, dieses Fenster, Spiele-Starter, Grafiktreiber
$script:BoostKeep = @(
    'explorer', 'dwm', 'sihost', 'ShellHost', 'StartMenuExperienceHost', 'ShellExperienceHost', 'SearchHost',
    'TextInputHost', 'RuntimeBroker', 'svchost', 'taskhostw', 'ctfmon', 'conhost', 'cmd', 'powershell', 'pwsh',
    'WindowsTerminal', 'OpenConsole', 'ApplicationFrameHost', 'SystemSettings', 'LockApp', 'dllhost', 'fontdrvhost',
    'csrss', 'winlogon', 'smartscreen', 'SecurityHealthSystray', 'msedgewebview2', 'Widgets', 'WidgetService',
    'steam', 'steamwebhelper', 'EpicGamesLauncher', 'EpicWebHelper', 'Battle.net', 'EADesktop', 'EABackgroundService',
    'Origin', 'GalaxyClient', 'GalaxyClient Helper', 'upc', 'UbisoftConnect', 'RiotClientServices', 'RiotClientUx',
    'nvcontainer', 'NVDisplay.Container', 'NVIDIA app', 'NVIDIA Overlay', 'RadeonSoftware', 'AMDRSServ'
)

function Get-FreeMemoryBytes {
    [long](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
}

function Get-PowerPlans {
    foreach ($line in (& powercfg.exe /list)) {
        if ($line -match '([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\s+\((.+)\)\s*(\*?)') {
            [pscustomobject]@{ Guid = $Matches[1]; Name = $Matches[2]; Active = [bool]$Matches[3] }
        }
    }
}

# Größte Speicherverbraucher der eigenen Sitzung, je Programm zusammengefasst
function Get-BoostCandidates {
    $session = (Get-Process -Id $PID).SessionId
    Get-Process | Where-Object { $_.SessionId -eq $session -and $script:BoostKeep -notcontains $_.ProcessName } |
        Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.Name
                Count     = $_.Count
                Bytes     = [long]($_.Group | Measure-Object WorkingSet64 -Sum).Sum
                Processes = $_.Group
            }
        } | Where-Object { $_.Bytes -ge 100MB } | Sort-Object Bytes -Descending | Select-Object -First 12
}

# Programme, die der Konfigurator zum Schließen vorschlägt: Musik, Chat, Abgleich mit der Cloud
$script:BoostSuggestApps = 'Spotify', 'OneDrive', 'Teams', 'ms-teams', 'Skype', 'Dropbox', 'GoogleDriveFS', 'iCloudDrive',
    'Creative Cloud', 'CCXProcess', 'PhoneExperienceHost', 'YourPhone', 'Zoom', 'Slack', 'Telegram', 'WhatsApp'

# Dienste anderer Hersteller, die nie zum Anhalten angeboten werden: Grafik, Ton, Kopierschutz der Spiele,
# Spiele-Starter, Virenschutz, Netzwerk und Eingabegeräte
$script:BoostServiceKeep = 'NVIDIA|\bNv|\bAMD\b|Radeon|Intel|Audio|Realtek|Rtk|Nahimic|Sonic|Dolby|DTS|THX|AntiCheat|^BEService|\bvgc\b|\bvgk\b|FACEIT|' +
    'Steam|Epic|Origin|\bEA\b|Ubisoft|Rockstar|Battle\.net|GOG|Xbox|Gaming|GameInput|Play Games|Defend|Antivir|Security|Firewall|Bitdefender|Kaspersky|ESET|Avast|AVG|' +
    'Norton|McAfee|Malware|VPN|Bluetooth|WLAN|Wi-?Fi|Ethernet|Killer|Thunderbolt|USB|HID|Synaptics|Wacom|VMware|VirtualBox|Docker|Hyper-V'

# Pfad der Programmdatei eines Dienstes aus seiner Befehlszeile
function Resolve-ServicePath([string]$PathName) {
    Import-PulsRigCore
    [PulsRig.Core.Treiber]::ResolveServicePath($PathName)
}

# Plan für den automatischen Boost aus den Einstellungen ($Plan = Boost-Teil der Einstellungsdatei oder $null).
# Die Datei liegt im Benutzerordner, darum gilt sie nicht ungeprüft: angehalten werden nur Dienste aus der eigenen
# Liste oder Dienste anderer Hersteller (Programmdatei außerhalb von Windows), Programme werden nie geschlossen.
function New-AutoBoostPlan($Plan) {
    # eine leere Auswahl heißt "keine Dienste" (aus der Einstellungsdatei kommt sie als leere Liste, nicht als $null)
    Import-PulsRigCore
    $wanted = @(if ($Plan -and $Plan.PSObject.Properties['Services'] -and $null -ne $Plan.Services) { @($Plan.Services) } else { $script:BoostServices }) |
        Where-Object { [PulsRig.Core.Boost]::IsSafeName("$_") }
    $allowed = @(foreach ($name in $wanted) {
            $pathName = ''
            if ($script:BoostServices -notcontains $name) {
                try { $pathName = "$((Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction Stop).PathName)" } catch { }
            }
            if ([PulsRig.Core.Boost]::IsAllowed("$name", [string[]]$script:BoostServices, $pathName, $env:WINDIR)) { $name }
        })
    # Programme schließt der automatische Boost nie: darin kann Ungespeichertes stecken
    @{ Apps = @(); Services = $allowed; Clipboard = $false
        PowerPlan = $(if ($Plan) { [bool]$Plan.PowerPlan } else { $true }); GameMode = $(if ($Plan) { [bool]$Plan.GameMode } else { $true }) }
}

# Auswahl für den Konfigurator im Fenster: Programme der eigenen Sitzung und laufende Dienste
function Get-BoostChoices {
    $session = (Get-Process -Id $PID).SessionId
    $apps = @(Get-Process | Where-Object { $_.SessionId -eq $session -and $_.Id -ne $PID -and $script:BoostKeep -notcontains $_.ProcessName } |
            Group-Object ProcessName | ForEach-Object {
                $largest = $_.Group | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
                $description = ''
                try { $description = "$($largest.MainModule.FileVersionInfo.FileDescription)".Trim() } catch { }
                [pscustomobject]@{
                    Name        = $_.Name
                    Description = $description
                    Count       = $_.Count
                    Bytes       = [long]($_.Group | Measure-Object WorkingSet64 -Sum).Sum
                    Suggested   = $script:BoostSuggestApps -contains $_.Name
                }
            } | Where-Object { $_.Bytes -ge 5MB } | Sort-Object Bytes -Descending)

    $services = @(Get-CimInstance Win32_Service -Filter "State='Running'" | ForEach-Object {
            if ($script:BoostServices -contains $_.Name) {
                [pscustomobject]@{ Name = $_.Name; Title = "$($_.DisplayName)"; Description = "$($_.Description)"; Known = $true }
            }
            else {
                $company = ''
                try { $company = "$([Diagnostics.FileVersionInfo]::GetVersionInfo((Resolve-ServicePath $_.PathName)).CompanyName)" } catch { }
                if ($company -and $company -notmatch 'Microsoft|Windows' -and "$($_.Name) $($_.DisplayName) $company" -notmatch $script:BoostServiceKeep) {
                    $text = "$($_.Description)".Trim()
                    if (-not $text -or $text -eq $_.DisplayName) { $text = $company }
                    [pscustomobject]@{ Name = $_.Name; Title = "$($_.DisplayName)"; Description = $text; Known = $false }
                }
            }
        } | Sort-Object Title)

    @{ Apps = $apps; Services = $services; DefaultServices = @($script:BoostServices) }
}

# Schließt ein Programm. Fenster werden höflich geschlossen; bleibt eines offen (meist fragt das Programm dann,
# ob es speichern soll), wird nichts hart beendet - sonst gingen ungespeicherte Daten verloren.
function Stop-AppGroup($Group) {
    $withWindow = @($Group.Processes | Where-Object { $_.MainWindowHandle -ne 0 })
    foreach ($process in $withWindow) { [void]$process.CloseMainWindow() }
    if ($withWindow.Count -gt 0) {
        # dem Programm Zeit zum sauberen Beenden lassen
        $deadline = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $deadline -and @($withWindow | Where-Object { $_.Refresh(); -not $_.HasExited }).Count -gt 0) {
            Start-Sleep -Milliseconds 400
        }
        if (@($withWindow | Where-Object { $_.Refresh(); -not $_.HasExited }).Count -gt 0) {
            throw 'noch offen - das Programm wartet vermutlich auf eine Antwort (Speichern?). Es wurde nicht beendet.'
        }
    }
    # was jetzt noch läuft, hat kein Fenster: Hintergrundprozesse des Programms
    Get-Process -Name $Group.Name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Spiele, die Windows als Spiel erkannt hat (Spielleiste, "GameConfigStore"): Name, Programmdatei, läuft gerade?
# Der Name kommt aus dem Ordner der Spielebibliothek (Steam, Epic, GOG, Xbox), sonst aus der Programmdatei.
function Get-KnownGames {
    $games = @{}
    foreach ($entry in @(Get-ChildItem 'HKCU:\System\GameConfigStore\Children' -ErrorAction SilentlyContinue)) {
        $path = "$((Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue).MatchedExeFullPath)"
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
        # Plattformen, die Windows als Spiel führt, die aber keines sind (Google Play Games: client.exe, crosvm.exe)
        if ($path -match '\\Google\\Play Games\\') { continue }
        $exe = [IO.Path]::GetFileNameWithoutExtension($path)
        if ($games.ContainsKey($exe.ToLower())) { continue }
        $name = ''
        if ($path -match '\\(?:steamapps\\common|Epic Games|GOG Galaxy\\Games|XboxGames)\\([^\\]+)\\') { $name = $Matches[1] }
        if (-not $name) { try { $name = "$((Get-Item -LiteralPath $path).VersionInfo.FileDescription)".Trim() } catch { } }
        if (-not $name) { $name = $exe }
        $games[$exe.ToLower()] = [pscustomobject]@{ Name = $name; Exe = $exe; Path = $path; Running = [bool](Get-Process -Name $exe -ErrorAction SilentlyContinue) }
    }
    @($games.Values | Sort-Object Name)
}

function New-BoostShortcut([string]$Path) {
    $folder = Split-Path -Parent $PSCommandPath
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    $shortcut.TargetPath = Join-Path $folder 'Treiber-Scan.bat'
    $shortcut.Arguments = '-Tool GameBoost'
    $shortcut.WorkingDirectory = $folder
    $shortcut.Description = 'Spiel-Beschleunigung ein- und ausschalten'
    $shortcut.Save()
}

function Invoke-GameBoostOff([string]$StatePath) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Write-Host "Die Spiel-Beschleunigung ist seit $($state.Time) eingeschaltet."
    if (-not (Confirm-Action 'Ausschalten und alles zurückstellen?')) { return }

    if ($state.PowerPlan) {
        Invoke-Step "Energieplan zurückstellen auf `"$($state.PowerPlanName)`"" { Invoke-Native powercfg.exe @('/setactive', $state.PowerPlan) }
    }
    foreach ($name in @($state.Services)) {
        Invoke-Step "Dienst wieder starten: $name" { Start-Service -Name $name }
    }
    if (@($state.ClosedApps).Count -gt 0) {
        Write-Host "  Geschlossene Programme bitte selbst wieder starten: $(@($state.ClosedApps) -join ', ')"
    }
    if (-not $DryRun) {
        Remove-Item -LiteralPath $StatePath -Confirm:$false
        Write-Host 'Spiel-Beschleunigung ausgeschaltet.' -ForegroundColor Green
    }
}

function Invoke-GameBoostTool {
    $statePath = Join-Path $OutDir 'Spiel-Beschleunigung.json'
    if (Test-Path -LiteralPath $statePath) {
        Invoke-GameBoostOff $statePath
        return
    }

    # Auswahl aus dem Konfigurator des Fensters; ohne sie gelten die Vorgaben, und nach Programmen wird gefragt
    $plan = $global:BoostPlan

    $freeBefore = Get-FreeMemoryBytes
    $total = [long](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    Write-Host ("Arbeitsspeicher: {0:N1} von {1:N1} GB frei" -f ($freeBefore / 1GB), ($total / 1GB))

    $gameMode = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -ErrorAction SilentlyContinue).AutoGameModeEnabled
    $gameModeOff = $gameMode -eq 0
    Write-Check 'Spielmodus von Windows' (-not $gameModeOff) $(if ($gameModeOff) { 'ausgeschaltet' } else { 'eingeschaltet' })
    if ($plan -and -not $plan.GameMode) { $gameModeOff = $false }   # abgewählt: nicht anfassen

    $plans = @(Get-PowerPlans)
    $active = $plans | Where-Object { $_.Active } | Select-Object -First 1
    $performance = $plans | Where-Object { $_.Guid -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' } | Select-Object -First 1
    $alreadyFast = $active -and ($active.Name -match 'leistung|performance' -or $active.Guid -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')
    Write-Check 'Energieplan' ([bool]$alreadyFast) $(if ($active) { $active.Name })
    $switchPlan = -not $alreadyFast -and $performance -and -not ($plan -and -not $plan.PowerPlan)

    # Get-Service ohne Namen würde alle Dienste liefern - eine leere Auswahl deshalb gesondert behandeln
    $serviceNames = @(if ($plan) { $plan.Services } else { $script:BoostServices }) | Where-Object { $_ }
    $running = @()
    if ($serviceNames) { $running = @(Get-Service -Name $serviceNames -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }) }
    $label = if ($plan) { 'Ausgewählte Dienste' } else { 'Entbehrliche Dienste' }
    Write-Host ("  {0}, die gerade laufen: {1}" -f $label, $(if ($running.Count) { ($running | ForEach-Object { $_.DisplayName }) -join ', ' } else { 'keine' }))

    $candidates = @(if (-not $plan) { Get-BoostCandidates })
    $selected = @()
    if ($plan) {
        $session = (Get-Process -Id $PID).SessionId
        foreach ($name in @($plan.Apps | Where-Object { $_ })) {
            $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
            if ($processes.Count -eq 0 -or $script:BoostKeep -contains $name) { continue }
            $selected += [pscustomobject]@{ Name = $name; Count = $processes.Count; Processes = $processes
                Bytes = [long]($processes | Measure-Object WorkingSet64 -Sum).Sum }
        }
        if ($selected.Count -gt 0) {
            Write-Host ''
            Write-Host 'Diese Programme werden geschlossen (dort vorher alles Ungespeicherte sichern):' -ForegroundColor Yellow
            foreach ($group in $selected) { Write-Host ('  {0,-28} {1,6:N0} MB' -f $group.Name, ($group.Bytes / 1MB)) }
        }
    }
    $clearClipboard = [bool]($plan -and $plan.Clipboard)
    if ($candidates.Count -gt 0) {
        Write-Host ''
        Write-Host 'Programme mit dem größten Speicherverbrauch:'
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-Host ('  {0,2}. {1,-28} {2,6:N0} MB' -f ($i + 1), $candidates[$i].Name, ($candidates[$i].Bytes / 1MB))
        }
        if (-not $Yes -and -not $DryRun) {
            Write-Host 'Gewählte Programme werden geschlossen; reagiert eines nach 8 Sekunden nicht, wird es beendet.'
            Write-Host 'Vorher dort alles Ungespeicherte sichern.' -ForegroundColor Yellow
            try { $answer = "$(Read-Host 'Welche schließen? Nummern mit Komma oder Eingabetaste für keines')".Trim() } catch { $answer = '' }
            foreach ($part in ($answer -split '[,\s]+')) {
                if ($part -match '^\d+$' -and [int]$part -ge 1 -and [int]$part -le $candidates.Count) { $selected += $candidates[[int]$part - 1] }
            }
        }
    }

    Write-Host ''
    if (-not $switchPlan -and -not $gameModeOff -and $running.Count -eq 0 -and $selected.Count -eq 0 -and -not $clearClipboard) {
        Write-Host 'Es gibt nichts zu beschleunigen - das System ist bereits so eingestellt.' -ForegroundColor Green
        return
    }
    if (-not (Confirm-Action 'Spiel-Beschleunigung einschalten?')) { return }

    if ($gameModeOff) {
        Invoke-Step 'Spielmodus von Windows einschalten' {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled -Value 1 -Type DWord
        }
    }
    if ($switchPlan) {
        Invoke-Step "Energieplan auf `"$($performance.Name)`" stellen" { Invoke-Native powercfg.exe @('/setactive', $performance.Guid) }
    }
    foreach ($service in $running) {
        Invoke-Step "Dienst anhalten: $($service.DisplayName)" { Stop-Service -Name $service.Name -Force }
    }
    foreach ($group in $selected) {
        Invoke-Step "Schließe $($group.Name)" { Stop-AppGroup $group }
    }
    if ($clearClipboard) {
        Invoke-Step 'Zwischenablage leeren' { Set-Clipboard -Value $null }
    }
    if ($DryRun) { return }

    # festhalten, was sich wirklich geändert hat - nur das wird später zurückgestellt
    $stopped = @(Get-Service -Name @($running | ForEach-Object { $_.Name }) -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'Running' } | ForEach-Object { $_.Name })
    $nowActive = Get-PowerPlans | Where-Object { $_.Active } | Select-Object -First 1
    $planChanged = $switchPlan -and $nowActive -and $nowActive.Guid -ne $active.Guid
    $state = [ordered]@{
        Time          = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        PowerPlan     = if ($planChanged) { $active.Guid } else { $null }
        PowerPlanName = if ($planChanged) { $active.Name } else { $null }
        Services      = $stopped
        ClosedApps    = @($selected | Where-Object { -not (Get-Process -Name $_.Name -ErrorAction SilentlyContinue) } | ForEach-Object { $_.Name })
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

    Start-Sleep -Seconds 2
    $freeAfter = Get-FreeMemoryBytes
    # vorher und nachher gehören zum Zustand: die Boost-Seite zeigt, wie viel der Boost freigemacht hat
    $state.FreeBefore = [long]$freeBefore
    $state.FreeAfter = [long]$freeAfter
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Host ''
    Write-Host ("Arbeitsspeicher jetzt: {0:N1} GB frei ({1:+0.0;-0.0} GB)" -f ($freeAfter / 1GB), (($freeAfter - $freeBefore) / 1GB)) -ForegroundColor Green
    Write-Host 'Nach dem Spielen dieses Werkzeug noch einmal starten - dann wird alles zurückgestellt.'

    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spiel-Beschleunigung.lnk'
    # die Verknüpfung zeigt auf Treiber-Scan.bat; im installierten Programm gibt es die Datei nicht - dort schaltet die Boost-Seite
    if ($PSCommandPath -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $PSCommandPath) 'Treiber-Scan.bat')) -and
        -not (Test-Path -LiteralPath $shortcutPath) -and
        (Confirm-Action 'Verknüpfung "Spiel-Beschleunigung" auf dem Desktop anlegen (ein Doppelklick schaltet ein und aus)?' -Optional)) {
        Invoke-Step 'Lege Verknüpfung an' { New-BoostShortcut $shortcutPath }
    }
}

# --- Speicherplatz freigeben ----------------------------------------------------
# Räumt Ordner auf, deren Inhalt Windows und Programme jederzeit neu anlegen: temporäre Dateien, alte Downloads von
# Windows Update, Fehlerberichte, Installer, die PulsRig selbst geladen hat. Gelöscht wird nur, was älter als ein paar
# Tage ist (was gerade benutzt wird, ist meist jünger und gesperrt). Bewusst nicht dabei: der Papierkorb, Sicherungen
# von Treibern und Speicherabbilder nach Bluescreens - die braucht man noch, um einen Absturz zu verstehen.
#
# Verknüpfungen auf andere Ordner (Junctions, symbolische Links) werden nie betreten: so kann das Aufräumen eines
# Ordners nicht in einen ganz anderen hineinlaufen.

# alle Dateien eines Ordners, die älter als $Days Tage sind - ohne Verknüpfungen zu folgen
function Get-CleanableFiles([string]$Path, [int]$Days) {
    # auch Papierkorb, Treibersicherungen und Speicherabbilder lässt Core aus, falls sie einmal in einem Ziel liegen
    Import-PulsRigCore
    [PulsRig.Core.Aufraeumen]::CleanableFiles($Path, $Days)
}

# Was es aufzuräumen gibt: Name, Ordner, Mindestalter, ob Adminrechte nötig sind
function Get-CleanTargetList {
    $windows = $env:WINDIR
    @(
        @{ Name = 'Temporäre Dateien'; Paths = @([IO.Path]::GetTempPath()); Days = 2; Admin = $false }
        @{ Name = 'Temporäre Dateien von Windows'; Paths = @((Join-Path $windows 'Temp')); Days = 2; Admin = $true }
        @{ Name = 'Alte Downloads von Windows Update'; Paths = @((Join-Path $windows 'SoftwareDistribution\Download')); Days = 7; Admin = $true }
        @{ Name = 'Fehlerberichte von Windows'; Paths = @((Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive')); Days = 7; Admin = $true }
        @{ Name = 'Von PulsRig geladene Installer'; Paths = @((Join-Path $OutDir 'Laufzeiten')); Days = 7; Admin = $false; Extra = 'Installer' }
    )
}

function Get-CleanTargets {
    foreach ($target in @(Get-CleanTargetList)) {
        $files = @(foreach ($path in $target.Paths) { Get-CleanableFiles $path $target.Days })
        # die Installer von NVIDIA liegen direkt im Zielordner: nur sie, nie Sicherungen oder Berichte
        if ($target.Extra -eq 'Installer' -and (Test-Path -LiteralPath $OutDir)) {
            $limit = (Get-Date).AddDays(-$target.Days)
            $files += @(Get-ChildItem -LiteralPath $OutDir -File -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $limit })
        }
        $target.Files = $files
        $target.Bytes = [long](($files | Measure-Object Length -Sum).Sum)
        [pscustomobject]$target
    }
}

function Remove-CleanableFiles($Files) {
    $removed = 0; $bytes = 0L
    foreach ($file in $Files) {
        try { $length = $file.Length; [IO.File]::Delete($file.FullName); $removed++; $bytes += $length } catch { }   # gesperrt: bleibt
    }
    @{ Count = $removed; Bytes = $bytes }
}

# Shader-Cache: was Grafiktreiber und Steam an übersetzten Shadern ablegen. Wird bei Bedarf neu angelegt; danach
# ruckeln Spiele beim ersten Start kurz, während sie neu übersetzen. Lohnt sich vor allem nach einem Treiberwechsel.
function Get-ShaderCacheTarget {
    $local = $env:LOCALAPPDATA
    $low = Join-Path (Split-Path -Parent $local) 'LocalLow'
    $paths = @(
        (Join-Path $local 'NVIDIA\DXCache'), (Join-Path $local 'NVIDIA\GLCache'), (Join-Path $local 'NVIDIA Corporation\NV_Cache'),
        (Join-Path $low 'NVIDIA\PerDriverVersion\DXCache'),
        (Join-Path $local 'AMD\DxCache'), (Join-Path $local 'AMD\DxcCache'), (Join-Path $local 'AMD\GLCache'), (Join-Path $local 'AMD\VkCache'),
        (Join-Path $low 'Intel\ShaderCache'),
        (Join-Path $local 'D3DSCache')
    )
    # Steam: der Shader-Cache jeder Spielebibliothek (Ordner aus libraryfolders.vdf)
    try {
        $steam = "$((Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath)" -replace '/', '\'
        $libraries = @($steam)
        $list = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $list) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $list -Raw), '"path"\s+"([^"]+)"')) { $libraries += $match.Groups[1].Value -replace '\\\\', '\' }
        }
        foreach ($library in @($libraries | Select-Object -Unique)) { $paths += Join-Path $library 'steamapps\shadercache' }
    }
    catch { }
    $files = @(foreach ($path in $paths) { Get-CleanableFiles $path 0 })
    [pscustomobject]@{ Name = 'Shader-Cache von Grafiktreibern und Steam'; Files = $files; Bytes = [long](($files | Measure-Object Length -Sum).Sum) }
}

# Alte Fassungen im Treiberspeicher von Windows (DriverStore): je Treiber bleiben die zwei neuesten - die vorige braucht
# man, um einen Treiber zurückzuholen. Was ein Gerät gerade benutzt, bleibt immer; pnputil löscht ohne /force nichts,
# was noch in Gebrauch ist. Braucht Adminrechte.
function Get-OldDriverPackages {
    $classes = @{ Display = 'Grafik'; Net = 'Netzwerk'; Media = 'Audio'; System = 'System'; USB = 'USB'; Bluetooth = 'Bluetooth'
        HIDClass = 'Eingabegerät'; Monitor = 'Monitor'; SoftwareComponent = 'Softwarekomponente'; Extension = 'Erweiterung'; Firmware = 'Firmware' }
    $inUse = @{}
    foreach ($device in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) { if ($device.InfName) { $inUse["$($device.InfName)".ToLower()] = $true } }
    $old = @()
    $packages = @(Get-WindowsDriver -Online -ErrorAction Stop | Where-Object { "$($_.Driver)" -match '^oem\d+\.inf$' })
    foreach ($group in @($packages | Group-Object { '{0}|{1}|{2}' -f [IO.Path]::GetFileName("$($_.OriginalFileName)").ToLower(), $_.ProviderName, $_.ClassName })) {
        if ($group.Count -lt 3) { continue }
        $sorted = @($group.Group | Sort-Object @{ Expression = { $v = $null; if ([version]::TryParse("$($_.Version)", [ref]$v)) { $v } else { [version]'0.0' } }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        foreach ($package in @($sorted | Select-Object -Skip 2)) {
            $inf = "$($package.Driver)".ToLower()
            if ($inUse[$inf]) { continue }
            $folder = Split-Path -Parent "$($package.OriginalFileName)"
            $bytes = [long]((Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)
            $class = if ($classes["$($package.ClassName)"]) { $classes["$($package.ClassName)"] } else { "$($package.ClassName)" }
            $old += [pscustomobject]@{ Inf = $inf; Provider = "$($package.ProviderName)"; Class = $class; Version = "$($package.Version)"; Bytes = $bytes }
        }
    }
    @($old | Sort-Object Bytes -Descending)
}

function Format-CleanSize([long]$Bytes) { if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } else { '{0:N0} MB' -f ($Bytes / 1MB) } }

function Invoke-CleanDiskTool {
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($drive) { Write-Host ("Laufwerk {0} hat {1:N1} GB frei." -f $env:SystemDrive, ($drive.Free / 1GB)) }
    Write-Host 'Suche, was sich gefahrlos löschen lässt ...'
    $targets = @(Get-CleanTargets)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host ''
    foreach ($target in $targets) {
        $note = if ($target.Admin -and -not $isAdmin) { ' (nur mit Adminrechten)' } else { '' }
        # eine Liste, kein Befund: viel Platz ist hier nichts Schlechtes
        Write-Host "  $($target.Name) - $(Format-CleanSize $target.Bytes)$note" -ForegroundColor $(if ($target.Bytes -ge 50MB) { 'Cyan' } else { 'Gray' })
    }
    $shader = Get-ShaderCacheTarget
    Write-Host "  $($shader.Name) - $(Format-CleanSize $shader.Bytes)" -ForegroundColor $(if ($shader.Bytes -ge 50MB) { 'Cyan' } else { 'Gray' })
    $packages = @()
    if ($isAdmin) {
        Write-Host '  Lese den Treiberspeicher von Windows ...' -ForegroundColor DarkGray
        try { $packages = @(Get-OldDriverPackages) } catch { Write-Host "  Der Treiberspeicher ließ sich nicht lesen ($($_.Exception.Message.Trim()))" -ForegroundColor DarkGray }
        $packBytes = [long](($packages | Measure-Object Bytes -Sum).Sum)
        Write-Host "  Alte Treiberpakete - $(Format-CleanSize $packBytes)" -ForegroundColor $(if ($packBytes -ge 50MB) { 'Cyan' } else { 'Gray' })
    }
    else { Write-Host '  Alte Treiberpakete (nur mit Adminrechten)' -ForegroundColor Gray }
    Write-Host ''
    Write-Host 'Nicht angefasst werden: Papierkorb, gesicherte Treiber, Speicherabbilder nach Bluescreens und je Treiber die zwei neuesten Fassungen.' -ForegroundColor DarkGray

    $usable = @($targets | Where-Object { $_.Bytes -ge 1MB -and (-not $_.Admin -or $isAdmin -or $DryRun) })
    $total = [long](($usable | Measure-Object Bytes -Sum).Sum)
    if ($total -lt 1MB -and $shader.Bytes -lt 1MB -and $packages.Count -eq 0) {
        Write-Host 'Nichts zu bereinigen.' -ForegroundColor Green
        return
    }
    $freed = 0L
    if ($total -ge 1MB -and (Confirm-Action ('Temporäre Dateien und alte Downloads: {0} freigeben?' -f (Format-CleanSize $total)))) {
        foreach ($target in $usable) {
            Invoke-Step "Lösche: $($target.Name)" { $script:CleanResult = Remove-CleanableFiles $target.Files }
            if ($script:CleanResult) { $freed += $script:CleanResult.Bytes; $script:CleanResult = $null }
        }
    }
    if ($shader.Bytes -ge 1MB) {
        Write-Host ''
        Write-Host 'Shader-Cache: Spiele ruckeln danach beim ersten Start kurz, während sie ihre Shader neu übersetzen. Lohnt sich vor allem nach einem neuen Grafiktreiber.' -ForegroundColor DarkGray
        if (Confirm-Action ('Shader-Cache löschen ({0})?' -f (Format-CleanSize $shader.Bytes))) {
            Invoke-Step 'Lösche: Shader-Cache' { $script:CleanResult = Remove-CleanableFiles $shader.Files }
            if ($script:CleanResult) { $freed += $script:CleanResult.Bytes; $script:CleanResult = $null }
        }
    }
    if ($packages.Count -gt 0) {
        Write-Host ''
        Write-Host 'Alte Treiberpakete (die zwei neuesten Fassungen jedes Treibers bleiben):'
        foreach ($package in @($packages | Select-Object -First 8)) { Write-Host ("  {0} · {1} · Version {2} - {3}" -f $package.Provider, $package.Class, $package.Version, (Format-CleanSize $package.Bytes)) }
        if ($packages.Count -gt 8) { Write-Host "  und $($packages.Count - 8) weitere" }
        $packBytes = [long](($packages | Measure-Object Bytes -Sum).Sum)
        if (Confirm-Action ('{0} alte Treiberpakete entfernen ({1})?' -f $packages.Count, (Format-CleanSize $packBytes))) {
            Invoke-Step "Entferne $($packages.Count) alte Treiberpakete" {
                $removed = 0; $bytes = 0L
                foreach ($package in $packages) {
                    # ohne /force: ein Paket, das doch noch gebraucht wird, lehnt pnputil ab - es bleibt
                    $null = & pnputil.exe /delete-driver $package.Inf 2>&1
                    if ($LASTEXITCODE -eq 0) { $removed++; $bytes += $package.Bytes }
                }
                $script:CleanResult = @{ Count = $removed; Bytes = $bytes }
                if ($removed -lt $packages.Count) { Write-Host "($($packages.Count - $removed) noch in Gebrauch, sie bleiben) " -NoNewline }
            }
            if ($script:CleanResult) { $freed += $script:CleanResult.Bytes; $script:CleanResult = $null }
        }
    }
    if ($DryRun) { return }
    Write-Host ''
    Write-Host ('Freigegeben: {0}. Gesperrte Dateien sind geblieben - sie gehören zu laufenden Programmen.' -f (Format-CleanSize $freed)) -ForegroundColor Green
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($drive) { Write-Host ("Laufwerk {0} hat jetzt {1:N1} GB frei." -f $env:SystemDrive, ($drive.Free / 1GB)) }
}

# --- Aufruf und Menü ----------------------------------------------------------

function Invoke-Tool([string]$Name) {
    Write-Step $script:ToolList[$Name].Title
    if ($DryRun) { Write-Host 'Probelauf: Es wird nur geprüft und angezeigt, nichts verändert.' -ForegroundColor DarkGray }
    switch ($Name) {
        'Backup' { Backup-InstalledDrivers $OutDir }
        'Restore' { Invoke-RestoreTool }
        'FixAudio' { Invoke-FixAudioTool }
        'FixDevices' { Invoke-FixDevicesTool }
        'CleanDevices' { Invoke-CleanDevicesTool }
        'FixNetwork' { Invoke-FixNetworkTool }
        'FixResolution' { Invoke-FixResolutionTool }
        'GameRuntimes' { Invoke-GameRuntimesTool }
        'IncompatibleDrivers' { Invoke-IncompatibleDriversTool }
        'OfflinePackage' { New-OfflinePackage $OutDir }
        'SystemInfo' { Invoke-SystemInfoTool }
        'GameBoost' { Invoke-GameBoostTool }
        'CleanDisk' { Invoke-CleanDiskTool }
    }
}

function Invoke-Menu {
    $names = @($script:ToolList.Keys)
    $emptyInputs = 0
    while ($true) {
        Write-Host ''
        Write-Host '=== Treiber-Scan ===' -ForegroundColor Cyan
        Write-Host '  1  Treiber suchen und herunterladen'
        Write-Host '  2  Treiber suchen, herunterladen und installieren'
        Write-Host '  3  Nur scannen (nichts herunterladen)'
        Write-Host ''
        for ($i = 0; $i -lt $names.Count; $i++) {
            Write-Host ('{0,3}  {1}' -f ($i + 4), $script:ToolList[$names[$i]].Title)
        }
        Write-Host ''
        Write-Host '  0  Beenden'

        $choice = $null
        try { $choice = Read-Host 'Auswahl' } catch { return }
        if ($null -eq $choice) { return }
        $choice = $choice.Trim()
        if (-not $choice) {
            # ohne Tastatur (z.B. umgeleitete Eingabe) nicht endlos weiterfragen
            $emptyInputs++
            if ($emptyInputs -ge 3) { return }
            continue
        }
        $emptyInputs = 0
        if ($choice -eq '0') { return }
        if ($choice -notmatch '^\d+$' -or [int]$choice -gt $names.Count + 3) {
            Write-Host 'Bitte eine Nummer aus der Liste eingeben.' -ForegroundColor Yellow
            continue
        }

        try {
            switch ([int]$choice) {
                1 { $script:ScanOnly = [bool]$DryRun; $script:Install = $false; Invoke-Main }
                2 { $script:ScanOnly = [bool]$DryRun; $script:Install = $true; Invoke-Main }
                3 { $script:ScanOnly = $true; $script:Install = $false; Invoke-Main }
                default { Invoke-Tool $names[[int]$choice - 4] }
            }
        }
        catch {
            Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
