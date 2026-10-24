# PulsRig - Arbeitsbereich: der Scan. Wird von PulsRig.ps1 als Text geladen und im Arbeitsbereich ausgeführt.
param($a)
function Stage($percent, $next, $text) { $sync.Queue.Enqueue(@{ Type = 'stage'; Percent = $percent; Next = $next; Text = $text }) }

Stage 2 16 'Lese Geräte und installierte Treiber …'
$global:DD_Installed = @(Get-InstalledDrivers)
# die Gerätenamen laufen während des Scans unter dem Knopf durch
$sync.Queue.Enqueue(@{ Type = 'devices'; Names = @($global:DD_Installed | ForEach-Object { "$($_.DeviceName)" } | Select-Object -Unique) })
$problems = @(Get-ProblemDevices | ForEach-Object {
        $issue = Get-DeviceError $_.ConfigManagerErrorCode
        @{ Name = "$($_.Name)"; Code = [int]$_.ConfigManagerErrorCode; Text = $issue.Text; Advice = $issue.Advice
            Id = "$(@($_.HardwareID)[0])"; Chipset = [bool](Test-ChipsetDevice "$($_.Name)" ([int]$_.ConfigManagerErrorCode) "$($_.DeviceID)") }
    })
# fehlt der Chipsatz-Treiber, nennt das Ergebnis das Mainboard und eine Suche nach dessen Treiber
$board = $null
if (@($problems | Where-Object { $_.Chipset }).Count -gt 0) {
    try {
        $system = Get-CimInstance Win32_ComputerSystem; $base = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
        $board = Get-BoardDriverSearch "$($system.Manufacturer)" "$($system.Model)" "$($base.Manufacturer)" "$($base.Product)"
    }
    catch { }
}

Stage 16 58 'Frage Windows Update nach neueren Treibern …'
$searchError = $null
$global:DD_Items = @()
try {
    $global:DD_Session = New-Object -ComObject Microsoft.Update.Session
    $global:DD_Session.ClientApplicationID = 'PulsRig'
    # neue Angebote für geschützte Grafikkarten zuerst verstecken (braucht Adminrechte, sonst bleiben sie sichtbar)
    try { [void]@(Set-GpuShield $global:DD_Session @($a.Shield) $true) } catch { }
    $global:DD_Items = @(Find-DriverUpdates $global:DD_Session)
}
catch { $searchError = Get-UpdateErrorText $_ }

Stage 58 66 'Frage NVIDIA und AMD nach den neuesten Treibern …'
$failed = @()   # Quellen, die nicht geantwortet haben: das Fenster nennt sie, statt still "alles aktuell" zu melden
$global:DD_Nvidia = $null
$nvidia = $null
try {
    if ($a.Nvidia) { $global:DD_Nvidia = Get-NvidiaUpdate }
    if ($global:DD_Nvidia) {
        $n = $global:DD_Nvidia
        $nvidia = @{ Gpu = "$($n.Gpu)"; Kind = "$($n.Kind)"; Installed = "$($n.Installed)"; Latest = "$($n.Latest)"; Released = "$($n.Released)"; Size = "$($n.Size)"; IsNewer = [bool]$n.IsNewer }
        # den Grafiktreiber liefert NVIDIA selbst immer mindestens so aktuell wie Windows Update (dort heißt die Klasse mal Display, mal Video)
        $global:DD_Items = @($global:DD_Items | Where-Object {
                -not ($_.Update.DriverClass -in 'Display', 'Video' -and "$($_.Update.Title) $($_.Update.DriverProvider)" -match 'NVIDIA') })
    }
}
catch { $failed += 'NVIDIA' }

# Chipsatz-Treiber bei AMD: nur ein Hinweis, geladen wird nichts
$amd = $null
try {
    if ($a.Nvidia) {
        $c = Get-AmdChipsetUpdate
        if ($c) { $amd = @{ Chipset = "$($c.Chipset)"; Cpu = "$($c.Cpu)"; Installed = "$($c.Installed)"; Latest = "$($c.Latest)"; Released = "$($c.Released)"; Size = "$($c.Size)"; Url = "$($c.Url)"; IsNewer = [bool]$c.IsNewer } }
    }
}
catch { $failed += 'AMD' }

# Grafiktreiber für Radeon bei AMD: ebenfalls nur ein Hinweis
$radeonDriver = $null
try {
    if ($a.Nvidia) {
        $r = Get-RadeonUpdate
        if ($r) { $radeonDriver = @{ Gpu = "$($r.Gpu)"; Installed = "$($r.Installed)"; Latest = "$($r.Latest)"; Released = "$($r.Released)"; Url = "$($r.Url)"; IsNewer = [bool]$r.IsNewer } }
    }
}
catch { if ($failed -notcontains 'AMD') { $failed += 'AMD' } }

$updates = @()
$allDevices = $null
foreach ($item in $global:DD_Items) {
    $u = $item.Update
    $current = Find-InstalledDriver $u.DriverHardwareID $global:DD_Installed
    # ist kein Treiber dazu installiert, sagt wenigstens der Name des Geräts, worum es geht
    $deviceName = ''
    if (-not $current) {
        try {
            if ($null -eq $allDevices) { $allDevices = @(Get-CimInstance Win32_PnPEntity) }
            $deviceName = Find-DeviceName "$($u.DriverHardwareID)" $allDevices
        }
        catch { }
    }
    $updates += @{
        Id        = "$($item.Id)"
        Name      = Format-UpdateTitle "$($u.Title)"
        Device    = $deviceName
        Title     = "$($u.Title)"
        Class     = "$($u.DriverClass)"
        Key       = "$($u.DriverHardwareID)"
        Installed = if ($current) { Format-DriverText $current.DriverVersion $current.ActualDate } else { '' }
        NewDate   = Format-Date $u.DriverVerDate
        Size      = if ($u.MaxDownloadSize -gt 0) { '{0:N1} MB' -f ($u.MaxDownloadSize / 1MB) } else { '' }
        Optional  = [bool]$item.Optional
        Firmware  = [bool](Test-IsFirmware $u)
    }
}

