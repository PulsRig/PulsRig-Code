<#
.SYNOPSIS
    Baut die Dateien zum Weitergeben: dist\PulsRig-Setup-<Version>.exe und dist\PulsRig-<Version>.zip.

.DESCRIPTION
    Stellt die Dateien des Programms in dist\PulsRig zusammen (ohne Tests, Daten und Unterlagen), packt sie als ZIP
    und baut mit Inno Setup die Installationsdatei. Fehlt Inno Setup, entsteht nur die ZIP-Datei.
    Vorher laufen die Tests; schlagen sie fehl, wird nichts gebaut.

    Aufruf:  powershell -NoProfile -ExecutionPolicy Bypass -File PulsRig-Paket.ps1
#>
[CmdletBinding()]
param([switch]$OhneTests, [string]$Projekt = 'PulsRig/PulsRig')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'PulsRig'

# Version aus dem Programm lesen: "0.5 Beta" wird im Dateinamen zu "0.5-Beta"
$main = [IO.File]::ReadAllText((Join-Path $root 'PulsRig.ps1'), [Text.Encoding]::UTF8)
if ($main -notmatch "\`$script:Version = '([^']+)'") { throw 'Version in PulsRig.ps1 nicht gefunden.' }
$version = $Matches[1]
$versionName = $version -replace '\s+', '-'

if (-not $OhneTests) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'PulsRig-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Die Tests sind fehlgeschlagen - es wird nichts gebaut.' }
}

# Programmsymbol: das Logo (Ring im Farbverlauf, Pulslinie) in vier Größen. Entsteht einmal und bleibt dann liegen.
function New-PulsRigIcon([string]$Path) {
    Add-Type -AssemblyName PresentationCore, WindowsBase
    $images = foreach ($size in 256, 48, 32, 16) {
        $visual = New-Object Windows.Media.DrawingVisual
        $context = $visual.RenderOpen()
        $scale = $size / 132.0
        $context.PushTransform((New-Object Windows.Media.ScaleTransform $scale, $scale))
        $back = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(12, 19, 38))
        $context.DrawRoundedRectangle($back, $null, (New-Object Windows.Rect 2, 2, 128, 128), 28, 28)
        $ring = New-Object Windows.Media.LinearGradientBrush
        $ring.StartPoint = New-Object Windows.Point 0, 0; $ring.EndPoint = New-Object Windows.Point 1, 1
        foreach ($stop in @(@('#22D3EE', 0.0), @('#6366F1', 0.55), @('#A855F7', 1.0))) {
            $ring.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($stop[0])), $stop[1]))
        }
        # kleine Größen brauchen kräftigere Linien, sonst bleibt nur ein grauer Fleck
        $thick = if ($size -le 32) { 12 } else { 8 }
        $context.DrawEllipse($null, (New-Object Windows.Media.Pen $ring, $thick), (New-Object Windows.Point 66, 66), 48, 48)
        $pen = New-Object Windows.Media.Pen ([Windows.Media.Brushes]::White), $(if ($size -le 32) { 11 } else { 8 })
        $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
        $context.DrawGeometry($null, $pen, [Windows.Media.Geometry]::Parse('M 34,68 L 50,68 L 58,52 L 68,88 L 78,40 L 86,68 L 96,68'))
        $context.Pop()
        $context.Close()
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap $size, $size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = New-Object IO.MemoryStream
        $encoder.Save($stream)
        , @($size, $stream.ToArray())
    }
    # ICO-Datei: Kopf, je Bild ein Eintrag mit Größe und Stelle, danach die Bilder als PNG
    $out = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter $out
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($image in $images) {
        $edge = if ($image[0] -ge 256) { 0 } else { $image[0] }
        $writer.Write([byte]$edge); $writer.Write([byte]$edge); $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$image[1].Length); $writer.Write([uint32]$offset)
        $offset += $image[1].Length
    }
    foreach ($image in $images) { $writer.Write([byte[]]$image[1]) }
    $writer.Flush()
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

