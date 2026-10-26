using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using PulsRig.Core;

namespace PulsRig.App;

// Optionen nach dem Entwurf: Aussehen, Sprache, Bewegung, Überwachung (Helfer neben der Uhr) und Schnellzugriff.
// Gespeichert wird in den Einstellungen des PowerShell-Programms, damit beide Programme und der Helfer dasselbe lesen.
sealed class OptionenPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Gruen = "#5EE0A0";

    readonly MainWindow window;
    readonly Grid root = Ui.Mosaic(3, 3, 12);
    string helperStatus = "";
    bool stopped, shown;
    static readonly System.Diagnostics.Stopwatch Pulse = System.Diagnostics.Stopwatch.StartNew();

    public OptionenPage(MainWindow window)
    {
        this.window = window;
        Content = root;
        Fill();
        ReadHelper();
    }

    // schtasks braucht einen Moment: der Zustand des Helfers kommt nach
    void ReadHelper() => Task.Run(() =>
    {
        var text = "";
        try { text = Helfer.Status(); } catch (Exception) { }
        Dispatcher.BeginInvoke(() => { helperStatus = text; Fill(); });
    });

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        var tiles = new List<UIElement>();
        void Put(UIElement e, int c, int r, int cs = 1, int rs = 1) { Ui.Place(root, e, c, r, cs, rs); tiles.Add(e); }
        Put(Look(), 0, 0, 2);
        Put(Language(), 2, 0);
        Put(Motion(), 0, 1, 2);
        Put(Watch(), 2, 1, 1, 2);
        Put(Quick(), 0, 2, 2);
        // einblenden nur beim Öffnen; ein Klick oder der nachgereichte Zustand des Helfers baut die Seite neu, und
        // jedes neue Einblenden ließ alle Kacheln zucken
        if (!shown) Ui.Arrive(tiles);
        shown = true;
    }

    static Border Section(string title, string color, string tint, UIElement body, string right = "")
    {
        var panel = new DockPanel();
        var head = new DockPanel();
        if (right.Length > 0) { var r = Ui.Text(right, 11, "Leise", mono: true); DockPanel.SetDock(r, Dock.Right); head.Children.Add(r); }
        head.Children.Add(Ui.Text(title, 12.5, color, bold: true));
        DockPanel.SetDock(head, Dock.Top);
        panel.Children.Add(head);
        panel.Children.Add(body);
        var tile = Ui.Tile(color, tint, new Thickness(18, 16, 18, 16));
        tile.CornerRadius = new CornerRadius(22);
        tile.Child = panel;
        return tile;
    }

    static Button Flat(object content, double height, string bg, string edge, double radius = 12)
    {
        return new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = height, Tag = radius.ToString(), Content = content,
            Background = bg.Length == 0 ? Brushes.Transparent : bg.StartsWith("Puls") ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush(bg),
            BorderBrush = edge.Length > 0 ? Ui.Brush(edge) : Brushes.Transparent, BorderThickness = new Thickness(edge.Length > 0 ? 1 : 0), HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Center };
    }

    // nur Reihe Q (Nacht-Bento); weitere Designs kommen später
    Border Look()
    {
        var grid = new UniformGrid2(2, 10) { Margin = new Thickness(0, 10, 0, 0) };
        grid.Add(LookCard("Nacht-Bento", "Reihe Q · Lila-Nacht", true));
        grid.Add(LookCard("Weitere Designs", "kommen später", false));
        return Section("Aussehen", Lila, "#160D29", grid);
    }

    static Border LookCard(string name, string sub, bool on)
    {
        var row = new DockPanel { VerticalAlignment = VerticalAlignment.Center };
        var preview = new Grid { Width = 62, Height = 44, Margin = new Thickness(0, 0, 12, 0) };
        preview.Children.Add(new Border { CornerRadius = new CornerRadius(8), Background = on ? new LinearGradientBrush(Ui.Hex("#160D29"), Ui.Hex("#09060D"), 60) : Ui.Brush("#0C0A10") });
        if (on)
        {
            var cells = Ui.Mosaic(2, 2, 3);
            cells.Margin = new Thickness(16, 5, 5, 5);
            Ui.Place(cells, new Border { CornerRadius = new CornerRadius(3), Background = Ui.Brush("#6D43C9") }, 0, 0);
            Ui.Place(cells, new Border { CornerRadius = new CornerRadius(3), Background = Ui.Brush("#10FFFFFF") }, 1, 0);
            Ui.Place(cells, new Border { CornerRadius = new CornerRadius(3), Background = Ui.Brush("#10FFFFFF") }, 0, 1);
            Ui.Place(cells, new Border { CornerRadius = new CornerRadius(3), Background = Ui.Brush("#A8326F") }, 1, 1);
            preview.Children.Add(new Border { Width = 8, CornerRadius = new CornerRadius(2), Background = Ui.Brush("#14FFFFFF"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(5) });
            preview.Children.Add(cells);
        }
        DockPanel.SetDock(preview, Dock.Left);
        row.Children.Add(preview);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(name, 13.5, on ? "Text" : "Leise", bold: true));
        var s = Ui.Text(sub, 11.5, "Leise");
        s.Margin = new Thickness(0, 2, 0, 0);
        text.Children.Add(s);
        row.Children.Add(text);
        return new Border { CornerRadius = new CornerRadius(14), Padding = new Thickness(12, 10, 12, 10), BorderThickness = new Thickness(1),
            BorderBrush = Ui.Brush(on ? "#6D43C9" : "#22172F"), Background = Ui.Brush(on ? "#140C1D" : "#04FFFFFF"), Child = row };
    }

    // wie Set-AppLanguage: speichern und das Fenster neu starten - die Texte kommen beim Start
    Border Language()
    {
        var list = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
        var current = Texte.IsEnglish ? "en" : "de";
        foreach (var (code, name) in new[] { ("de", "Deutsch"), ("en", "English") })
        {
            var on = code == current;
            var row = new DockPanel { Margin = new Thickness(14, 0, 14, 0) };
            var mark = Ui.Text(on ? "●" : "", 13, Beere);
            DockPanel.SetDock(mark, Dock.Right);
            row.Children.Add(mark);
            row.Children.Add(Ui.Text(name, 13, on ? "#FFFFFF" : "#B3A8C4", bold: true));
            var b = Flat(row, 36, on ? "#1B0916" : "", on ? "#66A8326F" : "#22172F");
            b.Margin = new Thickness(0, 6, 0, 0);
            b.Click += (_, _) =>
            {
                if (on) return;
                Altdaten.Change(s => s["Language"] = code);
                window.Restart();
            };
            list.Children.Add(b);
        }
        return Section("Sprache", Beere, "#1F0A19", list);
    }

    Border Motion()
    {
        var body = new DockPanel();
        // Pulslinie, die im gewählten Tempo läuft
        var line = new Path { Data = Geometry.Parse("M0 17 H200 l10 -10 l14 24 l12 -20 l8 6 H600"), Stroke = Ui.Brush(Lila), StrokeThickness = 2.4, Stretch = Stretch.Fill, Height = 30,
            Margin = new Thickness(0, 8, 0, 0), Effect = Ui.Glow("#6D43C9", 8), StrokeDashArray = new DoubleCollection { 60, 400 }, StrokeDashCap = PenLineCap.Round };
        if (!Bewegung.Off)
        {
            // die Seite baut beim Schalten neu: an der Stelle weiterlaufen, an der die Linie gerade ist, statt von vorn
            var period = TimeSpan.FromSeconds(2.4 / Bewegung.Speed);
            var phase = TimeSpan.FromTicks(Pulse.Elapsed.Ticks % period.Ticks);
            line.BeginAnimation(Shape.StrokeDashOffsetProperty, new System.Windows.Media.Animation.DoubleAnimation(460, 0, period)
                { RepeatBehavior = System.Windows.Media.Animation.RepeatBehavior.Forever, BeginTime = -phase });
        }
        DockPanel.SetDock(line, Dock.Top);
        body.Children.Add(line);
        var pick = new Grid { VerticalAlignment = VerticalAlignment.Bottom };
        var levels = new[] { "Aus", "Ruhig", "Normal", "Lebendig" };
        for (var i = 0; i < levels.Length; i++)
        {
            pick.ColumnDefinitions.Add(new ColumnDefinition());
            var level = levels[i];
            var on = Bewegung.Level == level;
            var label = Ui.Text(level, 12.5, on ? "#FFFFFF" : "Leise", bold: true);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            var b = Flat(label, 32, on ? "PulsQuer" : "", "", 10);
            b.Margin = new Thickness(3);
            b.Click += (_, _) => { Bewegung.Set(level); Fill(); };
            Grid.SetColumn(b, i);
            pick.Children.Add(b);
        }
        var frame = new Border { CornerRadius = new CornerRadius(14), Padding = new Thickness(1), Background = Ui.Brush("#06FFFFFF"), BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(1),
            Child = pick, VerticalAlignment = VerticalAlignment.Bottom };
        body.Children.Add(frame);
        var note = Bewegung.Level switch { "Aus" => "keine Animationen", "Ruhig" => "langsamer, weniger Glühen", "Lebendig" => "schneller, mehr Glühen", _ => "Standard" };
        return Section("Bewegung", Lila, "#130B24", body, note);
    }

    // die Schalter, die der Helfer liest; der erste richtet ihn selbst ein
    Border Watch()
    {
        var settings = Altdaten.Settings();
        var list = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        var helper = Altdaten.Flag(settings, "Helper", false);
        list.Children.Add(Switch("Helfer neben der Uhr", helperStatus.Length > 0 ? helperStatus : "startet mit Windows, leise im Infobereich", helper, Helfer.Exe != null, on =>
        {
            try { Helfer.Set(on); } catch (Exception) { }
            ReadHelper();
        }));
        foreach (var (key, name, sub, fallback) in new[]
        {
            ("WeeklyScan", "Neue Treiber melden", "der Helfer sieht einmal pro Woche nach", true),
            ("AutoBoost", "Boost automatisch", "bei den Boost-Spielen, braucht den Helfer mit Adminrechten", false),
            ("RecordGames", "Temperaturen aufzeichnen", "beim Spielen, für den Verlauf je Spiel", true),
        })
            list.Children.Add(Switch(name, sub, Altdaten.Flag(settings, key, fallback), helper, on => { Altdaten.Change(s => s[key] = on); Fill(); }));
        // gilt ohne Helfer: das Programm sieht beim Start nach
        list.Children.Add(Switch("Nach neuer Fassung sehen", "beim Start einmal bei GitHub, geladen wird nur auf Knopfdruck", Altdaten.Flag(settings, "UpdateCheck", true), true, on => { Altdaten.Change(s => s["UpdateCheck"] = on); Fill(); }));
        var note = new TextBlock { Text = Helfer.Exe == null ? "Den Helfer gibt es nur im installierten Programm." : "Die Schalter des Helfers wirken, solange er läuft.",
            FontSize = 11, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) };
        list.Children.Add(note);
        return Section("Überwachung", Gruen, "#10291F", list);
    }

    static Button Switch(string name, string sub, bool on, bool enabled, Action<bool> flip)
    {
        var row = new DockPanel { Margin = new Thickness(0, 10, 0, 10) };
        var track = new Border { Width = 38, Height = 22, CornerRadius = new CornerRadius(11), Background = Ui.Brush(on ? Gruen : "#1FFFFFFF"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0),
            Child = new Ellipse { Width = 16, Height = 16, Fill = Brushes.White, HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, Margin = new Thickness(3, 0, 3, 0) } };
        DockPanel.SetDock(track, Dock.Right);
        row.Children.Add(track);
        var text = new StackPanel();
        text.Children.Add(Ui.Text(name, 13, "Text", bold: true));
        var s = new TextBlock { Text = sub, FontSize = 11, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) };
        text.Children.Add(s);
        row.Children.Add(text);
        var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Content = new Border { BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(0, 0, 0, 1), Child = row },
            Background = Brushes.Transparent, HorizontalContentAlignment = HorizontalAlignment.Stretch, IsEnabled = enabled, Opacity = enabled ? 1 : 0.5, Tag = "0" };
        System.Windows.Automation.AutomationProperties.SetName(b, name);
        b.Click += (_, _) => flip(!on);
        return b;
    }

    Border Quick()
    {
        var grid = new Grid { VerticalAlignment = VerticalAlignment.Bottom };
        var items = new (string Name, string Icon, Action Do)[]
        {
            ("Treiberverlauf", "M12 8v4l3 2 M3 12a9 9 0 1 0 3-6.7 M3 4v4h4", () => { window.GoTop("tools"); window.Go("manage"); }),
            ("Zielordner", "M3 6h6l2 2h10v11H3z", () => { try { System.IO.Directory.CreateDirectory(Werkzeuglauf.Backups); Process.Start(new ProcessStartInfo("explorer.exe", "\"" + Werkzeuglauf.Backups + "\"") { UseShellExecute = true }); } catch (Exception) { } }),
            ("Kurzanleitung", "M4 4h7a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4z M20 4h-4a2 2 0 0 0-2 2", () => Bestaetigung.Ask(this, "PulsRig in Kürze",
                "Scan: fragt Windows Update, NVIDIA, AMD und den Microsoft-Katalog nach neueren Treibern; installiert wird nur nach Rückfrage, vorher entsteht ein Wiederherstellungspunkt.\n\n" +
                "Boost: schafft vor dem Spielen Platz. Ein zweiter Klick stellt alles zurück.\n\n" +
                "Werkzeuge: jedes prüft zuerst nur und fragt, bevor es etwas ändert.\n\n" +
                "Hardware: Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher und Bericht & Diagnose.", "Verstanden")),
            ("Über PulsRig", "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18 M12 11v5 M12 8h.01", () => Bestaetigung.About(this)),
        };
        for (var i = 0; i < items.Length; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var (name, icon, act) = items[i];
            var inner = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
            inner.Children.Add(new Path { Data = Geometry.Parse(icon), Stroke = Ui.Brush(Lila), StrokeThickness = 2, Width = 24, Height = 24, Stretch = Stretch.None, StrokeLineJoin = PenLineJoin.Round,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, LayoutTransform = new ScaleTransform(17 / 24.0, 17 / 24.0), HorizontalAlignment = HorizontalAlignment.Center });
            var t = Ui.Text(name, 12, "Text", bold: true);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            t.Margin = new Thickness(0, 5, 0, 0);
            inner.Children.Add(t);
            var b = Flat(inner, 54, "#140C1D", "#22172F", 14);
            b.Margin = new Thickness(i == 0 ? 0 : 4, 0, i == items.Length - 1 ? 0 : 4, 0);
            b.Click += (_, _) => act();
            Grid.SetColumn(b, i);
            grid.Children.Add(b);
        }
        var tile = Section("Schnellzugriff", "#B3A8C4", "#0B0710", grid, "PulsRig " + PulsRigInfo.Version.ToLowerInvariant());
        tile.Background = Ui.Brush("#0B0710");
        tile.BorderBrush = Ui.Brush("#22172F");
        return tile;
    }

    public void Stop() => stopped = true;
}

// zwei gleich breite Spalten mit Abstand
sealed class UniformGrid2 : Grid
{
    readonly double gap;
    public UniformGrid2(int columns, double gap)
    {
        this.gap = gap;
        for (var i = 0; i < columns; i++) ColumnDefinitions.Add(new ColumnDefinition());
    }

    public void Add(FrameworkElement e)
    {
        var i = Children.Count;
        SetColumn(e, i % ColumnDefinitions.Count);
        e.Margin = new Thickness(i % ColumnDefinitions.Count == 0 ? 0 : gap / 2, 0, i % ColumnDefinitions.Count == ColumnDefinitions.Count - 1 ? 0 : gap / 2, 0);
        Children.Add(e);
    }
}
