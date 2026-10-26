using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace PulsRig.App;

// Benchmark wie PulsRig-Benchmark.ps1: Prozessor (ein Kern, alle), Arbeitsspeicher, Grafikkarte (PulsRig-Benchmark.cs,
// dieselbe Messung) und das Windows-Laufwerk (Tempotest). Die Sensoren laufen mit, die Höchstwerte gehören zum Lauf.
// Jeder Lauf kommt mit seinen Umständen in History.Benchmarks der gemeinsamen Ergebnisdatei (die letzten 30), damit
// der Vergleich mit dem Lauf davor auch sagen kann, was sich seitdem geändert hat.
sealed class BenchPage : UserControl, IPage
{
    const double CpuFactor = 0.1, GpuFactor = 10.0, Noise = 5.0;

    sealed record Spec(string Key, string Label, string Unit, string Format, string Color, double Noise, Func<JsonObject, string> Detail);

    static readonly Spec[] Specs =
    {
        new("M", "Prozessor", "Punkte", "N0", "#8C6BD6", Noise, r => Num(r, "S") > 0 ? "1 Kern: " + Num(r, "S").ToString("N0", Ui.De) + " Punkte" : ""),
        // die Grafikkarte schwankt stärker (±4,5 % in vier Läufen kurz nacheinander)
        new("G", "Grafikkarte", "Punkte", "N0", "#C0608F", 10.0, r => Num(r, "F") > 0 ? "Füllrate " + Num(r, "F").ToString("N0", Ui.De) + " Gpx/s" : Str(r, "GE").Length > 0 ? "nicht messbar" : ""),
        new("C", "Arbeitsspeicher", "GB/s", "N1", "#5E4BB8", Noise, r => Num(r, "L") > 0 ? "Wartezeit " + Num(r, "L").ToString("N0", Ui.De) + " ns" : ""),
        new("R", "Laufwerk", "MB/s", "N0", "#F2B661", Noise, r => Num(r, "W") > 0 ? Str(r, "DL") + " lesen · schreiben " + Num(r, "W").ToString("N0", Ui.De) + " MB/s" : Str(r, "DE").Length > 0 ? Str(r, "DE") : "nicht gemessen"),
    };

    static double Num(JsonObject? r, string key) => r?[key] is JsonValue v && v.TryGetValue<double>(out var d) ? d : 0;
    static string Str(JsonObject? r, string key) => r?[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";

    // ein Lauf für alle Seiten: geht man weg, läuft er weiter
    static bool running;
    static string phase = "", message = "";
    static double maxCpu, maxGpu;
    static event Action? Changed;

    readonly Grid root = new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(300) };
    int tab;
    bool stopped;

    public BenchPage()
    {
        Content = root;
        Live.Use();
        Live.Updated += Sample;
        Changed += Fill;
        // nicht mitten in einem Klick neu aufbauen: sonst geht er verloren
        timer.Tick += (_, _) => { if (running && System.Windows.Input.Mouse.LeftButton != System.Windows.Input.MouseButtonState.Pressed) Fill(); };
        timer.Start();
        Fill();
    }

    static void Sample()
    {
        if (!running) return;
        if (Live.Get("CpuTemp") is { } c && c > maxCpu) maxCpu = c;
        if (Live.Get("GpuTemp") is { } g && g > maxGpu) maxGpu = g;
    }

    static List<JsonObject> Runs() =>
        (Ergebnisse.Read()["History"]?["Benchmarks"] as JsonArray)?.OfType<JsonObject>().Where(r => Str(r, "D").Length > 0).ToList() ?? new();

    static double? ChangeOf(JsonObject now, JsonObject? before, string key)
    {
        if (before == null) return null;
        double a = Num(now, key), b = Num(before, key);
        return a > 0 && b > 0 ? 100.0 * (a - b) / b : null;
    }

    // "um 14:20 Uhr" am selben Tag, sonst "am 16.10." bzw. "am 16.10.2026"
    static string Since(JsonObject before, bool shortDate)
    {
        var parts = Str(before, "D").Split(' ', 2);
        if (parts[0] == DateTime.Now.ToString("dd.MM.yyyy") && parts.Length > 1) return "um " + parts[1] + " Uhr";
        return shortDate && parts[0].Length >= 6 ? "am " + parts[0][..6] : "am " + parts[0];
    }

    static bool Worse(JsonObject run, JsonObject? before) => Specs.Any(s => ChangeOf(run, before, s.Key) is { } c && c <= -s.Noise);

