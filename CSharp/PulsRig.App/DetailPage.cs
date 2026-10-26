using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using PulsRig.Core;

namespace PulsRig.App;

// Detailseite der Reihe Q, eine Vorlage für alle Bauteile: große Kachel mit Kopf, Modell, großer Zahl und Verlauf,
// vier Faktenkacheln, "Was du tun kannst" mit drei Knöpfen und "Kurz erklärt". Live-Seiten zeichnen jede Sekunde neu,
// ohne die Kacheln auszutauschen (sonst flackert das Anheben beim Überfahren).
sealed class DetailPage : UserControl, IPage
{
    readonly string id;
    readonly bool demo;
    readonly MainWindow main;
    readonly Grid grid = Ui.Mosaic(4, 3, 12);
    readonly TextBlock state = Ui.Text("", 11), model = Ui.Text("", 20, "Text", bold: true), sub = Ui.Text("", 12.5, "Leise");
    readonly TextBlock big = new() { FontSize = 54, FontWeight = FontWeights.SemiBold, LineHeight = 54 }, unit = Ui.Text("", 14, "Halbleise");
    readonly TextBlock axisL = Ui.Text("", 10.5, "#3E3150", mono: true), axisR = Ui.Text("", 10.5, "#3E3150", mono: true);
    readonly Border stateChip = new() { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4) };
    readonly Ellipse stateDot = new() { Width = 6, Height = 6, Margin = new Thickness(0, 0, 6, 0) };
    readonly ContentControl chart = new() { VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 12, 0, 0) };
    readonly List<(TextBlock Title, TextBlock State, TextBlock Value, ContentControl Bar, TextBlock Note, Border Tile)> facts = new();
    readonly UniformGrid actions = new() { Columns = 3, VerticalAlignment = VerticalAlignment.Bottom };
    string shownActions = "";
    readonly TextBlock tip = new() { FontSize = 12.5, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 19 };
    readonly bool live;
    ChartKind shownChart = (ChartKind)(-1);
    // der Live-Livelinie bleibt über alle Takte dasselbe Element und gleitet flüssig (Livelinie)
    Livelinie? liveLine;
    string liveColor = "";
    bool stopped;

    public DetailPage(string id, MainWindow main, bool demo)
    {
        this.id = id;
        this.main = main;
        this.demo = demo;
        live = id is "gpu" or "cpu";
        Content = grid;
        var d = Hardwaremodell.Build(id, demo, main);
        Build(d);
        Fill(d);
        Ui.Arrive(grid.Children.Cast<UIElement>());
        Hw.Changed += Refresh;
        Probezeitlauf.Changed += Refresh;
        if (live) { Live.Updated += Refresh; Live.Use(); }
        if (id == "stress") Belastung.Changed += Refresh;
        if (!demo) Hw.Load(id switch { "gpu" => "gpu", "cpu" => "cpu", "ram" => "ram", "display" => "display", "crash" => "crash", "stress" => "cpu", _ => "" });
    }

    void Build(Detail d)
    {
        // große Kachel: Lichtfleck oben rechts in der Farbe des Bauteils, Rand von der Farbe nach Beere
        var glow = new RadialGradientBrush { Center = new Point(0.85, 0), GradientOrigin = new Point(0.85, 0), RadiusX = 0.8, RadiusY = 0.7 };
        glow.GradientStops.Add(new GradientStop(Ui.Hex("#1F" + d.Color[1..]), 0));
        glow.GradientStops.Add(new GradientStop(Ui.Hex("#00" + d.Color[1..]), 0.7));
        var ground = new LinearGradientBrush(Ui.Hex("#0B0710"), Ui.Hex("#09060D"), 90);
        var edge = new LinearGradientBrush { StartPoint = new Point(0.25, 0), EndPoint = new Point(0.75, 1) };
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#88" + d.Color[1..]), 0));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.4));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#1A1224"), 0.7));
        edge.GradientStops.Add(new GradientStop(Ui.Hex("#55A8326F"), 1));
        var inner = new Border { Background = glow };
        var hero = new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = edge, Background = ground, ClipToBounds = true, Child = inner };

        var chip = new StackPanel { Orientation = Orientation.Horizontal };
        chip.Children.Add(stateDot);
        chip.Children.Add(state);
        stateChip.Child = chip;
        Ui.Blink(stateDot);
        var head = new DockPanel();
        DockPanel.SetDock(stateChip, Dock.Right);
        head.Children.Add(stateChip);
        var kicker = Ui.Text(d.Kicker, 10, "Leise", mono: true);
        kicker.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(kicker);
        model.Margin = new Thickness(0, 8, 0, 0);
        sub.Margin = new Thickness(0, 2, 0, 0);
        big.FontFamily = Ui.Mono;
        big.Foreground = new LinearGradientBrush(Colors.White, Ui.Hex(d.Light), 0);
        unit.VerticalAlignment = VerticalAlignment.Bottom;
        unit.Margin = new Thickness(8, 0, 0, 6);
        var number = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 0, 0) };
        number.Children.Add(big);
        number.Children.Add(unit);
        var axis = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
        DockPanel.SetDock(axisR, Dock.Right);
        axis.Children.Add(axisR);
        axis.Children.Add(axisL);
        var body = new DockPanel { Margin = new Thickness(24, 22, 24, 22) };
        foreach (var top in new FrameworkElement[] { head, model, sub, number }) { DockPanel.SetDock(top, Dock.Top); body.Children.Add(top); }
        DockPanel.SetDock(axis, Dock.Bottom);
        body.Children.Add(axis);
        body.Children.Add(chart);
        inner.Child = body;
        Ui.Place(grid, hero, 0, 0, 2, 2);

        for (var i = 0; i < 4; i++)
        {
            var f = i < d.Facts.Count ? d.Facts[i] : new Fact("", "", "", "#22172F", "#0B0710", 0);
            var fState = Ui.Text(f.State, 11, f.StateColor);
            var fHead = new DockPanel();
            DockPanel.SetDock(fState, Dock.Right);
            fHead.Children.Add(fState);
            var fTitle = Ui.Text(f.Title, 12.5, f.Color, bold: true);
            fHead.Children.Add(fTitle);
            var fValue = Ui.Text(f.Value, 24, "Text", bold: true, mono: true);
            fValue.Margin = new Thickness(0, 6, 0, 0);
            var fBar = new ContentControl { Margin = new Thickness(0, 6, 0, 0), Focusable = false };
            var fNote = new TextBlock { FontSize = 11.5, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, LineHeight = 16, VerticalAlignment = VerticalAlignment.Bottom };
            var fBody = new DockPanel();
            foreach (var top in new FrameworkElement[] { fHead, fValue, fBar }) { DockPanel.SetDock(top, Dock.Top); fBody.Children.Add(top); }
            fBody.Children.Add(fNote);
            var tile = Ui.Tile(f.Color, f.Tint);
            tile.Child = fBody;
            Ui.Place(grid, tile, 2 + i % 2, i / 2);
            facts.Add((fTitle, fState, fValue, fBar, fNote, tile));
        }

        var todo = new DockPanel();
        var todoHead = Ui.Text("Was du tun kannst", 12.5, "Halbleise", bold: true);
        DockPanel.SetDock(todoHead, Dock.Top);
        todo.Children.Add(todoHead);
        todo.Children.Add(actions);
        Ui.Place(grid, new Border { CornerRadius = new CornerRadius(22), BorderThickness = new Thickness(1), BorderBrush = Ui.Res("KarteRand"), Background = Ui.Res("Karte"), Padding = new Thickness(18, 16, 18, 16), Child = todo }, 0, 2, 2);

        var bulb = new Border { Width = 38, Height = 38, CornerRadius = new CornerRadius(12), Background = Ui.Alpha(d.Color, "1A"), BorderBrush = Ui.Alpha(d.Color, "33"), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Top,
            Child = new Path { Data = Geometry.Parse("M9 18h6 M10 21h4 M12 3a6 6 0 0 0-4 10.5c.8.8 1 1.5 1 2.5h6c0-1 .2-1.7 1-2.5A6 6 0 0 0 12 3z"), Stroke = Ui.Brush(d.Light), StrokeThickness = 2,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round, Width = 24, Height = 24, LayoutTransform = new ScaleTransform(0.75, 0.75), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
        var tipText = new StackPanel { Margin = new Thickness(14, 0, 0, 0) };
        tipText.Children.Add(Ui.Text("Kurz erklärt", 12.5, d.Light, bold: true));
        tip.Margin = new Thickness(0, 4, 0, 0);
        tipText.Children.Add(tip);
        var tipRow = new DockPanel();
        DockPanel.SetDock(bulb, Dock.Left);
        tipRow.Children.Add(bulb);
        tipRow.Children.Add(tipText);
        var tipGlow = new RadialGradientBrush { Center = new Point(0, 1), GradientOrigin = new Point(0, 1), RadiusX = 0.6, RadiusY = 1.2 };
        tipGlow.GradientStops.Add(new GradientStop(Ui.Hex("#14" + d.Color[1..]), 0));
        tipGlow.GradientStops.Add(new GradientStop(Ui.Hex("#00" + d.Color[1..]), 0.7));
        var tipBox = new Border { CornerRadius = new CornerRadius(22), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(d.Color, "22"), Background = Ui.Res("Karte"),
            Child = new Border { CornerRadius = new CornerRadius(22), Background = tipGlow, Padding = new Thickness(18, 16, 18, 16), Child = tipRow } };
        Ui.Place(grid, tipBox, 2, 2, 2);
    }

    // Knopf wie im Entwurf: der erste mit Verlauf, die anderen dunkel; ohne Aktion gedimmt mit Hinweis
    Button ActionButton(Act a, bool primary, int index)
    {
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Ui.Text(a.Label, 12.5, bold: true));
        var subText = Ui.Text(a.Sub, 11);
        subText.Opacity = 0.75;
        subText.Margin = new Thickness(0, 3, 0, 0);
        text.Children.Add(subText);
        var b = new Button
        {
            Style = (Style)Application.Current.FindResource("Flach"), Height = 62, Tag = "14", Padding = new Thickness(12, 0, 12, 0),
            Margin = new Thickness(index == 0 ? 0 : 4, 0, index == 2 ? 0 : 4, 0), HorizontalContentAlignment = HorizontalAlignment.Left,
            Background = primary && a.Run != null ? Ui.Res("Puls") : Ui.Brush("#140C1D"), BorderBrush = primary && a.Run != null ? Brushes.Transparent : Ui.Res("KarteRand"),
            BorderThickness = new Thickness(1), Foreground = Brushes.White, Content = text,
        };
        if (a.Run == null) { b.Opacity = 0.45; b.ToolTip = a.Later; b.Cursor = System.Windows.Input.Cursors.Arrow; }
        else b.Click += (_, _) => a.Run();
        return b;
    }

    void Fill(Detail d)
    {
        state.Text = d.State;
        state.Foreground = Ui.Brush(d.StateColor);
        stateDot.Fill = Ui.Brush(d.StateColor);
        stateChip.Background = Ui.Brush(d.StateBg);
        model.Text = d.Model;
        sub.Text = d.Sub;
        big.Text = d.Big;
        unit.Text = d.Unit;
        axisL.Text = d.AxisL;
        axisR.Text = d.AxisR;
        tip.Text = d.Tip;
        for (var i = 0; i < facts.Count && i < d.Facts.Count; i++)
        {
            var f = d.Facts[i];
            facts[i].State.Text = f.State;
            facts[i].State.Foreground = Ui.Brush(f.StateColor);
            facts[i].Value.Text = f.Value;
            facts[i].Bar.Content = Ui.Bar(f.Bar, f.Color, 5, reuse: facts[i].Bar.Content);
            facts[i].Note.Text = f.Note;
            facts[i].Title.Text = f.Title;
            facts[i].Title.Foreground = Ui.Brush(f.Color);
            facts[i].Tile.Background = Ui.Tint(f.Tint);
            facts[i].Tile.BorderBrush = Ui.Alpha(f.Color, "2E");
        }
        // Linien zeichnen bei jedem Takt neu; Riegel, Kalender und Listen nur, wenn sich die Art ändert oder neue Daten da sind
        // Knöpfe nur neu, wenn sich Beschriftung oder Verfügbarkeit ändert (etwa sobald die Daten da sind)
        var key = string.Join("|", d.Actions.Select(a => a.Label + a.Sub + (a.Run != null)));
        if (key != shownActions)
        {
            shownActions = key;
            actions.Children.Clear();
            for (var i = 0; i < d.Actions.Count; i++) actions.Children.Add(ActionButton(d.Actions[i], i == 0, i));
        }
        chart.VerticalAlignment = d.Chart == ChartKind.Slots ? VerticalAlignment.Stretch : VerticalAlignment.Bottom;
        if (d.Chart == ChartKind.Line && d.Values.Count >= 2)
        {
            if (liveLine == null || liveColor != d.Color + d.Light) { liveLine = new Livelinie(d.Color, d.Light) { Height = 110 }; liveColor = d.Color + d.Light; }
            liveLine.Low = d.Low;
            liveLine.High = d.High;
            liveLine.Window = Math.Max(Live.Keep, d.Values.Count);
            liveLine.Set(d.Values, live ? Live.Tick : 0);
            if (chart.Content != liveLine) chart.Content = liveLine;
        }
        else if (d.Chart == ChartKind.Line || d.Chart != shownChart || !live) chart.Content = Chart(d);
        shownChart = d.Chart;
    }

    void Refresh()
    {
        if (stopped) return;
        Fill(Hardwaremodell.Build(id, demo, main));
    }

    UIElement Chart(Detail d) => d.Chart switch
    {
        ChartKind.Line => Line(d),
        ChartKind.Bars => Bars(d),
        ChartKind.Days => Days(d),
        ChartKind.Slots => Slots(d.Memory!),
        ChartKind.List => List(d),
        ChartKind.Note => new TextBlock { Text = d.NoteText, FontSize = 13, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 30), MaxWidth = 380, HorizontalAlignment = HorizontalAlignment.Left },
        _ => new Border(),
    };

    // Livelinie wie im Entwurf: 300 × 40, Fläche mit Livelinie nach unten, Linie mit Schein
    static UIElement Line(Detail d)
    {
        var host = new Grid { Height = 110 };
        if (d.Values.Count < 2) { host.Children.Add(new TextBlock { Text = "Messung läuft …", Foreground = Ui.Res("Leise"), FontSize = 12, VerticalAlignment = VerticalAlignment.Center }); return host; }
        var n = d.Values.Count;
        var pts = d.Values.Select((v, i) => new Point(i / (double)(n - 1) * 300, 38 - (Math.Clamp(v, d.Low, d.High) - d.Low) / (d.High - d.Low) * 34)).ToList();
        PathGeometry Geo(bool area)
        {
            var frame = new PathFigure { StartPoint = new Point(0, 0) };
            frame.Segments.Add(new LineSegment(new Point(300, 40), false));
            var f = new PathFigure { StartPoint = area ? new Point(0, 40) : pts[0], IsClosed = area };
            f.Segments.Add(new PolyLineSegment(area ? pts.Append(new Point(300, 40)) : pts.Skip(1), true));
            return new PathGeometry(new[] { frame, f });
        }
        var fill = new LinearGradientBrush(Ui.Hex("#59" + d.Color[1..]), Ui.Hex("#00" + d.Color[1..]), 90);
        host.Children.Add(new Path { Data = Geo(true), Fill = fill, Stretch = Stretch.Fill });
        host.Children.Add(new Path { Data = Geo(false), Stroke = Ui.Brush(d.Light), StrokeThickness = 2, Stretch = Stretch.Fill, StrokeLineJoin = PenLineJoin.Round, Effect = Ui.Glow(d.Color, 8) });
        return host;
    }

    static UIElement Bars(Detail d)
    {
        var row = new UniformGrid { Rows = 1, Height = 110 };
        foreach (var (height, color) in d.Bars)
            row.Children.Add(new Border { Margin = new Thickness(1.5, 0, 1.5, 0), VerticalAlignment = VerticalAlignment.Bottom, Height = 110 * Math.Clamp(height, 0, 1),
                CornerRadius = new CornerRadius(3, 3, 1, 1), Background = new LinearGradientBrush(Ui.Hex(color), Ui.Hex("#22" + color[1..]), 90) });
        return row;
    }

    static UIElement Days(Detail d)
    {
        var grid = new UniformGrid { Columns = 15 };
        foreach (var (color, glow, text) in d.Days)
        {
            var cell = new Border { CornerRadius = new CornerRadius(4), Background = Ui.Brush(color), Margin = new Thickness(2.5), ToolTip = text };
            cell.SizeChanged += (_, e) => cell.Height = e.NewSize.Width;
            if (glow) cell.Effect = Ui.Glow("#A8326F", 12);
            grid.Children.Add(cell);
        }
        return grid;
    }

    static UIElement List(Detail d)
    {
        var grid = new UniformGrid { Columns = 2 };
        foreach (var r in d.Rows)
        {
            var (bg, fg, mark) = r.Ok switch { true => ("#10261C", Hardwaremodell.Good, "✓"), false => ("#2A2112", Hardwaremodell.Warn, "!"), _ => ("#140C1D", "#8C819F", "·") };
            var circle = new Border { Width = 16, Height = 16, CornerRadius = new CornerRadius(8), Background = Ui.Brush(bg), Margin = new Thickness(0, 0, 8, 0),
                Child = new TextBlock { Text = mark, FontSize = 10, FontWeight = FontWeights.Bold, Foreground = Ui.Brush(fg), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
            var line = new StackPanel { Orientation = Orientation.Horizontal };
            line.Children.Add(circle);
            line.Children.Add(Ui.Text(r.Text, 12, "Halbleise"));
            grid.Children.Add(new Border { BorderBrush = Ui.Brush("#1A1224"), BorderThickness = new Thickness(0, 0, 0, 1), Padding = new Thickness(0, 6, 0, 6), Margin = new Thickness(0, 0, 14, 6), Child = line });
        }
        return grid;
    }

    // Steckplätze als Zeilen: belegte als lila Riegel mit Bausteinen, goldener Kontaktleiste und Lichtschimmer, leere
    // gestrichelt. Falsch gesteckte Riegel und der bessere freie Platz sind gelb markiert (wie im PowerShell-Programm).
    static UIElement Slots(Arbeitsspeicher m)
    {
        var placement = Speicher.Placement(m.Layout);
        // Zeilen teilen sich die freie Höhe, höchstens 48 Punkte je Steckplatz (bei 4 Plätzen passt es so in jedes Fenster)
        var list = new Grid();
        for (var i = 0; i < m.Layout.Count; i++)
        {
            var place = m.Layout[i];
            var module = place.Module >= 0 && place.Module < m.Modules.Count ? m.Modules[place.Module] : null;
            bool wrong = placement.Wrong.Contains(i), better = placement.Better.Contains(i);
            list.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star), MaxHeight = 48 });
            var row = new Grid { Margin = new Thickness(0, 0, 0, 6) };
            Grid.SetRow(row, i);
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(62) });
            row.ColumnDefinitions.Add(new ColumnDefinition());
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
            var (slotName, bankName) = SlotNames(place);
            var name = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            name.Children.Add(Ui.Text(slotName, 13, module != null ? "Text" : "#3E3150", bold: true, mono: true));
            name.Children.Add(Ui.Text(bankName, 10.5, "Leise"));
            row.Children.Add(name);
            UIElement stick = module != null ? Stick(wrong, i) : new Border
            {
                MaxHeight = 32, CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1.2), Margin = new Thickness(14, 3, 14, 3),
                BorderBrush = better ? Ui.Brush("#F2B661") : Ui.Brush("#3E3150"),
                Child = new TextBlock { Text = better ? "hierhin umstecken" : "frei", FontSize = 11, Foreground = better ? Ui.Brush("#F6C989") : Ui.Brush("#3E3150"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
            };
            if (stick is Border { Child: TextBlock } dashed) Dash(dashed);
            Grid.SetColumn(stick, 1);
            row.Children.Add(stick);
            var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            info.Children.Add(Ui.Text(module != null ? Ui.Gb(module.Bytes) + (module.Type.Length > 0 ? " · " + module.Type : "") + (module.Speed > 0 ? "-" + module.Speed : "") : "leer", 12.5, module != null ? "Text" : "#3E3150", bold: true));
            info.Children.Add(Ui.Text(module != null ? (wrong ? "falscher Steckplatz" : (module.Maker + " " + module.Part).Trim()) : "nichts eingesteckt", 10.5, wrong ? "#F6C989" : "Leise"));
            Grid.SetColumn(info, 2);
            row.Children.Add(info);
            list.Children.Add(row);
        }
        return list;
    }

    // "P0 CHANNEL A" + "DIMM 1" → A2 / Kanal A, sonst die Namen von Windows
    static (string Slot, string Bank) SlotNames(Steckplatz p)
    {
        var channel = Speicher.ChannelKey(p.Bank + " " + p.Slot);
        var number = System.Text.RegularExpressions.Regex.Match(p.Slot, @"(\d+)\s*$");
        if (channel.Length == 1 && number.Success)
        {
            var n = int.Parse(number.Groups[1].Value);
            // DIMM 0/1 zählen ab null, DIMM_A1/A2 ab eins
            if (System.Text.RegularExpressions.Regex.IsMatch(p.Slot, @"DIMM\s*[_ ]?\d", System.Text.RegularExpressions.RegexOptions.IgnoreCase) && !p.Slot.Contains("DIMM_" + channel, StringComparison.OrdinalIgnoreCase)) n++;
            return (channel + n, "Kanal " + channel);
        }
        return (p.Slot.Length > 0 ? p.Slot : "–", p.Bank);
    }

    static void Dash(Border b)
    {
        // gestrichelter Rahmen: WPF-Rahmen kennen keine Striche, darum ein Rechteck dahinter
        var rect = new Rectangle { RadiusX = 6, RadiusY = 6, Stroke = b.BorderBrush, StrokeThickness = 1.2, StrokeDashArray = new DoubleCollection { 4, 3 } };
        var text = b.Child;
        b.Child = null;
        b.BorderThickness = new Thickness(0);
        var g = new Grid();
        g.Children.Add(rect);
        g.Children.Add(text);
        b.Child = g;
    }

    static UIElement Stick(bool wrong, int index)
    {
        var board = new Border
        {
            MaxHeight = 36, CornerRadius = new CornerRadius(6, 6, 2, 2), BorderThickness = new Thickness(1), Margin = new Thickness(14, 1, 14, 1), ClipToBounds = true,
            BorderBrush = wrong ? Ui.Brush("#F2B661") : Ui.Brush("#AA8C6BD6"), Background = new LinearGradientBrush(Ui.Hex("#666D43C9"), Ui.Hex("#55A8326F"), 0),
            Effect = Ui.Glow(wrong ? "#F2B661" : "#6D43C9", 18, 0.27),
        };
        var g = new Grid();
        var chips = new Grid { Margin = new Thickness(12, 6, 12, 11) };
        for (var c = 0; c < 9; c++)
        {
            chips.ColumnDefinitions.Add(new ColumnDefinition { Width = c == 4 ? new GridLength(8) : new GridLength(1, GridUnitType.Star) });
            if (c == 4) continue;
            var chip = new Border { CornerRadius = new CornerRadius(2), Background = Ui.Brush("#0A0610"), BorderBrush = Ui.Brush("#14FFFFFF"), BorderThickness = new Thickness(1), Margin = new Thickness(3, 0, 3, 0) };
            Grid.SetColumn(chip, c);
            chips.Children.Add(chip);
        }
        g.Children.Add(chips);
        // goldene Kontaktleiste unten
        g.Children.Add(new Rectangle { Height = 4, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(10, 0, 10, 1), Opacity = 0.85,
            Fill = new DrawingBrush(new GeometryDrawing(Ui.Brush("#E9C46A"), null, new RectangleGeometry(new Rect(0, 0, 3, 4)))) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 5, 4), ViewportUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, 5, 4), ViewboxUnits = BrushMappingMode.Absolute } });
        // Lichtschimmer, der alle 4,5 s über den Riegel zieht (.r-sheen)
        var sheen = new Rectangle { Width = 60, HorizontalAlignment = HorizontalAlignment.Left, Fill = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0), EndPoint = new Point(1, 0),
            GradientStops = { new GradientStop(Colors.Transparent, 0), new GradientStop(Ui.Hex("#22FFFFFF"), 0.5), new GradientStop(Colors.Transparent, 1) },
        } };
        var move = new TranslateTransform(-70, 0);
        sheen.RenderTransform = move;
        g.Children.Add(sheen);
        board.Child = g;
        board.SizeChanged += (_, e) =>
        {
            var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(4.5), RepeatBehavior = RepeatBehavior.Forever, BeginTime = TimeSpan.FromSeconds(index % 2 * 0.6) };
            a.KeyFrames.Add(new LinearDoubleKeyFrame(-70, KeyTime.FromPercent(0)));
            a.KeyFrames.Add(new EasingDoubleKeyFrame(e.NewSize.Width * 1.05, KeyTime.FromPercent(0.55), new SineEase { EasingMode = EasingMode.EaseInOut }));
            a.KeyFrames.Add(new LinearDoubleKeyFrame(e.NewSize.Width * 1.05, KeyTime.FromPercent(1)));
            move.BeginAnimation(TranslateTransform.XProperty, a);
        };
        return board;
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Hw.Changed -= Refresh;
        Probezeitlauf.Changed -= Refresh;
        Belastung.Changed -= Refresh;
        if (live) { Live.Updated -= Refresh; Live.Release(); }
    }
}
