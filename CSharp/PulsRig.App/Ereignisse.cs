using System.Diagnostics.Eventing.Reader;
using System.Text.RegularExpressions;
using PulsRig.Core;

namespace PulsRig.App;

sealed record Speichertest(DateTime When, bool Ok, string Text);
sealed record Hardwarefehler(int Count, string Last);
sealed record Laufwerksstoerungen(Dictionary<string, (int Count, DateTime Last)> Disks, int Resets, DateTime? LastReset, bool Log);

// Das Ereignisprotokoll von Windows, gelesen wie in PulsRig-Abstuerze.ps1 und PulsRig-Hardware.ps1 (Get-WinEvent):
// Abstürze der letzten 30 Tage, Störungen der Laufwerke, letzter Speichertest und Hardwarefehler (WHEA).
// "Nichts gefunden" ist kein Fehler; lässt sich das Protokoll nicht lesen, steht Log auf false.
static class Ereignisse
{
    static string Since(int days) => "TimeCreated[timediff(@SystemTime) <= " + (long)TimeSpan.FromDays(days).TotalMilliseconds + "]";

    // pick liest aus jedem Ereignis, was gebraucht wird; danach wird das Ereignis gleich freigegeben. Jedes hält ein
    // Handle von Windows – früher blieben sie (bei den Update-Titeln bis zu 3000) liegen, bis die Speicherbereinigung kam
    static List<T> Read<T>(string log, string filter, ref bool readable, Func<EventRecord, T> pick, int max = int.MaxValue)
    {
        var list = new List<T>();
        try
        {
            // neueste zuerst wie bei Get-WinEvent
            using var reader = new EventLogReader(new EventLogQuery(log, PathType.LogName, "*[System[" + filter + "]]") { ReverseDirection = true });
            while (list.Count < max && reader.ReadEvent() is { } e)
                using (e) list.Add(pick(e));
        }
        catch (EventLogNotFoundException) { }
        catch (Exception) { readable = false; }
        return list;
    }

    static DateTime When(EventRecord e) => e.TimeCreated ?? DateTime.Now;

    static object? Prop(EventRecord e, int i) => i < e.Properties.Count ? e.Properties[i].Value : null;

    static string Message(EventRecord e)
    {
        try { return e.FormatDescription() ?? ""; } catch (Exception) { return ""; }
    }

    // für den Ruckler-Detektiv: installierte Updates (WindowsUpdateClient 19) und begonnene Defender-Scans (1000) der
    // letzten Tage. Das Defender-Protokoll lesen manche PCs nur mit Adminrechten; dann fehlen nur diese Einträge.
    public static List<RucklerEreignis> StutterEvents(int days)
    {
        var list = new List<RucklerEreignis>();
        var readable = true;
        foreach (var (time, title) in Read("System", "Provider[@Name='Microsoft-Windows-WindowsUpdateClient'] and EventID=19 and " + Since(days), ref readable, e => (e.TimeCreated, Prop(e, 0)?.ToString() ?? "Update"), 200))
            if (time is { } t) list.Add(new RucklerEreignis { When = t, Kind = "update", Text = title });
        foreach (var time in Read("Microsoft-Windows-Windows Defender/Operational", "EventID=1000 and " + Since(days), ref readable, e => e.TimeCreated, 200))
            if (time is { } t) list.Add(new RucklerEreignis { When = t, Kind = "defender", Text = "Scan" });
        return list;
    }

    // für die Herkunft-Anzeige: Titel aller über Windows Update installierten Updates (WindowsUpdateClient 19)
    public static List<string> UpdateTitles()
    {
        var readable = true;
        return Read("System", "Provider[@Name='Microsoft-Windows-WindowsUpdateClient'] and EventID=19", ref readable, e => Prop(e, 0)?.ToString() ?? "", 3000)
            .Where(t => t.Length > 0).ToList();
    }

    // für die Probezeit: wann Windows zuletzt einen Treiber je Gerät installiert hat (UserPnp 20001, 30 Tage), Ticks
    public static Dictionary<string, long> DriverInstalls()
    {
        var installs = new Dictionary<string, long>();
        var readable = true;
        foreach (var (ticks, values) in Read("System", "Provider[@Name='Microsoft-Windows-UserPnp'] and EventID=20001 and " + Since(30), ref readable,
                     e => (When(e).Ticks, e.Properties.Select(p => Convert.ToString(p.Value) ?? "").ToList())))
            foreach (var value in values)
                if (Regex.IsMatch(value, @"^(PCI|HDAUDIO|USB)\\", RegexOptions.IgnoreCase))
                    installs.TryAdd(value.ToUpperInvariant(), ticks);
        return installs;
    }

