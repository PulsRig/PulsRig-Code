# PulsRig - Autostart: Programme, die beim Anmelden mit Windows starten, anzeigen und ein- oder ausschalten.
# Wird von PulsRig.ps1 eingebunden und nutzt dessen großes Fenster mit Listen und den Arbeitsbereich.
#
# Ausgeschaltet wird wie im Task-Manager von Windows: Der Eintrag bleibt, wo er ist, und Windows bekommt unter
# "StartupApproved" vermerkt, dass er nicht starten soll. Das lässt sich jederzeit zurücknehmen, auch im Task-Manager.
# Einträge für alle Benutzer (HKLM, gemeinsamer Autostart-Ordner) lassen sich nur mit Adminrechten umschalten.
# Nicht erfasst: Aufgaben der Aufgabenplanung und Dienste - die zeigt der Task-Manager auch nicht unter "Autostart".

$script:AutostartApproved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

# Läuft im Arbeitsbereich: liest die Einträge samt Zustand, Hersteller und Beschreibung der Programmdatei
$script:Queries.Autostart = @'
param($a)
$approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
function Get-Root([string]$Hive) { if ($Hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine } }
# eingeschaltet, solange Windows nichts anderes vermerkt hat; ein ungerades erstes Byte heißt "ausgeschaltet"
function Test-Approved([string]$Hive, [string]$Folder, [string]$Name) {
    $key = $null
    try {
        $key = (Get-Root $Hive).OpenSubKey("$approved\$Folder")
        if (-not $key) { return $true }
        $bytes = $key.GetValue($Name)
        if ($bytes -isnot [byte[]] -or $bytes.Length -eq 0) { return $true }
        ($bytes[0] -band 1) -eq 0
    }
    catch { $true }
    finally { if ($key) { $key.Close() } }
}
# die Programmdatei aus einer Befehlszeile: in Anführungszeichen oder bis ".exe"
function Get-CommandFile([string]$Command) {
    $text = [Environment]::ExpandEnvironmentVariables("$Command".Trim())
    if ($text -match '^"([^"]+)"') { return $Matches[1] }
    if ($text -match '^(.+?\.exe)\b') { return $Matches[1] }
    ($text -split ' ')[0]
}
function New-Entry([string]$Name, [string]$Command, [string]$File, [string]$Hive, [string]$Folder, [string]$Where) {
    $company = ''; $description = ''
    try {
        if ($File -and (Test-Path -LiteralPath $File)) {
            $info = (Get-Item -LiteralPath $File).VersionInfo
            $company = "$($info.CompanyName)".Trim(); $description = "$($info.FileDescription)".Trim()
        }
    }
    catch { }
    @{ Name = $Name; Command = "$Command"; File = "$File"; Company = $company; Description = $description; Hive = $Hive; Folder = $Folder
        Where = $Where; Enabled = (Test-Approved $Hive $Folder $Name); Exists = [bool]($File -and (Test-Path -LiteralPath $File)) }
}

