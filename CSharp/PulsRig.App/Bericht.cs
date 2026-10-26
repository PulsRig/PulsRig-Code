using PulsRig.Core;

namespace PulsRig.App;

// Kind: good = in Ordnung, warn = auffällig, bad = Fehler, open = noch nicht gelaufen; Go = Seite, auf der die Prüfung nachgeholt wird
sealed record Pruefung(string Name, string Text, string Short, string Kind, string Go = "");

sealed record Urteil(string Title, string Rest, string Tone, int Good, int Warn, int Open);

// Prüfbericht wie Get-ReportChecks und Get-ReportVerdict in PulsRig-Hardware.ps1: fasst zusammen, was die anderen
// Bereiche herausgefunden haben. Tempomessung der Laufwerke und Controller kommen mit ihren Werkzeugen dazu.
static class Bericht
{
    static string N(double v) => v.ToString("N0", Ui.De);

    public static List<Pruefung> Checks()
    {
        var checks = new List<Pruefung>();

        if (Belastung.Last is not { } stress) checks.Add(new("Stabilitätstest", "Noch nicht gelaufen.", "noch nicht gelaufen", "open", "stress"));
        else
        {
            // von Hand beendet ist kein Befund, sondern eine Prüfung, die noch aussteht
            var kind = stress.Tone switch { "good" => "good", "bad" => "bad", _ => stress.Title.StartsWith("Gestoppt") ? "open" : "warn" };
            checks.Add(new("Stabilitätstest", stress.Title + ", " + stress.Time + " Uhr. " + stress.Text, stress.Title + " · " + stress.Time + " Uhr", kind, kind == "open" ? "stress" : ""));
            // Grafikkarte: ab 80 °C auffällig, ab 90 °C bricht der Test ab. Prozessor: viele takten unter Volllast
            // absichtlich bis an ihre Grenze; auffällig erst ab 95 °C, zu heiß ab 98 °C
            double gpu = stress.MaxGpuTemp, cpu = stress.MaxCpuTemp;
            if (gpu > 0 || cpu > 0)
            {
                int gpuKind = gpu >= 90 ? 2 : gpu >= 80 ? 1 : 0, cpuKind = cpu >= 98 ? 2 : cpu >= 95 ? 1 : 0, worst = Math.Max(gpuKind, cpuKind);
                var note = new[] { "Das ist unbedenklich.", "Das ist viel: Lüfter, Staub und die Luft im Gehäuse prüfen.", "Zu heiß: Kühlung, Lüfter und Staub prüfen." }[worst];
                var parts = new List<string>();
                if (cpu > 0) parts.Add("Prozessor höchstens " + N(cpu) + " °C");
                if (gpu > 0) parts.Add("Grafikkarte höchstens " + N(gpu) + " °C");
                var text = string.Join(" · ", parts) + " im Stabilitätstest. " + note;
                if (cpu <= 0) text += " Die Temperatur des Prozessors gibt Windows nicht heraus.";
                else if (cpu >= 88 && cpuKind == 0) text += "\nDer Prozessor lief an seiner Temperaturgrenze: Viele takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt.";
                parts.Add(new[] { "unbedenklich", "viel – Kühlung prüfen", "zu heiß" }[worst]);
                checks.Add(new("Höchsttemperatur unter Last", text, string.Join(" · ", parts), new[] { "good", "warn", "bad" }[worst]));
            }
        }

        if (Hw.Drives is { Disks.Count: > 0 } drives)
        {
            var disks = drives.Disks;
            var broken = disks.Where(x => x.Health != "Healthy").ToList();
            var faulty = disks.Where(x => Hw.Faults(drives, x.Number) > 0).ToList();
            var parts = new List<string> { disks.Count == 1 ? "1 Laufwerk" : disks.Count + " Laufwerke" };
            parts.Add(broken.Count == 0 ? disks.Count == 1 ? "Windows meldet es als gesund" : "Windows meldet alle als gesund" : "nicht gesund laut Windows: " + string.Join(", ", broken.Select(x => x.Name)));
            foreach (var x in faulty) parts.Add(x.Name + ": " + Hw.Faults(drives, x.Number) + " Störungen in 30 Tagen");
            var resets = drives.Faults?.Resets ?? 0;
            if (resets > 0) parts.Add(resets + "-mal Verbindung neu aufgebaut");
            if (drives.Faults is { Log: false }) parts.Add("Störungen im Ereignisprotokoll nicht lesbar");
            var kind = broken.Any(x => x.Health == "Unhealthy") ? "bad" : broken.Count + faulty.Count + resets > 0 ? "warn" : "good";
            checks.Add(new("Zustand der Laufwerke", string.Join(" · ", parts) + ".", faulty.Count > 0 ? string.Join(" · ", faulty.Select(x => x.Name + ": " + Hw.Faults(drives, x.Number) + " Störungen"))
                : resets > 0 ? resets + "-mal Verbindung neu aufgebaut" : string.Join(" · ", parts.Take(2)), kind));
        }
        else checks.Add(new("Zustand der Laufwerke", "Windows hat keine Angaben geliefert.", "keine Angaben", "open", "drives"));

        var measured = Tempotest.Results.Values.Where(x => x.Error.Length == 0).OrderBy(x => x.Letter).ToList();
        if (measured.Count == 0) checks.Add(new("Tempo der Laufwerke", "Noch kein Laufwerk gemessen.", "noch nicht gemessen", "open", "drives"));
        else
        {
            var slow = measured.Where(x => Laufwerkstempo.Slow(x.Read, x.Write)).ToList();
            var text = string.Join(" · ", measured.Select(x => x.Letter + ": Lesen " + N(x.Read) + ", Schreiben " + N(x.Write) + " MB/s")) + ".";
            if (slow.Count > 0) text += " Auffällig langsam: " + string.Join(", ", slow.Select(x => x.Letter + ":")) + ".";
            checks.Add(new("Tempo der Laufwerke", text, slow.Count > 0 ? "auffällig langsam: " + string.Join(", ", slow.Select(x => x.Letter + ":")) : measured.Count + " gemessen", slow.Count > 0 ? "warn" : "good"));
        }

        var memory = Hw.Memory;
        if (memory?.Test is { } test)
            checks.Add(new("Speichertest von Windows", "Letzter Lauf am " + test.When.ToString("dd.MM.yyyy HH:mm") + " Uhr: " + (test.Ok ? "keine Fehler gefunden" : "Windows hat Speicherfehler gefunden") + ".",
                test.Ok ? "keine Fehler · " + test.When.ToString("dd.MM.yyyy") : "Speicherfehler gefunden", test.Ok ? "good" : "bad"));
        else checks.Add(new("Speichertest von Windows", "Im Protokoll von Windows steht noch kein Speichertest.", "noch keiner gelaufen", "open", "ram"));

        // Stecken die Riegel richtig? Ohne Urteil gibt es keine Zeile.
        if (memory is { Modules.Count: > 0 } m)
        {
            var placement = Speicher.Placement(m.Layout);
            var channels = Speicher.Channels(m.Modules, m.Layout.Count);
            var where = m.Modules.Count + " von " + Math.Max(m.Layout.Count, m.Modules.Count) + " Steckplätzen belegt" + (channels != null ? " · " + channels.Name : "");
            if (placement.State == "bad")
            {
                var moves = string.Join(", ", placement.Wrong.Select((w, i) => m.Layout[w].Slot + " nach " + m.Layout[placement.Better[i]].Slot));
                checks.Add(new("Steckplätze des Arbeitsspeichers", "Falsch gesteckt (" + where + "). Umstecken: " + moves + ". So läuft der Speicher langsamer, oder das Speicherprofil (XMP) scheitert; im Zweifel gilt das Handbuch des Mainboards.",
                    "Falsch gesteckt · umstecken: " + moves, "warn", "ram"));
            }
            else if (channels is { Hint.Length: > 0 }) checks.Add(new("Steckplätze des Arbeitsspeichers", where + ". " + channels.Hint, where + " · ein zweiter Kanal wäre schneller", "warn", "ram"));
            else if (placement.State == "good") checks.Add(new("Steckplätze des Arbeitsspeichers", "Richtig gesteckt (" + where + ").", "Richtig gesteckt · " + where, "good"));
        }

        if (Hw.Crashes is { } crashes) checks.Add(CrashCheck(crashes));

        if (memory != null)
        {
            if (memory.Hardware is { Count: > 0 } h)
                checks.Add(new("Gemeldete Hardwarefehler", h.Count + " in 90 Tagen von Prozessor, Speicher oder Mainboard gemeldet, zuletzt " + h.Last + " Uhr.", h.Count + " in 90 Tagen", "warn"));
            else checks.Add(new("Gemeldete Hardwarefehler", "Prozessor, Speicher und Mainboard haben Windows in 90 Tagen nichts gemeldet.", "keine in 90 Tagen", "good"));
        }
        return checks;
    }

