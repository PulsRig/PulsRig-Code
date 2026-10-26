<#
.SYNOPSIS
    Bringt den letzten Bau zu GitHub: die Setup-Datei als Release, danach version.json und README.md.

.DESCRIPTION
    Erwartet, dass PulsRig-Paket.ps1 gelaufen ist (dist\PulsRig-Setup-….exe, dist\version.json, dist\README.md).
    Die Reihenfolge ist Absicht: erst das Release, dann version.json. Installierte Fassungen lesen version.json und
    schicken bei einem neueren Baudatum auf die Release-Seite - dort muss die Setup-Datei dann schon liegen.

    Hochgeladen wird nur das: kein Quelltext, keine Übergabe.

    Braucht das Programm "gh" von GitHub, einmalig angemeldet:
        winget install GitHub.cli
        gh auth login

.EXAMPLE
    .\PulsRig-Hochladen.ps1            zeigt, was hochgeladen würde, und fragt nach
    .\PulsRig-Hochladen.ps1 -Ja        lädt ohne Rückfrage hoch
    .\PulsRig-Hochladen.ps1 -NurSeite  erneuert nur Beschreibung und Bilder der Projektseite
#>
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Ja, [switch]$NurSeite, [switch]$NurText, [string]$Projekt = 'PulsRig/PulsRig')

$ErrorActionPreference = 'Stop'
# gh schreibt UTF-8; ohne das kämen Umlaute verstümmelt an und der Vergleich mit dem vorigen Release-Text schlüge fehl
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = Split-Path -Parent $PSCommandPath
$dist = Join-Path $root 'dist'

