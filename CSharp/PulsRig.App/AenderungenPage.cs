using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// "Was hat sich geändert?" wie Open-ChangesSheet: Reiter seit gestern, 7 und 30 Tage, die Unterschiede in einfachen
// Sätzen (Core.Aenderungen), Abstürze ganz oben. Die Bilder schreibt die Prüfung beim Start (Tagesbilder).
sealed class AenderungenPage : UserControl, IPage
{
    const string Lila = "#8C6BD6";
    static int lastTab;

    readonly MainWindow main;
    readonly bool demo;
    readonly Grid root = new();
    int tab = lastTab;
    bool stopped;

    public AenderungenPage(MainWindow main, bool demo)
    {
        this.main = main;
        this.demo = demo;
        Content = root;
        Tagesbilder.Changed += Fill;
        Fill();
    }

    // für -Demo und Bilder: eine Woche mit neuem Grafiktreiber, Programm und Autostart-Eintrag
    static (Tagesbild? Old, List<Aenderung> Changes, string First) Demo(int days)
    {
        var now = DateTime.Now;
        var old = new Tagesbild { D = Aenderungen.DayKey(now.AddDays(-Math.Min(days, 7))), Windows = "26100.6899 (24H2)", Plan = "Ausbalanciert",
            Programs = { "Steam|2.10|20260901", "Discord|1.0.9200|20260910" }, Autostart = { "Steam|an" }, Drivers = { @"PCI\VEN_10DE&DEV_2216|NVIDIA GeForce RTX 3080|32.0.15.8129|DISPLAY" } };
        var today = new Tagesbild { D = Aenderungen.DayKey(now), Windows = days == 1 ? old.Windows : "26100.7019 (24H2)", Plan = "Ausbalanciert",
            Programs = { "Steam|2.10|20260901", "Discord|1.0.9201|20260910", "OBS Studio|31.1|20261024" }, Autostart = { "Steam|an", "OBS Studio|an" },
            Drivers = { @"PCI\VEN_10DE&DEV_2216|NVIDIA GeForce RTX 3080|" + (days == 1 ? "32.0.15.8129" : "32.0.15.8157") + "|DISPLAY" } };
        if (days == 1) { old.Programs = today.Programs; old.Autostart = today.Autostart; }
        return (old, Aenderungen.Compare(old, today), Aenderungen.Day(Aenderungen.DayKey(now.AddDays(-7))));
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        var days = new[] { 1, 7, 30 }[tab];
        var snaps = Tagesbilder.Snaps;
        Tagesbild? old;
        List<Aenderung> changes;
        string first;
        if (demo) (old, changes, first) = Demo(days);
        else
        {
            (old, changes) = Tagesbilder.Compare(days);
            first = snaps.Count > 0 ? Aenderungen.Day(snaps[0].D) : "heute";
        }

        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "Was hat sich geändert?", FontSize = 26, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        left.Children.Add(new TextBlock { Text = "Unterschiede zu früheren Tagen, die PulsRig mitgeschrieben hat", FontSize = 13, Foreground = Ui.Res("Leise"),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        foreach (var (i, label) in new[] { (0, "Seit gestern"), (1, "7 Tage"), (2, "30 Tage") })
        {
            var b = NeuinstallPage.Big(label, i == tab);
            b.Click += (_, _) => { tab = lastTab = i; Fill(); };
            left.Children.Add(b);
        }
        var history = NeuinstallPage.Big("Treiberverlauf", false);
        history.Margin = new Thickness(0, 18, 0, 0);
        history.Click += (_, _) => { main.GoTop("tools"); main.Go("manage"); };
        left.Children.Add(history);
        var state = old == null ? "Mitgeschrieben wird bei jedem Start von PulsRig"
            : demo || Aenderungen.Exact(old, days, DateTime.Now) ? "Verglichen mit dem " + Aenderungen.Day(old.D) + " · mitgeschrieben seit " + first
            : "Mitgeschrieben erst seit " + first + ": verglichen mit diesem Tag";
        left.Children.Add(new TextBlock { Text = state, FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        var list = new StackPanel();
        if (old == null)
        {
            list.Children.Add(NeuinstallPage.Row("PulsRig schreibt ab jetzt mit",
                "Seit " + first + " merkt sich PulsRig einmal am Tag Windows-Stand, Programme, Autostart, wichtige Treiber und Energieplan. Ab morgen steht hier, was sich seitdem geändert hat.", ("ab heute", "accent")));
        }
        else
        {
            list.Children.Add(NeuinstallPage.Head(changes.Count == 0 ? "unverändert" : changes.Count == 1 ? "1 Änderung" : changes.Count + " Änderungen"));
            foreach (var change in changes)
            {
                var (action, run) = change.Kind switch
                {
                    "crashes" => ("Ansehen", (Action?)(() => { main.GoTop("hw"); main.Go("crash"); })),
                    "autostart" when change.Tone == "warn" => ("Autostart", () => { main.GoTop("tools"); main.Go("clean"); }),
                    _ => ("", null),
                };
                list.Children.Add(NeuinstallPage.Row(change.Title, change.Sub, change.Tone.Length > 0 ? ("", change.Tone) : null, action, run));
            }
            if (changes.Count == 0)
                list.Children.Add(NeuinstallPage.Row("Nichts geändert seit " + Aenderungen.Day(old.D),
                    "Windows, Programme, Autostart, wichtige Treiber und Energieplan sind wie damals, und es gab keine Abstürze.", ("unverändert", "good")));
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    public void Stop()
    {
        stopped = true;
        Tagesbilder.Changed -= Fill;
    }
}
