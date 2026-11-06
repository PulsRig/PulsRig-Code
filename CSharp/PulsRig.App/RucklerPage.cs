using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Shapes;
using PulsRig.Core;

namespace PulsRig.App;

// Ruckler-Detektiv: links die letzten Spielsitzungen, rechts, was beim Spielen dazwischengefunkt hat (Core.Ruckler),
// je Befund mit Knopf zur Abhilfe und einer Zeitleiste über die Sitzung. Die Daten schreibt der Helfer beim Aufzeichnen.
sealed class RucklerPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Bernstein = "#F2B661";

    readonly MainWindow main;
    readonly bool demo;
    readonly Grid root = new();
    static string pick = "";
    static List<RucklerEreignis>? events;
    bool stopped;

    public RucklerPage(MainWindow main, bool demo)
    {
        this.main = main;
        this.demo = demo;
        Content = root;
        if (events == null && !demo)
            Task.Run(() => { try { return Ereignisse.StutterEvents(31); } catch (Exception) { return new List<RucklerEreignis>(); } })
                .ContinueWith(t => Dispatcher.BeginInvoke(() => { events = t.Result; Fill(); }));
        Fill();
    }

    static string Folder => System.IO.Path.Combine(Altdaten.Folder, "Aufzeichnungen");

    static List<FileInfo> Files() => Directory.Exists(Folder) ? new DirectoryInfo(Folder).GetFiles("*.csv").OrderByDescending(f => f.Name).ToList() : new();

    // für -Demo und Bilder: eine Stunde mit Defender, Chrome und einem vollen Laufwerk
    static Spielsitzung Demo()
    {
        var s = new Spielsitzung { Game = "Cyberpunk2077", Begin = DateTime.Today.AddHours(20) };
        foreach (var c in new[] { "Sekunde", "CpuLast", "StoerCpu", "Platte", "Dpc", "RamFrei" }) s.Data[c] = new();
        s.Texts["Stoerer"] = new();
        for (var i = 0; i < 720; i++)
        {
            var defender = i is >= 130 and < 136;
            var chrome = i is >= 400 and < 410 or >= 600 and < 604;
            s.Data["Sekunde"].Add(i * 5);
            s.Data["CpuLast"].Add(70);
            s.Data["StoerCpu"].Add(defender ? 22 : chrome ? 15 : 2);
            s.Data["Platte"].Add(defender || i is >= 20 and < 26 ? 97 : 20);
            s.Data["Dpc"].Add(0.8);
            s.Data["RamFrei"].Add(5200);
            s.Texts["Stoerer"].Add(defender ? "MsMpEng" : chrome ? "chrome" : "Discord");
        }
        return s;
    }

    static string Label(FileInfo f)
    {
        var m = System.Text.RegularExpressions.Regex.Match(f.Name, @"^(\d{4})-(\d\d)-(\d\d)_(\d\d)-(\d\d)-\d\d_(.+)\.csv$");
        return m.Success ? m.Groups[3].Value + "." + m.Groups[2].Value + ". " + m.Groups[4].Value + ":" + m.Groups[5].Value + " · " + m.Groups[6].Value : f.Name;
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        var files = demo ? new List<FileInfo>() : Files();
        var file = files.FirstOrDefault(f => f.FullName == pick) ?? files.FirstOrDefault();
        Spielsitzung? session = null;
        var error = "";
        if (demo) session = Demo();
        else if (file != null)
            try { session = SensorPage.Read(file.FullName); } catch (Exception e) { error = Bedienfehler.Text(e); }

        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "Ruckler-Detektiv", FontSize = 26, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        left.Children.Add(new TextBlock { Text = "Was beim Spielen dazwischengefunkt hat: Programme im Hintergrund, Virenscans, Updates, volle Laufwerke, Treiber und knapper Arbeitsspeicher.",
            FontSize = 13, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        foreach (var f in files.Take(6))
        {
            var b = NeuinstallPage.Big(Label(f), f.FullName == file?.FullName);
            b.Click += (_, _) => { pick = f.FullName; Fill(); };
            left.Children.Add(b);
        }
        if (demo) left.Children.Add(NeuinstallPage.Big(Label(new FileInfo("2026-11-02_20-00-00_Cyberpunk2077.csv")), true));
        left.Children.Add(new TextBlock { Text = "Gemessen wird alle 5 Sekunden ohne Adminrechte. Wie viele Bilder pro Sekunde das Spiel schafft, sieht PulsRig dabei nicht.",
            FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        var list = new StackPanel();
        if (session == null)
        {
            var settings = Altdaten.Settings();
            var text = error.Length > 0 ? error
                : Helfer.Exe == null ? "Aufgezeichnet wird im Helfer neben der Uhr. Den gibt es nur im installierten Programm."
                : !Altdaten.Flag(settings, "Helper", false) ? "Aufgezeichnet wird im Helfer neben der Uhr. Er ist ausgeschaltet – einschalten unter Optionen → Überwachung."
                : !Altdaten.Flag(settings, "RecordGames", true) ? "Die Aufzeichnung beim Spielen ist ausgeschaltet – einschalten unter Optionen → Überwachung."
                : "Sobald ein Spiel aus der Spieleliste läuft, schreibt der Helfer mit. Danach steht hier, was dazwischengefunkt hat.";
            list.Children.Add(NeuinstallPage.Row(error.Length > 0 ? "Die Sitzung ließ sich nicht lesen" : "Noch keine Spielsitzung", text, ("", "accent"),
                error.Length > 0 ? "" : "Spieleliste", error.Length > 0 ? null : () => { WerkzeugePage.FocusTool = "Spieleliste für Boost"; main.Go("games"); }));
        }
        else
        {
            var result = Ruckler.Analyze(session, events);
            list.Children.Add(NeuinstallPage.Head((session.Game + " · " + session.Begin.ToString("dd.MM. HH:mm") + " · " + Aufzeichnung.Duration(session.Seconds)).ToUpperInvariant()));
            if (!result.Supported)
                list.Children.Add(NeuinstallPage.Row("Ältere Aufzeichnung", result.Summary, ("", "accent")));
            else
            {
                list.Children.Add(Timeline(session, result));
                if (result.Findings.Count == 0)
                    list.Children.Add(NeuinstallPage.Row("Nichts gefunden", result.Summary, ("ruhig", "good"), "Gaming-Check", () => Go("gamingcheck")));
                else
                {
                    list.Children.Add(new TextBlock { Text = result.Summary, FontSize = 12.5, Foreground = Ui.Res("Halbleise"), Margin = new Thickness(2, 0, 0, 10) });
                    foreach (var f in result.Findings)
                    {
                        var (label, to) = f.Action switch
                        {
                            "defender" => ("Öffnen", "defender"), "update" => ("Nutzungszeit", "update"), "boost" => ("Zum Boost", "boost"),
                            "autostart" => ("Autostart", "clean"), "drivers" => ("Scan", "scan"), "drives" => ("Laufwerke", "drives"), _ => ("", ""),
                        };
                        list.Children.Add(NeuinstallPage.Row(f.Title, f.Text, ("", f.Tone), label, to.Length > 0 ? () => Go(to) : null));
                    }
                }
            }
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    // die ganze Sitzung als Leiste, jeder Befund als Strich an seiner Stelle
    static Border Timeline(Spielsitzung s, RucklerErgebnis r)
    {
        var canvas = new Canvas { Height = 26, ClipToBounds = true };
        var total = Math.Max(s.Seconds, 5);
        canvas.SizeChanged += (_, _) =>
        {
            canvas.Children.Clear();
            var w = canvas.ActualWidth;
            canvas.Children.Add(new Rectangle { Width = w, Height = 6, RadiusX = 3, RadiusY = 3, Fill = Ui.Brush("#22172F") });
            Canvas.SetTop(canvas.Children[0], 10);
            foreach (var f in r.Findings)
                foreach (var sec in f.Seconds)
                {
                    var mark = new Rectangle { Width = 3, Height = 18, RadiusX = 1.5, RadiusY = 1.5, Fill = Ui.Brush(f.Total == 0 ? Lila : Bernstein) };
                    Canvas.SetLeft(mark, Math.Min(w - 3, sec / total * w));
                    Canvas.SetTop(mark, 4);
                    canvas.Children.Add(mark);
                }
        };
        var panel = new StackPanel();
        panel.Children.Add(canvas);
        var times = new Grid { Margin = new Thickness(0, 4, 0, 0) };
        times.Children.Add(Ui.Text(s.Begin.ToString("HH:mm"), 11, "Leise"));
        var endText = Ui.Text(s.Begin.AddSeconds(total).ToString("HH:mm"), 11, "Leise");
        endText.HorizontalAlignment = HorizontalAlignment.Right;
        times.Children.Add(endText);
        panel.Children.Add(times);
        return new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 12, 16, 10), Margin = new Thickness(0, 0, 0, 10), Child = panel };
    }

    void Go(string to)
    {
        switch (to)
        {
            case "defender": Open("windowsdefender://threatsettings"); break;
            case "update": Open("ms-settings:windowsupdate-activehours"); break;
            case "boost": main.GoTop("boost"); break;
            case "clean": main.GoTop("tools"); main.Go("clean"); break;
            case "scan": main.GoTop("home"); Treiberscan.Start(); break;
            case "drives": main.GoTop("hw"); main.Go("drives"); break;
            case "gamingcheck": WerkzeugePage.FocusTool = "Gaming-Check"; main.Go("games"); Werkzeuglauf.Check("games:Gaming-Check", "GamingCheck"); break;
        }
    }

    static void Open(string uri)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true }); } catch (Exception) { }
    }

    public void Stop() => stopped = true;
}