$gh = (Get-Command gh.exe -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe' }
if (-not (Test-Path -LiteralPath $gh)) { throw 'Das Programm "gh" fehlt. Einmalig: winget install GitHub.cli   und danach: gh auth login' }
# Meldungen von gh auf dem Fehlerkanal sind kein Abbruchgrund: ob ein Aufruf geklappt hat, sagt sein Code
function Invoke-Gh { $ErrorActionPreference = 'Continue'; & $gh @args 2>$null }
Invoke-Gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bei GitHub ist niemand angemeldet. Einmalig: gh auth login' }

# eine Datei im Projekt anlegen oder ersetzen; zum Ersetzen verlangt GitHub die Kennung des bisherigen Stands.
# Der Inhalt geht als Datei an gh: ein Bild ist für die Befehlszeile zu lang. Unveränderte Dateien bleiben liegen.
function Send-ProjectFile([string]$Path, [string]$Name, [string]$Message) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $body = [ordered]@{ message = $Message; content = [Convert]::ToBase64String($bytes); branch = 'main' }
    $sha = Invoke-Gh api "repos/$Projekt/contents/$Name" --jq '.sha'
    if ($LASTEXITCODE -eq 0 -and $sha) {
        # GitHub kennzeichnet den Inhalt wie git: SHA-1 über "blob <Länge>", ein Nullbyte und die Datei
        $head = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $own = -join ([Security.Cryptography.SHA1]::Create().ComputeHash([byte[]]($head + $bytes)) | ForEach-Object { $_.ToString('x2') })
        if ($own -eq "$sha".Trim()) { Write-Host "Unverändert: $Name"; return }
        $body.sha = "$sha".Trim()
    }
    $bodyFile = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Datei-$PID.json"
    [IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
    try { Invoke-Gh api --method PUT "repos/$Projekt/contents/$Name" --input $bodyFile --silent }
    finally { [IO.File]::Delete($bodyFile) }
    if ($LASTEXITCODE -ne 0) { throw "$Name ließ sich nicht hochladen." }
    Write-Host "Hochgeladen: $Name"
}
# die Bilder der Projektseite: Aufnahmen aus dem Probelauf mit erfundenen Daten, nie vom eigenen PC
function Send-ProjectPictures {
    foreach ($picture in @(Get-ChildItem -LiteralPath (Join-Path $root 'bilder') -Filter *.png -ErrorAction SilentlyContinue)) {
        Send-ProjectFile $picture.FullName "bilder/$($picture.Name)" 'Bilder'
    }
}

# Webseite\index.html leitet nur noch auf https://pulsrig.de weiter (eigenes Projekt PulsRig/pulsrig.github.io). Sie liegt
# im Hauptordner, GitHub Pages zeigt sie unter pulsrig.de/PulsRig/ für alte Links - eingeschaltet wird Pages hier. ".nojekyll" verhindert,
# dass GitHub die Dateien erst durch seinen Seitenbauer schickt.
function Send-Website {
    $page = Join-Path $root 'Webseite\index.html'
    if (-not (Test-Path -LiteralPath $page)) { return }
    Send-ProjectFile $page 'index.html' 'Webseite'
    $empty = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-nojekyll-$PID"
    [IO.File]::WriteAllBytes($empty, [byte[]]@(10))
    try { Send-ProjectFile $empty '.nojekyll' 'Webseite' }
    finally { [IO.File]::Delete($empty) }
    Invoke-Gh api "repos/$Projekt/pages" --silent
    if ($LASTEXITCODE -ne 0) {
        $bodyFile = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Pages-$PID.json"
        [IO.File]::WriteAllText($bodyFile, '{"source":{"branch":"main","path":"/"}}', (New-Object Text.UTF8Encoding $false))
        try { Invoke-Gh api --method POST "repos/$Projekt/pages" --input $bodyFile --silent }
        finally { [IO.File]::Delete($bodyFile) }
        if ($LASTEXITCODE -ne 0) { Write-Warning 'GitHub Pages ließ sich nicht einschalten - die Webseite liegt im Projekt, ist aber noch nicht erreichbar.' }
        else { Write-Host 'GitHub Pages eingeschaltet (die Seite ist nach ein bis zwei Minuten erreichbar).' }
    }
    $owner, $name = $Projekt -split '/'
    Write-Host "Alte Webseite (leitet auf pulsrig.de): https://pulsrig.de/$name/"
}

# Text der Release-Seite. PulsRig-Neuerungen.md sammelt alles, was in der Version neu ist. "Was ist neu" oben zeigt
# die Punkte der letzten 7 Tage, nach Bau sortiert (neuester zuerst); in welchem Bau ein Punkt dazukam, steht in den
# früheren Release-Texten: es ist der früheste, der ihn enthält. Ältere Punkte stehen nur in der aufklappbaren Liste.
function Get-EarlierReleases([string]$ExcludeTag) {
    $json = @(Invoke-Gh api "repos/$Projekt/releases?per_page=100") -join "`n"
    $list = @()
    # PowerShell 5.1 gibt eine JSON-Liste als ein Element zurück: erst zuweisen, dann durchgehen
    $data = $json | ConvertFrom-Json
    foreach ($release in $data) {
        if ("$($release.tag_name)" -eq $ExcludeTag) { continue }
        if ("$($release.name)" -notmatch 'Bau vom (\d\d\.\d\d\.\d{4} \d\d:\d\d)') { continue }
        $list += @{ Built = [datetime]::ParseExact($Matches[1], 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture)
            Lines = @("$($release.body)" -replace "`r`n", "`n" -split "`n" | ForEach-Object { $_.Trim() }) }
    }
    @($list | Sort-Object { $_.Built })
}

function New-ReleaseNotes($Earlier, [string]$Version, [datetime]$Built) {
    $newsFile = Join-Path $root 'PulsRig-Neuerungen.md'
    $news = if (Test-Path -LiteralPath $newsFile) { [IO.File]::ReadAllText($newsFile, [Text.Encoding]::UTF8).Trim() -replace "`r`n", "`n" } else { '' }
    # je Punkt der Bau, in dem er zuerst auftauchte (noch nirgends = dieser Bau); zusammengefasst je Tag, das Neueste oben
    $groups = [ordered]@{}
    $own = 0
    foreach ($line in @($news -split "`n" | Where-Object { $_ -match '^- ' })) {
        $first = @($Earlier | Where-Object { $_.Lines -contains $line.Trim() })[0]
        $when = if ($first) { $first.Built } else { $Built; $own++ }
        if ($when -lt $Built.AddDays(-7)) { continue }
        $key = $when.ToString('yyyy-MM-dd')
        if (-not $groups.Contains($key)) { $groups[$key] = @() }
        $groups[$key] = @($line) + $groups[$key]
    }
    $today = $Built.ToString('yyyy-MM-dd')
    if ($own -eq 0) {
        if (-not $groups.Contains($today)) { $groups[$today] = @() }
        $groups[$today] = @('- Fehlerbehebungen und kleine Verbesserungen.') + $groups[$today]
    }
    $recent = @()
    foreach ($key in @($groups.Keys | Sort-Object -Descending)) {
        $recent += "### Update vom $([datetime]::ParseExact($key, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture).ToString('dd.MM.yyyy'))"
        $recent += ''
        $recent += $groups[$key]
        $recent += ''
    }
    @(
        # oben das Bild der Startseite (liegt im Projekt unter bilder/) und der Weg zur Webseite
        "![PulsRig im Aussehen Nacht Puls](https://raw.githubusercontent.com/$Projekt/main/bilder/start.png)"
        ''
        "**Webseite:** https://pulsrig.de · **Hilfe und Fehler:** pulsrig.hilfe@gmail.com"
        ''
        '## Was ist neu'
        ''
        $recent
        '## Installieren'
        ''
        "Setup-Datei von PulsRig $Version, gebaut am $($Built.ToString('dd.MM.yyyy')) um $($Built.ToString('HH:mm')) Uhr."
        ''
        '- Nicht signiert: Windows warnt beim Start. Dort auf „Weitere Informationen“ und dann auf „Trotzdem ausführen“ klicken.'
        '- AVG/Avast (CyberCapture) halten das Setup oder die Deinstallation manchmal zur Prüfung an. Das ist kein Virenfund: ein paar Stunden warten oder im Virenschutz „Weitere Optionen“ → Datei ausführen/als vertrauenswürdig markieren.'
        '- Eine ältere Fassung muss nicht entfernt werden: Das Setup spielt die neue darüber, die Einstellungen bleiben erhalten.'
        '- Installierte Fassungen zeigen eine neuere selbst oben rechts an und installieren sie auf Knopfdruck.'
        ''
        "<details><summary>Alles, was in $Version neu ist</summary>"
        ''
        $news
        ''
        '</details>'
    ) -join "`n"
}

# nur den Text des neuesten Releases neu schreiben
if ($NurText) {
    $tags = @(Invoke-Gh release list --repo $Projekt --limit 1 --json tagName -q '.[].tagName')
    if ($tags.Count -lt 1) { throw 'Kein Release gefunden.' }
    $title = "$(Invoke-Gh release view $tags[0] --repo $Projekt --json name -q .name)"
    if ($title -notmatch 'PulsRig (.+), Bau vom (\d\d\.\d\d\.\d{4} \d\d:\d\d)') { throw "Titel nicht erkannt: $title" }
    $notes = New-ReleaseNotes (Get-EarlierReleases $tags[0]) $Matches[1] ([datetime]::ParseExact($Matches[2], 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture))
    $notesFile = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Release-$PID.md"
    [IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding $false))
    try { Invoke-Gh release edit $tags[0] --repo $Projekt --notes-file $notesFile | Out-Null }
    finally { [IO.File]::Delete($notesFile) }
    if ($LASTEXITCODE -ne 0) { throw 'Der Text ließ sich nicht ändern.' }
    Write-Host "Text erneuert: https://github.com/$Projekt/releases/tag/$($tags[0])" -ForegroundColor Green
    exit 0
}
# nur die Projektseite erneuern: Beschreibung, Bilder und Webseite, kein Release und keine version.json
if ($NurSeite) {
    Send-ProjectFile (Join-Path $root 'PulsRig-GitHub.md') 'README.md' 'Beschreibung'
    Send-ProjectPictures
    Send-Website
    Write-Host "Fertig: https://github.com/$Projekt" -ForegroundColor Green
    exit 0
}

