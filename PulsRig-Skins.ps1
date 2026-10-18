# PulsRig - Skins: komplette Aussehen des Programms. Wird von PulsRig.ps1 eingebunden, bevor das Fenster entsteht.
#
# Ein Farbdesign (Mitternacht, Tiefsee ...) tauscht nur Farben und wirkt sofort. Ein Skin geht weiter: Er legt Formen
# (Ecken), Schrift, die Optik der Karten, den Hintergrund und das Tempo der Bewegungen fest und bringt ein eigenes
# Farbdesign mit. Dazu schreibt er jeden XAML-Text des Programms um, bevor daraus Oberfläche wird - deshalb gilt ein
# neuer Skin erst nach einem Neustart des Fensters, den das Programm selbst erledigt.
#
# Einen Skin hinzufügen: unten einen Eintrag in $script:Skins anlegen. Alle Angaben außer Text sind freiwillig.
#   Text      Name im Menü
#   Ring      Name seiner Ring-Animation um den SCAN-Knopf (gebaut in PulsRig-Ringe.ps1); sie wird mit dem Skin
#             gewählt und steht nur in diesem Skin zur Auswahl
#   Theme     Name seines Farbdesigns; ThemeDef legt es an (Hue, Sat, Light, A = drei Akzentfarben,
#             R = drei Farben für den Ring um SCAN, OnAccent = Schrift auf Akzentflächen)
#   Radius    Rechenvorschrift für Ecken: bekommt den Radius aus der Vorlage und gibt den neuen zurück -
#             eine Zahl oder vier Werte "links oben,rechts oben,rechts unten,links unten"
#   Font      Schriftart des Fensters; FontMore hängt weitere Angaben an (z. B. eine schmale Laufweite)
#   Weights   Schriftstärken umsetzen, z. B. @{ SemiBold = 'Normal' }
#   Keys      Grundfarben der Schrift ersetzen (Text, TextDim, TextFaint) - angegeben in den Farben von Mitternacht,
#             das Farbdesign dreht sie wie alle anderen mit
#   Resources benannte Bausteine der Vorlage ersetzen (Glass = Fläche der Karten, GlassEdge = ihr Rand)
#   Replace   beliebige Textstellen der Vorlagen ersetzen: Paare aus "alt" und "neu"
#   Overlay   zusätzliche Ebene über dem Fensterhintergrund (XAML)
#   Transform eigene Rechenvorschrift für alles Weitere: bekommt den XAML-Text und gibt ihn verändert zurück
#   Start     läuft einmal, sobald das Fenster steht - für Dauerbewegungen (mit Add-SkinMotion anmelden)
#   Speed     Tempo der Bewegungen: 1 = wie gewohnt, kleiner = schneller
#   Calm      $true: nichts federt nach
#   Snappy    $true: Bewegungen schießen los und bremsen hart

