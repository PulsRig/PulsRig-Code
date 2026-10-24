# Ring-Animationen um den SCAN-Knopf. Wird von PulsRig.ps1 eingebunden und nutzt dessen
# Fenster ($window, $ui), die Animationshelfer (New-DoubleAnim, $P) und das Farbverzeichnis.
#
# Gezeichnet wird auf $ui.RingLayer, einer Fläche von 300 x 300 mit dem Knopf in der Mitte (150, 150).
# Der Knopf selbst reicht bis Radius 99 - alle Formen bleiben außerhalb davon und innerhalb von 148.
# Die Farben kommen aus den Ringfarben des Designs (Ring1-Ring3, RingGrad) und wechseln mit ihm.

$script:RingNames = 'Klassik', 'Welle', 'RGB', 'Komet', 'Technik', 'Sechseck', 'Orbit', 'Neon', 'Pac-Man', 'Puls'
$script:RingAnims = New-Object Collections.ArrayList   # @{ Target; Property; Clock } aller laufenden Daueranimationen
$script:RingRunning = $false
$script:RingStill = $false
$script:RingSpeed = 1.0      # Tempo, mit dem alle Bewegungen gerade laufen
$script:RingSpeedTo = 1.0    # Tempo, auf das sie zugleiten

function Get-RingBrush([string]$Key) { $window.FindResource($Key) }
function New-RingPoint([double]$Radius, [double]$Degrees) {
    $angle = $Degrees * [Math]::PI / 180.0
    New-Object Windows.Point (150.0 + $Radius * [Math]::Cos($angle)), (150.0 + $Radius * [Math]::Sin($angle))
}

function Add-RingAnim($Target, $Property, $Animation) {
    if ($script:RingStill) { return }
    # eigene Uhr je Bewegung: über sie lässt sich das Tempo im Lauf ändern, ohne dass etwas springt
    $clock = $Animation.CreateClock()
    $clock.Controller.SpeedRatio = $script:RingSpeed * $script:MotionFactor
    $Target.ApplyAnimationClock($Property, $clock)
    [void]$script:RingAnims.Add(@{ Target = $Target; Property = $Property; Clock = $clock })
}

# Tempo aller Bewegungen des Rings. Es gleitet in kleinen Schritten zum neuen Wert; weil alle Uhren im
# selben Augenblick umgestellt werden, bleiben die Teile eines Stils zueinander im Takt.
function Set-RingSpeed([double]$Ratio) {
    $script:RingSpeedTo = $Ratio
    if (-not $script:RingRunning) { $script:RingSpeed = $Ratio; return }
    if (-not $script:RingSpeedTimer) {
        $script:RingSpeedTimer = New-Object Windows.Threading.DispatcherTimer
        $script:RingSpeedTimer.Interval = [TimeSpan]::FromMilliseconds(40)
        $script:RingSpeedTimer.Add_Tick({
                try {
                    $rest = $script:RingSpeedTo - $script:RingSpeed
                    if ([Math]::Abs($rest) -le 0.03) { $script:RingSpeed = $script:RingSpeedTo; $script:RingSpeedTimer.Stop() }
                    else { $script:RingSpeed += [Math]::Sign($rest) * 0.03 }
                    foreach ($entry in $script:RingAnims) { $entry.Clock.Controller.SpeedRatio = $script:RingSpeed * $script:MotionFactor }
                }
                catch { $script:RingSpeedTimer.Stop(); Write-AppError $_ }
            })
    }
    $script:RingSpeedTimer.Start()
}

function Set-RingLook($Shape, [double]$Opacity, [double]$Blur) {
    $Shape.Opacity = $Opacity
    $Shape.IsHitTestVisible = $false
    if ($Blur -gt 0) {
        $effect = New-Object Windows.Media.Effects.BlurEffect
        $effect.Radius = $Blur * 2.5
        $Shape.Effect = $effect
    }
}

function Set-RingDash($Shape, [double]$Width, [double[]]$Dash, [double]$Offset, [bool]$Round) {
    # WPF misst Striche in Vielfachen der Linienstärke
    if ($Dash) {
        $list = New-Object Windows.Media.DoubleCollection
        foreach ($value in $Dash) { $list.Add($value / $Width) }
        $Shape.StrokeDashArray = $list
        $Shape.StrokeDashOffset = $Offset / $Width
    }
    if ($Round) { $Shape.StrokeDashCap = 'Round'; $Shape.StrokeStartLineCap = 'Round'; $Shape.StrokeEndLineCap = 'Round'; $Shape.StrokeLineJoin = 'Round' }
}

# Gruppe, die sich als Ganzes um die Mitte drehen lässt
function New-RingGroup {
    param($Parent = $ui.RingLayer, [double]$Angle = 0)
    $group = New-Object Windows.Controls.Canvas
    $group.Width = 300; $group.Height = 300
    $group.IsHitTestVisible = $false
    $group.RenderTransform = New-Object Windows.Media.RotateTransform $Angle, 150, 150
    [void]$Parent.Children.Add($group)
    $group
}

# Kreis oder Kreisbogen (mit -Dash) um die Mitte; -Scale macht ihn skalierbar statt drehbar
function Add-RingCircle {
    param($Parent = $ui.RingLayer, [double]$R, [double]$W = 3, $Brush, [double[]]$Dash, [double]$Offset = 0,
        [double]$Opacity = 1, [switch]$Round, [double]$Blur = 0, [switch]$Scale, [double]$Angle = 0)
    $shape = New-Object Windows.Shapes.Ellipse
    $shape.Width = 2 * $R + $W; $shape.Height = 2 * $R + $W
    $shape.StrokeThickness = $W
    $shape.Stroke = $Brush
    [Windows.Controls.Canvas]::SetLeft($shape, 150 - $R - $W / 2)
    [Windows.Controls.Canvas]::SetTop($shape, 150 - $R - $W / 2)
    $shape.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $shape.RenderTransform = if ($Scale) { New-Object Windows.Media.ScaleTransform } else { New-Object Windows.Media.RotateTransform $Angle }
    Set-RingDash $shape $W $Dash $Offset $Round.IsPresent
    Set-RingLook $shape $Opacity $Blur
    [void]$Parent.Children.Add($shape)
    $shape
}

function Add-RingDot {
    param($Parent = $ui.RingLayer, [double]$X, [double]$Y, [double]$Size, $Brush, [double]$Opacity = 1, [double]$Blur = 0)
    $shape = New-Object Windows.Shapes.Ellipse
    $shape.Width = 2 * $Size; $shape.Height = 2 * $Size
    $shape.Fill = $Brush
    [Windows.Controls.Canvas]::SetLeft($shape, $X - $Size)
    [Windows.Controls.Canvas]::SetTop($shape, $Y - $Size)
    Set-RingLook $shape $Opacity $Blur
    [void]$Parent.Children.Add($shape)
    $shape
}