$versionFile = Join-Path $dist 'version.json'
$readme = Join-Path $dist 'README.md'
if (-not (Test-Path -LiteralPath $versionFile)) { throw 'dist\version.json fehlt - zuerst PulsRig-Paket.ps1 laufen lassen.' }
$note = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
$versionName = "$($note.Version)" -replace '\s+', '-'
$setup = Join-Path $dist "PulsRig-Setup-$versionName.exe"
if (-not (Test-Path -LiteralPath $setup)) { throw "Die Setup-Datei fehlt: $setup" }
# die Setup-Datei muss zu version.json gehören: beide schreibt das Paketskript im selben Lauf
if ([Math]::Abs(((Get-Item -LiteralPath $setup).LastWriteTime - (Get-Item -LiteralPath $versionFile).LastWriteTime).TotalMinutes) -gt 5) {
    throw 'Setup-Datei und version.json stammen nicht aus demselben Bau - PulsRig-Paket.ps1 noch einmal laufen lassen.'
}
$built = [datetime]::ParseExact("$($note.Gebaut)".Substring(0, 16), 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture)
# je Bau ein eigenes Release: dieselbe Version wird während einer Testphase mehrfach gebaut
$tag = ('v{0}-{1:yyyyMMdd-HHmm}' -f $versionName, $built).ToLower()
$title = "PulsRig $($note.Version), Bau vom $($built.ToString('dd.MM.yyyy HH:mm'))"