$script:Skins = [ordered]@{
    'Standard'  = @{ Text = 'Klassisch' }   # das Aussehen vor Oktober 2026

    # Das Aussehen ab Oktober 2026: tiefe Nacht, Cyan und Violett, ruhige Karten mit leuchtendem Rand und
    # ein Puls, der als Schweif um den SCAN-Knopf läuft
    'NachtPuls' = @{
        Text     = 'Nacht Puls'
        Ring     = 'Herzmonitor'
        Theme    = 'Nachtblau'
        ThemeDef = @{ Hue = 222.0; Sat = 0.8; Light = -0.03; A = '#5CC8FF', '#7C9CFF', '#9B7BFF'; R = '#5CC8FF', '#7CA8FF', '#9B7BFF'; OnAccent = '#06101C' }
        # weiche, etwas größere Rundungen an Karten und Flächen
        Radius   = { param($r) if ($r -ge 14) { $r + 4 } else { $r } }
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#E6111A2E" Offset="0"/>
            <GradientStop Color="#E60D1424" Offset="1"/>
        </LinearGradientBrush>
'@
            # der Rand leuchtet oben links in der ersten und unten rechts in der dritten Akzentfarbe
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#7022D3EE" Offset="0"/>
            <GradientStop Color="#1E2A3A5C" Offset="0.32"/>
            <GradientStop Color="#1E2A3A5C" Offset="0.7"/>
            <GradientStop Color="#5AA855F7" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # der Farbschein im Hintergrund bleibt zart, die Fläche dunkel
            '#2A22D3EE', '#1422D3EE',
            '#2EA855F7', '#16A855F7',
            '#2A3B82F6', '#1A3B82F6',
            # Hintergrund des Fensters: tiefes Nachtblau statt Mitternacht
            '<GradientStop Color="#0C1326" Offset="0"/>', '<GradientStop Color="#0B1020" Offset="0"/>',
            '<GradientStop Color="#090D1A" Offset="1"/>', '<GradientStop Color="#080B15" Offset="1"/>'
        )
        Speed    = 0.95
    }

    'Cyberpunk' = @{
        Text     = 'Cyberpunk'
        Ring     = 'Cyberpunk'
        Theme    = 'Cyberpunk'
        ThemeDef = @{ Hue = 252.0; Sat = 0.9; Light = -0.055; A = '#FCEE0A', '#FF7A1A', '#FF2A6D'; R = '#05D9E8', '#00A3FF', '#D300C5'; OnAccent = '#16060C' }
        # kantig: kleine Ecken verschwinden, große bleiben nur an zwei gegenüberliegenden Seiten
        Radius   = { param($r) if ($r -le 4) { 0 } elseif ($r -lt 10) { '0,{0},0,{0}' -f [Math]::Round($r * 0.75) } else { '0,{0},0,{0}' -f $r } }
        Font     = 'Bahnschrift, Segoe UI'
        FontMore = 'FontStretch="SemiCondensed"'
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#1C22D3EE" Offset="0"/>
            <GradientStop Color="#08FFFFFF" Offset="0.3"/>
            <GradientStop Color="#05FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#C022D3EE" Offset="0"/>
            <GradientStop Color="#2822D3EE" Offset="0.3"/>
            <GradientStop Color="#28A855F7" Offset="0.7"/>
            <GradientStop Color="#B0A855F7" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # der Farbschein im Hintergrund leuchtet kräftiger
            '#2A22D3EE', '#3822D3EE',
            '#2EA855F7', '#40A855F7'
        )
        # feine waagerechte Linien wie auf einem alten Röhrenbildschirm
        Overlay  = @'
<Border Grid.ColumnSpan="2" Grid.RowSpan="2" CornerRadius="18" IsHitTestVisible="False" Opacity="0.045">
                    <Border.Background>
                        <DrawingBrush TileMode="Tile" Viewport="0,0,4,4" ViewportUnits="Absolute">
                            <DrawingBrush.Drawing>
                                <DrawingGroup>
                                    <GeometryDrawing Brush="Transparent">
                                        <GeometryDrawing.Geometry>
                                            <RectangleGeometry Rect="0,0,4,4"/>
                                        </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                    <GeometryDrawing Brush="White">
                                        <GeometryDrawing.Geometry>
                                            <RectangleGeometry Rect="0,0,4,1"/>
                                        </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                </DrawingGroup>
                            </DrawingBrush.Drawing>
                        </DrawingBrush>
                    </Border.Background>
                </Border>
