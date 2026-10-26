using System.Globalization;
using PulsRig.Core;

namespace PulsRig.App;

// Stabilitätstest, Abstürze und Bericht & Diagnose (Block 2b): Kacheln der Übersicht und Detailseiten
static partial class Hardwaremodell
{
    static Fact CpuTempFact()
    {
        if (Live.Get("CpuTemp") is { } t)
            return new("Temperatur", Math.Round(t) + " °C", t < 70 ? "kühl genug" : t < 88 ? "warm – unter Last normal" : "heiß", "#8C6BD6", "#160D29", t / 100);
        var why = Live.CpuTempStatus switch
        {
            "nodriver" => "braucht den Treiber PawnIO",
            "noadmin" => "nur mit Adminrechten",
            "none" => "dieser Prozessor meldet keine",
            "nolib" => "Ordner Sensoren fehlt",
            _ => "wird gemessen",
        };
        return new("Temperatur", "–", why, "#8C6BD6", "#160D29", 0);
    }

    // ---------- Stabilitätstest ----------

    static string StressState(StressErgebnis r) => r.Tone == "good" ? "bestanden" : r.Title.StartsWith("Gestoppt") ? "abgebrochen" : r.Tone == "bad" ? "durchgefallen" : "auffällig";

    static HwTile StressTile()
    {
        if (Belastung.Running)
            return new("stress", "Leistung", "Stabilitätstest", Belastung.Clock(Belastung.Elapsed), "läuft · " + Belastung.Minutes + " Minuten", "live", "#6D43C9", "#5EE0A0", "#10291F", Belastung.Elapsed / Math.Max(1, Belastung.Seconds));
        if (Belastung.Last is not { } r)
            return new("stress", "Leistung", "Stabilitätstest", "–", "noch nicht gelaufen", "", "#8C819F", "#5EE0A0", "#10291F", 0);
        var top = Math.Max(r.MaxCpuTemp, r.MaxGpuTemp);
        var state = StressState(r);
        return new("stress", "Leistung", "Stabilitätstest", top > 0 ? Math.Round(top) + "°" : "–", state + " · " + Day(r.Time),
            r.Tone == "good" ? "ok" : state, StateColor(r.Tone == "good" ? "good" : "warn"), "#5EE0A0", "#10291F", top / 100);
    }

    // "25.10.2026 14:02" → "heute", "gestern" oder das Datum
    static string Day(string time)
    {
        if (!DateTime.TryParseExact(time, "dd.MM.yyyy HH:mm", De, DateTimeStyles.None, out var t)) return time;
        return t.Date == DateTime.Today ? "heute" : t.Date == DateTime.Today.AddDays(-1) ? "gestern" : t.ToString("dd.MM.", De);
    }