# Linienzug durch Punkte; die Form lässt sich um die Mitte skalieren
function Add-RingPath {
    param($Parent = $ui.RingLayer, $Points, $Geometry, [switch]$Open, $Stroke, [double]$W = 2, $Fill, [double[]]$Dash,
        [double]$Offset = 0, [double]$Opacity = 1, [switch]$Round, [double]$Blur = 0)
    if (-not $Geometry) {
        $Geometry = New-Object Windows.Media.StreamGeometry
        $context = $Geometry.Open()
        $context.BeginFigure($Points[0], [bool]$Fill, -not $Open)
        for ($i = 1; $i -lt $Points.Count; $i++) { $context.LineTo($Points[$i], $true, $true) }
        $context.Close()
        $Geometry.Freeze()
    }
    $shape = New-Object Windows.Shapes.Path
    $shape.Data = $Geometry
    if ($Stroke) { $shape.Stroke = $Stroke; $shape.StrokeThickness = $W }
    if ($Fill) { $shape.Fill = $Fill }
    $shape.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 1, 150, 150
    Set-RingDash $shape $W $Dash $Offset $Round.IsPresent
    Set-RingLook $shape $Opacity $Blur
    [void]$Parent.Children.Add($shape)
    $shape
}

# --- Bewegungen ---------------------------------------------------------------

function Start-RingSpin($Element, [double]$Seconds, [int]$Direction = 1) {
    $transform = $Element.RenderTransform
    $from = $transform.Angle
    Add-RingAnim $transform $P.Angle (New-DoubleAnim -From $from -To ($from + 360 * $Direction) -Ms ($Seconds * 1000) -Linear -Forever)
}

# Dreht ruckweise in gleichen Schritten weiter (Lauflicht von Strich zu Strich)
function Start-RingSteps($Element, [double]$Seconds, [int]$Steps) {
    $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animation.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($Seconds))
    $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; Set-IdleFps $animation
    for ($i = 0; $i -lt $Steps; $i++) {
        $time = [Windows.Media.Animation.KeyTime]::FromPercent($i / $Steps)
        [void]$animation.KeyFrames.Add((New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame (360.0 * $i / $Steps), $time))
    }
    Add-RingAnim $Element.RenderTransform $P.Angle $animation
}

# Welle, die sich von der Form löst: wächst und verblasst
function Start-RingPulse($Element, [double]$To, [int]$Ms, [int]$Delay = 0, [double]$From = 0.55) {
    $Element.Opacity = 0
    $transform = $Element.RenderTransform
    Add-RingAnim $transform $P.ScaleX (New-DoubleAnim -From 1 -To $To -Ms $Ms -Delay $Delay -Forever)
    Add-RingAnim $transform $P.ScaleY (New-DoubleAnim -From 1 -To $To -Ms $Ms -Delay $Delay -Forever)
    Add-RingAnim $Element $P.Opacity (New-DoubleAnim -From $From -To 0 -Ms $Ms -Delay $Delay -Forever)
}

function Start-RingBreathe($Element, [double]$From, [double]$To, [int]$Ms, [int]$Delay = 0) {
    Add-RingAnim $Element $P.Opacity (New-DoubleAnim -From $From -To $To -Ms $Ms -Delay $Delay -Ease $script:EaseSine -Forever -AutoReverse)
}

# Licht, das an einer Linie entlangläuft: verschiebt das Strichmuster um eine ganze Länge
function Start-RingRun($Shape, [double]$Length, [double]$Seconds) {
    Add-RingAnim $Shape $P.Dash (New-DoubleAnim -From 0 -To ($Length / $Shape.StrokeThickness) -Ms ($Seconds * 1000) -Linear -Forever)
}

# Wert, der zu festen Zeitpunkten springt: Liste aus @(Anteil der Dauer, Wert)
function Start-RingFrames($Target, $Property, [double]$Seconds, $Frames) {
    $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animation.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($Seconds))
    $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; Set-IdleFps $animation
    foreach ($frame in $Frames) {
        [void]$animation.KeyFrames.Add((New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame ([double]$frame[1]), ([Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0]))))
    }
    Add-RingAnim $Target $Property $animation
}

# Wert mit Stützstellen: Liste aus @(Anteil der Dauer, Wert); ein drittes $true lässt den Wert dorthin springen
function Start-RingKeys($Target, $Property, [double]$Seconds, $Frames) {
    $animation = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $animation.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($Seconds))
    $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever; Set-IdleFps $animation
    foreach ($frame in $Frames) {
        $time = [Windows.Media.Animation.KeyTime]::FromPercent([double]$frame[0])
        $key = if ($frame.Count -gt 2 -and $frame[2]) { New-Object Windows.Media.Animation.DiscreteDoubleKeyFrame ([double]$frame[1]), $time }
        else { New-Object Windows.Media.Animation.LinearDoubleKeyFrame ([double]$frame[1]), $time }
        [void]$animation.KeyFrames.Add($key)
    }
    Add-RingAnim $Target $Property $animation
}

# --- Bausteine, die mehrere Stile teilen --------------------------------------

# Zwei Ringbögen, die sich gegen den Uhrzeigersinn drehen, über einem blassen Grundring
function Add-RingArcs([double]$R, $Brush) {
    $half = [Math]::PI * $R
    $dash = ($half * 0.682), ($half * 0.318)
    [void](Add-RingCircle -R $R -W 3 -Brush $Brush -Opacity 0.22)
    $group = New-RingGroup
    $glow = Add-RingCircle -Parent $group -R $R -W 5 -Brush $Brush -Dash $dash -Round -Blur 6 -Opacity 0.7
    [void](Add-RingCircle -Parent $group -R $R -W 3 -Brush $Brush -Dash $dash -Round)
    Start-RingBreathe $glow 0.5 0.95 1800
    Start-RingSpin $group 7 -1
}

function Add-RingPulses([double]$R, $Brush, [double]$To) {
    if ($script:RingStill) { return }
    foreach ($delay in 0, 1800) {
        $wave = Add-RingCircle -R $R -W 1.5 -Brush $Brush -Scale
        Start-RingPulse $wave $To 3600 $delay
    }
}

# Wellenlinie um die Mitte: Radius schwankt um $Base
function Get-RingWave([double]$Base, [double]$Amplitude, [int]$Lobes, [double]$Phase) {
    for ($i = 0; $i -lt 240; $i++) {
        $angle = 2 * [Math]::PI * $i / 240
        $radius = $Base + $Amplitude * [Math]::Sin($Lobes * $angle + $Phase)
        New-Object Windows.Point (150.0 + $radius * [Math]::Cos($angle)), (150.0 + $radius * [Math]::Sin($angle))
    }
}