'@
        Speed    = 0.7
        Snappy   = $true
    }

    'Minimal'   = @{
        Text     = 'Minimal'
        Ring     = 'Minimal'
        Theme    = 'Minimal'
        ThemeDef = @{ Hue = 225.0; Sat = 0.1; Light = 0.03; A = '#F4F4F5', '#D4D4D8', '#A1A1AA'; R = '#FF5A36', '#FF8A65', '#FFC2B0'; OnAccent = '#111113' }
        # knappe, überall gleiche Ecken
        Radius   = { param($r) if ($r -ge 14) { 6 } elseif ($r -ge 8) { 4 } else { [Math]::Min($r, 2) } }
        Font     = 'Segoe UI Variable Text, Segoe UI'
        Weights  = @{ SemiBold = 'Normal'; Bold = 'SemiBold' }
        Resources = @{
            Glass     = '<SolidColorBrush x:Key="Glass" Color="#09FFFFFF"/>'
            GlassEdge = '<SolidColorBrush x:Key="GlassEdge" Color="#16FFFFFF"/>'
        }
        Replace  = @(
            # kaum Farbschein: die Fläche bleibt ruhig
            '#2A22D3EE', '#0A22D3EE',
            '#2EA855F7', '#0AA855F7',
            '#2A3B82F6', '#0E3B82F6'
        )
        Calm     = $true
    }
    'Modern'    = @{
        Text     = 'Modern'
        Ring     = 'Modern'
        Theme    = 'Modern'
        ThemeDef = @{ Hue = 238.0; Sat = 1.0; Light = -0.02; A = '#8B5CF6', '#EC4899', '#F59E0B'; R = '#34D399', '#22D3EE', '#3B82F6'; OnAccent = '#FFFFFF' }
        # große, weiche Rundungen
        Radius   = { param($r) [Math]::Round($r * 1.6, 1) }
        Weights  = @{ SemiBold = 'Bold' }
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#2A22D3EE" Offset="0"/>
            <GradientStop Color="#0CFFFFFF" Offset="0.5"/>
            <GradientStop Color="#24A855F7" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#55FFFFFF" Offset="0"/>
            <GradientStop Color="#1FFFFFFF" Offset="0.2"/>
            <GradientStop Color="#14FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # kräftiger Farbschein im Hintergrund
            '#2A22D3EE', '#4222D3EE',
            '#2EA855F7', '#4AA855F7'
        )
    }

    'Designer'  = @{
        Text     = 'Designer'
        Ring     = 'Designer'
        Theme    = 'Designer'
        ThemeDef = @{ Hue = 32.0; Sat = 0.3; Light = -0.03; A = '#E9C46A', '#E9B44C', '#F4A261'; R = '#7DD3FC', '#38BDF8', '#0EA5E9'; OnAccent = '#1A1408' }
        # wie gedruckt: keine Rundungen
        Radius   = { param($r) 0 }
        Font     = 'Segoe UI Variable Text, Segoe UI'
        Weights  = @{ Bold = 'SemiBold' }
        Resources = @{
            Glass     = '<SolidColorBrush x:Key="Glass" Color="#00FFFFFF"/>'
            GlassEdge = '<SolidColorBrush x:Key="GlassEdge" Color="#2CFFFFFF"/>'
        }
        Replace  = @(
            # Zeilen und Kacheln ohne Fläche, nur mit feiner Linie
            'Background="#0AFFFFFF" BorderBrush="#14FFFFFF"', 'Background="#00FFFFFF" BorderBrush="#2CFFFFFF"',
            '#2A22D3EE', '#1022D3EE',
            '#2EA855F7', '#10A855F7',
            '#2A3B82F6', '#103B82F6'
        )
        # große Schrift wird zur Überschrift in einer Buchschrift, wie in einem Magazin
        Transform = {
            param($text)
            [regex]::Replace($text, '<TextBlock\b[^>]*>', [Text.RegularExpressions.MatchEvaluator] {
                    param($match)
                    $tag = $match.Value
                    if ($tag -match 'FontFamily=' -or $tag -notmatch 'FontSize="(\d+(?:\.\d+)?)"') { return $tag }
                    if ([double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) -lt 18) { return $tag }
                    $tag = $tag -replace '\sFontWeight="[^"]*"', ''
                    $tag -replace '^<TextBlock\b', '<TextBlock FontFamily="Sitka Display, Cambria, Georgia" FontWeight="Normal"'
                })
        }
        Calm     = $true
    }

    'Animiert'  = @{
        Text     = 'Animiert'
        Ring     = 'Animiert'
        Theme    = 'Animiert'
        ThemeDef = @{ Hue = 232.0; Sat = 1.0; Light = -0.03; A = '#38BDF8', '#818CF8', '#E879F9'; R = '#FDE047', '#FB923C', '#F43F5E'; OnAccent = '#FFFFFF' }
        Replace  = @(
            '#2A22D3EE', '#3A22D3EE',
            '#2EA855F7', '#40A855F7'
        )
        # um das Fenster läuft ein Farbband
        Overlay  = @'
<Border x:Name="SkinEdge" Grid.ColumnSpan="2" Grid.RowSpan="2" CornerRadius="18" BorderThickness="1.6" IsHitTestVisible="False" Opacity="0.85">
                    <Border.BorderBrush>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <LinearGradientBrush.RelativeTransform>
                                <RotateTransform x:Name="SkinEdgeTurn" CenterX="0.5" CenterY="0.5"/>
                            </LinearGradientBrush.RelativeTransform>
                            <GradientStop Color="#22D3EE" Offset="0"/>
                            <GradientStop Color="#006366F1" Offset="0.35"/>
                            <GradientStop Color="#00A855F7" Offset="0.65"/>
                            <GradientStop Color="#A855F7" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.BorderBrush>
                </Border>
'@
        # Dauerbewegungen: das Farbband kreist, die beiden Farbscheine im Hintergrund wandern und atmen.
        # Sie laufen mit gedrosselter Bildrate und ruhen beim Scannen und im Hintergrund.
        Start    = {
            $turn = $window.FindName('SkinEdgeTurn')
            if ($turn) { Add-SkinMotion $turn $P.Angle (New-DoubleAnim -From 0 -To 360 -Ms 9000 -Linear -Forever) }
            $moves = @(@{ Name = 'GlowA'; X = 260; Y = 150; Ms = 11000 }, @{ Name = 'GlowB'; X = -300; Y = -170; Ms = 14000 })
            foreach ($move in $moves) {
                $glow = $window.FindName($move.Name)
                if (-not $glow) { continue }
                $shift = New-Object Windows.Media.TranslateTransform
                $glow.RenderTransform = $shift
                Add-SkinMotion $shift $P.X (New-DoubleAnim -From 0 -To $move.X -Ms $move.Ms -Ease $script:EaseSine -Forever -AutoReverse)
                Add-SkinMotion $shift $P.Y (New-DoubleAnim -From 0 -To $move.Y -Ms ($move.Ms * 0.73) -Ease $script:EaseSine -Forever -AutoReverse)
                Add-SkinMotion $glow $P.Opacity (New-DoubleAnim -From 0.65 -To 1 -Ms ($move.Ms * 0.4) -Ease $script:EaseSine -Forever -AutoReverse)
            }
        }
    }

    'Terminal'  = @{
        Text     = 'Retro-Terminal'
        Ring     = 'Retro-Terminal'
        Theme    = 'Retro-Terminal'
        ThemeDef = @{ Hue = 130.0; Sat = 0.9; Light = -0.08; A = '#39FF14', '#22C55E', '#A3E635'; R = '#FFB000', '#FF8A00', '#FFD866'; OnAccent = '#021204' }
        # wie auf einem alten Bildschirm: nur rechte Winkel
        Radius   = { param($r) 0 }
        Font     = 'Consolas, Lucida Console, Courier New'
        # die Schrift selbst leuchtet in der Farbe des Designs
        Keys     = @{ Text = '#99B4FF'; TextDim = '#5C82E6'; TextFaint = '#3F5FB5' }
        Resources = @{
            # als Verlauf geschrieben, damit die Farbe dem Design folgt (einfarbige Pinsel bleiben, wie sie sind)
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#0A22D3EE" Offset="0"/>
            <GradientStop Color="#0A22D3EE" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#6022D3EE" Offset="0"/>
            <GradientStop Color="#6022D3EE" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # Zeilen und Kacheln: dunkle Fläche mit Linie in der Schriftfarbe
            'Background="#0AFFFFFF" BorderBrush="#14FFFFFF"', 'Background="#0822D3EE" BorderBrush="#3822D3EE"',
            '#2A22D3EE', '#1C22D3EE',
            '#2EA855F7', '#0CA855F7',
            '#2A3B82F6', '#103B82F6',
            # Knöpfe mit weniger Luft an den Seiten
            '<Setter Property="Padding" Value="18,9"/>', '<Setter Property="Padding" Value="12,9"/>',
            # Karten und Aufzählungen enger, damit die breitere Schrift hineinpasst
            '<Setter Property="Padding" Value="22"/>', '<Setter Property="Padding" Value="14"/>',
            'Margin="2,1,10,0"', 'Margin="0,1,6,0"',
            'Padding="18,16,18,14"', 'Padding="12,16,10,14"'
        )
        # die Schreibmaschinenschrift läuft breiter: etwas kleiner setzen, damit kein Text abgeschnitten wird
        Transform = {
            param($text)
            [regex]::Replace($text, '(?<pre>FontSize="|Property="FontSize" Value=")(?<v>\d+(?:\.\d+)?)"', [Text.RegularExpressions.MatchEvaluator] {
                    param($match)
                    $culture = [cultureinfo]::InvariantCulture
                    $size = [double]::Parse($match.Groups['v'].Value, $culture)
                    if ($size -ge 11) { $size = [Math]::Max(10.5, [Math]::Round($size * 0.87 * 2) / 2) }
                    $match.Groups['pre'].Value + $size.ToString($culture) + '"'
                })
        }
        # Zeilen des Röhrenbildschirms
        Overlay  = @'
<Border Grid.ColumnSpan="2" Grid.RowSpan="2" CornerRadius="18" IsHitTestVisible="False" Opacity="0.07">
                    <Border.Background>
                        <DrawingBrush TileMode="Tile" Viewport="0,0,3,3" ViewportUnits="Absolute">
                            <DrawingBrush.Drawing>
                                <DrawingGroup>
                                    <GeometryDrawing Brush="Transparent">
                                        <GeometryDrawing.Geometry>
                                            <RectangleGeometry Rect="0,0,3,3"/>
                                        </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                    <GeometryDrawing Brush="#22D3EE">
                                        <GeometryDrawing.Geometry>
                                            <RectangleGeometry Rect="0,0,3,1"/>
                                        </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                </DrawingGroup>
                            </DrawingBrush.Drawing>
                        </DrawingBrush>
                    </Border.Background>
                </Border>
'@
        Speed    = 0.6
        Snappy   = $true
    }

    'Glas'      = @{
        Text     = 'Glas'
        Ring     = 'Glas'
        Theme    = 'Glas'
        ThemeDef = @{ Hue = 205.0; Sat = 0.55; Light = 0.11; A = '#7DD3FC', '#A5B4FC', '#F0ABFC'; R = '#FDE68A', '#FDBA74', '#FDA4AF'; OnAccent = '#0B1220' }
        Radius   = { param($r) [Math]::Round($r * 1.25, 1) }
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#3CFFFFFF" Offset="0"/>
            <GradientStop Color="#14FFFFFF" Offset="0.45"/>
            <GradientStop Color="#24FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#8CFFFFFF" Offset="0"/>
            <GradientStop Color="#30FFFFFF" Offset="0.14"/>
            <GradientStop Color="#22FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # die Scheibe des Inhalts und die Zeilen schimmern heller, der Farbschein dahinter ist kräftiger
            '<GradientStop Color="#0FFFFFFF" Offset="0"/>', '<GradientStop Color="#20FFFFFF" Offset="0"/>',
            'BorderBrush="#21FFFFFF" BorderThickness="1,1,0,0"', 'BorderBrush="#50FFFFFF" BorderThickness="1,1,0,0"',
            'Background="#0AFFFFFF" BorderBrush="#14FFFFFF"', 'Background="#14FFFFFF" BorderBrush="#2CFFFFFF"',
            '#2A22D3EE', '#4A22D3EE',
            '#2EA855F7', '#4AA855F7'
        )
        # das Fenster selbst lässt durchscheinen, was dahinter liegt
        Transform = {
            param($text)
            $text = $text.Replace('<Border CornerRadius="18" Background="#0A0F1E">', '<Border CornerRadius="18" Background="#A60A0F1E">')
            [regex]::Replace($text, '(?s)(<Border x:Name="Shell".*?Color=")#0C1326(".*?Color=")#090D1A', '${1}#A60C1326${2}#A6090D1A')
        }
        Speed    = 1.1
    }

    'Gaming'    = @{
        Text     = 'Gaming'
        Ring     = 'Gaming'
        Theme    = 'Gaming'
        ThemeDef = @{ Hue = 355.0; Sat = 0.5; Light = -0.075; A = '#FF1F3D', '#FF4D00', '#FFB300'; R = '#00E5FF', '#38BDF8', '#F8FAFC'; OnAccent = '#FFFFFF' }
        # schräg geschnitten: Rundung nur links oben und rechts unten
        Radius   = { param($r) if ($r -le 4) { 0 } else { '{0},0,{0},0' -f [Math]::Round($r * 1.1) } }
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#2622D3EE" Offset="0"/>
            <GradientStop Color="#08FFFFFF" Offset="0.4"/>
            <GradientStop Color="#04FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = @'
<LinearGradientBrush x:Key="GlassEdge" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#E022D3EE" Offset="0"/>
            <GradientStop Color="#3022D3EE" Offset="0.35"/>
            <GradientStop Color="#18FFFFFF" Offset="1"/>
        </LinearGradientBrush>
'@
        }
        Replace  = @(
            # kräftiges Leuchten im Hintergrund
            '#2A22D3EE', '#5222D3EE',
            '#2EA855F7', '#44A855F7',
            '#2A3B82F6', '#3A3B82F6'
        )
        # schräge Streifen, die von rechts oben ins Fenster laufen
        Overlay  = @'
