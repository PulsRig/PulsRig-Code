using System.Management;
using System.Text.Json.Nodes;
using PulsRig.Core;

namespace PulsRig.App;

// Die Prüfung beim Start wie Start-ProbeCheck: Treiberstände von Grafik, Netzwerk, Ton und Speicher-Controllern und das
// Ereignisprotokoll lesen, Probezeiten fortschreiben (Core.Probezeit) und in der Ergebnisdatei unter History.Drivers und
// History.Probation speichern – dieselben Felder wie im PowerShell-Programm, damit beide denselben Stand haben.
static class Probezeitlauf
{
    public static List<ProbeEintrag> Entries { get; private set; } = Load();
    public static event Action? Changed;
    static bool started;

    static List<ProbeEintrag> Load()
    {
        try { return Read(Ergebnisse.History(Ergebnisse.Read())); } catch (Exception) { return new(); }
    }

    static List<ProbeEintrag> Read(JsonObject history)
    {
        var list = new List<ProbeEintrag>();
        foreach (var n in history["Probation"] as JsonArray ?? new())
        {
            if (n is not JsonObject o) continue;
            long Long(string k) => o[k] is JsonValue v && v.TryGetValue<long>(out var l) ? l : 0;
            int Int(string k) => (int)Long(k);
            list.Add(new ProbeEintrag
            {
                Id = Altdaten.Text(o, "Id", ""), Name = Altdaten.Text(o, "Name", ""), Class = Altdaten.Text(o, "Class", ""), Old = Altdaten.Text(o, "Old", ""), New = Altdaten.Text(o, "New", ""),
                Since = Long("Since"), Source = Altdaten.Text(o, "Source", "Windows"), Done = Altdaten.Flag(o, "Done", false), Verdict = Altdaten.Text(o, "Verdict", "läuft"),
                After = Int("After"), Before = Int("Before"), BeforeDays = Int("BeforeDays"),
            });
        }
        return list;
    }

    static List<TreiberStand> Drivers()
    {
        var list = new List<TreiberStand>();
        using var searcher = new ManagementObjectSearcher("SELECT DeviceID, DeviceName, DriverVersion, DeviceClass FROM Win32_PnPSignedDriver WHERE DeviceClass='DISPLAY' OR DeviceClass='NET' OR DeviceClass='MEDIA' OR DeviceClass='SCSIADAPTER' OR DeviceClass='HDC'");
        foreach (ManagementObject o in searcher.Get())
        {
            var id = o["DeviceID"]?.ToString() ?? "";
            var version = o["DriverVersion"]?.ToString() ?? "";
            if (version.Length == 0 || !System.Text.RegularExpressions.Regex.IsMatch(id, @"^(PCI|HDAUDIO|USB)\\")) continue;
            list.Add(new TreiberStand { Id = id, Name = (o["DeviceName"]?.ToString() ?? "").Trim(), Version = version, Class = o["DeviceClass"]?.ToString() ?? "" });
        }
        return list;
    }

    // einmal je Start, im Hintergrund
    public static void Start()
    {
        if (started) return;
        started = true;
        var ui = System.Windows.Application.Current.Dispatcher;
        Task.Run(() =>
        {
            try
            {
                var drivers = Drivers();
                if (drivers.Count == 0) return;
                var installs = Ereignisse.DriverInstalls();
                var crashes = Ereignisse.Crashes();
                List<ProbeEintrag> result = new();
                Ergebnisse.Change(results =>
                {
                    var history = Ergebnisse.History(results);
                    var known = new Dictionary<string, TreiberStand>();
                    if (history["Drivers"] is JsonObject saved)
                        foreach (var (id, node) in saved)
                            known[id] = new TreiberStand { Id = id, Name = Altdaten.Text(node, "Name", ""), Version = Altdaten.Text(node, "Version", ""), Class = Altdaten.Text(node, "Class", "") };
                    var last = history["LastInstall"] is JsonValue v && v.TryGetValue<long>(out var l) ? l : 0;
                    result = Probezeit.Update(known, Read(history), drivers, installs, crashes, DateTime.Now, last);
                    var map = new JsonObject();
                    foreach (var (id, d) in known) map[id] = new JsonObject { ["Name"] = d.Name, ["Version"] = d.Version, ["Class"] = d.Class };
                    history["Drivers"] = map;
                    history["Probation"] = new JsonArray(result.Select(e => (JsonNode)new JsonObject
                    {
                        ["Id"] = e.Id, ["Name"] = e.Name, ["Class"] = e.Class, ["Old"] = e.Old, ["New"] = e.New, ["Since"] = e.Since, ["Source"] = e.Source,
                        ["Done"] = e.Done, ["Verdict"] = e.Verdict, ["After"] = e.After, ["Before"] = e.Before, ["BeforeDays"] = e.BeforeDays,
                    }).ToArray());
                });
                ui.BeginInvoke(() => { Entries = result; Changed?.Invoke(); });
                Tagesbilder.Add(drivers, crashes);
            }
            catch (Exception) { }
        });
    }

    // nach einer Installation durch PulsRig: ein Treiberwechsel um diese Zeit kam von PulsRig
    public static void MarkInstall()
    {
        try { Ergebnisse.Change(r => Ergebnisse.History(r)["LastInstall"] = DateTime.Now.Ticks); } catch (Exception) { }
    }

    // die weggeklickte Warnung der Startseite (Einstellung ProbeWarnHidden wie im PowerShell-Programm)
    public static ProbeEintrag? Warning()
    {
        var w = Probezeit.Warning(Entries, DateTime.Now);
        return w == null || Altdaten.Text(Altdaten.Settings(), "ProbeWarnHidden", "") == Probezeit.WarnKey(w) ? null : w;
    }

    public static void Hide(ProbeEintrag e) => Altdaten.Change(s => s["ProbeWarnHidden"] = Probezeit.WarnKey(e));
}