    // wie Get-BenchContextChanges
    static List<string> ContextChanges(JsonObject now, JsonObject? before)
    {
        var list = new List<string>();
        if (before?["X"] is not JsonObject a || now["X"] is not JsonObject b) return list;
        void Diff(string key, string name, string unit = "")
        {
            var x = a[key]?.ToString() ?? ""; var y = b[key]?.ToString() ?? "";
            if (x.Length > 0 && y.Length > 0 && x != y) list.Add(name + " " + x + " → " + y + unit);
        }
        Diff("Gpu", "Grafiktreiber"); Diff("Ram", "Speichertakt", " MHz"); Diff("Plan", "Energieplan"); Diff("Win", "Windows");
        if (a["Boost"] is JsonValue ba && b["Boost"] is JsonValue bb && ba.TryGetValue<bool>(out var x1) && bb.TryGetValue<bool>(out var y1) && x1 != y1)
            list.Add("Boost " + (x1 ? "an" : "aus") + " → " + (y1 ? "an" : "aus"));
        return list;
    }

    // wie Get-BenchSummary
    static string Summary(JsonObject run, JsonObject? before)
    {
        var parts = new List<string>();
        var temps = new List<string>();
        if (Num(run, "CT") > 0) temps.Add("Prozessor bis " + Num(run, "CT").ToString("N0", Ui.De) + " °C");
        if (Num(run, "GT") > 0) temps.Add("Grafikkarte bis " + Num(run, "GT").ToString("N0", Ui.De) + " °C");
        var limit = Num(run, "CT") >= 88 ? "Der Prozessor lief an seiner Temperaturgrenze. Viele Prozessoren takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt: Bei normalen Punkten ist das kein Fehler. Werden die Punkte mit der Zeit weniger, Kühler und Staub prüfen." : "";
        if (before == null)
        {
            parts.Add("Erster Lauf: Er ist ab jetzt der Vergleich für die nächsten.");
            if (temps.Count > 0) parts.Add(string.Join(" · ", temps) + ".");
            if (limit.Length > 0) parts.Add(limit);
            return string.Join("\n", parts);
        }
        var better = new List<string>(); var worse = new List<string>();
        foreach (var s in Specs)
        {
            if (ChangeOf(run, before, s.Key) is not { } c || Math.Abs(c) < s.Noise) continue;
            if (c > 0) better.Add(s.Label + " +" + c.ToString("N0", Ui.De) + " %"); else worse.Add(s.Label + " −" + (-c).ToString("N0", Ui.De) + " %");
        }
        var since = Since(before, false);
        if (better.Count == 0 && worse.Count == 0) parts.Add("Alles wie " + since + ".");
        if (better.Count > 0) parts.Add("Besser als " + since + ": " + string.Join(", ", better) + ".");
        if (worse.Count > 0) parts.Add("Schlechter als " + since + ": " + string.Join(", ", worse) + ".");
        // 8 Grad mehr bei gleicher Leistung deutet auf Staub oder eingetrocknete Wärmeleitpaste
        if (Num(run, "CT") > 0 && Num(before, "CT") > 0 && Num(run, "CT") - Num(before, "CT") >= 8) parts.Add("Der Prozessor wurde " + (Num(run, "CT") - Num(before, "CT")).ToString("N0", Ui.De) + " °C wärmer als damals.");
        else if (Num(run, "GT") > 0 && Num(before, "GT") > 0 && Num(run, "GT") - Num(before, "GT") >= 8) parts.Add("Die Grafikkarte wurde " + (Num(run, "GT") - Num(before, "GT")).ToString("N0", Ui.De) + " °C wärmer als damals.");
        var changes = ContextChanges(run, before);
        if (changes.Count > 0) parts.Add("Seitdem: " + string.Join(", ", changes) + ".");
        else if (worse.Count > 0) parts.Add("Seitdem hat sich an Treiber, Speichertakt, Energieplan und Windows nichts geändert: andere Programme im Hintergrund oder Wärme sind wahrscheinlicher.");
        if (temps.Count > 0) parts.Add(string.Join(" · ", temps) + ".");
        if (limit.Length > 0 && worse.Count == 0) parts.Add(limit);
        return string.Join("\n", parts);
    }

