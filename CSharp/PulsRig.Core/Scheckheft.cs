using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace PulsRig.Core
{
    // Digitales PC-Scheckheft: ein Eintrag je Ereignis über die ganze Lebenszeit des PCs. Die Verläufe der Ergebnisdatei
    // (Benchmarks, Messpunkte, Probezeit, Tagesbilder) werden nach einiger Zeit gekürzt – das Scheckheft übernimmt daraus
    // je Ereignis einmal einen Satz (Key) und behält ihn. Dazu kommen Einträge von Hand: Reinigung, Aufrüstung, Reparatur,
    // Notiz. Für den Verkauf gibt es einen Bericht, den der Käufer mit dem Gebrauchtkauf-Check gegen den PC hält.
    public sealed class HeftEintrag
    {
        // "yyyy-MM-dd HH:mm"
        public string D { get; set; } = "";
        // hardware, driver, windows, test, temp, cleaning, upgrade, repair, note
        public string Kind { get; set; } = "";
        public string Title { get; set; } = "";
        public string Sub { get; set; } = "";
        public string Key { get; set; } = "";
        public bool Manual { get; set; }
    }

    // ein Bauteil des PCs: "Prozessor", "Grafikkarte", "Arbeitsspeicher", "Laufwerk"; Size in GB (0 = ohne Größe)
    public sealed class HeftTeil
    {
        public string Kind { get; set; } = "";
        public string Name { get; set; } = "";
        public double Size { get; set; }
        public string Line => Kind + "|" + Name + "|" + Size.ToString("0", CultureInfo.InvariantCulture);

        public static HeftTeil? Parse(string line)
        {
            var p = (line ?? "").Split('|');
            if (p.Length < 2 || p[0].Length == 0) return null;
            double.TryParse(p.Length > 2 ? p[2] : "0", NumberStyles.Float, CultureInfo.InvariantCulture, out var size);
            return new HeftTeil { Kind = p[0], Name = p[1], Size = size };
        }
    }

    public static class Scheckheft
    {
        static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

        public static readonly string[] ManualKinds = { "cleaning", "upgrade", "repair", "note" };

        public static string KindName(string kind) => kind switch
        {
            "hardware" => "Bauteile", "driver" => "Treiber", "windows" => "Windows", "test" => "Test", "temp" => "Temperaturen",
            "cleaning" => "Reinigung", "upgrade" => "Aufrüstung", "repair" => "Reparatur", "note" => "Notiz", _ => kind,
        };

        public static string Stamp(DateTime when) => when.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);

        public static DateTime? ParseStamp(string d)
        {
            foreach (var f in new[] { "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd.MM.yyyy HH:mm", "dd.MM.yyyy" })
                if (DateTime.TryParseExact(d ?? "", f, CultureInfo.InvariantCulture, DateTimeStyles.None, out var t)) return t;
            return null;
        }

        public static string Day(string d) => ParseStamp(d) is { } t ? t.ToString("dd.MM.yyyy", De) : d;

        static string Gb(double gb) => gb >= 1000 ? (gb / 1000).ToString("0.#", De) + " TB" : gb.ToString("0", De) + " GB";

        static string PartText(HeftTeil p) => p.Kind == "Arbeitsspeicher" ? Gb(p.Size) : p.Size > 0 ? p.Name + " (" + Gb(p.Size) + ")" : p.Name;

        // Bauteile von früher gegen heute: getauscht, dazu, entfernt. Laufwerke erkennt man an Name und Größe wieder.
        public static List<HeftEintrag> PartChanges(IList<HeftTeil>? before, IList<HeftTeil> now, DateTime when)
        {
            var list = new List<HeftEintrag>();
            if (before == null || before.Count == 0 || now.Count == 0) return list;
            var stamp = Stamp(when);
            foreach (var kind in new[] { "Prozessor", "Grafikkarte", "Arbeitsspeicher" })
            {
                var a = before.FirstOrDefault(p => p.Kind == kind);
                var b = now.FirstOrDefault(p => p.Kind == kind);
                if (a == null || b == null) continue;
                var same = kind == "Arbeitsspeicher" ? Math.Abs(a.Size - b.Size) < 0.5 : string.Equals(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
                if (same) continue;
                var title = kind == "Arbeitsspeicher" ? "Arbeitsspeicher " + (b.Size > a.Size ? "erweitert" : "verkleinert") : kind + " getauscht";
                list.Add(new HeftEintrag { D = stamp, Kind = "hardware", Title = title, Sub = PartText(a) + " → " + PartText(b), Key = "hw|" + kind + "|" + b.Line });
            }
            var oldDisks = before.Where(p => p.Kind == "Laufwerk").Select(p => p.Line).ToList();
            var newDisks = now.Where(p => p.Kind == "Laufwerk").Select(p => p.Line).ToList();
            foreach (var line in newDisks.Except(oldDisks))
            {
                var p = HeftTeil.Parse(line)!;
                list.Add(new HeftEintrag { D = stamp, Kind = "hardware", Title = "Neues Laufwerk", Sub = PartText(p), Key = "hw|add|" + line + "|" + stamp });
            }
            foreach (var line in oldDisks.Except(newDisks))
            {
                var p = HeftTeil.Parse(line)!;
                list.Add(new HeftEintrag { D = stamp, Kind = "hardware", Title = "Laufwerk entfernt", Sub = PartText(p), Key = "hw|del|" + line + "|" + stamp });
            }
            return list;
        }

        // der erste Eintrag: womit das Scheckheft beginnt
        public static HeftEintrag Start(IList<HeftTeil> parts, DateTime when) => new HeftEintrag
        {
            D = Stamp(when), Kind = "hardware", Title = "Scheckheft begonnen",
            Sub = string.Join(" · ", parts.Where(p => p.Kind != "Laufwerk").Select(PartText).Concat(new[] { parts.Count(p => p.Kind == "Laufwerk") + " Laufwerk(e)" })),
            Key = "start",
        };

        public static HeftEintrag Driver(ProbeEintrag e)
        {
            var when = e.Since > 0 ? new DateTime(e.Since) : DateTime.Now;
            var by = e.Source == "PulsRig" ? "über PulsRig" : "von Windows";
            var verdict = e.Verdict == "auffällig" ? " · in der Probezeit auffällig" : e.Verdict == "bestanden" ? " · Probezeit bestanden" : "";
            return new HeftEintrag
            {
                D = Stamp(when), Kind = "driver", Title = "Treiber " + e.Name, Sub = (e.Old.Length > 0 ? e.Old + " → " : "") + e.New + " (" + by + ")" + verdict,
                Key = "drv|" + e.Id + "|" + e.New,
            };
        }

        public static HeftEintrag Windows(string day, string oldVersion, string newVersion) => new HeftEintrag
        {
            D = day.Length == 10 ? day + " 00:00" : day, Kind = "windows", Title = "Windows aktualisiert", Sub = oldVersion + " → " + newVersion, Key = "win|" + newVersion,
        };

        // Benchmark-Lauf aus History.Benchmarks (D "dd.MM.yyyy HH:mm", S/M Prozessor, G Grafikkarte, R/W Laufwerk)
        public static HeftEintrag? Benchmark(string d, double? single, double? multi, double? gpu, double? read)
        {
            var when = ParseStamp(d);
            if (when == null) return null;
            var parts = new List<string>();
            if (single is { } s && multi is { } m) parts.Add("Prozessor " + s.ToString("N0", De) + " / " + m.ToString("N0", De));
            if (gpu is { } g && g > 0) parts.Add("Grafikkarte " + g.ToString("N0", De));
            if (read is { } r && r > 0) parts.Add("Laufwerk " + r.ToString("N0", De) + " MB/s");
            return new HeftEintrag { D = Stamp(when.Value), Kind = "test", Title = "Benchmark", Sub = string.Join(" · ", parts), Key = "bench|" + d };
        }

        public static HeftEintrag Stress(Messpunkt p) => new HeftEintrag
        {
            D = p.D.Length == 10 ? p.D + " 00:00" : p.D, Kind = "test", Title = "Stabilitätstest bestanden",
            Sub = string.Join(" · ", new[] { p.Min is { } m ? m.ToString("N0", De) + " Minuten" : "", p.CT is { } c ? "Prozessor höchstens " + c.ToString("N0", De) + " °C" : "", p.GT is { } g ? "Grafikkarte höchstens " + g.ToString("N0", De) + " °C" : "" }.Where(x => x.Length > 0)),
            Key = "stress|" + p.D + "|" + p.Name,
        };

        // bestandene Stabilitätstests. Abgebrochene oder durchgefallene (Fail) bleiben Messpunkte für die Kühlung,
        // bekommen aber keinen Eintrag: das Scheckheft soll beim Verkauf nichts als bestanden ausweisen, was es nicht war
        public static List<HeftEintrag> Stresses(IEnumerable<Messpunkt> points) =>
            points.Where(p => p.Src == "Stresstest" && !p.Fail).Select(Stress).ToList();

        // höchste Temperaturen beim Spielen je Monat; der Eintrag des laufenden Monats wird jeweils ersetzt
        public static List<HeftEintrag> Temperatures(IEnumerable<Messpunkt> points)
        {
            var list = new List<HeftEintrag>();
            foreach (var month in points.Where(p => p.Src != "Stresstest" && p.D.Length >= 7).GroupBy(p => p.D.Substring(0, 7)).OrderBy(g => g.Key, StringComparer.Ordinal))
            {
                var gpu = month.Where(p => p.GT != null).Select(p => p.GT!.Value).DefaultIfEmpty(double.NaN).Max();
                var cpu = month.Where(p => p.CT != null).Select(p => p.CT!.Value).DefaultIfEmpty(double.NaN).Max();
                var parts = new List<string>();
                if (!double.IsNaN(cpu)) parts.Add("Prozessor höchstens " + cpu.ToString("N0", De) + " °C");
                if (!double.IsNaN(gpu)) parts.Add("Grafikkarte höchstens " + gpu.ToString("N0", De) + " °C");
                if (parts.Count == 0) continue;
                var last = month.Max(p => p.D)!;
                var name = DateTime.TryParseExact(month.Key, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t) ? t.ToString("MMMM yyyy", De) : month.Key;
                list.Add(new HeftEintrag
                {
                    D = (last.Length == 10 ? last : last.Substring(0, Math.Min(10, last.Length))) + " 23:59", Kind = "temp",
                    Title = "Temperaturen im " + name, Sub = month.Count() + (month.Count() == 1 ? " Sitzung · " : " Sitzungen · ") + string.Join(" · ", parts), Key = "temp|" + month.Key,
                });
            }
            return list;
        }

        // neue Einträge übernehmen: je Key einmal, ein erneut gefundener ersetzt den alten (Monatswerte, Urteil der
        // Probezeit); was nicht mehr gefunden wird, bleibt. Einträge von Hand bleiben immer, wie sie sind.
        public static List<HeftEintrag> Merge(IEnumerable<HeftEintrag> saved, IEnumerable<HeftEintrag> found)
        {
            var map = new Dictionary<string, HeftEintrag>();
            var manual = new List<HeftEintrag>();
            foreach (var e in saved)
                if (e.Manual || e.Key.Length == 0) manual.Add(e);
                else map[e.Key] = e;
            foreach (var e in found)
                if (e.Key.Length > 0) map[e.Key] = e;
            return map.Values.Concat(manual).OrderByDescending(e => e.D, StringComparer.Ordinal).ToList();
        }

        // Hinweis zum Entstauben: seit über einem Jahr keine Reinigung eingetragen, obwohl das Heft so alt ist
        public static string? CleaningHint(IList<HeftEintrag> entries, DateTime now)
        {
            var first = entries.Select(e => ParseStamp(e.D)).Where(t => t != null).Select(t => t!.Value).DefaultIfEmpty(now).Min();
            var cleaned = entries.Where(e => e.Kind == "cleaning").Select(e => ParseStamp(e.D)).Where(t => t != null).Select(t => t!.Value).DefaultIfEmpty(DateTime.MinValue).Max();
            var since = cleaned > DateTime.MinValue ? cleaned : first;
            if ((now - since).TotalDays < 365) return null;
            return cleaned > DateTime.MinValue ? "Die letzte Reinigung ist über ein Jahr her – Zeit zum Entstauben?" : "Noch keine Reinigung eingetragen. Nach dem Entstauben hier festhalten, das zählt beim Verkauf.";
        }

        public static string Summary(IList<HeftEintrag> entries)
        {
            if (entries.Count == 0) return "Noch keine Einträge";
            var first = entries.Min(e => e.D)!;
            var tests = entries.Count(e => e.Kind == "test");
            var cleanings = entries.Count(e => e.Kind == "cleaning");
            return "Geführt seit " + Day(first) + " · " + entries.Count + " Einträge · " + tests + (tests == 1 ? " Test · " : " Tests · ") + cleanings + (cleanings == 1 ? " Reinigung" : " Reinigungen");
        }

        static string E(string s) => System.Net.WebUtility.HtmlEncode(s ?? "");

        static string J(string s)
        {
            var b = new StringBuilder("\"");
            foreach (var c in s ?? "")
                if (c == '"' || c == '\\') b.Append('\\').Append(c);
                else if (c < ' ' || c == '<' || c == '>' || c == '&') b.Append("\\u").Append(((int)c).ToString("x4"));
                else b.Append(c);
            return b.Append('"').ToString();
        }

        // Bericht zum Mitgeben: bewusst ohne Benutzer-, PC-Namen und Seriennummern. Die Bauteile stehen zusätzlich
        // maschinenlesbar im Block "pulsrig-scheckheft", den der Gebrauchtkauf-Check gegen den PC hält.
        public static string Html(IList<HeftEintrag> entries, IList<HeftTeil> parts, DateTime when)
        {
            var b = new StringBuilder();
            b.Append("<!doctype html><html lang=\"de\"><meta charset=\"utf-8\"><title>PulsRig PC-Scheckheft</title>");
            b.Append("<style>body{font:15px Segoe UI,sans-serif;max-width:820px;margin:32px auto;padding:0 16px;color:#222}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ccc;padding:8px;text-align:left;vertical-align:top}td.k{color:#666;white-space:nowrap}</style>");
            b.Append("<h1>Digitales PC-Scheckheft</h1><p>Erstellt mit PulsRig am ").Append(E(when.ToString("dd.MM.yyyy HH:mm", De))).Append(" Uhr · ").Append(E(Summary(entries))).Append("</p>");
            b.Append("<h2>Bauteile heute</h2><table>");
            foreach (var p in parts) b.Append("<tr><td class=\"k\">").Append(E(p.Kind)).Append("</td><td>").Append(E(PartText(p))).Append("</td></tr>");
            b.Append("</table>");
            foreach (var year in entries.GroupBy(e => e.D.Length >= 4 ? e.D.Substring(0, 4) : "").OrderByDescending(g => g.Key, StringComparer.Ordinal))
            {
                b.Append("<h2>").Append(E(year.Key)).Append("</h2><table><tr><th>Datum</th><th>Art</th><th>Eintrag</th></tr>");
                foreach (var e in year)
                    b.Append("<tr><td class=\"k\">").Append(E(Day(e.D))).Append("</td><td class=\"k\">").Append(E(KindName(e.Kind))).Append(e.Manual ? " (von Hand)" : "")
                        .Append("</td><td><b>").Append(E(e.Title)).Append("</b>").Append(e.Sub.Length > 0 ? "<br>" + E(e.Sub) : "").Append("</td></tr>");
                b.Append("</table>");
            }
            b.Append("<p style=\"color:#666\">Automatische Einträge schreibt PulsRig selbst mit; Einträge „von Hand“ stammen vom Besitzer. Mit dem Gebrauchtkauf-Check von PulsRig lässt sich dieser Bericht gegen den PC halten.</p>");
            b.Append("<script type=\"application/json\" id=\"pulsrig-scheckheft\">{\"Version\":1,\"D\":").Append(J(Stamp(when))).Append(",\"Parts\":[")
                .Append(string.Join(",", parts.Select(p => J(p.Line)))).Append("]}</script>");
            return b.Append("</html>").ToString();
        }

        // die Bauteile aus einem Bericht lesen (Block "pulsrig-scheckheft"); null, wenn es kein Scheckheft ist
        public static List<HeftTeil>? PartsFromHtml(string html)
        {
            var start = (html ?? "").IndexOf("id=\"pulsrig-scheckheft\">", StringComparison.Ordinal);
            if (start < 0) return null;
            var end = html!.IndexOf("</script>", start, StringComparison.Ordinal);
            if (end < 0) return null;
            var json = html.Substring(start, end - start);
            var at = json.IndexOf("\"Parts\":[", StringComparison.Ordinal);
            if (at < 0) return null;
            var list = new List<HeftTeil>();
            var i = at + 9;
            while (i < json.Length && json[i] != ']')
            {
                if (json[i] != '"') { i++; continue; }
                var s = new StringBuilder();
                for (i++; i < json.Length && json[i] != '"'; i++)
                {
                    if (json[i] == '\\' && i + 1 < json.Length)
                    {
                        i++;
                        if (json[i] == 'u' && i + 4 < json.Length) { s.Append((char)Convert.ToInt32(json.Substring(i + 1, 4), 16)); i += 4; }
                        else s.Append(json[i]);
                    }
                    else s.Append(json[i]);
                }
                i++;
                if (HeftTeil.Parse(s.ToString()) is { } p) list.Add(p);
            }
            return list;
        }

        // Bericht des Verkäufers gegen den PC: je Bauteil stimmt / weicht ab
        public static List<Abgleich> Compare(IList<HeftTeil> stated, IList<HeftTeil> found)
        {
            var list = new List<Abgleich>();
            foreach (var kind in new[] { "Prozessor", "Grafikkarte", "Arbeitsspeicher" })
            {
                var a = stated.FirstOrDefault(p => p.Kind == kind);
                var b = found.FirstOrDefault(p => p.Kind == kind);
                if (a == null) continue;
                if (b == null) { list.Add(new Abgleich(kind, PartText(a), "nicht gefunden", "open")); continue; }
                var same = kind == "Arbeitsspeicher" ? Math.Abs(a.Size - b.Size) < 0.5 : string.Equals(a.Name.Trim(), b.Name.Trim(), StringComparison.OrdinalIgnoreCase);
                list.Add(new Abgleich(kind, PartText(a), PartText(b), same ? "good" : "bad"));
            }
            var oldDisks = stated.Where(p => p.Kind == "Laufwerk").ToList();
            var newDisks = found.Where(p => p.Kind == "Laufwerk").ToList();
            if (oldDisks.Count > 0)
            {
                var missing = oldDisks.Where(a => !newDisks.Any(b => string.Equals(a.Name, b.Name, StringComparison.OrdinalIgnoreCase) && Math.Abs(a.Size - b.Size) <= Math.Max(2, a.Size * 0.02))).ToList();
                list.Add(new Abgleich("Laufwerke", string.Join(", ", oldDisks.Select(PartText)), missing.Count == 0 ? "alle vorhanden" : "fehlt: " + string.Join(", ", missing.Select(PartText)), missing.Count == 0 ? "good" : "bad"));
            }
            return list;
        }
    }
}
