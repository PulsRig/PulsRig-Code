# PulsRig - Probelauf: spielt das ganze Programm durch und legt Bilder ab (Schalter -Snapshot).
# Wird von PulsRig.ps1 nur im Probelauf eingebunden.

function Save-Snapshot([string]$Name, $Visual = $window) {
    Save-Untranslated $Snapshot   # Arbeitsliste für die Übersetzung, nach jedem Bild auf dem neuesten Stand
    $width = [int]$Visual.ActualWidth; $height = [int]$Visual.ActualHeight
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap $width, $height, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    if ($Visual -eq $window) { $bitmap.Render($Visual) }
    else {
        # ein einzelnes Element (z. B. das Aufklappmenü): über einen Pinsel zeichnen, sonst verschiebt sein Rand das Bild
        $drawing = New-Object Windows.Media.DrawingVisual
        $context = $drawing.RenderOpen()
        $context.DrawRectangle((New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(10, 15, 30))), $null, (New-Object Windows.Rect 0, 0, $width, $height))
        $context.DrawRectangle((New-Object Windows.Media.VisualBrush $Visual), $null, (New-Object Windows.Rect 0, 0, $width, $height))
        $context.Close()
        $bitmap.Render($drawing)
    }
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $Snapshot "$Name.png"))
    try { $encoder.Save($stream) } finally { $stream.Close() }
    Write-Host "Bild: $Name"
}

# Sucht im Bild-Baum unterhalb von $Root alle Elemente einer Art
function Find-Visual($Root, [type]$Type) {
    $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Root)
    for ($i = 0; $i -lt $count; $i++) {
        $child = [Windows.Media.VisualTreeHelper]::GetChild($Root, $i)
        if ($child -is $Type) { $child }
        Find-Visual $child $Type
    }
}

# Stellt einen Mausklick auf ein Kästchen oder einen Knopf nach
function Invoke-TestClick($Element, $Checked = $null) {
    if ($null -ne $Checked) { $Element.IsChecked = [bool]$Checked }
    $Element.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent), $Element))
}

