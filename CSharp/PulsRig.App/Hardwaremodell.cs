using System.Globalization;
using PulsRig.Core;

namespace PulsRig.App;

// Inhalt der Hardware-Seiten wie im Entwurf (hwTiles und detailDefs): eine Kachel je Bauteil auf der Übersicht und
// eine Detailseite nach derselben Vorlage. Echte Werte aus Hw und Live, mit -Demo die Werte des Entwurfs.

sealed record HwTile(string Id, string Group, string Name, string Value, string Note, string State, string StateColor, string Color, string Tint, double Bar);

sealed record Fact(string Title, string Value, string Note, string Color, string Tint, double Bar, string State = "", string StateColor = "#8C819F");

sealed record Act(string Label, string Sub, Action? Run, string Later = "");

enum ChartKind { None, Line, Bars, Days, Slots, List, Note }

sealed record ListRow(string Text, bool? Ok);

sealed class Detail
{
    public string Kicker = "", State = "", StateBg = "#160D29", StateColor = "#B19FE0", Model = "", Sub = "", Big = "–", Unit = "";
    public string Color = "#8C6BD6", Light = "#B19FE0", AxisL = "", AxisR = "", Tip = "", NoteText = "";
    public ChartKind Chart;
    public List<double> Values = new();
    public double Low, High = 100;
    public List<(double Height, string Color)> Bars = new();
    public List<(string Color, bool Glow, string Tip)> Days = new();
    public List<ListRow> Rows = new();
    public Arbeitsspeicher? Memory;
    public List<Fact> Facts = new();
    public List<Act> Actions = new();
}

static partial class Hardwaremodell
{
    public const string Good = "#8FF0BE", Warn = "#F6C989";
    static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

    static string StateColor(string tone) => tone switch { "good" => Good, "warn" => Warn, "bad" => "#F08A9C", _ => "#8C819F" };
    static (string Bg, string Fg) Badge(string tone) => tone switch
    {
        "good" => ("#10261C", Good), "warn" or "bad" => ("#2A2112", Warn), "live" => ("#160D29", "#B19FE0"), _ => ("#140C1D", "#8C819F"),
    };

    public static string Name(string id) => id switch
    {
        "gpu" => "Grafikkarte", "cpu" => "Prozessor", "ram" => "Arbeitsspeicher", "stress" => "Stabilitätstest", "drives" => "Laufwerke",
        "display" => "Bildschirm", "crash" => "Abstürze", "report" => "Bericht & Diagnose", _ => id,
    };

    // ---------- Übersicht ----------