<Border Grid.ColumnSpan="2" Grid.RowSpan="2" CornerRadius="18" IsHitTestVisible="False" Opacity="0.2">
                    <Border.Background>
                        <LinearGradientBrush MappingMode="Absolute" SpreadMethod="Repeat" StartPoint="0,0" EndPoint="11,11">
                            <GradientStop Color="#22D3EE" Offset="0"/>
                            <GradientStop Color="#22D3EE" Offset="0.16"/>
                            <GradientStop Color="#0022D3EE" Offset="0.16"/>
                            <GradientStop Color="#0022D3EE" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <Border.OpacityMask>
                        <LinearGradientBrush StartPoint="1,0" EndPoint="0.5,0.7">
                            <GradientStop Color="#FF000000" Offset="0"/>
                            <GradientStop Color="#00000000" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.OpacityMask>
                </Border>
'@
        # große Schrift steht fett und schräg
        Transform = {
            param($text)
            [regex]::Replace($text, '<TextBlock\b[^>]*>', [Text.RegularExpressions.MatchEvaluator] {
                    param($match)
                    $tag = $match.Value
                    if ($tag -match 'FontFamily=|FontStyle=' -or $tag -notmatch 'FontSize="(\d+(?:\.\d+)?)"') { return $tag }
                    if ([double]::Parse($Matches[1], [cultureinfo]::InvariantCulture) -lt 18) { return $tag }
                    $tag = $tag -replace '\sFontWeight="[^"]*"', ''
                    $tag -replace '^<TextBlock\b', '<TextBlock FontStyle="Italic" FontWeight="Bold"'
                })
        }
        Speed    = 0.75
        Snappy   = $true
    }

    'Pastell'   = @{
        Text     = 'Pastell'
        Ring     = 'Pastell'
        Theme    = 'Pastell'
        ThemeDef = @{ Hue = 265.0; Sat = 0.42; Light = 0.13; A = '#F9A8D4', '#C4B5FD', '#93C5FD'; R = '#FDE68A', '#A7F3D0', '#99F6E4'; OnAccent = '#2A1B3D' }
        # rund wie Kiesel
        Radius   = { param($r) [Math]::Round($r * 2.0, 1) }
        Weights  = @{ Bold = 'SemiBold' }
        Resources = @{
            Glass     = @'
<LinearGradientBrush x:Key="Glass" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#1C22D3EE" Offset="0"/>
            <GradientStop Color="#10FFFFFF" Offset="0.5"/>
            <GradientStop Color="#1CA855F7" Offset="1"/>
        </LinearGradientBrush>
'@
            GlassEdge = '<SolidColorBrush x:Key="GlassEdge" Color="#2EFFFFFF"/>'
        }
        Replace  = @(
            '#2A22D3EE', '#3222D3EE',
            '#2EA855F7', '#32A855F7'
        )
        Speed    = 1.15
    }

    'Kontrast'  = @{
        Text     = 'Kontrast'
        Ring     = 'Kontrast'
        Theme    = 'Kontrast'
        ThemeDef = @{ Hue = 224.0; Sat = 0.0; Light = -0.12; A = '#FFD60A', '#FFD60A', '#FFC400'; R = '#FFFFFF', '#E5E5E5', '#FFFFFF'; OnAccent = '#000000' }
        Radius   = { param($r) if ($r -ge 8) { 4 } else { [Math]::Min($r, 2) } }
        Weights  = @{ SemiBold = 'Bold' }
        # auch die leise Schrift bleibt hell genug zum Lesen
        Keys     = @{ Text = '#FFFFFF'; TextDim = '#CDCDCD'; TextFaint = '#A2A2A2' }
        Resources = @{
            Glass     = '<SolidColorBrush x:Key="Glass" Color="#00FFFFFF"/>'
            GlassEdge = '<SolidColorBrush x:Key="GlassEdge" Color="#B0FFFFFF"/>'
        }
        Replace  = @(
            # klare weiße Linien statt Flächen, kein Farbschein
            'Background="#0AFFFFFF" BorderBrush="#14FFFFFF"', 'Background="#00FFFFFF" BorderBrush="#70FFFFFF"',
            'BorderBrush="#21FFFFFF" BorderThickness="1,1,0,0"', 'BorderBrush="#70FFFFFF" BorderThickness="1,1,0,0"',
            '#2A22D3EE', '#0022D3EE',
            '#2EA855F7', '#00A855F7',
            '#2A3B82F6', '#003B82F6',
            '#146366F1', '#006366F1',
            # der Haken steht schwarz auf der Signalfarbe
            'Stroke="White" StrokeThickness="2.2"', 'Stroke="Black" StrokeThickness="2.6"'
        )
        Calm     = $true
    }
}