    // wie Get-BenchContext
    static JsonObject Context()
    {
        var x = new JsonObject { ["Boost"] = Spielboost.IsOn };
        try
        {
            using var s = new System.Management.ManagementObjectSearcher("SELECT DriverVersion, PNPDeviceID FROM Win32_VideoController");
            foreach (System.Management.ManagementObject o in s.Get()) if ((o["PNPDeviceID"]?.ToString() ?? "").StartsWith("PCI")) { x["Gpu"] = o["DriverVersion"]?.ToString(); break; }
        }
        catch (Exception) { }
        try
        {
            using var s = new System.Management.ManagementObjectSearcher("SELECT ConfiguredClockSpeed, Speed FROM Win32_PhysicalMemory");
            foreach (System.Management.ManagementObject o in s.Get()) { x["Ram"] = Convert.ToInt32(o["ConfiguredClockSpeed"] ?? o["Speed"] ?? 0); break; }
        }
        catch (Exception) { }
        var plan = Core.Boost.Plans(SpielboostPlans()).FirstOrDefault(p => p.Active);
        if (plan.Name != null) x["Plan"] = plan.Name;
        var cv = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        x["Win"] = Microsoft.Win32.Registry.GetValue(cv, "CurrentBuild", "") + "." + Microsoft.Win32.Registry.GetValue(cv, "UBR", "");
        return x;
    }

