using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Laufwerke wie im Entwurf: eine Karte je Laufwerksbuchstabe mit Zustand, Belegung, Temperatur und Störungen
sealed class DrivesPage : UserControl, IPage
{
    readonly bool demo;
    readonly UniformGrid grid = new() { Columns = 3 };
    bool stopped;

    public DrivesPage(bool demo)
    {
        this.demo = demo;
        Content = grid;
        Fill();
        Hw.Changed += Fill;
        Tempotest.Changed += Fill;
        if (!demo) Hw.Load("drives");
    }

    sealed record Card(string Letter, string Kind, double Used, string Free, string Tag, bool Ok, string Temperature, string Faults, bool? FaultsOk, string Action);

    List<Card> Cards()
    {
        if (demo)
            return new()
            {
                new("C:", "NVMe-SSD · Windows", 0.62, "356 GB", "gesund", true, "38 °C", "keine", true, "Tempo messen"),
                new("D:", "SSD · Spiele", 0.35, "610 GB", "gesund", true, "34 °C", "keine", true, "Tempo messen"),
                new("E:", "Festplatte (HDD) · Daten", 0.81, "190 GB", "ansehen", false, "41 °C", "2 Aussetzer", false, "Störungen ansehen"),
            };
        var cards = new List<Card>();
        if (Hw.Drives is not { } d) return cards;
        var system = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:").TrimEnd(':');
        foreach (var v in d.Volumes)
        {
            var disk = d.Disks.FirstOrDefault(x => x.Number == v.Disk);
            var kind = disk == null ? "Laufwerk" : disk.Bus == "NVMe" ? "NVMe-SSD" : disk.Media == "SSD" ? "SSD" : disk.Media == "HDD" ? "Festplatte (HDD)" : "Laufwerk";
            var use = v.Letter == system ? "Windows" : v.Label;
            var faults = disk == null ? 0 : Hw.Faults(d, disk.Number);
            var ok = (disk == null || disk.Health == "Healthy") && faults == 0;
            cards.Add(new(v.Letter + ":", use.Length > 0 ? kind + " · " + use : kind, v.Size > 0 ? 1 - v.Free / v.Size : 0, Ui.Size(v.Free),
                ok ? "gesund" : "ansehen", ok, disk?.Temperature is { } t ? t + " °C" : App.IsAdmin ? "–" : "nur mit Adminrechten",
                d.Faults is { Log: false } ? "nicht lesbar" : faults == 0 ? "keine" : faults == 1 ? "1 Störung" : faults + " Störungen",
                d.Faults is { Log: false } ? null : faults == 0, Tempotest.Results.ContainsKey(v.Letter) ? "Erneut messen" : "Tempo messen"));
        }
        return cards;
    }

    void Fill()
    {
        if (stopped) return;
        grid.Children.Clear();
        var cards = Cards();
        if (cards.Count == 0)
        {
            grid.Children.Add(new TextBlock { Text = Hw.Drives == null ? "Lese die Laufwerke …" : "Windows meldet keine Laufwerke.", Foreground = Ui.Res("Leise"), FontSize = 13 });
            return;
        }
        grid.Columns = Math.Clamp(cards.Count, 3, 4);
        foreach (var c in cards) grid.Children.Add(CardView(c));
        Ui.Arrive(grid.Children.Cast<UIElement>());
    }

    static Border CardView(Card c)
    {
        var edgeColor = c.Ok ? "#666D43C9" : "#99F2B661";
        var edge = new LinearGradientBrush { StartPoint = new Point(0.25, 0), EndPoint = new Point(0.75, 1) };
        edge.GradientStops.Add(new GradientStop(Ui.Hex(edgeColor), 0));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.45));
        var tag = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(11, 4, 11, 4), Background = Ui.Brush(c.Ok ? "#10261C" : "#2A2012"), VerticalAlignment = VerticalAlignment.Center,
            Child = Ui.Text(c.Tag, 11.5, c.Ok ? Hardwaremodell.Good : Hardwaremodell.Warn) };
        var head = new DockPanel();
        DockPanel.SetDock(tag, Dock.Right);
        head.Children.Add(tag);
        head.Children.Add(Ui.Text(c.Letter, 40, "Text", bold: true, mono: true));
        var bar = Ui.Bar(c.Used, "#6D43C9", 10, c.Ok ? null : "#F2B661");
        ((Border)bar).Background = Ui.Brush("#1A1224");
        bar.Margin = new Thickness(0, 20, 0, 0);
        var used = Ui.Text(Math.Round(c.Used * 100) + " % belegt · " + c.Free + " frei", 12, "Leise");
        used.Margin = new Thickness(0, 6, 0, 0);
        var facts = new StackPanel { Margin = new Thickness(0, 16, 0, 0) };
        var letter = c.Letter.TrimEnd(':');
        var (speed, speedOk) = Tempotest.Measuring == letter ? ("misst …", (bool?)null)
            : Tempotest.Results.TryGetValue(letter, out var r) ? r.Error.Length > 0 ? ("nicht möglich", (bool?)false)
                : ("L " + Tempotest.Speed(r.Read) + " · S " + Tempotest.Speed(r.Write) + " MB/s", !Laufwerkstempo.Slow(r.Read, r.Write))
            : ("nicht gemessen", (bool?)null);
        foreach (var (k, v, good) in new[] { ("Temperatur", c.Temperature, (bool?)null), ("Störungen 30 T.", c.Faults, c.FaultsOk), ("Tempo", speed, speedOk) })
        {
            var row = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
            var value = Ui.Text(v, 12.5, good == null ? "Text" : good.Value ? Hardwaremodell.Good : Hardwaremodell.Warn);
            DockPanel.SetDock(value, Dock.Right);
            row.Children.Add(value);
            row.Children.Add(Ui.Text(k, 12.5, "Leise"));
            facts.Children.Add(new Border { BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(0, 0, 0, 8), Margin = new Thickness(0, 0, 0, 8), Child = row });
        }
        var action = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 40, Tag = "12", Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"),
            BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Bottom, HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            Content = Ui.Text(c.Action, 13, bold: true),
            ToolTip = Tempotest.Results.TryGetValue(letter, out var last) && last.Error.Length > 0 ? last.Error : "Schreibt eine Testdatei von bis zu 1 GB und löscht sie wieder. Richtwerte: Festplatte 80–200, SATA-SSD 400–550, NVMe-SSD ab 1.500 MB/s" };
        if (Tempotest.Measuring.Length > 0) { action.Opacity = 0.45; action.Cursor = System.Windows.Input.Cursors.Arrow; }
        else action.Click += (_, _) => Tempotest.Start(letter);
        var body = new DockPanel();
        var kind = Ui.Text(c.Kind, 13, "Leise");
        foreach (var top in new FrameworkElement[] { head, kind, bar, used, facts }) { DockPanel.SetDock(top, Dock.Top); body.Children.Add(top); }
        body.Children.Add(action);
        return new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = edge, Padding = new Thickness(22), Margin = new Thickness(7, 0, 7, 0),
            Background = new LinearGradientBrush(Ui.Hex("#0B0710"), Ui.Hex("#09060D"), 90), Child = body };
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Hw.Changed -= Fill;
        Tempotest.Changed -= Fill;
    }
}