function Add-RingBraid($Front, $Back) {
    $backGroup = New-RingGroup
    [void](Add-RingPath -Parent $backGroup -Points @(Get-RingWave 122 5 12 ([Math]::PI)) -Stroke $Back -W 1.5 -Opacity 0.55 -Round)
    Start-RingSpin $backGroup 40 -1
    $frontGroup = New-RingGroup
    [void](Add-RingPath -Parent $frontGroup -Points @(Get-RingWave 122 5 12 0) -Stroke $Front -W 2 -Opacity 0.9 -Round)
    Start-RingSpin $frontGroup 40 1
}

# Regenbogen-Verlauf, dessen Farben über die Formen wandern
function New-RingRainbow {
    $brush = New-Object Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object Windows.Point 0, 0
    $brush.EndPoint = New-Object Windows.Point 1, 1
    $colors = '#FF4D4D', '#FFD84D', '#4DFF88', '#4DD8FF', '#7A6BFF', '#FF4DD8', '#FF4D4D'
    for ($i = 0; $i -lt $colors.Count; $i++) {
        $brush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($colors[$i])), ($i / ($colors.Count - 1))))
    }
    $brush.RelativeTransform = New-Object Windows.Media.RotateTransform 0, 0.5, 0.5
    Add-RingAnim $brush.RelativeTransform $P.Angle (New-DoubleAnim -From 0 -To 360 -Ms 6000 -Linear -Forever)
    $brush
}

$script:RingHex = @(274, 150), @(212, 257.4), @(88, 257.4), @(26, 150), @(88, 42.6), @(212, 42.6)

# --- Die zehn allgemeinen Stile -----------------------------------------------------------