Stage 66 93 'Durchsuche den Microsoft-Katalog …'
$hints = @()
try {
    $found = @(if ($a.Catalog) { Find-CatalogHints $global:DD_Installed })
    foreach ($group in ($found | Group-Object { '{0}|{1}' -f $_.Entry.Title, $_.Entry.Version })) {
        $first = $group.Group[0]
        $tiny = $first.Entry.Bytes -gt 0 -and $first.Entry.Bytes -lt 200KB -and -not ($group.Group | Where-Object { $_.HasService })
        $hints += @{
            Title     = "$($first.Entry.Title)"
            Date      = Format-Date $first.Entry.Date
            Size      = "$($first.Entry.Size)"
            Device    = (@($group.Group | ForEach-Object { $_.Driver.DeviceName } | Select-Object -Unique) -join ', ')
            Installed = Format-DriverText $first.Driver.DriverVersion $first.Driver.ActualDate
            Url       = "$($first.Url)"
            NoCode    = [bool]$tiny
        }
    }
}
catch { $failed += 'Katalog' }

# Geräte ohne Treiber: steht im Microsoft-Katalog einer? Dann sagt es die Zeile des Geräts, und "Beheben" kann ihn
# auf Bestätigung installieren. Eine fehlgeschlagene Nachfrage ist kein Befund - die Zeile bleibt dann, wie sie war.
# Antwortet der Katalog nicht, hört die Nachfrage beim ersten Fehlschlag auf (jede weitere würde wieder bis zum
# Zeitlimit warten), und mehr als acht Geräte werden nicht nachgeschlagen.
if ($a.Catalog) {
    $asked = 0
    foreach ($problem in $problems) {
        if ($problem.Code -ne 28 -or -not $problem.Id) { continue }
        if ($asked -ge 8) { break }
        $asked++
        try { $offer = Find-MissingDriver $problem.Id; if ($offer) { $problem.Catalog = "$($offer.Version)" } } catch { break }
    }
}

# Welche Quellen wurden auf diesem PC überhaupt gefragt? Und: Intel lässt sich nicht direkt abfragen - dafür gibt es
# auf Intel-Systemen einen Hinweis auf Intels eigenen Assistenten.
$sources = @('Windows Update')
$intel = $false
$radeon = $false
try {
    $cpuMaker = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer)"
    $gpuNames = @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name)" })
    if ($a.Nvidia -and ($gpuNames -match 'NVIDIA')) { $sources += 'NVIDIA' }
    if ($a.Nvidia -and $cpuMaker -match 'AMD') { $sources += 'AMD' }
    $intel = [bool]($cpuMaker -match 'Intel' -or ($gpuNames -match 'Intel'))
    # Radeon-Grafik: AMD lässt sich für den Grafiktreiber nicht direkt abfragen - Hinweis auf AMDs eigene Software
    $radeon = [bool]($gpuNames -match 'Radeon|^AMD ')
}
catch { }
if ($a.Catalog) { $sources += 'Katalog' }

Stage 93 99 'Prüfe Spielkomponenten …'
$runtimes = @()
try { $runtimes = @(Get-RuntimeStatus | ForEach-Object { @{ Name = "$($_.Name)"; Status = "$($_.Status)"; CanInstall = [bool]$_.Url } }) } catch { }

# alle Treiber für die Liste "Aktuell"; gleiche Einträge (z.B. mehrere PCI-Brücken) zusammengefasst
$drivers = @($global:DD_Installed | Group-Object DeviceClass, DeviceName, DriverVersion | ForEach-Object {
        $d = $_.Group[0]
        $query = $null
        try { $query = Get-CatalogQuery "$($d.HardWareID)" } catch { }
        @{
            Name       = "$($d.DeviceName)"
            Class      = "$($d.DeviceClass)"
            Version    = "$($d.DriverVersion)"
            Date       = Format-Date $d.ActualDate
            Provider   = "$($d.DriverProviderName)"
            Inf        = "$($d.InfName)"
            HardwareId = "$($d.HardWareID)"
            Signer     = "$($d.Signer)"
            Count      = $_.Count
            ThirdParty = [bool]($d.DriverProviderName -and $d.DriverProviderName -notlike 'Microsoft*')
            Catalog    = if ($query) { Get-CatalogUrl $query } else { '' }
        }
    })

@{
    Drivers     = $drivers
    Devices     = $global:DD_Installed.Count
    ThirdParty  = @($global:DD_Installed | Where-Object { $_.DriverProviderName -and $_.DriverProviderName -notlike 'Microsoft*' }).Count
    Problems    = $problems
    Board       = $board
    Updates     = $updates
    Nvidia      = $nvidia
    Amd         = $amd
    Hints       = $hints
    Failed      = $failed
    Sources     = $sources
    Intel       = $intel
    # fragt PulsRig AMD selbst, braucht es den allgemeinen Hinweis auf AMDs Software nicht
    Radeon      = $radeon -and -not $radeonDriver
    RadeonDriver = $radeonDriver
    Runtimes    = $runtimes
    SearchError = $searchError
}
