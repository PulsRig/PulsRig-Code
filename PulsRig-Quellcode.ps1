# PulsRig - Quelltext ins öffentliche Projekt PulsRig/PulsRig-Code bringen (GPL-3.0).
#   powershell -NoProfile -ExecutionPolicy Bypass -File PulsRig-Quellcode.ps1        zeigt nur, was hochginge
#   powershell -NoProfile -ExecutionPolicy Bypass -File PulsRig-Quellcode.ps1 -Ja    lädt hoch
#
# Öffentlich wird nur, was zum Programm gehört: Skripte, Oberfläche, C#-Teile, Setup-Skript, Ordner Sensoren, Bilder.
# Nie hinein: die Übergabe (Angaben zum PC des Nutzers und der Tester), alte Übergaben, desktop.ini, gebaute Dateien.
# Vor dem Hochladen sucht das Skript nach Benutzername, PC-Name und E-Mail aus der Versionsverwaltung und bricht ab,
# wenn etwas davon in einer Datei steht. Der öffentliche Verlauf hat eigene Commits mit der neutralen GitHub-Adresse
# des Kontos PulsRig - nicht die des privaten Projekts.
param([switch]$Ja)

$ErrorActionPreference = 'Stop'
# Git gibt Dateinamen in UTF-8 aus; sonst käme "PulsRig-Übergabe.md" verstümmelt an und der Ausschluss griffe nicht
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$root = Split-Path -Parent $PSCommandPath
$git = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
$gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
$repo = 'PulsRig/PulsRig-Code'
$author = 'PulsRig'; $mail = '342117437+PulsRig@users.noreply.github.com'
$work = Join-Path $root 'dist\PulsRig-Code'

# 1. die Dateien: alles, was die Versionsverwaltung kennt, ohne die privaten
$skip = '^(PulsRig-Übergabe\.md|handoff-.*\.md|desktop\.ini|PulsRig-GitHub\.md|PulsRig-Code\.md|PulsRig-Profilbild\.png|Webseite/.*)$'
$files = @(& $git -C $root -c core.quotepath=false ls-files | Where-Object { $_ -and $_ -notmatch $skip })
Write-Host "Dateien: $($files.Count)"

# 2. nach persönlichen Angaben suchen
$private = @($env:USERNAME, $env:COMPUTERNAME, "$(& $git -C $root config user.email)".Trim()) | Where-Object { $_ -and $_.Length -ge 4 }
$hits = @()
foreach ($file in $files) {
    $path = Join-Path $root $file
    if ($file -match '\.(dll|png|ico)$') { continue }
    $text = [IO.File]::ReadAllText($path)
    foreach ($word in $private) { if ($text.IndexOf($word, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += "$file enthält '$word'" } }
}
if ($hits) { $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; throw 'Persönliche Angaben gefunden - nichts hochgeladen.' }
Write-Host 'Keine persönlichen Angaben gefunden.'
if (-not $Ja) { Write-Host 'Nur angesehen. Mit -Ja wird hochgeladen.'; return }

# 3. Arbeitsordner: das öffentliche Projekt holen (oder neu anlegen) und mit dem jetzigen Stand füllen
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -Confirm:$false }
$exists = $true
try { & $gh repo view $repo --json name 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { $exists = $false } } catch { $exists = $false }
if ($exists) { & $git clone --quiet "https://github.com/$repo.git" $work; if ($LASTEXITCODE -ne 0) { throw 'Klonen fehlgeschlagen' } }
else { New-Item -ItemType Directory -Path $work -Force | Out-Null; & $git -C $work init --quiet -b main }
Get-ChildItem -LiteralPath $work -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force -Confirm:$false
foreach ($file in $files) {
    $target = Join-Path $work $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $target
}
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $work 'LICENSE')
Copy-Item -LiteralPath (Join-Path $root 'PulsRig-Code.md') -Destination (Join-Path $work 'README.md')

# 4. Commit mit der neutralen Adresse und hochladen
$stamp = "$(& $git -C $root rev-parse --short HEAD)".Trim()
& $git -C $work add -A
if (-not (& $git -C $work status --porcelain)) { Write-Host 'Nichts geändert.'; return }
& $git -C $work -c "user.name=$author" -c "user.email=$mail" commit --quiet -m "PulsRig: Quelltext (Stand $stamp)"
if (-not $exists) {
    & $gh repo create $repo --public --description 'PulsRig – Quelltext (PowerShell/WPF/C#): Treiber, Boost, Hardware-Prüfungen und Werkzeuge für Windows. GPL-3.0' --source $work --remote origin --push
}
else { & $git -C $work push --quiet origin main }
if ($LASTEXITCODE -ne 0) { throw 'Hochladen fehlgeschlagen' }
Write-Host "Fertig: https://github.com/$repo"
