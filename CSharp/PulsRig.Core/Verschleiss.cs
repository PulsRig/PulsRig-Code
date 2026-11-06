using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace PulsRig.Core
{
    // Staub und Verschleiß wie PulsRig-Verschleiss.ps1. Lässt die Kühlung nach, wird es bei gleicher Leistung wärmer,
    // die Lüfter drehen schneller oder ein Prozessor an seiner Temperaturgrenze hält weniger Takt. Dafür kommt aus jeder
    // Spielsitzung (ab der 10. Minute, nur unter Last) und jedem Stabilitätstest ab 5 Minuten ein Messpunkt in
    // History.Thermal (die letzten 200); verglichen werden die ältesten mit den neuesten, frühestens nach drei Wochen.
    // Dazu für jede SSD: Wie schnell steigt die Abnutzung, und wie lange hält sie bei diesem Tempo noch?
    public sealed class Messpunkt
    {
        public string D { get; set; } = "";
        public string Src { get; set; } = "";
        public string Name { get; set; } = "";
        public string File { get; set; } = "";
        public double? Min { get; set; }
        public double? GT { get; set; }
        public double? GW { get; set; }
        public double? GF { get; set; }
        public double? CT { get; set; }
        public double? CC { get; set; }
        public double? CW { get; set; }
    }

    public sealed class Verschleissbefund
    {
        public string Tone { get; set; } = "";
        public string Title { get; set; } = "";
        public string State { get; set; } = "";
        public string Text { get; set; } = "";
    }

    public static class Verschleiss
    {
        public const int MinDays = 21;          // Abstand zwischen den ältesten und den neuesten Messpunkten
        public const double Warmer = 5.0;       // so viel °C mehr bei gleicher Leistung gilt als Nachlassen
        public const double Fan = 15.0;         // so viele Prozentpunkte mehr Lüfter ebenso
        public const double Clock = 4.0;        // so viel % weniger Takt an der Temperaturgrenze ebenso

        static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

        public static double Median(IEnumerable<double?> values)
        {
            var list = values.Where(v => v.HasValue && !double.IsNaN(v.Value)).Select(v => v!.Value).OrderBy(v => v).ToList();
            if (list.Count == 0) return double.NaN;
            return list.Count % 2 == 1 ? list[list.Count / 2] : (list[list.Count / 2 - 1] + list[list.Count / 2]) / 2;
        }

        static double? R(double v, int digits) => double.IsNaN(v) ? (double?)null : Math.Round(v, digits, MidpointRounding.ToEven);

        // Messpunkt aus einer Spielsitzung: Proben ab der 10. Minute, Grafikkarte nur bei Last ab 85 %; ohne ihn eine
        // Markierung "kurz", damit die Datei nicht bei jedem Start neu gelesen wird
        public static Messpunkt Point(Spielsitzung s, string file)
        {
            var mark = new Messpunkt { D = s.Begin.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), Src = "kurz", File = file };
            var time = s.Column("Sekunde");
            if (time == null) return mark;
            var keep = Enumerable.Range(0, time.Count).Where(i => time[i] >= 600).ToList();
            if (keep.Count < 60) return mark;
            double Cell(string name, int i) => s.Column(name) is { } c && i < c.Count ? c[i] : double.NaN;
            var point = new Messpunkt { D = mark.D, Src = "Spiel", Name = s.Game, File = file, Min = Math.Round(keep.Count * 5 / 60.0, MidpointRounding.ToEven) };
            var gpu = keep.Where(i => Cell("GpuLast", i) >= 85).ToList();
            if (gpu.Count >= 36)
            {
                point.GT = R(Median(gpu.Select(i => (double?)Cell("GpuTemp", i))), 1);
                point.GW = R(Median(gpu.Select(i => (double?)Cell("GpuWatt", i))), 1);
                point.GF = R(Median(gpu.Select(i => (double?)Cell("GpuLuefter", i))), 1);
            }
            var cpu = keep.Where(i => !double.IsNaN(Cell("CpuTemp", i))).ToList();
            if (cpu.Count >= 36)
            {
                point.CT = R(Median(cpu.Select(i => (double?)Cell("CpuTemp", i))), 1);
                point.CC = R(Median(cpu.Select(i => (double?)Cell("CpuTakt", i))), 0);
                point.CW = R(Median(cpu.Select(i => (double?)Cell("CpuWatt", i))), 1);
            }
            return point.GT == null && point.CT == null ? mark : point;
        }

        static DateTime Day(string d) => DateTime.ParseExact(d, "yyyy-MM-dd", CultureInfo.InvariantCulture);

        // Art der Last: Stabilitätstest je Teil (gpu, cpu, both) oder Spiel je Name
        public static string Kind(Messpunkt p) => p.Src == "Stresstest" ? "S|" + p.Name : p.Src + "|" + p.Name.ToLowerInvariant();

        static string KindText(Messpunkt p) => p.Src == "Stresstest"
            ? "Stabilitätstest " + (p.Name == "gpu" ? "Grafikkarte" : p.Name == "cpu" ? "Prozessor" : "beide")
            : p.Name.Length > 0 ? p.Name : "Spielsitzungen";

        // Hinweis für die Startseite: Kühlung lässt nach (Schlüssel = jüngster Messtag, damit ein Ausblenden bis zur
        // nächsten Messung gilt)
        public static (string Title, string Key)? Warning(IEnumerable<Messpunkt> all, DateTime? cleaned = null)
        {
            var list = all.ToList();
            var bad = new[] { Trend(list, 'G', cleaned), Trend(list, 'C', cleaned) }.FirstOrDefault(t => t.Tone == "warn");
            if (bad == null) return null;
            var last = list.Where(p => p.Src != "kurz" && p.D.Length == 10).Select(p => p.D).OrderBy(d => d, StringComparer.Ordinal).LastOrDefault() ?? "";
            return (bad.Title + ": Kühlung lässt nach – entstauben?", bad.Title + "|" + last);
        }

        // Vergleich alt gegen neu für einen Teil ('G' Grafikkarte, 'C' Prozessor). Ist eine Reinigung im Scheckheft
        // eingetragen, beginnt der Vergleich danach neu (der Staub von früher ist weg); dazu kommt eine Zeile, wie viel
        // die Reinigung gebracht hat. Messpunkte vom Tag der Reinigung zählen weder davor noch danach.
        public static Verschleissbefund Trend(IEnumerable<Messpunkt> all, char part, DateTime? cleaned = null)
        {
            Func<Messpunkt, double?> temp = part == 'G' ? p => p.GT : p => p.CT;
            Func<Messpunkt, double?> watt = part == 'G' ? p => p.GW : p => p.CW;
            var points = all.Where(p => p.Src != "kurz" && temp(p) is > 0 && p.D.Length == 10).OrderBy(p => p.D, StringComparer.Ordinal).ToList();
            var name = part == 'G' ? "Grafikkarte" : "Prozessor";
            var effect = "";
            if (cleaned is { } c)
            {
                var day = c.Date;
                var before = points.Where(p => Day(p.D) < day).ToList();
                points = points.Where(p => Day(p.D) > day).ToList();
                effect = CleaningEffect(before, points, part, day);
                var cut = "seit der Reinigung am " + day.ToString("dd.MM.yyyy", De);
                if (points.Count < 4)
                    return new Verschleissbefund { Title = name, State = "neu gestartet", Text = Join(effect, "Der Vergleich beginnt " + cut + " neu: erst " + points.Count + " von vier Messpunkten.") };
                var span = (Day(points[points.Count - 1].D) - Day(points[0].D)).TotalDays;
                if (span < MinDays)
                    return new Verschleissbefund { Title = name, State = "neu gestartet", Text = Join(effect, "Der Vergleich beginnt " + cut + " neu: " + points.Count + " Messpunkte, verglichen wird ab dem " + Day(points[0].D).AddDays(MinDays).ToString("dd.MM.", De) + ".") };
            }
            // gleiche Last zuerst: Reicht eine Art von Test (derselbe Stabilitätstest oder dasselbe Spiel) für den
            // Vergleich, zählt nur sie – ein Spiel und ein Stresstest heizen verschieden, auch bei gleicher Leistung
            var same = points.GroupBy(Kind)
                .Select(g => g.ToList())
                .Where(g => g.Count >= 4 && (Day(g[g.Count - 1].D) - Day(g[0].D)).TotalDays >= MinDays)
                .OrderByDescending(g => g.Count).FirstOrDefault();
            var basis = "";
            if (same != null) { points = same; basis = "Gleicher Test: " + KindText(same[0]) + "."; }
            if (points.Count < 4)
                return new Verschleissbefund { Title = name, State = "zu wenig Daten", Text = "Erst " + points.Count + " Messpunkte. Der Vergleich beginnt ab vier, aus Spielsitzungen ab 15 Minuten oder Stabilitätstests ab 5 Minuten." };
            var first = Day(points[0].D);
            var last = Day(points[points.Count - 1].D);
            if ((last - first).TotalDays < MinDays)
                return new Verschleissbefund { Title = name, State = "sammelt noch", Text = points.Count + " Messpunkte seit dem " + first.ToString("dd.MM.", De) + " – verglichen wird ab drei Wochen Abstand, ab dem " + first.AddDays(MinDays).ToString("dd.MM.", De) };
            // die ältesten und die neuesten Messpunkte, je ein Drittel, mindestens zwei
            var size = Math.Max(2, points.Count / 3);
            var old = points.Take(size).ToList();
            var now = points.Skip(points.Count - size).ToList();
            double oldT = Median(old.Select(temp)), newT = Median(now.Select(temp)), oldW = Median(old.Select(watt)), newW = Median(now.Select(watt));
            var since = first.ToString("dd.MM.yyyy", De);
            var parts = new List<string>();
            var tone = "good";
            // Temperatur im Verhältnis zur Leistung: auf die Leistung der alten Punkte umgerechnet (25 °C Raum angenommen)
            var warmer = newT - oldT;
            if (oldW > 0 && newW > 0) warmer = ((newT - 25) * oldW / newW + 25) - oldT;
            if (part == 'C' && oldT >= 87 && newT >= 87)
            {
                // an der Temperaturgrenze sagt die Temperatur nichts mehr: dort zählt, wie viel Takt die Kühlung zulässt
                double oldC = Median(old.Select(p => p.CC)), newC = Median(now.Select(p => p.CC));
                var drop = oldC > 0 ? 100 * (oldC - newC) / oldC : 0;
                parts.Add(string.Format(De, "An der Temperaturgrenze hält er jetzt im Schnitt {0:N0} MHz, anfangs ({1}) {2:N0} MHz.", newC, since, oldC));
                if (drop >= Clock) { tone = "warn"; parts.Add(string.Format(De, "Das sind {0:N0} % weniger: Die Kühlung schafft weniger als früher.", drop)); }
            }
            else
            {
                parts.Add(string.Format(De, "Unter Last jetzt im Schnitt {0:N0} °C bei {1:N0} W, anfangs ({2}) {3:N0} °C bei {4:N0} W.", newT, newW, since, oldT, oldW));
                if (warmer >= Warmer) { tone = "warn"; parts.Add(string.Format(De, "Bei gleicher Leistung {0:N0} °C wärmer als damals.", warmer)); }
            }
            if (part == 'G')
            {
                double oldF = Median(old.Select(p => p.GF)), newF = Median(now.Select(p => p.GF));
                if (!double.IsNaN(oldF) && !double.IsNaN(newF) && newF - oldF >= Fan)
                { tone = "warn"; parts.Add(string.Format(De, "Die Lüfter drehen {0:N0} % schneller als damals ({1:N0} statt {2:N0} %).", newF - oldF, newF, oldF)); }
            }
            if (basis.Length > 0) parts.Add(basis);
            if (effect.Length > 0) parts.Insert(0, effect);
            parts.Add(tone == "warn" ? "Zeit zum Entstauben: Lüfter, Kühlrippen und Filter reinigen. Hilft das nicht, kann die Wärmeleitpaste eingetrocknet sein."
                : "Die Kühlung hält mit: kein Nachlassen zu sehen.");
            return new Verschleissbefund { Tone = tone, Title = name, State = tone == "warn" ? "lässt nach" : "unverändert", Text = string.Join("\n", parts) };
        }

        static string Join(string first, string second) => first.Length == 0 ? second : first + "\n" + second;

        // Was hat die Reinigung gebracht? Die letzten (bis zu drei) Messpunkte davor gegen die ersten danach, möglichst
        // aus derselben Art von Test, auf gleiche Leistung umgerechnet. Leer, solange auf einer Seite Punkte fehlen.
        public static string CleaningEffect(IList<Messpunkt> before, IList<Messpunkt> after, char part, DateTime day)
        {
            Func<Messpunkt, double?> temp = part == 'G' ? p => p.GT : p => p.CT;
            Func<Messpunkt, double?> watt = part == 'G' ? p => p.GW : p => p.CW;
            before = before.Where(p => temp(p) is > 0).ToList();
            after = after.Where(p => temp(p) is > 0).ToList();
            if (before.Count == 0 || after.Count == 0) return "";
            // eine gemeinsame Art von Test, sonst alle
            var kind = after.Select(Kind).Distinct().Where(k => before.Any(p => Kind(p) == k))
                .OrderByDescending(k => Math.Min(before.Count(p => Kind(p) == k), after.Count(p => Kind(p) == k))).FirstOrDefault();
            var old = (kind == null ? before : before.Where(p => Kind(p) == kind).ToList()).Skip(Math.Max(0, (kind == null ? before.Count : before.Count(p => Kind(p) == kind)) - 3)).ToList();
            var now = (kind == null ? after : after.Where(p => Kind(p) == kind).ToList()).Take(3).ToList();
            double oldT = Median(old.Select(temp)), newT = Median(now.Select(temp)), oldW = Median(old.Select(watt)), newW = Median(now.Select(watt));
            var cooler = oldT - newT;
            if (oldW > 0 && newW > 0) cooler = oldT - ((newT - 25) * oldW / newW + 25);
            var when = day.ToString("dd.MM.yyyy", De);
            if (cooler >= 2)
                return string.Format(De, "Reinigung am {0}: bei gleicher Leistung {1:N0} °C kühler (vorher {2:N0} °C, danach {3:N0} °C).", when, cooler, oldT, newT);
            return string.Format(De, "Reinigung am {0}: kaum Unterschied (vorher {1:N0} °C, danach {2:N0} °C). Wird es trotzdem wärmer, kann die Wärmeleitpaste eingetrocknet sein.", when, oldT, newT);
        }

        // für "Was ist los?": der schlechtere Zustand von Grafikkarte und Prozessor
        public static (string Text, string Tone) CoolingState(IEnumerable<Messpunkt> points, DateTime? cleaned = null)
        {
            var list = points.ToList();
            var trends = new[] { Trend(list, 'G', cleaned), Trend(list, 'C', cleaned) };
            if (trends.Any(t => t.Tone == "warn")) return ("lässt nach", "warn");
            if (trends.Any(t => t.Tone == "good")) return ("unverändert", "good");
            if (trends.Any(t => t.State == "neu gestartet")) return ("seit Reinigung neu", "");
            return ("sammelt noch", "");
        }

        // SSD: Abnutzung über die Zeit (Tag "yyyy-MM-dd", Abnutzung in %), wie Get-SsdLife
        public static Verschleissbefund Ssd(string name, IEnumerable<(string D, int W)> history)
        {
            var list = history.Where(h => h.D.Length == 10).OrderBy(h => h.D, StringComparer.Ordinal).ToList();
            var first = list[0];
            var last = list[list.Count - 1];
            var wear = last.W;
            var days = (Day(last.D) - Day(first.D)).TotalDays;
            var rise = last.W - first.W;
            if (rise >= 1 && days >= 30)
            {
                var perYear = rise / days * 365;
                var years = (100 - wear) / perYear;
                return new Verschleissbefund
                {
                    Title = name,
                    Text = string.Format(De, "Abnutzung {0} %, seit dem {1} um {2} Punkte gestiegen: rund {3:N1} Punkte im Jahr. Bei diesem Tempo hält sie noch etwa {4:N0} Jahre.", wear, Day(first.D).ToString("dd.MM.yyyy", De), rise, perYear, years),
                    Tone = wear >= 90 || years < 1 ? "bad" : wear >= 70 || years < 3 ? "warn" : "good",
                    State = years >= 10 ? "über 10 Jahre" : string.Format(De, "~{0:N0} Jahre", years),
                };
            }
            return new Verschleissbefund
            {
                Title = name,
                Text = "Abnutzung " + wear + " %. " + (days < 30 ? "Für eine Schätzung braucht es einen Monat Verlauf (bisher " + (int)Math.Round(days, MidpointRounding.ToEven) + " Tage)." : "Seit Beginn der Aufzeichnung unverändert: Für eine Schätzung ist sie noch zu jung oder wird wenig beschrieben."),
                Tone = wear >= 90 ? "bad" : wear >= 70 ? "warn" : "good",
                State = wear + " %",
            };
        }
    }
}
