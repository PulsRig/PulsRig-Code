<#
.SYNOPSIS
    Installiert PulsRig nach "C:\Program Files\PulsRig" (oder entfernt es wieder).

.DESCRIPTION
    PulsRig arbeitet mit Adminrechten. Liegt es in einem Ordner, in den jedes Programm schreiben darf, könnte ein
    fremdes Programm die Skripte ändern und käme so beim nächsten Start selbst an Adminrechte. Unter "Programme"
    darf nur ein Admin schreiben - deshalb gehört PulsRig dorthin, sobald es auf mehr als dem eigenen PC läuft.

    Einstellungen, Ergebnisse und geladene Treiber liegen nach der Installation im Benutzerordner
    (%LOCALAPPDATA%\PulsRig); vorhandene Einstellungen werden einmalig dorthin übernommen.

.PARAMETER Ziel
    Zielordner. Vorgabe: "PulsRig" unter "Programme".

.PARAMETER Entfernen
    Entfernt Programmordner und Verknüpfungen. Einstellungen und geladene Treiber bleiben.

.PARAMETER Zertifikat
    Fingerabdruck eines Zertifikats zur Codesignatur (aus dem Zertifikatspeicher). Damit werden die installierten
    Skripte signiert, und die Verknüpfung startet PulsRig so, dass nur signierte Skripte laufen.

.PARAMETER OhneVerknuepfung
    Legt keine Verknüpfungen an (zum Prüfen in einem Testordner).
#>
[CmdletBinding()]
param(
    [string]$Ziel = (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'PulsRig'),
    [switch]$Entfernen,
    [string]$Zertifikat,
    [switch]$OhneVerknuepfung
)

$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSCommandPath
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$startMenu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'PulsRig.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'PulsRig.lnk'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# unter "Programme" und für Verknüpfungen aller Benutzer braucht es Adminrechte: einmal nachfragen und neu starten
$needsAdmin = $Ziel.StartsWith($programFiles, [StringComparison]::OrdinalIgnoreCase) -or -not $OhneVerknuepfung
if ($needsAdmin -and -not (Test-IsAdmin)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Ziel', "`"$Ziel`"")
    if ($Entfernen) { $arguments += '-Entfernen' }
    if ($Zertifikat) { $arguments += @('-Zertifikat', $Zertifikat) }
    if ($OhneVerknuepfung) { $arguments += '-OhneVerknuepfung' }
    try { Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $arguments }
    catch { Write-Host 'Ohne Adminrechte lässt sich PulsRig nicht nach "Programme" installieren.' -ForegroundColor Yellow }
    return
}

