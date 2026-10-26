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

    static List<EventRecord> Read(string log, string filter, ref bool readable, int max = int.MaxValue)
    {
        var list = new List<EventRecord>();
        try
        {
            // neueste zuerst wie bei Get-WinEvent
            using var reader = new EventLogReader(new EventLogQuery(log, PathType.LogName, "*[System[" + filter + "]]") { ReverseDirection = true });
            for (var e = reader.ReadEvent(); e != null && list.Count < max; e = reader.ReadEvent()) list.Add(e);
        }
        catch (EventLogNotFoundException) { }
        catch (Exception) { readable = false; }
        return list;
    }

    static object? Prop(EventRecord e, int i) => i < e.Properties.Count ? e.Properties[i].Value : null;

    static string Message(EventRecord e)
    {
        try { return e.FormatDescription() ?? ""; } catch (Exception) { return ""; }
    }

    // für die Probezeit: wann Windows zuletzt einen Treiber je Gerät installiert hat (UserPnp 20001, 30 Tage), Ticks
    public static Dictionary<string, long> DriverInstalls()
    {
        var installs = new Dictionary<string, long>();
        var readable = true;
        foreach (var e in Read("System", "Provider[@Name='Microsoft-Windows-UserPnp'] and EventID=20001 and " + Since(30), ref readable))
            foreach (var p in e.Properties)
                if (Convert.ToString(p.Value) is { } value && Regex.IsMatch(value, @"^(PCI|HDAUDIO|USB)\\", RegexOptions.IgnoreCase))
                    installs.TryAdd(value.ToUpperInvariant(), (e.TimeCreated ?? DateTime.Now).Ticks);
        return installs;
    }

    static long Number(object? value) => long.TryParse(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture), out var n) ? n : 0;

    public static AbsturzDaten Crashes()
    {
        var log = true;
        var d = new AbsturzDaten();
        foreach (var e in Read("System", "Provider[@Name='Microsoft-Windows-WER-SystemErrorReporting'] and EventID=1001 and " + Since(30), ref log))
            d.Blue.Add(new Vorfall { When = e.TimeCreated ?? DateTime.Now, Code = Abstuerze.ParseCode(Prop(e, 0)), Dump = Convert.ToString(Prop(e, 1)) ?? "" });
        foreach (var e in Read("System", "Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=41 and " + Since(30), ref log))
        {
            var when = e.TimeCreated ?? DateTime.Now;
            var code = Abstuerze.ParseCode(Prop(e, 0));
            if (code != 0)
            {
                if (!Abstuerze.HasNearBlue(d.Blue, when)) d.Blue.Add(new Vorfall { When = when, Code = code });
                continue;
            }
            d.Off.Add(new Vorfall { When = when, Sleep = Number(Prop(e, 5)) != 0, Button = Number(Prop(e, 6)) != 0 });
        }
        foreach (var e in Read("System", "Provider[@Name='Display'] and EventID=4101 and " + Since(30), ref log))
        {
            var first = Convert.ToString(Prop(e, 0)) ?? "";
            d.Tdr.Add(new Vorfall { When = e.TimeCreated ?? DateTime.Now, Driver = Regex.IsMatch(first, @"^\w+$") ? first : Abstuerze.TdrDriver(first, Message(e)) });
        }
        foreach (var e in Read("Application", "Provider[@Name='Application Error'] and EventID=1000 and " + Since(30), ref log))
        {
            var module = Convert.ToString(Prop(e, 3)) ?? "";
            if (Abstuerze.IsGraphicsModule(module)) d.Apps.Add(new Vorfall { When = e.TimeCreated ?? DateTime.Now, App = Convert.ToString(Prop(e, 0)) ?? "", Module = module });
        }
        var whea = Read("System", "Provider[@Name='Microsoft-Windows-WHEA-Logger'] and (Level=1 or Level=2 or Level=3) and " + Since(30), ref log);
        d.Whea = whea.Count;
        d.LastWhea = whea.Count > 0 ? (whea[0].TimeCreated ?? DateTime.Now).ToString("dd.MM. HH:mm") : "";
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
        foreach (var e in Read("System", "(EventID=7 or EventID=11 or EventID=51 or EventID=129 or EventID=153) and " + Since(30), ref log))
        {
            var when = e.TimeCreated ?? DateTime.Now;
            if (e.Id == 129)
            {
                if (Regex.IsMatch(e.ProviderName ?? "", "stor|ahci|nvme|raid|scsi", RegexOptions.IgnoreCase)) { resets++; lastReset ??= when; }
                continue;
            }
            if (!string.Equals(e.ProviderName, "disk", StringComparison.OrdinalIgnoreCase)) continue;
            var message = Message(e);
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
        var e = Read("System", "Provider[@Name='Microsoft-Windows-MemoryDiagnostics-Results']", ref log, 1).FirstOrDefault();
        return e == null ? null : new(e.TimeCreated ?? DateTime.Now, e.Id == 1201, Message(e).Split('\n')[0].Trim());
    }

    // von der Hardware gemeldete Fehler der letzten 90 Tage (Prozessor, Speicher, Bus), nur Warnungen und Fehler
    public static Hardwarefehler Whea90()
    {
        var log = true;
        var list = Read("System", "Provider[@Name='Microsoft-Windows-WHEA-Logger'] and (Level=1 or Level=2 or Level=3) and " + Since(90), ref log);
        return new(list.Count, list.Count > 0 ? (list[0].TimeCreated ?? DateTime.Now).ToString("dd.MM.yyyy HH:mm") : "");
    }
}
