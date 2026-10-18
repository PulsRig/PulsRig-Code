# PulsRig - "Was hat sich geändert?" Wird von PulsRig.ps1 nach PulsRig-Probezeit.ps1 eingebunden.
#
# "Gestern lief noch alles": Bei der Prüfung nach dem Start (PulsRig-Probezeit.ps1) merkt sich PulsRig einmal am Tag
# ein kleines Bild des PCs - Windows-Stand, Energieplan, installierte Programme, Autostart, wichtige Treiber -
# in der Ergebnisdatei unter History.Snapshots. Das Fenster vergleicht heute mit gestern, vor 7 oder vor 30 Tagen
# und sagt in einfachen Sätzen, was neu, weg oder anders ist; dazu die Abstürze seit diesem Tag.
# Aufbewahrt werden die letzten 8 Tage und davor eines pro Woche bis 35 Tage zurück. Das Diagnose-Paket lässt die
# Bilder weg (Programmlisten gehen niemanden etwas an).

$script:LastCrashes = $null

function Add-Snapshot($Result) {
    if (-not $Result) { return }
    $script:LastCrashes = $Result.Crashes
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $snap = @{
        D         = $today
        Windows   = "$($Result.Windows)"
        Plan      = "$($Result.Plan)"
        Programs  = @(@($Result.Programs) | Where-Object { $_ } | ForEach-Object { "$($_.Name)|$($_.Version)|$($_.Date)" } | Sort-Object -Unique)
        Autostart = @(@($Result.Autostart) | Where-Object { $_ } | ForEach-Object { "$($_.Name)|$(if ($_.Enabled) { 'an' } else { 'aus' })" } | Sort-Object -Unique)
        Drivers   = @(@($Result.Drivers) | Where-Object { $_ } | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Version)|$($_.Class)" } | Sort-Object -Unique)
    }
    $list = @($script:History.Snapshots | Where-Object { $_ -and $_.D -ne $today }) + $snap
    # die letzten 8 Tage ganz, davor eines je Woche, nichts älter als 35 Tage
    $keep = @()
    $weeks = @{}
    foreach ($entry in @($list | Sort-Object { $_.D } -Descending)) {
        $age = ((Get-Date) - [datetime]::ParseExact($entry.D, 'yyyy-MM-dd', $null)).TotalDays
        if ($age -gt 35) { continue }
        if ($age -lt 8) { $keep += $entry; continue }
        $week = [Math]::Floor($age / 7)
        if (-not $weeks[$week]) { $weeks[$week] = $true; $keep += $entry }
    }
    $script:History.Snapshots = @($keep | Sort-Object { $_.D })
    Save-HardwareResults
    Update-ChangesTile
}

# das Bild, mit dem verglichen wird: das jüngste, das mindestens $Days Tage alt ist, sonst das älteste
function Get-SnapshotBefore([int]$Days) {
    $snaps = @($script:History.Snapshots | Where-Object { $_ } | Sort-Object { $_.D })
    if ($snaps.Count -lt 2) { return $null }
    $limit = (Get-Date).Date.AddDays(-$Days).ToString('yyyy-MM-dd')
    $older = @($snaps | Where-Object { $_.D -le $limit })
    if ($older.Count) { $older[-1] } else { $snaps[0] }
}

function Format-SnapDay([string]$Day) { try { [datetime]::ParseExact($Day, 'yyyy-MM-dd', $null).ToString('dd.MM.') } catch { $Day } }

# "Discord, Steam, OBS Studio und 2 weitere"
function Join-Names([string[]]$Names, [int]$Max = 4) {
    $Names = @($Names | Where-Object { $_ })
    if ($Names.Count -le $Max) { return ($Names -join ', ') }
    (($Names | Select-Object -First $Max) -join ', ') + " und $($Names.Count - $Max) weitere"
}