    // wie Get-CrashReportCheck: Hardwarefehler hat der Bericht schon als eigene Zeile, sie zählen hier nicht mit
    static Pruefung CrashCheck(AbsturzDaten d)
    {
        const string name = "Abstürze in 30 Tagen";
        var found = Abstuerze.Findings(d, false).Where(x => !x.Whea && !x.Hint).ToList();
        if (found.Count == 0)
            return d.Log ? new(name, "Kein Bluescreen, kein plötzliches Ausschalten und keine Aussetzer des Grafiktreibers.", "keine", "good")
                : new(name, "Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus.", "nicht lesbar", "open", "crash");
        var kind = found.Any(x => x.Tone == "bad") ? "bad" : "warn";
        var parts = new List<string>();
        if (d.Blue.Count > 0) parts.Add(d.Blue.Count == 1 ? "1 Bluescreen" : d.Blue.Count + " Bluescreens");
        if (d.Tdr.Count > 0) parts.Add("Grafik " + Abstuerze.Times(d.Tdr.Count) + " ausgesetzt");
        else if (d.Apps.Count > 0) parts.Add(Abstuerze.Times(d.Apps.Count) + " im Grafiktreiber abgestürzt");
        if (d.Off.Count > 0) parts.Add(Abstuerze.Times(d.Off.Count) + " ausgegangen");
        var last = d.Blue.Concat(d.Off).Concat(d.Tdr).Concat(d.Apps).OrderByDescending(x => x.When).FirstOrDefault();
        if (last != null) parts.Add("zuletzt " + last.Text + " Uhr");
        return new(name, string.Join(" · ", found.Select(x => x.Title + " · " + x.Sub)), string.Join(" · ", parts), kind, "crash");
    }

    public static Urteil Verdict(List<Pruefung> checks)
    {
        int bad = checks.Count(c => c.Kind == "bad"), warn = checks.Count(c => c.Kind == "warn"), open = checks.Count(c => c.Kind == "open");
        var rest = open == 1 ? "1 Prüfung steht noch aus" : open > 1 ? open + " Prüfungen stehen noch aus" : "";
        var title = bad > 0 ? (bad == 1 ? "1 Fehler gefunden" : bad + " Fehler gefunden")
            : warn > 0 ? (warn == 1 ? "1 Auffälligkeit" : warn + " Auffälligkeiten")
            : open > 0 ? "Bisher keine Auffälligkeiten" : "Alle Prüfungen bestanden";
        return new(title, rest, bad > 0 ? "bad" : warn > 0 ? "warn" : "good", checks.Count(c => c.Kind == "good"), warn + bad, open);
    }
}
