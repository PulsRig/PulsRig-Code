# PulsRig - Hardware: die Bereiche der Hardware-Seite, die schon eine Funktion haben.
# Wird von PulsRig.ps1 eingebunden und nutzt dessen Fenster, den großen Dialog mit Listen und den Arbeitsbereich.
#
# Bisher: Laufwerke (Zustand, Belegung, Einzelheiten, Störungen aus dem Ereignisprotokoll, Tempotest).
# Dazu Arbeitsspeicher (Riegel, Belegung, Speichertest von Windows) und Sensoren (Grafikkarte, Prozessor, Speicher
# im Sekundentakt mit Kurven) und Stabilitätstest (Volllast für Prozessor und Grafikkarte mit Überwachung).
# Der Prüfbericht fasst die Ergebnisse zusammen und speichert sie als Datei. Die FPS-Anzeige ist zurückgestellt:
# an ihrer Stelle steht die Karte "Diagnose-Paket" (PulsRig-Diagnose.ps1).

# --- Karten der Hardware-Seite freischalten -----------------------------------

# Macht eine Karte der Hardware-Seite benutzbar: Handzeiger, Hervorhebung unter der Maus, Klick.
# Dazu bekommt sie eine Fußzeile, die am unteren Rand sitzt: links der wichtigste Wert der letzten Prüfung oder,
# solange es keinen gibt, was ein Klick tut; rechts ein Pfeil. Was dort und im Schild oben rechts steht,
# bestimmt Update-HardwareBadges.
$script:HardwareCards = @{}
function Enable-HardwareCard([int]$Index, [scriptblock]$Action) {
    $card = $ui.HardwareGrid.Children[$Index]
    $stack = $card.Child
    $grid = New-Object Windows.Controls.Grid
    $top = New-Object Windows.Controls.RowDefinition
    $bottom = New-Object Windows.Controls.RowDefinition
    $bottom.Height = [Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($top)
    $grid.RowDefinitions.Add($bottom)
    $card.Child = $null
    [void]$grid.Children.Add($stack)
    $foot = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRow($foot, 1)
    $line = New-Object Windows.Controls.Border
    $line.Height = 1
    $line.VerticalAlignment = 'Top'
    $line.Background = New-Brush '#14FFFFFF'
    $text = New-Object Windows.Controls.TextBlock
    $text.FontSize = 12
    $text.Margin = '0,9,18,0'
    # die Karten sind schmal (vier nebeneinander): lieber zwei Zeilen als abgeschnitten
    $text.TextWrapping = 'Wrap'
    $arrow = New-Object Windows.Controls.TextBlock
    $arrow.Text = Get-Glyph 0xE76C
    $arrow.FontFamily = 'Segoe MDL2 Assets'
    $arrow.FontSize = 10
    $arrow.HorizontalAlignment = 'Right'
    $arrow.VerticalAlignment = 'Bottom'
    $arrow.Margin = '0,0,0,3'
    Set-Paint $arrow 'Foreground' 'TextFaint'
    foreach ($part in $line, $text, $arrow) { [void]$foot.Children.Add($part) }
    [void]$grid.Children.Add($foot)
    $card.Child = $grid
    $script:HardwareCards[$Index] = @{ Badge = $stack.Children[0].Children[1]; Foot = $text; Stack = $stack }
    # das Schild darf nie über das Symbol laufen: ist es zu lang (breite Schrift eines Skins), bricht es um
    $badge = $script:HardwareCards[$Index].Badge
    $badge.Margin = '48,0,0,0'
    $badge.Child.TextWrapping = 'Wrap'
    $badge.Child.TextAlignment = 'Right'
    $card.Cursor = 'Hand'
    $card.Tag = $Action
    if ($card.RenderTransform -isnot [Windows.Media.ScaleTransform]) {
        $card.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $card.RenderTransform = New-Object Windows.Media.ScaleTransform
    }
    # unter der Maus wächst die Karte leicht und bekommt einen farbigen Rand
    $card.Add_MouseEnter({
            try {
                Set-Paint $this 'BorderBrush' 'Accent'
                if ($this.RenderTransform -is [Windows.Media.ScaleTransform]) { Start-Scale $this 1.02 200 }
            }
            catch { Write-AppError $_ }
        })
    $card.Add_MouseLeave({
            try {
                $this.ClearValue([Windows.Controls.Border]::BorderBrushProperty)
                if ($this.RenderTransform -is [Windows.Media.ScaleTransform]) { Start-Scale $this 1 280 }
            }
            catch { Write-AppError $_ }
        })
    $card.Add_MouseLeftButtonUp({ try { & $this.Tag } catch { Write-AppError $_ } })
}

# --- Laufwerke ----------------------------------------------------------------

# Läuft im Arbeitsbereich: liest die eingebauten Laufwerke und ihre Volumes - über Get-DiskList, Get-PartitionList
# und Get-VolumeList aus Treiber-Werkzeuge.ps1, nicht über die speicherhungrigen Befehle von Windows.
# Zustand und Belegung gibt Windows
# jedem; Temperatur, Betriebsstunden und Abnutzung (Zuverlässigkeitswerte) nur mit Adminrechten.
$script:Queries.Drives = @'
param($a)
$diskOfLetter = @{}
$lettersOfDisk = @{}
try {
    foreach ($partition in @(Get-PartitionList | Where-Object { $_.DriveLetter })) {
        $letter = "$($partition.DriveLetter)"
        $number = "$($partition.DiskNumber)"
        $diskOfLetter[$letter] = $number
        $lettersOfDisk[$number] = @($lettersOfDisk[$number] | Where-Object { $_ }) + $letter
    }
}
catch { }

$volumes = @()
try {
    $volumes = @(Get-VolumeList | Where-Object { $_.DriveLetter -and $_.Size -gt 0 } | Sort-Object DriveLetter | ForEach-Object {
            @{
                Letter     = "$($_.DriveLetter)"
                Label      = "$($_.FileSystemLabel)"
                FileSystem = "$($_.FileSystem)"
                Health     = "$($_.HealthStatus)"
                Size       = [double]$_.Size
                Free       = [double]$_.SizeRemaining
                Disk       = "$($diskOfLetter["$($_.DriveLetter)"])"
            }
        })
}
catch { }

$detailed = $false
$disks = @()
try {
$disks = @(Get-DiskList -Counters | Sort-Object { [int]$_.DeviceId } | ForEach-Object {
        $counter = $null
        $counter = $_.Counter
        if ($counter) { $detailed = $true }
        @{
            Number      = "$($_.DeviceId)"
            Name        = "$($_.FriendlyName)".Trim()
            Media       = "$($_.MediaType)"
            Bus         = "$($_.BusType)"
            Size        = [double]$_.Size
            Health      = "$($_.HealthStatus)"
            Status      = "$($_.OperationalStatus)"
            Firmware    = "$($_.FirmwareVersion)".Trim()
            Serial      = "$($_.SerialNumber)".Trim().TrimEnd('.')
            Letters     = @($lettersOfDisk["$($_.DeviceId)"] | Where-Object { $_ } | Sort-Object)
            Temperature = $(if ($counter -and $counter.Temperature) { [int]$counter.Temperature })
            Hours       = $(if ($counter -and $null -ne $counter.PowerOnHours) { [long]$counter.PowerOnHours })
            Wear        = $(if ($counter -and $null -ne $counter.Wear) { [int]$counter.Wear })
            ReadErrors  = $(if ($counter -and $null -ne $counter.ReadErrorsTotal) { [long]$counter.ReadErrorsTotal })
            WriteErrors = $(if ($counter -and $null -ne $counter.WriteErrorsTotal) { [long]$counter.WriteErrorsTotal })
            Starts      = $(if ($counter -and $null -ne $counter.StartStopCycleCount) { [long]$counter.StartStopCycleCount })
        }
    })
}
catch { }   # ohne die Laufwerksverwaltung von Windows bleiben wenigstens Volumes und Belegung
# Störungen aus dem Ereignisprotokoll von Windows (30 Tage): wiederholte oder fehlgeschlagene Zugriffe je Laufwerk
# (Quelle "disk") und Zurücksetzungen eines Anschlusses (Kennung 129 der Speichertreiber, keinem Laufwerk zuzuordnen)
$faults = @{}
$resets = 0
$lastReset = $null
# "nichts gefunden" meldet Windows als Fehler; alles andere heißt, dass das Protokoll nicht lesbar ist
$log = $true
try {
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-30); Id = 7, 11, 51, 129, 153 } -ErrorAction Stop)
    foreach ($entry in $events) {
        if ($entry.Id -eq 129) {
            if ($entry.ProviderName -match 'stor|ahci|nvme|raid|scsi') {
                $resets++
                if (-not $lastReset) { $lastReset = $entry.TimeCreated }
            }
            continue
        }
        if ($entry.ProviderName -ne 'disk') { continue }
        $number = if ($entry.Message -match 'Harddisk(\d+)') { $Matches[1] } elseif ($entry.Message -match '"(\d+)"') { $Matches[1] } else { '' }
        if (-not $number) { continue }
        if (-not $faults[$number]) { $faults[$number] = @{ Count = 0; Last = $entry.TimeCreated } }
        $faults[$number].Count++
    }
}
catch { if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $log = $false } }
foreach ($disk in $disks) {
    $fault = $faults[$disk.Number]
    $disk.Faults = $(if ($fault) { [int]$fault.Count } else { 0 })
    $disk.LastFault = $(if ($fault) { $fault.Last.ToString('dd.MM. HH:mm') } else { '' })
}
@{ Disks = $disks; Volumes = $volumes; Detailed = $detailed; Log = $log; Time = (Get-Date).ToString('HH:mm'); Resets = $resets; LastReset = $(if ($lastReset) { $lastReset.ToString('dd.MM. HH:mm') } else { '' }) }
'@

function Format-DriveSize([double]$Bytes) {
    if ($Bytes -ge 1000GB) { '{0:N2} TB' -f ($Bytes / 1TB) } else { '{0:N0} GB' -f ($Bytes / 1GB) }
}

# Art des Laufwerks in Worten; Windows meldet ältere Festplatten oft ohne Angabe
function Get-DriveKind($Disk) {
    switch ($Disk.Media) { 'SSD' { 'SSD' } 'HDD' { 'Festplatte' } default { 'Laufwerk' } }
}

# Zustand, wie Windows ihn meldet: Text und Farbton für die Liste
function Get-DriveHealth([string]$Health) {
    switch ($Health) {
        'Healthy' { @{ Text = 'in Ordnung'; Tone = 'good'; Glyph = 0xE73E } }
        'Warning' { @{ Text = 'Warnung'; Tone = 'warn'; Glyph = 0xE7BA } }
        'Unhealthy' { @{ Text = 'defekt'; Tone = 'bad'; Glyph = 0xE783 } }
        default { @{ Text = 'unbekannt'; Tone = ''; Glyph = 0xE9CE } }
    }
}

function Open-DriveSheet {
    $opened = Open-Sheet @{
        Title  = 'Laufwerke'
        Sub    = 'Zustand und Belegung der eingebauten Laufwerke'
        Glyph  = 0xEDA2
        Tabs   = 'Übersicht', 'Einzelheiten', 'Tempo', 'Verlauf'
        Link   = 'Neu einlesen'
        Show   = { param($tab) Show-DriveTab }
        OnAction = { param($item) if ($item.Data -and $item.Data.Type -eq 'speed') { Start-DriveSpeed $item.Data.Letter } }
        OnLink = {
            if ($script:Sheet.Measuring) { return }
            $script:Sheet.Drives = $null
            $script:SheetWay = 0
            $ui.SheetChips.Children.Clear()
            Show-DriveTab
            Start-Query 'Drives' { param($result) Complete-DriveQuery $result }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese die Laufwerke …'
    Start-Query 'Drives' { param($result) Complete-DriveQuery $result }
}

function Complete-DriveQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Drives = $Result
    Set-CardState 'Drives' (Get-DriveCardState $Result)
    Add-DriveHistory $Result
    Update-DriveWarn $Result
    $disks = @($Result.Disks)
    $bad = @($disks | Where-Object { $_.Health -ne 'Healthy' -or $_.Faults -gt 0 }).Count
    $free = [double](@($Result.Volumes) | ForEach-Object { $_.Free } | Measure-Object -Sum).Sum
    # Bilanz als Schilder neben den Reitern
    $ui.SheetChips.Children.Clear()
    if ($disks.Count -eq 0) {
        Add-ResultChip 'keine Angaben' 'Ring2' $ui.SheetChips
        if (@($Result.Volumes).Count -gt 0) { Add-ResultChip "$(Format-DriveSize $free) frei" 'Ring2' $ui.SheetChips }
        Show-DriveTab
        return
    }
    Add-ResultChip $(if ($disks.Count -eq 1) { '1 Laufwerk' } else { "$($disks.Count) Laufwerke" }) 'Accent' $ui.SheetChips
    Add-ResultChip $(if ($bad -eq 0) { if ($disks.Count -eq 1) { 'in Ordnung' } else { 'alle in Ordnung' } } elseif ($bad -eq 1) { '1 auffällig' } else { "$bad auffällig" }) $(if ($bad) { 'Warn' } else { 'Good' }) $ui.SheetChips
    Add-ResultChip "$(Format-DriveSize $free) frei" 'Ring2' $ui.SheetChips
    Show-DriveTab
}

function Show-DriveTab {
    $data = $script:Sheet.Drives
    if ($script:Sheet.Measuring) {
        Start-SheetLoader "Messe das Tempo von $($script:Sheet.Measuring): – meist unter 20 Sekunden, bei einem gestörten Laufwerk auch Minuten …"
        return
    }
    if (-not $data) {
        Start-SheetLoader 'Lese die Laufwerke …'
        return
    }
    if ($script:Sheet.Tab -eq 2) {
        Show-DriveSpeedTab
        return
    }
    if ($script:Sheet.Tab -eq 3) {
        Show-DriveHistoryTab
        return
    }
    $disks = @($data.Disks)
    $rows = @()
    if ($disks.Count -eq 0) {
        $rows += New-SheetRow -Title 'Windows hat kein Laufwerk gemeldet' -Sub 'Das kommt in virtuellen Maschinen vor oder wenn die Laufwerksverwaltung von Windows nicht antwortet.' -Glyph 0xE946
    }
    elseif ($script:Sheet.Tab -eq 0) {
        $rows += New-SheetRow -Kind 'head' -Title 'LAUFWERKE'
        foreach ($disk in $disks) {
            $health = Get-DriveHealth $disk.Health
            $parts = @(@((Get-DriveKind $disk), $disk.Bus, (Format-DriveSize $disk.Size)) | Where-Object { $_ })
            if (@($disk.Letters).Count -gt 0) { $parts += (@($disk.Letters | ForEach-Object { "$_`:" }) -join ' ') }
            # meldet Windows das Laufwerk als gesund, hat aber Störungen protokolliert, gilt es als auffällig
            if ($disk.Faults -gt 0) {
                $parts += $(if ($disk.Faults -eq 1) { '1 Störung in 30 Tagen' } else { "$($disk.Faults) Störungen in 30 Tagen" })
                if ($disk.Health -eq 'Healthy') { $health = @{ Text = 'auffällig'; Tone = 'warn' } }
            }
            $rows += New-SheetRow -Title $disk.Name -Sub ($parts -join ' · ') -Glyph 0xEDA2 -State $health.Text -Tone $health.Tone `
                -Value $(if ($disk.Temperature) { "$($disk.Temperature) °C" })
        }
        if ($data.Resets -gt 0) {
            $rows += New-SheetRow -Title $(if ($data.Resets -eq 1) { 'Windows musste 1-mal die Verbindung zu einem Laufwerk neu aufbauen' } else { "Windows musste $($data.Resets)-mal die Verbindung zu einem Laufwerk neu aufbauen" }) `
                -Sub "In den letzten 30 Tagen, zuletzt $($data.LastReset). Häufige Ursachen: Kabel, Anschluss oder ein schwächelndes Laufwerk." -Glyph 0xE7BA -Tone 'warn'
        }
        if ($false -eq $data.Log) {
            $rows += New-SheetRow -Title 'Störungen der letzten 30 Tage sind nicht lesbar' -Sub 'Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus. Der Zustand oben stammt vom Laufwerk selbst.' -Glyph 0xE946
        }
        $volumes = @($data.Volumes)
        if ($volumes.Count -gt 0) {
            $rows += New-SheetRow -Kind 'head' -Title 'BELEGUNG'
            foreach ($volume in $volumes) {
                $used = if ($volume.Size -gt 0) { 1 - $volume.Free / $volume.Size } else { 0 }
                $title = if ($volume.Label) { "$($volume.Letter):   $($volume.Label)" } else { "$($volume.Letter):" }
                # unter zehn Prozent frei: Hinweis, dass es eng wird
                $tight = $used -gt 0.9
                $rows += New-SheetRow -Title $title -Sub ("{0} · {1} frei von {2}" -f $volume.FileSystem, (Format-DriveSize $volume.Free), (Format-DriveSize $volume.Size)) `
                    -Glyph 0xE8B7 -Bar $used -Value ('{0:N0} % belegt' -f ($used * 100)) -State $(if ($tight) { 'fast voll' }) -Tone $(if ($tight) { 'warn' } else { 'accent' })
            }
        }
    }
    else {
        foreach ($disk in $disks) {
            $health = Get-DriveHealth $disk.Health
            $rows += New-SheetRow -Kind 'head' -Title $disk.Name.ToUpper()
            $pairs = [ordered]@{
                'Art'             = Get-DriveKind $disk
                'Anschluss'       = $disk.Bus
                'Größe'           = Format-DriveSize $disk.Size
                'Laufwerksbuchstaben' = (@($disk.Letters | ForEach-Object { "$_`:" }) -join ', ')
                'Zustand'         = $health.Text
                'Betriebszustand' = $(if ($disk.Status -eq 'OK') { 'bereit' } else { $disk.Status })
                'Firmware'        = $disk.Firmware
                'Seriennummer'    = $disk.Serial
                'Störungen (30 Tage)' = $(if ($disk.Faults -gt 0) { "$($disk.Faults) im Ereignisprotokoll von Windows, zuletzt $($disk.LastFault)" } elseif ($false -eq $data.Log) { 'nicht lesbar' } else { 'keine' })
            }
            if ($data.Detailed) {
                if ($disk.Temperature) { $pairs['Temperatur'] = "$($disk.Temperature) °C" }
                if ($null -ne $disk.Hours) { $pairs['Betriebsstunden'] = '{0:N0} Stunden (rund {1:N0} Tage)' -f $disk.Hours, ($disk.Hours / 24) }
                if ($null -ne $disk.Starts) { $pairs['Einschaltungen'] = '{0:N0}' -f $disk.Starts }
                if ($null -ne $disk.Wear) { $pairs['Abnutzung'] = "$($disk.Wear) %" }
                if ($null -ne $disk.ReadErrors) { $pairs['Lesefehler'] = '{0:N0}' -f $disk.ReadErrors }
                if ($null -ne $disk.WriteErrors) { $pairs['Schreibfehler'] = '{0:N0}' -f $disk.WriteErrors }
            }
            else { $pairs['Weitere Werte'] = 'Temperatur, Betriebsstunden und Abnutzung nur mit Adminrechten' }
            foreach ($key in $pairs.Keys) {
                if ("$($pairs[$key])") { $rows += New-SheetRow -Kind 'pair' -Title $key -Value "$($pairs[$key])" }
            }
        }
    }
    Show-SheetList $rows
    Set-SheetStateText $(if ($data.Detailed) { "Stand: $($data.Time) Uhr" } else { "Stand: $($data.Time) Uhr · Temperatur und Betriebsstunden zeigt Windows nur mit Adminrechten" })
}

# --- Laufwerke: Tempo ----------------------------------------------------------

# Messergebnisse je Laufwerksbuchstabe; bleiben stehen, solange das Programm läuft
$script:DriveSpeed = @{}

function Start-DriveSpeed([string]$Letter) {
    if (-not $script:Sheet -or $script:Sheet.Measuring) { return }
    $script:Sheet.Measuring = $Letter
    $script:SheetWay = 0
    Show-DriveTab
    Start-Query 'DriveSpeed' {
        param($result)
        if (-not $script:Sheet) { return }
        $script:Sheet.Measuring = $null
        Show-DriveTab
    } @{ Letter = $Letter; TargetDir = (Get-TargetDir) }
}

# Balkenlänge für ein Tempo: die Wurzel staucht die Spanne, sonst wäre neben einer NVMe-SSD jede Festplatte unsichtbar
function Get-SpeedBar([double]$Value, [double]$Top) {
    if ($Value -le 0) { return 0.0 }
    [Math]::Min(1.0, [Math]::Sqrt($Value / $Top))
}

function Show-DriveSpeedTab {
    $data = $script:Sheet.Drives
    $rows = @()
    foreach ($volume in @($data.Volumes)) {
        $disk = @($data.Disks | Where-Object { $_.Number -eq $volume.Disk })[0]
        $name = if ($disk) { $disk.Name } elseif ($volume.Label) { $volume.Label } else { 'Laufwerk' }
        $result = $script:DriveSpeed[$volume.Letter]
        $sub = if (-not $result) { 'Noch nicht gemessen. Die Messung schreibt eine Testdatei von bis zu 1 GB und löscht sie wieder.' }
        elseif ($result.Error) { "Messung $(Format-SpeedWhen $result) nicht möglich: $($result.Error)" }
        else {
            $when = if ($result.Date -and $result.Date -ne (Get-Date).ToString('dd.MM.yyyy')) { "am $($result.Date.Substring(0, 6)) um $($result.Time)" } else { "heute um $($result.Time)" }
            $format = { param($v) if ($v -lt 10) { '{0:N1}' -f $v } else { '{0:N0}' -f $v } }
            "Lesen $(& $format $result.Read) · Schreiben $(& $format $result.Write) · kleine Dateien $('{0:N1}' -f $result.Small) MB/s · $when"
        }
        # eine Zeile je Laufwerk, damit auch drei oder vier Laufwerke ohne Scrollen passen; der Balken zeigt das Lesetempo
        $bar = if ($result -and -not $result.Error) { Get-SpeedBar $result.Read 3500 } else { $null }
        $rows += New-SheetRow -Title "$($volume.Letter): · $name" -Sub $sub -Glyph 0xEC4A -Tone $(if ($result -and $result.Error) { 'warn' } else { 'accent' }) -Bar $bar `
            -Action $(if ($result) { 'Erneut messen' } else { 'Tempo messen' }) -Data @{ Type = 'speed'; Letter = $volume.Letter }
        if ($result -and -not $result.Error) {
            # weit unter dem, was selbst eine alte Festplatte schafft: das deutet auf eine Störung, nicht auf ein langsames Modell
            if ($result.Read -lt 25 -or $result.Write -lt 15) {
                $rows += New-SheetRow -Title "$($volume.Letter): auffällig langsam" -Sub 'So langsam ist kein gesundes Laufwerk. Kabel und Anschluss prüfen; siehe auch „Übersicht“.' `
                    -Glyph 0xE7BA -Tone 'warn' -State 'prüfen'
            }
        }
    }
    if ($rows.Count -eq 0) { $rows += New-SheetRow -Title 'Kein Laufwerk mit Laufwerksbuchstaben gefunden' -Glyph 0xE946 }
    Show-SheetList $rows
    Set-SheetStateText 'Richtwerte am Stück: Festplatte 80–200 · SATA-SSD 400–550 · NVMe-SSD ab 1.500 MB/s'
}

