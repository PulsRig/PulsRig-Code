using System.Diagnostics;
using System.IO;
using System.Management;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Akku wie PulsRig-Akku.ps1: wie viel der Akku noch fasst, Ladezyklen, Laufzeit laut Windows und der Verlauf der
// Kapazität. Zahlen aus "powercfg /batteryreport /xml", ohne Bericht aus den Akku-Klassen von WMI.
sealed class AkkuPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    sealed record Stand(bool Has, int? Charge, bool OnPower, AkkuBericht Report, string Source);

    readonly Grid root = new();
    Stand? data;
    string note = "";
    bool stopped;

    public AkkuPage()
    {
        Content = root;
        Fill();
        Task.Run(Read).ContinueWith(t => Dispatcher.BeginInvoke(() => { data = t.IsCompletedSuccessfully ? t.Result : new Stand(false, null, false, new AkkuBericht(), ""); Fill(); }));
    }

    static IEnumerable<ManagementBaseObject> Query(string wql, string scope = @"root\cimv2")
    {
        using var searcher = new ManagementObjectSearcher(scope, wql);
        foreach (ManagementBaseObject o in searcher.Get()) yield return o;
    }

    static double Number(ManagementBaseObject o, string name) => o[name] is { } v ? Convert.ToDouble(v) : 0;

    // ob ein Akku da ist (für Knöpfe auf anderen Seiten), einmal je Start; PULSRIG_AKKU zeigt ihn auch auf einem PC ohne Akku
    static bool? present;
    public static bool HasBattery => present ??= Present();

    static bool Present()
    {
        if (Environment.GetEnvironmentVariable("PULSRIG_AKKU") is { Length: > 0 }) return true;
        try { if (Query("SELECT BatteryStatus FROM Win32_Battery").Any()) return true; } catch (Exception) { }
        try { return Query("SELECT Active FROM BatteryStatus", @"root\wmi").Any(o => o["Active"] is true); } catch (Exception) { return false; }
    }

    static Stand Read()
    {
        bool has = false, onPower = true;
        int? charge = null;
        try
        {
            if (Query("SELECT EstimatedChargeRemaining, BatteryStatus FROM Win32_Battery").FirstOrDefault() is { } b)
            {
                has = true;
                charge = (int)Number(b, "EstimatedChargeRemaining");
                onPower = (int)Number(b, "BatteryStatus") != 1;   // 1 = entlädt
            }
        }
        catch (Exception) { }
        if (!has)
        {
            try
            {
                if (Query("SELECT * FROM BatteryStatus", @"root\wmi").FirstOrDefault(o => o["Active"] is true) is { } s)
                {
                    has = true;
                    onPower = s["PowerOnline"] is true;
                    var full = Query("SELECT FullChargedCapacity FROM BatteryFullChargedCapacity", @"root\wmi").FirstOrDefault();
                    if (full != null && Number(full, "FullChargedCapacity") > 0) charge = (int)Math.Min(100, Math.Round(100.0 * Number(s, "RemainingCapacity") / Number(full, "FullChargedCapacity")));
                }
            }
            catch (Exception) { }
        }
        if (!has) return new Stand(false, null, true, new AkkuBericht(), "");
        var report = new AkkuBericht();
        var source = "";
        var file = Path.Combine(Path.GetTempPath(), "PulsRig-Akku-" + Environment.ProcessId + ".xml");
        try
        {
            using (var p = Process.Start(new ProcessStartInfo("powercfg.exe", "/batteryreport /xml /output \"" + file + "\"") { CreateNoWindow = true, UseShellExecute = false }))
                p?.WaitForExit(30000);
            if (File.Exists(file)) { report = Akku.Parse(File.ReadAllText(file)); source = "report"; }
        }
        catch (Exception) { }
        finally { try { File.Delete(file); } catch (Exception) { } }
        if (report.Batteries.Count == 0)
        {
            try
            {
                var design = Query("SELECT * FROM BatteryStaticData", @"root\wmi").ToList();
                var full = Query("SELECT FullChargedCapacity FROM BatteryFullChargedCapacity", @"root\wmi").ToList();
                var cycles = new List<ManagementBaseObject>();
                try { cycles = Query("SELECT CycleCount FROM BatteryCycleCount", @"root\wmi").ToList(); } catch (Exception) { }
                for (var i = 0; i < design.Count; i++)
                    report.Batteries.Add(new AkkuZelle { Name = (design[i]["DeviceName"]?.ToString() ?? "").Trim(), Maker = (design[i]["ManufactureName"]?.ToString() ?? "").Trim(),
                        Design = Number(design[i], "DesignedCapacity"), Full = i < full.Count ? Number(full[i], "FullChargedCapacity") : 0, Cycles = i < cycles.Count ? (int)Number(cycles[i], "CycleCount") : 0 });
                source = "wmi";
            }
            catch (Exception) { }
        }
        return new Stand(true, charge, onPower, report, source);
    }

    // ausführlicher Bericht von Windows als Seite im Browser
    void OpenReport()
    {
        note = "Erstelle den Bericht …";
        Fill();
        Task.Run(() =>
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PulsRig");
            Directory.CreateDirectory(folder);
            var file = Path.Combine(folder, "Akku-Bericht.html");
            using (var p = Process.Start(new ProcessStartInfo("powercfg.exe", "/batteryreport /output \"" + file + "\"") { CreateNoWindow = true, UseShellExecute = false }))
                p?.WaitForExit(30000);
            if (!File.Exists(file)) return false;
            Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
            return true;
        }).ContinueWith(t => Dispatcher.BeginInvoke(() => { note = t.IsCompletedSuccessfully && t.Result ? "Der Bericht ist im Browser offen" : "Windows hat keinen Bericht erstellt"; Fill(); }));
    }

    static string Color(string tone) => tone switch { "good" => Gruen, "warn" => Bernstein, "bad" => Beere, _ => Lila };

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        var first = data?.Report.Batteries.FirstOrDefault();
        var health = first == null ? null : Akku.Health(first.Design, first.Full);
        var tone = health?.Tone ?? "";

        // links: Zustand groß
        var left = new StackPanel();
        left.Children.Add(Ui.Text("AKKU", 10, "Leise", mono: true));
        var big = Ui.Text(data == null ? "…" : health is { } h ? h.Percent + " %" : "–", 44, health == null ? "Text" : Color(tone), bold: true, mono: true);
        big.Margin = new Thickness(0, 14, 0, 0);
        left.Children.Add(big);
        left.Children.Add(Wrap(data == null ? "Lese den Akku …" : !data.Has ? "Kein Akku gefunden" : health != null ? "fasst er noch von neu" : "Kapazität unbekannt", "Halbleise"));
        if (first is { Cycles: > 0 })
        {
            var cycles = Ui.Text(first.Cycles.ToString("N0", Ui.De) + " Ladezyklen", 22, first.Cycles >= 800 ? Bernstein : Lila, bold: true);
            cycles.Margin = new Thickness(0, 26, 0, 0);
            left.Children.Add(cycles);
        }
        if (data is { Has: true })
        {
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 34, Padding = new Thickness(14, 0, 14, 0), Tag = "17", Margin = new Thickness(0, 26, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Left, Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
                Content = Ui.Text("Ausführlicher Bericht von Windows", 12.5, "Text", bold: true) };
            b.Click += (_, _) => OpenReport();
            left.Children.Add(b);
        }
        var foot = data == null || !data.Has ? "" : data.Source == "wmi" ? "Werte aus der Akku-Schnittstelle von Windows" : "Werte aus dem Akku-Bericht von Windows";
        if (note.Length > 0) foot = note;
        left.Children.Add(Wrap(foot, "Leise", 14));
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Color(tone), "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        // rechts: die Zeilen wie Show-BatteryTab
        var list = new StackPanel();
        if (data == null) list.Children.Add(Row("Lese den Akku …", "", null));
        else if (!data.Has) list.Children.Add(Row("Kein Akku gefunden", "Dieser PC läuft am Netz – einen Akku-Bericht gibt es nur bei Notebooks und Tablets.", null));
        else
        {
            var all = data.Report.Batteries;
            if (all.Count == 0) list.Children.Add(Row("Windows gibt die Kapazität nicht heraus", "Der Akku ist da, aber Windows meldet nicht, wie viel er noch fasst. Der ausführliche Bericht von Windows zeigt, was es weiß.", (null, "warn")));
            foreach (var bat in all)
            {
                if (all.Count > 1) list.Children.Add(Head("AKKU " + bat.Name.ToUpperInvariant()));
                if (Akku.Health(bat.Design, bat.Full) is { } bh)
                    list.Children.Add(Row("Fasst noch " + bh.Percent + " % von neu", Akku.Verdict(bh.Tone) + " Heute " + bat.Full.ToString("N0", Ui.De) + " mWh, neu waren es " + bat.Design.ToString("N0", Ui.De) + " mWh.", (bh.Percent + " %", bh.Tone), bh.Percent / 100.0));
                if (bat.Cycles > 0)
                    list.Children.Add(Row(bat.Cycles.ToString("N0", Ui.De) + " Ladezyklen", "Ein Zyklus ist einmal ganz leer und wieder voll, auch in Teilen. Übliche Akkus sind für 300 bis 1.000 Zyklen gebaut.", (null, bat.Cycles >= 800 ? "warn" : "accent")));
                var about = string.Join(" · ", new[] { bat.Maker, Akku.Chemistry(bat.Chemistry) }.Where(s => s.Length > 0));
                if (about.Length > 0) list.Children.Add(Row(bat.Name, about, null));
            }
            if (data.Charge is { } c)
                list.Children.Add(Row("Gerade " + c + " % geladen", data.OnPower ? "Das Netzteil ist angeschlossen." : "Das Notebook läuft gerade mit Akku.", (null, "accent"), c / 100.0));
            var now = Akku.Time(data.Report.Runtime);
            var fresh = Akku.Time(data.Report.RuntimeNew);
            if (now.Length > 0)
                list.Children.Add(Row("Hält etwa " + now, "Schätzung von Windows bei voller Ladung und üblicher Nutzung." + (fresh.Length > 0 ? " Neu wären es etwa " + fresh + " gewesen." : ""), (null, "accent")));
            var months = Akku.Pick(data.Report.History);
            if (months.Count > 0)
            {
                list.Children.Add(Head("VERLAUF DER KAPAZITÄT"));
                foreach (var m in months)
                {
                    var p = (int)Math.Min(100, Math.Round(100.0 * m.Full / m.Design));
                    var label = DateTime.TryParseExact(m.Month, "yyyy-MM", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var d) ? d.ToString("MM.yyyy") : m.Month;
                    list.Children.Add(Row(label, "", (p + " %", Akku.Tone(p)), p / 100.0));
                }
            }
            list.Children.Add(Head("AKKU SCHONEN"));
            list.Children.Add(Row("Nicht dauernd auf 100 %", "Viele Hersteller-Programme (Lenovo Vantage, MyASUS, Dell Power Manager, Acer Care Center) können das Laden bei 80 % stoppen. Das verlängert die Lebensdauer deutlich.", (null, "accent")));
            list.Children.Add(Row("Hitze meiden", "Beim Spielen auf dem Schoß oder auf der Bettdecke wird es unter dem Notebook heiß; Wärme altert den Akku am stärksten.", (null, "accent")));
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    static TextBlock Wrap(string text, string color, double top = 6) => new() { Text = text, FontSize = 12, Foreground = Ui.Res(color), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, top, 0, 0), LineHeight = 17 };

    static TextBlock Head(string text) => new() { Text = text, FontSize = 10.5, FontFamily = (FontFamily)Application.Current.FindResource("Mono"), Foreground = Ui.Res("Leise"), Margin = new Thickness(2, 6, 0, 8) };

    // state: Text der Pille (null: keine) und Ton des Balkens links; bar: Füllstand 0..1
    static Border Row(string title, string sub, (string? Text, string Tone)? state, double? bar = null)
    {
        var color = Color(state?.Tone ?? "");
        var grid = new Grid { MinHeight = 56 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border { Width = 4, Height = 30, CornerRadius = new CornerRadius(2), Background = Ui.Brush(state == null ? "#22172F" : color), Margin = new Thickness(0, 0, 16, 0) });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(title, 14.5, "Text", bold: true));
        if (sub.Length > 0)
        {
            var s = Ui.Text(sub, 12.5, "Leise");
            s.TextWrapping = TextWrapping.Wrap;
            s.Margin = new Thickness(0, 3, 0, 0);
            text.Children.Add(s);
        }
        if (bar is { } f)
        {
            var track = new Grid { Height = 4, Margin = new Thickness(0, 8, 0, 0) };
            track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Clamp(f, 0, 1), GridUnitType.Star) });
            track.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1 - Math.Clamp(f, 0, 1), GridUnitType.Star) });
            track.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = Ui.Brush("#22172F") });
            Grid.SetColumnSpan(track.Children[0], 2);
            track.Children.Add(new Border { CornerRadius = new CornerRadius(2), Background = Ui.Brush(color) });
            text.Children.Add(track);
        }
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (state is { Text: { Length: > 0 } pill })
        {
            var p = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Center, Child = Ui.Text(pill, 11, color) };
            Grid.SetColumn(p, 2);
            grid.Children.Add(p);
        }
        return new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid };
    }

    public void Stop() => stopped = true;
}