    static Detail StressDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "LEISTUNG · STABILITÄTSTEST", Color = "#5EE0A0", Light = "#A7F3CC", Chart = ChartKind.Bars, AxisL = "Start" };
        var what = Belastung.What == "cpu" ? "Prozessor" : Belastung.What == "gpu" ? "Grafikkarte" : "Prozessor und Grafikkarte";
        List<double> temps;
        if (Belastung.Running)
        {
            SetState(d, "läuft", "live");
            d.Model = "Test läuft";
            d.Sub = Belastung.Clock(Belastung.Elapsed) + " von " + Belastung.Clock(Belastung.Seconds) + " · " + what;
            temps = Belastung.Temps;
            var now = Math.Max(Belastung.What == "cpu" ? 0 : Live.Get("GpuTemp") ?? 0, Belastung.What == "gpu" ? 0 : Live.Get("CpuTemp") ?? 0);
            d.Big = now > 0 ? Math.Round(now).ToString(De) : "–";
            d.Unit = now > 0 ? "°C gerade" : "°C nicht messbar";
            d.AxisR = Belastung.Clock(Belastung.Seconds);
            d.Tip = Belastung.State + (Belastung.State.Length > 0 ? ". " : "") + "Laut und warm ist dabei normal. Der Test endet von selbst, sobald etwas auffällt.";
            d.Actions = new() { new("Stoppen", "Test beenden", Belastung.Cancel), new("Abstürze", "Ereignisprotokoll", () => main.Go("crash")), new("Prozessor", "live ansehen", () => main.Go("cpu")) };
        }
        else
        {
            var r = Belastung.Last;
            if (r == null)
            {
                SetState(d, "offen", "");
                d.Model = "Noch kein Test";
                d.Sub = "Lastet " + what + " voll aus";
                d.Chart = ChartKind.Note;
                d.NoteText = "Der Test endet von selbst: bei Rechenfehlern, bei 90 °C an der Grafikkarte, 98 °C am Prozessor oder wenn der Prozessor seinen Takt drosselt. Vorher speichern, was offen ist: Ein instabiler PC kann beim Test abstürzen.";
            }
            else
            {
                SetState(d, StressState(r), r.Tone == "good" ? "good" : "warn");
                d.Model = "Volllast-Test " + (Day(r.Time) == "heute" ? "von heute" : Day(r.Time) == "gestern" ? "von gestern" : "vom " + Day(r.Time));
                d.Sub = r.Title;
                var top = Math.Max(r.MaxCpuTemp, r.MaxGpuTemp);
                d.Big = top > 0 ? Math.Round(top).ToString(De) : "–";
                d.Unit = top > 0 ? "°C höchste Temperatur" : "°C nicht messbar";
                if (r.Temps.Count == 0) { d.Chart = ChartKind.Note; d.NoteText = r.Text; }
            }
            temps = r?.Temps ?? new();
            d.AxisR = "Ende";
            d.Tip = r?.Text is { Length: > 0 } text && d.Chart != ChartKind.Note ? text : "Der Test lastet den PC voll aus. Bleibt er dabei stabil und unter den Grenzen, ist auch langes Spielen kein Problem.";
            var next = Belastung.What switch { "both" => "cpu", "cpu" => "gpu", _ => "both" };
            d.Actions = new()
            {
                new("Kurz testen", "5 Minuten", () => { Belastung.Minutes = 5; Belastung.Start(); }),
                new("Gründlich testen", "30 Minuten", () => { Belastung.Minutes = 30; Belastung.Start(); }),
                new("Belastet: " + (Belastung.What == "both" ? "beides" : what), "tippen zum Wechseln", () => Belastung.Choose(next)),
            };
        }
        // höchstens 30 Balken: die Messpunkte gleichmäßig zusammengefasst
        if (temps.Count > 0)
        {
            var n = Math.Min(30, temps.Count);
            for (var i = 0; i < n; i++)
            {
                var part = temps.Skip(i * temps.Count / n).Take(Math.Max(1, (i + 1) * temps.Count / n - i * temps.Count / n)).Max();
                d.Bars.Add(((part - 30) / 65, part >= 88 ? "#F08A9C" : part >= 80 ? "#F2B661" : "#5EE0A0"));
            }
        }
        else if (d.Chart == ChartKind.Bars) { d.Chart = ChartKind.Note; d.NoteText = Belastung.Running ? "Warte auf die ersten Messwerte …" : d.NoteText; }
        var last = Belastung.Last;
        double cpuMax = Belastung.Running ? Live.CpuTemp.LastOrDefault() : last?.MaxCpuTemp ?? 0, gpuMax = Belastung.Running ? Live.GpuTemp.LastOrDefault() : last?.MaxGpuTemp ?? 0;
        var errors = Belastung.Running ? PulsRigStress.Errors : last?.Title.StartsWith("Rechenfehler") == true ? 1 : 0;
        d.Facts = new()
        {
            new(Belastung.Running ? "Prozessor" : "Prozessor max.", cpuMax > 0 ? Math.Round(cpuMax) + " °C" : "–", cpuMax > 0 ? "Grenze 98 °C" : CpuTempFact().Note, "#8C6BD6", "#160D29", cpuMax / 100),
            new(Belastung.Running ? "Grafikkarte" : "Grafikkarte max.", gpuMax > 0 ? Math.Round(gpuMax) + " °C" : "–", gpuMax > 0 ? "Grenze 90 °C" : "nur bei NVIDIA messbar", "#6D43C9", "#160D29", gpuMax / 100),
            new("Fehler", errors > 0 ? (Belastung.Running ? errors + " Rechenfehler" : "Rechenfehler") : last == null && !Belastung.Running ? "–" : "keine",
                errors > 0 ? "die Hardware hat falsch gerechnet" : "kein Absturz, kein Rechenfehler", "#5EE0A0", "#10291F", errors > 0 || (last == null && !Belastung.Running) ? 0 : 1,
                errors > 0 ? "Fehler" : last != null || Belastung.Running ? "gut" : "", errors > 0 ? Warn : Good),
            new("Rechenproben", Belastung.Running ? PulsRigStress.Iterations.ToString("N0", De) : "–", Belastung.Running ? "jede wird nachgeprüft" : "zählen, während der Test läuft", "#A8326F", "#1F0A19", Belastung.Running ? Belastung.Elapsed / Math.Max(1, Belastung.Seconds) : 0),
        };
        return d;
    }

    // ---------- Abstürze ----------

    static HwTile CrashTile()
    {
        if (Hw.Crashes is not { } c) return new("crash", "Gesundheit", "Abstürze", "–", "wird gelesen …", "", "#8C819F", "#5EE0A0", "#10291F", 0);
        var card = Abstuerze.Card(c, DateTime.Today);
        if (card == null) return new("crash", "Gesundheit", "Abstürze", "–", "Protokoll nicht lesbar", "", "#8C819F", "#5EE0A0", "#10291F", 0);
        var calm = Abstuerze.CalmDays(c, DateTime.Today);
        var days = calm ?? 30;
        return new("crash", "Gesundheit", "Abstürze", days + (calm == null ? "+ T" : " T"), card.Tone == "good" ? "ohne Absturz" : card.Text,
            card.Tone == "good" ? "ruhig" : card.Text, StateColor(card.Tone), card.Tone == "bad" ? "#C0608F" : "#5EE0A0", card.Tone == "bad" ? "#1B0916" : "#10291F", days / 30.0);
    }

    internal static Act CrashAct(Befund f, MainWindow main) => f.Do switch
    {
        "scan" => new(f.Action, "Scan starten", () => main.GoTop("home")),
        "memory" => new(f.Action, "Arbeitsspeicher", () => main.Go("ram")),
        "drives" => new(f.Action, "Zustand & Störungen", () => main.Go("drives")),
        "stress" => new(f.Action, "Volllast prüfen", () => main.Go("stress")),
        // restore und rollback: "Treiber zurückholen" unter Treiber verwalten
        _ => new(f.Action, "vorige Fassung", () => main.Go("manage")),
    };

    static Detail CrashDetail(MainWindow main)
    {
        var d = new Detail { Kicker = "GESUNDHEIT · ABSTÜRZE", Color = "#5EE0A0", Light = "#A7F3CC", Chart = ChartKind.Days, AxisL = "vor 30 Tagen", AxisR = "heute" };
        var refresh = new Act("Neu einlesen", "Ereignisprotokoll", () => Hw.Load("crash", again: true));
        if (Hw.Crashes is not { } c)
        {
            SetState(d, "wird gelesen", "");
            d.Model = "Abstürze";
            d.Sub = "Bluescreens, Ausschalten und Aussetzer";
            d.Chart = ChartKind.Note;
            d.NoteText = "Lese das Ereignisprotokoll …";
            d.Actions = new() { refresh, new("Treiber prüfen", "Scan starten", () => main.GoTop("home")), new("Stabilitätstest", "Volllast prüfen", () => main.Go("stress")) };
            return d;
        }
        var card = Abstuerze.Card(c, DateTime.Today);
        var findings = Abstuerze.Findings(c, false);
        var calm = Abstuerze.CalmDays(c, DateTime.Today);
        if (card == null) SetState(d, "nicht lesbar", "");
        else SetState(d, card.Tone == "good" ? "ruhig" : card.Text, card.Tone);
        if (!c.Log && findings.Count == 0)
        {
            d.Model = "Das Ereignisprotokoll ist nicht lesbar";
            d.Sub = "PulsRig einmal als Admin starten und neu einlesen";
        }
        else if (calm == null) { d.Model = "Kein Absturz in 30 Tagen"; d.Sub = c.Tdr.Count + c.Apps.Count > 0 ? "aber Aussetzer des Grafiktreibers" : "kein Bluescreen, kein plötzliches Ausschalten"; }
        else
        {
            d.Model = calm == 0 ? "Heute abgestürzt" : calm == 1 ? "1 Tag ohne Absturz" : calm + " Tage ohne Absturz";
            var lastBlue = c.Blue.FirstOrDefault();
            d.Sub = lastBlue != null ? "Letzter Bluescreen am " + lastBlue.When.ToString("dd.MM.", De) : "Zuletzt ausgegangen am " + c.Off[0].When.ToString("dd.MM.", De);
        }
        d.Big = (calm ?? 30) + (calm == null ? "+" : "");
        d.Unit = "Tage stabil";
        d.Color = card?.Tone == "bad" ? "#C0608F" : "#5EE0A0";
        d.Light = card?.Tone == "bad" ? "#E59AC0" : "#A7F3CC";
        // 30 Kästchen, links vor 30 Tagen, rechts heute
        for (var ago = 29; ago >= 0; ago--)
        {
            var day = DateTime.Today.AddDays(-ago);
            bool blue = c.Blue.Concat(c.Off).Any(x => x.When.Date == day), graphics = c.Tdr.Concat(c.Apps).Any(x => x.When.Date == day);
            d.Days.Add((blue ? "#C0608F" : graphics ? "#88F2B661" : "#335EE0A0", blue, day.ToString("dd.MM.", De) + " · " + (blue ? c.Blue.Any(x => x.When.Date == day) ? "Bluescreen" : "ausgegangen" : graphics ? "Grafik-Aussetzer" : "ruhig")));
        }
        var cause = findings.FirstOrDefault(f => f.Title.StartsWith("Bluescreen"));
        d.Facts = new()
        {
            new("Bluescreens", c.Blue.Count.ToString(De), "in 30 Tagen", "#C0608F", "#1B0916", Math.Min(1, c.Blue.Count / 5.0), c.Blue.Count == 0 ? "gut" : "", c.Blue.Count == 0 ? Good : Warn),
            new("Ursache", cause?.State ?? "–", cause != null ? Abstuerze.Check(c.Blue[0].Code).Hex + " · " + Abstuerze.Check(c.Blue[0].Code).Name : "kein Bluescreen", "#A8326F", "#1F0A19", cause != null ? 1 : 0),
            new("Grafik-Aussetzer", (c.Tdr.Count + c.Apps.Count).ToString(De), c.Apps.Count > 0 ? string.Join(", ", c.Apps.GroupBy(x => x.App).OrderByDescending(g => g.Count()).Take(2).Select(g => g.Key + " " + g.Count() + "×")) : "Treiber setzte aus oder fing sich",
                "#F2B661", "#2A2112", Math.Min(1, (c.Tdr.Count + c.Apps.Count) / 5.0), c.Tdr.Count + c.Apps.Count == 0 ? "gut" : "", c.Tdr.Count + c.Apps.Count == 0 ? Good : Warn),
            new("Unerwartet aus", c.Off.Count.ToString(De), c.Off.Count == 0 ? "kein Stromausfall erkannt" : c.Off.Count(x => x.Button) > 0 ? "am Ausschalter ausgemacht" : "Strom, Netzteil oder Hitze",
                "#5EE0A0", "#10291F", Math.Min(1, c.Off.Count / 5.0), c.Off.Count == 0 ? "gut" : "", c.Off.Count == 0 ? Good : Warn),
        };
        var acts = findings.Where(f => f.Action.Length > 0).GroupBy(f => f.Do).Select(g => CrashAct(g.First(), main)).Take(2).ToList();
        foreach (var fallback in new[] { new Act("Treiber prüfen", "Scan starten", () => main.GoTop("home")), new Act("Stabilitätstest", "Volllast prüfen", () => main.Go("stress")) })
            if (acts.Count < 2 && acts.All(a => a.Label != fallback.Label)) acts.Add(fallback);
        d.Tip = findings.Count > 0 ? findings[0].Title + ": " + findings[0].Sub
            : "Gelegentliche Programmabstürze sind normal. Häufen sich Bluescreens, liegt es meist an einem Treiber oder am Arbeitsspeicher.";
        // Probezeit neuer Treiber (Probezeitlauf): auffällig geht vor, eine laufende steht im Tipp, wenn sonst nichts ist
        var probe = Probezeit.Entries(Probezeitlauf.Entries, DateTime.Now).OrderBy(e => e.Verdict == "auffällig" && !e.Done ? 0 : 1).FirstOrDefault();
        if (probe is { Verdict: "auffällig", Done: false })
        {
            d.Tip = Probezeit.WarnTitle(probe) + "\n" + Probezeit.Text(probe) + " Die vorige Fassung zurückholen?";
            if (acts.All(a => a.Label != "Zurückholen")) acts.Insert(0, new("Zurückholen", "vorige Fassung des Treibers", () => main.Go("manage")));
            if (acts.Count > 2) acts.RemoveAt(2);
        }
        else if (probe != null && findings.Count == 0)
            d.Tip = "Probezeit: " + probe.Name + " · " + Probezeit.Sub(probe, DateTime.Now);
        acts.Add(refresh);
        d.Actions = acts;
        return d;
    }

    // ---------- Bericht & Diagnose ----------

    static void LoadReport()
    {
        foreach (var what in new[] { "drives", "ram", "crash" }) Hw.Load(what);
    }

    static HwTile ReportTile()
    {
        LoadReport();
        var checks = Bericht.Checks();
        var v = Bericht.Verdict(checks);
        var state = v.Warn > 0 ? (v.Warn == 1 ? "1 Hinweis" : v.Warn + " Hinweise") : v.Open > 0 ? v.Open + " offen" : "ok";
        return new("report", "Gesundheit", "Bericht & Diagnose", v.Good + "/" + checks.Count, v.Title, state, StateColor(v.Warn > 0 ? "warn" : v.Open > 0 ? "" : "good"), "#A8326F", "#1B0916", checks.Count > 0 ? (double)v.Good / checks.Count : 0);
    }

    static string zipError = "", savedAt = "";

    static void SaveZip()
    {
        try { Diagnosepaket.Save(); zipError = ""; savedAt = DateTime.Now.ToString("HH:mm"); }
        catch (Exception e) { zipError = (e.InnerException ?? e).Message.Split('\n')[0]; }
        Hw.Touch();
    }

    static Detail ReportDetail(MainWindow main)
    {
        var saved = Diagnosepaket.LastFile;
        LoadReport();
        var checks = Bericht.Checks();
        var v = Bericht.Verdict(checks);
        var d = new Detail { Kicker = "GESUNDHEIT · BERICHT & DIAGNOSE", Model = v.Title, Color = "#A8326F", Light = "#E59AC0", Chart = ChartKind.List };
        SetState(d, v.Warn > 0 ? (v.Warn == 1 ? "1 Hinweis" : v.Warn + " Hinweise") : v.Open > 0 ? v.Open + " offen" : "gut", v.Warn > 0 ? "warn" : v.Open > 0 ? "" : "good");
        d.Sub = "Prüft " + checks.Count + " Bereiche" + (v.Rest.Length > 0 ? " · " + v.Rest : "");
        d.Big = v.Good + "/" + checks.Count;
        d.Unit = "Bereiche in Ordnung";
        d.Rows = checks.Select(c => new ListRow(c.Name, c.Kind switch { "good" => true, "open" => (bool?)null, _ => false })).ToList();
        var order = new Dictionary<string, int> { ["bad"] = 0, ["warn"] = 1, ["open"] = 2, ["good"] = 3 };
        d.Facts = checks.OrderBy(c => order[c.Kind]).Take(4).Select(c => new Fact(c.Name, c.Kind switch { "good" => "in Ordnung", "open" => "offen", "bad" => "Fehler", _ => "auffällig" }, c.Short,
            c.Kind is "warn" or "bad" ? "#F2B661" : c.Kind == "good" ? "#5EE0A0" : "#8C6BD6", c.Kind is "warn" or "bad" ? "#2A2112" : c.Kind == "good" ? "#10291F" : "#160D29",
            c.Kind == "good" ? 1 : c.Kind == "open" ? 0 : 0.6, c.Kind switch { "good" => "gut", "open" => "", _ => "Hinweis" }, c.Kind == "good" ? Good : c.Kind == "open" ? "#8C819F" : Warn)).ToList();
        var missing = checks.FirstOrDefault(c => c.Go.Length > 0);
        d.Actions = new()
        {
            new("ZIP speichern", saved.Length > 0 ? "gespeichert " + savedAt : "Bericht + Diagnose", SaveZip),
            missing != null ? new("Nachholen", missing.Name, () => main.Go(missing.Go)) : new Act("Nachholen", "nichts offen", null, "Alle Prüfungen sind gelaufen."),
            saved.Length > 0 ? new("Ordner zeigen", Diagnosepaket.Place(saved), () => Diagnosepaket.ShowInFolder(saved))
                : new("Neu einlesen", "alle Bereiche", () => { foreach (var what in new[] { "drives", "ram", "crash" }) Hw.Load(what, again: true); }),
        };
        var hint = checks.FirstOrDefault(c => c.Kind is "bad" or "warn");
        d.Tip = zipError.Length > 0 ? "Die ZIP-Datei ließ sich nicht erstellen: " + zipError
            : hint != null ? hint.Name + ": " + hint.Text : "Die ZIP-Datei enthält Bericht und Diagnose in einem. Du kannst sie bei Fragen einfach weitergeben – persönliche Dateien sind nicht dabei.";
        return d;
    }
}