    static long Number(object? value) => long.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out var n) ? n : 0;

    // Beim Start fragen Startseite und Probezeit fast gleichzeitig: der zweite wartet auf den ersten und bekommt
    // dessen Ergebnis, statt das Protokoll noch einmal zu lesen. fresh ("Neu einlesen") liest immer neu.
    static readonly object CrashGate = new();
    static AbsturzDaten? lastCrashes;

    public static AbsturzDaten Crashes(bool fresh = false)
    {
        lock (CrashGate)
        {
            if (!fresh && lastCrashes is { } known && DateTime.Now - known.Time < TimeSpan.FromSeconds(30)) return known;
            return lastCrashes = ReadCrashes();
        }
    }

    static AbsturzDaten ReadCrashes()
    {
        var log = true;
        var d = new AbsturzDaten();
        d.Blue.AddRange(Read("System", "Provider[@Name='Microsoft-Windows-WER-SystemErrorReporting'] and EventID=1001 and " + Since(30), ref log,
            e => new Vorfall { When = When(e), Code = Abstuerze.ParseCode(Prop(e, 0)), Dump = Convert.ToString(Prop(e, 1)) ?? "" }));
        foreach (var (when, code, sleep, button) in Read("System", "Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=41 and " + Since(30), ref log,
                     e => (When(e), Abstuerze.ParseCode(Prop(e, 0)), Number(Prop(e, 5)) != 0, Number(Prop(e, 6)) != 0)))
        {
            if (code != 0)
            {
                if (!Abstuerze.HasNearBlue(d.Blue, when)) d.Blue.Add(new Vorfall { When = when, Code = code });
                continue;
            }
            d.Off.Add(new Vorfall { When = when, Sleep = sleep, Button = button });
        }
        d.Tdr.AddRange(Read("System", "Provider[@Name='Display'] and EventID=4101 and " + Since(30), ref log, e =>
        {
            var first = Convert.ToString(Prop(e, 0)) ?? "";
            return new Vorfall { When = When(e), Driver = Regex.IsMatch(first, @"^\w+$") ? first : Abstuerze.TdrDriver(first, Message(e)) };
        }));
        d.Apps.AddRange(Read("Application", "Provider[@Name='Application Error'] and EventID=1000 and " + Since(30), ref log,
            e => new Vorfall { When = When(e), App = Convert.ToString(Prop(e, 0)) ?? "", Module = Convert.ToString(Prop(e, 3)) ?? "" })
            .Where(x => Abstuerze.IsGraphicsModule(x.Module)));
        var whea = Read("System", "Provider[@Name='Microsoft-Windows-WHEA-Logger'] and (Level=1 or Level=2 or Level=3) and " + Since(30), ref log, When);
        d.Whea = whea.Count;
        d.LastWhea = whea.Count > 0 ? whea[0].ToString("dd.MM. HH:mm") : "";
        d.Blue = d.Blue.OrderByDescending(x => x.When).ToList();
        d.Off = d.Off.OrderByDescending(x => x.When).ToList();
        d.Tdr = d.Tdr.OrderByDescending(x => x.When).ToList();
        d.Apps = d.Apps.OrderByDescending(x => x.When).ToList();
        if (Abfragen.Gpu() is { } gpu) { d.GpuVersion = gpu.WindowsVersion; d.GpuDate = gpu.Date; }
        d.Log = log;
        d.Time = DateTime.Now;
        return d;
    }

    // wiederholte oder fehlgeschlagene Zugriffe je Laufwerk (Quelle "disk") und Zurücksetzungen eines Anschlusses
    // (Kennung 129 der Speichertreiber, keinem Laufwerk zuzuordnen)
    public static Laufwerksstoerungen DiskFaults()
    {
        var log = true;
        var disks = new Dictionary<string, (int Count, DateTime Last)>();
        int resets = 0;
        DateTime? lastReset = null;
        foreach (var (id, provider, when, message) in Read("System", "(EventID=7 or EventID=11 or EventID=51 or EventID=129 or EventID=153) and " + Since(30), ref log, e =>
                 {
                     var source = e.ProviderName ?? "";
                     // den Text braucht nur die Quelle "disk"; ihn zu holen kostet je Ereignis am meisten
                     return (e.Id, source, When(e), e.Id != 129 && source.Equals("disk", StringComparison.OrdinalIgnoreCase) ? Message(e) : "");
                 }))
        {
            if (id == 129)
            {
                if (Regex.IsMatch(provider, "stor|ahci|nvme|raid|scsi", RegexOptions.IgnoreCase)) { resets++; lastReset ??= when; }
                continue;
            }
            if (!provider.Equals("disk", StringComparison.OrdinalIgnoreCase)) continue;
            var m = Regex.Match(message, @"Harddisk(\d+)", RegexOptions.IgnoreCase);
            if (!m.Success) m = Regex.Match(message, "\"(\\d+)\"");
            if (!m.Success) continue;
            var number = m.Groups[1].Value;
            disks[number] = disks.TryGetValue(number, out var f) ? (f.Count + 1, f.Last) : (1, when);
        }
        return new(disks, resets, lastReset, log);
    }

    // letzter Lauf der Speicherdiagnose: Kennung 1201 = keine Fehler, 1202 = Fehler gefunden
    public static Speichertest? MemoryTest()
    {
        var log = true;
        return Read("System", "Provider[@Name='Microsoft-Windows-MemoryDiagnostics-Results']", ref log,
            e => new Speichertest(When(e), e.Id == 1201, Message(e).Split('\n')[0].Trim()), 1).FirstOrDefault();
    }

    // von der Hardware gemeldete Fehler der letzten 90 Tage (Prozessor, Speicher, Bus), nur Warnungen und Fehler
    public static Hardwarefehler Whea90()
    {
        var log = true;
        var list = Read("System", "Provider[@Name='Microsoft-Windows-WHEA-Logger'] and (Level=1 or Level=2 or Level=3) and " + Since(90), ref log, When);
        return new(list.Count, list.Count > 0 ? list[0].ToString("dd.MM.yyyy HH:mm") : "");
    }
}
