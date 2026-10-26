using System.IO;
using Path = System.Windows.Shapes.Path;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using PulsRig.Core;

namespace PulsRig.App;

// Startseite als Kachelmosaik. Echt sind Grafikkarte (nvidia-smi über PulsRig.Core.Messung), Laufwerke, Treiber und
// "Was sich geändert hat" (beide aus dem letzten Scan); die übrigen Kacheln folgen mit ihren Blöcken. -Demo zeigt den Entwurf.
public partial class HomePage : UserControl, IPage
{
    readonly MainWindow main;
    readonly bool demo;
    readonly List<double> gpuHistory = new();
    readonly Livelinie gpuLine = new("#6D43C9", "#8C6BD6") { Low = 40, High = 60, Window = 40 };
    long demoTick;
    CancellationTokenSource? live;
    bool watching;
    bool boost;
    Ellipse scanBase = null!;
    // Schläge je Minute: der Ring trägt drei Zacken, eine Runde dauert drei Schläge
    const int Beat = 60;
    static readonly TimeSpan BeatTime = TimeSpan.FromSeconds(60.0 / Beat);

    public HomePage(MainWindow main, bool demo)
    {
        this.main = main;
        this.demo = demo;
        InitializeComponent();
        Tint(GpuTile, "#160D29", "#2E6D43C9");
        Tint(GameTile, "#1F0A19", "#2EA8326F");
        Tint(StabTile, "#10291F", "#2E5EE0A0");
        Tint(DrivesTile, "#160D29", "#2E8C6BD6");
        Tint(ChangesTile, "#130B24", "#2E5E4BB8");
        Tint(DrvTile, "#1B0916", "#2EA8326F");
        BuildRing();
        GpuChart.Children.Add(gpuLine);
        ((Storyboard)FindResource("Blinken")).Begin(GpuLiveDot, true);
        SetBoost(!demo && Spielboost.IsOn);
        Fill();
        Loaded += (_, _) => StartLive();
        Unloaded += (_, _) => Stop();
        Loaded += (_, _) => Probezeitlauf.Changed += FillScanResult;
        Unloaded += (_, _) => Probezeitlauf.Changed -= FillScanResult;
    }