# Unterschiede zwischen zwei Bildern als Zeilen: Title, Sub, Glyph, Tone
function Get-Changes($Old, $New) {
    $changes = @()
    if (-not $Old -or -not $New) { return $changes }
    $since = Format-SnapDay $Old.D

    if ($Old.Windows -and $New.Windows -and $Old.Windows -ne $New.Windows) {
        $changes += @{ Title = 'Windows wurde aktualisiert'; Sub = "Stand $($Old.Windows) → $($New.Windows)"; Glyph = 0xE895; Tone = 'accent'; Kind = 'windows' }
    }

    # Treiber: gleiche Gerätekennung, andere Version
    $oldDrivers = @{}; foreach ($line in @($Old.Drivers)) { $p = "$line" -split '\|'; if ($p.Count -ge 3) { $oldDrivers[$p[0]] = $p } }
    $driverChanges = @()
    foreach ($line in @($New.Drivers)) {
        $p = "$line" -split '\|'
        if ($p.Count -lt 4) { continue }
        $before = $oldDrivers[$p[0]]
        if ($before -and $before[2] -ne $p[2]) { $driverChanges += @{ Name = $p[1]; Old = $before[2]; New = $p[2]; Class = $p[3]; Id = $p[0] } }
    }
    foreach ($driver in @($driverChanges | Sort-Object { if ($_.Class -eq 'DISPLAY') { 0 } else { 1 } } | Select-Object -First 3)) {
        $probe = @($script:History.Probation | Where-Object { $_ -and $_.Id -eq $driver.Id -and $_.New -eq $driver.New })[0]
        $how = if ($probe) { "$(if ($probe.Source -eq 'PulsRig') { 'von PulsRig' } else { 'von Windows Update oder von Hand' }) am $(([datetime][long]$probe.Since).ToString('dd.MM.'))" } else { '' }
        $changes += @{ Title = "$(Get-ProbeClassName $driver.Class) geändert: $($driver.Name)"; Sub = (@("Version $($driver.Old) → $($driver.New)", $how) | Where-Object { $_ }) -join ' · '
            Glyph = 0xE7F4; Tone = $(if ($driver.Class -eq 'DISPLAY') { 'warn' } else { 'accent' }); Kind = 'driver' }
    }
    if ($driverChanges.Count -gt 3) { $changes += @{ Title = "$($driverChanges.Count - 3) weitere Treiber geändert"; Sub = Join-Names @($driverChanges | Select-Object -Skip 3 | ForEach-Object { $_.Name }); Glyph = 0xE7F4; Tone = 'accent'; Kind = 'driver' } }

    # Programme nach Namen
    $oldPrograms = @{}; foreach ($line in @($Old.Programs)) { $p = "$line" -split '\|'; $oldPrograms[$p[0]] = $p }
    $newPrograms = @{}; foreach ($line in @($New.Programs)) { $p = "$line" -split '\|'; $newPrograms[$p[0]] = $p }
    $added = @($newPrograms.Keys | Where-Object { -not $oldPrograms.ContainsKey($_) } | Sort-Object)
    $removed = @($oldPrograms.Keys | Where-Object { -not $newPrograms.ContainsKey($_) } | Sort-Object)
    $updated = @($newPrograms.Keys | Where-Object { $oldPrograms.ContainsKey($_) -and $oldPrograms[$_][1] -ne $newPrograms[$_][1] } | Sort-Object)
    if ($added.Count) {
        $changes += @{ Title = $(if ($added.Count -eq 1) { "Neues Programm: $($added[0])" } else { "$($added.Count) neue Programme" }); Sub = $(if ($added.Count -eq 1) { $(if ($newPrograms[$added[0]][1]) { "Version $($newPrograms[$added[0]][1])" } else { 'installiert' }) } else { Join-Names $added })
            Glyph = 0xECAA; Tone = 'accent'; Kind = 'programs' }
    }
    if ($removed.Count) {
        $changes += @{ Title = $(if ($removed.Count -eq 1) { "Entfernt: $($removed[0])" } else { "$($removed.Count) Programme entfernt" }); Sub = $(if ($removed.Count -eq 1) { 'nicht mehr installiert' } else { Join-Names $removed })
            Glyph = 0xE74D; Tone = ''; Kind = 'programs' }
    }
    if ($updated.Count) {
        $changes += @{ Title = $(if ($updated.Count -eq 1) { "Aktualisiert: $($updated[0])" } else { "$($updated.Count) Programme aktualisiert" })
            Sub = $(if ($updated.Count -eq 1) { "Version $($oldPrograms[$updated[0]][1]) → $($newPrograms[$updated[0]][1])" } else { Join-Names $updated }); Glyph = 0xE895; Tone = ''; Kind = 'programs' }
    }

    # Autostart
    $oldStart = @{}; foreach ($line in @($Old.Autostart)) { $p = "$line" -split '\|'; $oldStart[$p[0]] = $p[1] }
    $newStart = @{}; foreach ($line in @($New.Autostart)) { $p = "$line" -split '\|'; $newStart[$p[0]] = $p[1] }
    $startAdded = @($newStart.Keys | Where-Object { -not $oldStart.ContainsKey($_) -and $newStart[$_] -eq 'an' } | Sort-Object)
    $startOn = @($newStart.Keys | Where-Object { $oldStart[$_] -eq 'aus' -and $newStart[$_] -eq 'an' } | Sort-Object)
    $startGone = @($oldStart.Keys | Where-Object { $oldStart[$_] -eq 'an' -and (-not $newStart.ContainsKey($_) -or $newStart[$_] -eq 'aus') } | Sort-Object)
    $startNew = @($startAdded + $startOn)
    if ($startNew.Count) {
        $changes += @{ Title = $(if ($startNew.Count -eq 1) { "Startet jetzt mit Windows: $($startNew[0])" } else { "$($startNew.Count) Programme starten jetzt mit Windows" }); Sub = $(if ($startNew.Count -eq 1) { 'Neu im Autostart; lässt sich unter Werkzeuge → Autostart ausschalten' } else { Join-Names $startNew })
            Glyph = 0xE7E8; Tone = 'warn'; Kind = 'autostart' }
    }
    if ($startGone.Count) {
        $changes += @{ Title = $(if ($startGone.Count -eq 1) { "Startet nicht mehr mit Windows: $($startGone[0])" } else { "$($startGone.Count) Programme starten nicht mehr mit Windows" }); Sub = $(if ($startGone.Count -eq 1) { 'aus dem Autostart entfernt oder ausgeschaltet' } else { Join-Names $startGone })
            Glyph = 0xE7E8; Tone = ''; Kind = 'autostart' }
    }

    if ($Old.Plan -and $New.Plan -and $Old.Plan -ne $New.Plan) {
        $changes += @{ Title = 'Anderer Energieplan'; Sub = "$($Old.Plan) → $($New.Plan)"; Glyph = 0xE945; Tone = 'accent'; Kind = 'plan' }
    }

    # Abstürze seit dem Vergleichstag
    if ($script:LastCrashes) {
        $from = [datetime]::ParseExact($Old.D, 'yyyy-MM-dd', $null).Ticks
        $c = $script:LastCrashes
        $blue = @(@($c.Blue) | Where-Object { $_ -and [long]$_.When.Ticks -ge $from }).Count
        $other = @(@($c.Off) + @($c.Tdr) + @($c.Apps) | Where-Object { $_ -and [long]$_.When.Ticks -ge $from }).Count
        if ($blue + $other -gt 0) {
            $parts = @()
            if ($blue) { $parts += $(if ($blue -eq 1) { '1 Bluescreen' } else { "$blue Bluescreens" }) }
            if ($other) { $parts += $(if ($other -eq 1) { '1 Aussetzer oder Ausschalten' } else { "$other Aussetzer oder Ausschalten" }) }
            $changes = @(@{ Title = "Abstürze seit $since"; Sub = ($parts -join ' · ') + ' · Einzelheiten unter Hardware → Abstürze'; Glyph = 0xE7BA; Tone = $(if ($blue) { 'bad' } else { 'warn' }); Kind = 'crashes'; Action = 'crashes' }) + $changes
        }
    }
    $changes
}