$script:RingBuilders = @{
    'Klassik'  = {
        $grad = Get-RingBrush 'RingGrad'
        Add-RingPulses 112 $grad 1.3
        $outer = Add-RingCircle -R 127 -W 1.5 -Brush (Get-RingBrush 'Ring1') -Dash 52, 14.5 -Round -Opacity 0.55
        Start-RingSpin $outer 24 1
        Add-RingArcs 112 $grad
    }
    'Welle'    = {
        $grad = Get-RingBrush 'RingGrad'
        Add-RingPulses 106 $grad 1.3
        Add-RingBraid $grad (Get-RingBrush 'Ring1')
        Add-RingArcs 106 $grad
    }
    'RGB'      = {
        $rainbow = New-RingRainbow
        Add-RingPulses 106 $rainbow 1.3
        Add-RingBraid $rainbow $rainbow
        Add-RingArcs 106 $rainbow
    }
    'Komet'    = {
        $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'; $r3 = Get-RingBrush 'Ring3'
        $brushes = $r1, $r2, $r3
        $random = New-Object Random 5
        $dust = New-RingGroup
        for ($i = 0; $i -lt 24; $i++) {
            $point = New-RingPoint (118 + $random.NextDouble() * 24) ($random.NextDouble() * 360)
            $brush = $brushes[$i % 3]
            $dot = Add-RingDot -Parent $dust -X $point.X -Y $point.Y -Size (0.9 + $random.NextDouble() * 1.8) -Brush $brush
            Start-RingBreathe $dot 0.15 1 (800 + $random.Next(1200)) ($random.Next(3000))
        }
        Start-RingSpin $dust 80 -1
        [void](Add-RingCircle -R 107 -W 3 -Brush (Get-RingBrush 'RingGrad') -Opacity 0.22)
        $comets = New-RingGroup
        [void](Add-RingCircle -Parent $comets -R 107 -W 3 -Brush $r3 -Dash 165, 171.15 -Round -Opacity 0.4)
        [void](Add-RingCircle -Parent $comets -R 107 -W 3 -Brush $r2 -Dash 100, 236.15 -Offset -65 -Round -Opacity 0.75)
        [void](Add-RingCircle -Parent $comets -R 107 -W 6 -Brush $r1 -Dash 40, 296.15 -Offset -125 -Round -Blur 6)
        [void](Add-RingCircle -Parent $comets -R 107 -W 3.5 -Brush $r1 -Dash 40, 296.15 -Offset -125 -Round)
        [void](Add-RingDot -Parent $comets -X 153.1 -Y 257 -Size 4.5 -Brush $r1)
        [void](Add-RingDot -Parent $comets -X 146.9 -Y 43 -Size 4.5 -Brush $r1)
        Start-RingSpin $comets 5 1
    }
    'Technik'  = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'
        Add-RingPulses 106 $grad 1.13
        [void](Add-RingCircle -R 128 -W 12 -Brush $r2 -Dash 2, 11.404 -Opacity 0.22)
        [void](Add-RingCircle -R 141 -W 8 -Brush $r1 -Dash 3, 218.48 -Offset 1.5)
        $tail = @(for ($i = 0; $i -lt 23; $i++) { 2; 11.404 }) + 2, 493.96
        $bright = @(for ($i = 0; $i -lt 11; $i++) { 2; 11.404 }) + 2, 654.81
        $light = New-RingGroup
        [void](Add-RingCircle -Parent $light -R 128 -W 12 -Brush $r2 -Dash $tail -Opacity 0.5)
        [void](Add-RingCircle -Parent $light -R 128 -W 14 -Brush $r1 -Dash $bright -Offset -160.85)
        Start-RingSteps $light 5 60
        Add-RingArcs 106 $grad
    }
    'Sechseck' = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'; $r3 = Get-RingBrush 'Ring3'
        $points = @($script:RingHex | ForEach-Object { New-Object Windows.Point $_[0], $_[1] })
        $all = New-RingGroup
        if (-not $script:RingStill) {
            $wave = Add-RingPath -Parent $all -Points $points -Stroke $grad -W 1.5 -Round
            Start-RingPulse $wave 1.13 3600
        }
        $second = New-RingGroup -Parent $all -Angle 30
        [void](Add-RingPath -Parent $second -Points $points -Stroke $r3 -W 1 -Opacity 0.25 -Round)
        $back = Add-RingPath -Parent $second -Points $points -Stroke $r3 -W 2 -Dash 60, 312 -Round
        Start-RingRun $back 744 6
        [void](Add-RingPath -Parent $all -Points $points -Stroke $grad -W 1.5 -Opacity 0.35 -Round)
        $glow = Add-RingPath -Parent $all -Points $points -Stroke $r1 -W 6 -Dash 110, 262 -Round -Opacity 0.6 -Blur 5
        $run = Add-RingPath -Parent $all -Points $points -Stroke $r1 -W 3 -Dash 110, 262 -Round
        Start-RingRun $glow -744 4
        Start-RingRun $run -744 4
        foreach ($point in $points) { [void](Add-RingDot -Parent $all -X $point.X -Y $point.Y -Size 3 -Brush $r2) }
        Start-RingSpin $all 60 1
    }
    'Orbit'    = {
        $line = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(31, 255, 255, 255))
        foreach ($orbit in @(@(108, 'Ring1', 1, 6, 5.0), @(121, 'Ring2', -1, 10, 4.0), @(135, 'Ring3', 1, 16, 3.5))) {
            $brush = Get-RingBrush $orbit[1]
            [void](Add-RingCircle -R $orbit[0] -W 1 -Brush $line)
            $group = New-RingGroup
            [void](Add-RingDot -Parent $group -X (150 + $orbit[0]) -Y 150 -Size ($orbit[4] + 3) -Brush $brush -Opacity 0.6 -Blur 5)
            for ($i = 0; $i -lt 12; $i++) {
                $point = New-RingPoint $orbit[0] (-$orbit[2] * $i * 6.5)
                [void](Add-RingDot -Parent $group -X $point.X -Y $point.Y -Size ($orbit[4] - $i * ($orbit[4] - 0.8) / 11) -Brush $brush -Opacity (1 - $i * 0.07))
            }
            Start-RingSpin $group $orbit[3] $orbit[2]
        }
    }
    'Neon'     = {
        $grad = Get-RingBrush 'RingGrad'
        $halo = Add-RingCircle -R 107 -W 10 -Brush $grad -Blur 11 -Opacity 0.8
        Start-RingBreathe $halo 0.5 0.95 1800
        [void](Add-RingCircle -R 107 -W 6 -Brush $grad -Blur 5 -Opacity 0.9)
        [void](Add-RingCircle -R 107 -W 3 -Brush $grad)
        [void](Add-RingCircle -R 107 -W 1 -Brush ([Windows.Media.Brushes]::White) -Opacity 0.8)
        $brushes = (Get-RingBrush 'Ring1'), (Get-RingBrush 'Ring2'), (Get-RingBrush 'Ring3')
        $durations = 900, 1300, 1100, 1600, 800, 1400
        for ($i = 0; $i -lt 48; $i++) {
            $bar = New-Object Windows.Shapes.Rectangle
            $bar.Width = 2.8; $bar.Height = 26; $bar.RadiusX = 1.4; $bar.RadiusY = 1.4
            $bar.Fill = $brushes[$i % 3]
            $bar.IsHitTestVisible = $false
            [Windows.Controls.Canvas]::SetLeft($bar, 148.6)
            [Windows.Controls.Canvas]::SetTop($bar, 10)
            # der Balken wächst von seinem inneren Ende aus und steht auf seinem Platz im Kreis
            $scale = New-Object Windows.Media.ScaleTransform 1, 0.6, 1.4, 26
            $transform = New-Object Windows.Media.TransformGroup
            $transform.Children.Add($scale)
            $transform.Children.Add((New-Object Windows.Media.RotateTransform ($i * 7.5), 1.4, 140))
            $bar.RenderTransform = $transform
            [void]$ui.RingLayer.Children.Add($bar)
            Add-RingAnim $scale $P.ScaleY (New-DoubleAnim -From 0.25 -To 1 -Ms ($durations[$i % 6] / 2) -Delay (($i * 370) % 1600) -Ease $script:EaseSine -Forever -AutoReverse)
        }
    }
    'Pac-Man'  = {
        $r2 = Get-RingBrush 'Ring2'
        [void](Add-RingCircle -R 104 -W 1.5 -Brush (Get-RingBrush 'RingGrad') -Opacity 0.4)
        # jeder Punkt verschwindet, wenn Pac-Man ihn erreicht, und kommt nach knapp drei Vierteln der Runde wieder
        for ($i = 0; $i -lt 30; $i++) {
            $point = New-RingPoint 124 ($i * 12)
            $dot = Add-RingDot -X $point.X -Y $point.Y -Size 2.4 -Brush $r2
            $eaten = $i / 30.0
            $back = $eaten + 0.72
            $frames = if ($i -eq 0) { @(@(0.0, 0.0), @($back, 1.0)) }
            elseif ($back -le 1.0) { @(@(0.0, 1.0), @($eaten, 0.0), @($back, 1.0)) }
            else { @(@(0.0, 0.0), @(($back - 1.0), 1.0), @($eaten, 0.0)) }
            Start-RingFrames $dot $P.Opacity 6 $frames
        }
        $runner = New-RingGroup
        $ghost = New-RingGroup -Parent $runner -Angle -38
        [void](Add-RingPath -Parent $ghost -Geometry ([Windows.Media.Geometry]::Parse('M264,157 V148 A10,10 0 0 1 284,148 V157 L280.7,153.8 277.3,157 274,153.8 270.7,157 267.3,153.8 Z')) -Fill (Get-RingBrush 'Ring3'))
        [void](Add-RingDot -Parent $ghost -X 270.5 -Y 147.5 -Size 2.4 -Brush ([Windows.Media.Brushes]::White))
        [void](Add-RingDot -Parent $ghost -X 277.5 -Y 147.5 -Size 2.4 -Brush ([Windows.Media.Brushes]::White))
        $yellow = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(255, 216, 77))
        [void](Add-RingPath -Parent $runner -Geometry ([Windows.Media.Geometry]::Parse('M274,150 L279.74,158.19 A10,10 0 1 0 268.26,158.19 Z')) -Fill $yellow)
        $closed = Add-RingDot -Parent $runner -X 274 -Y 150 -Size 10 -Brush $yellow -Opacity 0
        Start-RingFrames $closed $P.Opacity 0.36 @(@(0.0, 0.0), @(0.5, 1.0))
        Start-RingSpin $runner 6 1
    }
    # Herzschlaglinie, zum Kreis gebogen: eine Leuchtspur mit Punkt an der Spitze fährt sie ab wie auf einem
    # Monitor, und bei jedem Ausschlag zuckt die Linie. Bewegt werden nur Deckkraft, Drehung und Größe -
    # das kostet kaum Rechenzeit, anders als wandernde Strichmuster oder Weichzeichner.
    'Puls'     = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'
        $round = 2.7                # Sekunden je Runde der Spur; drei Schläge je Runde
        [void](Add-RingCircle -R 104 -W 1.5 -Brush $grad -Opacity 0.4)
        # ein Herzschlag je Drittelkreis: Grad innerhalb des Schlags und Ausschlag nach außen
        $beat = @(0, 0), @(4, 3), @(8, 0), @(11, 0), @(13, -5), @(16, 22), @(19, -9), @(22, 0), @(27, 5), @(32, 0)
        $points = @(for ($degree = 0; $degree -le 360; $degree++) {
                $local = $degree % 120
                $shift = 0.0
                for ($k = 1; $k -lt $beat.Count; $k++) {
                    if ($local -ge $beat[$k - 1][0] -and $local -le $beat[$k][0]) {
                        $shift = $beat[$k - 1][1] + ($beat[$k][1] - $beat[$k - 1][1]) * ($local - $beat[$k - 1][0]) / ($beat[$k][0] - $beat[$k - 1][0])
                        break
                    }
                }
                New-RingPoint (119 + $shift) ($degree - 106)   # die große Zacke des ersten Schlags zeigt nach oben
            })
        # jeder Schlag schickt zwei kurze Wellen los, genau wenn die Spur die große Zacke erreicht
        if (-not $script:RingStill) {
            foreach ($delay in 120, 300) {
                $wave = Add-RingCircle -R 106 -W 1.5 -Brush $r1 -Scale
                Start-RingPulse $wave 1.2 ($round * 1000 / 3) $delay 0.5
            }
        }
        # die Linie zuckt im Takt: großer Ausschlag, kleiner Nachschlag
        $body = New-RingGroup
        $kick = New-Object Windows.Media.ScaleTransform 1, 1, 150, 150
        $body.RenderTransform = $kick
        $kicks = @(0.0, 1.0), @(0.1, 1.0), @(0.16, 1.05), @(0.27, 1.0), @(0.33, 1.022), @(0.44, 1.0), @(1.0, 1.0)
        Start-RingKeys $kick $P.ScaleX ($round / 3) $kicks
        Start-RingKeys $kick $P.ScaleY ($round / 3) $kicks
        [void](Add-RingPath -Parent $body -Points $points[0..359] -Stroke $grad -W 1.5 -Opacity 0.3 -Round)
        # Leuchtspur: die Linie in Stücken, jedes leuchtet auf, wenn die Spitze ankommt, und verblasst dann
        $pieces = 30; $span = 360 / $pieces; $fade = 0.42
        for ($i = 0; $i -lt $pieces; $i++) {
            $piece = Add-RingPath -Parent $body -Points $points[($i * $span)..(($i + 1) * $span)] -Open -Stroke $r1 -W 2.5 -Round
            $start = $i / $pieces
            if ($start + $fade -le 1.0) {
                $frames = @(@($start, 1.0, $true), @(($start + $fade), 0.0), @(1.0, 0.0))
                if ($i -gt 0) { $frames = @(, @(0.0, 0.0, $true)) + $frames }
                $piece.Opacity = if ($i -eq 0) { 1 } else { 0 }
            }
            else {
                $left = 1.0 - (1.0 - $start) / $fade     # so hell ist das Stück noch, wenn die Runde neu beginnt
                $frames = @(@(0.0, $left, $true), @(($start + $fade - 1.0), 0.0), @($start, 1.0, $true), @(1.0, $left))
                $piece.Opacity = $left
            }
            Start-RingKeys $piece $P.Opacity $round $frames
        }
        # Punkt an der Spitze: dreht mit der Spur und folgt den Ausschlägen nach außen und innen
        $head = New-RingGroup -Parent $body -Angle -106
        $glowBrush = New-Object Windows.Media.RadialGradientBrush
        $glowBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(150, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 0))
        $glowBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 1))
        $slide = New-Object Windows.Media.TranslateTransform
        foreach ($dot in (Add-RingDot -Parent $head -X 269 -Y 150 -Size 11 -Brush $glowBrush), (Add-RingDot -Parent $head -X 269 -Y 150 -Size 3.6 -Brush ([Windows.Media.Brushes]::White))) {
            $dot.RenderTransform = $slide
        }
        $slides = @(for ($b = 0; $b -lt 3; $b++) { foreach ($step in $beat) { , @((($b * 120 + $step[0]) / 360.0), [double]$step[1]) } }) + @(, @(1.0, 0.0))
        Start-RingKeys $slide $P.X $round $slides
        Start-RingSpin $head $round 1
    }

    # --- Stile der Skins: jeder Skin bringt seinen eigenen mit (Feld Ring in PulsRig-Skins.ps1) ---

    # Anzeige aus einem Cockpit: kantige Segmente, die ruckweise weiterspringen, dazu ein Bildfehler, der umherzuckt
    'Cyberpunk' = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'; $r3 = Get-RingBrush 'Ring3'
        [void](Add-RingCircle -R 104 -W 1.5 -Brush $grad -Opacity 0.4)
        [void](Add-RingCircle -R 139 -W 6 -Brush $r1 -Dash 2, 22.26 -Opacity 0.45)
        $brackets = Add-RingCircle -R 146 -W 2 -Brush $r2 -Dash 46, 183.34 -Angle 32 -Opacity 0.8
        Start-RingBreathe $brackets 0.35 0.9 1400
        $segments = New-RingGroup
        [void](Add-RingCircle -Parent $segments -R 114 -W 5 -Brush $r1 -Dash 124, 55.07)
        Start-RingSteps $segments 4 24
        $fine = Add-RingCircle -R 126 -W 2 -Brush $r2 -Dash 30, 13.98 -Opacity 0.7
        Start-RingSpin $fine 30 -1
        # der Bildfehler: ein Stück Ring in der dritten Farbe, das an wechselnden Stellen kurz aufblitzt
        $glitch = Add-RingCircle -R 114 -W 7 -Brush $r3 -Dash 58, 658.28 -Opacity 0.9
        Start-RingFrames $glitch.RenderTransform $P.Angle 2.3 @(@(0.0, 20), @(0.4, 205), @(0.68, 95), @(0.86, 310))
        Start-RingFrames $glitch $P.Opacity 2.3 @(@(0.0, 0.0), @(0.4, 0.9), @(0.45, 0.0), @(0.68, 0.9), @(0.71, 0.0), @(0.86, 0.9), @(0.9, 0.0))
    }
    # so wenig wie möglich: eine feine Linie und ein kurzer Bogen, der ruhig seine Runde zieht
    'Minimal'   = {
        $r1 = Get-RingBrush 'Ring1'
        [void](Add-RingCircle -R 110 -W 1 -Brush $r1 -Opacity 0.3)
        $outer = Add-RingCircle -R 126 -W 1 -Brush $r1 -Opacity 0.14
        Start-RingBreathe $outer 0.06 0.22 2600
        $arc = Add-RingCircle -R 110 -W 2 -Brush $r1 -Dash 90, 601.15 -Round
        Start-RingSpin $arc 6 1
    }
    # breite, weiche Bögen mit runden Enden in drei Bahnen, die gegeneinander laufen
    'Modern'    = {
        $grad = Get-RingBrush 'RingGrad'
        Add-RingPulses 108 $grad 1.3
        [void](Add-RingCircle -R 108 -W 8 -Brush $grad -Opacity 0.14)
        $inner = Add-RingCircle -R 108 -W 8 -Brush $grad -Dash 240, 438.58 -Round
        Start-RingSpin $inner 5 1
        $middle = Add-RingCircle -R 125 -W 5 -Brush (Get-RingBrush 'Ring2') -Dash 150, 635.4 -Round -Opacity 0.75
        Start-RingSpin $middle 8 -1
        $outer = Add-RingCircle -R 139 -W 3 -Brush (Get-RingBrush 'Ring3') -Dash 60, 813.36 -Round -Opacity 0.65
        Start-RingSpin $outer 11 1
    }
    # wie ein Zeichengerät: feine Skala mit langen und kurzen Strichen, Passkreuze und ein Zeiger, der die Runde abfährt
    'Designer'  = {
        $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'
        [void](Add-RingCircle -R 105 -W 1 -Brush $r1 -Opacity 0.5)
        $scale = New-RingGroup
        [void](Add-RingCircle -Parent $scale -R 118 -W 7 -Brush $r1 -Dash 1, 9.297 -Opacity 0.45)
        [void](Add-RingCircle -Parent $scale -R 121 -W 13 -Brush $r1 -Dash 1.5, 61.855 -Opacity 0.9)
        Start-RingSpin $scale 90 1
        [void](Add-RingCircle -R 134 -W 1 -Brush $r2 -Opacity 0.25)
        foreach ($degrees in 0, 90, 180, 270) {
            [void](Add-RingPath -Points (New-RingPoint 128 $degrees), (New-RingPoint 142 $degrees) -Open -Stroke $r2 -W 1 -Opacity 0.8)
            [void](Add-RingPath -Points (New-RingPoint 135 ($degrees - 2.8)), (New-RingPoint 135 ($degrees + 2.8)) -Open -Stroke $r2 -W 1 -Opacity 0.8)
        }
        $quarter = Add-RingCircle -R 134 -W 1.5 -Brush $r2 -Dash 210.5, 631.45
        Start-RingSpin $quarter 14 -1
        $pointer = New-RingGroup
        [void](Add-RingPath -Parent $pointer -Points (New-RingPoint 101 0), (New-RingPoint 112 0) -Open -Stroke $r1 -W 2)
        [void](Add-RingDot -Parent $pointer -X 255 -Y 150 -Size 2.6 -Brush $r1)
        Start-RingSpin $pointer 10 1
    }
    # alles in Bewegung: eine Welle aus Punkten läuft um den Knopf, zwei Bögen jagen sich in Gegenrichtung
    'Animiert'  = {
        $grad = Get-RingBrush 'RingGrad'
        $brushes = (Get-RingBrush 'Ring1'), (Get-RingBrush 'Ring2'), (Get-RingBrush 'Ring3')
        Add-RingPulses 106 $grad 1.3
        $inner = Add-RingCircle -R 106 -W 3 -Brush $grad -Dash 200, 466.02 -Round
        Start-RingSpin $inner 3 1
        $dots = New-RingGroup
        for ($i = 0; $i -lt 24; $i++) {
            $point = New-RingPoint 122 ($i * 15)
            $dot = Add-RingDot -Parent $dots -X $point.X -Y $point.Y -Size 3.4 -Brush $brushes[$i % 3]
            $dot.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
            $dot.RenderTransform = New-Object Windows.Media.ScaleTransform
            # zwei Wellenberge je Runde: jeder Punkt ist seinem Nachbarn ein Stück voraus
            $delay = $i * 100
            Add-RingAnim $dot.RenderTransform $P.ScaleX (New-DoubleAnim -From 0.45 -To 1.5 -Ms 600 -Delay $delay -Ease $script:EaseSine -Forever -AutoReverse)
            Add-RingAnim $dot.RenderTransform $P.ScaleY (New-DoubleAnim -From 0.45 -To 1.5 -Ms 600 -Delay $delay -Ease $script:EaseSine -Forever -AutoReverse)
            Start-RingBreathe $dot 0.3 1 600 $delay
        }
        Start-RingSpin $dots 40 -1
        $outer = Add-RingCircle -R 139 -W 2.5 -Brush $grad -Dash 120, 753.36 -Round -Opacity 0.8
        Start-RingSpin $outer 4 -1
    }
    # Radarschirm: ein Leuchtstrahl mit Nachleuchten kreist, und wo er Ziele überstreicht, blitzen sie auf
    'Retro-Terminal' = {
        $r1 = Get-RingBrush 'Ring1'; $r2 = Get-RingBrush 'Ring2'
        $round = 4.0
        foreach ($radius in 104, 123, 142) { [void](Add-RingCircle -R $radius -W 1 -Brush $r1 -Opacity 0.3) }
        foreach ($degrees in 0, 45, 90, 135, 180, 225, 270, 315) {
            [void](Add-RingPath -Points (New-RingPoint 104 $degrees), (New-RingPoint 142 $degrees) -Open -Stroke $r1 -W 1 -Opacity 0.14)
        }
        # Nachleuchten: Keile, die sich hinter dem Strahl überlagern - je näher am Strahl, desto heller
        $sweep = New-RingGroup
        foreach ($width in 70, 52, 36, 22, 10) {
            $points = @(for ($degrees = - $width; $degrees -le 0; $degrees += 2) { New-RingPoint 104 $degrees }) +
            @(for ($degrees = 0; $degrees -ge - $width; $degrees -= 2) { New-RingPoint 142 $degrees })
            [void](Add-RingPath -Parent $sweep -Points $points -Fill $r1 -Opacity 0.075)
        }
        [void](Add-RingPath -Parent $sweep -Points (New-RingPoint 104 0), (New-RingPoint 142 0) -Open -Stroke $r1 -W 2)
        Start-RingSpin $sweep $round 1
        # Ziele: Stelle in Grad und Abstand; sie leuchten auf, wenn der Strahl ankommt, und verblassen wieder
        foreach ($target in @(@(38, 131), @(112, 116), @(171, 136), @(236, 121), @(301, 132))) {
            $point = New-RingPoint $target[1] $target[0]
            $blip = Add-RingDot -X $point.X -Y $point.Y -Size 3 -Brush $r2
            $at = $target[0] / 360.0; $fade = 0.45
            if ($script:RingStill) { $blip.Opacity = 0.6; continue }
            if ($at + $fade -le 1.0) {
                $blip.Opacity = 0
                Start-RingKeys $blip $P.Opacity $round @(@(0.0, 0.0, $true), @($at, 1.0, $true), @(($at + $fade), 0.0), @(1.0, 0.0))
            }
            else {
                $left = 1.0 - (1.0 - $at) / $fade
                $blip.Opacity = $left
                Start-RingKeys $blip $P.Opacity $round @(@(0.0, $left, $true), @(($at + $fade - 1.0), 0.0), @($at, 1.0, $true), @(1.0, $left))
            }
        }
    }
    # eine Scheibe aus Milchglas um den Knopf, über die langsam Lichtreflexe gleiten
    'Glas'      = {
        $grad = Get-RingBrush 'RingGrad'; $white = [Windows.Media.Brushes]::White
        $band = Add-RingCircle -R 113 -W 16 -Brush $grad -Opacity 0.2
        Start-RingBreathe $band 0.14 0.26 2400
        [void](Add-RingCircle -R 113 -W 16 -Brush $white -Opacity 0.07)
        [void](Add-RingCircle -R 104.5 -W 1 -Brush $white -Opacity 0.45)
        [void](Add-RingCircle -R 121.5 -W 1 -Brush $white -Opacity 0.3)
        $glint = New-RingGroup
        [void](Add-RingCircle -Parent $glint -R 113 -W 16 -Brush $white -Dash 26, 684 -Opacity 0.16)
        [void](Add-RingCircle -Parent $glint -R 113 -W 16 -Brush $white -Dash 70, 640 -Offset 22 -Opacity 0.2)
        [void](Add-RingCircle -Parent $glint -R 113 -W 16 -Brush $white -Dash 12, 698 -Offset -330 -Opacity 0.22)
        Start-RingSpin $glint 9 1
        [void](Add-RingCircle -R 136 -W 7 -Brush $grad -Opacity 0.12)
        [void](Add-RingCircle -R 139.5 -W 1 -Brush $white -Opacity 0.2)
        $far = Add-RingCircle -R 136 -W 7 -Brush $white -Dash 44, 810.5 -Opacity 0.28
        Start-RingSpin $far 14 -1
    }
    # Sägeblatt: schräge Klingen wirbeln um einen glühenden Ring, außen laufen Hiebe dagegen
    'Gaming'    = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'; $r3 = Get-RingBrush 'Ring3'
        $glow = Add-RingCircle -R 105 -W 8 -Brush $r1 -Blur 7 -Opacity 0.7
        Start-RingBreathe $glow 0.35 0.9 700
        [void](Add-RingCircle -R 105 -W 3 -Brush $grad)
        $blades = New-RingGroup
        for ($i = 0; $i -lt 6; $i++) {
            $start = $i * 60
            $points = (New-RingPoint 111 $start), (New-RingPoint 141 ($start + 13)), (New-RingPoint 124 ($start + 21)), (New-RingPoint 111 ($start + 40))
            [void](Add-RingPath -Parent $blades -Points $points -Fill $(if ($i % 2) { $r3 } else { $r1 }) -Opacity $(if ($i % 2) { 0.7 } else { 0.95 }))
        }
        Start-RingSpin $blades 3.4 1
        $slashes = Add-RingCircle -R 146 -W 2.5 -Brush (Get-RingBrush 'Ring2') -Dash 96, 209.78 -Opacity 0.8
        Start-RingSpin $slashes 5 -1
    }
    # Seifenblasen: weiche Kugeln in zwei Bahnen treiben gemächlich um einen breiten, blassen Ring
    'Pastell'   = {
        $grad = Get-RingBrush 'RingGrad'
        $brushes = (Get-RingBrush 'Ring1'), (Get-RingBrush 'Ring2'), (Get-RingBrush 'Ring3')
        Add-RingPulses 106 $grad 1.25
        [void](Add-RingCircle -R 106 -W 6 -Brush $grad -Opacity 0.4)
        $near = New-RingGroup
        $sizes = 8, 5, 6.5, 4.5, 7.5, 5.5, 6, 4.5
        for ($i = 0; $i -lt 8; $i++) {
            $point = New-RingPoint 124 ($i * 45 + 10)
            $bubble = Add-RingDot -Parent $near -X $point.X -Y $point.Y -Size $sizes[$i] -Brush $brushes[$i % 3]
            Start-RingBreathe $bubble 0.45 0.95 (1500 + 190 * $i) (260 * $i)
        }
        Start-RingSpin $near 26 1
        $far = New-RingGroup
        for ($i = 0; $i -lt 10; $i++) {
            $point = New-RingPoint 141 ($i * 36)
            $bubble = Add-RingDot -Parent $far -X $point.X -Y $point.Y -Size (2 + ($i % 3)) -Brush $brushes[($i + 1) % 3]
            Start-RingBreathe $bubble 0.25 0.7 (1300 + 160 * $i) (210 * $i)
        }
        Start-RingSpin $far 38 -1
    }
    # klar und hart: zwölf Balken wie eine Ladeanzeige, das Licht springt von Balken zu Balken
    'Kontrast'  = {
        $r1 = Get-RingBrush 'Ring1'
        [void](Add-RingCircle -R 104 -W 2.5 -Brush $r1)
        [void](Add-RingCircle -R 146 -W 1 -Brush $r1 -Opacity 0.5)
        # Balken zwischen zwei Radien an einer Stelle des Kreises, 7 breit
        $bar = { param($degrees) $in = 7 * 90 / ([Math]::PI * 114); $out = 7 * 90 / ([Math]::PI * 139)
            (New-RingPoint 114 ($degrees - $in)), (New-RingPoint 139 ($degrees - $out)), (New-RingPoint 139 ($degrees + $out)), (New-RingPoint 114 ($degrees + $in)) }
        for ($i = 0; $i -lt 12; $i++) { [void](Add-RingPath -Points (& $bar ($i * 30 - 90)) -Fill $r1 -Opacity 0.2) }
        $light = New-RingGroup
        $levels = 1, 0.7, 0.45, 0.25
        for ($i = 0; $i -lt 4; $i++) { [void](Add-RingPath -Parent $light -Points (& $bar (- $i * 30 - 90)) -Fill $r1 -Opacity $levels[$i]) }
        Start-RingSteps $light 1.2 12
    }
    # Herzmonitor im Kreis: auf einer ruhigen Linie zieht ein Lichtkopf seine Runde, wo er vorbeikommt, schlägt die
    # Linie wie ein Puls aus und verblasst dahinter als Schweif; der Schein hinter dem Knopf pocht im selben Takt
    'Herzmonitor' = {
        $grad = Get-RingBrush 'RingGrad'; $r1 = Get-RingBrush 'Ring1'
        $round = 2.4                # Sekunden je Runde; drei Schläge je Runde, also 75 in der Minute
        $base = 118
        # Schein hinter dem Knopf: pocht zweimal kurz ("ba-bumm"), wenn der Kopf über die große Zacke läuft
        $glowBrush = New-Object Windows.Media.RadialGradientBrush
        $glowBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(120, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 0.62))
        $glowBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 1))
        $glow = Add-RingDot -X 150 -Y 150 -Size 146 -Brush $glowBrush -Opacity 0.35
        Start-RingKeys $glow $P.Opacity ($round / 3) @(@(0.0, 0.35), @(0.29, 0.35), @(0.34, 0.9), @(0.41, 0.45), @(0.48, 0.7), @(0.64, 0.35), @(1.0, 0.35))
        [void](Add-RingCircle -R $base -W 1.5 -Brush $grad -Opacity 0.22)
        # ein Herzschlag: Anteil des Schlags und Ausschlag nach außen (kleine Vorwelle, Zacke, Nachwelle)
        $beat = @(0.0, 0.0), @(0.14, 0.0), @(0.18, 2.5), @(0.22, 0.0), @(0.3, 0.0), @(0.315, -2.0), @(0.34, 18.0), @(0.365, -8.0), @(0.385, 0.0), @(0.5, 0.0), @(0.57, 4.0), @(0.64, 0.0), @(1.0, 0.0)
        $points = @(for ($i = 0; $i -le 720; $i++) {
                $t = (($i / 720.0) * 3.0) % 1.0
                $shift = 0.0
                for ($k = 1; $k -lt $beat.Count; $k++) {
                    if ($t -le $beat[$k][0]) { $shift = $beat[$k - 1][1] + ($beat[$k][1] - $beat[$k - 1][1]) * ($t - $beat[$k - 1][0]) / ($beat[$k][0] - $beat[$k - 1][0]); break }
                }
                New-RingPoint ($base + $shift) ($i / 2.0 - 90)
            })
        # Schweif: die Linie in Stücken, jedes leuchtet auf, wenn der Kopf ankommt, und verblasst dann
        $pieces = 48; $span = 720 / $pieces; $fade = 0.3
        for ($i = 0; $i -lt $pieces; $i++) {
            $piece = Add-RingPath -Points $points[($i * $span)..(($i + 1) * $span)] -Open -Stroke $r1 -W 2.2 -Round
            $start = $i / $pieces
            if ($start + $fade -le 1.0) {
                $frames = @(@($start, 1.0, $true), @(($start + $fade), 0.0), @(1.0, 0.0))
                if ($i -gt 0) { $frames = @(, @(0.0, 0.0, $true)) + $frames }
                $piece.Opacity = if ($i -eq 0) { 1 } else { 0 }
            }
            else {
                $left = 1.0 - (1.0 - $start) / $fade     # so hell ist das Stück noch, wenn die Runde neu beginnt
                $frames = @(@(0.0, $left, $true), @(($start + $fade - 1.0), 0.0), @($start, 1.0, $true), @(1.0, $left))
                $piece.Opacity = $left
            }
            Start-RingKeys $piece $P.Opacity $round $frames
        }
        # Lichtkopf: dreht mit und folgt den Ausschlägen nach außen und innen
        $head = New-RingGroup -Angle -90
        $haloBrush = New-Object Windows.Media.RadialGradientBrush
        $haloBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(170, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 0))
        $haloBrush.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0, $r1.Color.R, $r1.Color.G, $r1.Color.B)), 1))
        $slide = New-Object Windows.Media.TranslateTransform
        foreach ($dot in (Add-RingDot -Parent $head -X (150 + $base) -Y 150 -Size 10 -Brush $haloBrush), (Add-RingDot -Parent $head -X (150 + $base) -Y 150 -Size 3.2 -Brush ([Windows.Media.Brushes]::White))) {
            $dot.RenderTransform = $slide
        }
        $slides = @(for ($b = 0; $b -lt 3; $b++) { foreach ($step in $beat) { , @((($b + $step[0]) / 3.0), [double]$step[1]) } })
        Start-RingKeys $slide $P.X $round $slides
        Start-RingSpin $head $round 1
    }
}