# Läuft im Arbeitsbereich: misst das Tempo eines Laufwerks mit einer Testdatei, die danach wieder verschwindet.
# Gemessen wird am Windows-Zwischenspeicher vorbei, sonst käme beim Lesen nur das Tempo des Arbeitsspeichers heraus.
$script:Queries.DriveSpeed = @'
param($a)
$result = @{ Letter = "$($a.Letter)"; Time = (Get-Date).ToString('HH:mm'); Date = (Get-Date).ToString('dd.MM.yyyy'); Error = '' }
try {
    if (-not ('PulsRigDiskTest' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class PulsRigDiskTest
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(SafeFileHandle handle, IntPtr buffer, uint count, out uint done, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(SafeFileHandle handle, IntPtr buffer, uint count, out uint done, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFilePointerEx(SafeFileHandle handle, long distance, out long position, uint method);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr VirtualAlloc(IntPtr address, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool VirtualFree(IntPtr address, UIntPtr size, uint type);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle handle, uint code, ref ushort input, uint inputSize, IntPtr output, uint outputSize, out uint returned, IntPtr overlapped);

    // Ergebnis: Schreiben am Stück, Lesen am Stück, kleine zufällige Lesezugriffe (alles MB/s), Größe der Testdatei in MB.
    // Fehlercode 5 (Zugriff verweigert) kommt als negative Zahl im ersten Feld zurück, damit der Aufrufer einen anderen Ordner probiert.
    public static double[] Run(string path, long maxBytes, double seconds)
    {
        const int block = 1 << 20;
        IntPtr buffer = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)block, 0x3000, 0x04);
        if (buffer == IntPtr.Zero) throw new IOException("Kein Speicher für die Messung");
        try
        {
            // Zufallsdaten: manche Laufwerke stauchen gleichförmige Daten und wirken dann schneller, als sie sind
            byte[] noise = new byte[block];
            new Random(12345).NextBytes(noise);
            Marshal.Copy(noise, 0, buffer, block);
            // Lesen und Schreiben, immer neu anlegen; ohne Zwischenspeicher, direkt durchschreiben, beim Schließen löschen
            using (SafeFileHandle handle = CreateFile(path, 0xC0000000, 0, IntPtr.Zero, 2, 0xA4000000u, IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    int code = Marshal.GetLastWin32Error();
                    if (code == 5) return new double[] { -5, 0, 0, 0 };
                    throw new IOException("Die Testdatei lässt sich nicht anlegen (Windows-Fehler " + code + ")");
                }
                uint done;
                long position;
                // liegt die Datei in einem komprimierten Ordner, erbt sie die Komprimierung: dann schreibt Windows langsam und
                // liest immer über den Zwischenspeicher - gemessen würde der Prozessor statt des Laufwerks. Also abschalten.
                ushort plain = 0;
                DeviceIoControl(handle, 0x9C040, ref plain, 2, IntPtr.Zero, 0, out done, IntPtr.Zero);
                long written = 0;
                Stopwatch watch = Stopwatch.StartNew();
                while (written < maxBytes && watch.Elapsed.TotalSeconds < seconds)
                {
                    if (!WriteFile(handle, buffer, block, out done, IntPtr.Zero)) throw new IOException("Schreiben fehlgeschlagen (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                    written += done;
                }
                double write = written / 1048576.0 / watch.Elapsed.TotalSeconds;

                SetFilePointerEx(handle, 0, out position, 0);
                long read = 0;
                watch.Restart();
                while (read < written && watch.Elapsed.TotalSeconds < seconds)
                {
                    if (!ReadFile(handle, buffer, block, out done, IntPtr.Zero)) throw new IOException("Lesen fehlgeschlagen (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                    if (done == 0) break;
                    read += done;
                }
                double readSpeed = read / 1048576.0 / watch.Elapsed.TotalSeconds;

                // kleine Zugriffe: 4 KB an zufälligen Stellen, einer nach dem anderen
                Random random = new Random(7);
                long blocks = written / 4096;
                long count = 0;
                double smallSeconds = Math.Min(seconds, 3.0);
                watch.Restart();
                while (blocks > 0 && watch.Elapsed.TotalSeconds < smallSeconds)
                {
                    SetFilePointerEx(handle, (long)(random.NextDouble() * blocks) * 4096, out position, 0);
                    if (!ReadFile(handle, buffer, 4096, out done, IntPtr.Zero)) break;
                    count++;
                }
                double small = count * 4096 / 1048576.0 / watch.Elapsed.TotalSeconds;
                return new double[] { write, readSpeed, small, written / 1048576.0 };
            }
        }
        finally { VirtualFree(buffer, UIntPtr.Zero, 0x8000); }
    }
}
"@
    }
    $letter = "$($a.Letter)"
    $free = ([IO.DriveInfo]"$letter`:").AvailableFreeSpace
    if ($free -lt 3GB) { throw 'Für die Messung müssen mindestens 3 GB frei sein.' }
    # Ordner auf diesem Laufwerk, in den sicher geschrieben werden darf; zuletzt das Hauptverzeichnis
    $folders = @()
    foreach ($folder in $env:TEMP, $a.TargetDir, $global:DD_BaseDir) {
        if ($folder -and "$folder".Length -gt 2 -and "$folder".Substring(0, 1) -ieq $letter -and (Test-Path -LiteralPath $folder)) { $folders += "$folder" }
    }
    $folders += "$letter`:\"
    $values = $null
    foreach ($folder in $folders) {
        $file = Join-Path $folder 'PulsRig-Tempotest.tmp'
        $values = [PulsRigDiskTest]::Run($file, 1GB, 5.0)
        if ($values[0] -ge 0) { break }
        $values = $null
    }
    if (-not $values) { throw 'Auf dieses Laufwerk darf ohne Adminrechte nicht geschrieben werden.' }
    $result.Write = [double]$values[0]
    $result.Read = [double]$values[1]
    $result.Small = [double]$values[2]
    $result.SizeMb = [double]$values[3]
}
catch {
    $result.Error = "$($_.Exception.InnerException.Message)"
    if (-not $result.Error) { $result.Error = "$($_.Exception.Message)" }
}
$result
'@

# --- Arbeitsspeicher ----------------------------------------------------------

# Läuft im Arbeitsbereich: eingebaute Speicherriegel, Belegung, das letzte Ergebnis der Speicherdiagnose von Windows
# und Hardwarefehler aus dem Ereignisprotokoll. Alles ohne Adminrechte lesbar.
$script:Queries.Memory = @'
param($a)
$types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5' }
$modules = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $maker = "$($_.Manufacturer)".Trim()
        if ($maker -match '^(Unknown|Undefined|0+)$') { $maker = '' }
        @{
            Slot    = "$($_.DeviceLocator)".Trim()
            Bank    = "$($_.BankLabel)".Trim()
            Maker   = $maker
            Part    = "$($_.PartNumber)".Trim()
            Bytes   = [double]$_.Capacity
            Speed   = $(if ($_.ConfiguredClockSpeed) { [int]$_.ConfiguredClockSpeed } else { [int]$_.Speed })
            Rated   = [int]$_.Speed
            Voltage = $(if ($_.ConfiguredVoltage) { [int]$_.ConfiguredVoltage } else { 0 })
            Type    = $(if ($types.ContainsKey([int]$_.SMBIOSMemoryType)) { $types[[int]$_.SMBIOSMemoryType] } else { '' })
            Laptop  = [int]$_.FormFactor -eq 12
        }
    })
$slots = 0; $maxBytes = 0.0
try {
    foreach ($array in @(Get-CimInstance Win32_PhysicalMemoryArray)) {
        $slots += [int]$array.MemoryDevices
        $maxBytes += $(if ($array.MaxCapacityEx) { [double]$array.MaxCapacityEx * 1KB } else { [double]$array.MaxCapacity * 1KB })
    }
}
catch { }
# Reihenfolge der Steckplätze samt der leeren: steht nur in der Rohtabelle des BIOS (SMBIOS, Einträge der Art 17)
$layout = @()
try {
    $raw = (Get-CimInstance -Namespace root\wmi -ClassName MSSmBios_RawSMBiosTables -ErrorAction Stop | Select-Object -First 1).SMBiosData
    $at = 0; $filled = 0
    while ($at -lt $raw.Length - 4) {
        $kind = $raw[$at]; $length = $raw[$at + 1]
        if ($length -lt 4) { break }
        # hinter dem festen Teil stehen die Texte des Eintrags, jeder mit einer Null beendet, am Ende zwei Nullen
        $next = $at + $length; $strings = @()
        while ($next -lt $raw.Length - 1 -and -not ($raw[$next] -eq 0 -and $raw[$next + 1] -eq 0)) {
            $end = $next
            while ($end -lt $raw.Length -and $raw[$end] -ne 0) { $end++ }
            $strings += [Text.Encoding]::ASCII.GetString($raw, $next, $end - $next)
            $next = $end
            if ($next -lt $raw.Length - 1 -and $raw[$next + 1] -ne 0) { $next++ }
        }
        if ($kind -eq 17 -and $length -ge 0x12) {
            $size = [BitConverter]::ToUInt16($raw, $at + 0x0C)
            $names = foreach ($offset in 0x10, 0x11) { $index = [int]$raw[$at + $offset]; if ($index -ge 1 -and $index -le $strings.Count) { "$($strings[$index - 1])".Trim() } else { '' } }
            $place = @{ Slot = $names[0]; Bank = $names[1]; Module = -1 }
            if ($size -ne 0 -and $size -ne 0xFFFF) { $place.Module = $filled; $filled++ }
            $layout += $place
        }
        if ($kind -eq 127) { break }
        $at = $next + 2
    }
    # passt die Zahl der belegten Plätze nicht zu den Riegeln von Windows, ist der Tabelle nicht zu trauen
    if ($filled -ne $modules.Count) { $layout = @() }
}
catch { $layout = @() }
$total = 0.0; $free = 0.0
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $free = [double]$os.FreePhysicalMemory * 1KB
}
catch { }

# letzter Lauf der Speicherdiagnose: Kennung 1201 = keine Fehler, 1202 = Fehler gefunden
$test = $null
# "nichts gefunden" meldet Windows als Fehler; alles andere heißt, dass das Protokoll nicht lesbar ist
$log = $true
try {
    $entry = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop
    if ($entry) { $test = @{ Time = $entry.TimeCreated.ToString('dd.MM.yyyy HH:mm'); Ok = ($entry.Id -eq 1201); Text = ("$($entry.Message)" -split "`r?`n")[0] } }
}
catch { if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $log = $false } }

# von der Hardware gemeldete Fehler der letzten 90 Tage (Prozessor, Speicher, Bus)
$hardware = 0; $lastHardware = ''
try {
    # nur Warnungen und Fehler (Stufe 1 bis 3): reine Hinweise des Protokolls sind kein Befund
    $entries = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddDays(-90); Level = 1, 2, 3 } -ErrorAction Stop)
    $hardware = $entries.Count
    if ($hardware) { $lastHardware = $entries[0].TimeCreated.ToString('dd.MM.yyyy HH:mm') }
}
catch { if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $log = $false } }

@{ Modules = $modules; Layout = $layout; Slots = $slots; MaxBytes = $maxBytes; Total = $total; Free = $free; Test = $test; Hardware = $hardware; LastHardware = $lastHardware; Log = $log; Time = (Get-Date).ToString('HH:mm') }
'@

