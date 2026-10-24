# PulsRig - Arbeitsbereich: Neuinstallations-Begleiter. Wird von PulsRig.ps1 als Text geladen.
# Save:     Ordner "Neuinstallation_<Datum>" mit Offline-Treiberpaket und Programmliste (winget export) anlegen
# Drivers:  Treiber aus so einem Ordner wieder einspielen (nur mit Adminrechten)
# Programs: ausgewählte Programme der Liste per winget installieren
param($a)
$global:DryRun = [bool]$a.DryRun
$script:ExitCode = 0
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if ($a.Mode -eq 'Save') {
    $root = Join-Path $a.TargetDir ('Neuinstallation_{0:yyyy-MM-dd_HHmm}' -f (Get-Date))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Write-Host 'Schritt 1 von 2: Treiber' -ForegroundColor Cyan
    New-OfflinePackage $root
    Write-Host ''
    Write-Host 'Schritt 2 von 2: Programmliste' -ForegroundColor Cyan
    $list = Join-Path $root 'Programme.json'
    $count = 0
    if (-not $winget) {
        Write-Host 'winget fehlt auf diesem PC (App-Installer aus dem Microsoft Store) - die Programmliste wird ausgelassen.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Lese die installierten Programme, die winget kennt ...'
        # nur die Quelle "winget": der Microsoft Store verlangt eine eigene Zustimmung und Anmeldung
        $null = & $winget.Source export -o $list -s winget --accept-source-agreements --disable-interactivity 2>&1
        if (Test-Path -LiteralPath $list) {
            try { $count = @((Get-Content -LiteralPath $list -Raw | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages }).Count } catch { }
            Write-Host "$count Programme in der Liste." -ForegroundColor Green
        }
        else {
            Write-Host "Die Programmliste ließ sich nicht schreiben (winget-Code $LASTEXITCODE)." -ForegroundColor Red
            $script:ExitCode = 1
        }
    }
    $readme = @(
        "Sicherung für eine Neuinstallation vom $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        ''
        '1. Diesen Ordner vor der Neuinstallation auf einen USB-Stick oder ein anderes Laufwerk kopieren.'
        '2. Nach der Neuinstallation PulsRig starten: Werkzeuge → Neuinstallation → Danach einspielen.'
        '   Ohne PulsRig: im Offline-Paket "Treiber-installieren.bat" doppelt anklicken.'
        '3. Programme.json listet die Programme, die winget kennt. PulsRig bietet sie zum Abhaken an;'
        '   ohne PulsRig: winget import -i Programme.json'
        ''
        'Eigene Dateien, Spielstände und Einstellungen anderer Programme sind hier nicht enthalten.'
    )
    Set-Content -LiteralPath (Join-Path $root 'LIESMICH.txt') -Value $readme -Encoding UTF8
    Write-Host ''
    Write-Host "Fertig. Ordner: $root" -ForegroundColor Green
    Write-Host 'Diesen Ordner vor der Neuinstallation auf einen USB-Stick kopieren.'
    return @{ Failed = [bool]$script:ExitCode; Folder = $root }
}

if ($a.Mode -eq 'Drivers') {
    $package = @(Get-ChildItem -LiteralPath $a.Folder -Directory -Filter 'Offline-Paket_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)[0]
    $drivers = if ($package) { Join-Path $package.FullName 'Treiber' }
    if (-not $drivers -or -not (Test-Path -LiteralPath $drivers)) {
        Write-Host 'In diesem Ordner steckt kein Offline-Treiberpaket.' -ForegroundColor Red
        return @{ Failed = $true }
    }
    $count = @(Get-ChildItem -LiteralPath $drivers -Recurse -Filter '*.inf' -File).Count
    Write-Host "$count Treiberpakete aus $($package.Name)"
    if ($DryRun) {
        Write-Host "  [Probelauf] pnputil /add-driver `"$drivers\*.inf`" /subdirs /install" -ForegroundColor DarkGray
        Write-Host 'Zum Einspielen PulsRig mit Adminrechten starten.'
        return @{ Failed = $false }
    }
    if (-not (Confirm-Action "$count Treiberpakete jetzt einspielen?")) { return @{ Failed = $false } }
    Write-Host 'Spiele die Treiber ein (kann einige Minuten dauern) ...'
    & pnputil.exe /add-driver "$drivers\*.inf" /subdirs /install | Out-Null
    # 3010: fertig, Neustart nötig; 259: nichts Neues für die vorhandenen Geräte
    if ($LASTEXITCODE -in 0, 259, 3010) { Write-Host 'Fertig. Bitte den PC danach neu starten.' -ForegroundColor Green }
    else { Write-Host "pnputil meldet Code $LASTEXITCODE - einzelne Treiber passten evtl. nicht zu den Geräten." -ForegroundColor Yellow }
    return @{ Failed = $false }
}

if ($a.Mode -eq 'Programs') {
    if (-not $winget) {
        Write-Host 'winget fehlt auf diesem PC. Den „App-Installer“ aus dem Microsoft Store installieren und es noch einmal versuchen.' -ForegroundColor Red
        return @{ Failed = $true }
    }
    $ids = @($a.Ids)
    $done = 0; $failed = @()
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = $ids[$i]
        Write-Progress 'Programme installieren' "$id ($($i + 1) von $($ids.Count))" -PercentComplete (100 * $i / $ids.Count)
        Write-Host "$id ... " -NoNewline
        if ($DryRun) { Write-Host '[Probelauf]' -ForegroundColor DarkGray; continue }
        $null = & $winget.Source install --id $id -e -s winget --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        $code = $LASTEXITCODE
        # -1978335189: schon installiert, keine neuere Fassung
        if ($code -eq 0) { Write-Host 'installiert' -ForegroundColor Green; $done++ }
        elseif ($code -eq -1978335189) { Write-Host 'schon vorhanden' -ForegroundColor Green; $done++ }
        else { Write-Host "fehlgeschlagen (winget-Code $code)" -ForegroundColor Red; $failed += $id }
    }
    Write-Progress 'Programme installieren' -Completed
    if ($DryRun) { return @{ Failed = $false } }
    Write-Host ''
    Write-Host "$done von $($ids.Count) Programmen sind da." -ForegroundColor $(if ($failed) { 'Yellow' } else { 'Green' })
    if ($failed) { Write-Host 'Die übrigen beim Hersteller laden - manche Programme lassen sich nur dort installieren.' }
    return @{ Failed = [bool]$failed }
}