# Die Stile zur Auswahl: die zehn allgemeinen und der des gewählten Skins - die der anderen Skins gehören zu ihnen
function Get-RingNames {
    $own = "$($script:Skin.Ring)"
    if ($own -and $script:RingBuilders.ContainsKey($own)) { @($script:RingNames) + $own } else { @($script:RingNames) }
}

# --- Zeigen, anhalten, wechseln -----------------------------------------------

# Eine selbst angelegte Uhr läuft weiter, auch wenn ihre Eigenschaft sie nicht mehr nutzt - sie muss
# ausdrücklich aus dem Zeittakt genommen werden, sonst sammeln sich mit jedem Neuaufbau Uhren an
function Remove-RingClock($Entry) {
    if ($Entry.Clock) { try { $Entry.Clock.Controller.Remove() } catch { } }
}

function Clear-RingStyle {
    foreach ($entry in $script:RingAnims) {
        $entry.Target.BeginAnimation($entry.Property, $null)
        Remove-RingClock $entry
    }
    $script:RingAnims.Clear()
    $ui.RingLayer.Children.Clear()
    $script:RingRunning = $false
}

# Baut den gewählten Stil neu auf; mit -Still ohne Bewegung
function Show-RingStyle([switch]$Still) {
    Clear-RingStyle
    $name = "$($script:Settings.Ring)"
    if (-not $script:RingBuilders.ContainsKey($name)) { $name = 'Klassik' }
    $script:RingStill = $Still.IsPresent
    try { & $script:RingBuilders[$name] }
    finally { $script:RingStill = $false }
    $script:RingRunning = -not $Still
}

# Hält alle Bewegungen an der Stelle an, an der sie gerade stehen
function Suspend-RingStyle {
    foreach ($entry in $script:RingAnims) {
        $value = $entry.Target.GetValue($entry.Property)
        $entry.Target.BeginAnimation($entry.Property, $null)
        Remove-RingClock $entry
        $entry.Target.SetValue($entry.Property, $value)
    }
    $script:RingAnims.Clear()
    $script:RingRunning = $false
}

function Set-RingStyle([string]$Name) {
    if ((Get-RingNames) -notcontains $Name) { return }
    $script:Settings.Ring = $Name
    Show-RingStyle -Still:(-not $script:Settings.Animations)
}