function Open-MemorySheet {
    $opened = Open-Sheet @{
        Title    = 'Arbeitsspeicher'
        Sub      = 'Eingebaute Riegel, Belegung und Speichertest'
        Glyph    = 0xE950
        Tabs     = 'Übersicht', 'Test'
        Link     = 'Neu einlesen'
        Show     = { param($tab) Show-MemoryTab }
        OnAction = {
            param($item)
            if (-not $item.Data) { return }
            switch ($item.Data.Type) {
                'memtest' {
                    # die Speicherdiagnose gehört zu Windows: sie fragt selbst nach Adminrechten und danach,
                    # ob der Test sofort oder beim nächsten Start laufen soll - hier wird nichts ungefragt eingeplant
                    if ($Snapshot) { Set-SheetStateText 'Im Probelauf wird die Speicherdiagnose nicht gestartet'; return }
                    try {
                        Start-Process -FilePath (Join-Path $env:WINDIR 'System32\MdSched.exe')
                        Set-SheetStateText 'Windows fragt jetzt nach Adminrechten und danach, wann der Test laufen soll'
                    }
                    catch { Set-SheetStateText 'Die Speicherdiagnose wurde nicht gestartet' }
                }
                'url' { Open-WebLink $item.Data.Value }
            }
        }
        OnLink   = {
            $script:Sheet.Memory = $null
            $script:SheetWay = 0
            $ui.SheetChips.Children.Clear()
            Show-MemoryTab
            Start-Query 'Memory' { param($result) Complete-MemoryQuery $result }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese den Arbeitsspeicher …'
    Start-Query 'Memory' { param($result) Complete-MemoryQuery $result }
}

function Complete-MemoryQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Memory = $Result
    Set-CardState 'Memory' (Get-MemoryCardState $Result)
    $modules = @($Result.Modules)
    $installed = [double](($modules | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
    $ui.SheetChips.Children.Clear()
    if ($modules.Count -eq 0) {
        if ($Result.Total -gt 0) { Add-ResultChip ('{0:N0} GB' -f ($Result.Total / 1GB)) 'Accent' $ui.SheetChips }
        Add-ResultChip 'Riegel unbekannt' 'Ring2' $ui.SheetChips
        Show-MemoryTab
        return
    }
    Add-ResultChip ('{0:N0} GB' -f ($installed / 1GB)) 'Accent' $ui.SheetChips
    Add-ResultChip $(if ($modules.Count -eq 1) { '1 Riegel' } else { "$($modules.Count) Riegel" }) 'Ring2' $ui.SheetChips
    $first = $modules | Select-Object -First 1
    if ($first -and ($first.Type -or $first.Speed)) {
        Add-ResultChip ((@($first.Type, $(if ($first.Speed) { '{0:N0} MHz' -f $first.Speed })) | Where-Object { $_ }) -join ' · ') 'Ring1' $ui.SheetChips
    }
    Show-MemoryTab
}

# --- Arbeitsspeicher: Übersicht mit Bild der Steckplätze -------------------------

# Karte mit den Steckplätzen des Mainboards (die Zeilen kommen in "Slots") und darunter der Belegung
$memoryCardXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,0,8" Padding="18,13,18,11" CornerRadius="14" Background="#0AFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1">
    <StackPanel>
        <Grid Margin="0,0,0,8">
            <TextBlock Text="STECKPLÄTZE" FontSize="11" FontWeight="SemiBold" Foreground="#93A3C7"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <TextBlock x:Name="Verdict" FontSize="12" FontWeight="SemiBold" Margin="0,0,12,0"/>
                <TextBlock x:Name="Summary" FontSize="12" Foreground="#93A3C7"/>
            </StackPanel>
        </Grid>
        <UniformGrid x:Name="Slots" Columns="1"/>
        <Border Height="1" Background="#14FFFFFF" Margin="0,5,0,9"/>
        <Grid x:Name="Usage">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="UsageText" FontSize="12" Foreground="#E8EEFC" VerticalAlignment="Center"/>
            <Grid x:Name="UsageBar" Grid.Column="1" Height="8" Margin="16,0,14,0" VerticalAlignment="Center">
                <Border CornerRadius="4" Background="#14FFFFFF"/>
                <Border x:Name="UsageFill" CornerRadius="4" HorizontalAlignment="Left" Width="0"/>
            </Grid>
            <TextBlock x:Name="UsageShare" Grid.Column="2" FontSize="13" FontWeight="SemiBold" Foreground="#E8EEFC" VerticalAlignment="Center"/>
        </Grid>
    </StackPanel>
</Border>
'@

# Ein Steckplatz: Name, der Riegel als Bild (Platine, Bausteine, Kontaktleiste) oder ein leerer Rahmen, daneben die Angaben
$memorySlotXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Height="38" Margin="0,0,0,2">
    <Grid.ColumnDefinitions>
        <ColumnDefinition x:Name="NameColumn" Width="104"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition x:Name="InfoColumn" Width="250"/>
    </Grid.ColumnDefinitions>
    <StackPanel VerticalAlignment="Center">
        <TextBlock x:Name="Slot" FontSize="13" FontWeight="SemiBold" Foreground="#E8EEFC"/>
        <TextBlock x:Name="Bank" FontSize="11" Foreground="#93A3C7"/>
    </StackPanel>
    <Grid x:Name="Stick" Grid.Column="1" Height="36" VerticalAlignment="Center">
        <Rectangle x:Name="Empty" RadiusX="6" RadiusY="6" Stroke="#5E6E93" StrokeThickness="1.2" StrokeDashArray="4 3" Margin="0,2,0,2"/>
        <Grid x:Name="Full">
            <Border x:Name="Board" CornerRadius="6,6,2,2" Margin="0,0,0,5" BorderBrush="#22D3EE" BorderThickness="1">
                <Border.Background>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,0" Opacity="0.3">
                        <GradientStop Color="#22D3EE" Offset="0"/>
                        <GradientStop Color="#6366F1" Offset="1"/>
                    </LinearGradientBrush>
                </Border.Background>
            </Border>
            <UniformGrid x:Name="Chips" Rows="1" Margin="12,6,12,11"/>
            <Line X1="0" X2="1" Stretch="Fill" Stroke="#FDE047" StrokeThickness="4" StrokeDashArray="0.5 0.35" VerticalAlignment="Bottom" Margin="10,0,10,0" Opacity="0.85"/>
        </Grid>
    </Grid>
    <StackPanel Grid.Column="2" Margin="16,0,0,0" VerticalAlignment="Center">
        <TextBlock x:Name="Title" FontSize="13" FontWeight="SemiBold" Foreground="#E8EEFC"/>
        <TextBlock x:Name="Sub" FontSize="11" Foreground="#93A3C7"/>
    </StackPanel>
</Grid>
'@

# Der Takt, für den ein Riegel gebaut ist. Windows meldet oft nur den laufenden Takt; der volle steht bei den
# meisten Herstellern in der Typenbezeichnung (F4-3000C16, CMK16GX4M2B3200C16, KF432C16 ...).
function Get-MemoryRated($Module) {
    $rated = [int]$Module.Rated
    $part = "$($Module.Part)"
    $found = 0
    if ($part -match '(?<![0-9])([1-9][0-9]{3})H?CL?[0-9]{2}') { $found = [int]$Matches[1] }
    elseif ($part -match '^(?:KF|HX)[45]([0-9]{2})C[0-9]{2}') { $found = 100 * [int]$Matches[1] }
    elseif ($part -match '^BL[0-9]+G([0-9]{2})C[0-9]{2}') { $found = 100 * [int]$Matches[1] }
    if ($found -lt 1600 -or $found -gt 10000) { $found = 0 }
    @{ Speed = [Math]::Max($rated, $found); Known = ($found -gt 0 -or $rated -gt [int]$Module.Speed) }
}

# Urteil über den Takt: laufen die Riegel so schnell, wie sie können? Wenn nicht, fehlt meist das Speicherprofil im BIOS.
function Get-MemoryProfile($Modules) {
    $running = @($Modules | Where-Object { $_.Speed -gt 0 })
    if ($running.Count -eq 0) { return $null }
    $now = [int](($running | ForEach-Object { $_.Speed } | Measure-Object -Minimum).Minimum)
    $known = @($running | ForEach-Object { Get-MemoryRated $_ } | Where-Object { $_.Known })
    $rated = if ($known.Count -gt 0) { [int](($known | ForEach-Object { $_.Speed } | Measure-Object -Minimum).Minimum) } else { 0 }
    if ($rated -ge $now + 100) {
        return @{ Tone = 'Warn'; Badge = 'Profil prüfen'; Now = $now; Rated = $rated; Title = ('{0:N0} MHz – die Riegel können {1:N0} MHz' -f $now, $rated)
            Text = 'Im BIOS ist das Speicherprofil (XMP, bei AMD auch DOCP oder EXPO) nicht aktiv, oder der Takt ist dort von Hand niedriger gestellt. Nicht jedes Mainboard schafft den vollen Takt.' }
    }
    if ($rated -gt 0) {
        return @{ Tone = 'Good'; Badge = 'voller Takt'; Now = $now; Rated = $rated; Title = ('{0:N0} MHz – voller Takt der Riegel' -f $now)
            Text = 'Die Riegel laufen so schnell, wie sie gebaut sind. Am Speicherprofil im BIOS (XMP, DOCP oder EXPO) ist nichts zu tun.' }
    }
    @{ Tone = 'TextDim'; Badge = 'aktuell'; Now = $now; Rated = 0; Title = ('{0:N0} MHz' -f $now)
        Text = 'Für welchen Takt die Riegel gebaut sind, verrät Windows bei diesem Modell nicht. Steht auf ihrem Aufkleber mehr, im BIOS das Speicherprofil (XMP, DOCP oder EXPO) einschalten.' }
}

# Der Kanal eines Steckplatzes steht in seinem Namen ("CHANNEL A", "ChannelB-DIMM0", "DIMM_A1"); fehlt er, gibt es kein
# Urteil (leere Antwort). Intel-Boards ab der 12. Generation nennen beide Kanäle "ChannelA" und unterscheiden sie nur
# über den Speicher-Controller davor ("Controller0-ChannelA-DIMM1", "Controller1-ChannelA-DIMM1").
function Get-MemoryChannelKey([string]$Text) {
    if ($Text -match '(?i)controller\s*(\d+)\s*-?\s*channel\s*-?\s*([A-H])(?![A-Za-z])') { return "$($Matches[1])$($Matches[2].ToUpper())" }
    if ($Text -match '(?i)channel\s*-?\s*([A-H])(?![A-Za-z])' -or $Text -match '(?i)DIMM[_ ]?([A-H])[0-9]') { return $Matches[1].ToUpper() }
    ''
}

# In wie vielen Kanälen die Riegel stecken: auf zwei Kanäle verteilt (Dual-Channel) ist der Speicher deutlich schneller.
function Get-MemoryChannels($Modules, [int]$Slots) {
    $channels = @()
    foreach ($module in @($Modules)) {
        $channel = Get-MemoryChannelKey "$($module.Bank) $($module.Slot)"
        if ($channel) { $channels += $channel } else { return $null }
    }
    $count = @($channels | Sort-Object -Unique).Count
    if ($count -eq 0) { return $null }
    $name = switch ($count) { 1 { 'Single-Channel' } 2 { 'Dual-Channel' } 3 { 'Triple-Channel' } 4 { 'Quad-Channel' } default { "$count Kanäle" } }
    $hint = ''
    if ($count -eq 1 -and @($Modules).Count -gt 1) { $hint = 'Alle Riegel stecken im selben Kanal. Auf beide Kanäle verteilt (siehe Handbuch des Mainboards) wird der Speicher deutlich schneller.' }
    elseif ($count -eq 1 -and $Slots -gt 1) { $hint = 'Ein einzelner Riegel läuft im Single-Channel. Ein zweiter gleicher im anderen Kanal macht den Speicher deutlich schneller.' }
    @{ Name = $name; Hint = $hint }
}

# Stecken die Riegel in den richtigen Steckplätzen? Bei zwei Steckplätzen je Kanal verlangen fast alle Mainboards
# zuerst den zweiten (meist A2 und B2). Im ersten läuft der PC zwar, aber das Speicherprofil (XMP) scheitert oft.
# Ergebnis: State good/bad (leer = kein Urteil möglich), Wrong und Better als Stellen in der Reihenfolge der Steckplätze.
function Get-MemoryPlacement($Layout) {
    $result = @{ State = ''; Wrong = @(); Better = @(); Hint = '' }
    $places = @($Layout)
    $groups = [ordered]@{}
    for ($i = 0; $i -lt $places.Count; $i++) {
        $channel = Get-MemoryChannelKey "$($places[$i].Bank) $($places[$i].Slot)"
        if (-not $channel) { return $result }
        if (-not $groups.Contains($channel)) { $groups[$channel] = @() }
        $groups[$channel] += $i
    }
    # ein Urteil gibt es nur für den üblichen Aufbau: mindestens zwei Kanäle mit je zwei Steckplätzen
    if ($groups.Count -lt 2 -or @($groups.Keys | Where-Object { @($groups[$_]).Count -ne 2 }).Count -gt 0) { return $result }
    $filled = @{}
    foreach ($channel in $groups.Keys) { $filled[$channel] = @($groups[$channel] | Where-Object { $places[$_].Module -ge 0 }) }
    if (@($filled.Values | ForEach-Object { $_ }).Count -eq 0) { return $result }
    $first = $false; $crowded = $false
    $empty = @($groups.Keys | Where-Object { @($filled[$_]).Count -eq 0 })
    foreach ($channel in $groups.Keys) {
        $slots = @($groups[$channel]); $used = @($filled[$channel])
        if ($used.Count -eq 1 -and $used[0] -eq $slots[0]) {
            # ein Riegel im Kanal, aber im ersten Steckplatz statt im zweiten
            $result.Wrong += $slots[0]; $result.Better += $slots[1]; $first = $true
        }
        elseif ($used.Count -eq 2 -and $empty.Count -gt 0) {
            # zwei Riegel in einem Kanal, während ein anderer leer ist: einer gehört hinüber
            $target = $empty[0]; $empty = @($empty | Select-Object -Skip 1)
            $result.Wrong += $slots[0]; $result.Better += @($groups[$target])[1]; $crowded = $true
        }
    }
    if ($result.Wrong.Count -eq 0) { $result.State = 'good'; return $result }
    $result.State = 'bad'
    $hints = @()
    if ($first) { $hints += 'Die gelb markierten Riegel stecken im ersten Steckplatz ihres Kanals. Fast alle Mainboards wollen zuerst den zweiten (meist A2 und B2), sonst scheitert oft XMP.' }
    if ($crowded) { $hints += 'Zwei Riegel teilen sich einen Kanal, ein anderer ist leer: so läuft der Speicher nur im Single-Channel.' }
    $result.Hint = ($hints -join ' ') + ' PC ausschalten und wie markiert umstecken; im Zweifel gilt das Handbuch.'
    $result
}

# Reihenfolge der Steckplätze: aus dem BIOS, sonst die Riegel und dahinter die freien Plätze
function Get-MemoryLayout($Data) {
    $modules = @($Data.Modules)
    $layout = @($Data.Layout)
    if ($layout.Count -eq 0) {
        for ($i = 0; $i -lt $modules.Count; $i++) { $layout += @{ Slot = $modules[$i].Slot; Bank = $modules[$i].Bank; Module = $i } }
        for ($i = $modules.Count; $i -lt $Data.Slots; $i++) { $layout += @{ Slot = 'Steckplatz'; Bank = ''; Module = -1 } }
    }
    $layout
}

function Show-MemoryOverview($Data) {
    Show-SheetPanel
    $modules = @($Data.Modules)
    $layout = @(Get-MemoryLayout $Data)
    $channels = Get-MemoryChannels $modules $layout.Count

    $card = [Windows.Markup.XamlReader]::Parse((ConvertTo-ThemedXaml $memoryCardXaml))
    $summary = @(if ($modules.Count -eq 0) { 'Windows nennt auf diesem PC keine Riegel' } else { "$($modules.Count) von $([Math]::Max($layout.Count, $modules.Count)) belegt" })
    if ($channels) { $summary += $channels.Name }
    if ($Data.MaxBytes -gt 0) { $summary += 'Ausbau bis {0:N0} GB' -f ($Data.MaxBytes / 1GB) }
    $card.FindName('Summary').Text = T $($summary -join ' · ')
    $placement = Get-MemoryPlacement $layout
    $verdict = $card.FindName('Verdict')
    if ($placement.State -eq 'good') { $verdict.Text = T 'richtig gesteckt'; Set-Paint $verdict 'Foreground' 'Good' }
    elseif ($placement.State -eq 'bad') { $verdict.Text = T 'falsch gesteckt'; Set-Paint $verdict 'Foreground' 'Warn' }
    else { $verdict.Visibility = 'Collapsed' }
    $slots = $card.FindName('Slots')
    # mehr als vier Steckplätze: zwei Spalten, dafür schmaler und ohne die Typenbezeichnung
    $wide = $layout.Count -le 4
    if (-not $wide) { $slots.Columns = 2 }
    if ($script:Settings.Animations) {
        # die Karte kommt wie die Zeilen darunter: beim Öffnen von unten, beim Reiterwechsel von der Seite
        $card.Opacity = 0
        $card.RenderTransform = New-Object Windows.Media.TranslateTransform
        Start-Fade $card 1 300 50
        if ($script:SheetWay) { $card.RenderTransform.BeginAnimation($P.X, (New-DoubleAnim -From (20 * $script:SheetWay) -To 0 -Ms 440 -Delay 50)) }
        else { Start-Slide $card 0 440 50 12 }
    }
    [void]$ui.SheetPanel.Children.Add($card)

    $converter = New-Object Windows.Media.BrushConverter
    $chipBrush = $converter.ConvertFromString('#C0080E1C')
    $slotXaml = ConvertTo-ThemedXaml $memorySlotXaml
    $number = 0
    foreach ($place in $layout) {
        $row = [Windows.Markup.XamlReader]::Parse($slotXaml)
        if (-not $wide) {
            $row.FindName('NameColumn').Width = New-Object Windows.GridLength 70
            $row.FindName('InfoColumn').Width = New-Object Windows.GridLength 150
            $row.FindName('Sub').Visibility = 'Collapsed'
            $row.Margin = '0,0,14,2'
        }
        $row.FindName('Slot').Text = "$($place.Slot)"
        $bank = ("$($place.Bank)" -replace '^P\d+\s+', '') -replace '(?i)channel', 'Kanal'
        $row.FindName('Bank').Text = T $($bank)
        if (-not $bank) { $row.FindName('Bank').Visibility = 'Collapsed' }
        $module = if ($place.Module -ge 0 -and $place.Module -lt $modules.Count) { $modules[$place.Module] } else { $null }
        if ($module) {
            $row.FindName('Empty').Visibility = 'Collapsed'
            # acht Speicherbausteine auf der Platine
            $chips = $row.FindName('Chips')
            foreach ($i in 1..8) {
                $chip = New-Object Windows.Controls.Border
                $chip.CornerRadius = (Get-SkinRadius 2)
                $chip.Margin = '3,0,3,0'
                $chip.Background = $chipBrush
                [void]$chips.Children.Add($chip)
            }
            $size = (@(('{0:N0} GB' -f ($module.Bytes / 1GB)), $module.Type) | Where-Object { $_ }) -join ' '
            $clock = if ($module.Speed) { '{0:N0} MHz' -f $module.Speed } else { '' }
            $row.FindName('Title').Text = (@($size, $clock) | Where-Object { $_ }) -join ' · '
            $sub = (@($module.Maker, $module.Part) | Where-Object { $_ }) -join ' · '
            $row.FindName('Sub').Text = T $($sub)
            if (-not $sub) { $row.FindName('Sub').Visibility = 'Collapsed' }
            if ($placement.Wrong -contains $number) {
                # falscher Steckplatz: der Riegel bekommt einen gelben Rand und sagt es dazu
                Set-Paint $row.FindName('Board') 'BorderBrush' 'Warn'
                $row.FindName('Board').BorderThickness = 1.6
                $row.FindName('Sub').Text = T 'falscher Steckplatz'
                $row.FindName('Sub').Visibility = 'Visible'
                Set-Paint $row.FindName('Sub') 'Foreground' 'Warn'
            }
            # der Riegel schiebt sich von links in seinen Steckplatz
            $stick = $row.FindName('Full')
            $stick.RenderTransformOrigin = New-Object Windows.Point 0, 0.5
            $stick.RenderTransform = New-Object Windows.Media.ScaleTransform 0, 1
            $stick.RenderTransform.BeginAnimation($P.ScaleX, (New-DoubleAnim -To 1 -Ms 520 -Delay (180 + 90 * $number) -Ease $script:EaseOut))
        }
        else {
            $row.FindName('Full').Visibility = 'Collapsed'
            $row.FindName('Title').Text = T 'frei'
            Set-Paint $row.FindName('Title') 'Foreground' 'TextDim'
            $row.FindName('Sub').Visibility = 'Collapsed'
            if ($placement.Better -contains $number) {
                # hier gehört ein falsch gesteckter Riegel hin
                $row.FindName('Title').Text = T 'frei – hierhin umstecken'
                Set-Paint $row.FindName('Title') 'Foreground' 'Accent'
                Set-Paint $row.FindName('Empty') 'Stroke' 'Accent'
                $row.FindName('Empty').StrokeThickness = 1.6
            }
        }
        [void]$slots.Children.Add($row)
        $number++
    }

    # Belegung als Balken am Fuß der Karte; er füllt sich, sobald seine Breite feststeht
    if ($Data.Total -gt 0) {
        $used = [Math]::Max(0.0, [Math]::Min(1.0, 1 - $Data.Free / $Data.Total))
        $card.FindName('UsageText').Text = T $('{0:N1} GB belegt von {1:N1} GB' -f (($Data.Total - $Data.Free) / 1GB), ($Data.Total / 1GB))
        $card.FindName('UsageShare').Text = '{0:N0} %' -f ($used * 100)
        Set-Paint $card.FindName('UsageFill') 'Background' 'AccentGrad'
        $bar = $card.FindName('UsageBar')
        $bar.Tag = $used
        $bar.Add_Loaded({
                try { $this.Children[1].BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-DoubleAnim -To ($this.ActualWidth * [double]$this.Tag) -Ms 700 -Delay 320 -Ease $script:EaseOut)) }
                catch { Write-AppError $_ }
            })
    }
    else { $card.FindName('Usage').Visibility = 'Collapsed' }

    # Hinweise zum Aufbau in einer Zeile: falscher Kanal, gemischte Riegel
    $hints = @()
    if ($placement.Hint) { $hints += $placement.Hint }
    elseif ($channels -and $channels.Hint) { $hints += $channels.Hint }
    $kinds = @($modules | ForEach-Object { "$($_.Bytes)|$($_.Speed)|$($_.Part)" } | Sort-Object -Unique)
    if ($kinds.Count -gt 1) { $hints += 'Die Riegel sind unterschiedlich: Gemischte laufen nur so schnell wie der langsamste und führen öfter zu Abstürzen.' }
    if ($hints.Count -gt 0) {
        $slot = Add-SettingRow $(if ($placement.State -eq 'bad') { 'Falsch gesteckt' } else { 'Aufbau prüfen' }) ($hints -join ' ') 0xE7BA
        $slot.Visibility = 'Collapsed'
        Set-Paint $slot.Parent.Parent.FindName('Glyph') 'Foreground' 'Warn'
    }
    # aktueller Takt und ob die Riegel damit ausgereizt sind
    $profile = Get-MemoryProfile $modules
    if ($profile) {
        # bei falsch gesteckten Riegeln zählt zuerst das Umstecken: die Zeile zum Takt bleibt dann kurz
        $text = if ($placement.State -eq 'bad' -and $profile.Tone -eq 'Warn') { 'Erst umstecken, dann im BIOS das Speicherprofil (XMP, DOCP oder EXPO) einschalten.' } else { $profile.Text }
        $slot = Add-SettingRow $profile.Title $text 0xE916
        $badge = New-Object Windows.Controls.Border
        $badge.CornerRadius = (Get-SkinRadius 8)
        $badge.Padding = '9,3,9,3'
        $badge.Background = $converter.ConvertFromString('#14FFFFFF')
        $badge.Child = New-Object Windows.Controls.TextBlock
        $badge.Child.Text = T $($profile.Badge)
        $badge.Child.FontSize = 11
        $badge.Child.FontWeight = 'SemiBold'
        Set-Paint $badge.Child 'Foreground' $profile.Tone
        [void]$slot.Children.Add($badge)
        if ($profile.Tone -eq 'Warn') { Set-Paint $slot.Parent.Parent.FindName('Glyph') 'Foreground' 'Warn' }
    }

    Set-SheetStateText "Stand: $($Data.Time) Uhr"
}

function Show-MemoryTab {
    $data = $script:Sheet.Memory
    if (-not $data) {
        Start-SheetLoader 'Lese den Arbeitsspeicher …'
        return
    }
    $modules = @($data.Modules)
    $rows = @()
    if ($script:Sheet.Tab -eq 0) {
        Show-MemoryOverview $data
        return
    }

    $rows += New-SheetRow -Kind 'head' -Title 'SPEICHERTEST VON WINDOWS'
    $rows += New-SheetRow -Title 'Test beim Neustart' -Sub 'Windows prüft den Speicher vor dem Hochfahren. Das dauert je nach Größe 15 bis 40 Minuten.' `
        -Glyph 0xE777 -Tone 'accent' -Action 'Test einplanen' -Data @{ Type = 'memtest' }
    if ($data.Test) {
        $rows += New-SheetRow -Title 'Letztes Ergebnis' -Sub "$($data.Test.Time) Uhr · $(if ($data.Test.Ok) { 'keine Fehler gefunden' } else { 'Windows hat Speicherfehler gefunden' })" `
            -Glyph $(if ($data.Test.Ok) { 0xE73E } else { 0xE783 }) -State $(if ($data.Test.Ok) { 'in Ordnung' } else { 'Fehler' }) -Tone $(if ($data.Test.Ok) { 'good' } else { 'bad' })
    }
    elseif ($false -eq $data.Log) { $rows += New-SheetRow -Title 'Letztes Ergebnis' -Sub 'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus' -Glyph 0xE9CE }
    else { $rows += New-SheetRow -Title 'Letztes Ergebnis' -Sub 'Im Protokoll von Windows steht noch kein Speichertest' -Glyph 0xE9CE }

    $rows += New-SheetRow -Kind 'head' -Title 'IM LAUFENDEN BETRIEB'
    if ($data.Hardware -gt 0) {
        $rows += New-SheetRow -Title $(if ($data.Hardware -eq 1) { '1 Hardwarefehler in 90 Tagen' } else { "$($data.Hardware) Hardwarefehler in 90 Tagen" }) `
            -Sub "Von Prozessor, Speicher oder Mainboard gemeldet, zuletzt $($data.LastHardware) Uhr. Ein Speichertest ist ratsam." -Glyph 0xE7BA -State 'auffällig' -Tone 'warn'
    }
    elseif ($false -eq $data.Log) { $rows += New-SheetRow -Title 'Hardwarefehler sind nicht lesbar' -Sub 'Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus' -Glyph 0xE946 }
    else { $rows += New-SheetRow -Title 'Keine Hardwarefehler in 90 Tagen' -Sub 'Prozessor, Speicher und Mainboard haben Windows nichts gemeldet' -Glyph 0xE73E -State 'in Ordnung' -Tone 'good' }

    $rows += New-SheetRow -Kind 'head' -Title 'GRÜNDLICHER TEST VOM USB-STICK'
    $rows += New-SheetRow -Title 'Memtest86+' -Sub 'Startet vom USB-Stick und prüft länger und strenger als der Test von Windows. Kostenlos.' `
        -Glyph 0xE88E -Tone 'accent' -Action 'Seite öffnen' -Data @{ Type = 'url'; Value = 'https://www.memtest.org/' }
    Show-SheetList $rows
    Set-SheetStateText 'Bei Abstürzen oder Bluescreens zuerst den Test von Windows, bei Verdacht danach den vom USB-Stick'
}

# --- Sensoren ------------------------------------------------------------------
# Ein eigener kleiner Arbeitsbereich misst jede Sekunde; das Fenster zeichnet nur. Die Werte der Grafikkarte
# kommen vom NVIDIA-Werkzeug nvidia-smi (ein Prozess, der im Sekundentakt Zeilen liefert), Auslastung und Takt
# des Prozessors aus den Leistungszählern von Windows. Die Temperatur des Prozessors gibt Windows nicht her: Sie
# kommt aus PulsRig-Temperatur.cs, sobald der Treiber PawnIO installiert ist (sonst steht ein Hinweis im Fenster).

$sensorCode = @'
param($id)
$process = $null
try {
    $exe = Join-Path $env:WINDIR 'System32\nvidia-smi.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $found = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        $exe = if ($found) { $found.Source } else { '' }
    }
    if ($exe) {
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $exe
        # -i 0: bei mehreren NVIDIA-Karten käme sonst je Karte eine Zeile und die Werte sprängen hin und her
        $start.Arguments = '-i 0 --query-gpu=name,temperature.gpu,fan.speed,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits -l 1'
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::Start($start)
        $sync.SensorPid = $process.Id
    }
}
catch { $process = $null }

