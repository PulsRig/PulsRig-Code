using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Path = System.Windows.Shapes.Path;

namespace PulsRig.App;

// Scan als Ereignis wie im Entwurf: Fortschrittsring außen, zwei ruhige Lichtwellen aus dem Knopf, am Ende Lichtstoß
// mit Funken und die Treiber-Kachel leuchtet rosa. Die Kacheln bleiben während des Scans ruhig. Der Ring folgt dem
// Fortschritt Bild für Bild (CompositionTarget.Rendering) und kriecht zwischen zwei Meldungen langsam weiter, damit er
// weder steht noch springt. Leuchteffekte (DropShadowEffect) nur auf stehenden Teilen: auf bewegten kosten sie jedes Bild.
// Ohne -Demo läuft dabei der echte Scan (Treiberscan): Ring und Prozentzahl folgen seinem Fortschritt, das Ende kommt
// mit dem Ergebnis. -Demo spielt den Ablauf des Entwurfs in 8 Sekunden.
public partial class HomePage
{
    static readonly TimeSpan ScanTime = TimeSpan.FromSeconds(8);
    static readonly string[] Vendors = { "Chipsatz", "NVIDIA", "Realtek", "Intel", "AMD", "Windows-Update" };

    DispatcherTimer? scanClock;
    DateTime scanStart;
    bool scanning;
    Path? scanArc;
    double scanUnit;
    double shown;

    void Scan_Click(object sender, RoutedEventArgs e)
    {
        // der echte Scan lässt sich nicht abbrechen; ein zweiter Klick zeigt, was er bisher gefunden hat
        if (!demo && scanning) { main.Go("drivers"); return; }
        if (scanning) StopScanFx(); else StartScanFx();
    }

    void Drv_Click(object sender, System.Windows.Input.MouseButtonEventArgs e) => main.Go("drivers");

