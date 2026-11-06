using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    // Eine Zeile des Abgleichs: State good = stimmt, bad = weicht ab, open = nicht prüfbar
    public sealed class Abgleich
    {
        public Abgleich(string name, string stated, string found, string state)
        {
            Name = name; Stated = stated; Found = found; State = state;
        }
        public string Name { get; }
        public string Stated { get; }
        public string Found { get; }
        public string State { get; }
    }

    public sealed class KaufUrteil
    {
        public KaufUrteil(string title, string tone) { Title = title; Tone = tone; }
        public string Title { get; }
        public string Tone { get; }
    }

    // Gebrauchtkauf-Check: vergleicht die Anzeige mit dem PC. Das Urteil sagt nie "echt" oder "in Ordnung",
    // eine kurze Prüfung beim Verkäufer ist keine Garantie.
    public static class Gebrauchtkauf
    {
        public const string Limit = "Das ist keine Garantie: Die Prüfung sieht nur, was sich in wenigen Minuten messen lässt.";

        static readonly HashSet<string> Filler = new HashSet<string>(StringComparer.Ordinal)
            { "nvidia", "geforce", "amd", "radeon", "intel", "core", "ryzen", "processor", "prozessor", "cpu", "gpu", "graphics", "r", "tm" };

        // Zusätze, die ein anderes Modell bedeuten: fehlen sie in der Anzeige, ist es nicht dasselbe Bauteil
        static readonly HashSet<string> Suffixes = new HashSet<string>(StringComparer.Ordinal) { "ti", "super", "xt", "xtx", "x" };

        // "RTX3060 Ti" und "NVIDIA GeForce RTX 3060 Ti" ergeben dieselben Teile
        static List<string> Tokens(string name) =>
            Regex.Matches((name ?? "").ToLowerInvariant(), "[a-z]+|[0-9]+").Cast<Match>().Select(m => m.Value).Where(t => !Filler.Contains(t)).ToList();

        public static Abgleich Name(string label, string stated, string found)
        {
            stated = (stated ?? "").Trim();
            found = (found ?? "").Trim();
            if (stated.Length == 0 || found.Length == 0) return new Abgleich(label, stated, found, "open");
            var want = Tokens(stated);
            var have = Tokens(found);
            var same = want.Count > 0 && want.All(have.Contains) && !have.Any(t => Suffixes.Contains(t) && !want.Contains(t));
            return new Abgleich(label, stated, found, same ? "good" : "bad");
        }

        // "16 GB", "1 TB", "1,5 TB", "512"; ohne Zahl null
        public static double? ParseGb(string text)
        {
            var m = Regex.Match(text ?? "", @"^\s*(\d+(?:[.,]\d+)?)\s*(gb|tb|g|t)?\s*$", RegexOptions.IgnoreCase);
            if (!m.Success) return null;
            var value = double.Parse(m.Groups[1].Value.Replace(',', '.'), CultureInfo.InvariantCulture);
            return m.Groups[2].Value.StartsWith("t", StringComparison.OrdinalIgnoreCase) ? value * 1000 : value;
        }

        public const string More = "mehr als angegeben";

        // tolerance: Anteil, um den die gemessene Größe abweichen darf (Hersteller runden). Mehr als angegeben ist
        // warn statt good: Beim Gebrauchtkauf heißt auch das nachfragen (Teile getauscht, anderer PC?)
        public static Abgleich Size(string label, string stated, double foundGb, double tolerance)
        {
            var found = foundGb > 0 ? Math.Round(foundGb).ToString("N0", CultureInfo.GetCultureInfo("de-DE")) + " GB" : "";
            var want = ParseGb(stated);
            if (want == null || foundGb <= 0) return new Abgleich(label, (stated ?? "").Trim(), found, "open");
            var state = foundGb < want.Value * (1 - tolerance) ? "bad" : foundGb > want.Value * (1 + tolerance) ? "warn" : "good";
            return new Abgleich(label, stated.Trim(), found, state);
        }

        public static KaufUrteil Verdict(int mismatches, int bad, int warn, int open)
        {
            var problems = mismatches + bad;
            if (problems > 0) return new KaufUrteil((problems == 1 ? "1 Problem gefunden" : problems + " Probleme gefunden") + ": vor dem Kauf klären", "bad");
            if (warn > 0) return new KaufUrteil(warn == 1 ? "1 Auffälligkeit gefunden" : warn + " Auffälligkeiten gefunden", "warn");
            if (open > 0) return new KaufUrteil("Keine Auffälligkeiten gefunden, aber nicht alles prüfbar", "warn");
            return new KaufUrteil("Keine Auffälligkeiten gefunden", "good");
        }

        static string E(string text) => WebUtility.HtmlEncode(text ?? "");

        static string KindText(string kind)
        {
            switch (kind)
            {
                case "good": return "unauffällig";
                case "warn": return "auffällig";
                case "bad": return "Problem";
                default: return "nicht geprüft";
            }
        }

        // rows: Name, Text, Kind. Bewusst ohne Benutzer- und PC-Namen und ohne Seriennummern
        public static string Html(KaufUrteil verdict, DateTime when, IEnumerable<Abgleich> compare, IEnumerable<(string Name, string Text, string Kind)> rows)
        {
            var b = new StringBuilder();
            b.Append("<!doctype html><html lang=\"de\"><meta charset=\"utf-8\"><title>PulsRig Gebrauchtkauf-Check</title>");
            b.Append("<style>body{font:15px Segoe UI,sans-serif;max-width:760px;margin:32px auto;padding:0 16px;color:#222}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ccc;padding:8px;text-align:left;vertical-align:top}</style>");
            b.Append("<h1>Gebrauchtkauf-Check</h1><p>").Append(E(when.ToString("dd.MM.yyyy HH:mm"))).Append(" Uhr</p><h2>").Append(E(verdict.Title)).Append("</h2><p>").Append(E(Limit)).Append("</p>");
            b.Append("<h2>Anzeige und PC</h2><table><tr><th>Bauteil</th><th>Anzeige</th><th>Gefunden</th><th>Ergebnis</th></tr>");
            foreach (var c in compare)
                b.Append("<tr><td>").Append(E(c.Name)).Append("</td><td>").Append(E(c.Stated)).Append("</td><td>").Append(E(c.Found)).Append("</td><td>")
                    .Append(c.State == "good" ? "stimmt" : c.State == "bad" ? "weicht ab" : c.State == "warn" ? More : "nicht geprüft").Append("</td></tr>");
            b.Append("</table><h2>Zustand</h2><table><tr><th>Prüfung</th><th>Befund</th><th>Ergebnis</th></tr>");
            foreach (var r in rows)
                b.Append("<tr><td>").Append(E(r.Name)).Append("</td><td>").Append(E(r.Text)).Append("</td><td>").Append(E(KindText(r.Kind))).Append("</td></tr>");
            return b.Append("</table></html>").ToString();
        }
    }
}