$load = $null; $performance = $null
foreach ($name in @('Processor Information', '% Processor Utility'), @('Processor', '% Processor Time')) {
    try { $load = New-Object Diagnostics.PerformanceCounter $name[0], $name[1], '_Total'; [void]$load.NextValue(); break } catch { $load = $null }
}
try { $performance = New-Object Diagnostics.PerformanceCounter 'Processor Information', '% Processor Performance', '_Total'; [void]$performance.NextValue() } catch { $performance = $null }
$baseMhz = 0.0
try { $baseMhz = [double](Get-CimInstance Win32_Processor | Select-Object -First 1).MaxClockSpeed } catch { }
# Arbeitsspeicher: die Gesamtgröße einmal lesen, den freien Rest danach aus einem Leistungszähler - das kostet
# im Sekundentakt viel weniger als jedes Mal eine Abfrage an Windows
$available = $null; $totalMb = 0.0
try {
    $totalMb = [double](Get-CimInstance Win32_OperatingSystem -Property TotalVisibleMemorySize).TotalVisibleMemorySize / 1024.0
    $available = New-Object Diagnostics.PerformanceCounter 'Memory', 'Available MBytes'
    [void]$available.NextValue()
}
catch { $available = $null }

$number = { param($text) $value = 0.0; if ([double]::TryParse("$text".Trim(), [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$value)) { $value } else { $null } }
$stamp = 0
try {
    while ($sync.SensorId -eq $id) {
        $values = @{}
        if ($process -and -not $process.HasExited) {
            # die Zeile des NVIDIA-Werkzeugs gibt zugleich den Sekundentakt vor
            $line = $process.StandardOutput.ReadLine()
            $parts = @("$line" -split ',')
            if ($parts.Count -ge 7) {
                $values.GpuName = $parts[0].Trim()
                $values.GpuTemp = & $number $parts[1]
                $values.GpuFan = & $number $parts[2]
                $values.GpuLoad = & $number $parts[3]
                $values.GpuMemory = & $number $parts[4]
                $values.GpuMemoryTotal = & $number $parts[5]
                $values.GpuPower = & $number $parts[6]
            }
        }
        else { Start-Sleep -Milliseconds 1000 }
        try { if ($load) { $values.CpuLoad = [Math]::Min(100.0, [double]$load.NextValue()) } } catch { }
        try { if ($performance -and $baseMhz -gt 0) { $values.CpuClock = $baseMhz * [double]$performance.NextValue() / 100.0 / 1000.0 } } catch { }
        try { if ($available -and $totalMb -gt 0) { $values.Ram = [Math]::Max(0.0, 100.0 * (1.0 - [double]$available.NextValue() / $totalMb)) } } catch { }
        # Temperatur des Prozessors (PulsRig-Temperatur.cs); im Probelauf ein gestellter Wert
        if ($sync.CpuTempDemo) { $values.CpuTemp = [double]$sync.CpuTempDemo + (Get-Random -Minimum -2 -Maximum 3); $values.CpuPower = 60.0 + (Get-Random -Maximum 9) }
        elseif ($sync.CpuTempReady) {
            try {
                $temp = [PulsRigCpuTemp]::Read()
                if (-not [double]::IsNaN($temp)) { $values.CpuTemp = $temp }
                $power = [PulsRigCpuTemp]::Power
                if (-not [double]::IsNaN($power)) { $values.CpuPower = $power }
            }
            catch { }
        }
        $stamp++
        $values.Stamp = $stamp
        $sync.Sensors = $values
    }
}
finally {
    if ($process) { try { if (-not $process.HasExited) { $process.Kill() } } catch { } }
}
'@

$script:SensorRun = $null
$script:SensorTiles = @{}      # die Kacheln des Fensters, nach dem Schlüssel ihres Messwerts

function Stop-Sensors {
    if (-not $script:SensorRun) { return }
    # die Messschleife endet nach ihrem nächsten Takt; den NVIDIA-Prozess gleich beenden, damit er nicht verwaist
    $sync.SensorId = [int]$sync.SensorId + 1
    $script:SensorRun.Timer.Stop()
    if ($sync.SensorPid) {
        try {
            $child = Get-Process -Id ([int]$sync.SensorPid) -ErrorAction Stop
            if ($child.ProcessName -eq 'nvidia-smi') { $child.Kill() }
        }
        catch { }
        $sync.SensorPid = 0
    }
    $run = $script:SensorRun
    $script:SensorRun = $null
    Invoke-Later 2500 { param($old) try { $old.Ps.Dispose(); $old.Space.Dispose() } catch { } } $run
}

function Start-Sensors {
    if ($script:SensorRun) { return }
    $sync.SensorId = [int]$sync.SensorId + 1
    $sync.Sensors = $null
    $sync.SensorPid = 0
    $space = [runspacefactory]::CreateRunspace()
    $space.Open()
    $space.SessionStateProxy.SetVariable('sync', $sync)
    # nur im Probelauf auf einem vorgetäuschten System (PulsRig-Fremdsystem.ps1): auch die Messung sieht dieses System
    if ($script:ForeignCode) { $first = [powershell]::Create(); $first.Runspace = $space; [void]$first.AddScript($script:ForeignCode).Invoke(); $first.Dispose() }
    $ps = [powershell]::Create()
    $ps.Runspace = $space
    [void]$ps.AddScript($sensorCode).AddArgument($sync.SensorId)
    [void]$ps.BeginInvoke()
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({ try { Update-SensorTiles } catch { Write-AppError $_ } })
    $timer.Start()
    $script:SensorRun = @{ Space = $space; Ps = $ps; Timer = $timer; Stamp = 0 }
}

# Kachel für einen Messwert: Symbol und Name, großer Wert, kleinster und größter Wert, Verlaufskurve.
# #22D3EE steht für die Farbe der Kachel und wird je Kachel ersetzt.
$sensorTileXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Margin="0,0,8,8" Padding="14,12,14,10" CornerRadius="14" Background="#0AFFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Height="146">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Horizontal">
            <Grid x:Name="Icon" Width="26" Height="26" Margin="0,0,9,0" RenderTransformOrigin="0.5,0.5">
                <Grid.RenderTransform>
                    <ScaleTransform/>
                </Grid.RenderTransform>
                <Border CornerRadius="8" Background="#2422D3EE"/>
                <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="12.5" Foreground="#22D3EE" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <TextBlock x:Name="Label" FontSize="12" Foreground="#93A3C7" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,5,0,0">
            <TextBlock x:Name="Value" Text="–" FontSize="24" FontWeight="SemiBold" Foreground="#E8EEFC"/>
            <TextBlock x:Name="Unit" FontSize="13" Foreground="#93A3C7" VerticalAlignment="Bottom" Margin="5,0,0,4"/>
        </StackPanel>
        <TextBlock x:Name="Range" Grid.Row="2" FontSize="11" Foreground="#5E6E93" Margin="0,1,0,0"/>
        <Grid x:Name="Area" Grid.Row="3" Margin="0,6,0,0" ClipToBounds="True">
            <Canvas>
            <Path x:Name="Fill" Opacity="0.2" Fill="#22D3EE"/>
            <Path x:Name="Line" Stroke="#22D3EE" StrokeThickness="1.6" StrokeLineJoin="Round"/>
            </Canvas>
        </Grid>
    </Grid>
</Border>
'@

# Die Messwerte: Schlüssel im Ergebnis der Messschleife, Name, Einheit, Symbol, Zahlenformat, Spanne der Kurve
# und ab wann der Wert gelb oder rot wird. Top = 0: die Kurve richtet sich nach dem höchsten gesehenen Wert.
$script:SensorSpecs = @(
    @{ Key = 'GpuTemp'; Label = 'Grafikkarte · Temperatur'; Unit = '°C'; Glyph = 0xE706; Format = '{0:N0}'; Low = 20; Top = 100; Warn = 80; Bad = 90; Gpu = $true },
    @{ Key = 'GpuLoad'; Label = 'Grafikkarte · Auslastung'; Unit = '%'; Glyph = 0xEC4A; Format = '{0:N0}'; Low = 0; Top = 100; Gpu = $true },
    @{ Key = 'GpuFan'; Label = 'Grafikkarte · Lüfter'; Unit = '%'; Glyph = 0xE9F5; Format = '{0:N0}'; Low = 0; Top = 100; Gpu = $true },
    @{ Key = 'GpuMemory'; Label = 'Grafikspeicher belegt'; Unit = 'GB'; Glyph = 0xE9D9; Format = '{0:N1}'; Low = 0; Top = 0; Scale = 1 / 1024; TopKey = 'GpuMemoryTotal'; Gpu = $true },
    @{ Key = 'GpuPower'; Label = 'Grafikkarte · Leistung'; Unit = 'W'; Glyph = 0xE945; Format = '{0:N0}'; Low = 0; Top = 0; Gpu = $true },
    @{ Key = 'CpuTemp'; Label = 'Prozessor · Temperatur'; Unit = '°C'; Glyph = 0xE706; Format = '{0:N0}'; Low = 20; Top = 100; Warn = 85; Bad = 95 },
    @{ Key = 'CpuPower'; Label = 'Prozessor · Leistung'; Unit = 'W'; Glyph = 0xE945; Format = '{0:N0}'; Low = 0; Top = 0 },
    @{ Key = 'CpuLoad'; Label = 'Prozessor · Auslastung'; Unit = '%'; Glyph = 0xE950; Format = '{0:N0}'; Low = 0; Top = 100 },
    @{ Key = 'CpuClock'; Label = 'Prozessor · Takt'; Unit = 'GHz'; Glyph = 0xE916; Format = '{0:N2}'; Low = 0; Top = 0 },
    @{ Key = 'Ram'; Label = 'Arbeitsspeicher belegt'; Unit = '%'; Glyph = 0xE8FD; Format = '{0:N0}'; Low = 0; Top = 100; Warn = 85; Bad = 95 }
)

# Reiter 0: live im Sekundentakt; Reiter 1: aufgezeichnete Spielsitzungen (PulsRig-Aufzeichnung.ps1)
function Open-SensorSheet([int]$Tab = 0) {
    Initialize-CpuTemp
    $opened = Open-Sheet @{
        Title   = 'Sensoren'
        Sub     = 'Temperaturen, Lüfter und Auslastung im Sekundentakt – und beim Spielen aufgezeichnet'
        Glyph   = 0xE9D9
        Tabs    = 'Live', 'Spielsitzungen', 'Verschleiß'
        Show    = { param($tab) switch ([int]$script:Sheet.Tab) { 1 { Show-RecordingTab } 2 { Show-WearTab } default { Show-SensorPanel } } }
        OnClose = { Stop-Sensors }
    }
    if (-not $opened) { return }
    if ($Tab -gt 0) { Select-SheetTab $Tab }
    Start-Sensors
}

# Gibt es die Temperatur des Prozessors, steht der Prozessor vorn und alle zehn Kacheln passen etwas flacher
# ohne Scrollen ins Fenster; sonst acht Kacheln und darunter der Hinweis mit dem Knopf zum Freischalten.
$script:SensorKeysFull = 'CpuTemp', 'CpuLoad', 'CpuClock', 'CpuPower', 'GpuTemp', 'GpuLoad', 'GpuFan', 'GpuPower', 'GpuMemory', 'Ram'
$script:SensorKeysBasic = 'GpuTemp', 'GpuLoad', 'GpuFan', 'GpuMemory', 'GpuPower', 'CpuLoad', 'CpuClock', 'Ram'

function Show-SensorPanel {
    Show-SheetPanel
    if ($script:CpuTempSeen) {
        # über Core Temp gibt es keine Leistung des Prozessors: dann ohne diese Kachel
        $keys = $script:SensorKeysFull
        if (-not $sync.CpuTempDemo -and "$([PulsRigCpuTemp]::Source)" -eq 'Core Temp') { $keys = @($keys | Where-Object { $_ -ne 'CpuPower' }) }
        New-SensorGrid $keys -Height 116
        $ui.SheetState.Text = T $('Warte auf die ersten Messwerte …')
        return
    }
    New-SensorGrid $script:SensorKeysBasic -Height 132
    Add-CpuTempHint
    $ui.SheetState.Text = T $('Warte auf die ersten Messwerte …')
}

# Baut die Kacheln der Messwerte in die freie Fläche des großen Dialogs; mit $Keys nur die genannten
function New-SensorGrid([string[]]$Keys, [int]$Height = 0) {
    $grid = New-Object Windows.Controls.Primitives.UniformGrid
    $grid.Columns = 4
    $grid.Margin = '0,0,-8,0'
    $grid.VerticalAlignment = 'Top'
    [void]$ui.SheetPanel.Children.Add($grid)
    $tiles = @{}
    $index = 0
    # mit $Keys in deren Reihenfolge
    $specs = if ($Keys) { @($Keys | ForEach-Object { $key = $_; $script:SensorSpecs | Where-Object { $_.Key -eq $key } }) } else { $script:SensorSpecs }
    foreach ($spec in $specs) {
        $color = $script:ToolColors[$index % $script:ToolColors.Count]
        $xaml = $sensorTileXaml.Replace('#2422D3EE', '#24' + $color.Substring(1)).Replace('#22D3EE', $color)
        $tile = [Windows.Markup.XamlReader]::Parse((ConvertTo-ThemedXaml $xaml))
        if ($Height -gt 0) { $tile.Height = $Height }
        $tile.FindName('Glyph').Text = Get-Glyph $spec.Glyph
        $tile.FindName('Label').Text = T $($spec.Label)
        $tile.FindName('Unit').Text = $spec.Unit
        [void]$grid.Children.Add($tile)
        # die Kacheln springen der Reihe nach auf, das Symbol federt nach
        $tile.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
        $tile.RenderTransform = New-Object Windows.Media.ScaleTransform
        Start-Pop $tile (80 + 55 * $index) 0.9
        Start-Scale $tile.FindName('Icon') 1 650 (80 + 55 * $index) 0.5 $script:EaseElastic
        # die Teile der Kachel einmal heraussuchen, nicht bei jedem Messwert neu
        $tiles[$spec.Key] = @{ Tile = $tile; Spec = $spec; History = (New-Object 'System.Collections.Generic.List[double]'); Min = $null; Max = $null; Seen = 0.0
            Value = $tile.FindName('Value'); Range = $tile.FindName('Range'); Area = $tile.FindName('Area'); Line = $tile.FindName('Line'); Fill = $tile.FindName('Fill'); Tone = 'Text' }
        $index++
    }
    $script:SensorTiles = $tiles
    if ($script:SensorRun) { $script:SensorRun.Stamp = 0 }
}

# Trägt neue Messwerte in die Kacheln ein: Zahl, kleinster und größter Wert, Kurve der letzten 60 Sekunden
function Update-SensorTiles {
    $run = $script:SensorRun
    $values = $sync.Sensors
    if (-not $run -or -not $values -or $values.Stamp -eq $run.Stamp) { return }
    $run.Stamp = $values.Stamp
    $culture = [cultureinfo]::InvariantCulture
    foreach ($key in @($script:SensorTiles.Keys)) {
        $entry = $script:SensorTiles[$key]
        $spec = $entry.Spec
        $tile = $entry.Tile
        $raw = $values[$key]
        if ($null -eq $raw) {
            # kein Wert: ohne NVIDIA-Grafikkarte bleiben deren Kacheln leer
            if ($entry.History.Count -eq 0) { $entry.Range.Text = T 'nicht verfügbar'; $tile.Opacity = 0.55 }
            continue
        }
        $value = [double]$raw * $(if ($spec.Scale) { $spec.Scale } else { 1 })
        $tile.Opacity = 1
        $entry.Value.Text = $spec.Format -f $value
        if ($null -eq $entry.Min -or $value -lt $entry.Min) { $entry.Min = $value }
        if ($null -eq $entry.Max -or $value -gt $entry.Max) { $entry.Max = $value }
        $entry.Range.Text = T $("min $($spec.Format -f $entry.Min) · max $($spec.Format -f $entry.Max)")
        # die Zahl färbt sich, wenn der Wert in einen kritischen Bereich kommt
        $tone = if ($spec.Bad -and $value -ge $spec.Bad) { 'Bad' } elseif ($spec.Warn -and $value -ge $spec.Warn) { 'Warn' } else { 'Text' }
        if ($tone -ne $entry.Tone) { $entry.Tone = $tone; Set-Paint $entry.Value 'Foreground' $tone }

        $history = $entry.History
        $history.Add($value)
        while ($history.Count -gt 61) { $history.RemoveAt(0) }
        $top = [double]$spec.Top
        if ($spec.TopKey -and $values[$spec.TopKey]) { $top = [double]$values[$spec.TopKey] * $(if ($spec.Scale) { $spec.Scale } else { 1 }) }
        if ($top -le 0) {
            if ($value -gt $entry.Seen) { $entry.Seen = $value }
            $top = [Math]::Max(1.0, $entry.Seen * 1.15)
        }
        $low = [double]$spec.Low
        $area = $entry.Area
        $width = $area.ActualWidth; $height = $area.ActualHeight
        if ($width -lt 20 -or $height -lt 10) { continue }
        $step = $width / 60.0
        $points = New-Object Text.StringBuilder
        $firstX = 0.0
        for ($i = 0; $i -lt $history.Count; $i++) {
            $x = $width - ($history.Count - 1 - $i) * $step
            $share = [Math]::Max(0.0, [Math]::Min(1.0, ($history[$i] - $low) / ($top - $low)))
            $y = $height - 2.0 - $share * ($height - 4.0)
            if ($i -eq 0) { $firstX = $x }
            [void]$points.Append([string]::Format($culture, '{0}{1:0.##},{2:0.##} ', $(if ($i -eq 0) { 'M ' } else { 'L ' }), $x, $y))
        }
        $line = $points.ToString()
        if ($history.Count -gt 1) {
            $entry.Line.Data = [Windows.Media.Geometry]::Parse($line)
            $entry.Fill.Data =[Windows.Media.Geometry]::Parse($line + [string]::Format($culture, 'L {0:0.##},{1:0.##} L {2:0.##},{1:0.##} Z', $width, $height, $firstX))
        }
    }
    # die Fußzeile gehört nur im Fenster "Sensoren" den Messwerten; der Stabilitätstest schreibt dort selbst
    if ($script:Sheet -and ($script:Sheet.Title -ne 'Sensoren' -or [int]$script:Sheet.Tab -ne 0)) { return }
    $ui.SheetState.Text = T $($(if ($values.GpuName) { "$($values.GpuName) · " } else { 'Keine NVIDIA-Grafikkarte gefunden · ' }) + 'Kurven: letzte 60 Sekunden')
}

# --- Stabilitätstest -----------------------------------------------------------
# Die Last selbst steckt in PulsRig-Last.cs (wird beim ersten Start übersetzt): Rechenproben mit bekanntem Ergebnis
# auf allen Kernen und ein Fenster, das die Grafikkarte auslastet. Hier: Auswahl, Ablauf, Überwachung, Ergebnis.
# Der Test endet von selbst bei Rechenfehlern, bei 90 °C an der Grafikkarte, wenn der Prozessor seinen Takt
# drosselt (er schützt sich so vor Überhitzung) oder wenn die Zeit um ist.

$script:Stress = $null             # der laufende Test
$script:StressWhat = 'both'        # 'cpu', 'gpu' oder 'both'
$script:StressMinutes = 5
$script:StressResult = $null       # letztes Ergebnis, auch für den Prüfbericht
$script:StressRow = $null          # die Zeile mit Stand und Ergebnis

function Format-StressTime([double]$Seconds) {
    '{0}:{1:00}' -f [int][Math]::Floor($Seconds / 60), [int]([Math]::Floor($Seconds) % 60)
}

function Open-StressSheet {
    Initialize-CpuTemp
    $opened = Open-Sheet @{
        Title     = 'Stabilitätstest'
        Sub       = 'Prozessor und Grafikkarte unter Volllast prüfen'
        Glyph     = 0xEC4A
        Primary   = 'Test starten'
        Show      = { param($tab) Show-StressPanel }
        OnPrimary = { if ($script:Stress) { Stop-Stress 'Gestoppt' 'warn' 'Der Test wurde von Hand beendet.' } else { Start-Stress } }
        OnClose   = {
            if ($script:Stress) { Stop-Stress 'Gestoppt' 'warn' 'Das Fenster wurde geschlossen.' }
            Stop-Sensors
        }
    }
    if (-not $opened) { return }
    Start-Sensors
}

function Set-StressRow([string]$Title, [string]$Text, [string]$Tone = 'accent') {
    $Title = T $Title; $Text = T $Text
    $row = $script:StressRow
    if (-not $row) { return }
    $row.FindName('Title').Text = $Title
    $row.FindName('Text').Text = $Text
    $key = switch ($Tone) { 'good' { 'Good' } 'warn' { 'Warn' } 'bad' { 'Bad' } default { 'Accent' } }
    $glyph = switch ($Tone) { 'good' { 0xE73E } 'warn' { 0xE7BA } 'bad' { 0xE783 } 'run' { 0xE768 } default { 0xE946 } }
    $row.FindName('Glyph').Text = Get-Glyph $glyph
    Set-Paint $row.FindName('Glyph') 'Foreground' $key
}

function Show-StressPanel {
    Show-SheetPanel
    $slot = Add-SettingRow 'Was belasten?' 'Beides zusammen fordert auch das Netzteil am stärksten.' 0xE950
    foreach ($choice in @('cpu', 'Prozessor'), @('gpu', 'Grafikkarte'), @('both', 'Beides')) {
        $chip = New-SettingChip $choice[1] $choice[0]
        $chip.Add_Click({
                try {
                    if ($script:Stress) { return }
                    $script:StressWhat = $this.Uid
                    Update-SettingChips $this.Parent $this.Uid
                }
                catch { Write-AppError $_ }
            })
        [void]$slot.Children.Add($chip)
    }
    Update-SettingChips $slot $script:StressWhat
    $slot = Add-SettingRow 'Wie lange?' 'Eine Minute zeigt grobe Fehler, 15 Minuten auch Hitzeprobleme.' 0xE916
    foreach ($minutes in 1, 5, 15) {
        $chip = New-SettingChip $(if ($minutes -eq 1) { '1 Minute' } else { "$minutes Minuten" }) "$minutes"
        $chip.Add_Click({
                try {
                    if ($script:Stress) { return }
                    $script:StressMinutes = [int]$this.Uid
                    Update-SettingChips $this.Parent $this.Uid
                }
                catch { Write-AppError $_ }
            })
        [void]$slot.Children.Add($chip)
    }
    Update-SettingChips $slot "$($script:StressMinutes)"
    # unter Volllast ist die Auslastung des Prozessors ohnehin 100 %: gibt es seine Temperatur, steht sie an ihrer Stelle
    if ($script:CpuTempSeen) {
        New-SensorGrid 'CpuTemp', 'CpuClock', 'GpuTemp', 'GpuLoad'
        $slot = Add-SettingRow 'Bereit' 'Der Test endet von selbst: bei Rechenfehlern, bei 90 °C an der Grafikkarte, 98 °C am Prozessor oder wenn der Prozessor seinen Takt drosselt. Laut und warm ist dabei normal.' 0xE946
    }
    else {
        New-SensorGrid 'CpuLoad', 'CpuClock', 'GpuTemp', 'GpuLoad'
        $slot = Add-SettingRow 'Bereit' 'Der Test endet von selbst: bei Rechenfehlern, bei 90 °C an der Grafikkarte oder wenn der Prozessor seinen Takt drosselt. Laut und warm ist dabei normal.' 0xE946
    }
    $script:StressRow = $slot.Parent.Parent
    if ($script:StressResult) { Set-StressRow $script:StressResult.Title $script:StressResult.Text $script:StressResult.Tone }
    $ui.SheetState.Text = T $('Vorher speichern, was offen ist: Ein instabiler PC kann beim Test abstürzen')
}

function Start-Stress([int]$Seconds = 0) {
    if ($script:Stress -or -not $script:Sheet) { return }
    if (-not ('PulsRigStress' -as [type])) {
        Add-Type -TypeDefinition (Get-AppText 'PulsRig-Last.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
    }
    $what = $script:StressWhat
    if ($Seconds -le 0) { $Seconds = 60 * $script:StressMinutes }
    if ($what -in 'cpu', 'both') { [PulsRigStress]::StartCpu([Environment]::ProcessorCount) }
    if ($what -in 'gpu', 'both') { [PulsRigStress]::StartGpu('PulsRig – Grafiklast (Schließen beendet den Test)') }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({ try { Update-Stress } catch { Write-AppError $_ } })
    $script:Stress = @{ What = $what; Seconds = $Seconds; Start = [DateTime]::UtcNow; Timer = $timer; Stamp = 0
        BaseClock = 0.0; LowClock = 0; MaxGpuTemp = 0.0; MaxCpuTemp = 0.0; MaxClock = 0.0; Seen = [DateTime]::UtcNow; HadTemp = $false }
    # ein langer Lauf darf nicht daran scheitern, dass Windows den PC schlafen legt
    try { [PulsRigStress]::KeepAwake($true) } catch { }
    $ui.BtnSheetPrimary.Content = T $('Stoppen')
    Set-StressRow 'Läuft …' 'Die Last fährt hoch.' 'run'
    $timer.Start()
}

# Überwacht den laufenden Test und beendet ihn, sobald etwas auffällt oder die Zeit um ist
function Update-Stress {
    $stress = $script:Stress
    if (-not $stress) { return }
    $elapsed = ([DateTime]::UtcNow - $stress.Start).TotalSeconds
    $values = $sync.Sensors
    $cpu = $stress.What -in 'cpu', 'both'
    $gpu = $stress.What -in 'gpu', 'both'
    $samples = [PulsRigStress]::Iterations

    if ([PulsRigStress]::Errors -gt 0) {
        Stop-Stress 'Rechenfehler' 'bad' "Der Prozessor hat sich $([PulsRigStress]::Errors)-mal verrechnet. Das deutet auf Übertaktung, zu wenig Spannung, Hitze oder defekten Arbeitsspeicher."
        return
    }
    if ($gpu -and [PulsRigStress]::GpuError) {
        Stop-Stress 'Grafiklast nicht möglich' 'warn' "Die Grafikkarte ließ sich nicht belasten: $([PulsRigStress]::GpuError)"
        return
    }
    if ($gpu -and $elapsed -gt 6 -and -not [PulsRigStress]::GpuActive) {
        Stop-Stress 'Gestoppt' 'warn' 'Das Fenster der Grafiklast wurde geschlossen.'
        return
    }
    if ($values -and $values.Stamp -ne $stress.Stamp) {
        $stress.Stamp = $values.Stamp
        $stress.Seen = [DateTime]::UtcNow
        # die letzte Minute für den Messpunkt der Staub-Warnung (PulsRig-Verschleiss.ps1)
        if (-not $stress.Tail) { $stress.Tail = New-Object System.Collections.ArrayList }
        [void]$stress.Tail.Add(@{ GT = $values.GpuTemp; GW = $values.GpuPower; GF = $values.GpuFan; CT = $values.CpuTemp; CC = $values.CpuClock; CW = $values.CpuPower })
        while ($stress.Tail.Count -gt 60) { $stress.Tail.RemoveAt(0) }
        # Höchstwerte nur für das, was belastet wird: sonst stünde im Bericht die Leerlauf-Temperatur "unter Last"
        if ($null -ne $values.GpuTemp) {
            $stress.HadTemp = $true
            if ($gpu -and $values.GpuTemp -gt $stress.MaxGpuTemp) { $stress.MaxGpuTemp = [double]$values.GpuTemp }
            if ($gpu -and $values.GpuTemp -ge 90) {
                Stop-Stress 'Zu heiß' 'bad' "Die Grafikkarte hat $($values.GpuTemp) °C erreicht. Kühlung, Lüfter und Staub prüfen."
                return
            }
        }
        if ($null -ne $values.CpuTemp) {
            if ($cpu -and $values.CpuTemp -gt $stress.MaxCpuTemp) { $stress.MaxCpuTemp = [double]$values.CpuTemp }
            # die meisten Prozessoren drosseln zwischen 90 und 100 °C selbst; 98 °C heißt, die Kühlung reicht nicht
            if ($cpu -and $values.CpuTemp -ge 98) {
                Stop-Stress 'Zu heiß' 'bad' ('Der Prozessor hat {0:N0} °C erreicht. Kühler, Wärmeleitpaste und Lüfter prüfen.' -f $values.CpuTemp)
                return
            }
        }
        if ($cpu -and $null -ne $values.CpuClock) {
            $clock = [double]$values.CpuClock
            if ($clock -gt $stress.MaxClock) { $stress.MaxClock = $clock }
            # Vergleichswert ist der Takt unter Last zwischen der 8. und 20. Sekunde; fällt er später
            # anhaltend um ein Drittel, bremst sich der Prozessor selbst - das tut er, wenn er zu heiß wird
            if ($elapsed -ge 8 -and $elapsed -lt 20 -and $clock -gt $stress.BaseClock) { $stress.BaseClock = $clock }
            if ($elapsed -ge 20 -and $stress.BaseClock -gt 0) {
                if ($clock -lt 0.67 * $stress.BaseClock) { $stress.LowClock++ } else { $stress.LowClock = 0 }
                if ($stress.LowClock -ge 6) {
                    Stop-Stress 'Prozessor drosselt' 'warn' ('Der Takt ist von {0:N2} auf {1:N2} GHz eingebrochen. So schützt sich der Prozessor vor Überhitzung: Kühler und Wärmeleitpaste prüfen. Bei Notebooks ist das unter Dauerlast oft normal.' -f $stress.BaseClock, $clock)
                    return
                }
            }
        }
    }
    # kamen schon Temperaturen und bleiben dann aus, läuft die Grafiklast ohne Hitzeschutz: lieber beenden
    if ($gpu -and $stress.HadTemp -and ([DateTime]::UtcNow - $stress.Seen).TotalSeconds -gt 10) {
        Stop-Stress 'Überwachung ausgefallen' 'warn' 'Die Temperatur der Grafikkarte kam nicht mehr an. Ohne Überwachung läuft der Test nicht weiter.'
        return
    }
    if ($elapsed -ge $stress.Seconds) {
        $parts = @()
        if ($cpu) { $parts += ('{0:N0} Rechenproben ohne Fehler' -f $samples) }
        if ($cpu -and $stress.MaxClock -gt 0) { $parts += ('Takt bis {0:N2} GHz' -f $stress.MaxClock) }
        if ($stress.MaxCpuTemp -gt 0) { $parts += ('Prozessor höchstens {0:N0} °C' -f $stress.MaxCpuTemp) }
        if ($stress.MaxGpuTemp -gt 0) { $parts += ('Grafikkarte höchstens {0:N0} °C' -f $stress.MaxGpuTemp) }
        elseif ($gpu) { $parts += 'Grafiklast ohne Abbruch, Temperatur nicht messbar' }
        Stop-Stress 'Bestanden' 'good' (($parts -join ' · ') + '.')
        return
    }
    $state = @()
    if ($cpu) { $state += ('{0:N0} Rechenproben ohne Fehler' -f $samples) }
    if ($gpu) { $state += $(if ([PulsRigStress]::GpuActive) { 'Grafiklast läuft' } else { 'Grafiklast startet' }) }
    # ohne NVIDIA-Karte gibt es keine Temperatur und damit keinen Abbruch bei Hitze - das muss dastehen
    if ($gpu -and $elapsed -gt 5 -and -not $stress.HadTemp) { $state += 'Temperatur nicht messbar: kein Abbruch bei Hitze' }
    Set-StressRow ("Läuft – $(Format-StressTime $elapsed) von $(Format-StressTime $stress.Seconds)") ($state -join ' · ') 'run'
}

function Stop-Stress([string]$Title, [string]$Tone, [string]$Text) {
    $stress = $script:Stress
    if (-not $stress) { return }
    Add-MemTrace "Stabilitätstest beendet: $Title"
    $script:Stress = $null
    $stress.Timer.Stop()
    try { [PulsRigStress]::Stop(); [PulsRigStress]::KeepAwake($false) } catch { }
    # ein paar Sekunden später, wenn das Grafikfenster zu ist: unbenutzten Arbeitsspeicher an Windows zurückgeben
    Invoke-Later 5000 { if (-not $script:Stress) { try { [PulsRigStress]::ReleaseMemory(); Add-MemTrace 'Nach dem Stabilitätstest aufgeräumt' } catch { } } }
    $elapsed = ([DateTime]::UtcNow - $stress.Start).TotalSeconds
    $what = switch ($stress.What) { 'cpu' { 'Prozessor' } 'gpu' { 'Grafikkarte' } default { 'Prozessor und Grafikkarte' } }
    $script:StressResult = @{
        Title = "$Title – $what, $(Format-StressTime ([Math]::Min($elapsed, $stress.Seconds))) Minuten"
        Text  = $Text
        Tone  = $Tone
        Time  = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        # für die eigene Zeile im Prüfbericht; 0 = nicht gemessen
        MaxGpuTemp = [double]$stress.MaxGpuTemp
        MaxCpuTemp = [double]$stress.MaxCpuTemp
    }
    # bestanden und lang genug: ein Messpunkt für die Staub-Warnung
    if ($Tone -eq 'good') { try { Add-StressThermalPoint $stress ([Math]::Min($elapsed, $stress.Seconds)) } catch { Write-AppError $_ } }
    Save-HardwareResults
    Update-HardwareBadges
    if ($script:Sheet -and $script:StressRow) {
        Set-StressRow $script:StressResult.Title $script:StressResult.Text $Tone
        $ui.BtnSheetPrimary.Content = T $('Test starten')
        # das Ergebnis springt kurz auf, damit das Ende auffällt
        $tile = $script:StressRow.FindName('Tile')
        if ($tile.RenderTransform -is [Windows.Media.ScaleTransform]) { Start-Scale $tile 1 600 0 0.5 $script:EaseElastic }
    }
}

# --- Prüfbericht ---------------------------------------------------------------
# Fasst zusammen, was die anderen Bereiche herausgefunden haben: Stabilitätstest und Tempomessungen dieser Sitzung,
# dazu frisch gelesen Laufwerke, Speichertest von Windows und gemeldete Hardwarefehler. Der Bericht lässt sich als
# eine einzelne HTML-Datei speichern, die jeder Browser anzeigt und druckt.

# Läuft im Arbeitsbereich: Angaben zum Gerät, dazu die Abfragen für Laufwerke und Arbeitsspeicher in einem Zug
$script:Queries.Report = @'
param($a)
$drives = $null; $memory = $null
try { $drives = & ([scriptblock]::Create($a.Drives)) $null } catch { }
try { $memory = & ([scriptblock]::Create($a.Memory)) $null } catch { }
$crashes = $null
try { $crashes = & ([scriptblock]::Create($a.Crashes)) @{} } catch { }
# Platzhalter, die manche Hersteller statt eines Namens eintragen
$clean = { param($text) $text = "$text".Trim(); if ($text -match '^(System manufacturer|System Product Name|To Be Filled By O\.E\.M\.|Default string|Not Applicable|None|Unknown)$') { '' } else { $text } }
$device = @{ Name = "$env:COMPUTERNAME"; Gpus = @() }
try {
    $system = Get-CimInstance Win32_ComputerSystem
    $device.Computer = ((@((& $clean $system.Manufacturer), (& $clean $system.Model)) | Where-Object { $_ }) -join ' ')
}
catch { }
try {
    $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $device.Board = ((@((& $clean $board.Manufacturer), (& $clean $board.Product)) | Where-Object { $_ }) -join ' ')
}
catch { }
try {
    $bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
    $device.Bios = "$($bios.SMBIOSBIOSVersion)".Trim()
    if ($bios.ReleaseDate) { $device.Bios += " vom $($bios.ReleaseDate.ToString('dd.MM.yyyy'))" }
}
catch { }
try {
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $device.Processor = ("$($processor.Name)" -replace '\s+', ' ').Trim()
    $device.Cores = [int]$processor.NumberOfCores
    $device.Threads = [int]$processor.NumberOfLogicalProcessors
}
catch { }
try {
    $device.Gpus = @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.PNPDeviceID)" -like 'PCI*' } | ForEach-Object {
            @{ Name = "$($_.Name)".Trim(); Driver = "$($_.DriverVersion)"; Date = $(if ($_.DriverDate) { $_.DriverDate.ToString('dd.MM.yyyy') } else { '' }) }
        })
}
catch { }
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $device.Windows = ("$($os.Caption)" -replace '^Microsoft\s+', '').Trim() + " (Build $($os.BuildNumber))"
}
catch { }
@{ Drives = $drives; Memory = $memory; Crashes = $crashes; Device = $device; Time = (Get-Date).ToString('dd.MM.yyyy HH:mm') }
'@

