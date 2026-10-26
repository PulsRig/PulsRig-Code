using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace PulsRig.App;

// Rahmen der Reihe Q: Leiste links, Titelzeile mit Zurück und Weg-Leiste, darunter die Seite.
// Der Weg ist ein Stapel wie im Entwurf: Zurück = genau eine Ebene, Klick in der Leiste springt dorthin.
public partial class MainWindow : Window
{
    static readonly Dictionary<string, string> Names = new()
    {
        ["home"] = "Scan", ["boost"] = "Boost", ["tools"] = "Werkzeuge", ["hw"] = "Hardware", ["opt"] = "Optionen", ["boostsetup"] = "Einrichten", ["ping"] = "Ping-Test", ["power"] = "Stromverbrauch", ["bench"] = "Benchmark", ["sensors"] = "Sensoren",
        ["drives"] = "Laufwerke", ["gpu"] = "Grafikkarte", ["cpu"] = "Prozessor", ["ram"] = "Arbeitsspeicher", ["stress"] = "Stabilitätstest",
        ["display"] = "Bildschirm", ["crash"] = "Abstürze", ["report"] = "Bericht & Diagnose", ["drivers"] = "Treiber",
        ["repair"] = "Etwas reparieren", ["problem"] = "Was ist los?", ["input"] = "Controller und Maus", ["battery"] = "Akku", ["reinstall"] = "Neuinstallation", ["stick"] = "Notfall-Stick",["upgrade"] = "Aufrüst-Berater",["clean"] = "Aufräumen", ["manage"] = "Treiber verwalten", ["games"] = "Fürs Spielen", ["changes"] = "Was hat sich geändert?", ["single"] = "Einzelnen Treiber sichern",
    };

    static readonly (string Id, string Label, string Icon)[] RailDefs =
    {
        ("home", "Scan", "M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14 M20 20l-4-4"),
        ("boost", "Boost", "M4 16a8 8 0 1 1 16 0 M12 16l4-5"),
        ("tools", "Werkzeuge", "M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"),
        ("hw", "Hardware", "M6 6h12v12H6z M9 2v4 M15 2v4 M9 18v4 M15 18v4 M2 9h4 M2 15h4 M18 9h4 M18 15h4"),
    };
    const string OptIcon = "M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0 M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2";

    readonly List<string> stack = new() { "home" };
    readonly Dictionary<string, Button> railButtons = new();
    readonly bool demo;

    // path: Weg zur ersten Seite ohne "home", etwa "hw/ram" (Schalter -Seite, für Bilder und Tests)
    public MainWindow(bool demo, string path = "")
    {
        this.demo = demo;
        InitializeComponent();
        Texte.Attach(this);
        foreach (var r in RailDefs) Rail.Children.Add(RailButton(r.Id, r.Label, r.Icon));
        RailBottom.Children.Add(RailButton("opt", "Optionen", OptIcon));
        ((Storyboard)FindResource("Blinken")).Begin(WatchDot, true);
        AdminChip.Visibility = App.IsAdmin ? Visibility.Collapsed : Visibility.Visible;
        foreach (var part in path.Split('/', StringSplitOptions.RemoveEmptyEntries)) if (Names.ContainsKey(part) && part != "home") stack.Add(part);
        Show(true);
        // Probezeit neuer Treiber: einmal je Start im Hintergrund
        if (!demo) Loaded += (_, _) => Probezeitlauf.Start();
        Loaded += async (_, _) => { if (await Neuefassung.Check() is { } note) ShowVersion(note.Version != Core.PulsRigInfo.Version ? note.Version + " verfügbar" : "Neue Fassung verfügbar"); };
    }

