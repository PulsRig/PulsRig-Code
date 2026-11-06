using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// Digitales PC-Scheckheft: links Zusammenfassung, Eintrag von Hand und Bericht zum Verkauf, rechts alle Einträge nach
// Jahren. Die automatischen Einträge schreibt die Prüfung beim Start (Scheckheftdaten.Update).
sealed class ScheckheftPage : UserControl, IPage
{
    const string Lila = "#8C6BD6";

    readonly bool demo;
    readonly Grid root = new();
    readonly TextBox text = new(), detail = new();
    string kind = "cleaning", saved = "";
    bool adding, stopped;

    public ScheckheftPage(bool demo)
    {
        this.demo = demo;
        Content = root;
        foreach (var box in new[] { text, detail })
        {
            box.Height = 34; box.FontSize = 13.5; box.VerticalContentAlignment = VerticalAlignment.Center; box.Padding = new Thickness(8, 0, 8, 0); box.Margin = new Thickness(0, 4, 0, 10);
            box.Background = Ui.Brush("#0B0710"); box.Foreground = Ui.Res("Text"); box.CaretBrush = Ui.Res("Text"); box.BorderBrush = Ui.Res("KarteRand");
        }
        System.Windows.Automation.AutomationProperties.SetName(text, "Was wurde gemacht?");
        System.Windows.Automation.AutomationProperties.SetName(detail, "Einzelheiten");
        Scheckheftdaten.Changed += Fill;
        Fill();
    }

    static List<HeftEintrag> Demo()
    {
        var now = DateTime.Now;
        string D(int days) => Scheckheft.Stamp(now.AddDays(-days));
        return new()
        {
            new() { D = D(2), Kind = "test", Title = "Benchmark", Sub = "Prozessor 612 / 4.880 · Grafikkarte 18.240 · Laufwerk 3.410 MB/s" },
            new() { D = D(9), Kind = "driver", Title = "Treiber NVIDIA GeForce RTX 3080", Sub = "32.0.15.8129 → 32.0.15.8157 (von Windows) · Probezeit bestanden" },
            new() { D = D(40), Kind = "temp", Title = "Temperaturen im " + now.AddDays(-40).ToString("MMMM yyyy", Ui.De), Sub = "14 Sitzungen · Prozessor höchstens 78 °C · Grafikkarte höchstens 71 °C" },
            new() { D = D(120), Kind = "cleaning", Title = "Staub entfernt, Wärmeleitpaste erneuert", Sub = "Grafikkarte danach 6 °C kühler", Manual = true },
            new() { D = D(300), Kind = "hardware", Title = "Arbeitsspeicher erweitert", Sub = "16 GB → 32 GB" },
            new() { D = D(420), Kind = "hardware", Title = "Scheckheft begonnen", Sub = "AMD Ryzen 5 3600 · NVIDIA GeForce RTX 3080 · 16 GB · 2 Laufwerk(e)" },
        };
    }