try {
    # nie einen Ordner anfassen, der nicht eindeutig der von PulsRig ist
    if ((Split-Path -Leaf $Ziel) -notmatch 'PulsRig') { throw "Der Zielordner muss `"PulsRig`" im Namen tragen: $Ziel" }

    if ($Entfernen) {
        if (Test-Path -LiteralPath $Ziel) {
            if (-not (Test-Path -LiteralPath (Join-Path $Ziel 'PulsRig.ps1'))) { throw "In $Ziel liegt kein PulsRig - nichts entfernt." }
            Remove-Item -LiteralPath $Ziel -Recurse -Force -Confirm:$false
            Write-Host "Entfernt: $Ziel"
        }
        foreach ($link in $startMenu, $desktop) {
            if (-not $OhneVerknuepfung -and (Test-Path -LiteralPath $link)) { Remove-Item -LiteralPath $link -Confirm:$false; Write-Host "Entfernt: $link" }
        }
        Write-Host 'PulsRig ist entfernt. Einstellungen und geladene Treiber liegen weiter unter %LOCALAPPDATA%\PulsRig.' -ForegroundColor Green
    }
    else {
        if ([IO.Path]::GetFullPath($Ziel).TrimEnd('\') -ieq $source.TrimEnd('\')) { throw 'Quelle und Ziel sind derselbe Ordner.' }
        if (-not (Test-Path -LiteralPath $Ziel)) { New-Item -ItemType Directory -Path $Ziel -Force | Out-Null }

        # nur die Dateien des Programms - keine Sicherungen, Berichte oder Testskripte
        $files = @(Get-ChildItem -LiteralPath $source -File | Where-Object {
                $_.Name -match '^(PulsRig.*\.(ps1|xaml|bat|cs|ico)|Treiber-(Scan|Werkzeuge)\.ps1|Treiber-Scan\.bat|PulsRig-(Testzettel|Bau)\.txt)$' -and
                $_.Name -notin 'PulsRig-Tests.ps1', 'PulsRig-Paket.ps1'
            })
        if (-not ($files | Where-Object { $_.Name -eq 'PulsRig.ps1' })) { throw "Neben diesem Skript liegt kein PulsRig.ps1: $source" }
        foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $Ziel $file.Name) -Force }
        # LibreHardwareMonitor für die Temperatur des Prozessors
        $sensors = Join-Path $source 'Sensoren'
        if (Test-Path -LiteralPath $sensors) {
            $target = Join-Path $Ziel 'Sensoren'
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -Confirm:$false }
            Copy-Item -LiteralPath $sensors -Destination $target -Recurse
        }
        Write-Host "Installiert: $($files.Count) Dateien nach $Ziel"

        $policy = 'Bypass'
        if ($Zertifikat) {
            $certificate = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert |
                Where-Object { $_.Thumbprint -eq ($Zertifikat -replace '\s', '') } | Select-Object -First 1
            if (-not $certificate) { throw "Kein Zertifikat zur Codesignatur mit dem Fingerabdruck $Zertifikat gefunden." }
            foreach ($script in @(Get-ChildItem -LiteralPath $Ziel -Filter '*.ps1' -File)) {
                $result = Set-AuthenticodeSignature -LiteralPath $script.FullName -Certificate $certificate -HashAlgorithm SHA256
                if ($result.Status -ne 'Valid') { throw "Signieren fehlgeschlagen: $($script.Name) ($($result.StatusMessage))" }
            }
            $policy = 'AllSigned'
            Write-Host "Signiert mit: $($certificate.Subject)"
        }

        if (-not $OhneVerknuepfung) {
            $shell = New-Object -ComObject WScript.Shell
            foreach ($link in $startMenu, $desktop) {
                $shortcut = $shell.CreateShortcut($link)
                $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
                $shortcut.Arguments = "-NoProfile -ExecutionPolicy $policy -WindowStyle Hidden -File `"$(Join-Path $Ziel 'PulsRig.ps1')`""
                $shortcut.WorkingDirectory = $Ziel
                $shortcut.Description = 'PulsRig – Treiber, Boost, Werkzeuge'
                $shortcut.WindowStyle = 7
                if (Test-Path -LiteralPath (Join-Path $Ziel 'PulsRig.ico')) { $shortcut.IconLocation = (Join-Path $Ziel 'PulsRig.ico') }
                $shortcut.Save()
            }
            Write-Host 'Verknüpfungen im Startmenü und auf dem Desktop angelegt.'
        }

        # vorhandene Einstellungen und Ergebnisse einmalig in den Benutzerordner übernehmen
        if ($Ziel.StartsWith($programFiles, [StringComparison]::OrdinalIgnoreCase)) {
            $data = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PulsRig'
            if (-not (Test-Path -LiteralPath $data)) { New-Item -ItemType Directory -Path $data -Force | Out-Null }
            foreach ($name in 'PulsRig-Einstellungen.json', 'PulsRig-Ergebnisse.json') {
                $old = Join-Path (Join-Path $source 'Treiber') $name
                $new = Join-Path $data $name
                if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $new)) { Copy-Item -LiteralPath $old -Destination $new; Write-Host "Übernommen: $name" }
            }
        }
        Write-Host 'PulsRig ist installiert. Der alte Ordner wird nicht mehr gebraucht und kann gelöscht werden.' -ForegroundColor Green
    }
}
catch {
    Write-Host "Fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    $failed = $true
}
if ($needsAdmin -and -not $OhneVerknuepfung) { Write-Host ''; [void](Read-Host 'Eingabetaste schließt das Fenster') }
if ($failed) { exit 1 }
