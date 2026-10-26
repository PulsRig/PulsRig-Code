using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Stromverbrauch wie PulsRig-Strom.ps1: Watt der Teile aus der Messschleife (Live), Kosten aus dem Mittel seit dem
// Öffnen, Strompreis und Nutzung am Tag in den gemeinsamen Einstellungen, dazu der FPS-Limit-Vergleich: PulsRig stellt
// kein Limit um; es misst nach 10 s Vorlauf eine halbe Minute im Spiel, einmal ohne und einmal mit Limit.
sealed class StromPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";
    const int Lead = 10, Span = 30;

    sealed class Lauf { public string Kind = ""; public DateTime Start, End; public double Sum; public int Count; public bool GpuGuessed; }

    // Ergebnisse des Vergleichs bleiben bis zum Beenden des Programms, wie $script:PowerLimit
    static readonly Dictionary<string, (double Watt, bool GpuGuessed, DateTime Time)> Limit = new();
    static Lauf? run;

    readonly Grid root = Ui.Mosaic(4, 3, 12);
    readonly System.Windows.Threading.DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    Stromteile? last;
    double sum;
    int count;
    bool stopped;

    public StromPage()
    {
        Content = root;
        Live.Use();
        Live.Updated += Measured;
        // nicht mitten in einem Klick neu aufbauen: sonst geht er verloren
        timer.Tick += (_, _) => { Finish(); if (System.Windows.Input.Mouse.LeftButton != System.Windows.Input.MouseButtonState.Pressed) Fill(); };
        timer.Start();
        Fill();
    }

    static double Price => Altdaten.Settings()["PowerPrice"] is System.Text.Json.Nodes.JsonValue v && v.TryGetValue<double>(out var p) ? p : 0.35;
    static int Setting(string key, int fallback) => Altdaten.Settings()[key] is System.Text.Json.Nodes.JsonValue v && v.TryGetValue<int>(out var n) ? n : fallback;

    void Measured()
    {
        last = Strom.Parts(Live.Get("GpuPower"), Live.Get("CpuPower"), Live.Get("CpuLoad"));
        sum += last.Total;
        count++;
        if (run != null && DateTime.Now >= run.Start) { run.Sum += last.Total; run.Count++; if (!last.GpuMeasured) run.GpuGuessed = true; }
    }

    static void Finish()
    {
        if (run == null || DateTime.Now < run.End) return;
        if (run.Count > 0) Limit[run.Kind] = (run.Sum / run.Count, run.GpuGuessed, run.End);
        run = null;
    }

    static string W(double w) => w.ToString("N0", Ui.De) + " W";

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        var p = last;
        var price = Price;
        var hours = Setting("PowerHours", 4);

        // links groß: zusammen und Kosten
        var main = new StackPanel();
        main.Children.Add(Ui.Text("STROMVERBRAUCH", 10, "Leise", mono: true));
        var total = Ui.Text(p == null ? "–" : W(p.Total), 44, "Text", bold: true, mono: true);
        total.Margin = new Thickness(0, 14, 0, 0);
        main.Children.Add(total);
        main.Children.Add(Wrap(p == null ? "Warte auf den ersten Messwert …" : "zusammen, mit dem Verlust im Netzteil · " + (p.Total / 1000.0 * price * 100).ToString("N1", Ui.De) + " Cent pro Stunde", "Halbleise"));
        var average = sum / Math.Max(1, count);
        var year = Ui.Text(count == 0 ? "–" : Strom.YearEuro(average, hours, price).ToString("N0", Ui.De) + " € im Jahr", 26, Lila, bold: true);
        year.Margin = new Thickness(0, 26, 0, 0);
        main.Children.Add(year);
        main.Children.Add(Wrap(count == 0 ? "" : "Im Mittel " + W(average) + " · " + (average / 1000.0 * hours * price).ToString("N2", Ui.De) + " € am Tag bei " + hours + " Std.", "Leise"));
        main.Children.Add(Wrap("Schätzung – ein Messgerät an der Steckdose ist genauer.", "Leise", 24));
        Ui.Place(root, Tile(main, Lila, "#160D29"), 0, 0, 2, 2);

        Ui.Place(root, Part("Grafikkarte", p?.Gpu, p == null ? "" : p.GpuMeasured ? "gemessen · " + (Live.Values["GpuName"] as string ?? Hw.Gpu?.Name ?? "") : "geschätzt: keine NVIDIA-Grafikkarte, deren Verbrauch PulsRig messen kann", Lila, "#160D29"), 2, 0);
        Ui.Place(root, Part("Prozessor", p?.Cpu, p == null ? "" : p.CpuMeasured ? "gemessen über LibreHardwareMonitor" : "geschätzt aus " + p.Load.ToString("N0", Ui.De) + " % Auslastung × " + Strom.CpuRated + " W Nennleistung", Beere, "#1F0A19"), 3, 0);
        Ui.Place(root, Part("Mainboard, Speicher, Laufwerke, Lüfter", Strom.Rest, "pauschal geschätzt", "#5E4BB8", "#130B24"), 2, 1);

        // Strompreis − / +
        var priceRow = new StackPanel();
        priceRow.Children.Add(Ui.Text("Strompreis", 12.5, Bernstein, bold: true));
        var value = Ui.Text(price.ToString("N2", Ui.De) + " €/kWh", 20, "Text", bold: true);
        value.Margin = new Thickness(0, 6, 0, 0);
        priceRow.Children.Add(value);
        var steps = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        foreach (var (label, step) in new[] { ("–", -0.01), ("+", 0.01) })
        {
            var b = Chip(label, false);
            b.Click += (_, _) => { var n = Math.Round(Math.Clamp(Price + step, 0.05, 1.5), 2); Altdaten.Change(s => s["PowerPrice"] = n); Fill(); };
            steps.Children.Add(b);
        }
        priceRow.Children.Add(steps);
        priceRow.Children.Add(Wrap("Arbeitspreis je kWh, steht auf der Stromrechnung", "Leise", 8));
        Ui.Place(root, Tile(priceRow, Bernstein, "#2A2112"), 3, 1);

        // Nutzung am Tag
        var use = new StackPanel();
        use.Children.Add(Ui.Text("Nutzung am Tag", 12.5, Gruen, bold: true));
        use.Children.Add(Wrap("So lange läuft der PC im Schnitt", "Leise", 4));
        var chips = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        foreach (var h in new[] { 2, 4, 8, 12 })
        {
            var b = Chip(h + " Std.", h == hours);
            b.Click += (_, _) => { Altdaten.Change(s => s["PowerHours"] = h); Fill(); };
            chips.Children.Add(b);
        }
        use.Children.Add(chips);
        Ui.Place(root, Tile(use, Gruen, "#10291F"), 0, 2);

        Ui.Place(root, LimitTile(price), 1, 2, 3);
    }

    // FPS-Limit-Vergleich wie Update-PowerLimit
    Border LimitTile(double price)
    {
        var gameHours = Setting("GameHours", 2);
        var grid = new Grid();
        for (var i = 0; i < 3; i++) grid.ColumnDefinitions.Add(new ColumnDefinition());
        var now = DateTime.Now;
        var col = 0;
        foreach (var (kind, name) in new[] { ("Off", "Ohne FPS-Limit"), ("On", "Mit FPS-Limit") })
        {
            var box = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
            box.Children.Add(Ui.Text(name, 12.5, Beere, bold: true));
            string big = "–", note;
            if (run?.Kind == kind)
            {
                big = "…";
                note = now < run.Start ? "Jetzt ins Spiel wechseln – Messung beginnt in " + Math.Ceiling((run.Start - now).TotalSeconds) + " s" : "Misst im Spiel … noch " + Math.Ceiling((run.End - now).TotalSeconds) + " s";
            }
            else if (Limit.TryGetValue(kind, out var r))
            {
                big = W(r.Watt);
                note = r.GpuGuessed ? "Gemessen um " + r.Time.ToString("HH:mm") + " – Grafikkarte nur geschätzt, der Vergleich sagt so wenig" : "Gemessen um " + r.Time.ToString("HH:mm") + ", Mittel über " + Span + " s im Spiel";
            }
            else note = kind == "Off" ? "Spiel ohne Limit starten, hier „Messen“ und ins Spiel wechseln" : "Limit im Spiel oder Treiber setzen, dann erneut messen";
            var v = Ui.Text(big, 20, "Text", bold: true);
            v.Margin = new Thickness(0, 4, 0, 0);
            box.Children.Add(v);
            box.Children.Add(Wrap(note, "Leise", 2));
            var measure = Chip("Messen", false);
            measure.Margin = new Thickness(0, 8, 0, 0);
            measure.HorizontalAlignment = HorizontalAlignment.Left;
            measure.IsEnabled = run == null;
            measure.Click += (_, _) => { var start = DateTime.Now.AddSeconds(Lead); run = new Lauf { Kind = kind, Start = start, End = start.AddSeconds(Span) }; Fill(); };
            box.Children.Add(measure);
            Grid.SetColumn(box, col++);
            grid.Children.Add(box);
        }
        var saving = new StackPanel();
        saving.Children.Add(Ui.Text("Ersparnis durch das FPS-Limit", 12.5, Lila, bold: true));
        string value = "–", text = "Erst ohne, dann mit Limit messen";
        if (Limit.TryGetValue("Off", out var off) && Limit.TryGetValue("On", out var on))
        {
            var diff = off.Watt - on.Watt;
            if (diff < 1) { value = "0 €"; text = "Kein Unterschied gemessen – das Limit greift wohl nicht oder liegt über der erreichten Bildrate"; }
            else { value = Strom.YearEuro(diff, gameHours, price).ToString("N0", Ui.De) + " € im Jahr"; text = W(diff) + " weniger (" + (diff / off.Watt * 100).ToString("N0", Ui.De) + " %) bei " + gameHours + " Std. Spielen am Tag"; }
        }
        var sv = Ui.Text(value, 20, Lila, bold: true);
        sv.Margin = new Thickness(0, 4, 0, 0);
        saving.Children.Add(sv);
        saving.Children.Add(Wrap(text, "Leise", 2));
        var hours = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        foreach (var h in new[] { 1, 2, 4, 6 })
        {
            var b = Chip(h + " Std.", h == gameHours);
            b.Click += (_, _) => { Altdaten.Change(s => s["GameHours"] = h); Fill(); };
            hours.Children.Add(b);
        }
        saving.Children.Add(hours);
        Grid.SetColumn(saving, 2);
        grid.Children.Add(saving);
        return Tile(grid, Beere, "#1B0916");
    }

    static TextBlock Wrap(string text, string color, double top = 6) => new() { Text = text, FontSize = 12, Foreground = Ui.Res(color), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, top, 0, 0), LineHeight = 17 };

    static Border Tile(UIElement child, string color, string tint)
    {
        var t = Ui.Tile(color, tint, new Thickness(18, 16, 18, 16));
        t.CornerRadius = new CornerRadius(22);
        t.Child = child;
        return t;
    }

    static Border Part(string title, double? watt, string note, string color, string tint)
    {
        var s = new DockPanel();
        var head = Ui.Text(title, 12.5, color, bold: true);
        DockPanel.SetDock(head, Dock.Top);
        s.Children.Add(head);
        var v = Ui.Text(watt == null ? "–" : W(watt.Value), 24, "Text", bold: true, mono: true);
        v.Margin = new Thickness(0, 6, 0, 0);
        DockPanel.SetDock(v, Dock.Top);
        s.Children.Add(v);
        var n = Wrap(note, "Leise");
        n.VerticalAlignment = VerticalAlignment.Bottom;
        s.Children.Add(n);
        return Tile(s, color, tint);
    }

    static Button Chip(string label, bool on) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = 30, MinWidth = 40, Padding = new Thickness(12, 0, 12, 0), Margin = new Thickness(0, 0, 6, 6), Tag = "15",
        Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(on ? 0 : 1),
        HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 12, "Text", bold: true),
    };

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        timer.Stop();
        Live.Updated -= Measured;
        Live.Release();
        run = null;   // ohne Seite keine Messwerte: Durchgang abbrechen
    }
}
