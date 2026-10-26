using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;

namespace PulsRig.App;

// Werkzeuge nach dem Entwurf: Übersicht mit den vier Absichten als Kacheln (tools) und je Absicht die Werkzeugliste
// (toolList) – links Absicht und Hinweis, rechts je Werkzeug eine Zeile mit Farbbalken, Text, Hinweis und Knopf.
sealed class WerkzeugePage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    // Run: Aktion des Knopfs; Bridge: Werkzeug von Treiber-Scan.ps1; Page: Seite der neuen Oberfläche; nichts davon: folgt
    sealed record Werkzeug(string Name, string Sub, string? Bridge = null, string? Page = null, bool Native = false);
    sealed record Absicht(string Id, string Title, string Sub, string Color, string Tint, int Span, string Icon, Werkzeug[] Tools);

    static readonly Absicht[] Absichten =
    {
        new("repair", "Etwas reparieren", "Kein Ton, kein Netz, falsches Bild, Gerät mit Warnzeichen oder der PC wacht nachts auf.", Beere, "#1F0A19", 2,
            "M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z", new Werkzeug[]
            {
                new("Was ist los?", "Vom Problem zur Ursache: was PulsRig schon weiß und was als Nächstes zu prüfen ist", Page: "problem"),
                new("Ton reparieren", "Dienste, Stummschaltung und Ausgabegerät prüfen", "FixAudio"),
                new("Netzwerk reparieren", "Verbindung testen und in Stufen reparieren", "FixNetwork"),
                new("Ping-Test", "Verzögerung und Aussetzer zu Router und Internet messen", Page: "ping"),
                new("Bildauflösung reparieren", "Grafiktreiber und empfohlene Auflösung prüfen", "FixResolution"),
                new("Gerätefehler reparieren", "Geräte mit gelbem Warnzeichen neu einrichten", "FixDevices"),
                new("Standby-Detektiv", "Warum der PC aufwacht oder wach bleibt", "Standby"),
            }),
        new("clean", "Aufräumen", "Speicherplatz, Autostart und alte Geräteeinträge.", Gruen, "#10291F", 1,
            "M4 7h16 M10 11v6 M14 11v6 M6 7l1 13h10l1-13 M9 7V4h6v3", new Werkzeug[]
            {
                new("Speicherplatz freigeben", "Temporäre Dateien, Shader-Cache, alte Treiberpakete", "CleanDisk"),
                new("Autostart aufräumen", "Programme, die mit Windows starten", "Autostart"),
                new("Gerätedaten bereinigen", "Einträge längst abgesteckter Hardware entfernen", "CleanDevices"),
            }),
        new("manage", "Treiber verwalten", "Sichern, zurückholen, Offline-Paket und Kernisolierung.", Lila, "#160D29", 1,
            "M5 4h11l3 3v13H5z M8 4v5h7V4 M8 20v-6h8v6", new Werkzeug[]
            {
                new("Treiber sichern", "Alle Treiber von Drittherstellern sichern, mit ZIP-Datei", Native: true),
                new("Treiber zurückholen", "Eine Sicherung wieder einspielen", Native: true),
                new("Einzelnen Treiber sichern", "Das Treiberpaket eines Geräts in einen eigenen Ordner kopieren", Page: "single"),
                new("Neuinstallation", "Vorher Treiber und Programmliste sichern, danach geführt einspielen", Page: "reinstall"),
                new("Notfall-Stick", "PulsRig und die Treiber auf einen USB-Stick", Page: "stick"),
                new("Offline-Paket", "Treiberpaket für eine Neuinstallation ohne Internet", "OfflinePackage"),
                new("Treiberverlauf", "Was sich wann geändert hat", "DriverHistory"),
                new("Was hat sich geändert?", "Windows, Programme, Autostart und Treiber mit gestern, vor 7 oder 30 Tagen vergleichen", Page: "changes"),
                new("Inkompatible Treiber", "Was die Kernisolierung blockiert", "IncompatibleDrivers"),
            }),
        new("games", "Fürs Spielen", "Spielkomponenten, Gaming-Check und Systeminfos.", Bernstein, "#2A2112", 1,
            "M7 8h10a4.5 4.5 0 0 1 0 9H7a4.5 4.5 0 0 1 0-9z M8 11v3 M6.5 12.5h3 M15 12h.01 M17 14h.01", new Werkzeug[]
            {
                new("Spielkomponenten", "Visual C++, DirectX und XNA prüfen und nachinstallieren", Page: "drivers"),
                new("Benchmark", "Prozessor und Grafikkarte messen und mit früher vergleichen", Page: "bench"),
                new("Aufrüst-Berater", "Eine Minute im Spiel messen, was bremst, und was sich zum Aufrüsten lohnt", Page: "upgrade"),
                new("Stromverbrauch", "Watt und Stromkosten im Jahr, dazu der FPS-Limit-Vergleich", Page: "power"),
                new("Sensoren & Aufzeichnungen", "Temperaturen live und aufgezeichnete Spielsitzungen", Page: "sensors"),
                new("Gaming-Check", "Bildschirm-Hz, Resizable BAR, Spielmodus und mehr", "GamingCheck"),
                new("Spiele & Aufzeichnung", "Welche Spiele Boost und Aufzeichnung bekommen", "Games"),
                new("Controller und Maus", "Tasten, Stick-Drift, Abfragerate und ungewollte Doppelklicks prüfen", Page: "input"),
                new("Systeminformationen", "Hardware und Windows im Überblick", "SystemInfo"),
            }),
    };

    readonly MainWindow window;
    readonly Absicht? intent;
    readonly Grid root = new();
    bool stopped;
    // zugeklappte Ergebnisse; bleibt beim Seitenwechsel erhalten. Eine neue Prüfung klappt die übrigen zu (wie ein Akkordeon)
    static readonly HashSet<string> Collapsed = new();

    void Toggle(string key)
    {
        if (!Collapsed.Remove(key)) Collapsed.Add(key);
        Fill();
    }

    static Button? FindButton(DependencyObject? d)
    {
        for (; d != null && d is not Border { Child: StackPanel }; d = d is Visual ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d))
            if (d is Button b) return b;
        return null;
    }

    public WerkzeugePage(MainWindow window, string? intentId)
    {
        this.window = window;
        intent = Absichten.FirstOrDefault(a => a.Id == intentId);
        Content = root;
        Fill();
        Werkzeuglauf.Changed += Fill;
        Treiberscan.Changed += Fill;
    }

    // beim Neuaufbau (jede Meldung eines Werkzeugs) bleibt die Liste, wo sie war, und blendet nicht erneut ein
    double offset;
    bool arrived;

    void Fill()
    {
        if (stopped) return;
        if (root.Children.OfType<ScrollViewer>().FirstOrDefault() is { } old) offset = old.VerticalOffset;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.RowDefinitions.Clear();
        if (intent == null) Overview(); else List(intent);
    }

    static Path Icon(string data, string color, double size, double stroke = 1.9) => new()
    {
        Data = Geometry.Parse(data), Stroke = Ui.Brush(color), StrokeThickness = stroke, Width = 24, Height = 24, Stretch = Stretch.None,
        StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round,
        LayoutTransform = new ScaleTransform(size / 24, size / 24), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
    };

    static Border Pill(string text, string color) => new()
    {
        CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Center,
        Child = Ui.Text(text, 11, color),
    };

    // Hinweise auf den Kacheln aus echten Werten: Gerätefehler des letzten Scans, letzte Sicherung
    static string IntentHint(Absicht a)
    {
        var scan = Treiberscan.Last;
        return a.Id switch
        {
            "repair" when scan is { Problems.Count: > 0 } => scan.Problems.Count == 1 ? "1 Gerät mit Warnzeichen" : scan.Problems.Count + " Geräte mit Warnzeichen",
            "manage" when Werkzeuglauf.BackupFolders().Count == 0 => "noch keine Sicherung",
            _ => "",
        };
    }

    static string ToolHint(Werkzeug t)
    {
        var scan = Treiberscan.Last;
        return t.Name switch
        {
            "Gerätefehler reparieren" when scan is { Problems.Count: > 0 } => scan.Problems.Count == 1 ? "1 Gerät" : scan.Problems.Count + " Geräte",
            "Treiber zurückholen" => Werkzeuglauf.BackupFolders() is { Count: > 0 } b ? b.Count + (b.Count == 1 ? " Sicherung" : " Sicherungen") : "keine Sicherung",
            _ => "",
        };
    }

    void Overview()
    {
        for (var i = 0; i < 3; i++) root.ColumnDefinitions.Add(new ColumnDefinition());
        root.RowDefinitions.Add(new RowDefinition());
        root.RowDefinitions.Add(new RowDefinition());
        int col = 0, row = 0;
        var tiles = new List<UIElement>();
        foreach (var a in Absichten)
        {
            if (col + a.Span > 3) { col = 0; row++; }
            var tile = IntentTile(a);
            Grid.SetColumn(tile, col);
            Grid.SetRow(tile, row);
            Grid.SetColumnSpan(tile, a.Span);
            root.Children.Add(tile);
            tiles.Add(tile);
            col += a.Span;
        }
        var reco = Recommendation();
        Grid.SetColumn(reco, 2);
        Grid.SetRow(reco, 1);
        root.Children.Add(reco);
        tiles.Add(reco);
        if (!arrived) Ui.Arrive(tiles);
        arrived = true;
    }

    Button IntentTile(Absicht a)
    {
        var panel = new DockPanel();
        var head = new DockPanel();
        var icon = new Border { Width = 46, Height = 46, CornerRadius = new CornerRadius(14), Background = Ui.Alpha(a.Color, "1A"), BorderBrush = Ui.Alpha(a.Color, "33"), BorderThickness = new Thickness(1),
            Child = Icon(a.Icon, a.Color, 22), HorizontalAlignment = HorizontalAlignment.Left };
        DockPanel.SetDock(icon, Dock.Left);
        head.Children.Add(icon);
        var hint = IntentHint(a);
        if (hint.Length > 0) { var p = Pill(hint, a.Color); p.VerticalAlignment = VerticalAlignment.Top; p.HorizontalAlignment = HorizontalAlignment.Right; head.Children.Add(p); }
        DockPanel.SetDock(head, Dock.Top);
        panel.Children.Add(head);
        var title = Ui.Text(a.Title, 20, "Text", bold: true);
        title.Margin = new Thickness(0, 14, 0, 0);
        DockPanel.SetDock(title, Dock.Top);
        panel.Children.Add(title);
        var sub = new TextBlock { Text = a.Sub, FontSize = 12.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, LineHeight = 18, Margin = new Thickness(0, 4, 0, 0) };
        DockPanel.SetDock(sub, Dock.Top);
        panel.Children.Add(sub);
        var count = Ui.Text(a.Tools.Length + " Werkzeuge →", 11.5, a.Color, bold: true);
        count.Margin = new Thickness(0, 10, 0, 0);
        DockPanel.SetDock(count, Dock.Bottom);
        panel.Children.Add(count);
        var chips = new WrapPanel { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 12, 0, 0) };
        foreach (var t in a.Tools.Take(a.Span == 2 ? 4 : 2))
            chips.Children.Add(new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(0, 0, 6, 6), Background = Ui.Brush("#08FFFFFF"),
                BorderBrush = Ui.Brush("#22172F"), BorderThickness = new Thickness(1), Child = Ui.Text(t.Name, 11.5, "Halbleise") });
        panel.Children.Add(chips);

        var background = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0.6, 1) };
        background.GradientStops.Add(new GradientStop(Ui.Hex(a.Tint), 0));
        background.GradientStops.Add(new GradientStop(Ui.Hex("#09060D"), 0.75));
        var button = new Button { Style = (Style)Application.Current.FindResource("Flach"), Tag = "22", Margin = new Thickness(6), Padding = new Thickness(22, 20, 22, 20),
            Background = background, BorderBrush = Ui.Alpha(a.Color, "2E"), BorderThickness = new Thickness(1),
            HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch, Content = panel };
        System.Windows.Automation.AutomationProperties.SetName(button, a.Title);
        button.Click += (_, _) => window.Go(a.Id);
        return button;
    }

    // Empfehlung mit echtem Wert: wann zuletzt gesichert wurde
    Border Recommendation()
    {
        var last = Werkzeuglauf.BackupFolders().FirstOrDefault();
        var days = last == null ? -1 : (int)(DateTime.Now - last.LastWriteTime).TotalDays;
        var panel = new DockPanel();
        var label = Ui.Text("EMPFOHLEN", 10, "Leise", mono: true);
        DockPanel.SetDock(label, Dock.Top);
        panel.Children.Add(label);
        var title = Ui.Text("Treiber sichern", 18, "Text", bold: true);
        title.Margin = new Thickness(0, 10, 0, 0);
        DockPanel.SetDock(title, Dock.Top);
        panel.Children.Add(title);
        var sub = new TextBlock { Text = last == null ? "Vor großen Updates lohnt eine Sicherung aller Treiber von Drittherstellern." : "Letzte Sicherung: " + last.LastWriteTime.ToString("dd.MM.yyyy HH:mm") + " Uhr.",
            FontSize = 12.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
        DockPanel.SetDock(sub, Dock.Top);
        panel.Children.Add(sub);
        var big = new TextBlock { Text = last == null ? "noch keine" : days == 0 ? "heute" : days == 1 ? "vor 1 Tag" : "vor " + days + " Tagen", FontFamily = (FontFamily)Application.Current.FindResource("Mono"),
            FontSize = 30, FontWeight = FontWeights.SemiBold, Foreground = (Brush)Application.Current.FindResource("PulsQuer"), Margin = new Thickness(0, 14, 0, 0) };
        DockPanel.SetDock(big, Dock.Top);
        panel.Children.Add(big);
        var key = "manage:Treiber sichern";
        var busy = Werkzeuglauf.State.TryGetValue(key, out var s) && s.Busy;
        var run = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 40, Tag = "12", Margin = new Thickness(0, 12, 0, 0),
            Background = busy ? Ui.Brush("#140C1D") : (Brush)Application.Current.FindResource("PulsQuer"), HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            Content = Ui.Text(busy ? "Sichert …" : "Jetzt sichern", 13, "Text", bold: true) };
        if (!busy) run.Click += (_, _) => Werkzeuglauf.Backup(key);
        DockPanel.SetDock(run, Dock.Bottom);
        panel.Children.Add(run);
        panel.Children.Add(new Border());
        var edge = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#706D43C9"), 0));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.4));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.7));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#55A8326F"), 1));
        return new Border { CornerRadius = new CornerRadius(22), Margin = new Thickness(6), Padding = new Thickness(22, 20, 22, 20), Background = Ui.Brush("#0B0710"),
            BorderBrush = edge, BorderThickness = new Thickness(1), Child = panel };
    }

    void List(Absicht a)
    {
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        var panel = new DockPanel();
        var icon = new Border { Width = 64, Height = 64, CornerRadius = new CornerRadius(20), Background = Ui.Alpha(a.Color, "1A"), BorderBrush = Ui.Alpha(a.Color, "33"), BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Left, Child = Icon(a.Icon, a.Color, 30, 1.8) };
        var title = new TextBlock { Text = a.Title, FontSize = 26, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 20, 0, 0), TextWrapping = TextWrapping.Wrap };
        var sub = new TextBlock { Text = a.Sub, FontSize = 13, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), LineHeight = 19.5 };
        foreach (var top in new FrameworkElement[] { icon, title, sub }) { DockPanel.SetDock(top, Dock.Top); panel.Children.Add(top); }
        var note = new Border { CornerRadius = new CornerRadius(14), Background = Ui.Brush("#06FFFFFF"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), Padding = new Thickness(14, 12, 14, 12) };
        var noteRow = new DockPanel();
        var shield = Icon("M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6z M9 12l2 2 4-4", Gruen, 16, 2);
        shield.VerticalAlignment = VerticalAlignment.Top;
        shield.Margin = new Thickness(0, 1, 10, 0);
        noteRow.Children.Add(shield);
        noteRow.Children.Add(new TextBlock { Text = "Jedes Werkzeug prüft zuerst und fragt, bevor es etwas ändert." + "",
            FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 17.5 });
        note.Child = noteRow;
        DockPanel.SetDock(note, Dock.Bottom);
        panel.Children.Add(note);
        panel.Children.Add(new Border());
        var glow = new RadialGradientBrush { Center = new Point(0.2, 0.1), GradientOrigin = new Point(0.2, 0.1), RadiusX = 0.9, RadiusY = 0.5 };
        glow.GradientStops.Add(new GradientStop(Ui.Hex("#1C" + a.Color.TrimStart('#')), 0));
        glow.GradientStops.Add(new GradientStop(Colors.Transparent, 0.7));
        var layer = new Grid();
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(a.Color, "2E"), Padding = new Thickness(24), Child = panel, Background = Ui.Tint(a.Tint) });
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), Background = glow, IsHitTestVisible = false });
        root.Children.Add(layer);

        var list = new StackPanel();
        foreach (var t in a.Tools) list.Children.Add(Row(a, t));
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
        if (offset > 0) { var at = offset; scroll.Loaded += (_, _) => scroll.ScrollToVerticalOffset(at); }
        if (!arrived) Ui.Arrive(list.Children.Cast<UIElement>());
        arrived = true;
    }

    Border Row(Absicht a, Werkzeug t)
    {
        var key = a.Id + ":" + t.Name;
        var state = Werkzeuglauf.State.GetValueOrDefault(key, (Busy: false, Message: ""));
        var available = t.Native || t.Page != null || t.Bridge != null;
        var result = t.Bridge != null ? Werkzeuglauf.Results.GetValueOrDefault(key) : null;
        var done = !state.Busy && (state.Message.Length > 0 || result != null);
        var barColor = state.Busy ? a.Color : done ? Gruen : available ? "#22172F" : "#1A1224";

        var grid = new Grid { MinHeight = 72 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border { Width = 4, Height = 34, CornerRadius = new CornerRadius(2), Background = Ui.Brush(barColor), Margin = new Thickness(0, 0, 16, 0), Effect = Ui.Glow(barColor, 10) });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(t.Name, 15, available ? "Text" : "Leise", bold: true));
        var sub = Ui.Text(state.Message.Length > 0 ? state.Message : available ? t.Sub : t.Sub + " · folgt in der neuen Oberfläche", 12.5, state.Message.Length > 0 ? "Halbleise" : "Leise");
        sub.Margin = new Thickness(0, 3, 0, 0);
        sub.TextWrapping = TextWrapping.Wrap;
        text.Children.Add(sub);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        var hint = ToolHint(t);
        if (hint.Length > 0) { var p = Pill(hint, a.Color); p.Margin = new Thickness(0, 0, 12, 0); Grid.SetColumn(p, 2); grid.Children.Add(p); }

        var label = state.Busy ? "Läuft …" : !available ? "Folgt" : t.Page != null ? "Öffnen" : t.Bridge != null ? (result != null ? "Erneut prüfen" : "Prüfen") : done ? "Erneut" : "Starten";
        var primary = available && !state.Busy && !done;
        var button = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, MinWidth = 96, Padding = new Thickness(16, 0, 16, 0), Tag = "18", VerticalAlignment = VerticalAlignment.Center,
            Background = primary ? (Brush)Application.Current.FindResource("PulsQuer") : done ? Ui.Brush("#10261C") : Ui.Brush("#140C1D"),
            BorderBrush = done ? Ui.Alpha(Gruen, "33") : Ui.Res("KarteRand"), BorderThickness = new Thickness(primary ? 0 : 1),
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            Content = Ui.Text(label, 12.5, done && !state.Busy ? Gruen : "Text", bold: true), IsEnabled = available && !state.Busy, Opacity = available ? 1 : 0.5 };
        button.Click += (_, _) => Start(key, t);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        // nach dem Sichern: Ordner zeigen
        if (t.Name == "Treiber sichern" && done && Werkzeuglauf.BackupFolders().FirstOrDefault() is { } last)
        {
            var show = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(14, 0, 14, 0), Tag = "18", Margin = new Thickness(0, 0, 8, 0),
                Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalContentAlignment = VerticalAlignment.Center,
                Content = Ui.Text("Ordner zeigen", 12.5, "Halbleise") };
            show.Click += (_, _) => { try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + last.FullName + ".zip\"") { UseShellExecute = true }); } catch (Exception) { } };
            actions.Children.Add(show);
        }
        actions.Children.Add(button);
        // Ergebnis auf- und zuklappen: Pfeil rechts neben dem Knopf, ein Klick auf die Kopfzeile tut dasselbe
        var open = result != null && !Collapsed.Contains(key);
        if (result != null)
        {
            var chevron = new Path { Data = Geometry.Parse(open ? "M6 15l6-6 6 6" : "M6 9l6 6 6-6"), Stroke = Ui.Res("Halbleise"), StrokeThickness = 2, Width = 24, Height = 24, Stretch = Stretch.None,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round, LayoutTransform = new ScaleTransform(0.7, 0.7) };
            var toggle = new Button { Style = (Style)Application.Current.FindResource("Flach"), Width = 36, Height = 36, Tag = "18", Margin = new Thickness(8, 0, 0, 0),
                Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), ToolTip = open ? "Ergebnis zuklappen" : "Ergebnis zeigen",
                HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = chevron };
            System.Windows.Automation.AutomationProperties.SetName(toggle, open ? "Ergebnis zuklappen" : "Ergebnis zeigen");
            toggle.Click += (_, _) => Toggle(key);
            actions.Children.Add(toggle);
            grid.Background = Brushes.Transparent;
            grid.Cursor = System.Windows.Input.Cursors.Hand;
            grid.MouseLeftButtonUp += (_, e) => { if (e.OriginalSource is DependencyObject d && FindButton(d) == null) Toggle(key); };
        }
        Grid.SetColumn(actions, 3);
        grid.Children.Add(actions);
        var body = new StackPanel();
        body.Children.Add(grid);
        if (open) body.Children.Add(Details(a, t, key, result!, state.Busy));
        return new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(18), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"),
            Padding = new Thickness(20, 0, 18, 0), Margin = new Thickness(0, 0, 0, 10), Child = body };
    }

    static Button Small(string label, bool primary, bool enabled)
    {
        return new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 34, Padding = new Thickness(14, 0, 14, 0), Tag = "17", Margin = new Thickness(0, 0, 8, 8),
            Background = primary ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(primary ? 0 : 1),
            VerticalContentAlignment = VerticalAlignment.Center, IsEnabled = enabled, Opacity = enabled ? 1 : 0.5,
            Content = new TextBlock { Text = label, FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Ui.Res("Text"), TextWrapping = TextWrapping.Wrap, MaxWidth = 420 } };
    }

    // kleiner Umschalter wie der Boost-Schalter der Startseite: an = Verlauf, aus = dunkel mit Knopf links
    static Button Switch(bool on, bool enabled, string name)
    {
        var knob = new Ellipse { Width = 16, Height = 16, Fill = Brushes.White, Opacity = on ? 1 : 0.7 };
        Canvas.SetTop(knob, 3);
        Canvas.SetLeft(knob, on ? 19 : 3);
        var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Width = 38, Height = 22, Tag = "11", Margin = new Thickness(12, 0, 0, 0),
            Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#2A2036"), BorderThickness = new Thickness(0),
            IsEnabled = enabled, Opacity = enabled ? 1 : 0.5, Content = new Canvas { Width = 38, Height = 22, Children = { knob } }, ToolTip = name };
        System.Windows.Automation.AutomationProperties.SetName(b, name);
        return b;
    }

    static Border Counter(string text, string color)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = Ui.Brush(color), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        row.Children.Add(Ui.Text(text, 12, color, bold: true));
        return new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 12, 5), Margin = new Thickness(0, 0, 6, 0), Background = Ui.Alpha(color, "14"),
            BorderBrush = Ui.Alpha(color, "2E"), BorderThickness = new Thickness(1), Child = row };
    }

    // Ergebnis der Prüfung: Zähler und Zusammenfassung, die Prüfpunkte als Liste, was die Schritte gemeldet haben, und die Knöpfe
    FrameworkElement Details(Absicht a, Werkzeug t, string key, Werkbefund r, bool busy)
    {
        var panel = new StackPanel { Margin = new Thickness(20, 4, 0, 18) };
        // Kopf: Ampel-Zähler (grün / zu prüfen), darunter die Zusammenfassung über die ganze Breite
        var good = r.Lines.Count(l => l.Ok);
        var todo = r.Lines.Count - good;
        var counters = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        if (todo > 0) counters.Children.Add(Counter(todo + " zu prüfen", Bernstein));
        if (good > 0) counters.Children.Add(Counter(good + " in Ordnung", Gruen));
        if (counters.Children.Count > 0) panel.Children.Add(counters);
        if (r.Summary.Length > 0)
            panel.Children.Add(new TextBlock { Text = r.Summary, FontSize = 12.5, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 19, Margin = new Thickness(0, 0, 8, 14) });

        // eine ruhige Liste in einem Rahmen: was zu prüfen ist zuerst, je Zeile Zeichen, Name, Zustand rechts und die
        // Erklärung darunter; feine Linien trennen die Zeilen
        var list = new StackPanel();
        var lines = r.Lines.OrderBy(l => l.Ok).ToList();
        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            var color = line.Ok ? Gruen : Bernstein;
            var row = new Grid { Margin = new Thickness(0, 12, 0, 12) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var mark = new Border { Width = 24, Height = 24, CornerRadius = new CornerRadius(12), Background = Ui.Alpha(color, "1F"), VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Left,
                Child = new TextBlock { Text = line.Ok ? "✓" : "!", FontSize = 12.5, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(color), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
            Grid.SetRowSpan(mark, 2);
            row.Children.Add(mark);
            var parts = line.Label.Split(" · ", 2);
            var name = new TextBlock { Text = parts[0], FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = Ui.Res("Text"), TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 2, 12, 0) };
            Grid.SetColumn(name, 1);
            row.Children.Add(name);
            if (parts.Length > 1)
            {
                var state = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 3, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Top,
                    Child = new TextBlock { Text = parts[1], FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = Ui.Brush(color), MaxWidth = 220, TextTrimming = TextTrimming.CharacterEllipsis } };
                Grid.SetColumn(state, 2);
                row.Children.Add(state);
            }
            // die Aktion steht an der Zeile selbst: ein Schalter (wirkt sofort) oder ein Knopf (fragt vorher)
            if (line.Step is { } step)
            {
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                FrameworkElement control;
                if (line.On is { } on)
                {
                    var sw = Switch(on, !busy, step.Text);
                    sw.Click += (_, _) => Run(t, key, step.Text + "?", new[] { step });
                    control = sw;
                }
                else
                {
                    var b = Small(line.Button.Length > 0 ? line.Button : step.Text, false, !busy);
                    b.Margin = new Thickness(0);
                    b.Height = 30;
                    b.Click += (_, _) => Run(t, key, step.Text + "?", new[] { step });
                    control = b;
                }
                control.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetColumn(control, 3);
                Grid.SetRowSpan(control, 2);
                row.Children.Add(control);
            }
            if (line.Detail.Length > 0)
            {
                var detail = new TextBlock { Text = line.Detail, FontSize = 12.5, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 19, Margin = new Thickness(0, 5, 0, 0) };
                Grid.SetColumn(detail, 1);
                Grid.SetColumnSpan(detail, 2);
                Grid.SetRow(detail, 1);
                row.Children.Add(detail);
            }
            list.Children.Add(new Border { BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(0, i == 0 ? 0 : 1, 0, 0), Child = row });
        }
        panel.Children.Add(new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#06FFFFFF"), BorderBrush = Ui.Brush("#1F1729"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 2, 16, 2), Margin = new Thickness(0, 0, 8, 10), Child = list });

        var log = Werkzeuglauf.Log.GetValueOrDefault(key) ?? new();
        if (log.Count > 0)
        {
            var box = new StackPanel();
            foreach (var entry in log)
            {
                var ok = entry.StartsWith('✓');
                var line = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
                var dot = new Ellipse { Width = 7, Height = 7, Fill = Ui.Brush(ok ? Gruen : Bernstein), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 5, 10, 0) };
                DockPanel.SetDock(dot, Dock.Left);
                line.Children.Add(dot);
                line.Children.Add(new TextBlock { Text = entry.TrimStart('✓', '✕', ' '), FontSize = 12, Foreground = Ui.Res(ok ? "Halbleise" : "Text"), TextWrapping = TextWrapping.Wrap });
                box.Children.Add(line);
            }
            panel.Children.Add(new Border { CornerRadius = new CornerRadius(14), Background = Ui.Brush("#0A5EE0A0"), BorderBrush = Ui.Alpha(Gruen, "1F"), BorderThickness = new Thickness(1),
                Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 2, 8, 8), Child = box });
        }
        var buttons = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        var main = r.Steps.Where(s => !s.Optional).ToList();
        // nur der Wiederherstellungspunkt allein ist keine Reparatur
        if (main.Any(s => s.Text != "Wiederherstellungspunkt anlegen"))
        {
            var fix = Small(main.Count(s => s.Text != "Wiederherstellungspunkt anlegen") == 1 ? main.Last().Text : "Beheben (" + main.Count(s => s.Text != "Wiederherstellungspunkt anlegen") + " Schritte)", true, !busy);
            fix.Click += (_, _) => Run(t, key, r.Question, main);
            buttons.Children.Add(fix);
        }
        foreach (var step in r.Steps.Where(s => s.Optional))
        {
            var b = Small(step.Text, false, !busy);
            b.Click += (_, _) => Run(t, key, step.Text + "?", new[] { step });
            buttons.Children.Add(b);
        }
        if (buttons.Children.Count > 0) panel.Children.Add(buttons);
        return panel;
    }

    // Rückfrage mit allen geplanten Schritten, dann ausführen; ändernde Schritte nur mit Adminrechten. Ohne Frage nur,
    // was eine Seite von Windows öffnet oder sich sofort zurücknehmen lässt (Autostart, Aufzeichnung)
    void Run(Werkzeug t, string key, string question, IReadOnlyList<Schritt> steps)
    {
        var changes = steps.Any(s => s.Admin) && !(t.Bridge is "SystemInfo" or "OfflinePackage");
        if (changes && !App.IsAdmin) { Bestaetigung.Ask(this, "Adminrechte nötig", "Diese Schritte ändern etwas am System – dafür muss PulsRig als Administrator laufen.", "Verstanden"); return; }
        var plan = string.Join("\n", steps.Select(s => "• " + s.Text));
        if (steps.All(s => !s.Ask) || Bestaetigung.Ask(this, question, "Geplante Schritte:\n" + plan, "Ausführen")) Werkzeuglauf.Execute(key, t.Bridge!, steps);
    }

    void Start(string key, Werkzeug t)
    {
        if (t.Page != null) { window.Go(t.Page); return; }
        if (t.Bridge != null)
        {
            foreach (var other in Werkzeuglauf.Results.Keys) Collapsed.Add(other);
            Collapsed.Remove(key);
            Werkzeuglauf.Check(key, t.Bridge);
            return;
        }
        if (t.Name == "Treiber sichern")
        {
            if (Bestaetigung.Ask(this, "Alle Treiber sichern?", "PulsRig exportiert alle Treiber von Drittherstellern in einen Ordner und packt ihn als ZIP-Datei daneben. Das kann einige Minuten dauern; am System ändert sich nichts.", "Sichern"))
                Werkzeuglauf.Backup(key);
            return;
        }
        if (t.Name == "Treiber zurückholen")
        {
            if (!App.IsAdmin) { Bestaetigung.Ask(this, "Adminrechte nötig", "Zum Einspielen muss PulsRig als Administrator laufen.", "Verstanden"); return; }
            var folder = Werkzeuglauf.BackupFolders().FirstOrDefault();
            if (folder == null) { Bestaetigung.Ask(this, "Keine Sicherung", "Es gibt noch keine Sicherung. Lege zuerst mit „Treiber sichern“ eine an – vor Updates sichert PulsRig ersetzte Treiber auch selbst.", "Verstanden"); return; }
            if (Bestaetigung.Ask(this, "Sicherung einspielen?", "Neueste Sicherung: " + folder.Name + " vom " + folder.LastWriteTime.ToString("dd.MM.yyyy HH:mm") + " Uhr. Windows übernimmt daraus nur Treiber, die besser passen als die installierten – um ein Update zurückzunehmen, hilft der Wiederherstellungspunkt.", "Einspielen"))
                Werkzeuglauf.Restore(key, folder);
        }
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Werkzeuglauf.Changed -= Fill;
        Treiberscan.Changed -= Fill;
    }
}