$icon = Join-Path $root 'PulsRig.ico'
if (-not (Test-Path -LiteralPath $icon)) { New-PulsRigIcon $icon; Write-Host 'Programmsymbol erzeugt: PulsRig.ico' }

# Dateien zusammenstellen - nur der Ordner dist\PulsRig wird dabei geleert, nichts sonst
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$files = @(Get-ChildItem -LiteralPath $root -File | Where-Object {
        $_.Name -match '^(PulsRig.*\.(ps1|xaml|bat|cs|ico)|Treiber-(Scan|Werkzeuge)\.ps1|Treiber-Scan\.bat|PulsRig-Testzettel\.txt)$' -and
        $_.Name -notin 'PulsRig-Tests.ps1', 'PulsRig-Paket.ps1', 'PulsRig-Fremdsystem.ps1', 'PulsRig-Hochladen.ps1', 'PulsRig-Start.cs'
    })
foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stage $file.Name) }
# Ordner Sensoren: LibreHardwareMonitor für die Temperatur des Prozessors (PulsRig-Temperatur.cs), samt Lizenzen
$sensors = Join-Path $root 'Sensoren'
if (-not (Test-Path -LiteralPath (Join-Path $sensors 'LibreHardwareMonitorLib.dll'))) { throw "Der Ordner Sensoren fehlt: $sensors" }
Copy-Item -LiteralPath $sensors -Destination (Join-Path $stage 'Sensoren') -Recurse

# Baudatum und Stand der Versionsverwaltung: das Programm nennt beides im Diagnose-Paket
$stamp = (Get-Date).ToString('dd.MM.yyyy HH:mm')
try {
    $git = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
    if (Test-Path -LiteralPath $git) {
        $commit = "$(& $git -C $root rev-parse --short HEAD 2>$null)".Trim()
        if ($commit) { $stamp += " · Stand $commit" + $(if (& $git -C $root status --porcelain 2>$null) { ' mit ungesicherten Änderungen' }) }
    }
}
catch { }
[IO.File]::WriteAllText((Join-Path $stage 'PulsRig-Bau.txt'), $stamp, (New-Object Text.UTF8Encoding $true))
Write-Host "Baudatum: $stamp"
# version.json gehört ins Projekt bei GitHub: daran erkennen installierte Fassungen, dass es eine neuere gibt.
# Hier entsteht sie ohne Setup-Datei; gibt es am Ende eine, kommen deren Adresse, Größe und Prüfsumme dazu.
$versionNote = [ordered]@{ Version = $version; Gebaut = $stamp }
[IO.File]::WriteAllText((Join-Path $dist 'version.json'), ($versionNote | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
# die Beschreibung für die Projektseite bei GitHub liegt als README.md daneben
Copy-Item -LiteralPath (Join-Path $root 'PulsRig-GitHub.md') -Destination (Join-Path $dist 'README.md') -Force
Write-Host "Zusammengestellt: $($files.Count) Dateien"

# ZIP zum Entpacken und Installieren per PulsRig-Installieren.bat
$zip = Join-Path $dist "PulsRig-$versionName.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Confirm:$false }
Compress-Archive -Path $stage -DestinationPath $zip
Write-Host ("ZIP:   {0}  ({1:N0} KB)" -f $zip, ((Get-Item -LiteralPath $zip).Length / 1KB))

# PulsRig.exe für die Installationsdatei: die Hülle (PulsRig-Start.cs), die alle Skripte, die Oberfläche und das
# Baudatum in sich trägt - im Programmordner liegen dann nur sie, das Symbol und der Testzettel. Gebaut mit dem
# Compiler, den Windows mitbringt; die eingebaute PowerShell kommt aus derselben Bibliothek, die dieses Skript nutzt.
# (Das ZIP-Paket oben bleibt bei losen Dateien und startet wie bisher über powershell.exe.)
$program = Join-Path $dist 'PulsRig-Programm'
if (Test-Path -LiteralPath $program) { Remove-Item -LiteralPath $program -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Path $program -Force | Out-Null
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "Der Compiler von .NET Framework fehlt: $csc" }
$inside = @(Get-ChildItem -LiteralPath $stage -File | Where-Object { $_.Name -match '\.(ps1|xaml|cs)$|^PulsRig-Bau\.txt$' -and $_.Name -ne 'PulsRig-Installieren.ps1' })
$exe = Join-Path $program 'PulsRig.exe'
$resources = @($inside | ForEach-Object { "-resource:$($_.FullName),$($_.Name)" })
# der Helfer zeichnet beim Spielen auf (PulsRig-Aufzeichnung.cs) und liest dafür die Temperatur des Prozessors
# (PulsRig-Temperatur.cs); LibreHardwareMonitor wird nur übersetzt mit angegeben und zur Laufzeit aus "Sensoren" geladen
$library = Join-Path $root 'Sensoren\LibreHardwareMonitorLib.dll'
& $csc '-nologo' '-target:winexe' '-platform:anycpu' '-optimize+' "-out:$exe" "-win32icon:$icon" "-r:$([psobject].Assembly.Location)" '-r:System.Windows.Forms.dll' '-r:System.Drawing.dll' '-r:System.Web.Extensions.dll' '-r:System.Core.dll' "-r:$library" @resources (Join-Path $root 'PulsRig-Start.cs') (Join-Path $root 'PulsRig-Temperatur.cs') (Join-Path $root 'PulsRig-Aufzeichnung.cs')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw 'PulsRig.exe ließ sich nicht bauen.' }
foreach ($name in 'PulsRig.ico', 'PulsRig-Testzettel.txt') { Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $program $name) }
Copy-Item -LiteralPath (Join-Path $stage 'Sensoren') -Destination (Join-Path $program 'Sensoren') -Recurse
Write-Host ("Programmdatei: PulsRig.exe  ({0:N0} KB, {1} Dateien eingebettet)" -f ((Get-Item -LiteralPath $exe).Length / 1KB), $inside.Count)

