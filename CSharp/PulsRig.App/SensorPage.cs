using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Path = System.Windows.Shapes.Path;
using PulsRig.Core;

namespace PulsRig.App;

// Sensoren wie das Fenster Sensoren im PowerShell-Programm: "Live" mit den Werten der Messschleife und kleinen
// Verläufen, "Spielsitzungen" mit den Aufzeichnungen des Helfers (Ordner Aufzeichnungen beim PowerShell-Programm):
// Diagramm der Temperaturen über die ganze Sitzung, Zusammenfassung, Stromkosten und Auswahl der letzten Sitzungen.
sealed class SensorPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    readonly Grid root = new();
    readonly List<double> gpuLoad = new(), cpuClock = new();
    int tab;
    string? pick;
    bool stopped;

    // der Reiter beim nächsten Öffnen ("Was ist los?" springt zu Spielsitzungen oder Verschleiß)
    public static int Next;

    public SensorPage()
    {
        tab = Next;
        Next = 0;
        Content = root;
        Live.Use();
        Live.Updated += Tick;
        Fill();
    }

    void Tick()
    {
        void Add(List<double> list, double? v) { if (v is { } d) { list.Add(d); if (list.Count > Live.Keep) list.RemoveAt(0); } }
        Add(gpuLoad, Live.Get("GpuLoad"));
        Add(cpuClock, Live.Get("CpuClock"));
        // nicht mitten in einem Klick neu aufbauen: sonst geht er verloren
        if (tab == 0 && System.Windows.Input.Mouse.LeftButton != System.Windows.Input.MouseButtonState.Pressed) Fill();
    }

    static string Folder => System.IO.Path.Combine(Altdaten.Folder, "Aufzeichnungen");

    static List<FileInfo> Files() => Directory.Exists(Folder) ? new DirectoryInfo(Folder).GetFiles("*.csv").OrderByDescending(f => f.Name).ToList() : new();

    // die Datei kann der Helfer gerade schreiben: mit geteiltem Zugriff lesen
    internal static Spielsitzung Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var lines = new List<string>();
        for (string? line; (line = reader.ReadLine()) != null;) lines.Add(line);
        return Aufzeichnung.Read(lines);
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        foreach (var (i, name) in new[] { (0, "Live"), (1, "Spielsitzungen"), (2, "Verschleiß") })
        {
            var b = Chip(name, tab == i, 36);
            b.Click += (_, _) => { tab = i; Fill(); };
            tabs.Children.Add(b);
        }
        root.Children.Add(tabs);
        var body = tab == 0 ? LiveView() : tab == 1 ? Sessions() : Wear();
        Grid.SetRow(body, 1);
        root.Children.Add(body);
    }

    UIElement LiveView()
    {
        var grid = Ui.Mosaic(3, 2, 12);
        string N(double? v, string unit, string format = "N0") => v is { } d ? d.ToString(format, Ui.De) + unit : "–";
        var cpuNote = Live.CpuTempStatus switch
        {
            "nolib" => "Ordner Sensoren fehlt", "nodriver" => "braucht den Treiber PawnIO", "noadmin" => "nur mit Adminrechten", "none" => "nicht lesbar", _ => "LibreHardwareMonitor",
        };
        var tiles = new (string Title, string Value, string Note, string Color, string Tint, List<double> History, double Max)[]
        {
            ("Grafikkarte", N(Live.Get("GpuTemp"), " °C"), Live.Values["GpuName"] as string ?? "nur bei NVIDIA messbar", Lila, "#160D29", Live.GpuTemp, 100),
            ("Last der Grafikkarte", N(Live.Get("GpuLoad"), " %"), Live.Get("GpuPower") is { } w ? w.ToString("N0", Ui.De) + " W" + (Live.Get("GpuFan") is { } f ? " · Lüfter " + f.ToString("N0", Ui.De) + " %" : "") : "", Beere, "#1F0A19", gpuLoad, 100),
            ("Grafikspeicher", Live.Get("GpuMemory") is { } m && Live.Get("GpuMemoryTotal") is { } t && t > 0 ? (m / 1024).ToString("N1", Ui.De) + " GB" : "–",
                Live.Get("GpuMemoryTotal") is { } tt ? "von " + (tt / 1024).ToString("N0", Ui.De) + " GB belegt" : "", "#5E4BB8", "#130B24", new List<double>(), 1),
            ("Prozessor", N(Live.Get("CpuTemp"), " °C"), cpuNote, Bernstein, "#2A2112", Live.CpuTemp, 100),
            ("Auslastung", N(Live.Get("CpuLoad"), " %"), Live.Get("CpuCoreMax") is { } c ? "stärkster Kern " + c.ToString("N0", Ui.De) + " %" : "", Gruen, "#10291F", Live.CpuLoad, 100),
            ("Takt", N(Live.Get("CpuClock"), " GHz", "N1"), Live.Get("CpuPower") is { } p ? p.ToString("N0", Ui.De) + " W" : "", "#8C6BD6", "#160D29", cpuClock, Math.Max(1, cpuClock.DefaultIfEmpty(1).Max() * 1.1)),
        };
        for (var i = 0; i < tiles.Length; i++)
        {
            var (title, value, note, color, tint, history, max) = tiles[i];
            var panel = new DockPanel();
            var head = Ui.Text(title, 12.5, color, bold: true);
            DockPanel.SetDock(head, Dock.Top);
            panel.Children.Add(head);
            var v = Ui.Text(value, 30, "Text", bold: true, mono: true);
            v.Margin = new Thickness(0, 6, 0, 0);
            DockPanel.SetDock(v, Dock.Top);
            panel.Children.Add(v);
            var n = Ui.Text(note, 11.5, "Leise");
            DockPanel.SetDock(n, Dock.Top);
            panel.Children.Add(n);
            panel.Children.Add(Spark(title, history, max, color));
            var tile = Ui.Tile(color, tint, new Thickness(18, 16, 18, 14));
            tile.CornerRadius = new CornerRadius(22);
            tile.Child = panel;
            Ui.Place(grid, tile, i % 3, i / 3);
        }
        return grid;
    }

    // Livelinie der letzten Minute als Linie; je Kachel bleibt dasselbe Element über alle Takte stehen und gleitet flüssig
    readonly Dictionary<string, Livelinie> sparks = new();

    FrameworkElement Spark(string key, List<double> values, double max, string color)
    {
        if (values.Count < 2) return new Border();
        if (!sparks.TryGetValue(key, out var spark))
            sparks[key] = spark = new Livelinie(color, area: false) { Height = 46, Margin = new Thickness(0, 10, 0, 0), VerticalAlignment = VerticalAlignment.Bottom };
        (spark.Parent as Panel)?.Children.Remove(spark);
        spark.High = max;
        spark.Set(values, Live.Tick);
        return spark;
    }

    UIElement Sessions()
    {
        var list = new StackPanel();
        var files = Files();
        if (files.Count == 0)
        {
            var settings = Altdaten.Settings();
            var text = Helfer.Exe == null ? "Aufgezeichnet wird im Helfer neben der Uhr. Den gibt es nur im installierten Programm."
                : !Altdaten.Flag(settings, "Helper", false) ? "Aufgezeichnet wird im Helfer neben der Uhr. Er ist ausgeschaltet – einschalten unter Optionen → Überwachung."
                : !Altdaten.Flag(settings, "RecordGames", true) ? "Die Aufzeichnung beim Spielen ist ausgeschaltet – einschalten unter Optionen → Überwachung."
                : "Sobald ein Boost-Spiel oder ein unter „Spiele & Aufzeichnung“ gewähltes Spiel läuft, schreibt der Helfer alle 5 Sekunden mit.";
            list.Children.Add(Card(Ui.Text("Noch keine Spielsitzung", 16, "Text", bold: true), Para(text)));
            list.Children.Add(Card(Ui.Text("Was aufgezeichnet wird", 14, "Text", bold: true), Para("Alle 5 Sekunden Temperatur, Last und Takt von Prozessor und Grafikkarte, dazu Leistung und Lüfter der Grafikkarte. Es bleiben die letzten 30 Sitzungen.")));
            return list;
        }
        var file = files.FirstOrDefault(f => f.FullName == pick) ?? files[0];
        Spielsitzung session;
        try { session = Read(file.FullName); }
        catch (Exception e) { list.Children.Add(Card(Ui.Text("Die Sitzung ließ sich nicht lesen", 15, "Text", bold: true), Para(e.Message))); return list; }
        list.Children.Add(Chart(session));
        var summary = Aufzeichnung.Summary(session);
        list.Children.Add(Card(Ui.Text(summary.Tone == "warn" ? "Zu warm oder gedrosselt" : "Zusammenfassung", 15, summary.Tone == "warn" ? Bernstein : Gruen, bold: true), Para(string.Join("\n", summary.Lines))));
        // Stromkosten dieser Sitzung (wie Add-RecordingEnergyRow)
        if (session.Column("Sekunde") is { } seconds && Strom.Recording(seconds, session.Column("GpuWatt"), session.Column("CpuWatt"), session.Column("CpuLast")) is { } energy)
        {
            var price = Altdaten.Settings()["PowerPrice"] is System.Text.Json.Nodes.JsonValue pv && pv.TryGetValue<double>(out var p) ? p : 0.35;
            var euro = energy.Kwh * price;
            var measured = energy.GpuMeasured && energy.CpuMeasured ? "Grafikkarte und Prozessor gemessen, der Rest geschätzt" : energy.GpuMeasured ? "Grafikkarte gemessen, Prozessor und Rest geschätzt"
                : energy.CpuMeasured ? "Prozessor gemessen, Grafikkarte und Rest geschätzt" : "Geschätzt: weder Grafikkarte noch Prozessor gemessen";
            list.Children.Add(Card(Ui.Text("Stromkosten dieser Sitzung: " + (euro < 1 ? (euro * 100).ToString("N0", Ui.De) + " Cent" : euro.ToString("N2", Ui.De) + " €"), 15, Lila, bold: true),
                Para("Im Mittel " + energy.Average.ToString("N0", Ui.De) + " W · " + energy.Kwh.ToString("N2", Ui.De) + " kWh bei " + price.ToString("N2", Ui.De) + " €/kWh\n" + measured)));
        }
        // Auswahl: die letzten acht Sitzungen
        var choice = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) };
        foreach (var f in files.Take(8))
        {
            var name = f.Name;
            var m = System.Text.RegularExpressions.Regex.Match(name, @"^(\d{4})-(\d\d)-(\d\d)_(\d\d)-(\d\d)-\d\d_(.+)\.csv$");
            var label = m.Success ? m.Groups[3].Value + "." + m.Groups[2].Value + ". " + m.Groups[4].Value + ":" + m.Groups[5].Value + " · " + m.Groups[6].Value : name;
            var b = Chip(label, f.FullName == file.FullName, 32);
            b.Click += (_, _) => { pick = f.FullName; Fill(); };
            choice.Children.Add(b);
        }
        list.Children.Add(choice);
        list.Children.Add(Ui.Text(files.Count + (files.Count == 1 ? " Sitzung" : " Sitzungen") + " · Ordner Aufzeichnungen", 11.5, "Leise"));
        return new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
    }

    // Verschleiß wie Show-WearTab: Kühlung von Grafikkarte und Prozessor über die Wochen, Lebensdauer der SSDs.
    // Neue Spielsitzungen werden dabei im Hintergrund zu Messpunkten.
    (List<Verschleissbefund> Trends, List<Verschleissbefund> Ssds, int Count)? wear;
    bool wearLoading;

    UIElement Wear()
    {
        var list = new StackPanel();
        if (wear is not { } w)
        {
            list.Children.Add(Card(Ui.Text("Lese die Messpunkte …", 15, "Text", bold: true), Para("Spielsitzungen und Stabilitätstests der letzten Wochen")));
            if (!wearLoading)
            {
                wearLoading = true;

                Task.Run(() =>
                {
                    try { Verschleissdaten.Update(); } catch (Exception) { }
                    var points = Verschleissdaten.Points();
                    return (new List<Verschleissbefund> { Verschleiss.Trend(points, 'G'), Verschleiss.Trend(points, 'C') }, Verschleissdaten.Ssds(Hw.Drives ?? Abfragen.Drives()), points.Count(p => p.Src != "kurz"));
                }).ContinueWith(t => Dispatcher.BeginInvoke(() => { wearLoading = false; if (t.IsCompletedSuccessfully) wear = t.Result; if (tab == 2) Fill(); }));
            }
            return list;
        }
        string Color(string tone) => tone switch { "warn" => Bernstein, "bad" => Beere, "good" => Gruen, _ => Lila };
        foreach (var t in w.Trends) list.Children.Add(Card(Ui.Text(t.Title + ": " + t.State, 15, Color(t.Tone), bold: true), Para(t.Text)));
        if (w.Ssds.Count == 0)
            list.Children.Add(Card(Ui.Text("SSD", 15, "Text", bold: true), Para("Die Abnutzung liest Windows nur mit Adminrechten. PulsRig einmal als Admin starten.")));
        foreach (var s in w.Ssds) list.Children.Add(Card(Ui.Text(s.Title + " · " + s.State, 15, Color(s.Tone), bold: true), Para(s.Text)));
        list.Children.Add(Ui.Text(w.Count + " Messpunkte aus Spielsitzungen und Stabilitätstests · es zählen nur deutliche Unterschiede", 11.5, "Leise"));
        return new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
    }

    // wie New-RecordingChart: Prozessor und Grafikkarte über die Sitzung, 30 bis 100 °C, Hilfslinien bei 50, 70, 90 °C.
    // Jede Linie trägt unsichtbare Eckpunkte, damit alle mit Stretch Fill gleich gestreckt werden.
    static Border Chart(Spielsitzung s)
    {
        var seconds = Math.Max(1, s.Seconds);
        var inv = CultureInfo.InvariantCulture;
        var frame = string.Format(inv, "M 0,0 M {0:0.##},70 ", seconds);
        var outer = new DockPanel();
        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        var legend = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (label, color) in new[] { ("Prozessor", Bernstein), ("Grafikkarte", Lila) })
        {
            legend.Children.Add(new Ellipse { Width = 8, Height = 8, Fill = Ui.Brush(color), Margin = new Thickness(14, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center });
            legend.Children.Add(Ui.Text(label, 11.5, "Leise"));
        }
        DockPanel.SetDock(legend, Dock.Right);
        head.Children.Add(legend);
        head.Children.Add(Ui.Text(s.Game + " · " + s.Begin.ToString("dd.MM. HH:mm") + " · " + Aufzeichnung.Duration(s.Seconds), 14, "Text", bold: true));
        DockPanel.SetDock(head, Dock.Top);
        outer.Children.Add(head);
        var axis = new Grid { Margin = new Thickness(30, 4, 0, 0) };
        foreach (var (at, align) in new[] { (0.0, HorizontalAlignment.Left), (0.5, HorizontalAlignment.Center), (1.0, HorizontalAlignment.Right) })
        { var t = Ui.Text(s.Begin.AddSeconds(seconds * at).ToString("HH:mm"), 10.5, "Leise"); t.HorizontalAlignment = align; axis.Children.Add(t); }
        DockPanel.SetDock(axis, Dock.Bottom);
        outer.Children.Add(axis);
        var area = new Grid { Height = 190, Margin = new Thickness(30, 0, 0, 0) };
        foreach (var mark in new[] { 50, 70, 90 })
        {
            area.Children.Add(new Path { Data = Geometry.Parse(frame + string.Format(inv, "M 0,{0} L {1:0.##},{0}", 100 - mark, seconds)), Stretch = Stretch.Fill, StrokeThickness = 1,
                StrokeDashArray = new DoubleCollection { 3, 4 }, Stroke = Ui.Brush(mark == 90 ? Bernstein : "#8C819F"), Opacity = mark == 90 ? 0.55 : 0.25 });
            var label = Ui.Text(mark + " °", 10.5, "Leise");
            label.Margin = new Thickness(-30, 190.0 * (100 - mark) / 70 - 8, 0, 0);
            label.VerticalAlignment = VerticalAlignment.Top;
            label.HorizontalAlignment = HorizontalAlignment.Left;
            area.Children.Add(label);
        }
        var time = s.Column("Sekunde") ?? new();
        foreach (var (name, color) in new[] { ("GpuTemp", Lila), ("CpuTemp", Bernstein) })
        {
            if (s.Column(name) is not { } values) continue;
            var points = new StringBuilder(frame);
            var open = false;
            for (var i = 0; i < values.Count && i < time.Count; i++)
            {
                if (double.IsNaN(values[i])) { open = false; continue; }
                var y = 100 - Math.Clamp(values[i], 30, 100);
                points.Append(string.Format(inv, "{0} {1:0.##},{2:0.##} ", open ? "L" : "M", time[i], y));
                open = true;
            }
            area.Children.Add(new Path { Data = Geometry.Parse(points.ToString()), Stretch = Stretch.Fill, StrokeThickness = 1.8, StrokeLineJoin = PenLineJoin.Round, Stroke = Ui.Brush(color) });
        }
        outer.Children.Add(area);
        var card = Ui.Tile(Lila, "#120B1C", new Thickness(18, 16, 18, 12));
        card.CornerRadius = new CornerRadius(22);
        card.Margin = new Thickness(0, 0, 0, 10);
        card.Child = outer;
        return card;
    }

    static TextBlock Para(string text) => new() { Text = text, FontSize = 12.5, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0), LineHeight = 19 };

    static Border Card(params UIElement[] children)
    {
        var panel = new StackPanel();
        foreach (var c in children) panel.Children.Add(c);
        return new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(18), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"),
            Padding = new Thickness(18, 14, 18, 14), Margin = new Thickness(0, 0, 0, 10), Child = panel };
    }

    static Button Chip(string label, bool on, double height) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = height, Padding = new Thickness(14, 0, 14, 0), Margin = new Thickness(0, 0, 8, 8), Tag = (height / 2).ToString(CultureInfo.InvariantCulture),
        Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(on ? 0 : 1),
        VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 12.5, "Text", bold: true),
    };

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Live.Updated -= Tick;
        Live.Release();
    }
}
