using System.Diagnostics;
using System.IO;
using System.Text.Json.Nodes;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Das Tagesbild für "Was hat sich geändert?" wie die Abfrage ProbeCheck und Add-Snapshot: Windows-Stand, Energieplan,
// Programme, Autostart und die Treiber der Probezeit, einmal am Tag in der Ergebnisdatei unter History.Snapshots –
// dieselben Felder wie im PowerShell-Programm, damit beide dieselben Bilder vergleichen.
static class Tagesbilder
{
    public static List<Tagesbild> Snaps { get; private set; } = Load();
    // die Abstürze der Prüfung beim Start, für "Abstürze seit …"
    public static AbsturzDaten? Crashes { get; private set; }
    public static event Action? Changed;

    static List<string> Strings(JsonNode? node) => node switch
    {
        JsonArray a => a.Select(n => n?.ToString() ?? "").Where(s => s.Length > 0).ToList(),
        JsonValue v => new() { v.ToString() },
        _ => new(),
    };

    static List<Tagesbild> Read(JsonObject history)
    {
        var list = new List<Tagesbild>();
        var saved = history["Snapshots"] switch { JsonArray a => a, JsonObject o => new JsonArray(o.DeepClone()), _ => new JsonArray() };
        foreach (var n in saved)
        {
            if (n is not JsonObject o || Altdaten.Text(o, "D", "").Length == 0) continue;
            list.Add(new Tagesbild
            {
                D = Altdaten.Text(o, "D", ""), Windows = Altdaten.Text(o, "Windows", ""), Plan = Altdaten.Text(o, "Plan", ""),
                Programs = Strings(o["Programs"]), Autostart = Strings(o["Autostart"]), Drivers = Strings(o["Drivers"]),
            });
        }
        return list.OrderBy(s => s.D, StringComparer.Ordinal).ToList();
    }

    static List<Tagesbild> Load()
    {
        try { return Read(Ergebnisse.History(Ergebnisse.Read())); } catch (Exception) { return new(); }
    }

    static string WindowsVersion()
    {
        try
        {
            using var nt = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            if (nt == null) return "";
            var display = nt.GetValue("DisplayVersion")?.ToString() ?? "";
            return nt.GetValue("CurrentBuild") + "." + nt.GetValue("UBR") + (display.Length > 0 ? " (" + display + ")" : "");
        }
        catch (Exception) { return ""; }
    }

    static string Plan()
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "powercfg.exe"), "/getactivescheme") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!;
            var output = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            var m = System.Text.RegularExpressions.Regex.Match(output, @"\((.+)\)");
            return m.Success ? m.Groups[1].Value.Trim() : "";
        }
        catch (Exception) { return ""; }
    }

    static IEnumerable<string> Programs()
    {
        var roots = new[]
        {
            (Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
            (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
            (Registry.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\Uninstall"),
        };
        foreach (var (hive, path) in roots)
        {
            var lines = new List<string>();
            try
            {
                using var root = hive.OpenSubKey(path);
                foreach (var sub in root?.GetSubKeyNames() ?? Array.Empty<string>())
                {
                    using var item = root!.OpenSubKey(sub);
                    var name = (item?.GetValue("DisplayName")?.ToString() ?? "").Trim();
                    if (name.Length == 0 || item!.GetValue("SystemComponent") is int and 1 || item.GetValue("ParentKeyName") != null
                        || System.Text.RegularExpressions.Regex.IsMatch(name, @"\bKB\d{6,}\b")) continue;
                    lines.Add(name + "|" + (item.GetValue("DisplayVersion")?.ToString() ?? "").Trim() + "|" + (item.GetValue("InstallDate")?.ToString() ?? "").Trim());
                }
            }
            catch (Exception) { }
            foreach (var line in lines) yield return line;
        }
    }

    // die Verknüpfungen im Autostart-Ordner liest WScript.Shell, das einen STA-Thread will
    static List<string> Autostart()
    {
        var lines = new List<string>();
        var thread = new Thread(() =>
        {
            try { lines.AddRange(Werkzeugpruefung.StartEntries().Select(e => e.Name + "|" + (e.Enabled ? "an" : "aus"))); } catch (Exception) { }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join(TimeSpan.FromSeconds(20));
        return lines;
    }

    // aus der Prüfung beim Start (Probezeitlauf), im Hintergrund
    public static void Add(IEnumerable<TreiberStand> drivers, AbsturzDaten crashes)
    {
        var now = DateTime.Now;
        var today = new Tagesbild
        {
            D = Aenderungen.DayKey(now), Windows = WindowsVersion(), Plan = Plan(),
            Programs = Aenderungen.Lines(Programs()), Autostart = Aenderungen.Lines(Autostart()),
            Drivers = Aenderungen.Lines(drivers.Select(d => d.Id + "|" + d.Name + "|" + d.Version + "|" + d.Class)),
        };
        List<Tagesbild> kept = new();
        Ergebnisse.Change(results =>
        {
            var history = Ergebnisse.History(results);
            kept = Aenderungen.Keep(Read(history), today, now);
            history["Snapshots"] = new JsonArray(kept.Select(s => (JsonNode)new JsonObject
            {
                ["D"] = s.D, ["Windows"] = s.Windows, ["Plan"] = s.Plan,
                ["Programs"] = new JsonArray(s.Programs.Select(p => (JsonNode)p).ToArray()),
                ["Autostart"] = new JsonArray(s.Autostart.Select(p => (JsonNode)p).ToArray()),
                ["Drivers"] = new JsonArray(s.Drivers.Select(p => (JsonNode)p).ToArray()),
            }).ToArray());
        });
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => { Snaps = kept; Crashes = crashes; Changed?.Invoke(); });
    }

    // Unterschiede für einen Reiter: 1, 7 oder 30 Tage
    public static (Tagesbild? Old, List<Aenderung> Changes) Compare(int days)
    {
        var old = Aenderungen.Before(Snaps, days, DateTime.Now);
        return (old, old == null ? new() : Aenderungen.Compare(old, Snaps[^1], Probezeitlauf.Entries, Crashes));
    }
}
