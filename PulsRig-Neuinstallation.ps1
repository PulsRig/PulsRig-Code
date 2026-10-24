# PulsRig - Neuinstallations-Begleiter: vor einer Neuinstallation von Windows Treiber und Programmliste sichern,
# danach geführt wieder einspielen (Treiber, Spielkomponenten, Programme zum Abhaken).
# Wird von PulsRig.ps1 eingebunden und nutzt dessen großes Fenster mit Listen und den Arbeitsbereich.
#
# Die Sicherung ist ein Ordner "Neuinstallation_<Datum>" im Zielordner: darin ein Offline-Treiberpaket
# (New-OfflinePackage) und Programme.json aus "winget export". Programme installiert PulsRig nur, wenn sie abgehakt sind.

$reinstallCode = Get-AppText 'PulsRig-Arbeit-Neuinstallation.ps1'

# Sicherungen im Zielordner und auf allen Laufwerken (oberste Ebene und eine darunter, z.B. USB-Stick\PulsRig)
function Find-ReinstallFolders {
    $roots = @(Get-TargetDir)
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $drive.IsReady -or $drive.DriveType -notin 'Fixed', 'Removable') { continue }
            $roots += $drive.RootDirectory.FullName
            $roots += @(Get-ChildItem -LiteralPath $drive.RootDirectory.FullName -Directory -ErrorAction SilentlyContinue |
                    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $_.Name -notin 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', '$Recycle.Bin' } |
                    ForEach-Object { $_.FullName })
        }
        catch { }
    }
    @($roots | Select-Object -Unique | ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory -Filter 'Neuinstallation_*' -ErrorAction SilentlyContinue } |
            Sort-Object Name -Descending | Select-Object -ExpandProperty FullName -Unique)
}

# Paketkennungen aus Programme.json; aus "Mozilla.Firefox" wird zum Anzeigen "Firefox"
function Get-ReinstallPrograms([string]$Folder) {
    $file = Join-Path $Folder 'Programme.json'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    try { $ids = @((Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages } | ForEach-Object { "$($_.PackageIdentifier)" } | Where-Object { $_ }) }
    catch { return @() }
    @($ids | Sort-Object -Unique | ForEach-Object {
            $name = if ($_ -match '^[^.]+\.(.+)$') { $Matches[1] -replace '\.', ' ' } else { $_ }
            @{ Id = $_; Name = $name }
        } | Sort-Object { $_.Name })
}

