using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace PulsRig.App;

// Controller und Maus wie PulsRig-Eingabe.ps1; gemessen wird mit PulsRig-Eingabe.cs (XInput und Raw Input).
// Reiter Controller: Tasten leuchten beim Drücken auf und bleiben als getestet markiert, beide Sticks als Punkt im
// Kreis, die Trigger als Balken; "Drift messen" misst 3 Sekunden, wie weit die losgelassenen Sticks von der Mitte
// abweichen; "Vibrieren" lässt beide Motoren eine Sekunde laufen.
// Reiter Maus: Abfragerate beim schnellen Kreisen, Klicks je Taste und ungewollte Doppelklicks.
// Beim Verlassen kommt das Ergebnis wie im PowerShell-Programm unter Cards.Input in die Ergebnisdatei.
sealed class EingabePage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Bernstein = "#F2B661", Gruen = "#5EE0A0", Beere = "#C0608F";
    static readonly (int Bit, string Name)[] PadButtons =
    {
        (0x1000, "A"), (0x2000, "B"), (0x4000, "X"), (0x8000, "Y"), (0x0100, "LB"), (0x0200, "RB"), (0x0020, "Back"), (0x0010, "Start"),
        (0x0040, "LS"), (0x0080, "RS"), (0x0001, "↑"), (0x0002, "↓"), (0x0004, "←"), (0x0008, "→"),
    };
    static readonly string[] MouseButtons = { "Links", "Rechts", "Mitte", "Seite 1", "Seite 2" };

    readonly Grid root = new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(40) };
    int tab, pad, next;
    readonly HashSet<int> seen = new();
    (DateTime Until, double L, double R)? drift;
    (string Title, string Text, string Tone, double L, double R)? driftResult;
    int hz;
    bool hzMin, stopped;

    // Teile, die der Takt fortschreibt
    readonly Dictionary<int, Border> chips = new();
    readonly List<(Border Fill, Grid Track)> triggers = new();
    readonly List<(TranslateTransform Dot, TextBlock Text, string Label)> sticks = new();
    readonly List<Border> mouseChips = new();
    Border? wheel;
    TextBlock? rowTitle, rowText, rate, rateDetail;
    Border? rowBar;

    public EingabePage()
    {
        Content = root;
        try { PulsRigMouse.Start(); } catch (Exception) { }
        timer.Tick += (_, _) => { try { if (tab == 0) UpdatePad(); else UpdateMouse(); } catch (Exception) { } };
        timer.Start();
        Fill();
    }

    void Fill()
    {
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 12) };
        foreach (var (i, name) in new[] { (0, "Controller"), (1, "Maus") })
        {
            var b = Chip(name, tab == i);
            b.Click += (_, _) => { tab = i; Fill(); };
            tabs.Children.Add(b);
        }
        root.Children.Add(tabs);
        chips.Clear(); triggers.Clear(); sticks.Clear(); mouseChips.Clear();
        var body = new StackPanel();
        if (tab == 0) PadView(body); else MouseView(body);
        var scroll = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
    }

    static Button Chip(string label, bool on) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(14, 0, 14, 0), Margin = new Thickness(0, 0, 8, 0), Tag = "18",
        Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(on ? 0 : 1),
        VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 12.5, "Text", bold: true),
    };

    static Border Card(UIElement child) => new()
    {
        CornerRadius = new CornerRadius(18), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(1),
        Padding = new Thickness(18, 16, 18, 16), Margin = new Thickness(0, 0, 0, 10), Child = child,
    };

    static Border Key(string text, double width = 44) => new()
    {
        CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 5, 10, 5), Margin = new Thickness(3), MinWidth = width, BorderThickness = new Thickness(1),
        BorderBrush = Ui.Res("KarteRand"), Child = new TextBlock { Text = Texte.T(text), FontSize = 12.5, Foreground = Ui.Res("Text"), HorizontalAlignment = HorizontalAlignment.Center },
    };

    // gedrückt hell, schon einmal gedrückt grün umrandet
    static void SetKey(Border key, bool pressed, bool done)
    {
        key.Background = pressed ? Ui.Brush(Lila) : null;
        ((TextBlock)key.Child).Foreground = pressed ? Brushes.Black : Ui.Res("Text");
        key.BorderBrush = done ? Ui.Brush(Gruen) : Ui.Res("KarteRand");
    }

    // Zeile mit Zustand, Text und Knöpfen unter der Karte
    Border StateRow(string title, string text, params (string Label, Action Run)[] actions)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        rowBar = new Border { Width = 4, CornerRadius = new CornerRadius(2), Background = Ui.Brush(Lila), Margin = new Thickness(0, 2, 16, 2) };
        grid.Children.Add(rowBar);
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        rowTitle = Ui.Text(title, 14.5, "Text", bold: true);
        rowText = Ui.Text(text, 12.5, "Leise");
        rowText.TextWrapping = TextWrapping.Wrap;
        rowText.Margin = new Thickness(0, 3, 0, 0);
        stack.Children.Add(rowTitle);
        stack.Children.Add(rowText);
        Grid.SetColumn(stack, 1);
        grid.Children.Add(stack);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
        foreach (var (label, run) in actions)
        {
            var b = Chip(label, false);
            b.Click += (_, _) => run();
            buttons.Children.Add(b);
        }
        Grid.SetColumn(buttons, 2);
        grid.Children.Add(buttons);
        return Card(grid);
    }

    void SetRow(string title, string text, string tone)
    {
        if (rowTitle == null || rowText == null || rowBar == null) return;
        rowTitle.Text = Texte.T(title);
        rowText.Text = Texte.T(text);
        rowText.Visibility = text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        rowBar.Background = Ui.Brush(tone switch { "good" => Gruen, "warn" => Bernstein, "bad" => Beere, _ => Lila });
    }

    (FrameworkElement Panel, TranslateTransform Dot, TextBlock Text) Stick(string label)
    {
        var panel = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        var area = new Grid { Width = 116, Height = 116 };
        area.Children.Add(new Ellipse { StrokeThickness = 2, Stroke = Ui.Res("Leise"), Opacity = 0.5 });
        area.Children.Add(new Ellipse { Width = 28, Height = 28, StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 2, 3 }, Stroke = Ui.Res("Leise"), Opacity = 0.6 });
        var move = new TranslateTransform();
        area.Children.Add(new Ellipse { Width = 16, Height = 16, Fill = Ui.Brush(Lila), RenderTransform = move });
        panel.Children.Add(area);
        var text = Ui.Text(label, 12, "Text");
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.Margin = new Thickness(0, 8, 0, 0);
        panel.Children.Add(text);
        return (panel, move, text);
    }

    void PadView(StackPanel body)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        var left = Stick("Linker Stick");
        var right = Stick("Rechter Stick");
        Grid.SetColumn(right.Panel, 2);
        grid.Children.Add(left.Panel);
        grid.Children.Add(right.Panel);
        sticks.Add((left.Dot, left.Text, "Linker Stick"));
        sticks.Add((right.Dot, right.Text, "Rechter Stick"));
        var middle = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(middle, 1);
        var keys = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var (bit, name) in PadButtons) { var k = Key(name); keys.Children.Add(k); chips[bit] = k; }
        middle.Children.Add(keys);
        foreach (var name in new[] { "LT", "RT" })
        {
            var row = new DockPanel { Margin = new Thickness(20, 8, 20, 0) };
            var label = Ui.Text(name, 12, "Text");
            label.Width = 28;
            row.Children.Add(label);
            var track = new Grid { Height = 8, VerticalAlignment = VerticalAlignment.Center };
            track.Children.Add(new Border { CornerRadius = new CornerRadius(4), Background = Ui.Res("KarteRand") });
            var fill = new Border { CornerRadius = new CornerRadius(4), HorizontalAlignment = HorizontalAlignment.Left, Width = 0, Background = Ui.Brush(Lila) };
            track.Children.Add(fill);
            row.Children.Add(track);
            middle.Children.Add(row);
            triggers.Add((fill, track));
        }
        grid.Children.Add(middle);
        body.Children.Add(Card(grid));
        body.Children.Add(StateRow("Suche einen Controller …", "", ("Drift messen", StartDrift), ("Vibrieren", Rumble)));
        body.Children.Add(Ui.Text("Xbox-kompatible Controller (XInput). PlayStation-Controller nur über Steam oder DS4Windows.", 11.5, "Leise"));
    }

    void MouseView(StackPanel body)
    {
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        var hint = Ui.Text("Maus jetzt ein paar Sekunden schnell und ohne Pause im Kreis bewegen", 13, "Leise");
        hint.HorizontalAlignment = HorizontalAlignment.Center;
        rate = Ui.Text("–", 40, "Text", bold: true, mono: true);
        rate.HorizontalAlignment = HorizontalAlignment.Center;
        rate.Margin = new Thickness(0, 6, 0, 0);
        rateDetail = Ui.Text("Abfragerate", 12, "Leise");
        rateDetail.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(hint);
        stack.Children.Add(rate);
        stack.Children.Add(rateDetail);
        var card = Card(stack);
        card.Height = 190;
        body.Children.Add(card);
        var keys = new WrapPanel { Margin = new Thickness(0, 0, 0, 8), HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var name in MouseButtons) { var k = Key(name, 96); keys.Children.Add(k); mouseChips.Add(k); }
        wheel = Key("Rad · 0", 96);
        keys.Children.Add(wheel);
        body.Children.Add(keys);
        body.Children.Add(StateRow("Doppelklick-Fehler", "Jede Taste 20- bis 30-mal schnell hintereinander klicken. Löst eine kurz nach dem Loslassen von selbst wieder aus, steht es hier.",
            ("Zurücksetzen", () => { try { PulsRigMouse.Reset(); } catch (Exception) { } })));
        body.Children.Add(Ui.Text("Gemessen wird jede einzelne Meldung der Maus, auch außerhalb von PulsRig", 11.5, "Leise"));
    }

    void StartDrift()
    {
        drift = (DateTime.Now.AddSeconds(3), 0, 0);
        SetRow("Sticks nicht berühren …", "Gemessen wird 3 Sekunden lang, wie weit sie in Ruhe von der Mitte abweichen.", "");
    }

    void Rumble()
    {
        PulsRigPad.Vibrate(pad, true);
        var off = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        off.Tick += (_, _) => { off.Stop(); PulsRigPad.Vibrate(pad, false); };
        off.Start();
    }

    // Auslenkung eines Sticks in Prozent (0 = Mitte, 100 = Rand)
    static double Share(double x, double y) => Math.Min(100, 100 * Math.Sqrt(x * x + y * y) / 32767.0);

    // Urteil zur Ruhelage: die üblichen Totzonen der Spiele liegen um 20 bis 25 %
    static (string Text, string Tone) Verdict(double share) => share < 8 ? ("in Ordnung", "good") : share < 20 ? ("leichter Drift", "warn") : ("Drift", "bad");

    void UpdatePad()
    {
        var state = PulsRigPad.Read(pad);
        if (state[0] == 0)
        {
            // nicht verbunden: einmal pro Sekunde die vier Plätze absuchen
            if (Environment.TickCount >= next)
            {
                next = Environment.TickCount + 1000;
                for (var i = 0; i < 4; i++) if (PulsRigPad.Read(i)[0] != 0) { pad = i; break; }
            }
            SetRow("Kein Controller gefunden", "Controller per Kabel, Funk oder Bluetooth verbinden. Erkannt werden Xbox-kompatible Controller (XInput).", "");
            return;
        }
        foreach (var (bit, key) in chips)
        {
            var pressed = (state[1] & bit) != 0;
            if (pressed) seen.Add(bit);
            SetKey(key, pressed, seen.Contains(bit));
        }
        for (var t = 0; t < triggers.Count; t++)
            if (triggers[t].Track.ActualWidth > 0) triggers[t].Fill.Width = triggers[t].Track.ActualWidth * state[2 + t] / 255.0;
        for (var s = 0; s < sticks.Count; s++)
        {
            double x = state[4 + 2 * s], y = state[5 + 2 * s];
            sticks[s].Dot.X = 50 * x / 32767.0;
            sticks[s].Dot.Y = -50 * y / 32767.0;
            sticks[s].Text.Text = Texte.T(sticks[s].Label) + " · " + Share(x, y).ToString("N0", Ui.De) + " %";
        }
        if (drift is { } d)
        {
            d = (d.Until, Math.Max(d.L, Share(state[4], state[5])), Math.Max(d.R, Share(state[6], state[7])));
            drift = d;
            if (DateTime.Now < d.Until) return;
            drift = null;
            var left = Verdict(d.L);
            var right = Verdict(d.R);
            int Rank(string tone) => tone == "good" ? 0 : tone == "warn" ? 1 : 2;
            var worst = Rank(left.Tone) >= Rank(right.Tone) ? left : right;
            var text = string.Format(Ui.De, "Linker Stick in Ruhe {0:N0} % aus der Mitte ({1}), rechter {2:N0} % ({3}).", d.L, Texte.T(left.Text), d.R, Texte.T(right.Text)) + "\n" + worst.Tone switch
            {
                "good" => "Beide kehren sauber in die Mitte zurück.",
                "warn" => "Die meisten Spiele gleichen das mit ihrer Totzone aus. Wird es schlimmer: Stick mit Druckluft reinigen.",
                _ => "Der Stick bewegt die Figur von selbst. Reinigen hilft manchmal; sonst muss das Stick-Modul getauscht werden.",
            };
            driftResult = (worst.Tone == "good" ? "Kein Stick-Drift" : "Stick-Drift gemessen", text, worst.Tone, Math.Round(d.L), Math.Round(d.R));
        }
        if (driftResult is { } r) SetRow(r.Title, r.Text + "\n" + seen.Count + " von " + PadButtons.Length + " Tasten getestet.", r.Tone);
        else SetRow("Controller " + (pad + 1) + " verbunden", "Jede Taste einmal drücken: getestete werden grün umrandet (" + seen.Count + " von " + PadButtons.Length + "). Für den Drift die Sticks loslassen und „Drift messen“ wählen.", "good");
    }

    void UpdateMouse()
    {
        if (rate == null || rateDetail == null) return;
        var measured = PulsRigMouse.Rate();
        if (measured > 0)
        {
            int value;
            if (PulsRigMouse.SpeedLimited)
            {
                // die Bewegung war zu langsam für die Rate der Maus: Mindestwert, auf 100 abgerundet
                value = (int)Math.Max(100, Math.Floor(measured / 100) * 100);
                rate.Text = Texte.T("mindestens " + value.ToString("N0", Ui.De) + " Hz");
                rateDetail.Text = Texte.T("Die Maus meldet nur, wenn sie sich bewegt: Für eine höhere Rate schneller kreisen oder die DPI erhöhen.");
            }
            else
            {
                // auf die übliche Stufe runden, wenn sie nah genug liegt
                var standard = new[] { 125, 250, 500, 1000, 2000, 4000, 8000 }.OrderBy(s => Math.Abs(s - measured)).First();
                value = Math.Abs(standard - measured) / standard < 0.15 ? standard : (int)Math.Round(measured);
                rate.Text = value.ToString("N0", Ui.De) + " Hz";
                rateDetail.Text = Texte.T("Abfragerate · aus " + PulsRigMouse.Samples + " Meldungen" + (PulsRigMouse.Devices > 1 ? " · " + PulsRigMouse.Devices + " Mäuse gefunden" : ""));
            }
            hz = value;
            hzMin = PulsRigMouse.SpeedLimited;
        }
        for (var b = 0; b < mouseChips.Count; b++)
        {
            ((TextBlock)mouseChips[b].Child).Text = Texte.T(MouseButtons[b]) + " · " + PulsRigMouse.Clicks[b];
            SetKey(mouseChips[b], PulsRigMouse.Down[b], PulsRigMouse.Clicks[b] > 0);
        }
        if (wheel != null) ((TextBlock)wheel.Child).Text = Texte.T("Rad") + " · " + PulsRigMouse.Wheel;
        // ab zwei Fällen bei derselben Taste ist es ein verschlissener Schalter; ein einzelner kann vorkommen (etwa beim Mausrad)
        var bad = Enumerable.Range(0, 5).Where(b => PulsRigMouse.Bounces[b] >= 2).Select(b => Texte.T(MouseButtons[b]) + " " + PulsRigMouse.Bounces[b] + "×").ToList();
        var once = Enumerable.Range(0, 5).Where(b => PulsRigMouse.Bounces[b] == 1).Select(b => Texte.T(MouseButtons[b])).ToList();
        var total = PulsRigMouse.Clicks.Sum();
        if (bad.Count == 0 && once.Count > 0)
            SetRow("Einmal nachgeprellt", "Bei " + total + " Klicks hat diese Taste einmal kurz nach dem Loslassen nachgeprellt: " + string.Join(", ", once) + ". Das kann einmal vorkommen, etwa beim Mausrad; passiert es öfter, ist der Schalter verschlissen.", "");
        else if (bad.Count > 0)
            SetRow("Ungewollte Doppelklicks", "Kurz nach dem Loslassen wieder ausgelöst: " + string.Join(", ", bad) + ". Das ist meist ein verschlissener Schalter; tritt es öfter auf, hilft nur ein neuer Schalter oder eine neue Maus.", "warn");
        else if (total >= 20)
            SetRow("Kein Doppelklick-Fehler", total + " Klicks, keiner hat von selbst doppelt ausgelöst.", "good");
    }

    // wie Save-InputResult: Abfragerate, Klicks und Doppelklicks der Maus, Drift je Stick und getestete Tasten
    void Save()
    {
        var clicks = PulsRigMouse.Clicks.Sum();
        var bounces = Enumerable.Range(0, 5).Where(b => PulsRigMouse.Bounces[b] > 0).Select(b => MouseButtons[b] + " " + PulsRigMouse.Bounces[b] + "×").ToList();
        var bounceMax = PulsRigMouse.Bounces.Max();
        if (hz == 0 && clicks < 20 && driftResult == null && seen.Count == 0) return;
        Ergebnisse.Change(results =>
        {
            var cards = results["Cards"] as JsonObject ?? (JsonObject)(results["Cards"] = new JsonObject());
            var state = cards["Input"] as JsonObject ?? new JsonObject();
            if (hz > 0) { state["Hz"] = hz; state["HzMin"] = hzMin; }
            if (clicks >= 20) { state["Clicks"] = clicks; state["Bounces"] = string.Join(", ", bounces); state["BounceMax"] = bounceMax; }
            if (driftResult is { } r) { state["DriftL"] = (int)r.L; state["DriftR"] = (int)r.R; state["DriftTone"] = r.Tone; }
            if (seen.Count > 0) state["Buttons"] = seen.Count + " von " + PadButtons.Length;
            var tone = "good";
            if (Altdaten.Text(state, "Bounces", "").Length > 0 && (state["BounceMax"] is not JsonValue bm || bm.GetValue<int>() >= 2)) tone = "warn";
            var driftTone = Altdaten.Text(state, "DriftTone", "");
            if (driftTone is "warn" or "bad") tone = driftTone;
            var parts = new List<string>();
            if (state["Hz"] is JsonValue h) parts.Add("Maus " + (Altdaten.Flag(state, "HzMin", false) ? "≥ " : "") + h.GetValue<int>().ToString("N0", Ui.De) + " Hz");
            if (state["DriftL"] is JsonValue dl) parts.Add("Drift " + dl.GetValue<int>() + " / " + state["DriftR"]?.GetValue<int>() + " %");
            state["Text"] = tone == "good" ? "in Ordnung" : "auffällig";
            state["Tone"] = tone;
            state["Detail"] = string.Join(" · ", parts);
            state["Date"] = DateTime.Now.ToString("dd.MM.yyyy");
            cards["Input"] = state.DeepClone();
        });
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        timer.Stop();
        try { Save(); } catch (Exception) { }
        try { PulsRigPad.Vibrate(pad, false); } catch (Exception) { }
        try { PulsRigMouse.Stop(); } catch (Exception) { }
    }
}