# Installationsdatei mit Inno Setup
$compiler = Get-ChildItem "${env:ProgramFiles(x86)}\Inno Setup*", "$env:ProgramFiles\Inno Setup*", "$env:LOCALAPPDATA\Programs\Inno Setup*" -Filter ISCC.exe -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $compiler) {
    Write-Host 'Inno Setup ist nicht installiert - es gibt nur die ZIP-Datei.' -ForegroundColor Yellow
    return
}
& $compiler.FullName "/DAppVersion=$version" "/DVersionName=$versionName" '/Qp' (Join-Path $root 'PulsRig-Setup.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup hat einen Fehler gemeldet (Code $LASTEXITCODE)." }
$setup = Join-Path $dist "PulsRig-Setup-$versionName.exe"
Write-Host ("Setup: {0}  ({1:N0} KB)" -f $setup, ((Get-Item -LiteralPath $setup).Length / 1KB)) -ForegroundColor Green
# Damit eine installierte Fassung die neue selbst laden kann: wo die Setup-Datei nach dem Hochladen liegt (das Release
# heißt wie in PulsRig-Hochladen.ps1), wie groß sie ist und welche Prüfsumme sie hat. Das Programm startet nur eine
# Datei, bei der beides stimmt.
$built = [datetime]::ParseExact($stamp.Substring(0, 16), 'dd.MM.yyyy HH:mm', [cultureinfo]::InvariantCulture)
$tag = ('v{0}-{1:yyyyMMdd-HHmm}' -f $versionName, $built).ToLower()
$versionNote.Setup = "https://github.com/$Projekt/releases/download/$tag/$(Split-Path -Leaf $setup)"
$versionNote.Bytes = (Get-Item -LiteralPath $setup).Length
$versionNote.Sha256 = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $dist 'version.json'), ($versionNote | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
