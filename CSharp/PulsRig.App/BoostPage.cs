using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace PulsRig.App;

// Boost nach dem Entwurf: links die Spiel-Beschleunigung mit Ring und rundem Knopf, rechts sechs Kacheln mit echten
// Werten (Energieplan, freier Speicher, Dienste, Programme, Boost-Spiele, Gaming-Check). Eingeschaltet wird nur nach
// der Rückfrage mit allem, was sich ändert; Dienste anhalten braucht Adminrechte.
sealed class BoostPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0", Mint = "#8FF0BE";

    readonly MainWindow window;
    readonly Grid root = Ui.Mosaic(4, 3, 12);
    // bleibt über Seitenwechsel erhalten: beim nächsten Besuch steht die Seite gleich fertig da, statt zweimal aufzubauen
    static Spielboost.Plan? plan;
    // aus "Boost einrichten": nach dem Einlesen gleich einschalten (mit der üblichen Rückfrage)
    public static bool StartWhenReady;
    bool stopped, arrived;

    public BoostPage(MainWindow window)
    {
        this.window = window;
        Content = root;
        Fill();
        Spielboost.Changed += Refresh;
        Load();
    }

    void Load() => Task.Run(() =>
    {
        Spielboost.Plan? p = null;
        try { p = Spielboost.Prepare(); } catch (Exception) { }
        Dispatcher.BeginInvoke(() =>
        {
            if (stopped) return;
            plan = p;
            Fill();
            if (StartWhenReady && p != null) { StartWhenReady = false; Toggle(); }
        });
    });

    // nach dem Umschalten: neu einlesen, was der Boost jetzt anfassen würde
    void Refresh()
    {
        if (stopped) return;
        Fill();
        if (!Spielboost.Busy) Load();
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        var on = Spielboost.IsOn;
        var state = Spielboost.State();
        Ui.Place(root, Main(on, state), 0, 0, 2, 3);
        var tiles = Tiles(on, state);
        for (var i = 0; i < tiles.Count; i++) Ui.Place(root, tiles[i], 2 + i % 2, i / 2);
    }

    Border Main(bool on, Spielboost.Zustand? state)
    {
        var busy = Spielboost.Busy;
        var panel = new DockPanel();
        var kicker = Ui.Text("SPIEL-BESCHLEUNIGUNG", 10, "Leise", mono: true);
        var head = Ui.Text(busy ? Spielboost.Step : on ? "Volle Leistung fürs Spiel" : "Derzeit ausgeschaltet", 24, "Text", bold: true);
        head.Margin = new Thickness(0, 6, 0, 0);
        var sub = new TextBlock { Text = on ? "Alles wird beim Ausschalten wieder so, wie es war" + (state?.Time is { Length: > 0 } t ? " · an seit " + t : "") + "."
                : "Schafft vor dem Spielen Platz: Energieplan, entbehrliche Dienste und die Programme, die du dafür gewählt hast.",
            FontSize = 12.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0), LineHeight = 18 };
        // oben rechts: Boost einrichten (Programme, Dienste, Spiele wählen)
        var setup = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 32, Padding = new Thickness(14, 0, 14, 0), Tag = "16", Background = Ui.Brush("#140C1D"),
            BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text("Einrichten", 12, "Text", bold: true) };
        setup.Click += (_, _) => window.Go("boostsetup");
        var top = new DockPanel();
        DockPanel.SetDock(setup, Dock.Right);
        top.Children.Add(setup);
        top.Children.Add(kicker);
        kicker.VerticalAlignment = VerticalAlignment.Center;
        foreach (var e in new FrameworkElement[] { top, head, sub }) { DockPanel.SetDock(e, Dock.Top); panel.Children.Add(e); }

        // was der letzte Boost getan hat, als Schilder unten
        var chips = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center, MinHeight = 28 };
        if (on && state != null)
        {
            if (state.PowerPlan != null) chips.Children.Add(Chip("Energieplan umgestellt", "#B19FE0", "#160D29"));
            if (state.FreeAfter > state.FreeBefore) chips.Children.Add(Chip(Ui.Gb(state.FreeAfter - state.FreeBefore, "N1") + " freigemacht", Mint, "#10261C"));
            if (state.Services.Count > 0) chips.Children.Add(Chip(state.Services.Count + (state.Services.Count == 1 ? " Dienst" : " Dienste") + " pausiert", Beere, "#1B0916"));
            if (state.ClosedApps.Count > 0) chips.Children.Add(Chip(state.ClosedApps.Count + (state.ClosedApps.Count == 1 ? " Programm" : " Programme") + " geschlossen", "#F6C989", "#2A2112"));
            if (state.Priorities is { Count: > 0 } prio)
            {
                if (prio.Any(x => x.EndsWith("|spiel"))) chips.Children.Add(Chip("Spiel bevorzugt", "#B19FE0", "#160D29"));
                var back = prio.Count(x => x.EndsWith("|hintergrund"));
                if (back > 0) chips.Children.Add(Chip(back + (back == 1 ? " Hintergrundprozess" : " Hintergrundprozesse") + " zurückgestellt", Beere, "#1B0916"));
            }
        }
        if (Spielboost.Message.Length > 0) chips.Children.Add(Chip(Spielboost.Message, "#F6C989", "#2A2112"));
        DockPanel.SetDock(chips, Dock.Bottom);
        panel.Children.Add(chips);

        var center = new Grid { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Width = 210, Height = 210 };
        var breathe = new Ellipse { Width = 190, Height = 190, Fill = new RadialGradientBrush(Ui.Hex("#456D43C9"), Colors.Transparent), Opacity = busy ? 1 : on ? 0.8 : 0.35 };
        center.Children.Add(breathe);
        center.Children.Add(new Ellipse { Width = 194, Height = 194, Stroke = Ui.Brush("#1C1229"), StrokeThickness = 10 });
        var arcBrush = new LinearGradientBrush(Ui.Hex(Lila), Ui.Hex(Beere), 45);
        if (busy || on)
        {
            // läuft: ein Viertelbogen dreht sich; an: voller Ring mit Glühen
            var arc = new Ellipse { Width = 194, Height = 194, Stroke = arcBrush, StrokeThickness = 10, StrokeDashCap = PenLineCap.Round, Effect = Ui.Glow("#A8326F", busy ? 14 : 6),
                RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new RotateTransform(-90) };
            if (busy)
            {
                arc.StrokeDashArray = new DoubleCollection { 4.5, 14.5 };
                ((RotateTransform)arc.RenderTransform).BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(-90, 270, TimeSpan.FromSeconds(1.1)) { RepeatBehavior = RepeatBehavior.Forever });
            }
            center.Children.Add(arc);
        }
        var face = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        face.Children.Add(new Path { Data = Geometry.Parse("M13 2L4 14h7l-1 8 9-12h-7z"), Stroke = on ? Brushes.White : Ui.Brush("#6D43C9"), StrokeThickness = 2.2, Width = 26, Height = 26, Stretch = Stretch.Uniform,
            StrokeLineJoin = PenLineJoin.Round, HorizontalAlignment = HorizontalAlignment.Center });
        var big = Ui.Text(busy ? "…" : on ? "AN" : "AUS", 26, "Text", bold: true);
        big.HorizontalAlignment = HorizontalAlignment.Center;
        big.Margin = new Thickness(0, 4, 0, 0);
        face.Children.Add(big);
        var small = Ui.Text(busy ? "bitte warten" : on ? "Tippen zum Beenden" : plan == null ? "liest ein …" : "Tippen zum Starten", 11, "Leise");
        small.HorizontalAlignment = HorizontalAlignment.Center;
        face.Children.Add(small);
        var button = new Button { Style = (Style)Application.Current.FindResource("Flach"), Width = 150, Height = 150, Tag = "75", Content = face,
            Background = new RadialGradientBrush(Ui.Hex("#1F1331"), Ui.Hex("#0A0610")) { GradientOrigin = new Point(0.35, 0.3), Center = new Point(0.35, 0.3) },
            BorderBrush = Ui.Brush("#2F2147"), BorderThickness = new Thickness(1), IsEnabled = !busy && (on || plan != null),
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(button, "Boost umschalten");
        button.Click += (_, _) => Toggle();
        center.Children.Add(button);
        panel.Children.Add(center);

        var edge = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 1) };
        edge.GradientStops.Add(new GradientStop(Ui.Hex(on ? "#AA6D43C9" : "#506D43C9"), 0));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.35));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.7));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#55A8326F"), 1));
        var glow = new RadialGradientBrush(Ui.Hex(busy ? "#30A8326F" : on ? "#266D43C9" : "#086D43C9"), Colors.Transparent) { RadiusX = 0.6, RadiusY = 0.55 };
        var layer = new Grid();
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), Background = Ui.Brush("#0B0710") });
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), Background = glow, IsHitTestVisible = false });
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderBrush = edge, BorderThickness = new Thickness(1), Padding = new Thickness(24, 22, 24, 22), Child = panel });
        return new Border { Child = layer };
    }

    static Border Chip(string text, string color, string bg) => new()
    {
        CornerRadius = new CornerRadius(999), Padding = new Thickness(11, 5, 11, 5), Margin = new Thickness(3), Background = Ui.Brush(bg), BorderBrush = Ui.Alpha(color, "33"), BorderThickness = new Thickness(1),
        Child = Ui.Text(text, 11.5, color),
    };

    static Border Tile(string title, string state, string stateColor, string value, string note, string color, string tint, bool hit = false)
    {
        var panel = new DockPanel();
        var top = new DockPanel();
        var s = Ui.Text(state, 11, stateColor);
        DockPanel.SetDock(s, Dock.Right);
        top.Children.Add(s);
        top.Children.Add(Ui.Text(title, 12.5, color, bold: true));
        DockPanel.SetDock(top, Dock.Top);
        panel.Children.Add(top);
        var v = Ui.Text(value, 18, "Text", bold: true);
        v.Margin = new Thickness(0, 4, 0, 0);
        DockPanel.SetDock(v, Dock.Top);
        panel.Children.Add(v);
        var n = new TextBlock { Text = note, FontSize = 11.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, LineHeight = 16, VerticalAlignment = VerticalAlignment.Bottom, TextTrimming = TextTrimming.CharacterEllipsis };
        panel.Children.Add(n);
        var tile = Ui.Tile(color, tint, new Thickness(18, 16, 18, 16));
        tile.CornerRadius = new CornerRadius(22);
        tile.BorderBrush = Ui.Alpha(color, hit ? "66" : "2E");
        tile.Child = panel;
        return tile;
    }

    static string Names(IEnumerable<string> names, int max)
    {
        var list = names.ToList();
        return list.Count == 0 ? "" : string.Join(", ", list.Take(max)) + (list.Count > max ? " und " + (list.Count - max) + " weitere" : "");
    }

    List<Border> Tiles(bool on, Spielboost.Zustand? state)
    {
        var p = plan;
        var gray = "#8C819F";
        var tiles = new List<Border>();
        // Energieplan
        if (on && state?.PowerPlan != null) tiles.Add(Tile("Energieplan", "umgestellt", Mint, "Höchstleistung", "vorher " + state.PowerPlanName + " · wird beim Ausschalten zurückgestellt", Lila, "#160D29", true));
        else if (p?.Active is { } a) tiles.Add(Tile("Energieplan", p.SwitchPlan ? "bereit" : "passt", p.SwitchPlan ? gray : Mint, a.Name,
            p.SwitchPlan ? "wird beim Einschalten auf Höchstleistung gestellt" : "darf schon voll takten – bleibt, wie er ist", Lila, "#160D29"));
        else tiles.Add(Tile("Energieplan", "", gray, "–", "wird gelesen …", Lila, "#160D29"));
        // Arbeitsspeicher
        if (on && state != null && state.FreeAfter > state.FreeBefore)
            tiles.Add(Tile("Arbeitsspeicher frei", "+" + Ui.Gb(state.FreeAfter - state.FreeBefore, "N1"), Mint, Ui.Gb(p?.Free ?? state.FreeAfter, "N1"), "vorher " + Ui.Gb(state.FreeBefore, "N1") + " frei", "#A8326F", "#1F0A19", true));
        else tiles.Add(Tile("Arbeitsspeicher frei", "live", gray, p != null ? Ui.Gb(p.Free, "N1") : "–", p != null ? "von " + Ui.Gb(p.Total) : "wird gelesen …", "#A8326F", "#1F0A19"));
        // Dienste
        if (on && state?.Services.Count > 0) tiles.Add(Tile("Dienste", "pausiert", Mint, state.Services.Count + " pausiert", Names(state.Services, 3) + " · starten beim Ausschalten wieder", "#5E4BB8", "#130B24", true));
        else tiles.Add(Tile("Dienste", p == null ? "" : "bereit", gray, p == null ? "–" : p.Services.Count + " entbehrlich", p == null ? "wird gelesen …" : p.Services.Count == 0 ? "keiner der gewählten Dienste läuft gerade" : Names(p.Services.Select(s => s.Display), 3), "#5E4BB8", "#130B24"));
        // Programme: nur die unter Einrichten gewählten werden geschlossen, die größten Verbraucher stehen zur Info da
        if (on && state?.ClosedApps.Count > 0) tiles.Add(Tile("Gewählte Programme", "geschlossen", Mint, state.ClosedApps.Count + " geschlossen", Names(state.ClosedApps, 3) + " · bitte selbst wieder starten", Beere, "#1B0916", true));
        else if (p != null && p.Apps.Count > 0) tiles.Add(Tile("Gewählte Programme", "bereit", gray, p.Apps.Count + " laufen", string.Join(" · ", p.Apps.Take(2).Select(x => x.Name + " " + Ui.Gb(x.Bytes, "N1"))) + " · werden nach Rückfrage geschlossen", Beere, "#1B0916"));
        else tiles.Add(Tile("Speicherhungrige Programme", "nur Info", gray, p == null ? "–" : p.Hungry.Count > 0 ? p.Hungry[0].Name : "keine",
            p == null ? "wird gelesen …" : string.Join(" · ", p.Hungry.Select(x => x.Name + " " + Ui.Gb(x.Bytes, "N1"))) + " · der Boost schließt nur Programme, die unter Einrichten gewählt sind", Beere, "#1B0916"));
        // Boost-Spiele
        var games = p?.Games ?? new();
        tiles.Add(Tile("Boost-Spiele", "Liste", "#F6C989", games.Count == 1 ? "1 Spiel" : games.Count + " Spiele", games.Count == 0 ? "Noch keine gewählt – der Helfer schaltet den Boost bei diesen Spielen selbst ein" : Names(games, 4), Bernstein, "#2A2112"));
        // Gaming-Check: letztes Ergebnis aus den Werkzeugen
        var check = Werkzeuglauf.Results.GetValueOrDefault("games:Gaming-Check");
        var score = check?.Summary.Split(' ').FirstOrDefault() is { } first && int.TryParse(first, out var n) ? n : (int?)null;
        var gameTile = Tile("Gaming-Check", score is { } sc ? (sc >= 85 ? "gut" : sc >= 60 ? "geht so" : "prüfen") : "", score >= 85 ? Mint : "#F6C989",
            score is { } v ? v + " / 100" : "Prüfen", check != null ? string.Join(" · ", check.Lines.Where(l => !l.Ok).Select(l => l.Label).DefaultIfEmpty("alles grün")) : "Sieben Einstellungen, die fürs Spielen zählen – Tippen prüft", Gruen, "#10291F");
        gameTile.Cursor = System.Windows.Input.Cursors.Hand;
        gameTile.MouseLeftButtonUp += (_, _) => { window.GoTop("tools"); window.Go("games"); };
        tiles.Add(gameTile);
        if (!arrived) Ui.Arrive(tiles);
        arrived = true;
        return tiles;
    }

    void Toggle()
    {
        if (Spielboost.Busy) return;
        if (Spielboost.IsOn)
        {
            var state = Spielboost.State();
            if (state?.Services.Count > 0 && !App.IsAdmin) { Bestaetigung.Ask(this, "Adminrechte nötig", "Die angehaltenen Dienste lassen sich nur mit Adminrechten wieder starten. PulsRig als Administrator starten oder den Boost im PowerShell-Programm ausschalten.", "Verstanden"); return; }
            Spielboost.Off();
            return;
        }
        var p = plan;
        if (p == null) return;
        var changes = new List<string>();
        if (p.GameModeOff) changes.Add("• Spielmodus von Windows einschalten");
        if (p.SwitchPlan) changes.Add("• Energieplan „" + p.Active?.Name + "“ → Höchstleistung");
        foreach (var s in p.Services) changes.Add("• Dienst anhalten: " + s.Display);
        foreach (var a in p.Apps) changes.Add("• Programm schließen: " + a.Name + " (vorher Ungespeichertes sichern)");
        if (changes.Count == 0) { Bestaetigung.Ask(this, "Nichts zu beschleunigen", "Energieplan, Spielmodus und Dienste sind schon so eingestellt, wie der Boost es täte.", "Verstanden"); return; }
        if (p.Services.Count > 0 && !App.IsAdmin) { Bestaetigung.Ask(this, "Adminrechte nötig", "Dienste anhalten geht nur, wenn PulsRig als Administrator läuft.", "Verstanden"); return; }
        if (Bestaetigung.Ask(this, "Boost einschalten?", string.Join("\n", changes) + "\n\nBeim Ausschalten wird alles zurückgestellt; geschlossene Programme startest du selbst wieder.", "Einschalten"))
            Spielboost.On(p, closeApps: true);
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Spielboost.Changed -= Refresh;
    }
}