    Button RailButton(string id, string label, string icon)
    {
        var bar = new Rectangle { Width = 3, Height = 26, RadiusX = 1.5, RadiusY = 1.5, HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(-8, 2, 0, 0), Fill = Brushes.Transparent };
        var path = new Path { Data = Geometry.Parse(icon), StrokeThickness = 2, Width = 24, Height = 24, Stretch = Stretch.None,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
            LayoutTransform = new ScaleTransform(20 / 24.0, 20 / 24.0) };
        path.SetBinding(Shape.StrokeProperty, new System.Windows.Data.Binding("Foreground") { RelativeSource =
            new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.FindAncestor, typeof(Button), 1) });
        var text = new TextBlock { Text = label, FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 5, 0, 0) };
        var inner = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        inner.Children.Add(path);
        inner.Children.Add(text);
        var grid = new Grid();
        grid.Children.Add(bar);
        grid.Children.Add(inner);
        var b = new Button { Style = (Style)FindResource("Flach"), Width = 68, Padding = new Thickness(0, 10, 0, 10), Tag = "12",
            Margin = new Thickness(0, 0, 0, 6), Content = grid, Foreground = (Brush)FindResource("Leise"),
            HorizontalContentAlignment = HorizontalAlignment.Stretch };
        System.Windows.Automation.AutomationProperties.SetName(b, label);
        b.Click += (_, _) => GoTop(id);
        b.MouseEnter += (_, _) => { if (Section != id) b.Background = new SolidColorBrush(Color.FromRgb(0x11, 0x0A, 0x19)); };
        b.MouseLeave += (_, _) => { if (Section != id) b.Background = Brushes.Transparent; };
        railButtons[id] = b;
        return b;
    }

    string Section => stack.Count > 1 ? stack[1] : "home";

    public void Go(string id) { stack.Add(id); Show(true); }
    // neu starten, etwa nach dem Wechsel der Sprache: die Texte werden beim Start geladen
    public void Restart()
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!, "-Seite " + string.Join("/", stack.Skip(1))) { UseShellExecute = false }); }
        catch (Exception) { return; }
        Application.Current.Shutdown();
    }

    public void Back() { if (stack.Count > 1) { stack.RemoveAt(stack.Count - 1); Show(false); } }
    public void GoTop(string id)
    {
        stack.Clear();
        stack.Add("home");
        if (id != "home") stack.Add(id);
        Show(true);
    }

    protected override void OnClosed(EventArgs e)
    {
        (PageHost.Content as IPage)?.Stop();
        Belastung.Shutdown();
        Live.Shutdown();
        base.OnClosed(e);
    }

    void Show(bool forward)
    {
        (PageHost.Content as IPage)?.Stop();
        var cur = stack[^1];
        PageHost.Content = cur switch
        {
            "home" => new HomePage(this, demo),
            "hw" => new HardwarePage(this, demo),
            "drives" => new DrivesPage(demo),
            "drivers" => new TreiberPage(demo),
            "tools" => new WerkzeugePage(this, null),
            "repair" or "clean" or "manage" or "games" => new WerkzeugePage(this, cur),
            "boost" => new BoostPage(this),
            "opt" => new OptionenPage(this),
            "boostsetup" => new BoostSetupPage(this),
            "ping" => new PingPage(this),
            "power" => new StromPage(),
            "bench" => new BenchPage(),
            "sensors" => new SensorPage(),
            "problem" => new ProblemPage(this),
            "changes" => new AenderungenPage(this, demo),
            "single" => new EinzeltreiberPage(demo),
            "input" => new EingabePage(),
            "battery" => new AkkuPage(),
            "upgrade" => new AufruestPage(),
            "reinstall" => new NeuinstallPage(this),
            "stick" => new NeuinstallPage(this, 2),
            "gpu" or "cpu" or "ram" or "stress" or "display" or "crash" or "report" => new DetailPage(cur, this, demo),
            _ => new Platzhalter(Names.GetValueOrDefault(cur, cur)),
        };
        UpdateRail();
        UpdateCrumbs();
        Animate(forward);
    }

    void UpdateRail()
    {
        var bars = (Brush)new SolidColorBrush(Color.FromRgb(0x6D, 0x43, 0xC9));
        foreach (var (id, b) in railButtons)
        {
            var on = id == Section;
            b.Background = on ? new SolidColorBrush(Color.FromRgb(0x14, 0x0C, 0x1D)) : Brushes.Transparent;
            b.Foreground = on ? Brushes.White : (Brush)FindResource("Leise");
            var grid = (Grid)b.Content;
            var bar = (Rectangle)grid.Children[0];
            bar.Fill = on ? bars : Brushes.Transparent;
            bar.Effect = on ? new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 12, ShadowDepth = 0, Color = Color.FromRgb(0x6D, 0x43, 0xC9) } : null;
            ((TextBlock)((StackPanel)grid.Children[1]).Children[1]).FontWeight = on ? FontWeights.SemiBold : FontWeights.Medium;
        }
    }

    void UpdateCrumbs()
    {
        BackButton.Visibility = stack.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        Crumbs.Children.Clear();
        for (var i = 0; i < stack.Count; i++)
        {
            var last = i == stack.Count - 1;
            if (i > 0) Crumbs.Children.Add(new TextBlock { Text = "›", Foreground = (Brush)FindResource("Trenner"), VerticalAlignment = VerticalAlignment.Center });
            var depth = i;
            var b = new Button { Style = (Style)FindResource("Flach"), Padding = new Thickness(6, 4, 6, 4),
                Content = new TextBlock { Text = Names.GetValueOrDefault(stack[i], stack[i]), FontSize = 14, FontWeight = last ? FontWeights.SemiBold : FontWeights.Normal },
                Foreground = last ? Brushes.White : (Brush)FindResource("Leise") };
            if (!last)
            {
                b.Click += (_, _) => { stack.RemoveRange(depth + 1, stack.Count - depth - 1); Show(false); };
                b.MouseEnter += (_, _) => b.Foreground = Brushes.White;
                b.MouseLeave += (_, _) => b.Foreground = (Brush)FindResource("Leise");
            }
            Crumbs.Children.Add(b);
        }
    }

    // Seitenwechsel wie .z-in / .z-out: 0,45 s, vorwärts aus 96 % und 8 Punkten tiefer, zurück aus 104 %
    void Animate(bool forward)
    {
        var group = (TransformGroup)PageHost.RenderTransform;
        var scale = (ScaleTransform)group.Children[0];
        var move = (TranslateTransform)group.Children[1];
        var ease = new PageEase();
        var time = Bewegung.Time(450);
        void Run(DependencyObject target, DependencyProperty p, double from, double to) =>
            ((IAnimatable)target).BeginAnimation(p, new DoubleAnimation(from, to, time) { EasingFunction = ease });
        Run(PageHost, OpacityProperty, 0, 1);
        Run(scale, ScaleTransform.ScaleXProperty, forward ? 0.96 : 1.04, 1);
        Run(scale, ScaleTransform.ScaleYProperty, forward ? 0.96 : 1.04, 1);
        Run(move, TranslateTransform.YProperty, forward ? 8 : 0, 0);
    }

    void TitleBar_MouseDown(object sender, MouseButtonEventArgs e)
    {
        // DragMove fängt die Maus ein: ohne diese Ausnahme kommt das Loslassen nie bei den beiden Knöpfen an
        if (e.OriginalSource is DependencyObject source && (VersionChip.IsAncestorOf(source) || AdminChip.IsAncestorOf(source))) return;
        if (e.ClickCount == 2) WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        else DragMove();
    }

    void Back_Click(object sender, RoutedEventArgs e) => Back();
    // wie „Als Admin neu starten“ im PowerShell-Programm: Windows fragt nach, dann startet PulsRig neu
    void Admin_Click(object sender, MouseButtonEventArgs e)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!, "-Seite " + string.Join("/", stack.Skip(1))) { UseShellExecute = true, Verb = "runas" }); }
        catch (Exception) { return; }   // abgelehnt
        Application.Current.Shutdown();
    }

    void ShowVersion(string text) { VersionText.Text = text; VersionChip.Visibility = Visibility.Visible; }

    bool updating;

    // wie Open-UpdateSheet: erst erklären, dann laden, prüfen und still installieren; ohne Setup-Angaben die Webseite
    async void Version_Click(object sender, MouseButtonEventArgs e)
    {
        var note = Neuefassung.Found;
        if (note == null || updating) return;
        var page = "https://github.com/" + Core.Fassung.Repo + "/releases/latest";
        if (note.Setup.Length == 0) { try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(page) { UseShellExecute = true }); } catch (Exception) { } return; }
        var text = "PulsRig lädt die Setup-Datei (" + (note.Bytes / 1048576.0).ToString("N1", Ui.De) + " MB) von GitHub, prüft sie und startet die Installation. Das Programm schließt sich dabei und öffnet sich danach wieder.\n\n" +
            "Einstellungen, Ergebnisse und gesicherte Treiber bleiben erhalten. Gestartet wird die Datei nur, wenn Größe und Prüfsumme zu den veröffentlichten Angaben passen.\n\n" +
            (App.IsAdmin ? "PulsRig läuft mit Adminrechten: Die Installation beginnt ohne weitere Rückfrage." : "Die Installation braucht Adminrechte. Windows fragt danach, mit dem Hinweis „Unbekannter Herausgeber“.");
        if (!Bestaetigung.Ask(this, "PulsRig " + note.Version + " installieren?", text, "Laden und installieren")) return;
        updating = true;
        string result;
        try { result = await Neuefassung.Install(note, s => Dispatcher.BeginInvoke(() => VersionText.Text = s)); }
        catch (Exception) { result = "Das Laden hat nicht geklappt. Später noch einmal versuchen oder die Seite im Browser öffnen."; }
        updating = false;
        if (result.Length > 0) { VersionText.Text = note.Version + " verfügbar"; Bestaetigung.Ask(this, "Kein Update", result, "Verstanden"); return; }
        VersionText.Text = "Installation läuft …";
        App.ReleaseMark();
        Application.Current.Shutdown();
    }

    void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    void Close_Click(object sender, RoutedEventArgs e) => Close();
}