# die Farbdesigns der Skins stehen neben den übrigen zur Wahl
foreach ($name in $script:Skins.Keys) {
    $entry = $script:Skins[$name]
    if ($entry.Theme -and $entry.ThemeDef -and -not $script:Themes.Contains($entry.Theme)) { $script:Themes[$entry.Theme] = $entry.ThemeDef }
}

# zum Prüfen: die Umgebungsvariable PULSRIG_SKIN startet das Programm in einem bestimmten Skin
if ($env:PULSRIG_SKIN -and $script:Skins.Contains($env:PULSRIG_SKIN)) {
    $script:Settings.Skin = $env:PULSRIG_SKIN
    if ($script:Skins[$env:PULSRIG_SKIN].Theme) { $script:Settings.Theme = $script:Skins[$env:PULSRIG_SKIN].Theme }
}
if (-not $script:Skins.Contains("$($script:Settings.Skin)")) { $script:Settings.Skin = 'Standard' }
$script:Skin = $script:Skins[$script:Settings.Skin]
# Der Skin bringt seine Ring-Animation mit: einmal beim Wechsel in den Skin, danach gilt wieder die Wahl des Nutzers.
# Die Animation eines anderen Skins bleibt nicht stehen.
if ("$($script:Settings.SkinRing)" -ne "$($script:Settings.Skin)") {
    $skinRings = @($script:Skins.Values | ForEach-Object { $_.Ring } | Where-Object { $_ })
    if ($script:Skin.Ring) { $script:Settings.Ring = $script:Skin.Ring }
    elseif ($skinRings -contains $script:Settings.Ring) { $script:Settings.Ring = 'Puls' }
    $script:Settings.SkinRing = "$($script:Settings.Skin)"
}
if ($script:Skin.Keys) { foreach ($key in $script:Skin.Keys.Keys) { $script:ThemeKeys[$key] = $script:Skin.Keys[$key] } }
$script:SkinSpeedBase = if ($script:Skin.Speed) { [double]$script:Skin.Speed } else { 1.0 }

