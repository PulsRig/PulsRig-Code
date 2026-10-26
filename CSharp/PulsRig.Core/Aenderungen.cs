using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace PulsRig.Core
{
    // "Was hat sich geändert?" wie PulsRig-Aenderungen.ps1: einmal am Tag ein kleines Bild des PCs (Windows-Stand,
    // Energieplan, Programme, Autostart, wichtige Treiber) unter History.Snapshots, verglichen mit gestern, vor 7 oder
    // vor 30 Tagen, dazu die Abstürze seit diesem Tag. Felder und Zeilenformat wie im PowerShell-Programm.
    public sealed class Tagesbild
    {
        public string D { get; set; } = "";
        public string Windows { get; set; } = "";
        public string Plan { get; set; } = "";
        // "Name|Version|Datum", "Name|an" oder "Name|aus", "Id|Name|Version|Klasse"
        public List<string> Programs { get; set; } = new List<string>();
        public List<string> Autostart { get; set; } = new List<string>();
        public List<string> Drivers { get; set; } = new List<string>();
    }

    public sealed class Aenderung
    {
        public string Title { get; set; } = "";
        public string Sub { get; set; } = "";
        // accent, warn, bad oder leer
        public string Tone { get; set; } = "";
        // windows, driver, programs, autostart, plan, crashes
        public string Kind { get; set; } = "";
    }

    public static class Aenderungen
    {
        static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

        public static string DayKey(DateTime day) => day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        static DateTime ParseDay(string d) => DateTime.ParseExact(d, "yyyy-MM-dd", CultureInfo.InvariantCulture);

        public static string Day(string d)
        {
            try { return ParseDay(d).ToString("dd.MM.", De); } catch (FormatException) { return d; }
        }

        public static List<string> Lines(IEnumerable<string> lines) => lines.Where(l => !string.IsNullOrEmpty(l)).Distinct().OrderBy(l => l, StringComparer.Ordinal).ToList();

        // das Bild von heute ersetzt ein älteres von heute; die letzten 8 Tage ganz, davor eines je Woche, nichts älter als 35 Tage
        public static List<Tagesbild> Keep(IEnumerable<Tagesbild> saved, Tagesbild today, DateTime now)
        {
            var keep = new List<Tagesbild>();
            var weeks = new HashSet<int>();
            foreach (var entry in saved.Where(s => s != null && s.D != today.D).Concat(new[] { today }).OrderByDescending(s => s.D, StringComparer.Ordinal))
            {
                double age;
                try { age = (now - ParseDay(entry.D)).TotalDays; } catch (FormatException) { continue; }
                if (age > 35) continue;
                if (age < 8) { keep.Add(entry); continue; }
                if (weeks.Add((int)Math.Floor(age / 7))) keep.Add(entry);
            }
            return keep.OrderBy(s => s.D, StringComparer.Ordinal).ToList();
        }

        // das Bild, mit dem verglichen wird: das jüngste, das mindestens so alt ist, sonst das älteste
        public static Tagesbild? Before(IReadOnlyList<Tagesbild> snaps, int days, DateTime now)
        {
            var sorted = snaps.OrderBy(s => s.D, StringComparer.Ordinal).ToList();
            if (sorted.Count < 2) return null;
            var limit = DayKey(now.Date.AddDays(-days));
            return sorted.LastOrDefault(s => string.CompareOrdinal(s.D, limit) <= 0) ?? sorted[0];
        }

        public static bool Exact(Tagesbild old, int days, DateTime now) => string.CompareOrdinal(old.D, DayKey(now.Date.AddDays(-days))) <= 0;

        // "Discord, Steam, OBS Studio und 2 weitere"
        public static string JoinNames(IEnumerable<string> names, int max = 4)
        {
            var list = names.Where(n => !string.IsNullOrEmpty(n)).ToList();
            if (list.Count <= max) return string.Join(", ", list);
            return string.Join(", ", list.Take(max)) + " und " + (list.Count - max) + " weitere";
        }

        static Dictionary<string, string[]> Map(IEnumerable<string> lines, int min)
        {
            var map = new Dictionary<string, string[]>(StringComparer.Ordinal);
            foreach (var line in lines)
            {
                var p = (line ?? "").Split('|');
                if (p.Length >= min) map[p[0]] = p;
            }
            return map;
        }

        static string Part(string[] p, int i) => i < p.Length ? p[i] : "";

        public static List<Aenderung> Compare(Tagesbild? old, Tagesbild? now, IEnumerable<ProbeEintrag>? probation = null, AbsturzDaten? crashes = null)
        {
            var changes = new List<Aenderung>();
            if (old == null || now == null) return changes;

            if (old.Windows.Length > 0 && now.Windows.Length > 0 && old.Windows != now.Windows)
                changes.Add(new Aenderung { Title = "Windows wurde aktualisiert", Sub = "Stand " + old.Windows + " → " + now.Windows, Tone = "accent", Kind = "windows" });

            // Treiber: gleiche Gerätekennung, andere Version; Grafiktreiber zuerst
            var oldDrivers = Map(old.Drivers, 3);
            var driverChanges = new List<(string Name, string Old, string New, string Class, string Id)>();
            foreach (var line in now.Drivers)
            {
                var p = (line ?? "").Split('|');
                if (p.Length < 4) continue;
                if (oldDrivers.TryGetValue(p[0], out var before) && before[2] != p[2]) driverChanges.Add((p[1], before[2], p[2], p[3], p[0]));
            }
            driverChanges = driverChanges.OrderBy(d => d.Class == "DISPLAY" ? 0 : 1).ToList();
            var probes = (probation ?? Enumerable.Empty<ProbeEintrag>()).ToList();
            foreach (var d in driverChanges.Take(3))
            {
                var probe = probes.FirstOrDefault(e => e.Id == d.Id && e.New == d.New);
                var how = probe == null ? "" : (probe.Source == "PulsRig" ? "von PulsRig" : "von Windows Update oder von Hand") + " am " + Probezeit.Day(probe.Since);
                changes.Add(new Aenderung
                {
                    Title = Probezeit.ClassName(d.Class) + " geändert: " + d.Name,
                    Sub = string.Join(" · ", new[] { "Version " + d.Old + " → " + d.New, how }.Where(s => s.Length > 0)),
                    Tone = d.Class == "DISPLAY" ? "warn" : "accent", Kind = "driver",
                });
            }
            if (driverChanges.Count > 3)
                changes.Add(new Aenderung { Title = (driverChanges.Count - 3) + " weitere Treiber geändert", Sub = JoinNames(driverChanges.Skip(3).Select(d => d.Name)), Tone = "accent", Kind = "driver" });

            // Programme nach Namen
            var oldPrograms = Map(old.Programs, 1);
            var newPrograms = Map(now.Programs, 1);
            var added = newPrograms.Keys.Where(k => !oldPrograms.ContainsKey(k)).OrderBy(k => k, StringComparer.Ordinal).ToList();
            var removed = oldPrograms.Keys.Where(k => !newPrograms.ContainsKey(k)).OrderBy(k => k, StringComparer.Ordinal).ToList();
            var updated = newPrograms.Keys.Where(k => oldPrograms.ContainsKey(k) && Part(oldPrograms[k], 1) != Part(newPrograms[k], 1)).OrderBy(k => k, StringComparer.Ordinal).ToList();
            if (added.Count > 0)
            {
                var version = Part(newPrograms[added[0]], 1);
                changes.Add(new Aenderung
                {
                    Title = added.Count == 1 ? "Neues Programm: " + added[0] : added.Count + " neue Programme",
                    Sub = added.Count == 1 ? (version.Length > 0 ? "Version " + version : "installiert") : JoinNames(added), Tone = "accent", Kind = "programs",
                });
            }
            if (removed.Count > 0)
                changes.Add(new Aenderung { Title = removed.Count == 1 ? "Entfernt: " + removed[0] : removed.Count + " Programme entfernt", Sub = removed.Count == 1 ? "nicht mehr installiert" : JoinNames(removed), Kind = "programs" });
            if (updated.Count > 0)
                changes.Add(new Aenderung
                {
                    Title = updated.Count == 1 ? "Aktualisiert: " + updated[0] : updated.Count + " Programme aktualisiert",
                    Sub = updated.Count == 1 ? "Version " + Part(oldPrograms[updated[0]], 1) + " → " + Part(newPrograms[updated[0]], 1) : JoinNames(updated), Kind = "programs",
                });

            // Autostart
            var oldStart = Map(old.Autostart, 2).ToDictionary(p => p.Key, p => p.Value[1]);
            var newStart = Map(now.Autostart, 2).ToDictionary(p => p.Key, p => p.Value[1]);
            var startNew = newStart.Keys.Where(k => !oldStart.ContainsKey(k) && newStart[k] == "an").OrderBy(k => k, StringComparer.Ordinal)
                .Concat(newStart.Keys.Where(k => oldStart.TryGetValue(k, out var o) && o == "aus" && newStart[k] == "an").OrderBy(k => k, StringComparer.Ordinal)).ToList();
            var startGone = oldStart.Keys.Where(k => oldStart[k] == "an" && (!newStart.TryGetValue(k, out var n) || n == "aus")).OrderBy(k => k, StringComparer.Ordinal).ToList();
            if (startNew.Count > 0)
                changes.Add(new Aenderung
                {
                    Title = startNew.Count == 1 ? "Startet jetzt mit Windows: " + startNew[0] : startNew.Count + " Programme starten jetzt mit Windows",
                    Sub = startNew.Count == 1 ? "Neu im Autostart; lässt sich unter Werkzeuge → Autostart ausschalten" : JoinNames(startNew), Tone = "warn", Kind = "autostart",
                });
            if (startGone.Count > 0)
                changes.Add(new Aenderung
                {
                    Title = startGone.Count == 1 ? "Startet nicht mehr mit Windows: " + startGone[0] : startGone.Count + " Programme starten nicht mehr mit Windows",
                    Sub = startGone.Count == 1 ? "aus dem Autostart entfernt oder ausgeschaltet" : JoinNames(startGone), Kind = "autostart",
                });

            if (old.Plan.Length > 0 && now.Plan.Length > 0 && old.Plan != now.Plan)
                changes.Add(new Aenderung { Title = "Anderer Energieplan", Sub = old.Plan + " → " + now.Plan, Tone = "accent", Kind = "plan" });

            // Abstürze seit dem Vergleichstag, ganz oben
            if (crashes != null)
            {
                DateTime from;
                try { from = ParseDay(old.D); } catch (FormatException) { return changes; }
                var blue = crashes.Blue.Count(c => c.When >= from);
                var other = crashes.Off.Concat(crashes.Tdr).Concat(crashes.Apps).Count(c => c.When >= from);
                if (blue + other > 0)
                {
                    var parts = new List<string>();
                    if (blue > 0) parts.Add(blue == 1 ? "1 Bluescreen" : blue + " Bluescreens");
                    if (other > 0) parts.Add(other == 1 ? "1 Aussetzer oder Ausschalten" : other + " Aussetzer oder Ausschalten");
                    changes.Insert(0, new Aenderung { Title = "Abstürze seit " + Day(old.D), Sub = string.Join(" · ", parts) + " · Einzelheiten unter Hardware → Abstürze", Tone = blue > 0 ? "bad" : "warn", Kind = "crashes" });
                }
            }
            return changes;
        }
    }
}