function Open-ReinstallSheet([int]$Tab = 0) {
    $found = @(Find-ReinstallFolders)
    $opened = Open-Sheet @{
        Title     = 'Neuinstallation'
        Sub       = 'Vorher sichern, danach geführt einspielen'
        Glyph     = 0xE777
        Found     = $found
        Tabs      = 'Vorher sichern', 'Danach einspielen'
        Show      = { param($tab) if ($tab -eq 0) { Show-ReinstallBefore } else { Show-ReinstallAfter } }
        OnPrimary = {
            if ($script:Sheet.Tab -eq 0) { Close-Sheet -Quick; Open-ReinstallDialog 'Save'; return }
            $ids = @($script:Sheet.Programs | Where-Object { $_.Checked } | ForEach-Object { $_.Data.Id })
            if ($ids.Count -gt 0) { Close-Sheet -Quick; Open-ReinstallDialog 'Programs' $ids }
        }
        OnLink    = {
            # alle Programme an- oder abhaken
            $all = @($script:Sheet.Programs | Where-Object { -not $_.Checked }).Count -gt 0
            foreach ($row in $script:Sheet.Programs) { $row.Checked = $all }
            $script:SheetWay = 0
            Show-ReinstallAfter
        }
        OnAction  = {
            param($item)
            switch ($item.Data.Do) {
                'open' { Start-Process explorer.exe "`"$($item.Data.Folder)`"" }
                'pick' {
                    Add-Type -AssemblyName System.Windows.Forms
                    $picker = New-Object Windows.Forms.FolderBrowserDialog
                    $picker.Description = T 'Ordner der Sicherung wählen (Neuinstallation_…)'
                    if ($script:Sheet.Folder) { $picker.SelectedPath = $script:Sheet.Folder }
                    if ($picker.ShowDialog() -eq 'OK' -and $picker.SelectedPath) { Set-ReinstallFolder $picker.SelectedPath; Show-ReinstallAfter }
                }
                'drivers' { $folder = $script:Sheet.Folder; Close-Sheet -Quick; Open-ReinstallDialog 'Drivers' -Folder $folder }
                'runtimes' { Close-Sheet -Quick; Open-RuntimeSheet }
            }
        }
        OnCheck   = { param($item) Update-ReinstallState }
    }
    if (-not $opened) { return }
    if ($found.Count) { Set-ReinstallFolder $found[0] }
    if ($Tab) { Select-SheetTab $Tab }
}

function Set-ReinstallFolder([string]$Folder) {
    $script:Sheet.Folder = $Folder
    $script:Sheet.Programs = @(foreach ($program in (Get-ReinstallPrograms $Folder)) {
            New-SheetRow -Title $program.Name -Sub $program.Id -Glyph 0xE71D -Checkable -Checked $false -Data @{ Id = $program.Id }
        })
}

function Show-ReinstallBefore {
    Set-SheetButtons 'Sicherung erstellen'
    $winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    $rows = @(
        New-SheetRow -Kind 'head' -Title 'KOMMT IN DIE SICHERUNG'
        New-SheetRow -Title 'Treiber' -Sub 'Offline-Paket aller Treiber von Drittherstellern, auch ohne Internet einspielbar' -Glyph 0xE7B8 -State 'dabei' -Tone 'good'
        New-SheetRow -Title 'Programmliste' -Sub 'Programme, die winget kennt – danach zum Abhaken und Installieren' -Glyph 0xE71D `
            -State $(if ($winget) { 'dabei' } else { 'winget fehlt' }) -Tone $(if ($winget) { 'good' } else { 'warn' })
        New-SheetRow -Kind 'head' -Title 'SELBST SICHERN'
        New-SheetRow -Title 'Eigene Dateien und Spielstände' -Sub 'Dokumente, Bilder, Browser-Daten und Spielstände ohne Cloud – die sichert PulsRig nicht' -Glyph 0xE7BA -State 'nicht dabei' -Tone 'warn'
    )
    $last = @($script:Sheet.Found)
    if ($last.Count) {
        $rows += New-SheetRow -Kind 'head' -Title 'LETZTE SICHERUNG'
        $rows += New-SheetRow -Title (Split-Path -Leaf $last[0]) -Sub $last[0] -Glyph 0xE8B7 -Action 'Ordner öffnen' -Data @{ Do = 'open'; Folder = $last[0] }
    }
    Show-SheetList $rows
    Set-SheetStateText 'Den fertigen Ordner vor der Neuinstallation auf einen USB-Stick kopieren.'
}

function Show-ReinstallAfter {
    Set-SheetButtons 'Ausgewählte installieren' 'Schließen' $(if (@($script:Sheet.Programs).Count) { 'Alle auswählen' })
    $folder = $script:Sheet.Folder
    if (-not $folder) {
        Show-SheetList @(New-SheetRow -Title 'Keine Sicherung gefunden' -Sub 'Weder im Zielordner noch auf den Laufwerken liegt ein Ordner „Neuinstallation_…“. USB-Stick einstecken oder den Ordner selbst wählen.' `
                -Glyph 0xE783 -Tone 'warn' -Action 'Ordner wählen' -Data @{ Do = 'pick' })
        Update-ReinstallState
        return
    }
    $dry = -not $script:IsAdmin
    $programs = @($script:Sheet.Programs)
    $rows = @(
        New-SheetRow -Title (Split-Path -Leaf $folder) -Sub $folder -Glyph 0xE8B7 -Action 'Anderer Ordner' -Data @{ Do = 'pick' }
        New-SheetRow -Kind 'head' -Title '1 · TREIBER'
        New-SheetRow -Title 'Treiber einspielen' -Sub 'Alle Treiber aus dem Offline-Paket, danach neu starten' -Glyph 0xE7B8 -Tone 'accent' `
            -State $(if ($dry) { 'Probelauf' } else { '' }) -Action 'Jetzt einspielen' -Data @{ Do = 'drivers' }
        New-SheetRow -Kind 'head' -Title '2 · SPIELKOMPONENTEN'
        New-SheetRow -Title 'Spielkomponenten' -Sub 'Visual C++, DirectX und XNA prüfen und nachinstallieren' -Glyph 0xE7FC -Tone 'accent' -Action 'Prüfen' -Data @{ Do = 'runtimes' }
        New-SheetRow -Kind 'head' -Title $(if ($programs.Count) { "3 · PROGRAMME ($($programs.Count))" } else { '3 · PROGRAMME' })
    )
    if ($programs.Count) { $rows += $programs }
    else { $rows += New-SheetRow -Title 'Keine Programmliste' -Sub 'In dieser Sicherung fehlt Programme.json' -Glyph 0xE783 }
    if ($programs.Count) { $ui.BtnSheetLink.Content = T $(if (@($programs | Where-Object { -not $_.Checked }).Count) { 'Alle auswählen' } else { 'Keine auswählen' }) }
    Show-SheetList $rows
    Update-ReinstallState
}

function Update-ReinstallState {
    if ($script:Sheet.Tab -ne 1) { return }
    $selected = @($script:Sheet.Programs | Where-Object { $_.Checked }).Count
    $ui.BtnSheetPrimary.IsEnabled = $selected -gt 0
    if (@($script:Sheet.Programs).Count) { $ui.BtnSheetLink.Content = T $(if (@($script:Sheet.Programs | Where-Object { -not $_.Checked }).Count) { 'Alle auswählen' } else { 'Keine auswählen' }) }
    Set-SheetStateText $(if ($selected -eq 1) { '1 Programm ausgewählt' } elseif ($selected) { "$selected Programme ausgewählt" } else { 'Der Reihe nach: Treiber, Spielkomponenten, dann die Programme abhaken.' })
}

function Open-ReinstallDialog([string]$Mode, [string[]]$Ids, [string]$Folder) {
    if ($script:Busy) { return }
    $target = Get-TargetDir
    # Treiber einspielen braucht Adminrechte; winget fragt bei Bedarf selbst danach
    $dryRun = $Mode -eq 'Drivers' -and -not $script:IsAdmin
    $script:Dialog = @{ Kind = 'custom'; Name = 'Reinstall'; DryRun = $dryRun; Code = $reinstallCode
        Argument = @{ Mode = $Mode; TargetDir = $target; Folder = $Folder; Ids = @($Ids); DryRun = $dryRun } }
    switch ($Mode) {
        'Save' {
            $cards = @(
                New-IntroCard 0xE7B8 '1 · Treiber' 'als Offline-Paket' 'Accent'
                New-IntroCard 0xE71D '2 · Programme' 'Liste aus winget' 'Ring2'
                New-IntroCard 0xE8B7 (Split-Path -Leaf $target) 'Zielordner' 'Ring1'
            )
            Open-Dialog 'Neuinstallation vorbereiten' 'Treiber und Programmliste sichern' 0xE777 ('PulsRig legt einen Ordner „Neuinstallation_…“ mit allen Treibern und der Programmliste an.' + "`n`nZiel: $target`nAm System ändert sich nichts.") 'Sichern' $cards
        }
        'Drivers' {
            $intro = "Die Treiber aus der Sicherung werden eingespielt.`n`nOrdner: $Folder"
            if ($dryRun) { $intro += "`nOhne Adminrechte läuft das als Probelauf: Es wird nichts eingespielt." }
            $cards = @(
                New-IntroCard 0xE721 '1 · Prüfen' 'Paket im Ordner' 'Accent'
                New-IntroCard 0xE897 '2 · Nachfragen' 'vor dem Einspielen' 'Ring2'
                New-IntroCard 0xE777 '3 · Neustart' 'danach empfohlen' 'Ring1'
            )
            Open-Dialog 'Treiber einspielen' (Split-Path -Leaf $Folder) 0xE7B8 $intro $(if ($dryRun) { 'Probelauf starten' } else { 'Starten' }) $cards
        }
        'Programs' {
            $names = @($Ids | ForEach-Object { if ($_ -match '^[^.]+\.(.+)$') { $Matches[1] -replace '\.', ' ' } else { $_ } })
            $list = (@($names | Select-Object -First 3 | ForEach-Object { "• $_" }) + $(if ($names.Count -gt 3) { "• und $($names.Count - 3) weitere" })) -join "`n"
            $intro = $(if ($Ids.Count -eq 1) { 'Ein Programm wird mit winget installiert.' } else { "$($Ids.Count) Programme werden nacheinander mit winget installiert." }) + "`n`n$list"
            $intro += "`nFragt ein Installer nach Adminrechten, dort selbst bestätigen."
            $cards = @(
                New-IntroCard 0xE896 '1 · Laden' 'aus der winget-Quelle' 'Accent'
                New-IntroCard 0xE8FB '2 · Installieren' 'eins nach dem anderen' 'Ring2'
                New-IntroCard 0xE73E '3 · Fertig' 'Bericht je Programm' 'Good'
            )
            Open-Dialog 'Programme installieren' "$($Ids.Count) ausgewählt" 0xE71D $intro 'Installieren' $cards
        }
    }
}