# Stufe der Bewegung (Optionen → Allgemein): Ruhig lässt Ring und Übergänge langsamer laufen, Lebendig schneller.
# MotionFactor ist das Tempo der Dauerbewegungen, SkinSpeed die Länge der Übergänge (kleiner = schneller).
function Update-Motion {
    $level = "$($script:Settings.Motion)"
    $script:MotionFactor = switch ($level) { 'Ruhig' { 0.6 } 'Lebendig' { 1.45 } default { 1.0 } }
    $script:SkinSpeed = $script:SkinSpeedBase * $(switch ($level) { 'Ruhig' { 1.3 } 'Lebendig' { 0.8 } default { 1.0 } })
    foreach ($entry in @($script:RingAnims)) { if ($entry -and $entry.Clock) { $entry.Clock.Controller.SpeedRatio = $script:RingSpeed * $script:MotionFactor } }
}
Update-Motion

# Die Farbdesigns zur Auswahl: alle allgemeinen und das des gewählten Skins - die der anderen Skins gehören zu ihnen
function Get-ThemeNames {
    $foreign = @($script:Skins.Keys | Where-Object { $_ -ne $script:Settings.Skin -and $script:Skins[$_].Theme } | ForEach-Object { $script:Skins[$_].Theme })
    @($script:Themes.Keys | Where-Object { $foreign -notcontains $_ })
}