    static string[] SpielboostPlans()
    {
        try
        {
            using var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(System.IO.Path.Combine(Environment.SystemDirectory, "powercfg.exe"), "/list") { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true })!;
            var text = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return text.Split('\n');
        }
        catch (Exception) { return Array.Empty<string>(); }
    }

    static void Start()
    {
        if (running) return;
        if (Belastung.Running) { message = "Erst den Stabilitätstest beenden."; Changed?.Invoke(); return; }
        running = true; maxCpu = maxGpu = 0; message = ""; phase = "core";
        try { PulsRigStress.KeepAwake(true); } catch (Exception) { }
        PulsRigBench.Start(1.0, true);
        Changed?.Invoke();
        var ui = Application.Current.Dispatcher;
        Task.Run(() =>
        {
            while (PulsRigBench.Stage is not ("done" or "stopped")) Thread.Sleep(300);
            if (PulsRigBench.Stage == "stopped" || !running) { ui.BeginInvoke(() => Finish(null, true)); return; }
            phase = "drive";
            ui.BeginInvoke(() => Changed?.Invoke());
            var letter = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:").TrimEnd(':')[..1].ToUpperInvariant();
            var drive = running ? Tempotest.Run(letter) : null;
            ui.BeginInvoke(() => Finish(drive, drive == null));
        });
    }

    static void Cancel() { if (!running) return; try { PulsRigBench.Stop(); } catch (Exception) { } running = false; message = "Abgebrochen."; Changed?.Invoke(); }

    // wie Complete-Bench
    static void Finish(Tempo? drive, bool cancelled)
    {
        try { PulsRigStress.KeepAwake(false); } catch (Exception) { }
        running = false; phase = "";
        if (cancelled) { message = "Abgebrochen."; Changed?.Invoke(); return; }
        var run = new JsonObject
        {
            ["D"] = DateTime.Now.ToString("dd.MM.yyyy HH:mm"),
            ["S"] = Math.Round(PulsRigBench.Single * CpuFactor), ["M"] = Math.Round(PulsRigBench.Multi * CpuFactor),
            ["C"] = Math.Round(PulsRigBench.Copy, 1), ["L"] = Math.Round(PulsRigBench.Latency, 1),
            ["F"] = Math.Round(PulsRigBench.Fill, 1), ["G"] = Math.Round(PulsRigBench.Fill * GpuFactor),
            ["GN"] = PulsRigBench.GpuName ?? "", ["GE"] = PulsRigBench.GpuError ?? "",
            ["CT"] = Math.Round(maxCpu), ["GT"] = Math.Round(maxGpu), ["X"] = Context(),
        };
        if (drive != null && drive.Error.Length == 0) { run["R"] = Math.Round(drive.Read); run["W"] = Math.Round(drive.Write); run["DL"] = drive.Letter + ":"; }
        else if (drive != null) run["DE"] = drive.Error;
        try
        {
            Ergebnisse.Change(results =>
            {
                var history = Ergebnisse.History(results);
                var list = (history["Benchmarks"] as JsonArray)?.Select(n => n?.DeepClone()).ToList() ?? new();
                list.Add(run);
                history["Benchmarks"] = new JsonArray(list.Skip(Math.Max(0, list.Count - 30)).ToArray());
            });
        }
        catch (Exception e) { message = "Gemessen, aber nicht gespeichert: " + e.Message; }
        Changed?.Invoke();
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        var runs = Runs();

        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var action = Button(running ? "Stoppen" : "Benchmark starten", !running);
        action.Click += (_, _) => { if (running) Cancel(); else Start(); };
        DockPanel.SetDock(action, Dock.Right);
        head.Children.Add(action);
        var tabs = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (i, name) in new[] { (0, "Messen"), (1, "Verlauf") })
        {
            var b = Button(name, tab == i);
            b.Margin = new Thickness(0, 0, 8, 0);
            b.Click += (_, _) => { tab = i; Fill(); };
            tabs.Children.Add(b);
        }
        head.Children.Add(tabs);
        root.Children.Add(head);

        var body = tab == 0 ? Measure(runs) : History(runs);
        Grid.SetRow(body, 1);
        root.Children.Add(body);
    }

    UIElement Measure(List<JsonObject> runs)
    {
        var last = runs.LastOrDefault();
        var before = runs.Count > 1 ? runs[^2] : null;
        var grid = Ui.Mosaic(4, 2, 12);
        for (var i = 0; i < Specs.Length; i++)
        {
            var s = Specs[i];
            var panel = new DockPanel();
            var top = Ui.Text(s.Label, 12.5, s.Color, bold: true);
            DockPanel.SetDock(top, Dock.Top);
            panel.Children.Add(top);
            var value = last == null || Num(last, s.Key) <= 0 ? "–" : Num(last, s.Key).ToString(s.Format, Ui.De);
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
            row.Children.Add(Ui.Text(value, 26, "Text", bold: true, mono: true));
            var unit = Ui.Text(s.Unit, 13, "Leise");
            unit.VerticalAlignment = VerticalAlignment.Bottom;
            unit.Margin = new Thickness(6, 0, 0, 4);
            row.Children.Add(unit);
            DockPanel.SetDock(row, Dock.Top);
            panel.Children.Add(row);
            if (last != null)
            {
                var detail = Ui.Text(s.Detail(last), 11.5, "Leise");
                DockPanel.SetDock(detail, Dock.Top);
                panel.Children.Add(detail);
                var change = ChangeOf(last, before, s.Key);
                if (change is { } c && before != null)
                {
                    var since = Since(before, true);
                    var (label, color) = Math.Abs(c) < s.Noise ? ("wie " + since, "Leise") : c > 0 ? (c.ToString("N0", Ui.De) + " % besser als " + since, "#8FF0BE") : ((-c).ToString("N0", Ui.De) + " % schlechter als " + since, "#F6C989");
                    var d = Ui.Text(label, 11.5, color, bold: true);
                    d.Margin = new Thickness(0, 2, 0, 0);
                    DockPanel.SetDock(d, Dock.Top);
                    panel.Children.Add(d);
                }
            }
            // kleine Säulen: die letzten acht Läufe, der neueste rechts
            var values = runs.TakeLast(8).Select(r => Num(r, s.Key)).ToList();
            var bars = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom };
            var max = values.DefaultIfEmpty(0).Max();
            if (values.Count > 1 && max > 0)
                for (var k = 0; k < values.Count; k++)
                    bars.Children.Add(new Border { Width = 7, Margin = new Thickness(3, 0, 0, 0), CornerRadius = new CornerRadius(2), VerticalAlignment = VerticalAlignment.Bottom,
                        Height = Math.Max(2, 30 * values[k] / max), Background = Ui.Brush(s.Color), Opacity = k == values.Count - 1 ? 1 : 0.35 });
            panel.Children.Add(bars);
            var tile = Ui.Tile(s.Color, "#0F0A16", new Thickness(18, 16, 18, 14));
            tile.CornerRadius = new CornerRadius(22);
            tile.Child = panel;
            Ui.Place(grid, tile, i, 0);
        }

        // Zustand: läuft, fertig oder bereit
        var state = new StackPanel();
        string title, text;
        if (running)
        {
            var what = phase == "drive" ? "Laufwerk: schreiben und lesen (1 GB, wird gleich wieder gelöscht)" : PulsRigBench.Stage switch { "single" => "Prozessor, ein Kern", "multi" => "Prozessor, alle Kerne", "memory" => "Arbeitsspeicher", "gpu" => "Grafikkarte (eigenes Fenster)", _ => "" };
            title = "Läuft – " + (phase == "drive" ? 80 : (int)(PulsRigBench.Percent * 0.8)) + " %";
            text = what + (maxCpu > 0 ? " · Prozessor bis " + maxCpu.ToString("N0", Ui.De) + " °C" : "") + (maxGpu > 0 ? " · Grafikkarte bis " + maxGpu.ToString("N0", Ui.De) + " °C" : "");
        }
        else if (message.Length > 0) { title = "Nicht fertig geworden"; text = message; }
        else if (last != null) { title = "Letzter Lauf: " + Str(last, "D") + " Uhr" + (Str(last, "GE").Length > 0 ? " – die Grafikkarte ließ sich nicht messen" : ""); text = Summary(last, before); }
        else { title = "Bereit"; text = "Dauert rund eine Minute. Ein Fenster für die Grafikkarte geht kurz auf, auf das Windows-Laufwerk wird 1 GB geschrieben und gleich wieder gelöscht. Andere Programme vorher schließen, sonst sinken die Punkte."; }
        var tone = running ? "#8C6BD6" : last != null && Worse(last, before) ? "#F2B661" : "#5EE0A0";
        state.Children.Add(Ui.Text(title, 16, tone, bold: true));
        state.Children.Add(new TextBlock { Text = text, FontSize = 12.5, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), LineHeight = 19 });
        state.Children.Add(new TextBlock { Text = "Am besten vergleichbar: gleiche Uhrzeit, gleiche Programme offen, PC nicht gerade erst gestartet.", FontSize = 11.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) });
        var box = Ui.Tile("#8C6BD6", "#160D29", new Thickness(20, 18, 20, 18));
        box.CornerRadius = new CornerRadius(22);
        box.Child = new ScrollViewer { Content = state, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Ui.Place(grid, box, 0, 1, 4);
        return grid;
    }

    // wie Show-BenchHistory
    static UIElement History(List<JsonObject> runs)
    {
        var list = new StackPanel();
        if (runs.Count == 0) list.Children.Add(Ui.Text("Noch kein Lauf – der erste ist der Vergleich für alle späteren: nach einem Treiber-Update, mit XMP oder mit Boost.", 13, "Leise"));
        for (var i = runs.Count - 1; i >= 0; i--)
        {
            var run = runs[i];
            var before = i > 0 ? runs[i - 1] : null;
            var parts = new List<string> { "Prozessor " + Num(run, "M").ToString("N0", Ui.De) + " (1 Kern " + Num(run, "S").ToString("N0", Ui.De) + ")" };
            if (Num(run, "G") > 0) parts.Add("Grafik " + Num(run, "G").ToString("N0", Ui.De));
            if (Num(run, "C") > 0) parts.Add("Speicher " + Num(run, "C").ToString("N1", Ui.De) + " GB/s, " + Num(run, "L").ToString("N0", Ui.De) + " ns");
            if (Num(run, "R") > 0) parts.Add(Str(run, "DL") + " " + Num(run, "R").ToString("N0", Ui.De) + "/" + Num(run, "W").ToString("N0", Ui.De) + " MB/s");
            if (Num(run, "CT") > 0) parts.Add("CPU " + Num(run, "CT").ToString("N0", Ui.De) + " °C");
            if (Num(run, "GT") > 0) parts.Add("GPU " + Num(run, "GT").ToString("N0", Ui.De) + " °C");
            var changes = ContextChanges(run, before);
            if (changes.Count > 0) parts.Add("seit dem Lauf davor: " + string.Join(", ", changes));
            var state = before == null ? "erster Lauf" : Worse(run, before) ? "schlechter" : Specs.Any(s => ChangeOf(run, before, s.Key) is { } c && c >= s.Noise) ? "besser" : "gleich";
            var row = new DockPanel { Margin = new Thickness(0, 10, 0, 10) };
            var st = Ui.Text(state, 12, state == "besser" ? "#8FF0BE" : state == "schlechter" ? "#F6C989" : "Leise", bold: true);
            DockPanel.SetDock(st, Dock.Right);
            row.Children.Add(st);
            var t = new StackPanel();
            t.Children.Add(Ui.Text(Str(run, "D") + " Uhr", 14, "Text", bold: true));
            t.Children.Add(new TextBlock { Text = string.Join(" · ", parts), FontSize = 12, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) });
            row.Children.Add(t);
            list.Children.Add(new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"),
                Padding = new Thickness(18, 0, 18, 0), Margin = new Thickness(0, 0, 0, 8), Child = row });
        }
        list.Children.Add(Ui.Text(runs.Count + " von höchstens 30 Läufen gespeichert", 11.5, "Leise"));
        return new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
    }

    static Button Button(string label, bool primary) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(16, 0, 16, 0), Tag = "18",
        Background = primary ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(primary ? 0 : 1),
        VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 12.5, "Text", bold: true),
    };

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        timer.Stop();
        Changed -= Fill;
        Live.Updated -= Sample;
        Live.Release();
    }
}