function Open-ReportSheet {
    $opened = Open-Sheet @{
        Title     = 'Bericht & Diagnose'
        Sub       = 'Prüfergebnisse und Angaben für die Fehlersuche in einer ZIP-Datei'
        Glyph     = 0xE8A5
        Tabs      = 'Ergebnisse', 'Gerät'
        Primary   = 'Als ZIP speichern'
        Link      = 'Neu einlesen'
        Show      = { param($tab) Show-ReportTab }
        OnPrimary = { Save-ReportZip }
        OnAction  = {
            param($item)
            if (-not $item.Data) { return }
            # zur fehlenden Prüfung wechseln: das Fenster des jeweiligen Bereichs tritt an die Stelle des Berichts
            switch ($item.Data.Go) {
                'stress' { Close-Sheet -Quick; Open-StressSheet }
                'drives' { Close-Sheet -Quick; Open-DriveSheet }
                { $_ -in 'memory', 'slots' } { Close-Sheet -Quick; Open-MemorySheet }
                'crashes' { Close-Sheet -Quick; Open-CrashSheet }
            }
        }
        OnLink    = {
            $script:Sheet.Report = $null
            $script:SheetWay = 0
            $ui.SheetChips.Children.Clear()
            Show-ReportTab
            Start-Query 'Report' { param($result) Complete-ReportQuery $result } @{ Drives = $script:Queries.Drives; Memory = $script:Queries.Memory; Crashes = $script:Queries.Crashes }
        }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Stelle den Bericht zusammen …'
    Start-Query 'Report' { param($result) Complete-ReportQuery $result } @{ Drives = $script:Queries.Drives; Memory = $script:Queries.Memory; Crashes = $script:Queries.Crashes }
}

# Die Prüfungen des Berichts mit ihrem Urteil: good = in Ordnung, warn = auffällig, bad = Fehler, open = noch nicht gelaufen
function Get-ReportChecks($Data) {
    $checks = @()

    $stress = $script:StressResult
    if (-not $stress) {
        $checks += @{ Name = 'Stabilitätstest'; Text = 'Noch nicht gelaufen.'; Kind = 'open'; Go = 'stress'; Glyph = 0xEC4A }
    }
    else {
        # von Hand beendet ist kein Befund, sondern eine Prüfung, die noch aussteht
        $kind = switch ($stress.Tone) { 'good' { 'good' } 'bad' { 'bad' } default { if ($stress.Title -like 'Gestoppt*') { 'open' } else { 'warn' } } }
        # im Fenster nur Urteil und Zeitpunkt, damit die Zeile nicht abgeschnitten wird; die Datei nennt auch die Einzelheiten
        $checks += @{ Name = 'Stabilitätstest'; Text = "$($stress.Title), $($stress.Time) Uhr. $($stress.Text)"; Short = "$($stress.Title) · $($stress.Time) Uhr"
            Kind = $kind; Go = $(if ($kind -eq 'open') { 'stress' }); Glyph = 0xEC4A }
        # die Höchsttemperaturen aus dem Test als eigene Zeile. Grafikkarte: ab 80 °C auffällig, ab 90 °C bricht der
        # Test ab. Prozessor: viele takten unter Volllast absichtlich bis an ihre Grenze (Ryzen 5000: 90 °C, Ryzen 7000
        # und neuere Intel: 95 bis 100 °C); auffällig erst ab 95 °C, zu heiß ab 98 °C (dort bricht der Test ab).
        $gpuTop = [double]$stress.MaxGpuTemp; $cpuTop = 0.0
        if ($null -ne $stress.MaxCpuTemp) { $cpuTop = [double]$stress.MaxCpuTemp }
        if ($gpuTop -gt 0 -or $cpuTop -gt 0) {
            $gpuKind = if ($gpuTop -ge 90) { 2 } elseif ($gpuTop -ge 80) { 1 } else { 0 }
            $cpuKind = if ($cpuTop -ge 98) { 2 } elseif ($cpuTop -ge 95) { 1 } else { 0 }
            $worst = [Math]::Max($gpuKind, $cpuKind)
            $note = @('Das ist unbedenklich.', 'Das ist viel: Lüfter, Staub und die Luft im Gehäuse prüfen.', 'Zu heiß: Kühlung, Lüfter und Staub prüfen.')[$worst]
            $parts = @()
            if ($cpuTop -gt 0) { $parts += ('Prozessor höchstens {0:N0} °C' -f $cpuTop) }
            if ($gpuTop -gt 0) { $parts += ('Grafikkarte höchstens {0:N0} °C' -f $gpuTop) }
            $text = ($parts -join ' · ') + ' im Stabilitätstest. ' + $note
            if ($cpuTop -le 0) { $text += ' Die Temperatur des Prozessors gibt Windows nicht heraus.' }
            elseif ($cpuTop -ge 88 -and $cpuKind -eq 0) { $text += "`n" + 'Der Prozessor lief an seiner Temperaturgrenze: Viele takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt.' }
            $checks += @{ Name = 'Höchsttemperatur unter Last'; Text = $text
                Short = (($parts + @(@('unbedenklich', 'viel – Kühlung prüfen', 'zu heiß')[$worst])) -join ' · ')
                Kind = @('good', 'warn', 'bad')[$worst]; Glyph = 0xE706 }
        }
    }

    $drives = $Data.Drives
    if ($drives -and @($drives.Disks).Count -gt 0) {
        $disks = @($drives.Disks)
        $broken = @($disks | Where-Object { $_.Health -ne 'Healthy' })
        $faulty = @($disks | Where-Object { $_.Faults -gt 0 })
        $parts = @()
        $parts += if ($disks.Count -eq 1) { '1 Laufwerk' } else { "$($disks.Count) Laufwerke" }
        $parts += if ($broken.Count -eq 0) { if ($disks.Count -eq 1) { 'Windows meldet es als gesund' } else { 'Windows meldet alle als gesund' } } else { 'nicht gesund laut Windows: ' + (@($broken | ForEach-Object { $_.Name }) -join ', ') }
        foreach ($disk in $faulty) { $parts += "$($disk.Name): $($disk.Faults) Störungen in 30 Tagen" }
        if ($drives.Resets -gt 0) { $parts += "$($drives.Resets)-mal Verbindung neu aufgebaut" }
        if ($false -eq $drives.Log) { $parts += 'Störungen im Ereignisprotokoll nicht lesbar' }
        $kind = if (@($broken | Where-Object { $_.Health -eq 'Unhealthy' }).Count -gt 0) { 'bad' } elseif ($broken.Count -gt 0 -or $faulty.Count -gt 0 -or $drives.Resets -gt 0) { 'warn' } else { 'good' }
        $checks += @{ Name = 'Zustand der Laufwerke'; Text = ($parts -join ' · ') + '.'; Kind = $kind; Glyph = 0xEDA2 }
    }
    else { $checks += @{ Name = 'Zustand der Laufwerke'; Text = 'Windows hat keine Angaben geliefert.'; Kind = 'open'; Go = 'drives'; Glyph = 0xEDA2 } }

    $measured = @($script:DriveSpeed.Keys | Sort-Object | ForEach-Object { $script:DriveSpeed[$_] } | Where-Object { $_ -and -not $_.Error })
    if ($measured.Count -eq 0) {
        $checks += @{ Name = 'Tempo der Laufwerke'; Text = 'Noch kein Laufwerk gemessen.'; Kind = 'open'; Go = 'drives'; Glyph = 0xE9D5 }
    }
    else {
        $slow = @($measured | Where-Object { $_.Read -lt 25 -or $_.Write -lt 15 })
        $parts = @($measured | ForEach-Object { '{0}: Lesen {1:N0}, Schreiben {2:N0} MB/s{3}' -f $_.Letter, $_.Read, $_.Write, $(if ($_.Date) { " ($($_.Date))" }) })
        $text = ($parts -join ' · ') + '.'
        if ($slow.Count -gt 0) { $text += ' Auffällig langsam: ' + (@($slow | ForEach-Object { "$($_.Letter):" }) -join ', ') + '.' }
        $checks += @{ Name = 'Tempo der Laufwerke'; Text = $text; Kind = $(if ($slow.Count -gt 0) { 'warn' } else { 'good' }); Glyph = 0xE9D5 }
    }

    $memory = $Data.Memory
    if ($memory -and $memory.Test) {
        $checks += @{ Name = 'Speichertest von Windows'; Text = "Letzter Lauf am $($memory.Test.Time) Uhr: $(if ($memory.Test.Ok) { 'keine Fehler gefunden' } else { 'Windows hat Speicherfehler gefunden' })."
            Kind = $(if ($memory.Test.Ok) { 'good' } else { 'bad' }); Glyph = 0xE950 }
    }
    elseif ($memory -and $false -eq $memory.Log) { $checks += @{ Name = 'Speichertest von Windows'; Text = 'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus.'; Kind = 'open'; Go = 'memory'; Glyph = 0xE950 } }
    else { $checks += @{ Name = 'Speichertest von Windows'; Text = 'Im Protokoll von Windows steht noch kein Speichertest.'; Kind = 'open'; Go = 'memory'; Glyph = 0xE950 } }

    # Stecken die Riegel richtig? Ohne Urteil (unbekannte Namen der Steckplätze) gibt es keine Zeile.
    if ($memory -and @($memory.Modules).Count -gt 0) {
        $layout = @(Get-MemoryLayout $memory)
        $placement = Get-MemoryPlacement $layout
        $channels = Get-MemoryChannels @($memory.Modules) $layout.Count
        $where = "$(@($memory.Modules).Count) von $([Math]::Max($layout.Count, @($memory.Modules).Count)) Steckplätzen belegt" + $(if ($channels) { " · $($channels.Name)" })
        if ($placement.State -eq 'bad') {
            $moves = for ($i = 0; $i -lt $placement.Wrong.Count; $i++) { "$($layout[$placement.Wrong[$i]].Slot) nach $($layout[$placement.Better[$i]].Slot)" }
            $checks += @{ Name = 'Steckplätze des Arbeitsspeichers'; Text = "Falsch gesteckt ($where). Umstecken: $($moves -join ', '). So läuft der Speicher langsamer, oder das Speicherprofil (XMP) scheitert; im Zweifel gilt das Handbuch des Mainboards."
                Short = "Falsch gesteckt · umstecken: $($moves -join ', ')"; Kind = 'warn'; Go = 'slots'; Glyph = 0xE950 }
        }
        elseif ($channels -and $channels.Hint) {
            $checks += @{ Name = 'Steckplätze des Arbeitsspeichers'; Text = "$where. $($channels.Hint)"; Short = "$where · ein zweiter Kanal wäre schneller"; Kind = 'warn'; Go = 'slots'; Glyph = 0xE950 }
        }
        elseif ($placement.State -eq 'good') {
            $checks += @{ Name = 'Steckplätze des Arbeitsspeichers'; Text = "Richtig gesteckt ($where)."; Short = "Richtig gesteckt · $where"; Kind = 'good'; Glyph = 0xE950 }
        }
    }

    # Controller und Maus (PulsRig-Eingabe.ps1): nur, wenn schon einmal getestet
    $inputState = $script:CardState.Input
    if ($inputState -and (Get-Command Get-InputSummary -ErrorAction SilentlyContinue)) {
        $checks += @{ Name = 'Controller und Maus'; Text = (Get-InputSummary); Short = "$($inputState.Detail)"; Glyph = 0xE7FC
            Kind = $(switch ("$($inputState.Tone)") { 'bad' { 'bad' } 'warn' { 'warn' } default { 'good' } }) }
    }

    # Abstürze der letzten 30 Tage (PulsRig-Abstuerze.ps1); fehlt die Abfrage (ältere Ergebnisse), gibt es keine Zeile
    if ($Data.Contains('Crashes')) { $checks += Get-CrashReportCheck $Data.Crashes }

    if ($memory) {
        if ($memory.Hardware -gt 0) {
            $checks += @{ Name = 'Gemeldete Hardwarefehler'; Text = "$($memory.Hardware) in 90 Tagen von Prozessor, Speicher oder Mainboard gemeldet, zuletzt $($memory.LastHardware) Uhr."; Kind = 'warn'; Glyph = 0xE9D9 }
        }
        elseif ($false -eq $memory.Log) { $checks += @{ Name = 'Gemeldete Hardwarefehler'; Text = 'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus.'; Kind = 'open'; Glyph = 0xE9D9 } }
        else { $checks += @{ Name = 'Gemeldete Hardwarefehler'; Text = 'Prozessor, Speicher und Mainboard haben Windows in 90 Tagen nichts gemeldet.'; Kind = 'good'; Glyph = 0xE9D9 } }
    }
    $checks
}

# Gesamturteil aus den Prüfungen: Text und Farbton
function Get-ReportVerdict($Checks) {
    $bad = @($Checks | Where-Object { $_.Kind -eq 'bad' }).Count
    $warn = @($Checks | Where-Object { $_.Kind -eq 'warn' }).Count
    $open = @($Checks | Where-Object { $_.Kind -eq 'open' }).Count
    $rest = if ($open -eq 1) { '1 Prüfung steht noch aus' } elseif ($open -gt 1) { "$open Prüfungen stehen noch aus" } else { '' }
    $title = if ($bad -gt 0) { $(if ($bad -eq 1) { '1 Fehler gefunden' } else { "$bad Fehler gefunden" }) }
    elseif ($warn -gt 0) { $(if ($warn -eq 1) { '1 Auffälligkeit' } else { "$warn Auffälligkeiten" }) }
    elseif ($open -gt 0) { 'Bisher keine Auffälligkeiten' }
    else { 'Alle Prüfungen bestanden' }
    @{ Title = $title; Rest = $rest; Tone = $(if ($bad -gt 0) { 'bad' } elseif ($warn -gt 0) { 'warn' } else { 'good' }); Good = @($Checks | Where-Object { $_.Kind -eq 'good' }).Count; Warn = $warn + $bad; Open = $open }
}

function Get-ReportState([string]$Kind) {
    switch ($Kind) {
        'good' { @{ Text = 'in Ordnung'; Tone = 'good' } }
        'warn' { @{ Text = 'auffällig'; Tone = 'warn' } }
        'bad' { @{ Text = 'Fehler'; Tone = 'bad' } }
        default { @{ Text = 'offen'; Tone = '' } }
    }
}

# Angaben zum Gerät als Paare aus Bezeichnung und Wert - für das Fenster und für die Datei
function Get-ReportDevice($Data) {
    $device = $Data.Device
    $pairs = [ordered]@{}
    # bei selbst gebauten PCs steht als Modell nur noch einmal das Mainboard - dann genügt dessen Zeile
    if ($device.Computer -and "$($device.Board)".IndexOf($device.Computer, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $pairs['Computer'] = $device.Computer }

    if ($device.Board) { $pairs['Mainboard'] = $device.Board }
    if ($device.Bios) { $pairs['BIOS'] = $device.Bios }
    if ($device.Processor) { $pairs['Prozessor'] = "$($device.Processor) · $($device.Cores) Kerne, $($device.Threads) Threads" }
    $number = 0
    foreach ($gpu in @($device.Gpus)) {
        $number++
        $label = if (@($device.Gpus).Count -gt 1) { "Grafikkarte $number" } else { 'Grafikkarte' }
        $pairs[$label] = $gpu.Name + $(if ($gpu.Driver) { " · Treiber $($gpu.Driver)$(if ($gpu.Date) { " vom $($gpu.Date)" })" })
    }
    if ($Data.Memory) {
        $modules = @($Data.Memory.Modules)
        $installed = [double](($modules | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
        $first = $modules | Select-Object -First 1
        $parts = @(('{0:N0} GB' -f ($installed / 1GB)), $(if ($modules.Count -eq 1) { '1 Riegel' } else { "$($modules.Count) Riegel" }))
        if ($first -and $first.Type) { $parts += $first.Type }
        if ($first -and $first.Speed) { $parts += ('{0:N0} MHz' -f $first.Speed) }
        # laufen die Riegel langsamer, als sie gebaut sind, gehört das in den Bericht
        $profile = Get-MemoryProfile $modules
        if ($profile -and $profile.Tone -eq 'Warn') { $parts += ('gebaut für {0:N0} MHz' -f $profile.Rated) }
        if ($installed -gt 0) { $pairs['Arbeitsspeicher'] = $parts -join ' · ' }
    }
    if ($Data.Drives) {
        foreach ($disk in @($Data.Drives.Disks)) {
            $letters = (@($disk.Letters | ForEach-Object { "$_`:" }) -join ' ')
            $kind = Get-DriveKind $disk
            $pairs["Laufwerk $($disk.Number)"] = (@($disk.Name, $(if ($kind -ne 'Laufwerk') { $kind }), (Format-DriveSize $disk.Size), $letters) | Where-Object { $_ }) -join ' · '
        }
    }
    if ($device.Windows) { $pairs['Windows'] = $device.Windows }
    $pairs
}

function Complete-ReportQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Report = $Result
    $verdict = Get-ReportVerdict (Get-ReportChecks $Result)
    # der Bericht liest Laufwerke und Arbeitsspeicher mit: auch deren Karten kennen danach ihren Stand
    if ($Result.Drives) { Set-CardState 'Drives' (Get-DriveCardState $Result.Drives) }
    if ($Result.Memory) { Set-CardState 'Memory' (Get-MemoryCardState $Result.Memory) }
    if ($Result.Crashes) { $script:LastCrashes = $Result.Crashes; $crashState = Get-CrashCardState $Result.Crashes; if ($crashState) { Set-CardState 'Crashes' $crashState } }
    $state = if ($verdict.Tone -eq 'bad') { @{ Text = 'Fehler gefunden'; Tone = 'bad' } }
    elseif ($verdict.Tone -eq 'warn') { @{ Text = "$($verdict.Warn) auffällig"; Tone = 'warn' } }
    elseif ($verdict.Open -gt 0) { @{ Text = "$($verdict.Open) offen"; Tone = '' } }
    else { @{ Text = 'alles bestanden'; Tone = 'good' } }
    $state.Detail = (@("$($verdict.Good) gut", $(if ($verdict.Warn -gt 0) { "$($verdict.Warn) auffällig" }), $(if ($verdict.Open -gt 0) { "$($verdict.Open) offen" })) | Where-Object { $_ }) -join ' · '
    Set-CardState 'Report' $state
    $ui.SheetChips.Children.Clear()
    Add-ResultChip "$($verdict.Good) in Ordnung" 'Good' $ui.SheetChips
    if ($verdict.Warn -gt 0) { Add-ResultChip "$($verdict.Warn) auffällig" 'Warn' $ui.SheetChips }
    if ($verdict.Open -gt 0) { Add-ResultChip "$($verdict.Open) offen" 'Ring2' $ui.SheetChips }
    Show-ReportTab
}

function Show-ReportTab {
    $data = $script:Sheet.Report
    if (-not $data) {
        Start-SheetLoader 'Stelle den Bericht zusammen …'
        return
    }
    $rows = @()
    if ($script:Sheet.Tab -eq 0) {
        foreach ($check in @(Get-ReportChecks $data)) {
            $state = Get-ReportState $check.Kind
            $action = switch ($check.Go) { 'stress' { 'Zum Test' } 'drives' { 'Zu den Laufwerken' } 'memory' { 'Zum Speichertest' } 'slots' { 'Zum Arbeitsspeicher' } 'crashes' { 'Zu den Abstürzen' } default { '' } }
            $rows += New-SheetRow -Title $check.Name -Sub $(if ($check.Short) { $check.Short } else { $check.Text }) -Glyph $check.Glyph -State $state.Text -Tone $state.Tone -Action $action -Data @{ Go = $check.Go }
        }
        Show-SheetList $rows
        Set-SheetStateText "Stand: $($data.Time) Uhr"
        return
    }
    $pairs = Get-ReportDevice $data
    foreach ($key in $pairs.Keys) { $rows += New-SheetRow -Kind 'pair' -Title $key -Value "$($pairs[$key])" }
    Show-SheetList $rows
    Set-SheetStateText "Stand: $($data.Time) Uhr"
}

# Vorlage der Berichtsdatei: dunkel am Bildschirm, hell und sparsam auf Papier
$script:ReportTemplate = @'
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PulsRig Prüfbericht – {{NAME}}</title>
<style>
  :root { --bg:#0b1220; --card:#131c33; --line:#223052; --text:#e8eefc; --dim:#93a3c7; --a1:{{A1}}; --a2:{{A2}}; --good:#34d399; --warn:#fbbf24; --bad:#f87171; }
  * { box-sizing:border-box; }
  body { margin:0; padding:32px 16px; background:var(--bg); color:var(--text); font:15px/1.5 "Segoe UI Variable Text","Segoe UI",system-ui,sans-serif; }
  main { max-width:820px; margin:0 auto; }
  header { display:flex; justify-content:space-between; align-items:flex-end; gap:16px; flex-wrap:wrap; padding-bottom:18px; border-bottom:2px solid; border-image:linear-gradient(90deg,var(--a1),var(--a2)) 1; }
  .brand { font-size:13px; font-weight:600; letter-spacing:.14em; text-transform:uppercase; color:var(--a1); }
  h1 { margin:2px 0 0; font-size:30px; font-weight:600; letter-spacing:-.01em; }
  .meta { text-align:right; color:var(--dim); font-size:13px; }
  .meta b { display:block; color:var(--text); font-size:15px; font-weight:600; }
  .verdict { margin:24px 0 8px; padding:18px 22px; border-radius:14px; background:var(--card); border:1px solid var(--line); border-left:5px solid var(--tone); }
  .verdict b { display:block; font-size:22px; font-weight:600; color:var(--tone); }
  .verdict span { color:var(--dim); }
  .good { --tone:var(--good); } .warn { --tone:var(--warn); } .bad { --tone:var(--bad); } .open { --tone:var(--dim); }
  h2 { margin:30px 0 10px; font-size:12px; font-weight:600; letter-spacing:.14em; text-transform:uppercase; color:var(--dim); }
  .check { display:flex; gap:16px; align-items:flex-start; justify-content:space-between; padding:14px 18px; margin-bottom:8px; border-radius:12px; background:var(--card); border:1px solid var(--line); break-inside:avoid; }
  .check b { display:block; font-weight:600; }
  .check p { margin:2px 0 0; color:var(--dim); font-size:14px; }
  .pill { flex:none; padding:3px 12px; border-radius:99px; font-size:12px; font-weight:600; color:var(--tone); border:1px solid var(--tone); white-space:nowrap; }
  table { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
  th, td { padding:9px 18px; text-align:left; vertical-align:top; border-top:1px solid var(--line); }
  tr:first-child th, tr:first-child td { border-top:0; }
  th { width:30%; font-weight:400; color:var(--dim); white-space:nowrap; }
  footer { margin-top:26px; color:var(--dim); font-size:12.5px; }
  @media (max-width:560px) { th { white-space:normal; } .meta { text-align:left; } }
  @media print {
    :root { --bg:#fff; --card:#fff; --line:#cfd6e4; --text:#111827; --dim:#4b5563; --good:#047857; --warn:#b45309; --bad:#b91c1c; --a1:#111827; --a2:#111827; }
    body { padding:0; font-size:12pt; }
  }
</style>
</head>
<body>
<main>
<header>
  <div><div class="brand">PulsRig</div><h1>Prüfbericht</h1></div>
  <div class="meta"><b>{{NAME}}</b>{{TIME}} Uhr</div>
</header>
<div class="verdict {{TONE}}"><b>{{VERDICT}}</b><span>{{REST}}</span></div>
<h2>Prüfungen</h2>
{{CHECKS}}
<h2>Gerät</h2>
<table>
{{DEVICE}}
</table>
<footer>Der Bericht gibt wieder, was Windows und die Tests von PulsRig zum genannten Zeitpunkt gemeldet haben. Er ist kein Gutachten und keine Garantie: Fehler, die nur selten oder erst nach Stunden auftreten, kann eine kurze Prüfung übersehen.</footer>
</main>
</body>
</html>
'@

function New-ReportHtml($Data) {
    # alles, was in den Bericht kommt, geht durch die Übersetzung: der Bericht hat die Sprache des Programms
    $escape = { param($text) [Security.SecurityElement]::Escape((T "$text")) }
    $checks = @(Get-ReportChecks $Data)
    $verdict = Get-ReportVerdict $checks
    $checkHtml = foreach ($check in $checks) {
        $state = Get-ReportState $check.Kind
        '<div class="check {0}"><div><b>{1}</b><p>{2}</p></div><span class="pill">{3}</span></div>' -f $check.Kind, (& $escape $check.Name), (& $escape $check.Text), (& $escape $state.Text)
    }
    $pairs = Get-ReportDevice $Data
    $deviceHtml = foreach ($key in $pairs.Keys) { '<tr><th>{0}</th><td>{1}</td></tr>' -f (& $escape $key), (& $escape $pairs[$key]) }
    # in der Kopfzeile steht das Gerät, nicht der Name des PCs im Netzwerk: Berichte werden weitergegeben
    $name = if ($pairs.Contains('Computer')) { $pairs['Computer'] } elseif ($Data.Device.Board) { $Data.Device.Board } else { 'Dieser PC' }
    $html = $script:ReportTemplate
    if ($script:Language -ne 'de') {
        # die festen Texte der Vorlage: alles, was zwischen zwei Marken steht und Wörter enthält
        $html = [regex]::Replace($html, '(?<=>)([^<>{}\r\n]*[A-Za-zÄÖÜäöü]{3}[^<>{}\r\n]*)(?=<)', { param($match) [Security.SecurityElement]::Escape((T $match.Value)) })
        $html = $html.Replace('lang="de"', "lang=`"$script:Language`"").Replace('{{TIME}} Uhr', '{{TIME}}').Replace('<title>PulsRig Prüfbericht', "<title>PulsRig $(T 'Prüfbericht')")
    }
    $fill = [ordered]@{
        '{{A1}}'      = "$($script:Theme.A[0])"
        '{{A2}}'      = "$($script:Theme.A[1])"
        '{{NAME}}'    = & $escape $name
        '{{TIME}}'    = & $escape $Data.Time
        '{{TONE}}'    = $verdict.Tone
        '{{VERDICT}}' = & $escape $verdict.Title
        '{{REST}}'    = & $escape $(if ($verdict.Rest) { "$($verdict.Rest)." } else { 'Jede Prüfung des Berichts ist gelaufen.' })
        '{{CHECKS}}'  = $checkHtml -join "`n"
        '{{DEVICE}}'  = $deviceHtml -join "`n"
    }
    foreach ($key in $fill.Keys) { $html = $html.Replace($key, "$($fill[$key])") }
    $html
}

# Speichert den Bericht als Datei und zeigt ihn im Browser; dort lässt er sich drucken
# Bericht & Diagnose in einem Zug: der Prüfbericht als Webseite und die Angaben des Diagnose-Pakets in einer ZIP-Datei
# auf dem Desktop. Danach schickt derselbe Knopf die Datei per Mail.
function Save-ReportZip {
    if (-not $script:Sheet) { return }
    try {
        $window.Cursor = [Windows.Input.Cursors]::Wait
        # ohne fertigen Bericht (er hängt oder ist gescheitert) kommen wenigstens die Angaben zur Fehlersuche ins Paket
        $extra = @{}
        if ($script:Sheet.Report) {
            try { $extra["PulsRig-Prüfbericht-$((Get-Date).ToString('yyyy-MM-dd')).html"] = New-ReportHtml $script:Sheet.Report }
            catch { Write-AppError $_; $extra['Bericht-fehlt.txt'] = "Der Prüfbericht ließ sich nicht erstellen: $($_.Exception.Message)" }
        }
        else { $extra['Bericht-fehlt.txt'] = 'Der Prüfbericht war beim Speichern noch nicht fertig.' }
        $file = if ($Snapshot) { New-DiagnosePackage $Snapshot $extra 'PulsRig-Bericht' } else { New-DiagnosePackage ([Environment]::GetFolderPath('Desktop')) $extra 'PulsRig-Bericht' }
        $script:Sheet.File = $file
        $place = Get-DiagnosePlace $file
        Set-SheetStateText "Gespeichert $($place): $(Split-Path -Leaf $file)"
        Set-CardState 'Diagnose' @{ Text = "erstellt $((Get-Date).ToString('HH:mm'))"; Place = $place; File = $file }
        $ui.BtnSheetPrimary.Content = T 'Per E-Mail schicken'
        $script:Sheet.OnPrimary = { Send-DiagnoseMail $script:Sheet.File }
        if (-not $Snapshot) { try { Start-Process explorer.exe "/select,`"$file`"" } catch { } }
    }
    catch { Write-AppError $_; Set-SheetStateText "Die ZIP-Datei ließ sich nicht erstellen: $(@("$($_.Exception.Message)" -split "`r?`n")[0])" }
    finally { $window.Cursor = $null }
}

function Save-Report {
    if (-not $script:Sheet -or -not $script:Sheet.Report) { return }
    $name = "PulsRig-Prüfbericht-$((Get-Date).ToString('yyyy-MM-dd')).html"
    if ($Snapshot) { $path = Join-Path $Snapshot $name }   # im Probelauf ohne Rückfrage in den Ordner der Bilder
    else {
        $picker = New-Object Microsoft.Win32.SaveFileDialog
        $picker.Title = 'Prüfbericht speichern'
        $picker.Filter = 'Webseite (*.html)|*.html'
        $picker.FileName = $name
        $picker.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        if (-not $picker.ShowDialog($window)) { return }
        $path = $picker.FileName
    }
    try {
        [IO.File]::WriteAllText($path, (New-ReportHtml $script:Sheet.Report), (New-Object Text.UTF8Encoding $true))
        $script:Sheet.ReportPath = $path
        if (-not $Snapshot) { Start-Process $path }
        Set-SheetStateText "Gespeichert als $(Split-Path -Leaf $path) · zum Drucken im Browser Strg+P"
    }
    catch { Set-SheetStateText "Speichern nicht möglich: $(@("$($_.Exception.Message)" -split "`r?`n")[0])" }
}

# --- Ergebnisse merken ----------------------------------------------------------
# Stabilitätstest und Tempomessungen stehen in einer eigenen Datei neben den Einstellungen, damit der Prüfbericht
# sie auch nach einem Neustart des Programms noch kennt. "Einstellungen zurücksetzen" lässt sie unberührt.

$script:ResultsPath = Join-Path (Split-Path -Parent $script:SettingsPath) 'PulsRig-Ergebnisse.json'

# Statt eines Schilds "Verfügbar" zeigt jede Karte der Hardware-Seite, was die letzte Prüfung ergeben hat.
# Laufwerke, Arbeitsspeicher und Prüfbericht merken sich ihren Stand in der Ergebnisdatei; er steht mit Datum da,
# weil er alt sein kann. Das Diagnose-Paket zeigt nur, ob in dieser Sitzung eines erstellt wurde.
$script:CardState = @{}

function Get-DriveCardState($Drives) {
    $disks = @($Drives.Disks)
    if ($disks.Count -eq 0) { return @{ Text = 'keine Angaben'; Tone = '' } }
    $bad = @($disks | Where-Object { $_.Health -ne 'Healthy' -or $_.Faults -gt 0 }).Count
    $state = if ($bad -gt 0) { @{ Text = "$bad auffällig"; Tone = 'warn' } }
    elseif ($Drives.Resets -gt 0) { @{ Text = 'auffällig'; Tone = 'warn' } }
    else { @{ Text = 'in Ordnung'; Tone = 'good' } }
    $free = [double](@($Drives.Volumes) | ForEach-Object { $_.Free } | Measure-Object -Sum).Sum
    $state.Detail = $(if ($disks.Count -eq 1) { '1 Laufwerk' } else { "$($disks.Count) Laufwerke" }) + $(if (@($Drives.Volumes).Count -gt 0) { " · $(Format-DriveSize $free) frei" })
    # Belegung je Laufwerksbuchstabe für die Balken auf der Karte: "C|62"
    $state.Bars = @(@($Drives.Volumes) | Where-Object { $_.Size -gt 0 } | Select-Object -First 3 | ForEach-Object { '{0}|{1:0}' -f $_.Letter, (100.0 * (1.0 - $_.Free / $_.Size)) })
    $state
}

function Get-MemoryCardState($Memory) {
    $modules = @($Memory.Modules)
    if ($modules.Count -eq 0) {
        $state = if ($Memory.Test -and -not $Memory.Test.Ok) { @{ Text = 'Speicherfehler'; Tone = 'bad' } } else { @{ Text = 'Riegel unbekannt'; Tone = '' } }
        if ($Memory.Total -gt 0) { $state.Detail = '{0:N0} GB laut Windows' -f ($Memory.Total / 1GB) }
        return $state
    }
    $layout = @(Get-MemoryLayout $Memory)
    $placement = Get-MemoryPlacement $layout
    $channels = Get-MemoryChannels $modules $layout.Count
    $size = [double](($modules | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum)
    $state = if ($Memory.Test -and -not $Memory.Test.Ok) { @{ Text = 'Speicherfehler'; Tone = 'bad' } }
    elseif ($placement.State -eq 'bad') { @{ Text = 'falsch gesteckt'; Tone = 'warn' } }
    elseif ($Memory.Hardware -gt 0) { @{ Text = 'Hardwarefehler'; Tone = 'warn' } }
    elseif ($channels -and $channels.Hint) { @{ Text = "$($channels.Name)"; Tone = 'warn' } }
    else { @{ Text = ('{0:N0} GB' -f ($size / 1GB)); Tone = $(if ($placement.State -eq 'good') { 'good' } else { '' }) } }
    # Fußzeile der Karte: Anzahl der Riegel, Bauart und Takt (das Schild oben ist schmal)
    $first = $modules[0]
    $state.Detail = (@($(if ($modules.Count -eq 1) { '1 Riegel' } else { "$($modules.Count) Riegel" }), "$($first.Type)", $(if ($first.Speed) { '{0:N0} MHz' -f $first.Speed })) | Where-Object { $_ }) -join ' · '
    # Steckplätze für das Bild auf der Karte
    $state.Slots = [int]$layout.Count
    $state.Used = [int]$modules.Count
    $state.Size = ('{0:N0} GB' -f ($size / 1GB))
    $state
}

function Set-CardState([string]$Name, $State) {
    if (-not $State) { return }
    $State.Date = (Get-Date).ToString('dd.MM.yyyy')
    $script:CardState[$Name] = $State
    if ($Name -ne 'Diagnose') { Save-HardwareResults }
    Update-HardwareBadges
}

# "in Ordnung · heute" oder "in Ordnung · 13.10."
function Format-CardState($State) {
    if (-not $State -or -not $State.Text) { return '' }
    $date = "$($State.Date)"
    $when = if ($date.Length -lt 6) { '' } elseif ($date -eq (Get-Date).ToString('dd.MM.yyyy')) { 'heute' } else { $date.Substring(0, 6) }
    if ($when) { "$($State.Text) · $when" } else { "$($State.Text)" }
}

function Set-HardwareBadge([int]$Index, [string]$Text, [string]$Tone = '') {
    $Text = T $Text
    $badge = $script:HardwareCards[$Index].Badge
    $badge.Visibility = if ($Text) { 'Visible' } else { 'Collapsed' }
    $badge.Child.Text = $Text
    Set-Paint $badge.Child 'Foreground' $(switch ($Tone) { 'good' { 'Good' } 'warn' { 'Warn' } 'bad' { 'Bad' } 'accent' { 'Accent' } default { 'TextDim' } })
}

# Fußzeile einer Karte: ein Wert der letzten Prüfung - oder, in der Akzentfarbe, was ein Klick tut
function Set-HardwareFoot([int]$Index, [string]$Value, [string]$Call) {
    $Value = T $Value; $Call = T $Call
    $foot = $script:HardwareCards[$Index].Foot
    $foot.Text = if ($Value) { $Value } else { $Call }
    Set-Paint $foot 'Foreground' $(if ($Value) { 'TextDim' } else { 'Accent' })
}

# Reihenfolge der Karten: Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher, Abstürze, Bildschirm, Bericht & Diagnose, BIOS
function Update-HardwareBadges {
    Set-HardwareBadge 0 'Live' 'accent'
    Set-HardwareFoot 0 '' 'Messung öffnen'
    $stress = $script:StressResult
    if ($stress -and $stress.Title) {
        # lange Abbruchgründe ("Überwachung ausgefallen") passen nicht ins Schild; sie stehen in der Fußzeile
        $reason = ("$($stress.Title)" -split ' – ')[0]
        $word = if ($stress.Tone -ne 'good' -and $reason.Length -gt 12) { 'Abgebrochen' } else { $reason }
        Set-HardwareBadge 1 (Format-CardState @{ Text = $word; Date = ("$($stress.Time)" -split ' ')[0] }) "$($stress.Tone)"
        $parts = @()
        if ($stress.MaxCpuTemp -gt 0 -and $stress.MaxGpuTemp -gt 0) { $parts += ('CPU {0:N0} · GPU {1:N0} °C' -f $stress.MaxCpuTemp, $stress.MaxGpuTemp) }
        elseif ($stress.MaxGpuTemp -gt 0) { $parts += ('Höchstens {0:N0} °C' -f $stress.MaxGpuTemp) }
        elseif ($stress.MaxCpuTemp -gt 0) { $parts += ('Prozessor höchstens {0:N0} °C' -f $stress.MaxCpuTemp) }
        if ("$($stress.Text)" -match 'Takt bis ([\d.,]+) GHz') { $parts += "$($Matches[1]) GHz" }
        Set-HardwareFoot 1 $(if ($stress.Tone -ne 'good') { $reason } elseif ($parts.Count -gt 0) { $parts -join ' · ' } else { 'Ohne Fehler durchgelaufen' }) ''
    }
    else { Set-HardwareBadge 1 'Noch nicht gelaufen'; Set-HardwareFoot 1 '' 'Test starten' }
    foreach ($pair in @(@(2, 'Drives', 'Jetzt prüfen'), @(3, 'Memory', 'Jetzt prüfen'), @(4, 'Crashes', 'Jetzt prüfen'), @(5, 'Displays', 'Test öffnen'), @(6, 'Report', 'Bericht und ZIP erstellen'))) {
        $state = $script:CardState[$pair[1]]
        if ($state) { Set-HardwareBadge $pair[0] (Format-CardState $state) "$($state.Tone)" } else { Set-HardwareBadge $pair[0] 'Noch nicht geprüft' }
        Set-HardwareFoot $pair[0] $(if ($state) { "$($state.Detail)" } else { '' }) $pair[2]
    }
    # wurde in dieser Sitzung eine ZIP-Datei erstellt, steht das in der Fußzeile von Bericht & Diagnose
    $pack = $script:CardState.Diagnose
    if ($pack) { Set-HardwareFoot 6 "ZIP $($pack.Text) · $(if ($pack.Place) { $pack.Place } else { 'auf dem Desktop' })" '' }
    # das Alter des BIOS hängt nicht davon ab, wann nachgesehen wurde: das Schild zeigt es ohne Datum
    $bios = $script:CardState.Bios
    Set-HardwareBadge 7 $(if ($bios) { "$($bios.Text)" } else { 'Noch nicht gelesen' }) $(if ($bios) { "$($bios.Tone)" } else { '' })
    Set-HardwareFoot 7 $(if ($bios) { "$($bios.Detail)" } else { '' }) 'Jetzt ansehen'
    Update-HardwareVisuals
}
# --- Bilder auf den Karten ---------------------------------------------------------
# Sobald es Messwerte gibt, ersetzt ein kleines Bild die Stichpunkte einer Karte: großer Wert, Balken,
# Steckplätze oder Tage. Ohne Werte bleiben die Stichpunkte, die erklären, was die Karte tut.

function New-HwText([string]$Text, [double]$Size = 22) {
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $Text; $block.FontSize = $Size; $block.FontWeight = 'SemiBold'; $block.TextWrapping = 'Wrap'
    Set-Paint $block 'Foreground' 'Text'
    $block
}

function New-HwColumn([double]$Stars) {
    $column = New-Object Windows.Controls.ColumnDefinition
    $column.Width = New-Object Windows.GridLength ([Math]::Max($Stars, 0.0001)), ([Windows.GridUnitType]::Star)
    $column
}

# Balken mit Anteil 0..1; $Paint = Name einer Farbe des Designs oder 'grad' für den Farbverlauf
function New-HwBar([double]$Fraction, [string]$Paint = 'grad', [double]$Height = 8) {
    $Fraction = [Math]::Max(0.0, [Math]::Min(1.0, $Fraction))
    $grid = New-Object Windows.Controls.Grid
    $grid.Height = $Height
    $grid.ColumnDefinitions.Add((New-HwColumn $Fraction))
    $grid.ColumnDefinitions.Add((New-HwColumn (1.0 - $Fraction)))
    $track = New-Object Windows.Controls.Border
    $track.CornerRadius = (Get-SkinRadius ($Height / 2)); $track.Background = New-Brush '#1AFFFFFF'
    [Windows.Controls.Grid]::SetColumnSpan($track, 2)
    [void]$grid.Children.Add($track)
    if ($Fraction -gt 0) {
        $fill = New-Object Windows.Controls.Border
        $fill.CornerRadius = (Get-SkinRadius ($Height / 2))
        if ($Paint -eq 'grad') { $fill.Background = $window.FindResource('AccentGrad') } else { Set-Paint $fill 'Background' $Paint }
        [void]$grid.Children.Add($fill)
    }
    $grid
}

function New-HwVisual([int]$Index) {
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '0,2,0,0'
    switch ($Index) {
        0 {
            # Sensoren: letzter Wert der Live-Messung auf der Startseite samt Kurve
            $row = if ($script:HomeLive) { $script:HomeLive[0] } else { $null }
            if (-not $row -or $row.History.Count -lt 2 -or -not $row.Text) { return $null }
            [void]$panel.Children.Add((New-HwText $row.Text))
            # die Kurve wird gezeichnet, sobald die Fläche ihre Breite kennt; kleine Schwankungen bleiben klein
            $area = New-Object Windows.Controls.Grid
            $area.Height = 30; $area.Margin = '0,8,0,0'; $area.ClipToBounds = $true
            $line = New-Object Windows.Shapes.Path
            $line.StrokeThickness = 1.8; $line.StrokeLineJoin = 'Round'
            # auf einer Zeichenfläche: die Kurve verlangt so keinen Platz und kann die Karte nicht aufweiten
            $canvas = New-Object Windows.Controls.Canvas
            [void]$canvas.Children.Add($line)
            [void]$area.Children.Add($canvas)
            Set-Paint $line 'Stroke' 'Accent'
            $area.Tag = @{ Line = $line; Values = @($row.History) }
            $area.Add_SizeChanged({
                    try {
                        $values = $this.Tag.Values
                        $width = $this.ActualWidth; $height = $this.ActualHeight
                        if ($values.Count -lt 2 -or $width -lt 10) { return }
                        $low = ($values | Measure-Object -Minimum).Minimum; $high = ($values | Measure-Object -Maximum).Maximum
                        if ($high - $low -lt 6) { $middle = ($high + $low) / 2; $low = $middle - 3; $high = $middle + 3 }
                        $culture = [cultureinfo]::InvariantCulture
                        $points = for ($i = 0; $i -lt $values.Count; $i++) {
                            $x = $width * $i / ($values.Count - 1)
                            $y = $height - 1 - ($values[$i] - $low) / ($high - $low) * ($height - 2)
                            '{0}{1},{2}' -f $(if ($i) { ' L ' } else { 'M ' }), $x.ToString('0.0', $culture), $y.ToString('0.0', $culture)
                        }
                        $this.Tag.Line.Data = [Windows.Media.Geometry]::Parse(($points -join ''))
                    }
                    catch { Write-AppError $_ }
                })
            # auf Notebooks steht unter dem Wert die Akku-Zeile: für die Kurve ist dann kein Platz
            if (-not $script:HasBattery) { [void]$panel.Children.Add($area) }
        }
        1 {
            $stress = $script:StressResult
            if (-not $stress) { return $null }
            # die höhere der beiden Temperaturen; der Prozessor darf etwas wärmer werden als die Grafikkarte
            $top = [Math]::Max([double]$stress.MaxGpuTemp, [double]$stress.MaxCpuTemp)
            if (-not ($top -gt 0)) { return $null }
            $hot = ($stress.MaxGpuTemp -ge 85) -or ($stress.MaxCpuTemp -ge 90)
            [void]$panel.Children.Add((New-HwText ('{0:N0} °C' -f $top)))
            $bar = New-HwBar ($top / 100.0) $(if ($hot) { 'Warn' } else { 'grad' })
            $bar.Margin = '0,10,0,0'
            [void]$panel.Children.Add($bar)
        }
        2 {
            $bars = @($script:CardState.Drives.Bars | Where-Object { "$_" -match '^\w\|\d+$' })
            if ($bars.Count -eq 0) { return $null }
            foreach ($entry in $bars) {
                $parts = "$entry" -split '\|'
                $row = New-Object Windows.Controls.Grid
                $row.Margin = '0,0,0,8'
                $first = New-Object Windows.Controls.ColumnDefinition
                $first.Width = New-Object Windows.GridLength 18
                $row.ColumnDefinitions.Add($first)
                $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
                $label = New-Object Windows.Controls.TextBlock
                $label.Text = $parts[0]; $label.FontSize = 11; $label.VerticalAlignment = 'Center'
                Set-Paint $label 'Foreground' 'TextDim'
                $used = [double]$parts[1] / 100.0
                $bar = New-HwBar $used $(if ($used -ge 0.9) { 'Warn' } else { 'Accent' }) 6
                [Windows.Controls.Grid]::SetColumn($bar, 1)
                [void]$row.Children.Add($label); [void]$row.Children.Add($bar)
                [void]$panel.Children.Add($row)
            }
        }
        3 {
            $memory = $script:CardState.Memory
            if (-not $memory -or -not ([int]$memory.Slots -gt 0)) { return $null }
            $slots = [Math]::Min(8, [int]$memory.Slots); $used = [Math]::Min($slots, [int]$memory.Used)
            [void]$panel.Children.Add((New-HwText "$($memory.Size)"))
            $grid = New-Object Windows.Controls.Primitives.UniformGrid
            $grid.Rows = 1; $grid.Columns = $slots; $grid.Margin = '-3,10,-3,0'
            # zwei von vier Riegeln stecken üblicherweise im zweiten und vierten Platz
            $filled = if ($used * 2 -eq $slots) { @(for ($i = 1; $i -lt $slots; $i += 2) { $i }) } else { @(for ($i = 0; $i -lt $used; $i++) { $i }) }
            for ($i = 0; $i -lt $slots; $i++) {
                $slot = New-Object Windows.Controls.Border
                $slot.Height = 18; $slot.Margin = '3,0'; $slot.CornerRadius = (Get-SkinRadius 4)
                if ($filled -contains $i) { $slot.Background = $window.FindResource('AccentGrad') } else { $slot.Background = New-Brush '#1AFFFFFF' }
                [void]$grid.Children.Add($slot)
            }
            [void]$panel.Children.Add($grid)
        }
        4 {
            $crashes = $script:CardState.Crashes
            if (-not $crashes -or $null -eq $crashes.Days) { return $null }
            $days = @($crashes.Days | ForEach-Object { [int]$_ })
            $grid = New-Object Windows.Controls.Primitives.UniformGrid
            $grid.Rows = 2; $grid.Columns = 15; $grid.Margin = '-2,4,-2,0'
            $tone = if ($crashes.Tone -eq 'bad') { 'Bad' } else { 'Warn' }
            # links vor 29 Tagen, rechts heute
            for ($i = 29; $i -ge 0; $i--) {
                $day = New-Object Windows.Controls.Border
                $day.Height = 12; $day.Margin = '2'; $day.CornerRadius = (Get-SkinRadius 3)
                if ($days -contains $i) { Set-Paint $day 'Background' $tone } else { $day.Background = New-Brush '#2834D399' }
                [void]$grid.Children.Add($day)
            }
            [void]$panel.Children.Add($grid)
        }
        6 {
            $report = $script:CardState.Report
            if (-not $report -or "$($report.Detail)" -notmatch '(\d+) gut') { return $null }
            $good = [int]$Matches[1]
            $warn = if ("$($report.Detail)" -match '(\d+) auffällig') { [int]$Matches[1] } else { 0 }
            $open = if ("$($report.Detail)" -match '(\d+) offen') { [int]$Matches[1] } else { 0 }
            $all = $good + $warn + $open
            if ($all -eq 0) { return $null }
            [void]$panel.Children.Add((New-HwText (T "$good von $all gut")))
            $bar = New-Object Windows.Controls.Grid
            $bar.Height = 8; $bar.Margin = '0,10,-4,0'
            $column = 0
            foreach ($part in @(@($good, 'Good'), @($warn, 'Warn'), @($open, ''))) {
                if ($part[0] -le 0) { continue }
                $bar.ColumnDefinitions.Add((New-HwColumn ([double]$part[0])))
                $piece = New-Object Windows.Controls.Border
                $piece.CornerRadius = (Get-SkinRadius 4); $piece.Margin = '0,0,4,0'
                if ($part[1]) { Set-Paint $piece 'Background' $part[1] } else { $piece.Background = New-Brush '#26FFFFFF' }
                [Windows.Controls.Grid]::SetColumn($piece, $column)
                [void]$bar.Children.Add($piece)
                $column++
            }
            [void]$panel.Children.Add($bar)
        }
        7 {
            $bios = $script:CardState.Bios
            if (-not $bios -or "$($bios.Detail)" -notmatch '^(.+) vom (\d\d)\.(\d\d)\.(\d{4})$') { return $null }
            $version = $Matches[1]
            $date = Get-Date -Year ([int]$Matches[4]) -Month ([int]$Matches[3]) -Day ([int]$Matches[2])
            $months = [Math]::Max(0.0, ((Get-Date) - $date).TotalDays / 30.44)
            [void]$panel.Children.Add((New-HwText $version))
            # voller Balken nach drei Jahren
            $bar = New-HwBar ($months / 36.0) $(if ($bios.Tone -eq 'warn') { 'Warn' } else { 'grad' })
            $bar.Margin = '0,10,0,0'
            [void]$panel.Children.Add($bar)
        }
        default { return $null }
    }
    $panel
}

function Update-HardwareVisuals {
    foreach ($index in @($script:HardwareCards.Keys)) {
        $card = $script:HardwareCards[$index]
        $stack = $card.Stack
        if (-not $stack -or $stack.Children.Count -lt 5) { continue }
        # vorheriges Bild entfernen; die Stichpunkte stehen ab dem fünften Eintrag
        if ($card.Visual) { $stack.Children.Remove($card.Visual); $card.Visual = $null }
        $visual = $null
        try { $visual = New-HwVisual ([int]$index) } catch { Write-AppError $_ }
        for ($i = 4; $i -lt $stack.Children.Count; $i++) {
            # die Akku-Zeile schaltet Update-BatteryPill selbst
            if ($script:BatteryRow -and $stack.Children[$i] -eq $script:BatteryRow.Row) { continue }
            $stack.Children[$i].Visibility = if ($visual) { 'Collapsed' } else { 'Visible' }
        }
        if ($visual) { [void]$stack.Children.Add($visual); $card.Visual = $visual }
        # ohne Bild und mit Akku-Zeile: der letzte Stichpunkt macht ihr Platz
        elseif ($script:BatteryRow -and $script:BatteryRow.Row.Tag -eq 'keep') {
            $at = $stack.Children.IndexOf($script:BatteryRow.Row)
            if ($at -gt 4) { $stack.Children[$at - 1].Visibility = 'Collapsed' }
        }
        # Zeilen, die immer bleiben (Akku in der Sensoren-Karte), stehen unter dem Bild
        foreach ($keep in @($stack.Children | Where-Object { $_.Tag -eq 'keep' })) { $stack.Children.Remove($keep); [void]$stack.Children.Add($keep) }
    }
}


function Save-HardwareResults {
    try {
        $speed = @{}
        foreach ($letter in @($script:DriveSpeed.Keys)) {
            $entry = $script:DriveSpeed[$letter]
            if ($entry -and -not $entry.Error) { $speed["$letter"] = $entry }
        }
        $cards = @{}
        foreach ($name in 'Drives', 'Memory', 'Report', 'Crashes', 'Bios', 'GameCheck', 'Battery', 'Displays', 'Ping', 'Bench', 'Input') { if ($script:CardState[$name]) { $cards[$name] = $script:CardState[$name] } }
        Save-TextFile $script:ResultsPath (@{ Stress = $script:StressResult; Speed = $speed; Cards = $cards; History = $script:History } | ConvertTo-Json -Depth 6)
    }
    catch { Write-AppError $_ }
}

function Import-HardwareResults {
    if (-not (Test-Path -LiteralPath $script:ResultsPath)) { return }
    try {
        $saved = Get-Content -LiteralPath $script:ResultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # den Verlauf liest PulsRig-Verlauf.ps1 (Import-History)
        $script:SavedHistory = $saved.History
        if ($saved.Stress -and $saved.Stress.Title) {
            $script:StressResult = @{ Title = "$($saved.Stress.Title)"; Text = "$($saved.Stress.Text)"; Tone = "$($saved.Stress.Tone)"; Time = "$($saved.Stress.Time)"; MaxGpuTemp = 0.0 }
            # ältere Dateien kennen die Höchsttemperatur nur aus dem Text des Ergebnisses
            if ($null -ne $saved.Stress.MaxCpuTemp) { $script:StressResult.MaxCpuTemp = [double]$saved.Stress.MaxCpuTemp }
            if ($null -ne $saved.Stress.MaxGpuTemp) { $script:StressResult.MaxGpuTemp = [double]$saved.Stress.MaxGpuTemp }
            elseif ("$($saved.Stress.Text)" -match '(\d+)\s*°C') { $script:StressResult.MaxGpuTemp = [double]$Matches[1] }
        }
        if ($saved.Cards) {
            foreach ($property in $saved.Cards.PSObject.Properties) {
                $entry = $property.Value
                if (-not $entry -or -not $entry.Text) { continue }
                $state = @{ Text = "$($entry.Text)"; Tone = "$($entry.Tone)"; Date = "$($entry.Date)"; Detail = "$($entry.Detail)" }
                # weitere Angaben für die Bilder auf den Karten (Balken, Steckplätze, Tage) übernehmen, wie sie sind
                foreach ($extra in $entry.PSObject.Properties) {
                    if ($extra.Name -notin 'Text', 'Tone', 'Date', 'Detail' -and $null -ne $extra.Value) { $state[$extra.Name] = $(if ($extra.Value -is [array]) { , @($extra.Value) } else { $extra.Value }) }
                }
                $script:CardState["$($property.Name)"] = $state
            }
        }
        if ($saved.Speed) {
            foreach ($property in $saved.Speed.PSObject.Properties) {
                $entry = $property.Value
                if (-not $entry -or $null -eq $entry.Read) { continue }
                $script:DriveSpeed["$($property.Name)"] = @{ Letter = "$($property.Name)"; Time = "$($entry.Time)"; Date = "$($entry.Date)"; Error = ''
                    Write = [double]$entry.Write; Read = [double]$entry.Read; Small = [double]$entry.Small; SizeMb = [double]$entry.SizeMb }
            }
        }
    }
    catch { Write-AppError $_ }
}

# Nimmt das Ergebnis einer Tempomessung an - auch dann, wenn das Fenster der Laufwerke inzwischen geschlossen wurde
function Save-DriveSpeed($Result) {
    if (-not $Result -or -not $Result.Letter) { return }
    $script:DriveSpeed["$($Result.Letter)"] = $Result
    if (-not $Result.Error) {
        Add-SpeedHistory $Result
        Save-HardwareResults
    }
    # eine neue Messung kann den Hinweis auf der Startseite ändern
    Update-DriveWarn $null
}

# Zeitpunkt einer Messung in Worten: heute nur die Uhrzeit, sonst mit Datum
function Format-SpeedWhen($Result) {
    if ($Result.Date -and $Result.Date -ne (Get-Date).ToString('dd.MM.yyyy')) { "am $($Result.Date) um $($Result.Time) Uhr" } else { "um $($Result.Time) Uhr" }
}

Import-HardwareResults

# Reihenfolge der Karten auf der Hardware-Seite (4 x 2): Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher,
# Abstürze, Bildschirm, Bericht & Diagnose, BIOS (Abstürze und BIOS stehen in PulsRig-Abstuerze.ps1, Bildschirm in PulsRig-Monitor.ps1)
Enable-HardwareCard 0 { Open-SensorSheet }
Enable-HardwareCard 1 { Open-StressSheet }
Enable-HardwareCard 2 { Open-DriveSheet }
Enable-HardwareCard 3 { Open-MemorySheet }
Enable-HardwareCard 4 { Open-CrashSheet }
Enable-HardwareCard 5 { Open-MonitorSheet }
Enable-HardwareCard 6 { Open-ReportSheet }
Enable-HardwareCard 7 { Open-BiosSheet }
Update-HardwareBadges
# beim Schließen des Programms darf der Messprozess der Grafikkarte nicht zurückbleiben
$window.Add_Closing({ try { if ($script:Stress) { [PulsRigStress]::Stop() }; Stop-Sensors } catch { } })
$ui.HardwarePill.Child.Children[1].Text = T $('Testversion')
$ui.HardwarePill.ToolTip = T $('Fehler bitte mit dem Diagnose-Paket melden')