$entries = @()
foreach ($source in @(
        @{ Hive = 'HKCU'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Folder = 'Run'; Where = 'Benutzer' },
        @{ Hive = 'HKLM'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Folder = 'Run'; Where = 'Alle Benutzer' },
        @{ Hive = 'HKLM'; Key = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Folder = 'Run32'; Where = 'Alle Benutzer' })) {
    $key = $null
    try {
        $key = (Get-Root $source.Hive).OpenSubKey($source.Key)
        if (-not $key) { continue }
        foreach ($name in $key.GetValueNames()) {
            if (-not $name) { continue }
            $command = "$($key.GetValue($name))"
            $entries += New-Entry $name $command (Get-CommandFile $command) $source.Hive $source.Folder $source.Where
        }
    }
    catch { }
    finally { if ($key) { $key.Close() } }
}
# Verknüpfungen in den Autostart-Ordnern: das Ziel der Verknüpfung ist die Programmdatei
$shell = $null
try { $shell = New-Object -ComObject WScript.Shell } catch { }
foreach ($source in @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Hive = 'HKCU'; Where = 'Benutzer' },
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Hive = 'HKLM'; Where = 'Alle Benutzer' })) {
    if (-not $source.Path -or -not (Test-Path -LiteralPath $source.Path)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $source.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $target = $file.FullName
        if ($file.Extension -eq '.lnk' -and $shell) { try { $target = $shell.CreateShortcut($file.FullName).TargetPath } catch { } }
        $entries += New-Entry $file.Name $file.FullName $target $source.Hive 'StartupFolder' $source.Where
    }
}
@{ Entries = $entries; Admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
'@

# Schaltet einen Eintrag ein oder aus: so, wie es der Task-Manager tut (erstes Byte 2 = an, 3 = aus, dazu der Zeitpunkt)
function Set-AutostartEntry($Entry, [bool]$On) {
    $root = if ($Entry.Hive -eq 'HKCU') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
    $key = $root.CreateSubKey("$script:AutostartApproved\$($Entry.Folder)")
    try {
        $bytes = New-Object byte[] 12
        $bytes[0] = if ($On) { 2 } else { 3 }
        if (-not $On) { [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($bytes, 4) }
        $key.SetValue($Entry.Name, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
    }
    finally { $key.Close() }
}

# der Name, unter dem man ein Programm kennt: Beschreibung der Programmdatei, sonst der Name des Eintrags
function Get-AutostartTitle($Entry) {
    $name = "$($Entry.Name)" -replace '\.lnk$', ''
    if ($Entry.Description -and $Entry.Description.Length -le 40) { $Entry.Description } else { $name }
}

function Open-AutostartSheet {
    $opened = Open-Sheet @{
        Title    = 'Autostart'
        Sub      = 'Programme, die beim Anmelden mit Windows starten'
        Glyph    = 0xE7E8
        Link     = 'Neu einlesen'
        Search   = $true
        Show     = { param($tab) Show-AutostartList }
        OnCheck  = { param($item) Switch-AutostartEntry $item }
        OnLink   = { Start-SheetLoader 'Lese den Autostart …'; Start-Query 'Autostart' { param($result) Complete-AutostartQuery $result } }
    }
    if (-not $opened) { return }
    Start-SheetLoader 'Lese den Autostart …'
    Start-Query 'Autostart' { param($result) Complete-AutostartQuery $result }
}

function Complete-AutostartQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.Autostart = $Result
    Show-AutostartList
}

function Show-AutostartList {
    $data = $script:Sheet.Autostart
    if (-not $data) { return }
    $entries = @($data.Entries | Sort-Object @{ Expression = { -not $_.Enabled } }, @{ Expression = { Get-AutostartTitle $_ } })
    $ui.SheetChips.Children.Clear()
    $active = @($entries | Where-Object { $_.Enabled }).Count
    Add-ResultChip $(if ($entries.Count -eq 1) { '1 Eintrag' } else { "$($entries.Count) Einträge" }) 'Accent' $ui.SheetChips
    Add-ResultChip "$active eingeschaltet" 'Good' $ui.SheetChips
    $rows = @()
    if ($entries.Count -eq 0) { $rows += New-SheetRow -Title 'Beim Anmelden startet kein Programm von selbst' -Glyph 0xE73E }
    else {
        $rows += New-SheetRow -Kind 'head' -Title 'STARTET BEIM ANMELDEN'
        foreach ($entry in $entries) {
            $parts = @($(if ($entry.Company) { $entry.Company }), $(if ($entry.File) { Split-Path -Leaf $entry.File }), $entry.Where) | Where-Object { $_ }
            if (-not $entry.Exists) { $parts += 'Programmdatei fehlt' }
            $locked = $entry.Hive -eq 'HKLM' -and -not $data.Admin
            $rows += New-SheetRow -Title (Get-AutostartTitle $entry) -Sub ($parts -join ' · ') -Glyph 0xE7E8 -Checkable -Checked ([bool]$entry.Enabled) `
                -State $(if ($locked) { 'nur mit Adminrechten' } elseif ($entry.Enabled) { 'an' } else { 'aus' }) -Tone $(if ($entry.Enabled) { 'good' } else { '' }) -Data $entry
        }
    }
    Show-SheetList $rows
    Set-SheetStateText 'Ein Haken heißt: startet mit Windows. Wirkt ab der nächsten Anmeldung.'
}

# Häkchen gesetzt oder entfernt: sofort umschalten; ohne Rechte bleibt es, wie es war
function Switch-AutostartEntry($Item) {
    $entry = $Item.Data
    if (-not $entry) { return }
    $on = [bool]$Item.Checked
    try {
        if ($entry.Hive -eq 'HKLM' -and -not $script:Sheet.Autostart.Admin) { throw 'Adminrechte' }
        Set-AutostartEntry $entry $on
        $entry.Enabled = $on
        Show-AutostartList
        Set-SheetStateText $(if ($on) { "$(Get-AutostartTitle $entry) startet wieder mit Windows" } else { "$(Get-AutostartTitle $entry) startet nicht mehr mit Windows" })
    }
    catch {
        Show-AutostartList
        Set-SheetStateText 'Einträge für alle Benutzer lassen sich nur mit Adminrechten umschalten'
    }
}