# Schritte laufen nacheinander: entweder nach einer Wartezeit (Wait) oder sobald eine Bedingung gilt (Until)
function Start-SnapshotTour {
    $idle = { -not $script:Busy }
    if ($Real) {
        # echter Scan und echte Werkzeugläufe; am Ende eine Rückfrage quer durch den Arbeitsbereich
        $script:PromptTest = 'param($a) $global:DryRun = $false; $first = Confirm-Action "Testfrage aus dem Arbeitsbereich?"; $second = Read-Host "Testeingabe"; Write-Host "Antworten: $first / $second" -ForegroundColor Green'
        $script:Tour = @(
            # Prüfung der Laufwerke wie beim Start; ein Klick auf SCAN währenddessen startet den Scan direkt danach
            @{ Wait = 4300; Do = { Start-DriveCheck; Start-Scan; Write-Host "Laufwerksprüfung läuft: $script:DriveCheckRunning, Scan danach: $script:ScanAfterCheck" } },
            @{ Until = { -not $script:DriveCheckRunning }; Timeout = 60000; Do = {
                    Write-Host "Laufwerke geprüft: Hinweis $($ui.DriveWarn.Visibility) | $($ui.DriveWarnTitle.Text) | $($ui.DriveWarnText.Text) | Laufwerke im Verlauf: $(@($script:History.Disks.Keys).Count)"
                    Save-Snapshot 'echt-0-laufwerkshinweis'
                }
            },
            @{ Wait = 7000; Do = { Write-Host "Scan läuft: $script:Busy"; Save-Snapshot 'echt-1-scan' } },
            @{ Until = { -not $script:Busy -and $script:Page -eq 'Results' }; Timeout = 240000; Do = { } },
            @{ Wait = 1700; Do = { Save-Snapshot 'echt-2-ergebnisse'; Open-ToolDialog 'SystemInfo' } },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 'echt-3-systeminfo'; Close-Dialog } },
            @{ Wait = 500; Do = { Open-ToolDialog 'FixNetwork' } },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 90000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 'echt-4-netzwerk'; Close-Dialog } },
            @{ Wait = 500; Do = { Open-ToolDialog 'SystemInfo' } },
            @{ Wait = 700; Do = { Start-DialogJob $script:PromptTest } },
            @{ Until = { $script:PromptMode -eq 'confirm' }; Timeout = 20000; Do = { } },
            @{ Wait = 700; Do = { Save-Snapshot 'echt-5-rueckfrage'; Send-Reply $true } },
            @{ Until = { $script:PromptMode -eq 'input' }; Timeout = 20000; Do = { $ui.PromptInput.Text = '2, 3' } },
            @{ Wait = 700; Do = { Save-Snapshot 'echt-6-eingabe'; Send-Reply $true } },
            @{ Until = $idle; Timeout = 20000; Do = { } },
            @{ Wait = 900; Do = {
                    Save-Snapshot 'echt-7-antworten'
                    Close-Dialog
                    # was die folgenden Läufe schreiben, landet im Ordner der Bildschirmfotos
                    $script:Settings.TargetDir = $Snapshot
                    $rows = @($ui.ResultList.Children | Where-Object { $_ -is [Windows.Controls.Border] }).Count
                    Write-Host "Ergebniszeilen: $rows, Treiber im Ergebnis: $(@($script:LastResult.Drivers).Count)"
                }
            },
            # Komponente mit fester Auswahl und Boost mit Auswahl aus dem Konfigurator (ohne Adminrechte als Probelauf)
            @{ Wait = 600; Do = { Open-RuntimeInstall @('Visual C++ 2013 (x64)') } },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 'echt-8-komponente'; Close-Dialog } },
            @{ Wait = 500; Do = { $script:Settings.Boost.Apps = @('Spotify'); Open-ToolDialog 'GameBoost' } },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 'echt-9-boost'; Close-Dialog } },
            # einzelnen Treiber sichern: läuft auch ohne Adminrechte wirklich
            @{ Wait = 500; Do = {
                    $packages = @($script:LastResult.Drivers | Where-Object { $_.Inf -like 'oem*.inf' -and $_.Class -ne 'Display' })
                    $driver = $packages | Where-Object { $_.Name -match 'SMBUS|GPIO' } | Select-Object -First 1
                    if (-not $driver) { $driver = $packages | Select-Object -First 1 }
                    Open-ExportDialog $driver
                }
            },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 120000; Do = { } },
            # Autostart lesen und Speicherplatz prüfen: beides ohne Adminrechte nur lesend
            @{ Wait = 900; Do = { Save-Snapshot 'echt-10-export'; Close-Dialog; Open-AutostartSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Autostart }; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = {
                    Save-Snapshot 'echt-10b-autostart'
                    Write-Host "Autostart: $(@($script:Sheet.Autostart.Entries).Count) Einträge, davon eingeschaltet $(@($script:Sheet.Autostart.Entries | Where-Object { $_.Enabled }).Count)"
                    Close-Sheet -Quick; Open-ToolDialog 'CleanDisk'
                }
            },
            @{ Wait = 700; Do = { Start-DialogJob } },
            @{ Until = $idle; Timeout = 180000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 'echt-10c-aufraeumen'; Close-Dialog; Open-SystemSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Info }; Timeout = 60000; Do = { } },
            @{ Wait = 700; Do = { Export-SystemInfo; Write-Host $ui.SheetState.Text; Close-Sheet -Quick } },
            # Neue Fassung laden: nur wenn PULSRIG_UPDATE_TEST gesetzt ist ("Adresse|Prüfsumme|Größe" einer veröffentlichten
            # Setup-Datei). Geladen und geprüft wird wirklich, installiert wird im Probelauf nie.
            @{ Wait = 600; Do = {
                    $parts = @("$env:PULSRIG_UPDATE_TEST" -split '\|')
                    if ($parts.Count -eq 3) {
                        Show-NewVersion @{ Version = $script:Version; Built = '31.12.2099 00:00'; Setup = $parts[0]; Sha256 = $parts[1].ToUpper(); Bytes = [long]$parts[2] }
                        Open-UpdateSheet
                    }
                }
            },
            @{ Wait = 1200; Do = { if ($env:PULSRIG_UPDATE_TEST) { Save-Snapshot 'echt-11-neue-fassung'; Start-UpdateDownload } } },
            @{ Until = { -not $script:UpdateJob }; Timeout = 120000; Do = { } },
            @{ Wait = 900; Do = {
                    if ($env:PULSRIG_UPDATE_TEST) {
                        Save-Snapshot 'echt-12-neue-fassung-geladen'
                        Write-Host "Neue Fassung: $($ui.SheetState.Text) | Datei da: $(Test-Path -LiteralPath (Join-Path (Get-UpdateFolder) 'PulsRig-Setup.exe'))"
                        Close-Sheet -Quick
                    }
                    $window.Close()
                }
            }
        )
    }
    else {
        $script:Tour = @(
            @{ Wait = 1500; Do = { Save-Snapshot '01-vorspann' } },
            @{ Wait = 900; Do = { Save-Snapshot '01b-vorspann-zweiter-schlag' } },
            @{ Wait = 2600; Do = {
                    Save-Snapshot '02-start'
                    # Hinweis auf ein auffälliges Laufwerk, mit gestellten Werten
                    $script:Settings.DriveWarnHidden = ''
                    Update-DriveWarn @{ Disks = @(@{ Name = 'Intenso SSD Sata III'; Letters = @('E'); Health = 'Healthy'; Faults = 12; LastFault = '14.10. 16:02'; Size = 256GB }); Resets = 3; LastReset = '14.10. 16:02' }
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '02b-start-laufwerkshinweis'
                    Write-Host "Laufwerkshinweis: $($ui.DriveWarnTitle.Text) | $($ui.DriveWarnText.Text)"
                    # Probezeit: gestellter Wechsel des Grafiktreibers vor 3 Tagen, seitdem ein Bluescreen und zwei Aussetzer
                    $script:ProbeBackup = @{ Drivers = $script:History.Drivers; Probation = $script:History.Probation }
                    $id = 'PCI\VEN_10DE&DEV_2206&PROBELAUF'
                    $script:History.Drivers = @{ $id = @{ Name = 'NVIDIA GeForce RTX 3080'; Version = '32.0.15.6094'; Class = 'DISPLAY' } }
                    $script:History.Probation = @()
                    $script:Settings.ProbeWarnHidden = ''
                    $now = Get-Date
                    $at = { param($h) @{ Text = $now.AddHours(-$h).ToString('dd.MM. HH:mm'); Ticks = $now.AddHours(-$h).Ticks } }
                    Update-Probation @{
                        Drivers  = @(@{ Id = $id; Name = 'NVIDIA GeForce RTX 3080'; Version = '32.0.16.1742'; Class = 'DISPLAY' })
                        Installs = @{ ($id.ToUpper()) = $now.AddDays(-3).Ticks }
                        Crashes  = @{ Blue = @(@{ When = & $at 20; Code = [uint32]0x116 }); Off = @(); Tdr = @(@{ When = & $at 30 }, @{ When = & $at 50 }); Apps = @() }
                    }
                    $p = @($script:History.Probation)[0]
                    Write-Host "Probezeit: $($p.Name) $($p.Old) -> $($p.New), $($p.Verdict), seitdem $($p.After), davor $($p.Before) in $($p.BeforeDays) Tagen, Quelle $($p.Source)"
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '02c-start-treiberhinweis'
                    Write-Host "Treiberhinweis: $($ui.ProbeWarnTitle.Text) | $($ui.ProbeWarnText.Text)"
                    $ui.DriveWarn.Visibility = 'Collapsed'; $script:LastDrives = $null
                    $ui.ProbeWarn.Visibility = 'Collapsed'
                    Start-Scan
                }
            },
            @{ Wait = 2500; Do = { Save-Snapshot '03-scan' } },
            @{ Until = { -not $script:Busy -and $script:Page -eq 'Results' }; Timeout = 30000; Do = { } },
            @{ Wait = 1600; Do = { Save-Snapshot '04-ergebnisse'; Show-Page 'Tools' } },
            @{ Wait = 1700; Do = { Save-Snapshot '05-werkzeuge'; Open-ToolDialog 'FixAudio' } },
            @{ Wait = 1000; Do = { Save-Snapshot '06-dialog'; Start-DialogJob } },
            @{ Until = $idle; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '07-dialog-lauf'; Close-Dialog; Show-Page 'Boost' } },
            # eingeschalteter Boost: ein vorgetäuschter Zustand, solange es keinen echten gibt - danach wieder weg
            @{ Wait = 2700; Do = {
                    Save-Snapshot '08-boost'
                    $script:SnapBoost = Join-Path $script:OutDir 'Spiel-Beschleunigung.json'
                    if (-not (Test-Path -LiteralPath $script:SnapBoost)) {
                        @{ Time = (Get-Date).ToString('dd.MM.yyyy HH:mm'); Services = @('SysMain', 'WSearch'); ClosedApps = @('Spotify'); PowerPlan = 'x'
                            FreeBefore = [long](12.4GB); FreeAfter = [long](13.9GB) } | ConvertTo-Json | Set-Content -LiteralPath $script:SnapBoost -Encoding UTF8
                        $script:SnapBoostFake = $true
                    }
                    Update-Boost
                }
            },
            @{ Wait = 1900; Do = {
                    Save-Snapshot '09-boost-an'
                    if ($script:SnapBoostFake) { Remove-Item -LiteralPath $script:SnapBoost -Force -Confirm:$false; $script:SnapBoostFake = $false }
                    Update-Boost; Open-Drawer
                }
            },
            # Seitenmenü und Designs
            @{ Wait = 1300; Do = { Save-Snapshot '10-menue'; Set-Theme 'Smaragd' } },
            @{ Wait = 900; Do = { Save-Snapshot '11-design-smaragd'; Set-Theme 'Graphit' } },
            @{ Wait = 900; Do = { Save-Snapshot '12-design-graphit'; Set-Theme 'Eigene' 150 } },
            @{ Wait = 900; Do = { Save-Snapshot '13-design-eigen'; Set-Theme 'Lila-Nacht'; Open-SettingsSheet 0 } },
            # Dialoge mit Reitern
            @{ Wait = 1300; Do = {
                    Save-Snapshot '14-einstellungen'
                    # Schalter "Animationen" aus- und wieder einschalten, Reiter per Klick wechseln
                    $toggle = Find-Visual $ui.SheetPanel ([Windows.Controls.CheckBox]) | Select-Object -First 1
                    Invoke-TestClick $toggle $false
                    $off = $script:Settings.Animations
                    Invoke-TestClick $toggle $true
                    Write-Host "Schalter Animationen: nach Aus-Klick $off, nach An-Klick $($script:Settings.Animations)"
                    Invoke-TestClick $script:SheetTabButtons[1] $true
                    Write-Host "Reiter per Klick: $($script:Sheet.Tab)"
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '15-einstellungen-design'
                    # Design und Ring über die Knöpfe im Reiter wechseln und wieder zurück
                    $chips = @(Find-Visual $ui.SheetPanel ([Windows.Controls.Button]) | Where-Object { $_.Uid })
                    Invoke-TestClick ($chips | Where-Object { $_.Uid -eq 'Tiefsee' })
                    Invoke-TestClick ($chips | Where-Object { $_.Uid -eq 'Komet' })
                    Write-Host "Design-Reiter per Klick: $($script:Theme.Name), Ring $($script:Settings.Ring)"
                    Set-RingStyle 'Puls'
                    Set-Theme 'Eigene' 150 -Instant
                }
            },
            @{ Wait = 700; Do = { Save-Snapshot '15a-einstellungen-eigener-farbton'; Set-Theme 'Lila-Nacht' -Instant; Select-SheetTab 3 } },
            @{ Wait = 900; Do = { Save-Snapshot '15b-einstellungen-treiber'; Select-SheetTab 5 } },
            @{ Wait = 900; Do = { Save-Snapshot '15c-einstellungen-hintergrund'; Close-Sheet } },
            @{ Wait = 500; Do = { Open-BoostSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Lists }; Timeout = 40000; Do = { } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '16-boost-programme'
                    # Klick auf ein Auswahlkästchen der Liste, dann "Empfohlene Auswahl" und Speichern
                    $box = Find-Visual $ui.SheetList ([Windows.Controls.CheckBox]) | Where-Object { $_.Visibility -eq 'Visible' } | Select-Object -Last 1
                    Invoke-TestClick $box $true
                    Write-Host "Nach Klick auf `"$($box.DataContext.Title)`": $($ui.SheetState.Text)"
                    Set-BoostRecommended
                    Write-Host "Empfohlene Auswahl: $($ui.SheetState.Text)"
                    $ui.SheetSearch.Text = 'spot'
                    Write-Host "Suche 'spot': $(@($ui.SheetList.ItemsSource).Count) Zeilen"
                    $ui.SheetSearch.Text = ''
                    Save-BoostSheet
                    Write-Host "Gespeichert: $((Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).Boost | ConvertTo-Json -Compress)"
                    Select-SheetTab 1
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '17-boost-dienste'; Select-SheetTab 2 } },
            @{ Wait = 900; Do = { Save-Snapshot '18-boost-weitere'; Select-SheetTab 3 } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '18b-boost-spiele'
                    Write-Host "Spiele, die Windows kennt: $(@($script:Sheet.Lists[3] | Where-Object { $_.Kind -eq 'row' -and $_.Data -and $_.Data.Type -eq 'game' }).Count)"
                    Close-Sheet
                }
            },
            @{ Wait = 500; Do = { Open-RuntimeSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Components }; Timeout = 40000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '19-komponenten'; Select-SheetTab 1 } },
            @{ Wait = 900; Do = { Save-Snapshot '20-dateien'; Close-Sheet } },
            # Neuinstallation: im Bildordner eine Probe-Sicherung mit Programmliste, damit "Danach einspielen" etwas zeigt
            @{ Wait = 500; Do = { Open-ReinstallSheet } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '20a-neuinstallation-vorher'
                    $probe = Join-Path $Snapshot 'Neuinstallation_Probe'
                    New-Item -ItemType Directory -Path $probe -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $probe 'Programme.json') -Encoding UTF8 -Value '{"Sources":[{"Packages":[{"PackageIdentifier":"Valve.Steam"},{"PackageIdentifier":"Discord.Discord"},{"PackageIdentifier":"Mozilla.Firefox"}]}]}'
                    Set-ReinstallFolder $probe
                    $script:Sheet.Programs[0].Checked = $true
                    Select-SheetTab 1
                    Write-Host "Neuinstallation: $(@($script:Sheet.Programs).Count) Programme aus der Probe-Sicherung"
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '20b-neuinstallation-danach'; Close-Sheet } },
            @{ Wait = 500; Do = { Open-RescueStickSheet } },
            @{ Wait = 900; Do = { Save-Snapshot '20c-notfall-stick'; Close-Sheet } },
            @{ Wait = 500; Do = { Open-SystemSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Info }; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '21-system'; Select-SheetTab 2 } },
            @{ Wait = 5200; Do = { Save-Snapshot '22-system-prozessor'; Close-Sheet } },
            @{ Wait = 500; Do = { Open-HistorySheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.History }; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '23-verlauf'; Select-SheetTab 1 } },
            @{ Wait = 900; Do = { Save-Snapshot '24-pakete'; Close-Sheet; Show-Page 'Results' } },
            # Ergebnisse mit der Liste aller Treiber, Suche, Aufklappmenü und Einzelheiten
            @{ Wait = 1500; Do = {
                    $ui.ResultSearch.Text = 'usb'
                    $shown = @($ui.ResultList.Children | Where-Object { $_ -is [Windows.Controls.Border] -and $_.Visibility -eq 'Visible' }).Count
                    Write-Host "Suche 'usb': $shown Zeilen sichtbar"
                }
            },
            @{ Wait = 600; Do = {
                    Save-Snapshot '25-ergebnisse-suche'
                    $ui.ResultSearch.Text = ''
                    # die Zeile mit den meisten Einträgen im Menü, danach eine mit "Ignorieren"
                    $rows = @($ui.ResultList.Children | Where-Object { $_ -is [Windows.Controls.Border] -and $_.FindName('More').Visibility -eq 'Visible' })
                    $more = $rows | Sort-Object { @($_.FindName('More').Tag).Count } -Descending | Select-Object -First 1
                    Show-RowMenu $more.FindName('More')
                    Write-Host "Aufklappmenü: $($ui.RowMenuItems.Children.Count) Einträge, offen: $($ui.RowMenu.IsOpen)"
                }
            },
            @{ Wait = 700; Do = {
                    Save-Snapshot '26-zeilenmenue' $ui.RowMenu.Child
                    $ui.RowMenu.IsOpen = $false
                    $first = @($ui.ResultList.Children | Where-Object { $_ -is [Windows.Controls.Border] -and $_.FindName('More').Visibility -eq 'Visible' })[0]
                    Show-RowMenu $first.FindName('More')
                }
            },
            @{ Wait = 700; Do = { Save-Snapshot '26b-zeilenmenue-ignorieren' $ui.RowMenu.Child; $ui.RowMenu.IsOpen = $false; Open-UpdateDialog } },
            # Einstieg des Aktualisieren-Dialogs; gestartet wird hier nichts
            @{ Wait = 1000; Do = { Save-Snapshot '26c-aktualisieren'; Close-Dialog } },
            # Einstiege der Dialoge für Spielkomponenten und für das Sichern eines Treibers
            @{ Wait = 500; Do = { Open-RuntimeInstall @('Visual C++ 2013 (x64)', 'Visual C++ 2015-2022 (x64)', 'DirectX-Laufzeit', 'XNA Framework 4.0') } },
            @{ Wait = 1000; Do = { Save-Snapshot '26d-komponenten-installieren'; Close-Dialog } },
            @{ Wait = 500; Do = { Open-ExportDialog $demoResult.Drivers[0] } },
            @{ Wait = 1000; Do = { Save-Snapshot '26e-treiber-sichern'; Close-Dialog } },
            # Rückfrage eines Werkzeugs: nur die Anzeige, es läuft dabei nichts und es wird nichts beantwortet
            @{ Wait = 500; Do = {
                    Open-ToolDialog 'FixAudio'
                    $ui.DialogIntro.Visibility = 'Collapsed'
                    $ui.LogFrame.Opacity = 1
                    Add-Log '  [ ok ] Dienst "Windows-Audio-Endpunkterstellung" - läuft, Starttyp automatisch' 'Green' $false
                    Add-Log '  [ !! ] Dienst "Windows-Audio" - gestoppt' 'Yellow' $false
                    Show-Prompt 'Dienst "Windows-Audio" jetzt starten?' 'confirm'
                }
            },
            @{ Wait = 1000; Do = { Save-Snapshot '26f-rueckfrage'; Hide-Prompt; Show-Prompt 'Welche schließen? Nummern mit Komma oder Eingabetaste für keines' 'input' } },
            @{ Wait = 1000; Do = { Save-Snapshot '26g-rueckfrage-eingabe'; Hide-Prompt; Close-Dialog } },
            @{ Wait = 500; Do = { Open-DetailSheet $demoResult.Drivers[0] } },
            @{ Wait = 1100; Do = { Save-Snapshot '27-einzelheiten'; Close-Sheet; Show-Page 'Hardware' } },
            @{ Wait = 1200; Do = { Save-Snapshot '28-hardware'; Open-DriveSheet } },
            @{ Until = { $script:Sheet -and $script:Sheet.Drives }; Timeout = 30000; Do = { } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28a-laufwerke'
                    Write-Host "Laufwerke: $(@($script:Sheet.Drives.Disks).Count), Volumes: $(@($script:Sheet.Drives.Volumes).Count), Zuverlässigkeitswerte: $($script:Sheet.Drives.Detailed)"
                    Select-SheetTab 1
                }
            },
            @{ Wait = 1500; Do = { Save-Snapshot '28b-laufwerke-einzelheiten'; Select-SheetTab 2 } },
            # Tempotest nur auf Wunsch (Umgebungsvariable PULSRIG_TEMPO = Laufwerksbuchstabe): er schreibt eine Testdatei
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28c-laufwerke-tempo'
                    if ($env:PULSRIG_TEMPO) { Start-DriveSpeed $env:PULSRIG_TEMPO }
                    else {
                        # gestellte Messwerte (schnelle NVMe, Festplatte, gestörte SATA-SSD), nur für das Bild
                        $script:SpeedBackup = $script:DriveSpeed.Clone()
                        $letters = @($script:Sheet.Drives.Volumes | ForEach-Object { $_.Letter })
                        $fake = @(@(2140, 1667, 60.3), @(80, 50, 0.4), @(0.7, 333, 20.7))
                        for ($i = 0; $i -lt [Math]::Min(3, $letters.Count); $i++) {
                            $script:DriveSpeed[$letters[$i]] = @{ Letter = $letters[$i]; Read = $fake[$i][0]; Write = $fake[$i][1]; Small = $fake[$i][2]
                                SizeMb = 1024; Date = '12.10.2026'; Time = '20:21'; Error = '' }
                        }
                        Show-DriveSpeedTab
                    }
                }
            },
            @{ Wait = 900; Do = {
                    if (-not $env:PULSRIG_TEMPO) {
                        Save-Snapshot '28c2-laufwerke-tempo-werte'
                        # gestellter Verlauf über drei Wochen: das erste Laufwerk unauffällig, das dritte mit wachsenden Störungen
                        $script:HistoryBackup = $script:History
                        $script:History = @{ Disks = @{}; Speed = @{} }
                        $disks = @($script:Sheet.Drives.Disks)
                        for ($i = 0; $i -lt $disks.Count; $i++) {
                            $list = @()
                            for ($day = 20; $day -ge 0; $day--) {
                                $list += @{ D = (Get-Date).AddDays(-$day).ToString('yyyy-MM-dd'); F = $(if ($i -eq 2) { [int]((20 - $day) / 2) } else { 0 }); H = 'Healthy'; T = 34 + $i * 3 + ($day % 4); W = $(if ($i -eq 0) { 2 + [int]((20 - $day) / 10) }) }
                            }
                            $script:History.Disks[(Get-DiskKey $disks[$i])] = $list
                        }
                        foreach ($letter in @($script:DriveSpeed.Keys)) {
                            $now = $script:DriveSpeed[$letter]
                            $script:History.Speed[$letter] = @(@{ D = '01.10.2026'; R = [double]$now.Read * $(if ($disks.Count -gt 2 -and $letter -eq "$(@($disks[2].Letters)[0])") { 6 } else { 1.02 }) }, @{ D = $now.Date; R = [double]$now.Read })
                        }
                        Select-SheetTab 3
                    }
                }
            },
            @{ Wait = 900; Do = {
                    if (-not $env:PULSRIG_TEMPO) {
                        Save-Snapshot '28c3-laufwerke-verlauf'
                        $script:History = $script:HistoryBackup
                        $script:DriveSpeed = $script:SpeedBackup
                        Select-SheetTab 2
                    }
                }
            },
            @{ Until = { -not $env:PULSRIG_TEMPO -or $script:DriveSpeed[$env:PULSRIG_TEMPO] }; Timeout = 240000; Do = { } },
            @{ Wait = 1500; Do = {
                    if ($env:PULSRIG_TEMPO) {
                        $speed = $script:DriveSpeed[$env:PULSRIG_TEMPO]
                        Write-Host ('Tempo {0}: Schreiben {1:N0}, Lesen {2:N0}, klein {3:N1} MB/s, Fehler "{4}"' -f $speed.Letter, $speed.Write, $speed.Read, $speed.Small, $speed.Error)
                        Save-Snapshot '28d-laufwerke-tempo-gemessen'
                    }
                    Close-Sheet -Quick; Open-MemorySheet
                }
            },
            @{ Until = { $script:Sheet -and $script:Sheet.Memory }; Timeout = 30000; Do = { } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28e-arbeitsspeicher'
                    Write-Host "Riegel: $(@($script:Sheet.Memory.Modules).Count), Steckplätze: $($script:Sheet.Memory.Slots), Hardwarefehler: $($script:Sheet.Memory.Hardware), Test im Protokoll: $([bool]$script:Sheet.Memory.Test)"
                    # zur Probe so tun, als steckten die Riegel im jeweils ersten Steckplatz ihres Kanals: das muss auffallen
                    $places = @($script:Sheet.Memory.Layout)
                    if ($places.Count -eq 4 -and $places[0].Module -lt 0 -and $places[2].Module -lt 0) {
                        $script:MemoryProbe = @($places | ForEach-Object { $_.Module })
                        $places[0].Module = $places[1].Module; $places[1].Module = -1
                        $places[2].Module = $places[3].Module; $places[3].Module = -1
                        $script:SheetWay = 0
                        Show-MemoryTab
                    }
                }
            },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28e2-arbeitsspeicher-falsch-gesteckt'
                    $places = @($script:Sheet.Memory.Layout)
                    if ($script:MemoryProbe) { for ($i = 0; $i -lt $places.Count; $i++) { $places[$i].Module = $script:MemoryProbe[$i] } }
                    Select-SheetTab 1
                }
            },
            @{ Wait = 1500; Do = { Save-Snapshot '28f-arbeitsspeicher-test'; Close-Sheet -Quick; Open-SensorSheet } },
            @{ Wait = 6500; Do = {
                    Save-Snapshot '28g-sensoren'
                    $seen = $sync.Sensors
                    Write-Host ('Sensoren: Stand {0}, GPU {1} °C / {2} % / Lüfter {3} % / {4} W, CPU {5:N0} % / {6:N2} GHz, RAM {7:N0} %' -f $seen.Stamp, $seen.GpuTemp, $seen.GpuLoad, $seen.GpuFan, $seen.GpuPower, $seen.CpuLoad, $seen.CpuClock, $seen.Ram)
                    Write-Host "Prozessor-Temperatur: geladen $($script:CpuTempLoaded), gesehen $($script:CpuTempSeen), $(if ($script:CpuTempLoaded) { Get-CpuTempReport })"
                    # ab hier eine gestellte Temperatur des Prozessors: Sensoren und Stabilitätstest mit den Kacheln dafür
                    $sync.CpuTempDemo = 66
                    Close-Sheet -Quick; Open-SensorSheet
                }
            },
            @{ Wait = 4500; Do = {
                    Save-Snapshot '28g2-sensoren-prozessor'
                    Write-Host ('Mit Prozessor-Temperatur: {0} Kacheln, CPU {1:N0} °C / {2:N0} W' -f $script:SensorTiles.Count, $sync.Sensors.CpuTemp, $sync.Sensors.CpuPower)
                    Close-Sheet -Quick; Open-StressSheet
                }
            },
            # Stabilitätstest: zwölf Sekunden Volllast für Prozessor und Grafikkarte, dann muss er von selbst "Bestanden" melden
            @{ Wait = 2500; Do = { Save-Snapshot '28h-stabilitaet'; Start-Stress 12 } },
            @{ Wait = 8000; Do = {
                    Save-Snapshot '28i-stabilitaet-lauf'
                    $seen = $sync.Sensors
                    Write-Host ('Unter Last: CPU {0:N0} % / {1:N2} GHz, GPU {2} % / {3} °C, Rechenproben {4}, Fehler {5}, Grafiklast aktiv {6}' -f $seen.CpuLoad, $seen.CpuClock, $seen.GpuLoad, $seen.GpuTemp, [PulsRigStress]::Iterations, [PulsRigStress]::Errors, [PulsRigStress]::GpuActive)
                }
            },
            @{ Until = { -not $script:Stress }; Timeout = 30000; Do = { } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28j-stabilitaet-ergebnis'
                    Write-Host "Ergebnis: $($script:StressResult.Title) | $($script:StressResult.Text)"
                    # die Ergebnisse müssen einen Neustart überstehen: vergessen, aus der Datei holen, vergleichen
                    $script:StressResult = $null; $script:DriveSpeed = @{}
                    Import-HardwareResults
                    Write-Host "Wieder eingelesen: $($script:StressResult.Title) | Tempo für: $(@($script:DriveSpeed.Keys | Sort-Object) -join ', ')"
                    $script:SnapPassed = $script:StressResult
                    # nach jedem vorgetäuschten Abbruch: Bild, Meldung, und ob die Last wirklich steht
                    $script:SnapAbort = {
                        param([string]$Name)
                        Save-Snapshot "28j-abbruch-$Name"
                        Write-Host "Abbruch ${Name}: Test läuft noch $([bool]$script:Stress) | $($script:StressResult.Title) | $($script:StressResult.Text) | Last danach: CPU $([PulsRigStress]::CpuActive), GPU $([PulsRigStress]::GpuActive)"
                    }
                    $script:SnapField = { param([string]$Field, $Value) [PulsRigStress].GetField($Field, [Reflection.BindingFlags]'NonPublic, Static').SetValue($null, $Value) }
                }
            },
            # Abbruchwege des Stabilitätstests: auf einem gesunden PC löst sie nichts aus, also werden die Auslöser
            # vorgetäuscht - ein Messwert von 93 °C, ein Rechenfehler, ein eingebrochener Takt, ausbleibende Messwerte,
            # ein geschlossenes Grafikfenster. Jedes Mal muss der Test von selbst enden und die Last stehen.
            @{ Wait = 500; Do = { Start-Stress 60 } },
            @{ Wait = 4000; Do = { $sync.Sensors = @{ Stamp = 900001; GpuTemp = 93.0; CpuClock = 4.2 }; Update-Stress } },
            # die vorgetäuschten 93 °C wieder wegnehmen, sonst bricht der nächste Lauf sofort mit "Zu heiß" ab
            @{ Wait = 1500; Do = { & $script:SnapAbort 'heiss'; $sync.Sensors = @{ Stamp = 0 }; Start-Stress 60 } },
            @{ Wait = 4000; Do = { & $script:SnapField 'errors' ([long]2); Update-Stress } },
            @{ Wait = 1500; Do = { & $script:SnapAbort 'rechenfehler'; Start-Stress 60 } },
            @{ Wait = 4000; Do = {
                    $script:Stress.BaseClock = 4.3
                    $script:Stress.Start = [DateTime]::UtcNow.AddSeconds(-25)
                    for ($i = 1; $i -le 6 -and $script:Stress; $i++) { $sync.Sensors = @{ Stamp = 900010 + $i; CpuClock = 2.0 }; Update-Stress }
                }
            },
            @{ Wait = 1500; Do = { & $script:SnapAbort 'drosselt'; $sync.Sensors = @{ Stamp = 0 }; Start-Stress 60 } },
            @{ Wait = 4000; Do = {
                    # der Messbereich kann dazwischen einen neuen Wert liefern, deshalb bis zu fünf Anläufe
                    for ($i = 1; $i -le 5 -and $script:Stress; $i++) {
                        $script:Stress.HadTemp = $true
                        $script:Stress.Stamp = $sync.Sensors.Stamp
                        $script:Stress.Seen = [DateTime]::UtcNow.AddSeconds(-11)
                        Update-Stress
                    }
                }
            },
            @{ Wait = 1500; Do = { & $script:SnapAbort 'ueberwachung'; Start-Stress 60 } },
            @{ Wait = 7500; Do = { & $script:SnapField 'gpuRun' $false } },
            @{ Until = { -not $script:Stress }; Timeout = 10000; Do = { } },
            @{ Wait = 1500; Do = {
                    & $script:SnapAbort 'fenster-zu'
                    # für den Prüfbericht gilt wieder das bestandene Ergebnis von oben
                    $script:StressResult = $script:SnapPassed
                    Save-HardwareResults
                    Close-Sheet -Quick; Open-ReportSheet
                }
            },
            # Prüfbericht: muss das Ergebnis des Stabilitätstests und der Tempomessung enthalten und sich speichern lassen
            @{ Until = { $script:Sheet -and $script:Sheet.Report }; Timeout = 60000; Do = { } },
            @{ Wait = 1800; Do = { Save-Snapshot '28k-bericht'; Select-SheetTab 1 } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28l-bericht-geraet'
                    Select-SheetTab 0
                    Save-Report
                    $verdict = Get-ReportVerdict (Get-ReportChecks $script:Sheet.Report)
                    Write-Host "Bericht: $($verdict.Title) | $($verdict.Rest) | Datei $($script:Sheet.ReportPath), $([int]((Get-Item -LiteralPath $script:Sheet.ReportPath).Length / 1KB)) KB"
                }
            },
            @{ Wait = 1200; Do = { Save-Snapshot '28m-bericht-gespeichert'; Close-Sheet -Quick; Open-DiagnoseSheet } },
            @{ Wait = 1500; Do = { Save-Snapshot '28n-diagnose'; & $script:Sheet.OnPrimary; Write-Host "Diagnose-Paket: $(if ($script:Sheet.File) { "$(Split-Path -Leaf $script:Sheet.File), $([int]((Get-Item -LiteralPath $script:Sheet.File).Length / 1KB)) KB" } else { 'nicht erstellt' })" } },
            @{ Wait = 1200; Do = { Save-Snapshot '28o-diagnose-erstellt'; Close-Sheet -Quick; Open-CrashSheet } },
            # Abstürze: erst der echte Stand dieses PCs, dann gestellte Befunde, damit jede Art Zeile einmal zu sehen ist
            @{ Until = { $script:Sheet -and $script:Sheet.Crashes }; Timeout = 30000; Do = { } },
            @{ Wait = 900; Do = {
                    $c = $script:Sheet.Crashes
                    Write-Host "Abstürze: Bluescreens $(@($c.Blue).Count), ausgegangen $(@($c.Off).Count), Grafik $(@($c.Tdr).Count), im Treiber $(@($c.Apps).Count), WHEA $($c.Whea), lesbar $($c.Log)"
                    Save-Snapshot '28q-abstuerze'
                    $now = Get-Date
                    $stamp = { param($h) @{ Text = $now.AddHours(-$h).ToString('dd.MM. HH:mm'); Ticks = $now.AddHours(-$h).Ticks } }
                    $script:Sheet.Crashes = @{
                        Blue = @(@{ When = & $stamp 20; Code = [uint32]0x116; Dump = '' }, @{ When = & $stamp 70; Code = [uint32]0x116; Dump = '' }, @{ When = & $stamp 200; Code = [uint32]0x1000007E; Dump = '' })
                        Off  = @(@{ When = & $stamp 50; Button = $true; Sleep = $false })
                        Tdr  = @(@{ When = & $stamp 21; Driver = 'nvlddmkm' }, @{ When = & $stamp 95; Driver = 'nvlddmkm' })
                        Apps = @(@{ When = & $stamp 21; App = 'cs2.exe'; Module = 'nvwgf2umx.dll' })
                        Whea = 0; LastWhea = ''; Log = $true; Time = $now.ToString('HH:mm')
                        Gpu  = @{ Name = 'NVIDIA GeForce RTX 3080'; Version = '32.0.16.1742'; Date = '30.09.2026' }
                    }
                    Show-CrashTab
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28r-abstuerze-beispiel'
                    # die gestellte Probezeit vom Anfang des Rundgangs wieder herausnehmen
                    if ($script:ProbeBackup) { $script:History.Drivers = $script:ProbeBackup.Drivers; $script:History.Probation = $script:ProbeBackup.Probation }
                    Open-BiosSheet
                }
            },
            @{ Until = { $script:Sheet -and $script:Sheet.Bios }; Timeout = 30000; Do = { } },
            @{ Wait = 900; Do = {
                    Write-Host "BIOS: $($script:Sheet.Bios.Version) vom $($script:Sheet.Bios.Date) · $($script:Sheet.Bios.Board)"
                    Save-Snapshot '28s-bios'
                    # "Was hat sich geändert?" mit zwei gestellten Tagesbildern im Abstand von 8 Tagen
                    $script:SnapBackup = @{ Snapshots = $script:History.Snapshots; Crashes = $script:LastCrashes }
                    $id = 'PCI\VEN_10DE&DEV_2206&PROBELAUF'
                    $now = Get-Date
                    $script:History.Snapshots = @(
                        @{ D = $now.AddDays(-8).ToString('yyyy-MM-dd'); Windows = '26100.6584 (25H2)'; Plan = 'Ausbalanciert'
                            Programs = @('Discord|1.0.9|', 'Google Chrome|141.0|', 'Steam|2.10|'); Autostart = @('Spotify|aus', 'Steam|an')
                            Drivers = @("$id|NVIDIA GeForce RTX 3080|32.0.15.6094|DISPLAY") },
                        @{ D = $now.ToString('yyyy-MM-dd'); Windows = '26100.6725 (25H2)'; Plan = 'Ultimative Leistung'
                            Programs = @('Discord|1.0.10|', 'Google Chrome|142.0|', 'OBS Studio|32.0|', 'Steam|2.10|'); Autostart = @('RazerAppEngine|an', 'Spotify|an', 'Steam|an')
                            Drivers = @("$id|NVIDIA GeForce RTX 3080|32.0.16.1742|DISPLAY") })
                    $script:LastCrashes = @{ Blue = @(@{ When = @{ Text = $now.AddDays(-2).ToString('dd.MM. HH:mm'); Ticks = $now.AddDays(-2).Ticks } }); Off = @()
                        Tdr = @(@{ When = @{ Text = $now.AddDays(-1).ToString('dd.MM. HH:mm'); Ticks = $now.AddDays(-1).Ticks } }); Apps = @() }
                    Update-ChangesTile
                    Write-Host "Änderungen-Kachel: $($ui.HomeChangesText.Text)"
                    Close-Sheet -Quick
                    Open-ChangesSheet
                    Select-SheetTab 1
                }
            },
            @{ Wait = 1200; Do = {
                    Save-Snapshot '28t-aenderungen'
                    $script:History.Snapshots = $script:SnapBackup.Snapshots; $script:LastCrashes = $script:SnapBackup.Crashes
                    Update-ChangesTile
                    Close-Sheet -Quick
                    Open-GameCheckSheet
                }
            },
            # Gaming-Check mit den echten Einstellungen dieses PCs
            @{ Until = { $script:Sheet -and $script:Sheet.GameCheck }; Timeout = 30000; Do = { } },
            @{ Wait = 900; Do = {
                    $checks = @(Get-GameChecks $script:Sheet.GameCheck)
                    Write-Host "Gaming-Check: $(Get-GameScore $checks) von 100 · $(@($checks | ForEach-Object { "$($_.Name)=$($_.Tone)/$($_.State)" }) -join ', ')"
                    Save-Snapshot '28u-gaming-check'
                    # gestellte schlechte Werte: jede Zeile einmal gelb oder rot, alles muss ohne Scrollen passen
                    $real = $script:Sheet.GameCheck
                    $script:Sheet.GameCheck = @{ Displays = @(@{ Name = 'Samsung Odyssey G5'; Width = 2560; Height = 1440; Hz = 60; Max = 165; Primary = $true }); Bar = 256; Gpu = 'NVIDIA GeForce RTX 4070'
                        Hags = 1; Hvci = $true; PlanGuid = 'a1841308-3541-4fab-bc81-f71556f20b4a'; Plan = 'Energiesparmodus'; Battery = $false; GameMode = $false
                        Memory = @{ Modules = @(@{ Speed = 2133; Rated = 2133; Part = 'F4-3600C16-16GVKC'; Bytes = 16GB; Type = 'DDR4' }) } }
                    Show-GameCheckTab
                    $script:Sheet.GameCheck = $real
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28v-gaming-check-beispiel'; Close-Sheet -Quick; Open-GpuShieldSheet } },
            # Grafiktreiber schützen mit den echten Grafikkarten (nur gelesen, nichts versteckt)
            @{ Until = { $script:Sheet -and $script:Sheet.GpuShield }; Timeout = 90000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '28v2-treiberschutz'; Close-Sheet -Quick; Open-StandbySheet } },
            # Standby-Detektiv mit den echten Daten dieses PCs
            @{ Until = { $script:Sheet -and $script:Sheet.Standby }; Timeout = 30000; Do = { } },
            @{ Wait = 900; Do = {
                    $s = $script:Sheet.Standby
                    Write-Host "Standby: $(@($s.Wakes).Count)-mal aufgewacht, Weckgeräte $(@($s.Armed).Count), Timer $($s.Timers), Standby nach $($s.Idle) s, Anfragen $(@($s.Requests).Count), Admin nötig $($s.NeedsAdmin)"
                    Save-Snapshot '28w-standby-aufwachen'
                    Select-SheetTab 1
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28x-standby-wach'
                    # gestellte Weckquellen, damit jede Art einmal zu sehen ist
                    $now = Get-Date
                    $wake = { param($h, $source, $owner) @{ Ticks = $now.AddHours(-$h).Ticks; Text = $now.AddHours(-$h).ToString('dd.MM. HH:mm'); Hour = $now.AddHours(-$h).Hour; Source = $source; Type = ''; Owner = $owner } }
                    $script:Sheet.Standby = @{ Log = $true; Timers = 1; Idle = 0; NeedsAdmin = $false; Armed = @('HID-konforme Maus', 'HID-Tastaturgerät', 'Realtek PCIe GbE Family Controller')
                        Wakes = @((& $wake 20 'HID-konforme Maus' ''), (& $wake 44 'HID-konforme Maus' ''), (& $wake 70 '' 'NT TASK\Microsoft\Windows\UpdateOrchestrator\Reboot'), (& $wake 90 'Realtek PCIe GbE Family Controller' ''))
                        Requests = @(@{ Section = 'DISPLAY'; Kind = 'PROCESS'; Name = 'chrome.exe'; Why = 'Video Wake Lock' }, @{ Section = 'SYSTEM'; Kind = 'DRIVER'; Name = 'Realtek High Definition Audio'; Why = 'Ein Audiostream wird zurzeit verwendet.' }) }
                    Select-SheetTab 0
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28y-standby-beispiel'; Select-SheetTab 1 } },
            @{ Wait = 900; Do = { Save-Snapshot '28z-standby-beispiel-wach'; Close-Sheet -Quick; Open-PowerSheet } },
            # Stromverbrauch mit den echten Messwerten dieses PCs (ein paar Sekunden für das Mittel)
            @{ Wait = 4000; Do = {
                    Save-Snapshot '28zz-stromverbrauch'
                    # FPS-Limit-Vergleich mit Beispielwerten: ein Durchgang fertig, einer läuft
                    $script:PowerLimit = @{ Off = @{ Watt = 312.0; GpuGuessed = $false; Time = [DateTime]::Now } }
                    Start-PowerLimitMeasure 'On'
                    $ui.SheetScroll.ScrollToEnd()
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zz-stromverbrauch-fps-messen'
                    $script:PowerLimitRun = $null
                    $script:PowerLimit.On = @{ Watt = 224.0; GpuGuessed = $false; Time = [DateTime]::Now }
                    Update-PowerLimit
                }
            },
            @{ Wait = 700; Do = { Save-Snapshot '28zz-stromverbrauch-fps-ersparnis'; $script:PowerLimit = @{}; Close-Sheet -Quick } },
            # Was ist los? (Problem zuerst): Spiele ruckeln mit der Liste der Spiele, dann Abstürze und Sonstiges
            @{ Wait = 700; Do = { Open-ProblemSheet } },
            @{ Until = { $null -ne $script:Sheet.Games }; Timeout = 30000; Do = {
                    Write-Host "Spiele erkannt: $(@($script:Sheet.Games).Count) | $((@($script:Sheet.Games) | ForEach-Object { "$($_.Name) ($($_.Letter): $($_.Kind))" }) -join ', ')"
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28za-problem-ruckeln'; Select-SheetTab 1 } },
            @{ Wait = 900; Do = { Save-Snapshot '28zb-problem-absturz'; Select-SheetTab 5 } },
            # gestellte Abstürze: "Schon gefunden" oben in den Reitern Abstürze und Ruckeln, dazu die Zeile des Prüfberichts
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zc-problem-sonstiges'
                    $script:CrashBackup = $script:LastCrashes
                    $now = Get-Date
                    $stamp = { param($h) @{ Text = $now.AddHours(-$h).ToString('dd.MM. HH:mm'); Ticks = $now.AddHours(-$h).Ticks } }
                    $script:LastCrashes = @{
                        Blue = @(@{ When = & $stamp 20; Code = [uint32]0x116; Dump = '' }, @{ When = & $stamp 200; Code = [uint32]0x1000007E; Dump = '' })
                        Off  = @(@{ When = & $stamp 50; Button = $true; Sleep = $false })
                        Tdr  = @(@{ When = & $stamp 30; Driver = 'nvlddmkm' }, @{ When = & $stamp 60; Driver = 'nvlddmkm' })
                        Apps = @(@{ When = & $stamp 31; App = 'cs2.exe'; Module = 'nvwgf2umx.dll' })
                        Whea = 1; LastWhea = $now.AddDays(-3).ToString('dd.MM. HH:mm'); Gpu = @{ Version = '32.0.15.6094'; Date = '01.10.2026' }; Log = $true; Time = $now.ToString('HH:mm')
                    }
                    Select-SheetTab 1
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28zcb-problem-absturz-befund'; Select-SheetTab 0 } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zcc-problem-ruckeln-befund'
                    $line = Get-CrashReportCheck $script:LastCrashes
                    Write-Host "Problem-Befund: $(@(Get-ProblemCrashRows).Count) Zeilen, davon Grafik $(@(Get-ProblemCrashRows -Graphics).Count) | Bericht: $($line.Kind) | $($line.Short)"
                    $script:LastCrashes = $script:CrashBackup
                    Invoke-ProblemAction 'crashes'
                }
            },
            @{ Wait = 1500; Do = { Write-Host "Nach Klick auf Abstürze offen: $($ui.SheetTitle.Text)"; Close-Sheet -Quick } },
            # Benchmark: ein echter Lauf in einem Viertel der Zeit (ohne Laufwerk, außer mit PULSRIG_TEMPO) gegen einen
            # gestellten Lauf von vor zwei Tagen mit anderem Grafiktreiber, damit Vergleich und Verlauf im Bild sind
            @{ Wait = 700; Do = {
                    $script:BenchBackup = @{ Runs = $script:History.Benchmarks; Card = $script:CardState.Bench }
                    $old = (Get-Date).AddDays(-2).ToString('dd.MM.yyyy') + ' 21:10'
                    $script:History.Benchmarks = @(@{ D = $old; S = 1100; M = 8600; C = 22.0; L = 58.0; F = 140.0; G = 1400; GN = 'NVIDIA GeForce RTX 3080/PCIe/SSE2'; GE = ''; CT = 74; GT = 60
                            R = 2100; W = 1880; DL = 'C:'; X = @{ Gpu = '32.0.15.6094'; Ram = 3066; Plan = 'Ausbalanciert'; Win = '26300.6899'; Boost = $false } })
                    Open-BenchSheet
                }
            },
            @{ Wait = 1500; Do = { Save-Snapshot '28zcd-benchmark'; if ($env:PULSRIG_TEMPO) { Start-Bench 0.25 } else { Start-Bench 0.25 -NoDrive } } },
            @{ Wait = 4000; Do = { Save-Snapshot '28zce-benchmark-lauf' } },
            @{ Until = { -not $script:Bench }; Timeout = 90000; Do = { } },
            @{ Wait = 1200; Do = {
                    $run = @(Get-BenchRuns)[-1]
                    Write-Host ('Benchmark: Prozessor {0} (1 Kern {1}) · Grafik {2} ({3} Gpx/s, {4}) · Speicher {5} GB/s, {6} ns · Laufwerk {7} · CPU {8} °C · GPU {9} °C · Fehler {10} | {11}' -f $run.M, $run.S, $run.G, $run.F, $run.GN, $run.C, $run.L, $run.R, $run.CT, $run.GT, $run.GE, (Get-BenchSummary $run @(Get-BenchRuns)[-2]))
                    Save-Snapshot '28zcf-benchmark-fertig'
                    Select-SheetTab 1
                }
            },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zcg-benchmark-verlauf'
                    $script:History.Benchmarks = $script:BenchBackup.Runs
                    if ($script:BenchBackup.Card) { $script:CardState.Bench = $script:BenchBackup.Card } else { $script:CardState.Remove('Bench') }
                    Update-BenchPill
                    Close-Sheet -Quick
                }
            },
            # Spielsitzungen: erst ohne Aufzeichnung (Hinweis), dann zwei gestellte Sitzungen - eine ruhige und eine, in der
            # die Grafikkarte nach 20 Minuten heiß wird und drosselt
            @{ Wait = 700; Do = { Open-SensorSheet 1 } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28zch-spielsitzungen-leer'
                    New-Item -ItemType Directory -Path $script:RecordFolder -Force | Out-Null
                    $culture = [cultureinfo]::InvariantCulture
                    $make = {
                        param([string]$Name, [datetime]$Begin, [int]$Minutes, [bool]$Hot)
                        $lines = @("# PulsRig-Aufzeichnung;Spiel=$Name;Beginn=$($Begin.ToString('yyyy-MM-ddTHH:mm:ss'));Takt=5", 'Sekunde;CpuTemp;CpuLast;CpuTakt;CpuWatt;GpuTemp;GpuLast;GpuWatt;GpuLuefter;GpuTakt')
                        $random = New-Object Random 7
                        for ($s = 5; $s -le $Minutes * 60; $s += 5) {
                            $warm = [Math]::Min(1.0, $s / 600.0)
                            $late = $Hot -and $s -gt 1200
                            $cpu = 52 + 22 * $warm + $random.NextDouble() * 6
                            $gpu = 45 + 25 * $warm + $(if ($late) { 13 } else { 0 }) + $random.NextDouble() * 3
                            $clock = $(if ($late -and $random.NextDouble() -lt 0.6) { 1450 } else { 1905 }) + $random.Next(-15, 15)
                            $lines += [string]::Format($culture, '{0};{1:0.0};{2};{3};{4:0.0};{5:0};{6};{7:0.0};{8};{9}', $s, $cpu, 45 + $random.Next(0, 20), 4300 + $random.Next(-80, 60), 70 + $random.Next(0, 20), $gpu, 97, 290 + $random.Next(0, 30), 55 + [int](20 * $warm), $clock)
                        }
                        [IO.File]::WriteAllLines((Join-Path $script:RecordFolder "$($Begin.ToString('yyyy-MM-dd_HH-mm-ss'))_$Name.csv"), $lines)
                    }
                    & $make 'cs2' (Get-Date).AddDays(-1).Date.AddHours(20) 95 $false
                    & $make 'Cyberpunk2077' (Get-Date).Date.AddHours(-3) 48 $true
                    Show-RecordingTab
                }
            },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28zci-spielsitzungen'
                    $summary = Get-RecordingSummary (Read-Recording (@(Get-Recordings)[0]).FullName)
                    Write-Host "Spielsitzung: $($summary.Tone) | $($summary.Text -replace "`n", ' | ')"
                    Invoke-RecordingAction "pick:$((@(Get-Recordings)[1]).FullName)"
                }
            },
            @{ Wait = 1200; Do = { Save-Snapshot '28zcj-spielsitzungen-ruhig'; $script:RecordPick = $null; Close-Sheet -Quick; Open-GamesSheet } },
            @{ Until = { $script:Sheet -and $null -ne $script:Sheet.Games }; Timeout = 30000; Do = { } },
            @{ Wait = 1200; Do = {
                    Save-Snapshot '28zck-deine-spiele'
                    Write-Host "Deine Spiele: $(@($script:Sheet.Games).Count) | $((@($script:Sheet.Games) | ForEach-Object { "$($_.Name) [$($_.Exe)] $($_.Letter): $($_.Kind)$(if (Get-GameRecording $_.Exe) { ' mit Sitzung' })" }) -join ', ')"
                    # Verschleiß: erst der echte Stand, dann gestellt (zwei Monate, Grafikkarte wird wärmer, SSD nutzt sich ab)
                    Close-Sheet -Quick; Open-SensorSheet 2
                }
            },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28zcl-verschleiss'
                    $script:WearBackup = @{ Thermal = $script:History.Thermal; Disks = $script:History.Disks }
                    $start = (Get-Date).AddDays(-60)
                    $script:History.Thermal = @(for ($i = 0; $i -lt 9; $i++) {
                            $share = $i / 8
                            @{ D = $start.AddDays(60 * $share).ToString('yyyy-MM-dd'); Src = 'Spiel'; Name = 'cs2'; Min = 40
                                GT = 70 + 9 * $share + ($i % 3) - 1; GW = 300 + ($i % 4) * 5; GF = 50 + 22 * $share; CT = 89 + ($i % 2); CC = 4200 - 60 * $share; CW = 80 } })
                    $disk = @($script:LastDrives.Disks | Where-Object { (Get-DriveKind $_) -eq 'SSD' })[0]
                    if ($disk) {
                        $key = Get-DiskKey $disk
                        $script:History.Disks = @{}
                        $script:History.Disks[$key] = @(for ($d = 0; $d -le 120; $d += 30) { @{ D = (Get-Date).AddDays($d - 120).ToString('yyyy-MM-dd'); W = 4 + [int]($d / 30) } })
                    }
                    Show-WearTab
                }
            },
            @{ Wait = 1200; Do = {
                    Save-Snapshot '28zcm-verschleiss-beispiel'
                    Write-Host "Verschleiß: $((Get-CoolingTrend 'G').State) / $((Get-CoolingTrend 'C').State) / $(@(Get-SsdLife | ForEach-Object { "$($_.Title) $($_.State)" }) -join ', ')"
                    $script:History.Thermal = $script:WearBackup.Thermal; $script:History.Disks = $script:WearBackup.Disks
                    Remove-Item -LiteralPath $script:RecordFolder -Recurse -Force -Confirm:$false
                    Close-Sheet -Quick
                }
            },
            # Controller und Maus: erst echt (meist ohne Controller), dann gestellt: Tasten A, LB und ↑ gedrückt, Sticks
            # ausgelenkt, Drift gemessen; Maus mit 1.000 Hz und zwei ungewollten Doppelklicks der linken Taste
            @{ Wait = 700; Do = { Open-InputSheet } },
            @{ Wait = 1500; Do = {
                    Save-Snapshot '28zcn-controller'
                    $script:InputDemo = @{ Pad = @(1, (0x1000 -bor 0x0100 -bor 0x0001), 200, 40, 9000, -3000, -1200, 800)
                        Mouse = @{ Rate = 998.0; Samples = 400; Clicks = @(31, 12, 2, 0, 0); Bounces = @(2, 0, 0, 0, 0); Down = @($true, $false, $false, $false, $false); Wheel = 14; Devices = 1 } }
                    foreach ($key in 0x2000, 0x4000, 0x8000, 0x0200, 0x0010) { $script:InputTest.Seen[$key] = $true }
                    $script:InputTest.DriftResult = @{ Title = 'Stick-Drift gemessen'; Text = "Linker Stick in Ruhe 12 % aus der Mitte (leichter Drift), rechter 3 % (in Ordnung).`nDie meisten Spiele gleichen das mit ihrer Totzone aus. Wird es schlimmer: Stick mit Druckluft reinigen."; Tone = 'warn' }
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28zco-controller-beispiel'; Select-SheetTab 1 } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zcp-maus-beispiel'
                    Write-Host "Controller und Maus: $($ui.SheetState.Text) | Abfragerate $($script:InputTest.Rate.Text)"
                    $script:InputDemo = $null
                    Close-Sheet -Quick
                    # gespeichertes Ergebnis: Zeile im Prüfbericht (gestellt, danach wieder weg)
                    $script:CardState.Input = @{ Text = 'auffällig'; Tone = 'warn'; Detail = 'Maus 1.000 Hz · Drift 12 / 3 %'; Hz = 1000; Clicks = 43; Bounces = 'Links 2×'; DriftL = 12; DriftR = 3; Buttons = '14 von 14'; Date = (Get-Date).ToString('dd.MM.yyyy') }
                    $line = @(Get-ReportChecks @{ Drives = $null; Memory = $null } | Where-Object { $_.Name -eq 'Controller und Maus' })[0]
                    Write-Host "Bericht Controller und Maus: $($line.Kind) | $(T $line.Text) | $(T $line.Short)"
                    $script:CardState.Remove('Input')
                }
            },
            # Akku-Bericht: erst echt (auf einem PC ohne Akku), dann mit gestelltem Notebook-Akku; der Knopf auf der Hardware-Seite
            @{ Wait = 700; Do = { Open-BatterySheet } },
            @{ Until = { $null -ne $script:Sheet.Battery }; Timeout = 30000; Do = { Write-Host "Akku echt: vorhanden $($script:Sheet.Battery.Has), Akkus $(@($script:Sheet.Battery.Batteries).Count)" } },
            @{ Wait = 900; Do = {
                    Save-Snapshot '28zd-akku-echt'
                    $script:Sheet.Battery = @{ Has = $true; Charge = 64; OnPower = $false; Source = 'report'; Runtime = 'PT2H48M'; RuntimeNew = 'PT4H5M'
                        Batteries = @(@{ Name = 'AP18E8M'; Maker = 'SMP'; Chemistry = 'LION'; Design = 58752; Full = 41210; Cycles = 312 })
                        History = @(@{ Month = '2025-11'; Full = 47900; Design = 58752 }, @{ Month = '2026-03'; Full = 45120; Design = 58752 }, @{ Month = '2026-06'; Full = 43380; Design = 58752 }, @{ Month = '2026-10'; Full = 41210; Design = 58752 }) }
                    Show-BatteryTab
                }
            },
            @{ Wait = 900; Do = { Save-Snapshot '28ze-akku-beispiel'; Close-Sheet -Quick; $script:HasBattery = $true; $script:CardState.Battery = @{ Text = '70 %'; Tone = 'warn'; Detail = '312 Ladezyklen'; Date = (Get-Date).ToString('dd.MM.yyyy') }; Update-BatteryPill; Show-Page 'Hardware' } },
            @{ Wait = 1600; Do = { Save-Snapshot '28zf-akku-knopf'; $script:HasBattery = $false; $script:CardState.Remove('Battery'); Update-BatteryPill } },
            # Monitor-Test: Fenster mit den Bildschirmen, dann das Vollbild (erstes Bild, Verlauf, Bewegung) und zurück
            @{ Wait = 600; Do = { Open-MonitorSheet } },
            @{ Until = { $null -ne $script:Sheet.Displays }; Timeout = 30000; Do = { Write-Host "Bildschirme: $((@($script:Sheet.Displays) | ForEach-Object { "$($_.Name) $($_.Width)x$($_.Height) $($_.Hz)/$($_.Max) Hz" }) -join ' | ')" } },
            @{ Wait = 900; Do = { Save-Snapshot '28zg-monitor'; Start-MonitorTest } },
            @{ Wait = 1500; Do = { Save-Snapshot '28zh-monitor-schwarz' $script:MonitorTest.Window; Step-MonitorTest 6 } },
            @{ Wait = 900; Do = { Save-Snapshot '28zi-monitor-verlauf' $script:MonitorTest.Window; Step-MonitorTest 1 } },
            @{ Wait = 1300; Do = { Save-Snapshot '28zj-monitor-bewegung' $script:MonitorTest.Window; Step-MonitorTest 1 } },
            @{ Wait = 700; Do = { Write-Host "Vollbild nach dem letzten Bild geschlossen: $($null -eq $script:MonitorTest)"; Close-Sheet -Quick } },
            # Ping-Test: echte Messung (rund acht Sekunden)
            @{ Wait = 600; Do = { Open-PingSheet } },
            @{ Until = { $null -ne $script:Sheet.Ping }; Timeout = 60000; Do = { Write-Host "Ping: $($script:Sheet.Ping.Link) | $((@($script:Sheet.Ping.Targets) | ForEach-Object { "$($_.Name) $([Math]::Round([double]$_.Avg, 1)) ms, $($_.Lost) verloren" }) -join ' | ')" } },
            @{ Wait = 900; Do = { Save-Snapshot '28zk-ping'; Close-Sheet -Quick } },
            # die Karten der Hardware-Seite müssen jetzt den Stand der Prüfungen zeigen
            @{ Wait = 2200; Do = { Save-Snapshot '28p-hardware-stand'; Show-Page 'Home'; Set-RingStyle 'Klassik' } },
            @{ Wait = 1500; Do = { Write-Host "Last nach dem Schließen noch aktiv: CPU $([PulsRigStress]::CpuActive), GPU $([PulsRigStress]::GpuActive)" } },
            @{ Wait = 100; Do = { Write-Host "Messprozess nach dem Schließen noch da: $([bool](Get-Process nvidia-smi -ErrorAction SilentlyContinue))" } },
            @{ Wait = 1600; Do = { Save-Snapshot '30-ring-klassik'; Set-RingStyle 'Welle' } },
            @{ Wait = 1300; Do = { Save-Snapshot '31-ring-welle'; Set-RingStyle 'RGB' } },
            @{ Wait = 1300; Do = { Save-Snapshot '32-ring-rgb'; Set-RingStyle 'Komet' } },
            @{ Wait = 1300; Do = { Save-Snapshot '33-ring-komet'; Set-RingStyle 'Technik' } },
            @{ Wait = 1300; Do = { Save-Snapshot '34-ring-technik'; Set-RingStyle 'Sechseck' } },
            @{ Wait = 1300; Do = { Save-Snapshot '35-ring-sechseck'; Set-RingStyle 'Orbit' } },
            @{ Wait = 1300; Do = { Save-Snapshot '36-ring-orbit'; Set-RingStyle 'Neon' } },
            @{ Wait = 1300; Do = { Save-Snapshot '37-ring-neon'; Set-RingStyle 'Pac-Man'; Set-Theme 'Neon-Nacht' } },
            @{ Wait = 1300; Do = { Save-Snapshot '38-ring-pacman-neon-nacht'; Set-RingStyle 'Puls' } },
            @{ Wait = 1700; Do = { Save-Snapshot '38b-ring-puls-neon-nacht'; Set-Theme 'Tiefsee' } },
            @{ Wait = 900; Do = { Save-Snapshot '39-design-tiefsee'; Set-Theme 'Aurora' } },
            @{ Wait = 900; Do = { Save-Snapshot '40-design-aurora'; Set-Theme 'Lila-Nacht'; Show-Page 'Boost'; Open-ToolDialog 'GameBoost' } },
            # Boost-Dialog: Einstieg mit Karten, dann die Ausgabe - nur als Probelauf, damit nichts verändert wird
            @{ Wait = 1100; Do = { Save-Snapshot '41-boost-dialog'; if ($script:Dialog.DryRun) { Start-DialogJob } } },
            @{ Until = { -not $script:Busy }; Timeout = 60000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot '42-boost-dialog-lauf'; Close-Dialog; Show-Page 'Home'; Open-HelpSheet 0 } },
            @{ Wait = 1000; Do = { Save-Snapshot '43-hilfe'; Select-SheetTab 1 } },
            @{ Wait = 1000; Do = { Save-Snapshot '44-ueber'; Close-Sheet } },
            # Rechenlast der Daueranimationen auf der Startseite messen: erst zur Ruhe kommen lassen, dann je
            # zehn Sekunden für Pac-Man (Vergleichswert) und für den voreingestellten Ring
            @{ Wait = 4000; Do = { Set-RingStyle 'Pac-Man' } },
            @{ Wait = 3000; Do = { $script:CpuMark = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds } },
            @{ Wait = 10000; Do = {
                    $used = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds - $script:CpuMark
                    Write-Host ('Rechenlast im Leerlauf, Pac-Man: {0:N1} % eines Kerns' -f ($used / 100))
                    Set-RingStyle 'Puls'
                }
            },
            @{ Wait = 3000; Do = { $script:CpuMark = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds } },
            @{ Wait = 10000; Do = {
                    $used = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds - $script:CpuMark
                    Write-Host ('Rechenlast im Leerlauf, Puls: {0:N1} % eines Kerns' -f ($used / 100))
                    $window.Close()
                }
            }
        )
    }
    # Messlauf der Rechenlast (Umgebungsvariable PULSRIG_BENCH): "start" misst gleich nach dem Vorspann,
    # "danach" erst nach dem ganzen Durchlauf. Gemessen wird je Zustand mehrfach und im Wechsel, damit
    # Schwankungen des PCs nicht einem einzelnen Ring zugeschrieben werden.
    if ($env:PULSRIG_BENCH) {
        $script:BenchPlan = @($(if ($env:PULSRIG_BENCH_PLAN) { $env:PULSRIG_BENCH_PLAN } else { 'Ruhe,Pac-Man,Puls,Ruhe,Puls,Pac-Man,Puls,Pac-Man,Ruhe' }) -split ',')
        $script:BenchIndex = 0
        $bench = @()
        foreach ($entry in $script:BenchPlan) {
            $bench += @{ Wait = 400; Do = {
                    $name = $script:BenchPlan[$script:BenchIndex]
                    Suspend-OrbIdle
                    if ($name -ne 'Ruhe') { $script:Settings.Ring = $name; Set-OrbIdle }
                }
            }
            $bench += @{ Wait = 3000; Do = {
                    $script:CpuMark = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds
                    $script:GcMark = [GC]::CollectionCount(0)
                    $script:BenchSince = [DateTime]::UtcNow
                }
            }
            $bench += @{ Wait = $(if ($env:PULSRIG_BENCH_MS) { [int]$env:PULSRIG_BENCH_MS } else { 15000 }); Do = {
                    $used = [Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.TotalMilliseconds - $script:CpuMark
                    $span = ([DateTime]::UtcNow - $script:BenchSince).TotalMilliseconds
                    Write-Host ('MESSUNG {0,-8} {1,5:N1} % eines Kerns   GC {2,3}   Animationen {3}' -f $script:BenchPlan[$script:BenchIndex], (100 * $used / $span),
                        ([GC]::CollectionCount(0) - $script:GcMark), $script:RingAnims.Count)
                    $script:BenchIndex++
                }
            }
        }
        $bench += @{ Wait = 300; Do = { $window.Close() } }
        if ($env:PULSRIG_BENCH -eq 'danach' -and -not $Real) { $script:Tour = @($script:Tour[0..($script:Tour.Count - 6)]) + $bench }
        else { $script:Tour = @(@{ Wait = 7000; Do = { } }) + $bench }
    }
    # Kurzer Rundgang nur über die Hauptseiten (Umgebungsvariable PULSRIG_SEITEN): zum schnellen Prüfen des Aussehens
    if ($env:PULSRIG_SEITEN -and -not $Real) {
        # PULSRIG_SEITEN=web: gestellte Beispiele für die Bilder der Webseite (Gaming-Check, Änderungen)
        if ($env:PULSRIG_SEITEN -eq 'web') {
            $script:CardState.GameCheck = @{ Text = '92'; Hints = 1; Tone = 'good'; Date = (Get-Date).ToString('dd.MM.yyyy') }
            Update-GameCheckPill
            $script:History.Snapshots = @(@{ D = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd') }, @{ D = (Get-Date).ToString('yyyy-MM-dd') })
            function script:Get-Changes($Old, $New) {
                @{ Title = 'Grafikkarte geändert: NVIDIA GeForce RTX 3080'; Sub = 'Version 32.0.15.6094 → 32.0.16.1742' }
                @{ Title = 'Windows wurde aktualisiert'; Sub = 'Stand 26100.6584 → 26100.6899' }
                @{ Title = 'Startet jetzt mit Windows: Discord'; Sub = 'Neu im Autostart' }
            }
            Update-ChangesTile
            # Hardware-Karten mit Bild: gestellte Werte einer letzten Prüfung
            $today = (Get-Date).ToString('dd.MM.yyyy')
            $script:StressResult = @{ Title = 'Bestanden'; Text = 'Takt bis 4,32 GHz'; Tone = 'good'; Time = "$today 16:40"; MaxGpuTemp = 61.0 }
            $script:CardState.Drives = @{ Text = 'in Ordnung'; Tone = 'good'; Date = $today; Detail = '3 Laufwerke · 1,16 TB frei'; Bars = @('C|62', 'D|35', 'E|48') }
            $script:CardState.Memory = @{ Text = '32 GB'; Tone = 'good'; Date = $today; Detail = '2 Riegel · DDR4 · 3.200 MHz'; Slots = 4; Used = 2; Size = '32 GB' }
            $script:CardState.Crashes = @{ Text = '1 Vorfall'; Tone = 'warn'; Date = $today; Detail = 'Zuletzt vor 19 Tagen'; Days = @(19) }
            $script:CardState.Report = @{ Text = '1 auffällig'; Tone = 'warn'; Date = $today; Detail = '5 gut · 1 auffällig · 1 offen' }
            $script:CardState.Bios = @{ Text = '7 Monate alt'; Tone = 'good'; Date = $today; Detail = 'F12 vom 19.03.2026' }
            Update-HardwareBadges
        }
        $script:Tour = @(
            @{ Wait = 4200; Do = { Save-Snapshot 's1-start'; Start-Scan } },
            @{ Wait = 1800; Do = { Save-Snapshot 's2-scan' } },
            @{ Until = { -not $script:Busy -and $script:Page -eq 'Results' }; Timeout = 30000; Do = { } },
            @{ Wait = 1600; Do = { Save-Snapshot 's3-ergebnisse'; Show-Page 'Boost' } },
            @{ Wait = 2000; Do = { Save-Snapshot 's4-boost'; Show-Page 'Tools' } },
            @{ Wait = 1700; Do = { Save-Snapshot 's5-werkzeuge'; if ($script:Bento) { Show-BentoToolList 'Aufräumen' } } },
            @{ Wait = 900; Do = { if ($script:Bento) { Save-Snapshot 's5a-werkzeuge-liste'; Close-BentoSub }; Open-ToolDialog 'CleanDisk' } },
            @{ Wait = 900; Do = { Start-DialogJob } },
            @{ Until = { -not $script:Busy }; Timeout = 120000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 's5b-speicherplatz'; Close-Dialog; Show-Page 'Hardware' } },
            @{ Wait = 1900; Do = { Save-Snapshot 's6-hardware'; if ($script:Bento) { Show-BentoDetail 0 } } },
            @{ Wait = 3500; Do = { if ($script:Bento) { Save-Snapshot 's6c-sensoren'; Close-BentoSub -Quiet; Show-BentoDetail 3 } } },
            @{ Until = { -not $script:Bento -or $script:BentoData.Memory }; Timeout = 20000; Do = { } },
            @{ Wait = 1600; Do = { if ($script:Bento) { Save-Snapshot 's6d-arbeitsspeicher'; Close-BentoSub -Quiet; Show-BentoDetail 2 } } },
            @{ Until = { -not $script:Bento -or $script:BentoData.Drives }; Timeout = 30000; Do = { } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6e-laufwerke'; Close-BentoSub -Quiet; Show-BentoDetail 4 } } },
            @{ Until = { -not $script:Bento -or $script:BentoData.Crashes }; Timeout = 30000; Do = { } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6f-abstuerze'; Close-BentoSub -Quiet; Show-BentoDetail 5 } } },
            @{ Until = { -not $script:Bento -or $script:BentoData.Displays }; Timeout = 20000; Do = { } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6g-bildschirm'; Close-BentoSub -Quiet; Show-BentoDetail 7 } } },
            @{ Until = { -not $script:Bento -or $script:BentoData.Bios }; Timeout = 20000; Do = { } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6h-bios'; Close-BentoSub -Quiet; Show-BentoDetail 6 } } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6i-bericht'; Close-BentoSub -Quiet; Show-BentoDetail 1 } } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6j-stabilitaet'; Close-BentoSub }; Show-Page $(if ($script:Bento) { 'Options' } else { 'Home' }) } },
            @{ Wait = 1400; Do = { if ($script:Bento) { Save-Snapshot 's6k-optionen'; Open-SettingsSheet 1 } } },
            @{ Wait = 1200; Do = { if ($script:Bento) { Save-Snapshot 's6l-einstellungen-design'; Select-SheetTab 0 } } },
            @{ Wait = 900; Do = { if ($script:Bento) { Save-Snapshot 's6m-einstellungen-allgemein'; Select-SheetTab 4 } } },
            @{ Wait = 900; Do = { if ($script:Bento) { Save-Snapshot 's6n-einstellungen-ignoriert'; Close-Sheet -Quick }; Show-Page 'Home' } },
            @{ Wait = 1200; Do = { Open-ProblemSheet } },
            @{ Until = { $null -ne $script:Sheet.Games }; Timeout = 30000; Do = { } },
            @{ Wait = 900; Do = { Save-Snapshot 's6b-problem'; Close-Sheet -Quick } },
            @{ Wait = $(if ($env:PULSRIG_SEITEN -eq 'web') { 45000 } else { 1500 }); Do = { Save-Snapshot 's7-start-danach'; $window.Close() } }   # für die Webseite: Kurven füllen lassen
        )
    }
    $script:TourIndex = 0
    $script:TourSince = Get-Date
    $tourTimer = New-Object Windows.Threading.DispatcherTimer
    $tourTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $tourTimer.Add_Tick({
            try {
                if ($script:TourIndex -ge $script:Tour.Count) { $this.Stop(); return }
                $step = $script:Tour[$script:TourIndex]
                $elapsed = ((Get-Date) - $script:TourSince).TotalMilliseconds
                $due = if ($step.Until) { (& $step.Until) -or $elapsed -gt $step.Timeout } else { $elapsed -ge $step.Wait }
                if (-not $due) { return }
                if ($step.Until -and $elapsed -gt $step.Timeout) { Write-Host "Zeitüberschreitung bei Schritt $($script:TourIndex)" }
                $script:TourIndex++
                $script:TourSince = Get-Date
                & $step.Do
            }
            catch { Write-AppError $_ }
        })
    $tourTimer.Start()
}