    public static List<HwTile> Tiles(bool demo)
    {
        if (demo)
            return new List<HwTile>
            {
                new("gpu", "Leistung", "Grafikkarte", Math.Round(Live.GpuTemp.LastOrDefault(46)) + "°", "RTX 3080 · Lüfter 32 %", "live", "#6D43C9", "#6D43C9", "#160D29", 0.46),
                new("cpu", "Leistung", "Prozessor", "18%", "Ryzen 7 · ruhig", "live", "#6D43C9", "#5E4BB8", "#130B24", 0.18),
                new("ram", "Leistung", "Arbeitsspeicher", "32 GB", "Dual-Channel · XMP an", "ok", Good, "#A8326F", "#1F0A19", 0.41),
                new("stress", "Leistung", "Stabilitätstest", "61°", "bestanden · heute", "ok", Good, "#5EE0A0", "#10291F", 0.61),
                new("drives", "Speicher & Anzeige", "Laufwerke", "1,16 TB", "frei · E: zwei Aussetzer", "1 Hinweis", Warn, "#F2B661", "#2A2112", 0.62),
                new("display", "Speicher & Anzeige", "Bildschirm", "165 Hz", "2560 × 1440 · G-Sync", "ok", Good, "#8C6BD6", "#160D29", 1),
                new("crash", "Gesundheit", "Abstürze", "19 T", "ohne Absturz", "ruhig", Good, "#5EE0A0", "#10291F", 0.63),
                new("report", "Gesundheit", "Bericht & Diagnose", "5/7", "als ZIP speichern", "2 Hinweise", Warn, "#A8326F", "#1B0916", 0.71),
            };
        var tiles = new List<HwTile>();
        var gpuTemp = Live.Get("GpuTemp");
        var fan = Live.Get("GpuFan");
        var gpuName = Hw.Gpu?.Name ?? Live.Values["GpuName"] as string ?? "";
        tiles.Add(new("gpu", "Leistung", "Grafikkarte", gpuTemp is { } t ? Math.Round(t) + "°" : "–",
            Join(gpuName.Length > 0 ? Hw.Short(gpuName) : "", fan is { } f ? (f < 1 ? "Lüfter aus" : "Lüfter " + Math.Round(f) + " %") : ""), "live", "#6D43C9", "#6D43C9", "#160D29", (gpuTemp ?? 0) / 100));
        var load = Live.Get("CpuLoad");
        tiles.Add(new("cpu", "Leistung", "Prozessor", load is { } l ? Math.Round(l) + "%" : "–",
            Join(Hw.Cpu != null ? Hw.Short(Hw.Cpu.Name) : "", load is { } q ? (q < 25 ? "ruhig" : q < 70 ? "beschäftigt" : "unter Last") : ""), "live", "#6D43C9", "#5E4BB8", "#130B24", (load ?? 0) / 100));
        if (Hw.Memory is { } m && m.Modules.Count > 0)
        {
            var (text, tone) = Hw.MemoryState(m);
            var channels = Speicher.Channels(m.Modules, m.Layout.Count);
            var profile = Speicher.Profile(m.Modules);
            tiles.Add(new("ram", "Leistung", "Arbeitsspeicher", Ui.Gb(m.Modules.Sum(x => x.Bytes)),
                Join(channels?.Name ?? "", profile?.Tone == "Good" ? "XMP an" : profile?.Tone == "Warn" ? "Profil prüfen" : ""),
                tone == "good" ? "ok" : text, StateColor(tone), "#A8326F", "#1F0A19", m.Total > 0 ? 1 - m.Free / m.Total : 0));
        }
        else tiles.Add(new("ram", "Leistung", "Arbeitsspeicher", "–", Hw.Memory == null ? "wird gelesen …" : "Riegel unbekannt", "", "#8C819F", "#A8326F", "#1F0A19", 0));
        tiles.Add(StressTile());
        if (Hw.Drives is { } d && d.Volumes.Count > 0)
        {
            var (text, tone) = Hw.DriveState(d);
            double size = d.Volumes.Sum(v => v.Size), free = d.Volumes.Sum(v => v.Free);
            tiles.Add(new("drives", "Speicher & Anzeige", "Laufwerke", Ui.Size(free), "frei · " + (d.Disks.Count == 1 ? "1 Laufwerk" : d.Disks.Count + " Laufwerke"),
                tone == "good" ? "ok" : text, StateColor(tone), "#F2B661", "#2A2112", size > 0 ? 1 - free / size : 0));
        }
        else tiles.Add(new("drives", "Speicher & Anzeige", "Laufwerke", "–", "wird gelesen …", "", "#8C819F", "#F2B661", "#2A2112", 0));
        if (Hw.Displays is { Count: > 0 } list)
        {
            var main = list.FirstOrDefault(x => x.Primary) ?? list[0];
            var (text, tone) = Hw.DisplayState(list);
            tiles.Add(new("display", "Speicher & Anzeige", "Bildschirm", main.Hz + " Hz", main.Width + " × " + main.Height + (list.Count > 1 ? " · " + list.Count + " Bildschirme" : ""),
                tone == "good" ? "ok" : text, StateColor(tone), "#8C6BD6", "#160D29", main.Max > 0 ? (double)main.Hz / main.Max : 1));
        }
        else tiles.Add(new("display", "Speicher & Anzeige", "Bildschirm", "–", "wird gelesen …", "", "#8C819F", "#8C6BD6", "#160D29", 0));
        tiles.Add(CrashTile());
        tiles.Add(ReportTile());
        return tiles;
    }

    static string Join(params string[] parts) => string.Join(" · ", parts.Where(p => p.Length > 0));

    // ---------- Detailseiten ----------

    public static Detail Build(string id, bool demo, MainWindow main) => demo ? DemoDetail(id, main) : id switch
    {
        "gpu" => GpuDetail(main),
        "cpu" => CpuDetail(main),
        "ram" => RamDetail(main),
        "display" => DisplayDetail(main),
        "stress" => StressDetail(main),
        "crash" => CrashDetail(main),
        _ => ReportDetail(main),
    };

