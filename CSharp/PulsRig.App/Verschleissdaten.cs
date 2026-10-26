using System.IO;
using System.Text.Json.Nodes;
using PulsRig.Core;

namespace PulsRig.App;

// Messpunkte und Laufwerksverlauf für "Verschleiß" in der Ergebnisdatei (History.Thermal, History.Disks), mit denselben
// Feldern wie im PowerShell-Programm (PulsRig-Verschleiss.ps1, Add-DriveHistory in PulsRig-Verlauf.ps1).
static class Verschleissdaten
{
    static readonly string[] Numbers = { "Min", "GT", "GW", "GF", "CT", "CC", "CW" };

    static Messpunkt ToPoint(JsonObject o)
    {
        double? N(string k) => o[k] is JsonValue v && v.TryGetValue<double>(out var d) ? d : null;
        return new Messpunkt
        {
            D = Altdaten.Text(o, "D", ""), Src = Altdaten.Text(o, "Src", ""), Name = Altdaten.Text(o, "Name", ""), File = Altdaten.Text(o, "File", ""),
            Min = N("Min"), GT = N("GT"), GW = N("GW"), GF = N("GF"), CT = N("CT"), CC = N("CC"), CW = N("CW"),
        };
    }

    static JsonObject ToJson(Messpunkt p)
    {
        var o = new JsonObject { ["D"] = p.D, ["Src"] = p.Src };
        if (p.Name.Length > 0) o["Name"] = p.Name;
        if (p.File.Length > 0) o["File"] = p.File;
        var values = new[] { p.Min, p.GT, p.GW, p.GF, p.CT, p.CC, p.CW };
        for (var i = 0; i < Numbers.Length; i++) if (values[i] is { } v && !double.IsNaN(v)) o[Numbers[i]] = v;
        return o;
    }

    public static List<Messpunkt> Points() =>
        (Ergebnisse.History(Ergebnisse.Read())["Thermal"] as JsonArray ?? new()).OfType<JsonObject>().Select(ToPoint).ToList();

    static void Add(IEnumerable<Messpunkt> points) => Ergebnisse.Change(results =>
    {
        var history = Ergebnisse.History(results);
        var list = (history["Thermal"] as JsonArray ?? new()).OfType<JsonObject>().Select(o => o.DeepClone()).ToList();
        list.AddRange(points.Select(p => (JsonNode)ToJson(p)));
        history["Thermal"] = new JsonArray(list.Skip(Math.Max(0, list.Count - 200)).ToArray());
    });

    // neue, abgeschlossene Spielsitzungen übernehmen (je Datei einmal), wie Update-ThermalHistory
    public static void Update()
    {
        var folder = Path.Combine(Altdaten.Folder, "Aufzeichnungen");
        if (!Directory.Exists(folder)) return;
        var known = Points().Select(p => p.File).Where(f => f.Length > 0).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var added = new List<Messpunkt>();
        foreach (var file in new DirectoryInfo(folder).GetFiles("*.csv").OrderBy(f => f.Name))
        {
            if (known.Contains(file.Name)) continue;
            // noch in Arbeit: der Helfer schreibt alle 5 Sekunden, eine fertige Sitzung ist eine Minute alt
            if (DateTime.Now - file.LastWriteTime < TimeSpan.FromMinutes(1)) continue;
            try { added.Add(Verschleiss.Point(SensorPage.Read(file.FullName), file.Name)); } catch (Exception) { }
        }
        if (added.Count > 0) Add(added);
    }

    // Messpunkt aus einem Stabilitätstest ab 5 Minuten: Mittel (Median) der letzten Minute
    public static void AddStress(string what, double seconds, IReadOnlyList<(double? GT, double? GW, double? GF, double? CT, double? CC, double? CW)> tail)
    {
        if (seconds < 290 || tail.Count < 20) return;
        var p = new Messpunkt { D = DateTime.Now.ToString("yyyy-MM-dd"), Src = "Stresstest", Name = what, Min = Math.Round(seconds / 60, MidpointRounding.ToEven) };
        double? R(double v, int d) => double.IsNaN(v) ? null : Math.Round(v, d, MidpointRounding.ToEven);
        if (what is "gpu" or "both") { p.GT = R(Verschleiss.Median(tail.Select(t => t.GT)), 1); p.GW = R(Verschleiss.Median(tail.Select(t => t.GW)), 1); p.GF = R(Verschleiss.Median(tail.Select(t => t.GF)), 1); }
        if (what is "cpu" or "both") { p.CT = R(Verschleiss.Median(tail.Select(t => t.CT)), 1); p.CC = R(Verschleiss.Median(tail.Select(t => t.CC)) * 1000, 0); p.CW = R(Verschleiss.Median(tail.Select(t => t.CW)), 1); }
        try { Add(new[] { p }); } catch (Exception) { }
    }

    // Laufwerke je Tag festhalten wie Add-DriveHistory (Name und Größe erkennen ein Laufwerk wieder)
    public static string DiskKey(Laufwerk d) => d.Name + "|" + Math.Round(d.Size / (1L << 30), MidpointRounding.ToEven);

    public static void AddDrives(Laufwerke drives)
    {
        var today = DateTime.Now.ToString("yyyy-MM-dd");
        try
        {
            Ergebnisse.Change(results =>
            {
                var history = Ergebnisse.History(results);
                var all = history["Disks"] as JsonObject ?? (JsonObject)(history["Disks"] = new JsonObject());
                foreach (var disk in drives.Disks)
                {
                    var key = DiskKey(disk);
                    var faults = drives.Faults?.Disks.TryGetValue(disk.Number, out var f) == true ? f : default;
                    var entry = new JsonObject { ["D"] = today, ["F"] = faults.Count, ["L"] = faults.Count > 0 ? faults.Last.ToString("dd.MM. HH:mm") : "", ["H"] = disk.Health };
                    var list = (all[key] as JsonArray ?? new()).OfType<JsonObject>().ToList();
                    var old = list.FirstOrDefault(e => Altdaten.Text(e, "D", "") == today);
                    var oldT = old?["T"] is JsonValue ov && ov.TryGetValue<int>(out var ot) ? ot : 0;
                    // am selben Tag zählt die höchste Temperatur
                    var t = Math.Max(disk.Temperature ?? 0, oldT);
                    if (t > 0) entry["T"] = t;
                    if (disk.Wear is { } w) entry["W"] = w;
                    var kept = list.Where(e => Altdaten.Text(e, "D", "") != today).Select(e => e.DeepClone()).Append(entry).ToList();
                    all[key] = new JsonArray(kept.Skip(Math.Max(0, kept.Count - 120)).ToArray());
                }
            });
        }
        catch (Exception) { }
    }

    // SSD-Lebensdauer: nur SSDs, die gerade angeschlossen sind und einen Verlauf mit Abnutzung haben
    public static List<Verschleissbefund> Ssds(Laufwerke drives)
    {
        var list = new List<Verschleissbefund>();
        var all = Ergebnisse.History(Ergebnisse.Read())["Disks"] as JsonObject;
        if (all == null) return list;
        foreach (var disk in drives.Disks.Where(d => d.Media == "SSD"))
        {
            var entries = (all[DiskKey(disk)] as JsonArray ?? new()).OfType<JsonObject>()
                .Where(e => e["W"] is JsonValue).Select(e => (Altdaten.Text(e, "D", ""), e["W"]!.GetValue<int>())).ToList();
            if (entries.Count > 0) list.Add(Verschleiss.Ssd(disk.Name, entries));
        }
        return list;
    }
}
