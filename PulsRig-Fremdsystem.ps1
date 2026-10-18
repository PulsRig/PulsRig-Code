# PulsRig - Probelauf auf einem vorgetäuschten fremden System. Wird nur im Probelauf (-Snapshot) geladen und nur, wenn
# die Umgebungsvariable PULSRIG_FREMD gesetzt ist; die Datei gehört nicht ins Paket für andere.
#   intel-notebook   Intel-Prozessor mit eingebauter Intel-Grafik, dazu eine NVIDIA-Notebook-Karte und ein Akku
#   intel-desktop    Intel-Prozessor ohne eigene Grafik, die echte Grafikkarte dieses PCs
#   intel-radeon     Intel-Prozessor mit einer Radeon-Karte, keine NVIDIA-Karte
#   karg             Büro-PC: nur die eingebaute Intel-Grafik (kein NVIDIA-Werkzeug), ein Laufwerk, ein Riegel,
#                    kein Zugriff aufs Ereignisprotokoll
#   leer             wie eine virtuelle Maschine: Windows nennt weder Laufwerke noch Riegel, Standard-Anzeigetreiber
# Vorgetäuscht werden nur die Antworten von Windows auf die Fragen nach Prozessor, Grafik, Akku, Gerät, Mainboard
# und Speicherriegeln, bei "karg" und "leer" auch nach Laufwerken und Ereignisprotokoll. Alles andere bleibt das dieses PCs.
#   offline          dieser PC ohne Internet: Windows Update, NVIDIA, AMD und der Katalog antworten nicht
#   wu-aus           dieser PC mit abgeschaltetem Dienst "Windows Update"; das Internet geht
if ("$env:PULSRIG_FREMD" -eq 'offline') {
    function global:Invoke-WebRequest { throw (New-Object Net.WebException 'Der Remotename konnte nicht aufgelöst werden.') }
    function global:Invoke-RestMethod { throw (New-Object Net.WebException 'Der Remotename konnte nicht aufgelöst werden.') }
    function global:Find-DriverUpdates { throw (New-Object Runtime.InteropServices.COMException 'Vorgetäuscht', ([int]0x80072EE7)) }
}
if ("$env:PULSRIG_FREMD" -eq 'wu-aus') {
    function global:Find-DriverUpdates { throw (New-Object Runtime.InteropServices.COMException 'Vorgetäuscht', ([int]0x80070422)) }
}
if ("$env:PULSRIG_FREMD" -in 'karg', 'leer') {
    function global:Get-WinEvent { throw 'Vorgetäuscht: kein Zugriff auf das Ereignisprotokoll.' }
    # das Werkzeug von NVIDIA gibt es auf so einem PC nicht
    function global:Test-Path {
        if ("$args" -like '*nvidia-smi.exe*') { return $false }
        Microsoft.PowerShell.Management\Test-Path @args
    }
    function global:Get-Command {
        if ("$args" -like '*nvidia-smi*') { return }
        Microsoft.PowerShell.Core\Get-Command @args
    }
}
function global:Get-CimInstance {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$ClassName, [string]$Namespace, [string]$Filter, [string[]]$Property)
    $kind = "$env:PULSRIG_FREMD"
    $storage = "$Namespace" -match 'Storage$'
    if ($kind -eq 'leer' -and ($storage -or $ClassName -eq 'MSSmBios_RawSMBiosTables')) { throw 'Vorgetäuscht: Windows gibt hier keine Auskunft.' }
    $real = @(CimCmdlets\Get-CimInstance @PSBoundParameters)
    $notebook = $kind -eq 'intel-notebook'
    if ($kind -eq 'karg' -and $storage) {
        # nur das Laufwerk, auf dem Windows liegt
        $system = "$(@(CimCmdlets\Get-CimInstance -Namespace $Namespace -ClassName MSFT_Partition | Where-Object { [int][char]$_.DriveLetter -eq 67 })[0].DiskNumber)"
        switch ($ClassName) {
            'MSFT_PhysicalDisk' { return @($real | Where-Object { "$($_.DeviceId)" -eq $system }) }
            'MSFT_Partition' { return @($real | Where-Object { "$($_.DiskNumber)" -eq $system }) }
            'MSFT_Volume' { return @($real | Where-Object { [int][char]$_.DriveLetter -eq 67 }) }
        }
    }
    if ($Namespace -or -not $kind -or $kind -in 'offline', 'wu-aus') { return $real }
    if ($kind -in 'karg', 'leer') {
        $plain = { param($item, [hashtable]$fields) $copy = $item | Select-Object *; foreach ($key in $fields.Keys) { $copy | Add-Member -NotePropertyName $key -NotePropertyValue $fields[$key] -Force }; $copy }
        switch ($ClassName) {
            'Win32_VideoController' {
                $fields = if ($kind -eq 'karg') { @{ Name = 'Intel(R) UHD Graphics 730'; VideoProcessor = 'Intel(R) UHD Graphics Family'; AdapterCompatibility = 'Intel Corporation'; DriverVersion = '31.0.101.5186'; AdapterRAM = [uint32]1073741824; PNPDeviceID = 'PCI\VEN_8086&DEV_4692&SUBSYS_7D431462&REV_0C\3&11583659&0&10' } }
                else { @{ Name = 'Microsoft Basic Display Adapter'; VideoProcessor = ''; AdapterCompatibility = '(Standardanzeigetypen)'; DriverVersion = '10.0.26100.1'; AdapterRAM = [uint32]0; PNPDeviceID = 'ROOT\BASICDISPLAY\0000' } }
                $fields.Caption = $fields.Name; $fields.Description = $fields.Name
                return @($real | Select-Object -First 1 | ForEach-Object { & $plain $_ $fields })
            }
            'Win32_Processor' {
                $fields = @{ Name = '12th Gen Intel(R) Core(TM) i5-12400'; NumberOfCores = 6; NumberOfLogicalProcessors = 12; SocketDesignation = 'LGA1700'; MaxClockSpeed = 2500; Manufacturer = 'GenuineIntel' }
                return @($real | Select-Object -First 1 | ForEach-Object { & $plain $_ $fields })
            }
            'Win32_ComputerSystem' {
                $fields = if ($kind -eq 'leer') { @{ Manufacturer = 'innotek GmbH'; Model = 'VirtualBox' } } else { @{ Manufacturer = 'Micro-Star International Co., Ltd.'; Model = 'MS-7D43' } }
                return @($real | ForEach-Object { & $plain $_ $fields })
            }
            'Win32_BaseBoard' {
                $fields = if ($kind -eq 'leer') { @{ Manufacturer = 'Oracle Corporation'; Product = 'VirtualBox' } } else { @{ Manufacturer = 'Micro-Star International Co., Ltd.'; Product = 'PRO B660M-A DDR4 (MS-7D43)' } }
                return @($real | ForEach-Object { & $plain $_ $fields })
            }
            'Win32_PhysicalMemory' {
                if ($kind -eq 'leer') { return }
                return @($real | Select-Object -First 1)
            }
            'Win32_PhysicalMemoryArray' { if ($kind -eq 'leer') { return } }
        }
        return $real
    }
    # eine Kopie mit geänderten Feldern; die Kopie ist ein einfaches Objekt und trägt alle Felder des Originals
    $change = {
        param($item, [hashtable]$fields)
        $copy = $item | Select-Object *
        foreach ($key in $fields.Keys) { $copy | Add-Member -NotePropertyName $key -NotePropertyValue $fields[$key] -Force }
        $copy
    }
    switch ($ClassName) {
        'Win32_Processor' {
            $fields = if ($notebook) { @{ Name = '12th Gen Intel(R) Core(TM) i7-12700H'; NumberOfCores = 14; NumberOfLogicalProcessors = 20; SocketDesignation = 'U3E1'; MaxClockSpeed = 2300 } }
            else { @{ Name = '12th Gen Intel(R) Core(TM) i5-12400F'; NumberOfCores = 6; NumberOfLogicalProcessors = 12; SocketDesignation = 'LGA1700'; MaxClockSpeed = 2500 } }
            $fields.Manufacturer = 'GenuineIntel'; $fields.Caption = 'Intel64 Family 6 Model 154 Stepping 3'; $fields.Description = $fields.Caption
            return @($real | Select-Object -First 1 | ForEach-Object { & $change $_ $fields })
        }
        'Win32_VideoController' {
            $cards = @($real)
            if ($kind -eq 'intel-radeon') {
                return @($cards | ForEach-Object { & $change $_ @{ Name = 'AMD Radeon RX 6700 XT'; Caption = 'AMD Radeon RX 6700 XT'; Description = 'AMD Radeon RX 6700 XT'; VideoProcessor = 'AMD Radeon Graphics Processor (0x73DF)'
                            AdapterCompatibility = 'Advanced Micro Devices, Inc.'; DriverVersion = '32.0.21030.2001'; PNPDeviceID = 'PCI\VEN_1002&DEV_73DF&SUBSYS_23301DA2&REV_C1\6&2A3C8B7&0&00000019' } })
            }
            if ($notebook) {
                $own = & $change $cards[0] @{ Name = 'Intel(R) Iris(R) Xe Graphics'; Caption = 'Intel(R) Iris(R) Xe Graphics'; Description = 'Intel(R) Iris(R) Xe Graphics'; VideoProcessor = 'Intel(R) Iris(R) Xe Graphics Family'
                    AdapterCompatibility = 'Intel Corporation'; DriverVersion = '31.0.101.5186'; AdapterRAM = [uint32]1073741824; PNPDeviceID = 'PCI\VEN_8086&DEV_46A6&SUBSYS_3B2F17AA&REV_0C\3&11583659&0&10' }
                $extra = @($cards | ForEach-Object { & $change $_ @{ Name = 'NVIDIA GeForce RTX 3060 Laptop GPU'; Caption = 'NVIDIA GeForce RTX 3060 Laptop GPU'; Description = 'NVIDIA GeForce RTX 3060 Laptop GPU'; VideoProcessor = 'NVIDIA GeForce RTX 3060 Laptop GPU' } })
                return @($own) + $extra
            }
            return $cards
        }
        'Win32_Battery' {
            if ($notebook) { return [pscustomobject]@{ Name = 'L21M4PC2'; DeviceID = '1'; BatteryStatus = 2; EstimatedChargeRemaining = 78; Status = 'OK' } }
            return
        }
        'Win32_ComputerSystem' {
            $fields = if ($notebook) { @{ Manufacturer = 'LENOVO'; Model = '82RG'; PCSystemType = 2; SystemFamily = 'Legion 5 15IAH7H' } } else { @{ Manufacturer = 'Micro-Star International Co., Ltd.'; Model = 'MS-7D43' } }
            return @($real | ForEach-Object { & $change $_ $fields })
        }
        'Win32_BaseBoard' {
            $fields = if ($notebook) { @{ Manufacturer = 'LENOVO'; Product = 'LNVNB161216' } } else { @{ Manufacturer = 'Micro-Star International Co., Ltd.'; Product = 'PRO B660M-A DDR4 (MS-7D43)' } }
            return @($real | ForEach-Object { & $change $_ $fields })
        }
        'Win32_PhysicalMemory' {
            if ($notebook) { $n = 0; return @($real | ForEach-Object { & $change $_ @{ FormFactor = 12; BankLabel = "BANK $($n * 2)"; DeviceLocator = "Controller$n-ChannelA-DIMM0" }; $n++ }) }
            return $real
        }
    }
    $real
}