    static void SetState(Detail d, string text, string tone)
    {
        d.State = text;
        (d.StateBg, d.StateColor) = Badge(tone);
    }

    static Detail GpuDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "LEISTUNG · GRAFIKKARTE", Color = "#6D43C9", Light = "#B19FE0", Chart = ChartKind.Line, Low = 38, High = 58, AxisL = "vor einer Minute", AxisR = "jetzt" };
        SetState(d, "live", "live");
        var name = Hw.Gpu?.Name ?? Live.Values["GpuName"] as string ?? "Grafikkarte";
        d.Model = name;
        var total = Live.Get("GpuMemoryTotal");
        var memory = total is { } mt ? mt * 1024 * 1024 : Hw.Gpu?.MemoryBytes ?? 0;
        d.Sub = Join(memory > 0 ? Ui.Gb(memory) + " Grafikspeicher" : "", Hw.Gpu is { Driver.Length: > 0 } g ? "Treiber " + g.Driver : "");
        var temp = Live.Get("GpuTemp");
        if (temp is { } t) { d.Big = Math.Round(t).ToString(De); d.Unit = "°C · " + (t < 60 ? "ruhig" : t < 80 ? "warm" : "heiß"); }
        else d.Unit = Abfragen.NvidiaSmi().Length == 0 ? "Temperatur nur bei NVIDIA-Karten" : "°C · wird gemessen";
        d.Values = Live.GpuTemp.ToList();
        if (d.Values.Count > 0) { d.Low = Math.Min(38, d.Values.Min() - 2); d.High = Math.Max(58, d.Values.Max() + 2); }
        var load = Live.Get("GpuLoad");
        var fan = Live.Get("GpuFan");
        var used = Live.Get("GpuMemory");
        d.Facts = new()
        {
            new("Auslastung", load is { } a ? Math.Round(a) + " %" : "–", load is { } a2 ? (a2 < 20 ? "Desktop, kein Spiel offen" : "arbeitet gerade") : "wird gemessen", "#8C6BD6", "#160D29", (load ?? 0) / 100),
            new("Lüfter", fan is { } f ? Math.Round(f) + " %" : "–", fan is { } f2 ? (f2 < 1 ? "steht still – ohne Last normal" : f2 < 40 ? "leise" : f2 < 70 ? "hörbar" : "laut") : "ohne Angabe", "#5E4BB8", "#130B24", (fan ?? 0) / 100),
            new("Grafikspeicher", used is { } u ? (u / 1024).ToString("N1", De) + " GB" : "–", total is { } tt ? "von " + Math.Round(tt / 1024) + " GB belegt" : "belegt", "#A8326F", "#1F0A19", used is { } u2 && total is { } t2 && t2 > 0 ? u2 / t2 : 0),
            new("Treiber", Hw.Gpu?.Driver is { Length: > 0 } v ? v : "–", "Neuere Treiber findet der Scan", "#F2B661", "#2A2112", 0.9),
        };
        d.Actions = new()
        {
            new("Treiber prüfen", "Scan starten", () => main.GoTop("home")),
            new("Stabilitätstest", "Volllast prüfen", () => main.Go("stress")),
            new("Bild prüfen", "Auflösung & Hz", () => main.Go("display")),
        };
        d.Tip = "Bis etwa 80 °C im Spiel ist alles normal. Ohne Last sollte die Grafikkarte deutlich kühler sein.";
        return d;
    }

    static Detail CpuDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "LEISTUNG · PROZESSOR", Color = "#5E4BB8", Light = "#B19FE0", Chart = ChartKind.Line, Low = 0, High = 60, AxisL = "vor einer Minute", AxisR = "jetzt" };
        SetState(d, "live", "live");
        var cpu = Hw.Cpu;
        d.Model = cpu?.Name ?? "Prozessor";
        d.Sub = cpu != null ? cpu.Cores + " Kerne · " + cpu.Threads + " Threads" : "";
        var load = Live.Get("CpuLoad");
        if (load is { } l) { d.Big = Math.Round(l).ToString(De); d.Unit = "% Auslastung"; }
        d.Values = Live.CpuLoad.ToList();
        if (d.Values.Count > 0) d.High = Math.Max(60, d.Values.Max() + 5);
        var clock = Live.Get("CpuClock");
        var top = Live.Get("CpuCoreMax");
        d.Facts = new()
        {
            CpuTempFact(),
            new("Takt", clock is { } c ? c.ToString("N1", De) + " GHz" : "–", cpu != null ? "Grundtakt " + cpu.MaxGhz.ToString("N1", De) + " GHz" : "", "#5E4BB8", "#130B24", clock is { } c2 && cpu is { MaxGhz: > 0 } ? Math.Min(1, c2 / (cpu.MaxGhz * 1.3)) : 0),
            new("Stärkster Kern", top is { } tc ? Math.Round(tc) + " %" : "–", "zählt bei Spielen mehr als der Mittelwert", "#A8326F", "#1F0A19", (top ?? 0) / 100),
            new("Arbeitsspeicher", Live.Get("Ram") is { } r ? Math.Round(r) + " %" : "–", "belegt", "#C0608F", "#1B0916", (Live.Get("Ram") ?? 0) / 100),
        };
        d.Actions = new()
        {
            new("Stabilitätstest", "10 Minuten", () => main.Go("stress")),
            new("Boost öffnen", "mehr Leistung", () => main.GoTop("boost")),
            new("Autostart prüfen", "weniger Last", () => main.Go("clean")),
        };
        d.Tip = "Im Leerlauf sind 5–20 % normal. Bleibt die Auslastung ohne offenes Programm lange hoch, lohnt ein Blick in den Autostart.";
        return d;
    }

    static Detail RamDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "LEISTUNG · ARBEITSSPEICHER", Color = "#A8326F", Light = "#E59AC0" };
        var m = Hw.Memory;
        if (m == null || m.Modules.Count == 0)
        {
            SetState(d, m == null ? "wird gelesen" : "Riegel unbekannt", "");
            d.Model = "Arbeitsspeicher";
            d.Sub = "Riegel, Steckplätze und Takt";
            d.Chart = ChartKind.Note;
            d.NoteText = m == null ? "Lese den Arbeitsspeicher …" : "Windows nennt die eingebauten Riegel nicht.";
            d.Actions = RamActions(main);
            return d;
        }
        var (text, tone) = Hw.MemoryState(m);
        SetState(d, tone == "good" ? "gut" : text, tone);
        var placement = Speicher.Placement(m.Layout);
        var channels = Speicher.Channels(m.Modules, m.Layout.Count);
        var profile = Speicher.Profile(m.Modules);
        var size = m.Modules.Sum(x => x.Bytes);
        d.Model = Join(Ui.Gb(size), m.Modules[0].Type).Replace(" · ", " ");
        var placeText = placement.State == "good" ? "richtig gesteckt" : placement.State == "bad" ? "falsch gesteckt" : "";
        d.Sub = Join(m.Modules.Count == 1 ? "1 Riegel" : m.Modules.Count + " × " + Ui.Gb(m.Modules[0].Bytes), placeText);
        if (m.Total > 0) { d.Big = ((m.Total - m.Free) / 1073741824).ToString("N1", De); d.Unit = "GB von " + Ui.Gb(m.Total) + " belegt"; }
        d.Chart = ChartKind.Slots;
        d.Memory = m;
        d.AxisL = m.MaxBytes > 0 ? m.Layout.Count + " Steckplätze · Ausbau bis " + Ui.Gb(m.MaxBytes) : m.Layout.Count + " Steckplätze";
        d.AxisR = channels?.Name ?? "";
        var maker = (m.Modules[0].Maker + " " + m.Modules[0].Part).Trim();
        d.Facts = new()
        {
            new("Tempo", profile != null ? profile.Now.ToString("N0", De) + " MT/s" : "–",
                profile?.Tone == "Good" ? "XMP ist an – volles Tempo" : profile is { Rated: > 0 } p ? "die Riegel können " + p.Rated.ToString("N0", De) : "laut Windows",
                "#5EE0A0", "#10291F", 1, profile?.Badge ?? "", profile?.Tone == "Warn" ? Warn : Good),
            new("Kanäle", channels != null ? channels.Name.Replace("-Channel", "") : "–", channels is { Hint.Length: > 0 } ? "auf zwei Kanäle verteilen" : "Riegel arbeiten zusammen",
                "#8C6BD6", "#160D29", 1, channels is { Hint.Length: 0 } ? "gut" : "", channels is { Hint.Length: 0 } ? Good : Warn),
            new("Frei", m.Total > 0 ? (m.Free / 1073741824).ToString("N1", De) + " GB" : "–", "jetzt gerade", "#A8326F", "#1F0A19", m.Total > 0 ? m.Free / m.Total : 0),
            new("Riegel", m.Modules.Count.ToString(De), maker.Length > 0 ? maker : "Hersteller unbekannt", "#C0608F", "#1B0916", (double)m.Modules.Count / Math.Max(1, m.Layout.Count)),
        };
        d.Actions = RamActions(main);
        d.Tip = placement.State == "bad" ? placement.Hint
            : profile?.Tone == "Warn" ? profile.Text
            : channels is { Hint.Length: > 0 } ? channels.Hint
            : "Stecken die Riegel in A2 und B2, arbeiten sie zusammen im Dual-Channel. Mit eingeschaltetem XMP laufen sie so schnell, wie sie gebaut sind.";
        return d;
    }

    static List<Act> RamActions(MainWindow main) => new()
    {
        new("Speicher frei", "per Boost", () => main.GoTop("boost")),
        // die Speicherdiagnose gehört zu Windows: sie fragt selbst nach Adminrechten und danach, wann der Test laufen soll
        new("Speichertest", "von Windows", () => Start(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "MdSched.exe"))),
        new("Neu einlesen", "Riegel und Steckplätze", () => Hw.Load("ram", again: true)),
    };

    static Detail DisplayDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "SPEICHER & ANZEIGE · BILDSCHIRM", Color = "#8C6BD6", Light = "#D9CFF0", Chart = ChartKind.List };
        var list = Hw.Displays;
        if (list is not { Count: > 0 })
        {
            SetState(d, list == null ? "wird gelesen" : "keine Angaben", "");
            d.Model = "Bildschirm";
            d.Chart = ChartKind.Note;
            d.NoteText = list == null ? "Lese die Bildschirme …" : "Windows meldet keinen Bildschirm.";
        }
        else
        {
            var (text, tone) = Hw.DisplayState(list);
            SetState(d, tone == "good" ? "gut" : text, tone);
            var main1 = list.FirstOrDefault(x => x.Primary) ?? list[0];
            d.Model = main1.Name;
            d.Sub = main1.Width + " × " + main1.Height + (list.Count > 1 ? " · " + list.Count + " Bildschirme" : "");
            d.Big = main1.Hz.ToString(De);
            d.Unit = main1.Max > main1.Hz ? "Hz – er kann " + main1.Max + " Hz" : "Hz · volle Bildrate";
            foreach (var x in list)
            {
                d.Rows.Add(new(x.Name + " · " + x.Width + " × " + x.Height, true));
                d.Rows.Add(new(x.Max > x.Hz ? x.Hz + " von " + x.Max + " Hz" : x.Hz + " Hz eingestellt", x.Max <= x.Hz));
            }
            d.Facts = new()
            {
                new("Auflösung", main1.Width + " × " + main1.Height, "Hauptbildschirm", "#8C6BD6", "#160D29", 1),
                new("Bildrate", main1.Hz + " Hz", main1.Max > main1.Hz ? "möglich wären " + main1.Max + " Hz" : "das Maximum bei dieser Auflösung", "#6D43C9", "#160D29",
                    main1.Max > 0 ? (double)main1.Hz / main1.Max : 1, main1.Max > main1.Hz ? "zu langsam" : "gut", main1.Max > main1.Hz ? Warn : Good),
                new("Bildschirme", list.Count.ToString(De), list.Count > 1 ? "alle oben in der Liste" : "ein Anzeigegerät", "#A8326F", "#1F0A19", 1),
                new("Testbilder", "8", "tote Pixel, Lichthöfe, Schlieren", "#5E4BB8", "#130B24", 1),
            };
        }
        d.Actions = new()
        {
            new("Monitor-Test", "acht Testbilder", () => Monitortest.Open(main)),
            new("Anzeige", "Hz einstellen", () => Start("ms-settings:display-advanced")),
            new("Gaming-Check", "Einstellungen", () => main.Go("games")),
        };
        d.Tip = "Viele Bildschirme laufen nach dem Anschließen nur mit 60 Hz. Kann deiner mehr, wirken Bewegungen nach dem Umstellen deutlich flüssiger.";
        return d;
    }

    static void Start(string target)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    // ---------- Werte des Entwurfs (-Demo) ----------

    static Detail DemoDetail(string id, MainWindow main)
    {
        Fact F(string t, string v, string n, string c, string tint, double bar, string s = "", string sc = "#8C819F") => new(t, v, n, c, tint, bar, s, sc);
        List<Act> A(params string[] items) => items.Select(i => { var p = i.Split('|'); return new Act(p[0], p[1], () => { }); }).ToList();
        var d = new Detail();
        void Live1() => SetState(d, "live", "live");
        void Good1(string s) => SetState(d, s, "good");
        switch (id)
        {
            case "gpu":
                Live1();
                d.Kicker = "LEISTUNG · GRAFIKKARTE"; d.Model = "NVIDIA GeForce RTX 3080"; d.Sub = "10 GB GDDR6X · Treiber 566.14";
                d.Values = Live.GpuTemp.Count > 1 ? Live.GpuTemp.ToList() : Enumerable.Range(0, 40).Select(i => 46 + Math.Sin(i / 4.0) * 2).ToList();
                d.Big = Math.Round(d.Values[^1]).ToString(De); d.Unit = "°C · ruhig"; d.Color = "#6D43C9"; d.Light = "#B19FE0"; d.Chart = ChartKind.Line; d.Low = 38; d.High = 58; d.AxisL = "vor 12 s"; d.AxisR = "jetzt";
                d.Facts = new() { F("Auslastung", "18 %", "Desktop, kein Spiel offen", "#8C6BD6", "#160D29", .18), F("Lüfter", "32 %", "1 100 U/min · leise", "#5E4BB8", "#130B24", .32), F("Grafikspeicher", "2,1 GB", "von 10 GB belegt", "#A8326F", "#1F0A19", .21), F("Treiber", "566.14", "Neuer verfügbar: 566.36", "#F2B661", "#2A2112", .9, "Update", Warn) };
                d.Actions = A("Treiber-Update|auf 566.36", "Stabilitätstest|10 Minuten", "Bild prüfen|Auflösung & Hz");
                d.Tip = "Bis etwa 80 °C im Spiel ist alles normal. Der Treiber ist eine Version älter – das Update bringt Fehlerkorrekturen für neue Spiele.";
                break;
            case "cpu":
                Live1();
                d.Kicker = "LEISTUNG · PROZESSOR"; d.Model = "AMD Ryzen 7 5800X"; d.Sub = "8 Kerne · 16 Threads"; d.Big = "18"; d.Unit = "% Auslastung"; d.Color = "#5E4BB8"; d.Light = "#B19FE0";
                d.Chart = ChartKind.Line; d.Low = 0; d.High = 60; d.Values = Enumerable.Range(0, 40).Select(i => 12 + Math.Sin(i / 4.0) * 2 + i % 3).ToList(); d.AxisL = "vor 12 s"; d.AxisR = "jetzt";
                d.Facts = new() { F("Temperatur", "52 °C", "kühl genug", "#8C6BD6", "#160D29", .52), F("Takt", "4,2 GHz", "max. 4,7 GHz", "#5E4BB8", "#130B24", .89), F("Energieplan", "Ausbalanciert", "Boost stellt auf Höchstleistung", "#A8326F", "#1F0A19", .5), F("Größter Verbraucher", "Chrome", "6 % der Rechenzeit", "#C0608F", "#1B0916", .3) };
                d.Actions = A("Stabilitätstest|10 Minuten", "Boost öffnen|mehr Leistung", "Autostart prüfen|weniger Last");
                d.Tip = "Im Leerlauf sind 5–20 % normal. Bleibt die Auslastung ohne offenes Programm lange hoch, lohnt ein Blick in den Autostart.";
                break;
            case "ram":
                Good1("gut");
                d.Kicker = "LEISTUNG · ARBEITSSPEICHER"; d.Model = "32 GB DDR4"; d.Sub = "2 × 16 GB · richtig gesteckt in A2 und B2"; d.Big = "13,1"; d.Unit = "GB von 32 GB belegt"; d.Color = "#A8326F"; d.Light = "#E59AC0";
                d.Chart = ChartKind.Slots; d.AxisL = "Mainboard MSI B550 · 4 Steckplätze"; d.AxisR = "Dual-Channel";
                var stick = new SpeicherRiegel { Maker = "Corsair", Part = "Vengeance LPX", Bytes = 16 * 1073741824.0, Speed = 3600, Rated = 3600, Type = "DDR4" };
                d.Memory = new Arbeitsspeicher(new() { stick, stick }, new()
                {
                    new Steckplatz { Slot = "A1", Bank = "Kanal A", Module = -1 }, new Steckplatz { Slot = "A2", Bank = "Kanal A", Module = 0 },
                    new Steckplatz { Slot = "B1", Bank = "Kanal B", Module = -1 }, new Steckplatz { Slot = "B2", Bank = "Kanal B", Module = 1 },
                }, 4, 128 * 1073741824.0, 32 * 1073741824.0, 18.9 * 1073741824.0);
                d.Facts = new() { F("Tempo", "3 600 MT/s", "XMP ist an – volles Tempo", "#5EE0A0", "#10291F", 1, "gut", Good), F("Kanäle", "Dual", "beide Module arbeiten zusammen", "#8C6BD6", "#160D29", 1, "gut", Good), F("Frei", "18,9 GB", "reicht für jedes Spiel", "#A8326F", "#1F0A19", .59), F("Größter Verbraucher", "Chrome", "2,1 GB · 34 Tabs", "#C0608F", "#1B0916", .16) };
                d.Actions = A("Speicher frei|per Boost", "Speichertest|beim Neustart", "Verbraucher|wer belegt was");
                d.Tip = "Beide Riegel stecken richtig in A2 und B2 – so arbeiten sie zusammen im Dual-Channel. XMP ist an, der Speicher läuft so schnell, wie er gebaut ist.";
                break;
            case "stress":
                Good1("bestanden");
                d.Kicker = "LEISTUNG · STABILITÄTSTEST"; d.Model = "Volllast-Test von heute"; d.Sub = "14:02 Uhr · 10 Minuten · Prozessor und Grafikkarte"; d.Big = "61"; d.Unit = "°C höchste Temperatur"; d.Color = "#5EE0A0"; d.Light = "#A7F3CC";
                d.Chart = ChartKind.Bars; d.AxisL = "Start"; d.AxisR = "10 min";
                for (var i = 0; i < 30; i++) { var v = 38 + 23 * (1 - Math.Exp(-i / 5.0)) + Math.Sin(i * 1.7) * 1.2; d.Bars.Add(((v - 30) / 35, "#5EE0A0")); }
                d.Facts = new() { F("Prozessor max.", "78 °C", "Grenze 90 °C", "#8C6BD6", "#160D29", .78), F("Grafikkarte max.", "71 °C", "Grenze 83 °C", "#6D43C9", "#160D29", .71), F("Fehler", "keine", "kein Absturz, kein Rechenfehler", "#5EE0A0", "#10291F", 1, "gut", Good), F("Takt gehalten", "99 %", "keine Drosselung durch Hitze", "#A8326F", "#1F0A19", .99) };
                d.Actions = A("Kurz testen|5 Minuten", "Gründlich testen|30 Minuten", "Verlauf ansehen|frühere Tests");
                d.Tip = "Der Test lastet den PC voll aus. Bleibt er dabei stabil und unter den Grenzen, ist auch langes Spielen kein Problem.";
                break;
            case "display":
                Good1("gut");
                d.Kicker = "SPEICHER & ANZEIGE · BILDSCHIRM"; d.Model = "LG 27GL850"; d.Sub = "27 Zoll · über DisplayPort"; d.Big = "165"; d.Unit = "Hz · volle Bildrate"; d.Color = "#8C6BD6"; d.Light = "#D9CFF0"; d.Chart = ChartKind.List;
                d.Rows = new() { new("2560 × 1440", true), new("165 Hz eingestellt", true), new("G-Sync an", true), new("DisplayPort", true), new("10-Bit Farbe", true), new("HDR aus", false) };
                d.Facts = new() { F("Auflösung", "1440p", "empfohlen für 27 Zoll", "#8C6BD6", "#160D29", 1, "gut", Good), F("Bildrate", "165 Hz", "Maximum des Bildschirms", "#6D43C9", "#160D29", 1, "gut", Good), F("Skalierung", "100 %", "gestochen scharf", "#A8326F", "#1F0A19", 1), F("Zweiter Bildschirm", "keiner", "nur ein Anzeigegerät", "#5E4BB8", "#130B24", 0) };
                d.Actions = A("Bild reparieren|Auflösung & Hz", "Gaming-Check|alle Einstellungen", "Bildschirm-Infos|kopieren");
                d.Tip = "Viele Bildschirme laufen nach dem Kauf nur mit 60 Hz. Deiner nutzt die vollen 165 Hz – Bewegungen wirken dadurch flüssiger.";
                break;
            case "crash":
                Good1("ruhig");
                d.Kicker = "GESUNDHEIT · ABSTÜRZE"; d.Model = "19 Tage ohne Absturz"; d.Sub = "Letzter Bluescreen am 29.09."; d.Big = "19"; d.Unit = "Tage stabil"; d.Color = "#5EE0A0"; d.Light = "#A7F3CC";
                d.Chart = ChartKind.Days; d.AxisL = "vor 30 Tagen"; d.AxisR = "heute";
                for (var i = 0; i < 30; i++) { bool bad = i == 10, app = i is 4 or 16 or 22; d.Days.Add((bad ? "#C0608F" : app ? "#88F2B661" : "#335EE0A0", bad, bad ? "Bluescreen" : app ? "App-Absturz" : "ruhig")); }
                d.Facts = new() { F("Bluescreens", "1", "in 30 Tagen", "#C0608F", "#1B0916", .1), F("Ursache", "Grafiktreiber", "nvlddmkm.sys – seitdem aktualisiert", "#A8326F", "#1F0A19", 1, "behoben", Good), F("App-Abstürze", "3", "Discord 2×, Steam 1×", "#F2B661", "#2A2112", .3), F("Unerwartete Neustarts", "0", "kein Stromausfall erkannt", "#5EE0A0", "#10291F", 0, "gut", Good) };
                d.Actions = A("Absturz|vom 29.09. ansehen", "Treiber prüfen|Scan starten", "Bericht|als ZIP speichern");
                d.Tip = "Der Bluescreen kam vom Grafiktreiber. Nach dem Update ist er nicht wieder aufgetreten – das Problem gilt als gelöst.";
                break;
            default:
                SetState(d, "2 Hinweise", "warn");
                d.Kicker = "GESUNDHEIT · BERICHT & DIAGNOSE"; d.Model = "Systembericht"; d.Sub = "Prüft 7 Bereiche und packt alles in eine ZIP-Datei"; d.Big = "5/7"; d.Unit = "Bereiche in Ordnung"; d.Color = "#A8326F"; d.Light = "#E59AC0"; d.Chart = ChartKind.List;
                d.Rows = new() { new("Treiber", true), new("Temperaturen", true), new("Laufwerke", false), new("Abstürze", true), new("Windows-Update", true), new("Autostart", false), new("Netzwerk", true) };
                d.Facts = new() { F("Laufwerk E:", "2 Aussetzer", "Festplatte älter – Daten sichern", "#F2B661", "#2A2112", .81, "Hinweis", Warn), F("Autostart", "12 Programme", "Discord neu dazugekommen", "#F2B661", "#2A2112", .6, "Hinweis", Warn), F("Letzter Bericht", "12.10.", "vor 6 Tagen", "#8C6BD6", "#160D29", .4), F("Größe", "≈ 4 MB", "ohne persönliche Dateien", "#5E4BB8", "#130B24", .2) };
                d.Actions = A("ZIP speichern|Bericht + Diagnose", "Ordner öffnen|frühere Berichte", "Hinweise|2 offen");
                d.Tip = "Die ZIP-Datei enthält Bericht und Diagnose in einem. Du kannst sie bei Fragen einfach weitergeben – persönliche Dateien sind nicht dabei.";
                break;
        }
        return d;
    }
}
