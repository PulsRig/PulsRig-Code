using System;
using System.Collections.Generic;
using System.Linq;

namespace PulsRig.Core
{
    // Probezeit für neue Treiber wie PulsRig-Probezeit.ps1. Hat sich die Version eines Grafik-, Netzwerk-, Audio- oder
    // Speichertreibers seit dem letzten Start geändert, beginnt für ihn eine Probezeit von 7 Tagen. Wann er wirklich
    // installiert wurde, steht im Ereignis 20001 von UserPnp; fehlt es, gilt der Zeitpunkt, an dem PulsRig es bemerkt.
    // Verglichen werden die Vorfälle seitdem mit den 14 Tagen davor (Bluescreens und plötzliches Ausschalten, beim
    // Grafiktreiber auch Aussetzer und Programmabstürze darin): mindestens zwei und mehr als doppelt so viele pro Tag
    // heißt "auffällig", sieben ruhige Tage "bestanden". Felder wie in History.Probation der Ergebnisdatei.
    public sealed class ProbeEintrag
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Class { get; set; } = "";
        public string Old { get; set; } = "";
        public string New { get; set; } = "";
        public long Since { get; set; }
        public string Source { get; set; } = "Windows";
        public bool Done { get; set; }
        public string Verdict { get; set; } = "läuft";
        public int After { get; set; }
        public int Before { get; set; }
        public int BeforeDays { get; set; }
    }

    public sealed class TreiberStand
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Version { get; set; } = "";
        public string Class { get; set; } = "";
    }

    public static class Probezeit
    {
        public const int Days = 7;

        public static readonly IReadOnlyDictionary<string, string> Classes = new Dictionary<string, string>
        {
            ["DISPLAY"] = "Grafiktreiber", ["NET"] = "Netzwerktreiber", ["MEDIA"] = "Audiotreiber", ["SCSIADAPTER"] = "Speichertreiber", ["HDC"] = "Speichertreiber",
        };

        public static string ClassName(string cls) => Classes.TryGetValue(cls, out var name) ? name : "Treiber";

        static readonly System.Globalization.CultureInfo De = System.Globalization.CultureInfo.GetCultureInfo("de-DE");

        public static string Day(long ticks) => new DateTime(ticks).ToString("dd.MM.", De);

        // Vorfälle, die zu einem Treiber zählen
        public static List<long> Events(AbsturzDaten crashes, string cls)
        {
            var list = crashes.Blue.Concat(crashes.Off).Select(x => x.When.Ticks).ToList();
            if (cls == "DISPLAY") list.AddRange(crashes.Tdr.Concat(crashes.Apps).Select(x => x.When.Ticks));
            return list;
        }

        // Treiberstände abgleichen (known wird fortgeschrieben) und laufende Probezeiten bewerten; gibt die neue Liste zurück
        public static List<ProbeEintrag> Update(Dictionary<string, TreiberStand> known, List<ProbeEintrag> list, IEnumerable<TreiberStand> drivers,
            IDictionary<string, long> installs, AbsturzDaten crashes, DateTime now, long lastInstall)
        {
            list = list.ToList();
            var first = known.Count == 0;
            foreach (var driver in drivers)
            {
                if (known.TryGetValue(driver.Id, out var old) && old.Version != driver.Version && !first && Classes.ContainsKey(driver.Class))
                {
                    var since = installs.TryGetValue(driver.Id.ToUpperInvariant(), out var at) && at > 0 ? at : now.Ticks;
                    var byPulsRig = lastInstall > 0 && Math.Abs(since - lastInstall) < TimeSpan.FromHours(6).Ticks;
                    list.RemoveAll(e => e.Id == driver.Id);
                    list.Add(new ProbeEintrag { Id = driver.Id, Name = driver.Name, Class = driver.Class, Old = old.Version, New = driver.Version, Since = since, Source = byPulsRig ? "PulsRig" : "Windows" });
                }
                known[driver.Id] = new TreiberStand { Id = driver.Id, Name = driver.Name, Version = driver.Version, Class = driver.Class };
            }
            var windowStart = now.AddDays(-30).Ticks;
            foreach (var entry in list.Where(e => !e.Done))
            {
                var events = Events(crashes, entry.Class);
                var after = events.Count(t => t >= entry.Since);
                var beforeStart = Math.Max(entry.Since - TimeSpan.FromDays(14).Ticks, windowStart);
                var before = events.Count(t => t >= beforeStart && t < entry.Since);
                var beforeDays = (int)Math.Max(1, Math.Round((entry.Since - beforeStart) / (double)TimeSpan.TicksPerDay, MidpointRounding.ToEven));
                var days = (now.Ticks - entry.Since) / (double)TimeSpan.TicksPerDay;
                var worse = after >= 2 && after / Math.Max(1, days) > 2.0 * before / beforeDays;
                entry.After = after; entry.Before = before; entry.BeforeDays = beforeDays;
                if (worse) entry.Verdict = "auffällig";
                else if (days >= Days) { entry.Verdict = "bestanden"; entry.Done = true; }
                else entry.Verdict = "läuft";
                // nach 14 Tagen endet auch eine auffällige Probezeit
                if (days >= 14) entry.Done = true;
            }
            return list.Count > 20 ? list.Skip(list.Count - 20).ToList() : list;
        }

        // die Probezeiten, die etwas zu sagen haben: laufend, auffällig oder seit höchstens 14 Tagen
        public static List<ProbeEintrag> Entries(IEnumerable<ProbeEintrag> list, DateTime now) =>
            list.Where(e => !e.Done || e.Verdict == "auffällig" || now.Ticks - e.Since < TimeSpan.FromDays(14).Ticks).OrderByDescending(e => e.Since).ToList();

        // die Warnung der Startseite: auffällig und noch nicht beendet, der Grafiktreiber zuerst
        public static ProbeEintrag? Warning(IEnumerable<ProbeEintrag> list, DateTime now) =>
            Entries(list, now).Where(e => e.Verdict == "auffällig" && !e.Done).OrderBy(e => e.Class == "DISPLAY" ? 0 : 1).FirstOrDefault();

        public static string WarnKey(ProbeEintrag e) => e.Id + "|" + e.New + "|" + e.After;

        public static string WarnTitle(ProbeEintrag e) => "Seit dem neuen " + ClassName(e.Class) + " " + e.After + " Abstürze oder Aussetzer";

        // "NVIDIA …, neu seit 14.10. (Version 32.0.15.6094, vorher 32.0.15.5612). In den 14 Tagen davor: keine."
        public static string Text(ProbeEintrag e) =>
            e.Name + ", neu seit " + Day(e.Since) + " (Version " + e.New + ", vorher " + e.Old + "). In den " + e.BeforeDays + " Tagen davor: " + (e.Before == 0 ? "keine" : e.Before.ToString()) + ".";

        // Unterzeile im Fenster "Abstürze"
        public static string Sub(ProbeEintrag e, DateTime now)
        {
            var day = Math.Min(Days, (int)Math.Floor((now.Ticks - e.Since) / (double)TimeSpan.TicksPerDay) + 1);
            var parts = new List<string>
            {
                "Treiber " + e.New + " seit " + Day(e.Since) + ", vorher " + e.Old,
                e.Source == "PulsRig" ? "von PulsRig installiert" : "von Windows Update oder von Hand",
                e.Verdict == "bestanden" ? "sieben Tage ohne Auffälligkeiten" : "Tag " + day + " von " + Days,
                e.After == 0 ? "seitdem keine Abstürze" : e.After == 1 ? "seitdem 1 Absturz oder Aussetzer" : "seitdem " + e.After + " Abstürze oder Aussetzer",
            };
            if (e.Verdict == "auffällig") parts.Add(e.Before == 0 ? "davor keine" : "davor " + e.Before + " in " + e.BeforeDays + " Tagen");
            return string.Join(" · ", parts);
        }
    }
}
