# PulsRig - Sprache: Deutsch ist die Sprache des Programms, Englisch eine Übersetzung darüber.
# Wird von PulsRig.ps1 eingebunden, nach den Einstellungen und vor der Oberfläche.
#
# Der Quelltext bleibt deutsch. Übersetzt wird an den Stellen, an denen Text ins Fenster kommt: in den Vorlagen der
# Oberfläche (Convert-XamlLanguage) und in den Bausteinen, die Zeilen, Schilder und Meldungen bauen (T). Bei Deutsch
# gibt T den Text unverändert zurück - für die deutsche Fassung ändert sich nichts.
#
# Die Wörter stehen in PulsRig-Englisch.ps1 und werden nur geladen, wenn Englisch gewählt ist:
#   Words     deutscher Text -> englischer Text (genau dieser Text, Groß- und Kleinschreibung zählt)
#   Patterns  Muster für Texte mit wechselnden Teilen: @{ R = '^(\d+) Laufwerke$'; F = '$1 drives' }
# Zusammengesetzte Texte ("3 Laufwerke · 1,15 TB frei") zerlegt T an " · " und übersetzt die Teile einzeln.
# Was sich nicht übersetzen ließ, sammelt $script:Untranslated; der Probelauf schreibt es in "Unuebersetzt.txt".

$script:Language = 'de'
if ("$env:PULSRIG_SPRACHE" -in 'de', 'en') { $script:Language = "$env:PULSRIG_SPRACHE" }
elseif ("$($script:Settings.Language)" -eq 'en') { $script:Language = 'en' }

$script:Words = New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
$script:WordPatterns = New-Object Collections.ArrayList
$script:Untranslated = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)

if ($script:Language -eq 'en') {
    $table = & (Get-AppCode 'PulsRig-Englisch.ps1')
    $pairs = @($table.Words)
    for ($i = 0; $i + 1 -lt $pairs.Count; $i += 2) { $script:Words["$($pairs[$i])"] = "$($pairs[$i + 1])" }
    foreach ($pattern in $table.Patterns) { [void]$script:WordPatterns.Add(@{ R = (New-Object regex $pattern.R); F = "$($pattern.F)" }) }
}

# Übersetzt einen Text der Oberfläche. Unbekanntes bleibt, wie es ist.
function T([string]$Text) {
    if ($script:Language -eq 'de' -or -not $Text) { return $Text }
    $found = ''
    if ($script:Words.TryGetValue($Text, [ref]$found)) { return $found }
    # ohne Buchstaben gibt es nichts zu übersetzen ("12,5 GB", "66 °C")
    if ($Text -notmatch '[A-Za-zÄÖÜäöüß]{2}') { return $Text }
    foreach ($separator in " · ", "`n") {
        if ($Text.Contains($separator)) {
            return (@($Text -split [regex]::Escape($separator) | ForEach-Object { T $_ }) -join $separator)
        }
    }
    foreach ($pattern in $script:WordPatterns) {
        $match = $pattern.R.Match($Text)
        if ($match.Success) {
            # die wechselnden Teile dürfen selbst wieder übersetzbare Wörter sein ("{T:1}")
            $result = $pattern.F
            for ($i = $match.Groups.Count - 1; $i -ge 1; $i--) {
                $value = $match.Groups[$i].Value
                $result = $result.Replace("{T:$i}", (T $value)).Replace("`$$i", $value)
            }
            return $result
        }
    }
    [void]$script:Untranslated.Add($Text)
    $Text
}

# Wie T, lässt aber Einrückung und Leerzeichen am Ende stehen (Zeilen im Protokoll der Werkzeuge)
function TL([string]$Text) {
    if ($script:Language -eq 'de' -or -not $Text) { return $Text }
    $core = $Text.Trim()
    if (-not $core) { return $Text }
    $start = $Text.IndexOf($core)
    $Text.Substring(0, $start) + (T $core) + $Text.Substring($start + $core.Length)
}

# Übersetzt die festen Texte einer Vorlage der Oberfläche (Text, Content, ToolTip), bevor Oberfläche daraus wird
function Convert-XamlLanguage([string]$Xaml) {
    if ($script:Language -eq 'de') { return $Xaml }
    [regex]::Replace($Xaml, '(?<a>\b(?:Text|Content|ToolTip))="(?<v>[^"{]*[A-Za-zÄÖÜäöü]{2}[^"]*)"', {
            param($match)
            $value = $match.Groups['v'].Value
            if ($value -match '&#x') { return $match.Value }   # Symbole aus der Symbolschrift
            $plain = [Net.WebUtility]::HtmlDecode($value)
            $new = T $plain
            if ($new -ceq $plain) { return $match.Value }
            '{0}="{1}"' -f $match.Groups['a'].Value, [Security.SecurityElement]::Escape($new)
        })
}

# Stellt die Sprache um: speichert sie und startet das Fenster neu (wie beim Wechsel des Skins) - die Oberfläche
# entsteht beim Start aus den Vorlagen, eine laufende lässt sich nicht umschreiben
function Set-Language([string]$Id) {
    if ($Id -notin 'de', 'en' -or $Id -eq $script:Language) { return }
    $script:Settings.Language = $Id
    Save-Settings
    if ($Snapshot) { return }
    $script:RestartAfterClose = $true
    $window.Close()
}

# Probelauf: was noch deutsch geblieben ist, als Arbeitsliste
function Save-Untranslated([string]$Folder) {
    if ($script:Language -eq 'de' -or $script:Untranslated.Count -eq 0) { return }
    try { [IO.File]::WriteAllLines((Join-Path $Folder 'Unuebersetzt.txt'), [string[]]@($script:Untranslated | Sort-Object), (New-Object Text.UTF8Encoding $true)) } catch { }
}