function Open-ChangesSheet {
    $opened = Open-Sheet @{
        Title    = 'Was hat sich geändert?'
        Sub      = 'Unterschiede zu früheren Tagen, die PulsRig mitgeschrieben hat'
        Glyph    = 0xE81C
        Tabs     = 'Seit gestern', '7 Tage', '30 Tage'
        Link     = 'Treiberverlauf'
        Show     = { param($tab) Show-ChangesTab }
        OnAction = { param($item) if ($item.Data -and $item.Data.Do -eq 'crashes') { Open-CrashSheet } elseif ($item.Data -and $item.Data.Do -eq 'autostart') { Close-Sheet; Invoke-Later 300 { Open-AutostartSheet } } }
        OnLink   = { Open-HistorySheet }
    }
    if (-not $opened) { return }
}

function Show-ChangesTab {
    $days = @(1, 7, 30)[[int]$script:Sheet.Tab]
    $snaps = @($script:History.Snapshots | Where-Object { $_ } | Sort-Object { $_.D })
    $ui.SheetChips.Children.Clear()
    $rows = @()
    if ($snaps.Count -lt 2) {
        $first = if ($snaps.Count) { Format-SnapDay $snaps[0].D } else { 'heute' }
        $rows += New-SheetRow -Title 'PulsRig schreibt ab jetzt mit' -Glyph 0xE81C -Tone 'accent' -State 'ab heute' `
            -Sub "Seit $first merkt sich PulsRig einmal am Tag Windows-Stand, Programme, Autostart, wichtige Treiber und Energieplan. Ab morgen steht hier, was sich seitdem geändert hat."
        Show-SheetList $rows
        Set-SheetStateText 'Mitgeschrieben wird bei jedem Start von PulsRig'
        return
    }
    $old = Get-SnapshotBefore $days
    $new = $snaps[-1]
    $changes = @(Get-Changes $old $new)
    foreach ($change in $changes) {
        $action = switch ($change.Kind) { 'crashes' { 'Ansehen' } 'autostart' { $(if ($change.Tone -eq 'warn') { 'Autostart' }) } default { '' } }
        $rows += New-SheetRow -Title $change.Title -Sub $change.Sub -Glyph $change.Glyph -Tone $change.Tone -Action $action -Data @{ Do = $change.Kind }
    }
    if ($rows.Count -eq 0) {
        $rows += New-SheetRow -Title "Nichts geändert seit $(Format-SnapDay $old.D)" -Glyph 0xE73E -Tone 'good' -State 'unverändert' `
            -Sub 'Windows, Programme, Autostart, wichtige Treiber und Energieplan sind wie damals, und es gab keine Abstürze.'
    }
    # nicht mehr als in das Fenster passt: die wichtigsten zuerst, der Rest zusammengefasst
    if ($rows.Count -gt 7) {
        $rest = $rows.Count - 6
        $rows = @($rows | Select-Object -First 6) + (New-SheetRow -Title "$rest weitere Änderungen" -Glyph 0xE712 -Sub 'Der Reiter mit dem kürzeren Abstand zeigt sie einzeln.')
    }
    $count = $changes.Count
    Add-ResultChip $(if ($count -eq 0) { 'unverändert' } elseif ($count -eq 1) { '1 Änderung' } else { "$count Änderungen" }) $(if ($count) { 'Accent' } else { 'Good' }) $ui.SheetChips
    Show-SheetList $rows
    $exact = $old.D -le (Get-Date).Date.AddDays(-$days).ToString('yyyy-MM-dd')
    Set-SheetStateText $(if ($exact) { "Verglichen mit dem $(Format-SnapDay $old.D) · mitgeschrieben seit $(Format-SnapDay $snaps[0].D)" } else { "Mitgeschrieben erst seit $(Format-SnapDay $snaps[0].D): verglichen mit diesem Tag" })
}

# Unterzeile der Kachel auf der Startseite
function Update-ChangesTile {
    if (-not $ui.HomeChangesText) { return }
    $snaps = @($script:History.Snapshots | Where-Object { $_ } | Sort-Object { $_.D })
    $text = if ($snaps.Count -lt 2) { 'Ab heute mitgeschrieben' }
    else {
        $count = @(Get-Changes (Get-SnapshotBefore 7) $snaps[-1]).Count
        if ($count -eq 0) { 'Seit einer Woche unverändert' } elseif ($count -eq 1) { '1 Änderung in 7 Tagen' } else { "$count Änderungen in 7 Tagen" }
    }
    $ui.HomeChangesText.Text = T $text
    if (Get-Command Update-HomeChangesList -ErrorAction SilentlyContinue) { Update-HomeChangesList }
}

Update-ChangesTile
