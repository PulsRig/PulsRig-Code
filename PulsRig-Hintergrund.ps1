# PulsRig - Arbeit ohne Fenster für den Helfer neben der Uhr. PulsRig.exe startet dieses Skript mit
#   -Boost Ein [-Spiel Name]   Boost einschalten (Energieplan, Dienste, Spielmodus - Programme schließt er nie)
#   -Boost Aus                 Boost ausschalten und alles zurückstellen
#   -Wochenscan                bei Windows Update (und NVIDIA) nach neueren Treibern sehen
# Es gibt nichts aus und fragt nichts; was es tut, steht in PulsRig-Hintergrund.log neben den Einstellungen.
# Das Ergebnis ist eine Zahl: beim Wochenscan die Zahl neuer Treiber, sonst 0.
#
# Der Helfer kann mit Adminrechten laufen, die Einstellungen liegen im Benutzerordner. Deshalb nimmt der Boost hier
# nur Dienste aus der eingebauten Liste entbehrlicher Dienste und Dienste anderer Hersteller (Programmdatei außerhalb
# des Windows-Ordners) - eine veränderte Einstellungsdatei kann so keine Dienste von Windows anhalten lassen.
param([string]$Aufgabe, [string]$Wert, [string]$Spiel)

$ErrorActionPreference = 'Stop'
$files = $PulsRigEmbedded
$root = if ($PulsRigRoot) { "$PulsRigRoot" } else { Split-Path -Parent $PSCommandPath }
function Get-AppText([string]$Name) {
    if ($files -and $files.ContainsKey($Name)) { return $files[$Name] }
    [IO.File]::ReadAllText((Join-Path $root $Name), [Text.Encoding]::UTF8)
}
$installed = $root.StartsWith([Environment]::GetFolderPath('ProgramFiles'), [StringComparison]::OrdinalIgnoreCase)
$target = if ($installed) { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PulsRig' } else { Join-Path $root 'Treiber' }
if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
$script:HintergrundLog = Join-Path $target 'PulsRig-Hintergrund.log'
try { if ((Get-Item -LiteralPath $script:HintergrundLog -ErrorAction Stop).Length -gt 256KB) { Remove-Item -LiteralPath $script:HintergrundLog -Force } } catch { }

# Ausgaben ins Protokoll, Rückfragen beantwortet: Hauptschritte ja, Zusatzschritte nein
function global:Write-Host {
    param([Parameter(Position = 0, ValueFromRemainingArguments = $true)] $Object, $ForegroundColor, $BackgroundColor, $Separator, [switch]$NoNewline)
    $text = (@($Object) | ForEach-Object { "$_" }) -join ' '
    try { Add-Content -LiteralPath $script:HintergrundLog -Value ('{0:dd.MM. HH:mm:ss}  {1}' -f (Get-Date), $text) -Encoding UTF8 } catch { }
}
function global:Write-Progress { }
function global:Read-Host { '' }
function global:Confirm-Action([string]$Question, [switch]$Optional) { -not $Optional }

# nur die Funktionen der beiden Skripte laden
$global:DD_Embedded = $true
$global:DD_ProgramDir = $root
. ([scriptblock]::Create((Get-AppText 'Treiber-Scan.ps1')))
. ([scriptblock]::Create((Get-AppText 'Treiber-Werkzeuge.ps1')))
$global:OutDir = $target
$global:DryRun = $false
$global:Yes = $true

$settings = $null
try { $settings = Get-Content -LiteralPath (Join-Path $target 'PulsRig-Einstellungen.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
$statePath = Join-Path $target 'Spiel-Beschleunigung.json'
Write-Host "=== $Aufgabe $Wert $Spiel ==="

switch ($Aufgabe) {
    'Boost' {
        if ($Wert -eq 'Aus') {
            if (Test-Path -LiteralPath $statePath) { Invoke-GameBoostTool }
            return 0
        }
        if (Test-Path -LiteralPath $statePath) { return 0 }   # ist schon an
        $plan = if ($settings) { $settings.Boost } else { $null }
        # eine leere Auswahl heißt "keine Dienste" (aus der Einstellungsdatei kommt sie als leere Liste, nicht als $null)
        $wanted = @(if ($plan -and $plan.PSObject.Properties['Services'] -and $null -ne $plan.Services) { @($plan.Services) } else { $script:BoostServices }) | Where-Object { "$_" -match '^[\w.\- ]{1,80}$' }
        $allowed = @(foreach ($name in $wanted) {
                if ($script:BoostServices -contains $name) { $name; continue }
                try {
                    $service = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction Stop
                    if ($service -and "$($service.PathName)" -and "$($service.PathName)" -notmatch [regex]::Escape($env:WINDIR)) { $name }
                }
                catch { }
            })
        # Programme schließt der automatische Boost nie: darin kann Ungespeichertes stecken
        $global:BoostPlan = @{ Apps = @(); Services = $allowed; Clipboard = $false
            PowerPlan = $(if ($plan) { [bool]$plan.PowerPlan } else { $true }); GameMode = $(if ($plan) { [bool]$plan.GameMode } else { $true }) }
        Invoke-GameBoostTool
        # für die Boost-Seite festhalten, für welches Spiel er an ist
        if ($Spiel -and (Test-Path -LiteralPath $statePath)) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $state | Add-Member -NotePropertyName Game -NotePropertyValue $Spiel -Force
                $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
            }
            catch { }
        }
        return 0
    }
    'Wochenscan' {
        $ignored = @(if ($settings) { @($settings.Ignored) | ForEach-Object { "$($_.Key)" } })
        $names = @()
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'PulsRig'
        foreach ($item in @(Find-DriverUpdates $session)) {
            $update = $item.Update
            if ((Test-IsFirmware $update) -and -not ($settings -and $settings.Firmware)) { continue }
            if ($ignored -contains "wu:$($update.DriverHardwareID)|$($update.Title)") { continue }
            # was NVIDIA selbst liefert, zählt unten
            if ($settings -and $settings.Nvidia -and $update.DriverClass -eq 'Display' -and "$($update.Title) $($update.DriverProvider)" -match 'NVIDIA') { continue }
            $names += "$($update.Title)"
        }
        if (-not $settings -or $settings.Nvidia) {
            try {
                $nvidia = Get-NvidiaUpdate
                if ($nvidia -and $nvidia.IsNewer -and $ignored -notcontains "nvidia:$($nvidia.Latest)") { $names += "NVIDIA $($nvidia.Latest)" }
            }
            catch { Write-Host "NVIDIA: $($_.Exception.Message)" }
            # Chipsatz-Treiber von AMD: lädt PulsRig nicht selbst, ist aber eine Meldung wert
            try {
                $amd = Get-AmdChipsetUpdate
                if ($amd -and $amd.IsNewer -and $ignored -notcontains "amd:$($amd.Latest)") { $names += "AMD-Chipsatz $($amd.Latest)" }
            }
            catch { Write-Host "AMD: $($_.Exception.Message)" }
        }
        @{ Time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Count = $names.Count; Names = $names } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $target 'PulsRig-Hintergrund-Scan.json') -Encoding UTF8
        Write-Host "Neuere Treiber: $($names.Count)"
        return $names.Count
    }
}
