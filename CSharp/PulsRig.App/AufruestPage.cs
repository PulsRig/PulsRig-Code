using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Aufrüst-Berater wie PulsRig-Aufruesten.ps1: misst eine Minute im laufenden Spiel, was bremst, und sagt in einem Satz,
// welches Bauteil sich zum Aufrüsten lohnt. Dazu die Bestandsaufnahme: Prozessor, Grafikkarte, RAM-Steckplätze und ob
// das Spiel auf einer Festplatte liegt. PulsRig schließt nichts und stellt nichts um, es misst nur. Keine Kauf-Links.
sealed class AufruestPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    sealed class Lauf { public DateTime Start, End; public readonly List<IDictionary<string, double?>> Samples = new(); }
    sealed record Ergebnis(Aufruestmessung Messung, DateTime Time, (string Name, string Letter, string Kind)? Game);

    // letzte Messung, bleibt bis zum Beenden wie $script:UpgradeResult
    static Ergebnis? result;
    static Lauf? run;

    readonly Grid root = new();
    readonly System.Windows.Threading.DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    Dictionary<string, (string Name, string Exe, string Path)>? games;
    Laufwerke? drives;
    bool stopped;

    public AufruestPage()
    {
        Content = root;
        Live.Use();
        Live.Updated += Measured;
        Hw.Changed += Fill;
        foreach (var what in new[] { "cpu", "gpu", "ram" }) Hw.Load(what);
        Task.Run(() => (Werkzeugpruefung.KnownGames(), Abfragen.Drives()))
            .ContinueWith(t => Dispatcher.BeginInvoke(() => { if (t.IsCompletedSuccessfully) (games, drives) = t.Result; }));
        timer.Tick += (_, _) => { Finish(); if (System.Windows.Input.Mouse.LeftButton != System.Windows.Input.MouseButtonState.Pressed) Fill(); };
        timer.Start();
        Fill();
    }

    void Measured()
    {
        if (run == null || DateTime.Now < run.Start) return;
        var s = new Dictionary<string, double?>();
        foreach (var key in new[] { "CpuCoreMax", "CpuLoad", "GpuLoad", "Ram", "GpuMemory", "GpuMemoryTotal" }) s[key] = Live.Get(key);
        run.Samples.Add(s);
    }

    void Finish()
    {
        if (run == null || DateTime.Now < run.End) return;
        var m = Aufruesten.Measure(run.Samples);
        run = null;
        // welches bekannte Spiel lief gerade, und auf welchem Laufwerk liegt es?
        (string, string, string)? game = null;
        if (games != null)
        {
            var running = new HashSet<string>(Process.GetProcesses().Select(p => { try { return p.ProcessName; } catch (Exception) { return ""; } }), StringComparer.OrdinalIgnoreCase);
            foreach (var g in games.Values)
            {
                if (!running.Contains(g.Exe)) continue;
                var letter = g.Path.Length > 1 && g.Path[1] == ':' ? g.Path[..1].ToUpperInvariant() : "";
                var disk = drives?.Disks.FirstOrDefault(d => d.Letters.Contains(letter));
                game = (g.Name, letter, disk == null ? "" : disk.Bus == "NVMe" ? "NVMe" : disk.Media);
                break;
            }
        }
        result = new Ergebnis(m, DateTime.Now, game);
    }

    void Start()
    {
        var start = DateTime.Now.AddSeconds(Aufruesten.Lead);
        run = new Lauf { Start = start, End = start.AddSeconds(Aufruesten.Seconds) };
        Fill();
    }

    static string P(double v) => v.ToString("N0", Ui.De) + " %";

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        var now = DateTime.Now;

        // links: Messung und Ergebnis
        var left = new StackPanel();
        left.Children.Add(Ui.Text("AUFRÜST-BERATER", 10, "Leise", mono: true));
        var verdict = result == null ? ("Noch nicht gemessen", "Spiel starten, hier „Messen“ und ins Spiel wechseln. PulsRig misst eine Minute lang.") : Aufruesten.Verdict(result.Messung);
        var title = Ui.Text(verdict.Item1, 24, result == null ? "Text" : Lila, bold: true);
        title.TextWrapping = TextWrapping.Wrap;
        title.Margin = new Thickness(0, 14, 0, 0);
        left.Children.Add(title);
        left.Children.Add(Wrap(verdict.Item2, "Halbleise", 8));
        var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 38, MinWidth = 120, Padding = new Thickness(18, 0, 18, 0), Tag = "17", Margin = new Thickness(0, 24, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left, Background = (Brush)Application.Current.FindResource("PulsQuer"), BorderThickness = new Thickness(0),
            Content = Ui.Text("Messen", 13, "Text", bold: true), IsEnabled = run == null, Opacity = run == null ? 1 : 0.5 };
        b.Click += (_, _) => Start();
        left.Children.Add(b);
        var state = run == null
            ? result == null ? "" : "Gemessen um " + result.Time.ToString("HH:mm") + ". Für ein anderes Spiel oder andere Einstellungen erneut messen."
            : now < run.Start ? "Jetzt ins Spiel wechseln – Messung beginnt in " + Math.Ceiling((run.Start - now).TotalSeconds) + " s" : "Misst im Spiel … noch " + Math.Ceiling((run.End - now).TotalSeconds) + " s";
        left.Children.Add(Wrap(state, run == null ? "Leise" : Bernstein, 10));
        left.Children.Add(Wrap("PulsRig schließt nichts und stellt nichts um – es misst nur", "Leise", 24));
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        // rechts: Messwerte (ohne Ergebnis die von gerade), dann die Bestandsaufnahme
        var list = new StackPanel();
        list.Children.Add(Head(result == null ? "GERADE" : "IM SPIEL GEMESSEN"));
        if (result?.Messung is { } m)
        {
            list.Children.Add(Row("Prozessor · stärkster Kern", m.Core == null ? "Nicht messbar" : "Mittel im Spiel, " + P(m.Core.Busy * 100) + " der Zeit über 90 % · alle Kerne zusammen nur " + P(m.Cpu?.Mean ?? 0), m.Core == null ? "–" : P(m.Core.Mean), Beere));
            list.Children.Add(Row("Grafikkarte · Auslastung", m.Gpu == null ? "Nur bei NVIDIA messbar" : "Mittel im Spiel, " + P(m.Gpu.Busy * 100) + " der Zeit über 95 %", m.Gpu == null ? "–" : P(m.Gpu.Mean), Lila));
            list.Children.Add(Row("Arbeitsspeicher · belegt", m.Vram is { } v ? "Mittel im Spiel · Grafikspeicher " + P(v) + " belegt" : "Mittel im Spiel", m.Ram == null ? "–" : P(m.Ram.Mean), Gruen));
        }
        else
        {
            list.Children.Add(Row("Prozessor · stärkster Kern", Live.Get("CpuLoad") is { } cl ? "Gerade · alle Kerne zusammen " + P(cl) : "Gerade", Live.Get("CpuCoreMax") is { } cm ? P(cm) : "–", Beere));
            list.Children.Add(Row("Grafikkarte · Auslastung", Live.Get("GpuLoad") != null ? "Gerade" : "Nur bei NVIDIA messbar", Live.Get("GpuLoad") is { } gl ? P(gl) : "–", Lila));
            list.Children.Add(Row("Arbeitsspeicher · belegt", "Gerade", Live.Get("Ram") is { } r ? P(r) : "–", Gruen));
        }

        list.Children.Add(Head("DEIN PC"));
        var cpu = Hw.Cpu;
        list.Children.Add(Row(cpu?.Name is { Length: > 0 } cn ? cn : "Prozessor unbekannt", cpu == null ? "" : cpu.Cores + " Kerne, " + cpu.Threads + " Threads", "", Beere));
        var gpu = Hw.Gpu;
        var nvidia = gpu?.Name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) == true;
        list.Children.Add(Row(gpu?.Name is { Length: > 0 } gn ? gn : "Grafikkarte unbekannt", nvidia ? "NVIDIA: Auslastung messbar" : "Keine NVIDIA-Karte: ihre Auslastung kann PulsRig nicht sicher messen", "", Lila));
        if (Hw.Memory is { } mem)
        {
            var installed = mem.Modules.Sum(x => x.Bytes);
            if (installed <= 0) installed = mem.Total;
            var firstModule = mem.Modules.FirstOrDefault();
            var kind = string.Join(" · ", new[] { firstModule?.Type ?? "", firstModule is { Speed: > 0 } fm ? fm.Speed + " MT/s" : "" }.Where(s => s.Length > 0));
            var head = Math.Round(installed / (1L << 30)).ToString("N0", Ui.De) + " GB Arbeitsspeicher" + (kind.Length > 0 ? " · " + kind : "");
            var line = Aufruesten.Memory(mem.Modules.Count, mem.Slots, mem.MaxBytes, mem.Modules.Any(x => x.Laptop));
            list.Children.Add(Row(head, line.Text, line.Chip, line.Free ? Gruen : Lila));
        }
        else list.Children.Add(Row("Arbeitsspeicher", "Lese die Steckplätze …", "", Gruen));
        if (result?.Game is { } game) list.Children.Add(Row("Laufwerk von " + game.Name, Aufruesten.DriveText(game.Letter, game.Kind), game.Kind == "HDD" ? "Festplatte" : "", game.Kind == "HDD" ? Bernstein : Lila));
        else list.Children.Add(Row("Laufwerk des Spiels", result == null ? "Wird beim Messen erkannt, wenn ein bekanntes Spiel läuft" : "Beim Messen lief kein Spiel, das Windows als Spiel kennt", "", Lila));

        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    static TextBlock Wrap(string text, string color, double top = 6) => new() { Text = text, FontSize = 12.5, Foreground = color.StartsWith('#') ? Ui.Brush(color) : Ui.Res(color), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, top, 0, 0), LineHeight = 18 };

    static TextBlock Head(string text) => new() { Text = text, FontSize = 10.5, FontFamily = (FontFamily)Application.Current.FindResource("Mono"), Foreground = Ui.Res("Leise"), Margin = new Thickness(2, 6, 0, 8) };

    static Border Row(string title, string sub, string value, string color)
    {
        var grid = new Grid { MinHeight = 60 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border { Width = 4, Height = 30, CornerRadius = new CornerRadius(2), Background = Ui.Brush(color), Margin = new Thickness(0, 0, 16, 0) });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(title, 14.5, "Text", bold: true));
        if (sub.Length > 0)
        {
            var s = Ui.Text(sub, 12.5, "Leise");
            s.TextWrapping = TextWrapping.Wrap;
            s.Margin = new Thickness(0, 3, 0, 0);
            text.Children.Add(s);
        }
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (value.Length > 0)
        {
            var v = Ui.Text(value, value.EndsWith('%') || value == "–" ? 20 : 12.5, value.EndsWith('%') || value == "–" ? "Text" : color, bold: true, mono: value.EndsWith('%'));
            v.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(v, 2);
            grid.Children.Add(v);
        }
        return new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid };
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        timer.Stop();
        Live.Updated -= Measured;
        Hw.Changed -= Fill;
        Live.Release();
        run = null;   // ohne Seite keine Messwerte: Durchgang abbrechen
    }
}
