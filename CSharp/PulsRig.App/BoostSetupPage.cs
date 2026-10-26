using System.Diagnostics;
using System.Management;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Boost einrichten wie Open-BoostSheet: vier Listen zum Ankreuzen (Programme, Dienste, Weitere, Spiele), dazu die
// empfohlene Auswahl. Gespeichert wird in Boost und BoostGames der gemeinsamen Einstellungen. Angeboten werden nur
// Programme außerhalb von Core.Boost.Keep und Dienste aus der eigenen Liste oder fremder Hersteller ohne die
// geschützten (Core.Boost.IsServiceKept); was der Boost am Ende anfasst, prüft Spielboost noch einmal.
sealed class BoostSetupPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    sealed class Eintrag
    {
        public string Type = "", Name = "", Title = "", Sub = "", Value = "";
        public double Share;
        public bool Checked, Suggested;
    }

    sealed record Wahl(List<Eintrag> Apps, List<Eintrag> Services, List<Eintrag> Options, List<Eintrag> Games, bool AutoBoost);

    static readonly string[] TabNames = { "Programme", "Dienste", "Weitere", "Spiele" };

    readonly MainWindow window;
    readonly Grid root = new();
    Wahl? data;
    int tab;
    bool stopped;

    public BoostSetupPage(MainWindow window)
    {
        this.window = window;
        Content = root;
        Fill();
        Task.Run(() =>
        {
            Wahl? w = null;
            try { w = Read(); } catch (Exception) { }
            Dispatcher.BeginInvoke(() => { data = w; Fill(); });
        });
    }

    // wie Get-BoostChoices und Complete-BoostQuery
    static Wahl Read()
    {
        var settings = Altdaten.Settings();
        var plan = settings["Boost"];
        var chosenApps = Altdaten.List(plan, "Apps");
        var session = Process.GetCurrentProcess().SessionId;
        var own = Environment.ProcessId;
        var groups = Process.GetProcesses().Where(p => { try { return p.SessionId == session && p.Id != own && !Core.Boost.IsKept(p.ProcessName); } catch (Exception) { return false; } })
            .GroupBy(p => p.ProcessName, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                long bytes = g.Sum(p => { try { return p.WorkingSet64; } catch (Exception) { return 0L; } });
                var description = "";
                try { description = (g.OrderByDescending(p => p.WorkingSet64).First().MainModule?.FileVersionInfo.FileDescription ?? "").Trim(); } catch (Exception) { }
                return (Name: g.Key, Count: g.Count(), Bytes: bytes, Description: description);
            })
            .Where(a => a.Bytes >= 5L << 20).OrderByDescending(a => a.Bytes).ToList();
        double largest = Math.Max(1, groups.Select(a => (double)a.Bytes).DefaultIfEmpty(1).Max());
        Eintrag App((string Name, int Count, long Bytes, string Description) a) => new()
        {
            Type = "app", Name = a.Name, Title = a.Count > 1 ? a.Name + "   ×" + a.Count : a.Name, Sub = a.Description != a.Name ? a.Description : "",
            Value = (a.Bytes / (double)(1 << 20)).ToString("N0", Ui.De) + " MB", Share = a.Bytes / largest,
            Checked = chosenApps.Contains(a.Name, StringComparer.OrdinalIgnoreCase), Suggested = Core.Boost.SuggestApps.Contains(a.Name, StringComparer.OrdinalIgnoreCase),
        };
        var apps = groups.Where(a => Core.Boost.SuggestApps.Contains(a.Name, StringComparer.OrdinalIgnoreCase)).Select(App).ToList();
        // gemerkte Programme, die gerade nicht laufen, bleiben in der Auswahl sichtbar
        apps.AddRange(chosenApps.Where(n => !groups.Any(a => a.Name.Equals(n, StringComparison.OrdinalIgnoreCase))).Select(n => new Eintrag { Type = "app", Name = n, Title = n, Value = "läuft nicht", Checked = true }));
        apps.AddRange(groups.Where(a => !Core.Boost.SuggestApps.Contains(a.Name, StringComparer.OrdinalIgnoreCase)).Select(App));

        var chosenServices = plan?["Services"] is JsonArray ? Altdaten.List(plan, "Services") : null;
        var services = new List<Eintrag>();
        using (var s = new ManagementObjectSearcher("SELECT Name, DisplayName, Description, PathName FROM Win32_Service WHERE State = 'Running'"))
            foreach (ManagementObject o in s.Get())
            {
                var name = o["Name"]?.ToString() ?? "";
                var title = o["DisplayName"]?.ToString() ?? name;
                var description = (o["Description"]?.ToString() ?? "").Trim();
                var known = Core.Boost.Services.Contains(name, StringComparer.OrdinalIgnoreCase);
                if (!known)
                {
                    var company = "";
                    try { company = FileVersionInfo.GetVersionInfo(Core.Treiber.ResolveServicePath(o["PathName"]?.ToString())).CompanyName ?? ""; } catch (Exception) { }
                    if (company.Length == 0 || System.Text.RegularExpressions.Regex.IsMatch(company, "Microsoft|Windows") || Core.Boost.IsServiceKept(name + " " + title + " " + company)) continue;
                    if (description.Length == 0 || description == title) description = company;
                }
                services.Add(new() { Type = "service", Name = name, Title = title, Sub = description, Checked = chosenServices?.Contains(name, StringComparer.OrdinalIgnoreCase) ?? known, Suggested = known });
            }
        services = services.OrderBy(x => !x.Suggested).ThenBy(x => x.Title).ToList();

        var options = new List<Eintrag>
        {
            new() { Type = "option", Name = "PowerPlan", Title = "Energieplan „Höchstleistung“", Sub = "Stellt den Energieplan um und nach dem Spielen wieder zurück", Checked = Altdaten.Flag(plan, "PowerPlan", true), Suggested = true },
            new() { Type = "option", Name = "GameMode", Title = "Spielmodus von Windows", Sub = "Schaltet den Spielmodus ein, falls er ausgeschaltet ist", Checked = Altdaten.Flag(plan, "GameMode", true), Suggested = true },
            new() { Type = "option", Name = "Clipboard", Title = "Zwischenablage leeren", Sub = "Gibt den Speicher frei, den kopierte Inhalte belegen", Checked = Altdaten.Flag(plan, "Clipboard", false) },
        };

        var boostGames = Altdaten.List(settings, "BoostGames");
        var running = Process.GetProcesses().Select(p => { try { return p.ProcessName; } catch (Exception) { return ""; } }).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var knownGames = Werkzeugpruefung.KnownGames();
        var games = knownGames.Values.OrderBy(g => g.Name).Select(g => new Eintrag { Type = "game", Name = g.Exe, Title = g.Name, Sub = g.Exe + ".exe" + (running.Contains(g.Exe) ? " · läuft gerade" : ""),
            Checked = boostGames.Contains(g.Exe, StringComparer.OrdinalIgnoreCase) }).ToList();
        games.AddRange(boostGames.Where(e => !knownGames.ContainsKey(e)).Select(e => new Eintrag { Type = "game", Name = e, Title = e, Sub = "gemerkt, Windows kennt es nicht mehr", Checked = true }));
        return new(apps, services, options, games, Altdaten.Flag(settings, "AutoBoost", false));
    }

    List<Eintrag> Current => data == null ? new() : tab switch { 0 => data.Apps, 1 => data.Services, 2 => data.Options, _ => data.Games };

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        // Kopf: Reiter und "Empfohlene Auswahl"
        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var reco = Button("Empfohlene Auswahl", false);
        reco.Click += (_, _) => Recommend();
        DockPanel.SetDock(reco, Dock.Right);
        head.Children.Add(reco);
        var tabs = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < TabNames.Length; i++)
        {
            var n = i;
            var count = data == null ? 0 : (i switch { 0 => data.Apps, 1 => data.Services, 2 => data.Options, _ => data.Games }).Count(x => x.Checked);
            var b = Button(TabNames[i] + (count > 0 ? "  " + count : ""), i == tab);
            b.Margin = new Thickness(0, 0, 8, 0);
            b.Click += (_, _) => { tab = n; Fill(); };
            tabs.Children.Add(b);
        }
        head.Children.Add(tabs);
        root.Children.Add(head);

        var list = new StackPanel();
        if (data == null) list.Children.Add(Ui.Text("Lese Programme und Dienste …", 13, "Leise"));
        else
        {
            if (tab == 3 && !data.AutoBoost)
                list.Children.Add(Note("Boost automatisch ist ausgeschaltet – einschalten unter Optionen → Überwachung. Die Auswahl hier gilt dann sofort."));
            if (tab == 0) list.Children.Add(Note("Gewählte Programme schließt der Boost nach Rückfrage, wenn du ihn selbst einschaltest – der automatische Boost schließt nie Programme."));
            var items = Current;
            if (items.Count == 0) list.Children.Add(Note(tab == 1 ? "Keine entbehrlichen Dienste gefunden." : tab == 3 ? "Windows kennt auf diesem PC noch keine Spiele." : "Nichts zur Auswahl."));
            foreach (var item in items) list.Children.Add(Row(item));
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        Ui.Arrive(list.Children.Cast<UIElement>().Take(12));

        // Fuß: Zählung und Knöpfe wie Update-BoostState
        var foot = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var on = Spielboost.IsOn;
        var save = Button(on ? "Speichern" : "Nur speichern", false);
        save.Click += (_, _) => { Save(); window.Back(); };
        buttons.Children.Add(save);
        if (!on)
        {
            var start = Button("Speichern und Boost starten", true);
            start.Margin = new Thickness(8, 0, 0, 0);
            start.Click += (_, _) => { Save(); BoostPage.StartWhenReady = true; window.Back(); };
            buttons.Children.Add(start);
        }
        save.IsEnabled = data != null;
        DockPanel.SetDock(buttons, Dock.Right);
        foot.Children.Add(buttons);
        if (data != null)
        {
            int apps = data.Apps.Count(x => x.Checked), services = data.Services.Count(x => x.Checked), games = data.Games.Count(x => x.Checked);
            var text = "Gewählt: " + (apps == 1 ? "1 Programm" : apps + " Programme") + " · " + (services == 1 ? "1 Dienst" : services + " Dienste") + " · " + data.Options.Count(x => x.Checked) + " weitere"
                + (games > 0 ? " · " + (games == 1 ? "1 Spiel" : games + " Spiele") : "");
            var t = Ui.Text(text, 12.5, "Halbleise");
            t.VerticalAlignment = VerticalAlignment.Center;
            foot.Children.Add(t);
        }
        Grid.SetRow(foot, 2);
        root.Children.Add(foot);
    }

    static Border Note(string text) => new()
    {
        CornerRadius = new CornerRadius(14), Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 0, 10), Background = Ui.Brush("#06FFFFFF"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
        Child = new TextBlock { Text = text, FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap },
    };

    static Button Button(string label, bool primary) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(16, 0, 16, 0), Tag = "18",
        Background = primary ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(primary ? 0 : 1),
        VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 12.5, "Text", bold: true),
    };

    Border Row(Eintrag item)
    {
        var color = item.Type switch { "app" => Beere, "service" => Lila, "game" => Bernstein, _ => Gruen };
        var grid = new Grid { MinHeight = 56 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var box = new Border { Width = 20, Height = 20, CornerRadius = new CornerRadius(6), Margin = new Thickness(0, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center,
            Background = item.Checked ? Ui.Brush(color) : Brushes.Transparent, BorderBrush = Ui.Brush(item.Checked ? color : "#3A2F4A"), BorderThickness = new Thickness(1.5),
            Child = item.Checked ? Ui.Text("✓", 12, "#0B0710", bold: true) : null };
        if (box.Child is TextBlock check) { check.HorizontalAlignment = HorizontalAlignment.Center; check.VerticalAlignment = VerticalAlignment.Center; }
        grid.Children.Add(box);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 8, 12, 8) };
        text.Children.Add(Ui.Text(item.Title, 14, "Text", bold: true));
        if (item.Sub.Length > 0) { var s = Ui.Text(item.Sub, 12, "Leise"); s.Margin = new Thickness(0, 2, 0, 0); text.Children.Add(s); }
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (item.Value.Length > 0)
        {
            var right = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Width = 120 };
            var v = Ui.Text(item.Value, 12.5, "Halbleise", mono: true);
            v.HorizontalAlignment = HorizontalAlignment.Right;
            right.Children.Add(v);
            if (item.Share > 0) { var bar = Ui.Bar(item.Share, color, 4); bar.Margin = new Thickness(0, 6, 0, 0); right.Children.Add(bar); }
            Grid.SetColumn(right, 2);
            grid.Children.Add(right);
        }
        var row = new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(16), Background = Ui.Brush(item.Checked ? "#120B1A" : "#0B0710"),
            BorderBrush = Ui.Brush(item.Checked ? "#2E2140" : "#1A1224"), Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid, Cursor = System.Windows.Input.Cursors.Hand };
        row.MouseLeftButtonUp += (_, _) => { item.Checked = !item.Checked; Fill(); };
        return row;
    }

    // wie Set-BoostRecommended: die Spiele bleiben, wie sie sind
    void Recommend()
    {
        if (data == null) return;
        foreach (var item in data.Apps.Concat(data.Services).Concat(data.Options)) item.Checked = item.Suggested;
        Fill();
    }

    // wie Save-BoostSheet
    void Save()
    {
        if (data == null) return;
        Altdaten.Change(s =>
        {
            s["Boost"] = new JsonObject
            {
                ["Apps"] = Altdaten.Array(data.Apps.Where(x => x.Checked).Select(x => x.Name)),
                ["Services"] = Altdaten.Array(data.Services.Where(x => x.Checked).Select(x => x.Name)),
                ["PowerPlan"] = data.Options.First(x => x.Name == "PowerPlan").Checked,
                ["GameMode"] = data.Options.First(x => x.Name == "GameMode").Checked,
                ["Clipboard"] = data.Options.First(x => x.Name == "Clipboard").Checked,
            };
            s["BoostGames"] = Altdaten.Array(data.Games.Where(x => x.Checked).Select(x => x.Name));
        });
    }

    public void Stop() => stopped = true;
}
