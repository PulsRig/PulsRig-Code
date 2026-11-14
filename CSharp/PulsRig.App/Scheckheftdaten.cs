using System.Text.Json.Nodes;
using PulsRig.Core;

namespace PulsRig.App;

// Das digitale PC-Scheckheft in der Ergebnisdatei unter History.Logbook (Einträge) und History.LogbookParts (Bauteile
// beim letzten Blick). Einmal je Programmlauf nach dem Tagesbild: Bauteile vergleichen und aus den Verläufen
// (Benchmarks, Messpunkte, Probezeit, Tagesbilder) neue Einträge übernehmen (Core.Scheckheft.Merge).
static class Scheckheftdaten
{
    public static event Action? Changed;

    static HeftEintrag ToEntry(JsonObject o) => new()
    {
        D = Altdaten.Text(o, "D", ""), Kind = Altdaten.Text(o, "K", ""), Title = Altdaten.Text(o, "T", ""), Sub = Altdaten.Text(o, "S", ""),
        Key = Altdaten.Text(o, "Key", ""), Manual = Altdaten.Flag(o, "M", false),
    };

    static JsonObject ToJson(HeftEintrag e)
    {
        var o = new JsonObject { ["D"] = e.D, ["K"] = e.Kind, ["T"] = e.Title };
        if (e.Sub.Length > 0) o["S"] = e.Sub;
        if (e.Key.Length > 0) o["Key"] = e.Key;
        if (e.Manual) o["M"] = true;
        return o;
    }

    static List<HeftEintrag> Read(JsonObject history) =>
        (history["Logbook"] as JsonArray ?? new()).OfType<JsonObject>().Select(ToEntry).Where(e => e.D.Length > 0).OrderByDescending(e => e.D, StringComparer.Ordinal).ToList();

    public static List<HeftEintrag> Entries()
    {
        try { return Read(Ergebnisse.History(Ergebnisse.Read())); } catch (Exception) { return new(); }
    }

    public static List<HeftTeil> SavedParts()
    {
        try { return Parts(Ergebnisse.History(Ergebnisse.Read())); } catch (Exception) { return new(); }
    }

    static List<HeftTeil> Parts(JsonObject history) =>
        (history["LogbookParts"] as JsonArray ?? new()).Select(n => HeftTeil.Parse(n?.ToString() ?? "")).Where(p => p != null).Select(p => p!).ToList();

    // die Bauteile jetzt; Seriennummern bleiben bewusst draußen
    public static List<HeftTeil> CurrentParts()
    {
        var list = new List<HeftTeil>();
        try { if (Abfragen.Cpu() is { } cpu && cpu.Name.Length > 0) list.Add(new HeftTeil { Kind = "Prozessor", Name = cpu.Name.Trim() }); } catch (Exception) { }
        try { if (Abfragen.Gpu() is { } gpu && gpu.Name.Length > 0) list.Add(new HeftTeil { Kind = "Grafikkarte", Name = gpu.Name.Trim() }); } catch (Exception) { }
        try
        {
            var ram = Abfragen.Memory();
            var bytes = ram.Modules.Sum(m => m.Bytes);
            if (bytes <= 0) bytes = ram.Total;
            if (bytes > 0) list.Add(new HeftTeil { Kind = "Arbeitsspeicher", Name = "", Size = Math.Round(bytes / (1L << 30)) });
        }
        catch (Exception) { }
        try
        {
            foreach (var d in Abfragen.Drives().Disks.Where(d => d.Bus != "USB").OrderBy(d => d.Name, StringComparer.Ordinal))
                list.Add(new HeftTeil { Kind = "Laufwerk", Name = d.Name.Trim(), Size = Math.Round(d.Size / 1e9) });
        }
        catch (Exception) { }
        return list;
    }

    static double? Num(JsonNode? o, string name) => o?[name] is JsonValue v && v.TryGetValue<double>(out var d) ? d : null;

    // alles, was die Verläufe gerade hergeben
    static List<HeftEintrag> Found(JsonObject history)
    {
        var found = new List<HeftEintrag>();
        foreach (var r in (history["Benchmarks"] as JsonArray ?? new()).OfType<JsonObject>())
            if (Scheckheft.Benchmark(Altdaten.Text(r, "D", ""), Num(r, "S"), Num(r, "M"), Num(r, "G"), Num(r, "R")) is { } b) found.Add(b);
        var points = Verschleissdaten.Points();
        found.AddRange(Scheckheft.Stresses(points));
        found.AddRange(Scheckheft.Temperatures(points));
        found.AddRange(Probezeitlauf.Read(history).Select(Scheckheft.Driver));
        var snaps = (history["Snapshots"] as JsonArray ?? new()).OfType<JsonObject>()
            .Select(o => (D: Altdaten.Text(o, "D", ""), W: Altdaten.Text(o, "Windows", ""))).Where(s => s.D.Length > 0 && s.W.Length > 0).OrderBy(s => s.D, StringComparer.Ordinal).ToList();
        for (var i = 1; i < snaps.Count; i++)
            if (snaps[i - 1].W != snaps[i].W) found.Add(Scheckheft.Windows(snaps[i].D, snaps[i - 1].W, snaps[i].W));
        return found;
    }

    // aus der Prüfung beim Start, im Hintergrund (nach dem Tagesbild)
    public static void Update()
    {
        try
        {
            // neue Spielsitzungen erst zu Messpunkten machen, sonst fehlen die Monatswerte der Temperaturen
            try { Verschleissdaten.Update(); } catch (Exception) { }
            var parts = CurrentParts();
            var now = DateTime.Now;
            Ergebnisse.Change(results =>
            {
                var history = Ergebnisse.History(results);
                var saved = Read(history);
                var found = Found(history);
                if (parts.Count > 0)
                {
                    if (saved.Count == 0 && history["LogbookParts"] == null) found.Add(Scheckheft.Start(parts, now));
                    found.AddRange(Scheckheft.PartChanges(Parts(history), parts, now));
                    history["LogbookParts"] = new JsonArray(parts.Select(p => (JsonNode)p.Line).ToArray());
                }
                history["Logbook"] = new JsonArray(Scheckheft.Merge(saved, found).Select(e => (JsonNode)ToJson(e)).ToArray());
            });
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Changed?.Invoke());
        }
        catch (Exception e) { Fehlerprotokoll.Write(e); }
    }

    public static void Add(HeftEintrag entry)
    {
        Ergebnisse.Change(results =>
        {
            var history = Ergebnisse.History(results);
            history["Logbook"] = new JsonArray(Scheckheft.Merge(Read(history).Append(entry), Array.Empty<HeftEintrag>()).Select(e => (JsonNode)ToJson(e)).ToArray());
        });
        Changed?.Invoke();
    }

    // nur Einträge von Hand lassen sich löschen; die automatischen kämen beim nächsten Start ohnehin wieder
    public static void Remove(HeftEintrag entry)
    {
        Ergebnisse.Change(results =>
        {
            var history = Ergebnisse.History(results);
            var list = Read(history);
            list.RemoveAll(e => e.Manual && e.D == entry.D && e.Title == entry.Title && e.Sub == entry.Sub);
            history["Logbook"] = new JsonArray(list.Select(e => (JsonNode)ToJson(e)).ToArray());
        });
        Changed?.Invoke();
    }
}