# Ecke für Flächen, die das Programm selbst baut (nicht aus einer Vorlage): gleiche Regel wie für die Vorlagen
function Get-SkinRadius([double]$Radius) {
    if (-not $script:Skin.Radius) { return $Radius }
    $value = & $script:Skin.Radius $Radius
    if ($value -is [string]) { $value } else { [double]$value }
}

$script:SkinRadiusEvaluator = [Text.RegularExpressions.MatchEvaluator] {
    param($match)
    $culture = [cultureinfo]::InvariantCulture
    $numbers = @($match.Groups['v'].Value -split ',' | ForEach-Object { [double]::Parse($_.Trim(), $culture) })
    $single = $match.Groups['pre'].Value -notmatch 'Radius[XY]'
    if ($numbers.Count -eq 1 -and $single) {
        $value = & $script:Skin.Radius $numbers[0]
        $text = if ($value -is [string]) { $value } else { ([double]$value).ToString($culture) }
    }
    else {
        # mehrere Werte oder die Rundung eines Rechtecks: jeder Wert für sich, ohne Aufteilung auf vier Ecken
        $text = (@($numbers | ForEach-Object {
                    $value = & $script:Skin.Radius $_
                    if ($value -is [string]) { $value = (@($value -split ',' | ForEach-Object { [double]::Parse($_, $culture) }) | Measure-Object -Minimum).Minimum }
                    ([double]$value).ToString($culture)
                })) -join ','
    }
    $match.Groups['pre'].Value + $text + '"'
}

