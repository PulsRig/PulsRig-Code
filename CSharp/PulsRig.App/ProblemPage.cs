using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// "Was ist los?" wie PulsRig-Problem.ps1: vom Problem zur Ursache. Oben wählt man, was nicht stimmt; darunter stehen
// die passenden Prüfungen in der Reihenfolge, in der sie am häufigsten die Ursache finden. Jede Zeile sagt, was PulsRig
// schon weiß, und führt mit einem Klick zur Prüfung, zum Werkzeug oder zur Seite. Geändert wird hier nichts.
sealed class ProblemPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";
    static readonly string[] Tabs = { "Spiele ruckeln", "Stürzt ab", "Ist langsam", "Kein Ton", "Internet", "Sonstiges" };

    // Do: wohin der Knopf führt; Known: was PulsRig dazu schon weiß (leer: nichts anzuzeigen)
    sealed record Zeile(string Title, string Sub, string Do, string Action, string Known = "");

    static int lastTab;
    readonly MainWindow main;
    readonly Grid root = new();
    int tab;
    List<(string Name, string Where)>? hddGames;
    int gameCount = -1;
    bool stopped;

    public ProblemPage(MainWindow main)
    {
        this.main = main;
        tab = lastTab;
        Content = root;
        Fill();
        Hw.Changed += Fill;
        foreach (var what in new[] { "crash", "drives", "ram" }) Hw.Load(what);
        // Spiele und ihre Laufwerke im Hintergrund (für "Spiele ruckeln")
        Task.Run(() =>
        {
            var games = Werkzeugpruefung.KnownGames();
            var drives = Abfragen.Drives();
            var hdd = new List<(string, string)>();
            foreach (var g in games.Values.OrderBy(g => g.Name))
            {
                var letter = g.Path.Length > 1 && g.Path[1] == ':' ? g.Path[..1].ToUpperInvariant() : "";
                if (drives.Disks.FirstOrDefault(d => d.Letters.Contains(letter)) is { Media: "HDD" }) hdd.Add((g.Name, letter + ":"));
            }
            return (hdd, games.Count);
        }).ContinueWith(t => Dispatcher.BeginInvoke(() => { if (t.IsCompletedSuccessfully) { (hddGames, gameCount) = t.Result; } else gameCount = 0; Fill(); }));
    }

    static IEnumerable<Zeile> Rows(int tab) => tab switch
    {
        0 => new Zeile[]
        {
            new("Gaming-Check", "Bildwiederholrate, Energieplan, voller Takt des Speichers: sieben Einstellungen, die fürs Spielen zählen", "games", "Prüfen"),
            new("Grafiktreiber aktuell?", "Ein Scan prüft NVIDIA, AMD und Windows Update auf neuere Treiber", "scan", "Scan starten", "scan"),
            new("Wird es zu heiß?", "Der Stabilitätstest lastet Prozessor und Grafikkarte voll aus und misst, ob der Takt einbricht", "stress", "Testen", "stress"),
            new("Wie warm wird es beim Spielen?", "Der Helfer neben der Uhr zeichnet jede Spielsitzung auf: Temperaturen, Takt und ob etwas drosselt", "recordings", "Ansehen"),
            new("Lässt die Kühlung nach?", "Vergleicht Temperaturen bei gleicher Leistung über Wochen: Wird es wärmer, ist es Zeit zum Entstauben", "wear", "Ansehen", "cooling"),
            new("Programme im Hintergrund", "Der Boost schaltet vor dem Spielen Dienste und speicherhungrige Programme ab", "boost", "Zum Boost"),
            new("Was startet mit Windows?", "Jedes Programm im Autostart kostet Speicher und Rechenzeit, auch beim Spielen", "clean", "Ansehen"),
        },
        1 => new Zeile[]
        {
            new("Abstürze verstehen", "Bluescreens, plötzliches Ausgehen und Grafik-Aussetzer der letzten 30 Tage, jeweils mit Erklärung", "crash", "Ansehen", "crashes"),
            new("Neuer Treiber schuld?", "Seit einem neuen Treiber mehr Abstürze? PulsRig vergleicht die Tage davor und danach", "crash", "Ansehen", "probation"),
            new("Arbeitsspeicher testen", "Fehlerhafter Speicher ist eine häufige Ursache für Bluescreens", "ram", "Prüfen", "memory"),
            new("Unter Last stabil?", "Der Stabilitätstest zeigt, ob der PC bei voller Last abstürzt oder sich verrechnet", "stress", "Testen", "stress"),
            new("Laufwerke in Ordnung?", "Störungen und Zustand der Laufwerke aus dem Protokoll von Windows", "drives", "Prüfen", "drives"),
        },
        2 => new Zeile[]
        {
            new("Was startet mit Windows?", "Viele Programme im Autostart machen den Start und den Alltag langsam", "clean", "Ansehen"),
            new("Ist das Laufwerk voll?", "Unter 10 Prozent freiem Platz wird Windows spürbar langsamer", "clean", "Platz schaffen", "space"),
            new("Laufwerke in Ordnung?", "Ein Laufwerk mit Störungen oder nachlassendem Tempo bremst alles aus", "drives", "Prüfen", "drives"),
            new("Arbeitsspeicher voll?", "Die Boost-Seite zeigt, wie viel belegt ist und welche Programme am meisten brauchen", "boost", "Ansehen"),
            new("Was hat sich geändert?", "Seit wann ist es langsam? PulsRig vergleicht Windows, Programme, Autostart und Treiber mit früheren Tagen", "changes", "Ansehen"),
            new("Wirklich langsamer als früher?", "Der Benchmark misst Prozessor, Speicher, Grafikkarte und Laufwerk und vergleicht mit früheren Läufen", "bench", "Messen"),
            new("Was bremst im Spiel?", "Der Aufrüst-Berater misst eine Minute im Spiel und sagt, welches Bauteil sich zum Aufrüsten lohnt", "upgrade", "Messen"),
        },
        3 => new Zeile[]
        {
            new("Tonstörung beheben", "Prüft Dienste, Stummschaltung und Ausgabegerät und repariert in Stufen", "repair", "Starten"),
            new("Audiotreiber aktuell?", "Ein Scan findet neuere Treiber für Soundkarte und Headset", "scan", "Scan starten", "scan"),
            new("Gerät mit Fehler?", "Erkennt Geräte, die Windows mit Fehler meldet, und richtet sie neu ein", "repair", "Starten"),
        },
        4 => new Zeile[]
        {
            new("Ping-Test", "Verzögerung, Schwankung und Verlust: zeigt, ob das Problem zu Hause (WLAN, Router) oder beim Anbieter liegt", "ping", "Messen"),
            new("Netzwerkfehler beheben", "Testet die Verbindung Schritt für Schritt und repariert in Stufen", "repair", "Starten"),
            new("Netzwerktreiber aktuell?", "Ein Scan findet neuere Treiber für WLAN und Netzwerkkarte", "scan", "Scan starten", "scan"),
            new("WLAN bricht im Standby ab?", "Der Standby-Detektiv zeigt, welche Geräte den PC wecken dürfen", "repair", "Ansehen"),
        },
        _ => new Zeile[]
        {
            new("Bild unscharf oder falsche Auflösung", "Prüft Grafiktreiber und empfohlene Auflösung", "repair", "Starten"),
            new("Pixelfehler, Lichthof oder Schlieren?", "Der Monitor-Test zeigt Farbflächen und ein Bewegungsbild im Vollbild", "monitor", "Testen"),
            new("Ein Gerät geht nicht", "Erkennt fehlerhafte Geräte und richtet sie neu ein", "repair", "Starten"),
            new("Controller oder Maus spinnt", "Stick-Drift, Tasten, Abfragerate und ungewollte Doppelklicks prüfen", "input", "Testen"),
            new("PC wacht von selbst auf", "Der Standby-Detektiv zeigt, was ihn weckt oder wach hält", "repair", "Ansehen"),
            new("Hilfe holen", "Ein Diagnose-Paket fasst alles für die Fehlersuche zusammen", "report", "Erstellen"),
        },
    };

    // was PulsRig aus der letzten Prüfung weiß, wie Get-ProblemState; null: noch nicht geprüft
    static (string Text, string Tone)? Known(string name)
    {
        switch (name)
        {
            case "scan":
                if (Treiberscan.Last is { } s) return s.Newer > 0 ? (s.Newer + " offen", "warn") : ("aktuell", "good");
                break;
            case "stress":
                if (Belastung.Last is { } b) return (b.Title.Split(" – ")[0], b.Tone);
                break;
            case "probation":
                if (Probezeitlauf.Warning() != null) return ("auffällig", "warn");
                if (Probezeitlauf.Entries.Count > 0) return ("unauffällig", "good");
                break;
            case "cooling":
                try { return Verschleiss.CoolingState(Verschleissdaten.Points()); } catch (Exception) { }
                break;
            case "crashes":
                if (Hw.Crashes is { } c && Abstuerze.Card(c, DateTime.Today) is { } card) return (card.Text, card.Tone);
                break;
            case "memory":
                if (Hw.Memory is { } m) return Hw.MemoryState(m);
                break;
            case "drives":
                if (Hw.Drives is { } d) return Hw.DriveState(d);
                break;
            case "space":
                if (Hw.Drives?.Volumes.FirstOrDefault(v => v.Letter.StartsWith("C", StringComparison.OrdinalIgnoreCase)) is { Size: > 0 } v)
                {
                    var used = (int)Math.Round(100 * (1 - v.Free / v.Size));
                    return ("C: " + used + " % belegt", used >= 90 ? "warn" : "good");
                }
                break;
        }
        return null;
    }

    void Go(string to)
    {
        switch (to)
        {
            case "scan": main.GoTop("home"); Treiberscan.Start(); break;
            case "recordings": SensorPage.Next = 1; main.Go("sensors"); break;
            case "wear": SensorPage.Next = 2; main.Go("sensors"); break;
            case "boost": main.GoTop("boost"); break;
            case "monitor": Monitortest.Open(main); break;
            default: main.Go(to); break;
        }
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        // links: Frage und Auswahl des Problems
        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "Was ist los?", FontSize = 26, FontWeight = FontWeights.SemiBold });
        left.Children.Add(new TextBlock { Text = "Problem wählen: PulsRig zeigt, was es schon weiß, und was als Nächstes zu prüfen ist", FontSize = 13, Foreground = Ui.Res("Leise"),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        for (var i = 0; i < Tabs.Length; i++)
        {
            var n = i;
            var on = i == tab;
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 42, Tag = "14", Margin = new Thickness(0, 0, 0, 8), Padding = new Thickness(16, 0, 16, 0),
                Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(on ? 0 : 1),
                HorizontalContentAlignment = HorizontalAlignment.Left, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(Tabs[i], 13.5, "Text", bold: true) };
            b.Click += (_, _) => { tab = lastTab = n; Fill(); };
            left.Children.Add(b);
        }
        left.Children.Add(new TextBlock { Text = "Am besten von oben nach unten: die ersten Punkte finden die häufigsten Ursachen", FontSize = 12, Foreground = Ui.Res("Halbleise"),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        // rechts: schon Gefundenes, dann die Prüfungen
        var list = new StackPanel();
        if (tab is 0 or 1 && Hw.Crashes is { } c)
        {
            var found = Abstuerze.Findings(c, false).Where(f => tab == 1 || f.Graphics).Take(4).ToList();
            if (found.Count > 0)
            {
                list.Children.Add(Head("SCHON GEFUNDEN"));
                foreach (var f in found)
                {
                    var act = Hardwaremodell.CrashAct(f, main);
                    list.Children.Add(Row(f.Title, f.Sub, (f.State, f.Tone), f.Action.Length > 0 ? f.Action : "", f.Action.Length > 0 ? act.Run : null));
                }
            }
        }
        list.Children.Add(Head(tab == 0 ? "DIE HÄUFIGSTEN URSACHEN" : tab == 5 ? "WEITERE PROBLEME" : "DER REIHE NACH"));
        var rows = Rows(tab).ToList();
        // Akku nur auf Notebooks und Tablets
        if (tab == 5 && AkkuPage.HasBattery) rows.Insert(rows.Count - 1, new("Akku hält nicht mehr lange", "Wie viel der Akku noch fasst, wie oft er geladen wurde und wie lange er laut Windows hält", "battery", "Ansehen"));
        foreach (var r in rows)
        {
            var state = r.Known.Length == 0 ? ((string, string)?)null : Known(r.Known) ?? ("noch nicht geprüft", "");
            var to = r.Do;
            list.Children.Add(Row(r.Title, r.Sub, state, r.Action, () => Go(to)));
        }
        if (tab == 0)
        {
            list.Children.Add(Head("DEINE SPIELE"));
            if (gameCount < 0) list.Children.Add(Row("Suche die Spiele …", "", null, "", null));
            else if (gameCount == 0) list.Children.Add(Row("Windows kennt noch keine Spiele", "Sobald ein Spiel einmal gelaufen ist, steht es hier mit dem Laufwerk, auf dem es liegt.", null, "", null));
            else
            {
                foreach (var (name, where) in (hddGames ?? new()).Take(3))
                    list.Children.Add(Row(name, "Liegt auf " + where + ", einer Festplatte (HDD). Auf eine SSD verschoben lädt es schneller und ruckelt weniger beim Nachladen.", ("Festplatte", "warn"), "", null));
                list.Children.Add(Row(gameCount == 1 ? "Das Spiel einzeln prüfen" : "Alle " + gameCount + " Spiele einzeln prüfen", "Laufwerk, Temperaturen beim letzten Spielen und ob etwas gedrosselt hat", null, "Ansehen", () => main.Go("games")));
            }
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    static TextBlock Head(string text) => new() { Text = text, FontSize = 10.5, FontFamily = (FontFamily)Application.Current.FindResource("Mono"), Foreground = Ui.Res("Leise"), Margin = new Thickness(2, 6, 0, 8) };

    static Border Row(string title, string sub, (string Text, string Tone)? state, string action, Action? run)
    {
        var color = state?.Tone switch { "good" => Gruen, "warn" => Bernstein, "bad" => Beere, _ => Lila };
        var grid = new Grid { MinHeight = 64 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
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
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (state is { } st && st.Text.Length > 0)
        {
            var pill = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 12, 0), Child = Ui.Text(st.Text, 11, st.Tone.Length > 0 ? color : "Leise") };
            Grid.SetColumn(pill, 2);
            grid.Children.Add(pill);
        }
        if (action.Length > 0)
        {
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 34, MinWidth = 96, Padding = new Thickness(14, 0, 14, 0), Tag = "17", VerticalAlignment = VerticalAlignment.Center,
                Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), HorizontalContentAlignment = HorizontalAlignment.Center,
                Content = Ui.Text(action, 12.5, "Text", bold: true), IsEnabled = run != null, Opacity = run != null ? 1 : 0.5 };
            if (run != null) b.Click += (_, _) => run();
            Grid.SetColumn(b, 3);
            grid.Children.Add(b);
        }
        return new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid };
    }

    public void Stop()
    {
        stopped = true;
        Hw.Changed -= Fill;
    }
}