    void StartScanFx()
    {
        if (!demo) Treiberscan.Start();
        scanning = true;
        ScanFx.Children.Clear();
        ResetResult();
        Fade(scanBase, 1);
        HomeKicker.Text = "Scan läuft";
        HomeHead.Text = "Ich schaue nach …";

        // Fortschrittsring: Kreis r = 108 ab 12 Uhr, Strich so lang wie der Kreis, der Versatz läuft von voll auf 0
        var unit = 2 * Math.PI * 108 / 3;
        var arc = new Path
        {
            Data = Circle(120, 120, 108), Stroke = (Brush)FindResource("Puls"), StrokeThickness = 3,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            StrokeDashArray = new DoubleCollection { unit, unit }, StrokeDashOffset = unit,
        };
        ScanFx.Children.Add(arc);
        scanArc = arc;
        scanUnit = unit;
        shown = demo ? 0 : Treiberscan.Percent / 100;
        arc.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(500)));
        CompositionTarget.Rendering += MoveRing;

        // zwei Lichtwellen in ruhiger Dauerschleife (3 s, versetzt um 1,5 s, die zweite rosa)
        for (var i = 0; i < 2; i++)
            ScanFx.Children.Add(Wave(152, 1.5, i == 1 ? "#C0608F" : "#8C6BD6", TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(1.5 * i), true));

        scanStart = DateTime.Now;
        ScanLabel.Text = "0%";
        ScanSub.Text = "Prüft " + Vendors[0];
        scanClock = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        scanClock.Tick += (_, _) =>
        {
            if (!demo) { ScanProgress(); return; }
            var p = Math.Min(1, (DateTime.Now - scanStart) / ScanTime);
            ScanSub.Text = "Prüft " + Vendors[Math.Min(5, (int)(p * 6))];
            if (p >= 1) CompleteScanFx();
        };
        scanClock.Start();
        if (!demo) ScanProgress();
    }

    // echter Scan: Ring gleitet zum Fortschritt, unter dem Knopf laufen die Namen der Geräte durch
    void ScanProgress()
    {
        if (!Treiberscan.Running) { CompleteScanFx(); return; }
        var p = Treiberscan.Percent / 100;
        var names = Treiberscan.Names;
        ScanSub.Text = p < 0.16 || names.Count == 0 ? "Liest die Geräte"
            : p < 0.58 ? "Prüft " + Hw.Short(names[(int)((DateTime.Now - scanStart).TotalSeconds * 1.2) % names.Count])
            : p < 0.66 ? "Fragt NVIDIA und AMD" : p < 0.93 ? "Durchsucht den Katalog" : "Fasst zusammen";
    }

    // je Bild: der Ring gleitet zum gemeldeten Fortschritt und kriecht danach langsam weiter (höchstens 6 Punkte
    // voraus, nie über 99 %); die Prozentzahl zeigt, was der Ring zeigt
    void MoveRing(object? sender, EventArgs e)
    {
        if (scanArc == null) return;
        var target = demo ? Math.Min(1, (DateTime.Now - scanStart) / ScanTime) : Treiberscan.Percent / 100;
        if (shown < target) shown += Math.Max((target - shown) * 0.06, 0.0004);
        else if (!demo && shown < Math.Min(target + 0.06, 0.99)) shown += 0.00012;
        shown = Math.Min(shown, demo ? target : 0.995);
        scanArc.StrokeDashOffset = scanUnit * (1 - shown);
        var label = Math.Round(shown * 100) + "%";
        if (ScanLabel.Text != label) ScanLabel.Text = label;
    }

    // zweiter Klick während des Scans bricht ab
    void StopScanFx()
    {
        scanning = false;
        scanClock?.Stop();
        CompositionTarget.Rendering -= MoveRing;
        ScanFx.Children.Clear();
        Fade(scanBase, 0);
        ScanLabel.Text = "SCAN";
        ScanSub.Text = demo ? "letzter: vor 2 Tagen" : "Treiber und System prüfen";
        SetGreeting();
    }

    void CompleteScanFx()
    {
        scanning = false;
        scanClock?.Stop();
        CompositionTarget.Rendering -= MoveRing;
        // Wellen und Fortschritt weg, der volle Ring bleibt stehen
        ScanFx.Children.Clear();
        ScanFx.Children.Add(new Path { Data = Circle(120, 120, 108), Stroke = (Brush)FindResource("Puls"), StrokeThickness = 3,
            Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 0, Color = Hex("#A8326F") } });
        Burst();
        ScanLabel.Text = "SCAN";
        ScanSub.Text = "Erneut prüfen";
        HomeKicker.Text = "Scan fertig · gerade eben";
        if (demo)
        {
            HomeHead.Text = "Vier Treiber sind neuer.";
            DrvValue.Text = "4 neu";
            DrvSub.Text = "NVIDIA · Realtek · Intel · AMD";
        }
        else
        {
            FillScanResult();
            if (Treiberscan.Last is { } s)
                HomeHead.Text = s.Newer == 0 && s.Problems.Count == 0 ? "Alle Treiber sind aktuell." : s.Newer == 1 ? "Ein Treiber ist neuer." : s.Newer > 1 ? s.Newer + " Treiber sind neuer."
                    : s.Problems.Count == 1 ? "Ein Gerät meldet einen Fehler." : s.Problems.Count + " Geräte melden Fehler.";
            else HomeHead.Text = "Der Scan ist gescheitert.";
            // nichts gefunden: die Treiber-Kachel bleibt ruhig
            if (Treiberscan.Last is { Newer: 0 } calm && calm.Problems.Count == 0) return;
        }

        // Treiber-Kachel: federt kurz (.b-pop) und behält den rosa Rand mit Schein (.s-res)
        Lift(DrvTile, -4, TimeSpan.FromMilliseconds(800), TimeSpan.Zero, 0.3);
        var grow = Keys(TimeSpan.FromMilliseconds(800), (0, 1), (.3, 1.03), (1, 1));
        Own(DrvTile).Children.OfType<ScaleTransform>().First().BeginAnimation(ScaleTransform.ScaleXProperty, grow);
        Own(DrvTile).Children.OfType<ScaleTransform>().First().BeginAnimation(ScaleTransform.ScaleYProperty, grow);
        // nur der Rand färbt sich: ein Schein (DropShadowEffect) würde die Schrift der Kachel weich zeichnen
        Edge(DrvTile).BeginAnimation(SolidColorBrush.ColorProperty, new ColorAnimation(Hex("#99C0608F"), TimeSpan.FromMilliseconds(400)));
    }

    // vor einem neuen Scan: Treiber-Kachel wieder wie vorher
    void ResetResult()
    {
        Edge(DrvTile).BeginAnimation(SolidColorBrush.ColorProperty, null);
    }

    // Lichtstoß am Ende: Aufblitzen, zwei Wellen und 14 Funken (.b-flash, .b-wave, .b-spark)
    void Burst()
    {
        var glow = new RadialGradientBrush();
        glow.GradientStops.Add(new GradientStop(Hex("#55C0608F"), 0));
        glow.GradientStops.Add(new GradientStop(Hex("#226D43C9"), 0.35));
        glow.GradientStops.Add(new GradientStop(Hex("#006D43C9"), 0.65));
        var flash = new Ellipse { Width = 320, Height = 320, Opacity = 0, Fill = glow };
        Canvas.SetLeft(flash, -40);
        Canvas.SetTop(flash, -40);
        ScanFx.Children.Insert(0, flash);
        flash.BeginAnimation(OpacityProperty, Keys(TimeSpan.FromSeconds(1.6), (0, 0), (.12, 1), (1, 0)));

        ScanFx.Children.Add(Wave(150, 2, "#8C6BD6", TimeSpan.FromSeconds(1.5), TimeSpan.Zero, false));
        ScanFx.Children.Add(Wave(150, 2, "#C0608F", TimeSpan.FromSeconds(1.5), TimeSpan.FromSeconds(0.25), false));

        var spark = new LinearGradientBrush(Colors.White, Hex("#C0608F"), 90);
        for (var i = 0; i < 14; i++)
        {
            var line = new Rectangle { Width = 2, Height = 20, RadiusX = 1, RadiusY = 1, Fill = spark, Opacity = 0,
                RenderTransformOrigin = new Point(0.5, 0.5) };
            Canvas.SetLeft(line, 119);
            Canvas.SetTop(line, 110);
            // wie CSS rotate() translateY() scaleY(): erst strecken, dann hinausschieben, dann drehen
            var stretch = new ScaleTransform(1, 0.2);
            var move = new TranslateTransform(0, -72);
            var t = new TransformGroup();
            t.Children.Add(stretch);
            t.Children.Add(move);
            t.Children.Add(new RotateTransform(i * 360.0 / 14 + 8));
            line.RenderTransform = t;
            var begin = TimeSpan.FromSeconds(0.05 + i % 3 * 0.08);
            var time = TimeSpan.FromSeconds(1.1);
            move.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-72, -160, time) { BeginTime = begin, EasingFunction = new WaveEase() });
            stretch.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.2, 1, time) { BeginTime = begin, EasingFunction = new WaveEase() });
            var fade = Keys(time, (0, 0), (.25, 1), (1, 0));
            fade.BeginTime = begin;
            line.BeginAnimation(OpacityProperty, fade);
            ScanFx.Children.Add(line);
        }
    }

    // Welle aus dem Knopf: wächst von 75 % auf 240 % und verblasst; die Verzögerung gilt nur beim ersten Mal
    static Ellipse Wave(double size, double width, string color, TimeSpan time, TimeSpan delay, bool forever)
    {
        var scale = new ScaleTransform(0.75, 0.75);
        var wave = new Ellipse { Width = size, Height = size, Stroke = new SolidColorBrush(Hex(color)), StrokeThickness = width, Opacity = 0,
            RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = scale };
        Canvas.SetLeft(wave, 120 - size / 2);
        Canvas.SetTop(wave, 120 - size / 2);
        var repeat = forever ? RepeatBehavior.Forever : new RepeatBehavior(1);
        var grow = new DoubleAnimation(0.75, 2.4, time) { EasingFunction = new WaveEase(), RepeatBehavior = repeat };
        var fade = new DoubleAnimation(0.7, 0, time) { EasingFunction = new WaveEase(), RepeatBehavior = repeat };
        var start = new DispatcherTimer { Interval = delay > TimeSpan.Zero ? delay : TimeSpan.FromMilliseconds(1) };
        start.Tick += (_, _) =>
        {
            start.Stop();
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
            wave.BeginAnimation(OpacityProperty, fade);
        };
        start.Start();
        return wave;
    }

    static void Lift(Border tile, double by, TimeSpan time, TimeSpan delay, double peak)
    {
        var a = Keys(time, (0, 0), (peak, by), (1, 0));
        a.BeginTime = delay;
        Move(tile).BeginAnimation(TranslateTransform.YProperty, a);
    }

    // Der Kachel-Stil setzt Skalierung und Verschiebung; Werte aus Stilen sind eingefroren, daher je Kachel eine
    // eigene Kopie, an der die Animationen hängen (das Anheben beim Überfahren greift auf dieselbe Kopie)
    static TransformGroup Own(Border tile)
    {
        if (tile.RenderTransform is TransformGroup { IsFrozen: false } own) return own;
        var copy = tile.RenderTransform is TransformGroup g ? g.Clone() : new TransformGroup { Children = { new ScaleTransform(), new TranslateTransform() } };
        tile.RenderTransform = copy;
        return copy;
    }

    static TranslateTransform Move(Border tile) => Own(tile).Children.OfType<TranslateTransform>().First();

    // eigener, nicht eingefrorener Pinsel für den Rand, damit er sich einfärben lässt
    static SolidColorBrush Edge(Border tile)
    {
        if (tile.BorderBrush is SolidColorBrush { IsFrozen: false } own) return own;
        var copy = new SolidColorBrush((tile.BorderBrush as SolidColorBrush)?.Color ?? Hex("#22172F"));
        tile.BorderBrush = copy;
        return copy;
    }

    static DoubleAnimationUsingKeyFrames Keys(TimeSpan time, params (double At, double Value)[] keys)
    {
        var a = new DoubleAnimationUsingKeyFrames { Duration = time };
        foreach (var (at, value) in keys)
            a.KeyFrames.Add(new EasingDoubleKeyFrame(value, KeyTime.FromPercent(at), new QuadraticEase { EasingMode = EasingMode.EaseOut }));
        return a;
    }

    static void Fade(UIElement element, double to) =>
        element.BeginAnimation(OpacityProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(400)));

    // zwei Halbbögen ab 12 Uhr im Uhrzeigersinn, damit der Strich oben beginnt
    static Geometry Circle(double cx, double cy, double r)
    {
        var figure = new PathFigure { StartPoint = new Point(cx, cy - r) };
        figure.Segments.Add(new ArcSegment(new Point(cx, cy + r), new Size(r, r), 0, false, SweepDirection.Clockwise, true));
        figure.Segments.Add(new ArcSegment(new Point(cx, cy - r), new Size(r, r), 0, false, SweepDirection.Clockwise, true));
        var g = new PathGeometry(new[] { figure });
        g.Freeze();
        return g;
    }
}