    static string Tone(string kind) => kind switch { "hardware" or "upgrade" => "accent", "cleaning" or "test" => "good", "repair" => "warn", _ => "" };

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        var entries = demo ? Demo() : Scheckheftdaten.Entries();

        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "PC-Scheckheft", FontSize = 26, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        left.Children.Add(new TextBlock { Text = "Tests, Temperaturen, Treiberwechsel, Aufrüstungen und Reinigungen über die ganze Lebenszeit des PCs – zum Mitgeben beim Verkauf.",
            FontSize = 13, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        if (adding) AddForm(left);
        else
        {
            var add = NeuinstallPage.Big("Eintrag hinzufügen", true);
            add.Click += (_, _) => { adding = true; text.Text = detail.Text = ""; Fill(); };
            left.Children.Add(add);
            var report = NeuinstallPage.Big("Verkaufsbericht speichern", false);
            report.Click += (_, _) => Save(entries);
            left.Children.Add(report);
        }
        left.Children.Add(new TextBlock { Text = Scheckheft.Summary(entries), FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        if (saved.Length > 0) left.Children.Add(new TextBlock { Text = saved, FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), LineHeight = 17 });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        var list = new StackPanel();
        if (Scheckheft.CleaningHint(entries, DateTime.Now) is { } hint)
            list.Children.Add(NeuinstallPage.Row("Reinigung", hint, ("Hinweis", "warn"), "Eintragen", () => { adding = true; kind = "cleaning"; Fill(); }));
        if (entries.Count == 0)
            list.Children.Add(NeuinstallPage.Row("PulsRig schreibt ab jetzt mit",
                "Bei jedem Start übernimmt PulsRig neue Benchmarks, Stabilitätstests, Treiberwechsel, Windows-Updates, die Temperaturen beim Spielen und getauschte Bauteile. Reinigungen und Reparaturen trägst du von Hand ein.", ("ab heute", "accent")));
        foreach (var year in entries.GroupBy(e => e.D.Length >= 4 ? e.D.Substring(0, 4) : ""))
        {
            list.Children.Add(NeuinstallPage.Head(year.Key + " · " + year.Count() + (year.Count() == 1 ? " EINTRAG" : " EINTRÄGE")));
            foreach (var e in year)
            {
                var state = (Scheckheft.KindName(e.Kind), Tone(e.Kind));
                var sub = Scheckheft.Day(e.D) + (e.Sub.Length > 0 ? " · " + e.Sub : "");
                list.Children.Add(e.Manual && !demo
                    ? NeuinstallPage.Row(e.Title, sub, state, "Löschen", () => { if (Bestaetigung.Ask(this, "Diesen Eintrag löschen?", e.Title, "Löschen")) Scheckheftdaten.Remove(e); })
                    : NeuinstallPage.Row(e.Title, sub, state));
            }
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    void AddForm(StackPanel left)
    {
        var kinds = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        foreach (var k in Scheckheft.ManualKinds)
        {
            var b = NeuinstallPage.Big(Scheckheft.KindName(k), k == kind);
            b.Margin = new Thickness(0, 0, 8, 8);
            b.Click += (_, _) => { kind = k; Fill(); };
            kinds.Children.Add(b);
        }
        left.Children.Add(kinds);
        // text und detail bleiben über Fill() hinweg bestehen (Eingaben gehen nicht verloren), hängen aber noch im alten Panel
        foreach (var box in new[] { text, detail }) (box.Parent as Panel)?.Children.Remove(box);
        left.Children.Add(Ui.Text("Was wurde gemacht?", 12.5, "Halbleise", bold: true));
        left.Children.Add(text);
        left.Children.Add(Ui.Text("Einzelheiten (freiwillig)", 12.5, "Halbleise", bold: true));
        left.Children.Add(detail);
        var buttons = new WrapPanel();
        var ok = NeuinstallPage.Big("Speichern", true);
        ok.Margin = new Thickness(0, 0, 8, 0);
        ok.Click += (_, _) =>
        {
            var title = text.Text.Trim();
            if (title.Length == 0) title = Scheckheft.KindName(kind);
            adding = false;
            if (!demo) Scheckheftdaten.Add(new HeftEintrag { D = Scheckheft.Stamp(DateTime.Now), Kind = kind, Title = title, Sub = detail.Text.Trim(), Manual = true });
            else Fill();
        };
        var cancel = NeuinstallPage.Big("Abbrechen", false);
        cancel.Click += (_, _) => { adding = false; Fill(); };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        left.Children.Add(buttons);
        Dispatcher.BeginInvoke(() => text.Focus());
    }

    void Save(List<HeftEintrag> entries)
    {
        saved = "Speichere den Bericht …";
        Fill();
        Task.Run(() =>
        {
            try
            {
                var parts = Scheckheftdaten.CurrentParts();
                var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "PulsRig");
                Directory.CreateDirectory(folder);
                var file = Path.Combine(folder, "PC-Scheckheft-" + DateTime.Now.ToString("yyyy-MM-dd") + ".html");
                File.WriteAllText(file, Scheckheft.Html(entries, parts, DateTime.Now));
                Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
                return "Gespeichert: " + file;
            }
            catch (Exception e) { return Bedienfehler.Text(e); }
        }).ContinueWith(t => Dispatcher.BeginInvoke(() => { saved = t.Result; Fill(); }));
    }

    public void Stop()
    {
        stopped = true;
        Scheckheftdaten.Changed -= Fill;
    }
}