Write-Host "Projekt:      $Projekt"
Write-Host "Release:      $title  (Tag $tag)"
Write-Host ("Setup-Datei:  {0}  ({1:N0} KB)" -f (Split-Path -Leaf $setup), ((Get-Item -LiteralPath $setup).Length / 1KB))
Write-Host "Danach:       version.json und README.md"
if (-not $Ja) {
    $answer = Read-Host 'Hochladen? (j/n)'
    if ($answer -notmatch '^[jJyY]') { Write-Host 'Nichts hochgeladen.'; exit 0 }
}

# ein Lauf, der nach dem Release abbrach, darf wiederholt werden
Invoke-Gh release view $tag --repo $Projekt | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host 'Das Release gibt es schon - die Setup-Datei wird ersetzt.'; Invoke-Gh release upload $tag $setup --repo $Projekt --clobber }
else {
    # der Text geht als Datei an gh: Anführungszeichen und Zeilenwechsel überstehen die Übergabe als Argument nicht
    # oben die Punkte der letzten 7 Tage nach Bau, die ganze Liste aufklappbar darunter
    $notes = New-ReleaseNotes (Get-EarlierReleases $tag) $note.Version $built
    $notesFile = Join-Path ([IO.Path]::GetTempPath()) "PulsRig-Release-$PID.md"
    [IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding $false))
    try { Invoke-Gh release create $tag $setup --repo $Projekt --title $title --notes-file $notesFile --latest }
    finally { [IO.File]::Delete($notesFile) }
}
if ($LASTEXITCODE -ne 0) { throw 'Das Release ließ sich nicht anlegen - version.json bleibt unverändert.' }

if (Test-Path -LiteralPath $readme) { Send-ProjectFile $readme 'README.md' 'Beschreibung' }
Send-ProjectPictures
Send-Website
Send-ProjectFile $versionFile 'version.json' "Bau vom $($built.ToString('dd.MM.yyyy HH:mm'))"

Write-Host ''
Write-Host "Fertig: https://github.com/$Projekt/releases/latest" -ForegroundColor Green
Write-Host 'Installierte Fassungen sehen den Hinweis beim nächsten Start (GitHub braucht dafür bis zu fünf Minuten).'