    // Kachelgrund wie linear-gradient(160deg, Farbton, #09060D 75%)
    static void Tint(Border tile, string tint, string border)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0.33, 0), EndPoint = new Point(0.67, 1) };
        brush.GradientStops.Add(new GradientStop(Hex(tint), 0));
        brush.GradientStops.Add(new GradientStop(Hex("#09060D"), 0.75));
        tile.Background = brush;
        tile.BorderBrush = new SolidColorBrush(Hex(border));
    }

    static Color Hex(string s) => (Color)ColorConverter.ConvertFromString(s);

    void SetGreeting()
    {
        HomeKicker.Text = "Guten " + (DateTime.Now.Hour < 11 ? "Morgen" : DateTime.Now.Hour < 18 ? "Tag" : "Abend");
        HomeHead.Text = demo ? "Dein PC ist in Form." : "Bereit für den Scan.";
    }

    void Fill()
    {
        SetGreeting();
        // ruhiger Puls, der zum Ring passt: ein Schlag je Sekunde, auch während des Scans
        PulseValue.Text = Beat.ToString();
        ScanSub.Text = demo ? "letzter: vor 2 Tagen" : "Treiber und System prüfen";
        SetGameScore(demo ? 92 : Werkzeugpruefung.GameScore);
        // Gaming-Check im Hintergrund, wenn noch keiner lief (fragt WMI und nvidia-smi, dauert ein, zwei Sekunden)
        if (!demo && Werkzeugpruefung.GameScore == null)
            Task.Run(() => { try { Werkzeugpruefung.Check("GamingCheck"); } catch (Exception) { } })
                .ContinueWith(_ => SetGameScore(Werkzeugpruefung.GameScore), TaskScheduler.FromCurrentSynchronizationContext());
        StabDays.Text = demo ? "19" : "–";
        for (var i = 0; i < 30; i++)
            StabGrid.Children.Add(new Rectangle { Height = 9, Margin = new Thickness(1.5), RadiusX = 2, RadiusY = 2,
                Fill = new SolidColorBrush(demo && i == 11 ? Hex("#F2B661") : Hex("#555EE0A0")) });
        ToolHead.Text = "Speicherplatz freigeben";
        ToolSub.Text = demo ? "9,6 GB Shader-Cache möglich" : "Temporäre Dateien und Caches";
        FillScanResult();
        FillDrives();
        if (demo) for (var i = 0; i < 40; i++) gpuHistory.Add(46 + Math.Sin(i / 4.0) * 2);
        DrawGpu();
        // läuft der Scan noch (Seite gewechselt und zurück), geht der Ablauf weiter
        if (!demo && Treiberscan.Running) Loaded += (_, _) => { if (!scanning) StartScanFx(); };
    }

    // Treiber-Kachel und "Was sich geändert hat" aus dem letzten Scan; die Änderungen sind die zuletzt
    // installierten Treiber von Drittherstellern (der Livelinie mit Tagesbildern kommt mit den Werkzeugen)
    void FillScanResult()
    {
        var s = demo ? null : Treiberscan.Last;
        DrvValue.Text = demo ? "3" : s == null ? "–" : s.Newer > 0 ? s.Newer + " neu" : s.Problems.Count > 0 ? s.Problems.Count + " Fehler" : "aktuell";
        DrvSub.Text = demo ? "Updates bereit" : s == null ? "noch kein Scan"
            : s.Newer > 0 ? string.Join(" · ", new[] { s.Nvidia, s.Radeon, s.Amd }.Where(v => v is { IsNewer: true }).Select(v => v!.Source).Concat(s.Updates.Select(u => u.Name.Split(" – ")[0])).Distinct().Take(4))
            : s.Problems.Count > 0 ? Hw.Short(s.Problems[0].Name) : s.Devices + " geprüft";
        // Zahlen groß, Wörter wie „aktuell“ kleiner und mit Haken, damit die Kachel ruhig bleibt
        var word = !char.IsDigit(DrvValue.Text.FirstOrDefault()) && DrvValue.Text != "–";
        DrvValue.FontSize = word ? 18 : 28;
        if (word && s is { Newer: 0 } && s.Problems.Count == 0) DrvValue.Text = "✓ aktuell";
        DrvValue.Foreground = word && s is { Newer: 0 } && s.Problems.Count == 0 ? (Brush)FindResource("Gruen") : (Brush)FindResource("Text");
        if (!demo && s != null) ScanSub.Text = "letzter: " + Ago(s.When);
        ChangesList.Children.Clear();
        var changes = demo
            ? new[] { ("09:14", "NVIDIA-Treiber neu", true), ("gestern", "Windows-Update", false), ("15.10.", "Discord im Autostart", false) }
            : s == null ? new[] { ("–", "zeigt der erste Scan", false) }
            : s.Drivers.Where(d => d.ThirdParty && d.When != null).OrderByDescending(d => d.When).Take(3)
                .Select(d => (Day(d.When!.Value), Hw.Short(d.Name) + " · " + (d.Provider.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) && d.Class.Equals("Display", StringComparison.OrdinalIgnoreCase) ? Hersteller.NvidiaVersion(d.Version) ?? d.Version : d.Version),DateTime.Now - d.When!.Value < TimeSpan.FromDays(2))).ToArray();
        // Probezeit: ein neuer Treiber, seit dem es öfter abstürzt, steht ganz oben (Klick: Abstürze, × blendet ihn aus)
        if (!demo && Probezeitlauf.Warning() is { } warn)
        {
            var row = new DockPanel { Margin = new Thickness(0, 0, 0, 8), Background = Brushes.Transparent, ToolTip = Probezeit.Text(warn) + " Die vorige Fassung zurückholen?" };
            var hide = new TextBlock { Text = "×", FontSize = 14, Foreground = (Brush)FindResource("Leise"), Padding = new Thickness(6, 0, 0, 0), ToolTip = "Ausblenden" };
            hide.MouseLeftButtonUp += (_, e) => { e.Handled = true; Probezeitlauf.Hide(warn); FillScanResult(); };
            DockPanel.SetDock(hide, Dock.Right);
            row.Children.Add(hide);
            var sign = new TextBlock { Text = "⚠", FontSize = 12.5, Foreground = new SolidColorBrush(Hex("#F6C989")), Margin = new Thickness(0, 0, 6, 0) };
            DockPanel.SetDock(sign, Dock.Left);
            row.Children.Add(sign);
            row.Children.Add(new TextBlock { Text = Probezeit.WarnTitle(warn), FontSize = 12.5, Foreground = new SolidColorBrush(Hex("#F6C989")), TextWrapping = TextWrapping.Wrap });
            row.MouseLeftButtonUp += (_, e) => { e.Handled = true; main.Go("crash"); };
            ChangesList.Children.Add(row);
        }
        // Zeitleiste: Punkt an einer feinen Linie, Name hell, Fassung leise, Tag als Plakette rechts
        for (var i = 0; i < changes.Length; i++)
        {
            var (when, what, fresh) = changes[i];
            var row = new Grid { Margin = new Thickness(0, 0, 0, 2), MinHeight = 26 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            if (i < changes.Length - 1)
                row.Children.Add(new Rectangle { Width = 1, Fill = new SolidColorBrush(Hex("#2A2245")), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(3.5, 14, 0, -2) });
            row.Children.Add(new Ellipse { Width = 8, Height = 8, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 5, 0, 0),
                Fill = fresh ? (Brush)FindResource("Indigo") : new SolidColorBrush(Hex("#3A3160")) });
            var parts = what.Split(" · ", 2);
            var text = new TextBlock { FontSize = 12.5, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Top };
            text.Inlines.Add(new Run(parts[0]) { Foreground = (Brush)FindResource("Text") });
            if (parts.Length > 1) text.Inlines.Add(new Run("  " + parts[1]) { Foreground = (Brush)FindResource("Leise"), FontSize = 11.5 });
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            var day = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(8, 1, 8, 2), Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Top,
                Background = new SolidColorBrush(Hex(fresh ? "#2A5E4BB8" : "#0CFFFFFF")),
                Child = new TextBlock { Text = when, FontFamily = (FontFamily)FindResource("Mono"), FontSize = 10.5,
                    Foreground = fresh ? (Brush)FindResource("Indigo") : (Brush)FindResource("Leise") } };
            Grid.SetColumn(day, 2);
            row.Children.Add(day);
            ChangesList.Children.Add(row);
        }
    }

    static string Day(DateTime when) => when.Date == DateTime.Today ? "heute" : when.Date == DateTime.Today.AddDays(-1) ? "gestern" : when.ToString("dd.MM.");

    static string Ago(DateTime when)
    {
        var span = DateTime.Now - when;
        return span.TotalMinutes < 2 ? "gerade eben" : span.TotalHours < 1 ? "vor " + (int)span.TotalMinutes + " Min." : when.Date == DateTime.Today ? "heute " + when.ToString("HH:mm")
            : span.TotalDays < 2 ? "gestern" : "vor " + (int)span.TotalDays + " Tagen";
    }

    void FillDrives()
    {
        var drives = demo
            ? new List<(string, double, double)> { ("C", 0.71, 290e9), ("D", 0.38, 1.2e12), ("E", 0.91, 90e9) }
            : DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Fixed && d.IsReady && d.TotalSize > 0)
                .Select(d => (d.Name[..1], 1 - (double)d.TotalFreeSpace / d.TotalSize, (double)d.TotalFreeSpace)).Take(3).ToList();
        var full = drives.Where(d => d.Item2 >= 0.9).Select(d => d.Item1).FirstOrDefault();
        DrivesHint.Text = full != null ? full + ": ansehen" : "";
        // je Laufwerk eine Zeile, die Zeilen teilen sich die Höhe der Kachel: Buchstabe als Plakette, daneben frei und
        // Prozent, darunter ein Balken im Lila-Beere-Verlauf des Designs; fast voll (ab 90 %) wird er rosa
        foreach (var (letter, used, free) in drives)
        {
            var tone = used >= 0.9 ? "#E0708F" : "#8C6BD6";
            var row = new Grid { VerticalAlignment = VerticalAlignment.Center };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            var badge = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(9), VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Hex("#1A" + tone.TrimStart('#'))), BorderBrush = new SolidColorBrush(Hex("#40" + tone.TrimStart('#'))), BorderThickness = new Thickness(1),
                Child = new TextBlock { Text = letter, FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Hex(used >= 0.9 ? tone : "#B19FE0")),
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            var head = new DockPanel();
            var pct = new TextBlock { Text = Math.Round(used * 100) + " %", FontSize = 12, FontFamily = (FontFamily)FindResource("Mono"), Foreground = (Brush)FindResource("Text") };
            DockPanel.SetDock(pct, Dock.Right);
            head.Children.Add(pct);
            head.Children.Add(new TextBlock { Text = Ui.Size(free) + " frei", FontSize = 12, Foreground = (Brush)FindResource("Halbleise") });
            info.Children.Add(head);
            var track = new Border { Height = 7, CornerRadius = new CornerRadius(3.5), Background = new SolidColorBrush(Hex("#12FFFFFF")), Margin = new Thickness(0, 6, 0, 0) };
            var fill = used >= 0.9 ? new LinearGradientBrush(Hex("#A8326F"), Hex(tone), 0) : (Brush)FindResource("PulsQuer");
            var bar = new Border { Height = 7, CornerRadius = new CornerRadius(3.5), HorizontalAlignment = HorizontalAlignment.Left, Background = fill };
            track.Child = bar;
            track.SizeChanged += (_, e) => bar.Width = e.NewSize.Width * used;
            info.Children.Add(track);
            Grid.SetColumn(info, 1);
            row.Children.Add(badge);
            row.Children.Add(info);
            DrivesList.Children.Add(row);
        }
    }

    void SetGameScore(int? score)
    {
        GameValue.Text = score?.ToString() ?? "–";
        var part = (score ?? 0) / 100.0;
        if (part <= 0) { GameArc.Data = null; return; }
        // Bogen ab 12 Uhr im Uhrzeigersinn, Radius 31 um (38, 38)
        var angle = Math.Min(part, 0.9999) * 2 * Math.PI;
        var end = new Point(38 + 31 * Math.Sin(angle), 38 - 31 * Math.Cos(angle));
        var figure = new PathFigure { StartPoint = new Point(38, 7) };
        figure.Segments.Add(new ArcSegment(end, new Size(31, 31), 0, angle > Math.PI, SweepDirection.Clockwise, true));
        GameArc.Data = new PathGeometry(new[] { figure });
    }

    // Herzmonitor-Ring: EKG-Zacke dreimal auf dem Kreis, vier Spuren laufen mit verschiedener Länge im Kreis (.p-t1 bis .p-t4)
    void BuildRing()
    {
        var k = new (double T, double V)[] { (0, 0), (.14, 0), (.18, 2.5), (.22, 0), (.3, 0), (.315, -2), (.34, 18), (.365, -8), (.385, 0), (.5, 0), (.57, 4), (.64, 0), (1, 0) };
        double F(double t)
        {
            for (var i = 1; i < k.Length; i++)
                if (t <= k[i].T) return k[i - 1].V + (k[i].V - k[i - 1].V) * (t - k[i - 1].T) / (k[i].T - k[i - 1].T);
            return 0;
        }
        var points = new List<Point>();
        for (var i = 0; i <= 900; i++)
        {
            var u = i / 900.0;
            var r = 94 + F(u * 3 % 1) * 0.8;
            var w = -Math.PI / 2 + u * 2 * Math.PI;
            points.Add(new Point(120 + r * Math.Cos(w), 120 + r * Math.Sin(w)));
        }
        var length = 0.0;
        for (var i = 1; i < points.Count; i++) length += (points[i] - points[i - 1]).Length;
        var figure = new PathFigure { StartPoint = points[0] };
        figure.Segments.Add(new PolyLineSegment(points.Skip(1), true));
        var geometry = new PathGeometry(new[] { figure });
        geometry.Freeze();

        Ring.Children.Add(new Ellipse { Width = 188, Height = 188, Stroke = new SolidColorBrush(Hex("#1C1229")), StrokeThickness = 2, Margin = new Thickness(26) });
        scanBase = new Ellipse { Width = 216, Height = 216, Stroke = new SolidColorBrush(Hex("#1C1229")), StrokeThickness = 2, Margin = new Thickness(12), Opacity = 0 };
        Ring.Children.Add(scanBase);
        var pulse = (Brush)FindResource("Puls");
        var traces = new (double Dash, double From, Brush Brush, double Width, double Opacity, bool Glow)[]
        {
            (340, 340, pulse, 2, 0.2, false), (200, 200, pulse, 2, 0.4, false),
            (100, 100, new SolidColorBrush(Hex("#6D43C9")), 2.2, 0.75, false), (28, 28, new SolidColorBrush(Hex("#D9CFF0")), 2.8, 1, true),
        };
        foreach (var t in traces)
        {
            // pathLength=1000: Strichlängen auf die echte Länge umrechnen, WPF misst sie in Strichstärken
            var unit = length / 1000 / t.Width;
            var path = new Path { Data = geometry, Stroke = t.Brush, StrokeThickness = t.Width, Opacity = t.Opacity,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
                StrokeDashArray = new DoubleCollection { t.Dash * unit, (1000 - t.Dash) * unit } };
            // kein Leuchteffekt auf der laufenden Spur: er müsste jedes Bild neu gerechnet werden
            path.BeginAnimation(Shape.StrokeDashOffsetProperty,
                new DoubleAnimation(t.From * unit, (t.From - 1000) * unit, TimeSpan.FromTicks(BeatTime.Ticks * 3)) { RepeatBehavior = RepeatBehavior.Forever });
            Ring.Children.Add(path);
        }

        // Atmen hinter dem Knopf (.p-breathe): Herzschlag mit Doppelschlag im Takt des Pulses
        var opacity = new DoubleAnimationUsingKeyFrames { Duration = BeatTime, RepeatBehavior = RepeatBehavior.Forever };
        var scale = new DoubleAnimationUsingKeyFrames { Duration = BeatTime, RepeatBehavior = RepeatBehavior.Forever };
        foreach (var (at, o, s) in new[] { (0.0, .5, 1.0), (.29, .5, 1), (.34, .9, 1.05), (.41, .62, 1.01), (.48, .75, 1.03), (.64, .5, 1), (1, .5, 1) })
        {
            var time = KeyTime.FromTimeSpan(TimeSpan.FromTicks((long)(BeatTime.Ticks * at)));
            opacity.KeyFrames.Add(new EasingDoubleKeyFrame(o, time, new QuadraticEase { EasingMode = EasingMode.EaseOut }));
            scale.KeyFrames.Add(new EasingDoubleKeyFrame(s, time, new QuadraticEase { EasingMode = EasingMode.EaseOut }));
        }
        Breath.BeginAnimation(OpacityProperty, opacity);
        var st = (ScaleTransform)Breath.RenderTransform;
        st.BeginAnimation(ScaleTransform.ScaleXProperty, scale);
        st.BeginAnimation(ScaleTransform.ScaleYProperty, scale);

        ScanButton.MouseEnter += (_, _) => { Zoom(ScanButton, 1.04); Zoom(ScanShadow, 1.04); };
        ScanButton.MouseLeave += (_, _) => { Zoom(ScanButton, 1); Zoom(ScanShadow, 1); };
    }

    static void Zoom(FrameworkElement element, double to)
    {
        var s = (ScaleTransform)element.RenderTransform;
        var a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(250)) { EasingFunction = new QuadraticEase() };
        s.BeginAnimation(ScaleTransform.ScaleXProperty, a);
        s.BeginAnimation(ScaleTransform.ScaleYProperty, a);
    }

    // Grafikkarte live über die gemeinsame Messung (Live), die letzten 40 Werte als Verlauf
    void StartLive()
    {
        live = new CancellationTokenSource();
        var token = live.Token;
        if (demo)
        {
            var random = new Random();
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
            timer.Tick += (_, _) =>
            {
                if (token.IsCancellationRequested) { timer.Stop(); return; }
                var last = gpuHistory[^1];
                gpuHistory.RemoveAt(0);
                gpuHistory.Add(Math.Clamp(last + (random.NextDouble() * 2 - 1) * 1.4, 40, 60));
                DrawGpu();
            };
            timer.Start();
            return;
        }
        watching = true;
        Live.Updated += OnLive;
        Live.Use();
        OnLive();
    }

    void OnLive()
    {
        gpuHistory.Clear();
        gpuHistory.AddRange(Live.GpuTemp.TakeLast(40));
        DrawGpu();
    }

    // gibt die Messung frei (auch beim Schließen des Fensters, wo Unloaded nicht kommt); mehrfacher Aufruf schadet nicht
    public void Stop()
    {
        live?.Cancel();
        if (!watching) return;
        watching = false;
        Live.Updated -= OnLive;
        Live.Release();
    }

    void DrawGpu()
    {
        if (gpuHistory.Count == 0) { GpuValue.Text = "–"; return; }
        GpuValue.Text = Math.Round(gpuHistory[^1]) + "°";
        // wie im Entwurf: 40 bis 60 Grad füllen die Höhe; die Linie gleitet flüssig (Livelinie)
        gpuLine.Set(gpuHistory, demo ? ++demoTick : Live.Tick);
    }

    void SetBoost(bool on)
    {
        boost = on;
        BoostText.Text = on ? "AN" : "AUS";
        BoostNote.Text = on ? "Spiel-Beschleunigung an" : "vor dem Spielen";
        BoostSwitch.Background = on ? (Brush)FindResource("PulsQuer") : new SolidColorBrush(Hex("#2A2036"));
        var to = on ? 23.0 : 3.0;
        // federnd wie cubic-bezier(.5,1.6,.4,1)
        BoostKnob.BeginAnimation(Canvas.LeftProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(300))
            { EasingFunction = new BackEase { Amplitude = 0.6, EasingMode = EasingMode.EaseOut } });
        var bg = new LinearGradientBrush { StartPoint = new Point(0.33, 0), EndPoint = new Point(0.67, 1) };
        bg.GradientStops.Add(new GradientStop(Hex(on ? "#241540" : "#140C22"), 0));
        bg.GradientStops.Add(new GradientStop(Hex("#09060D"), 0.75));
        BoostTile.Background = bg;
    }

    // der Schalter führt zur Boost-Seite: dort steht vor dem Einschalten, was sich ändert
    void BoostSwitch_Click(object sender, RoutedEventArgs e) { e.Handled = true; if (demo) SetBoost(!boost); else main.Go("boost"); }
    void Hw_Click(object sender, MouseButtonEventArgs e) => main.GoTop("hw");
    void Drives_Click(object sender, MouseButtonEventArgs e) { main.GoTop("hw"); main.Go("drives"); }
    void Tools_Click(object sender, MouseButtonEventArgs e) => main.Go("tools");
    void Game_Click(object sender, MouseButtonEventArgs e) => main.Go("games");
    void Boost_Click(object sender, RoutedEventArgs e) { e.Handled = true; main.Go("boost"); }
}