# Schreibt einen XAML-Text auf den gewählten Skin um; ohne Skin bleibt er, wie er ist
function ConvertTo-SkinXaml([string]$Text) {
    $skin = $script:Skin
    if ($skin.Overlay) { $Text = $Text.Replace('<!-- Skin-Ebene -->', $skin.Overlay) }
    if ($skin.Resources) {
        foreach ($key in $skin.Resources.Keys) {
            $found = [regex]::Match($Text, '(?s)<LinearGradientBrush x:Key="' + $key + '".*?</LinearGradientBrush>|<SolidColorBrush x:Key="' + $key + '"[^>]*/>')
            if ($found.Success) { $Text = $Text.Substring(0, $found.Index) + $skin.Resources[$key].Trim() + $Text.Substring($found.Index + $found.Length) }
        }
    }
    if ($skin.Replace) { for ($i = 0; $i + 1 -lt $skin.Replace.Count; $i += 2) { $Text = $Text.Replace($skin.Replace[$i], $skin.Replace[$i + 1]) } }
    if ($skin.Transform) { $Text = "$(& $skin.Transform $Text)" }
    if ($skin.Radius) {
        $Text = [regex]::Replace($Text, '(?<pre>CornerRadius="|Property="CornerRadius" Value="|Radius[XY]="|Property="Radius[XY]" Value=")(?<v>[0-9][0-9\.,\s]*)"', $script:SkinRadiusEvaluator)
    }
    if ($skin.Font) { $Text = $Text.Replace('FontFamily="Segoe UI Variable Display, Segoe UI"', ('FontFamily="' + $skin.Font + '"' + $(if ($skin.FontMore) { ' ' + $skin.FontMore }))) }
    if ($skin.Weights) {
        # erst auf Platzhalter, dann auf die Zielwerte: sonst würde SemiBold -> Normal und Bold -> SemiBold sich überkreuzen
        foreach ($from in $skin.Weights.Keys) { $Text = $Text -replace ('(FontWeight(?:" Value)?=")' + $from + '"'), ('$1~' + $from + '~"') }
        foreach ($from in $skin.Weights.Keys) { $Text = $Text.Replace('~' + $from + '~', $skin.Weights[$from]) }
    }
    $Text
}

# Dauerbewegungen eines Skins: jede bekommt eine eigene Uhr, damit sie sich gemeinsam anhalten lassen, und eine
# gedrosselte Bildrate - das Fenster ist durchscheinend, jedes neue Bild kostet Rechenzeit
$script:SkinClocks = @()
function Add-SkinMotion($Target, $Property, $Animation, [int]$Fps = 20) {
    if (-not $script:Settings.Animations) { return }
    [Windows.Media.Animation.Timeline]::SetDesiredFrameRate($Animation, $Fps)
    $clock = $Animation.CreateClock()
    $Target.ApplyAnimationClock($Property, $clock)
    $script:SkinClocks += $clock
}

# Hält die Dauerbewegungen an (beim Scannen und im Hintergrund) oder lässt sie weiterlaufen
function Set-SkinMotion([bool]$Run) {
    foreach ($clock in $script:SkinClocks) {
        if ($Run -and $script:Settings.Animations) { $clock.Controller.Resume() } else { $clock.Controller.Pause() }
    }
}

# Wählt einen Skin: speichert ihn samt seinem Farbdesign und startet das Fenster neu, damit er überall gilt
function Set-Skin([string]$Name) {
    if (-not $script:Skins.Contains($Name) -or $Name -eq $script:Settings.Skin) { return }
    if ($script:Busy) { Set-StatusText 'Den Skin erst wechseln, wenn die laufende Aufgabe fertig ist'; return }
    $old = $script:Skins[$script:Settings.Skin]
    $new = $script:Skins[$Name]
    $script:Settings.Skin = $Name
    if ($new.Theme) { $script:Settings.Theme = $new.Theme }
    elseif ($old.Theme -and $script:Settings.Theme -eq $old.Theme) { $script:Settings.Theme = 'Mitternacht' }
    Save-Settings
    if ($Snapshot) { return }
    $script:RestartAfterClose = $true
    $window.Close()
}

# Startet das Programm neu (nach dem Schließen des Fensters); ohne Adminrechte auch ohne neue Rückfrage danach
function Start-AppAgain {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script:Self`"")
    if (-not $script:IsAdmin) { $arguments += '-NoElevate' }
    Start-Process -FilePath (Get-Process -Id $PID).Path -WindowStyle Hidden -ArgumentList $arguments
}
