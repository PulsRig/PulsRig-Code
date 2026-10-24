# PulsRig - Grafiktreiber vor Windows Update schützen. Wird von PulsRig.ps1 nach PulsRig-Autostart.ps1 eingebunden.
#
# Gezielt und umkehrbar: je Grafikkarte ein Schalter. "Schützen" versteckt die Angebote von Windows Update für genau
# diese Karte (Klasse Display, passende Geräte-ID), "Freigeben" zeigt sie wieder. Keine Richtlinie, keine Gerätesperre:
# Treiber von NVIDIA oder AMD lassen sich weiter installieren, alle anderen Geräte bekommen weiter ihre Updates.
# Später neu angebotene Treiber versteckt der nächste Scan oder der Wochenscan des Helfers (Liste in GpuShield).
# Die Funktionen dazu stehen in Treiber-Scan.ps1 (Get-ShieldGpus, Find-GpuDriverOffers, Set-GpuShield).

$script:Queries.GpuShield = @'
param($a)
$r = @{ Gpus = @(Get-ShieldGpus); Hidden = @{}; Offered = @{}; Changed = @(); Error = '' }
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'PulsRig'
    if ($a.Key) { $r.Changed = @(Set-GpuShield $session @($a.Key) ([bool]$a.On)) }
    $keys = @($r.Gpus | ForEach-Object { $_.Key })
    foreach ($hidden in $true, $false) {
        foreach ($update in @(Find-GpuDriverOffers $session $keys $hidden)) {
            $key = Get-GpuShieldKey "$($update.DriverHardwareID)"
            $list = if ($hidden) { $r.Hidden } else { $r.Offered }
            if (-not $list.ContainsKey($key)) { $list[$key] = @() }
            $list[$key] += "$($update.Title)"
        }
    }
}
catch { $r.Error = Get-UpdateErrorText $_ }
$r
'@

function Open-GpuShieldSheet {
    $opened = Open-Sheet @{
        Title    = 'Grafiktreiber schützen'
        Sub      = 'Windows Update soll den Grafiktreiber nicht überschreiben'
        Glyph    = 0xEA18
        Link     = 'Neu einlesen'
        Show     = { param($tab) Show-GpuShieldList }
        OnAction = { param($item) if ($item.Data) { Switch-GpuShield $item.Data } }
        OnLink   = { Start-GpuShieldQuery $null }
    }
    if (-not $opened) { return }
    Start-GpuShieldQuery $null
}

function Start-GpuShieldQuery($Argument) {
    $script:Sheet.GpuShield = $null
    $ui.SheetChips.Children.Clear()
    Start-SheetLoader 'Frage Windows Update nach Grafiktreibern …'
    Start-Query 'GpuShield' { param($result) Complete-GpuShieldQuery $result } $Argument
}

function Complete-GpuShieldQuery($Result) {
    if (-not $script:Sheet) { return }
    $script:Sheet.GpuShield = $Result
    $ui.SheetChips.Children.Clear()
    $on = @($Result.Gpus | Where-Object { $script:Settings.GpuShield -contains $_.Key }).Count
    Add-ResultChip $(if ($on) { "$on geschützt" } else { 'Kein Schutz' }) $(if ($on) { 'Good' } else { 'Accent' }) $ui.SheetChips
    Show-GpuShieldList
}

function Show-GpuShieldList {
    $data = $script:Sheet.GpuShield
    if (-not $data) { Start-SheetLoader 'Frage Windows Update nach Grafiktreibern …'; return }
    $rows = @()
    if (@($data.Gpus).Count -eq 0) {
        $rows += New-SheetRow -Title 'Keine Grafikkarte gefunden' -Sub 'Windows meldet keine Grafikkarte mit eigener Geräte-ID.' -Glyph 0xE7F4
    }
    foreach ($gpu in @($data.Gpus)) {
        $on = $script:Settings.GpuShield -contains $gpu.Key
        $hidden = @($data.Hidden[$gpu.Key] | Where-Object { $_ }).Count
        $offered = @($data.Offered[$gpu.Key] | Where-Object { $_ }).Count
        $parts = @("Treiber $($gpu.Version)")
        if ($hidden) { $parts += $(if ($hidden -eq 1) { '1 Angebot von Windows Update zurückgehalten' } else { "$hidden Angebote von Windows Update zurückgehalten" }) }
        if ($offered) { $parts += $(if ($offered -eq 1) { '1 Angebot von Windows Update offen' } else { "$offered Angebote von Windows Update offen" }) }
        if (-not $hidden -and -not $offered -and -not $data.Error) { $parts += 'Windows Update bietet gerade nichts an' }
        $parts += $(if ($on) { 'Neue Angebote versteckt PulsRig beim Scan' } else { 'Windows Update darf den Treiber ersetzen' })
        $rows += New-SheetRow -Title $gpu.Name -Sub ($parts -join ' · ') -Glyph 0xE7F4 -Tone $(if ($on) { 'good' } elseif ($offered) { 'warn' } else { 'accent' }) `
            -State $(if ($on) { 'geschützt' } else { 'offen' }) -Action $(if (-not $script:IsAdmin) { '' } elseif ($on) { 'Freigeben' } else { 'Schützen' }) -Data @{ Key = $gpu.Key; On = -not $on }
    }
    if (-not $script:IsAdmin) {
        $rows += New-SheetRow -Title 'Schützen und Freigeben gehen nur mit Adminrechten' -Sub 'Windows Update lässt Angebote nur von Admins verstecken.' -Glyph 0xE72E -Action 'Als Admin neu starten' -Data @{ Admin = $true }
    }
    if ($data.Error) { $rows += New-SheetRow -Title 'Windows Update war nicht erreichbar' -Sub $data.Error -Glyph 0xE783 -Tone 'warn' }
    $rows += New-SheetRow -Title 'So funktioniert der Schutz' -Glyph 0xE946 `
        -Sub 'PulsRig versteckt nur die Angebote für diese Grafikkarte, wie Microsofts Werkzeug „Updates anzeigen oder ausblenden“. Treiber von NVIDIA oder AMD lassen sich weiter installieren; Freigeben macht alles rückgängig.'
    Show-SheetList $rows
    Set-SheetStateText $(if (@($data.Changed).Count) { "Geändert: $(Join-Names @($data.Changed) 2)" } else { 'Andere Geräte bekommen ihre Treiber weiter von Windows Update' })
}

function Switch-GpuShield($Data) {
    if ($Data.Admin) { Restart-Elevated; $window.Close(); return }
    if (-not $Data.Key) { return }
    $script:Settings.GpuShield = @(@($script:Settings.GpuShield | Where-Object { $_ -ne $Data.Key }) + @(if ($Data.On) { $Data.Key }))
    Save-Settings
    Start-GpuShieldQuery @{ Key = $Data.Key; On = [bool]$Data.On }
}
