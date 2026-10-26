// PulsRig.Core - Abstürze der letzten 30 Tage, abgelöst aus PulsRig-Abstuerze.ps1: Fehlercodes der Bluescreens in
// Worten, die Art der Ursache mit dem nächsten Schritt und die Befunde für Fenster, Karte und Prüfbericht.
// Das Ereignisprotokoll liest der Aufrufer (PowerShell oder die neue Oberfläche) und reicht die Vorfälle herein.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    // ein Vorfall aus dem Ereignisprotokoll; je nach Art sind nur einige Felder belegt
    public sealed class Vorfall
    {
        public DateTime When { get; set; }
        public uint Code { get; set; }
        public string Dump { get; set; } = "";
        public bool Button { get; set; }
        public bool Sleep { get; set; }
        public string Driver { get; set; } = "";
        public string App { get; set; } = "";
        public string Module { get; set; } = "";
        public string Text => When.ToString("dd.MM. HH:mm", CultureInfo.InvariantCulture);
    }

    public sealed class AbsturzDaten
    {
        public List<Vorfall> Blue { get; set; } = new List<Vorfall>();
        public List<Vorfall> Off { get; set; } = new List<Vorfall>();
        public List<Vorfall> Tdr { get; set; } = new List<Vorfall>();
        public List<Vorfall> Apps { get; set; } = new List<Vorfall>();
        public int Whea { get; set; }
        public string LastWhea { get; set; } = "";
        public string GpuVersion { get; set; } = "";
        public string GpuDate { get; set; } = "";
        public bool Log { get; set; } = true;
        public DateTime Time { get; set; } = DateTime.Now;
    }

    public sealed class BugCheck
    {
        public string Name { get; set; } = "";
        public string Kind { get; set; } = "";
        public string Hex { get; set; } = "";
    }

    public sealed class AbsturzArt
    {
        public string Text { get; set; } = "";
        public string State { get; set; } = "";
        public string Action { get; set; } = "";
        public string Do { get; set; } = "";
    }

    // eine Zeile im Fenster, im Prüfbericht und bei "Was ist los?"
    public sealed class Befund
    {
        public string Title { get; set; } = "";
        public string Sub { get; set; } = "";
        public string Short { get; set; } = "";
        public string Tone { get; set; } = "";
        public string State { get; set; } = "";
        public string Action { get; set; } = "";
        public string Do { get; set; } = "";
        public bool Graphics { get; set; }
        public bool Whea { get; set; }
        public bool Hint { get; set; }
    }

    public sealed class AbsturzKarte
    {
        public string Text { get; set; } = "";
        public string Tone { get; set; } = "";
        public string Detail { get; set; } = "";
        // vor wie vielen Tagen etwas war (0 = heute), für die 30 Kästchen
        public List<int> Days { get; set; } = new List<int>();
    }

    public static class Abstuerze
    {
        static readonly Dictionary<uint, string[]> Checks = new Dictionary<uint, string[]>
        {
            [0x0A] = new[] { "Ein Treiber griff auf falschen Speicher zu", "driver" },
            [0xD1] = new[] { "Ein Treiber griff auf falschen Speicher zu", "driver" },
            [0x1E] = new[] { "Ein Treiber hat einen Fehler nicht abgefangen", "driver" },
            [0x7E] = new[] { "Ein Treiber hat einen Fehler nicht abgefangen", "driver" },
            [0x3B] = new[] { "Fehler in einem Systemaufruf", "driver" },
            [0xC2] = new[] { "Ein Treiber hat Speicher falsch angefordert", "driver" },
            [0x19] = new[] { "Speicherverwaltung durcheinander", "driver" },
            [0xFC] = new[] { "Ein Treiber wollte geschützten Speicher ausführen", "driver" },
            [0x139] = new[] { "Sicherheitsprüfung im Windows-Kern", "driver" },
            [0x133] = new[] { "Ein Treiber hat das System zu lange blockiert", "driver" },
            [0x9F] = new[] { "Ein Treiber hing beim Standby oder Aufwachen", "driver" },
            [0x1A] = new[] { "Fehler in der Speicherverwaltung", "memory" },
            [0x50] = new[] { "Zugriff auf Speicher, den es nicht gibt", "memory" },
            [0x116] = new[] { "Grafiktreiber reagierte nicht mehr", "graphics" },
            [0x117] = new[] { "Grafiktreiber reagierte nicht mehr", "graphics" },
            [0x119] = new[] { "Fehler im Grafiktreiber", "graphics" },
            [0x10E] = new[] { "Fehler im Grafikspeicher", "graphics" },
            [0x124] = new[] { "Die Hardware hat einen schweren Fehler gemeldet", "hardware" },
            [0x101] = new[] { "Ein Prozessorkern hat nicht mehr geantwortet", "hardware" },
            [0x7A] = new[] { "Daten vom Laufwerk ließen sich nicht lesen", "disk" },
            [0x24] = new[] { "Fehler im Dateisystem", "disk" },
            [0x154] = new[] { "Unerwarteter Fehler beim Laufwerkszugriff", "disk" },
            [0xEF] = new[] { "Ein wichtiger Windows-Prozess wurde beendet", "disk" },
        };

        static readonly Dictionary<string, AbsturzArt> Kinds = new Dictionary<string, AbsturzArt>
        {
            ["driver"] = new AbsturzArt { Text = "Meist ein Treiber. Treiber aktualisieren hilft oft.", State = "Treiber", Action = "Treiber suchen", Do = "scan" },
            ["graphics"] = new AbsturzArt { Text = "Grafiktreiber oder Grafikkarte. Eine neuere oder die vorige Treiberfassung hilft oft.", State = "Grafik", Action = "Treiber suchen", Do = "scan" },
            ["memory"] = new AbsturzArt { Text = "Oft der Arbeitsspeicher: ein zu scharfes XMP-Profil oder ein defekter Riegel.", State = "Speicher", Action = "Speicher prüfen", Do = "memory" },
            ["hardware"] = new AbsturzArt { Text = "Hardware: Übertaktung, Spannung, Hitze oder Netzteil.", State = "Hardware", Action = "Stabilitätstest", Do = "stress" },
            ["disk"] = new AbsturzArt { Text = "Laufwerk, Kabel oder Anschluss, manchmal beschädigte Windows-Dateien.", State = "Laufwerk", Action = "Laufwerke prüfen", Do = "drives" },
            ["unknown"] = new AbsturzArt { Text = "Seltener Fehlercode, meist steckt ein Treiber dahinter.", State = "Treiber", Action = "Treiber suchen", Do = "scan" },
        };

        public static BugCheck Check(uint code)
        {
            // 0x1000007E und ähnliche sind dieselben Fehler wie 0x7E, nur anders gemeldet
            var bas = (code & 0x10000000) != 0 ? code & 0x0FFFFFFF : code;
            var hex = "0x" + bas.ToString("X", CultureInfo.InvariantCulture);
            return Checks.TryGetValue(bas, out var known)
                ? new BugCheck { Name = known[0], Kind = known[1], Hex = hex }
                : new BugCheck { Name = "Bluescreen", Kind = "unknown", Hex = hex };
        }

        public static AbsturzArt Kind(string kind) => Kinds.TryGetValue(kind, out var k) ? k : Kinds["unknown"];

        // Fehlercode aus dem Ereignis: "0x0000007e" (die letzten 8 Stellen zählen) oder eine Zahl
        public static uint ParseCode(object? value)
        {
            var text = Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";
            ulong number = 0;
            var m = Regex.Match(text, "0x([0-9a-fA-F]+)");
            if (m.Success) { var hex = m.Groups[1].Value; number = Convert.ToUInt64(hex.Substring(Math.Max(0, hex.Length - 8)), 16); }
            else if (Regex.IsMatch(text, @"^\d+$")) ulong.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out number);
            return (uint)(number & 0xFFFFFFFF);
        }

        // Programmabstürze, die im Grafiktreiber passiert sind: Hinweis auf den Treiber, nicht auf das Spiel
        public static bool IsGraphicsModule(string module) =>
            Regex.IsMatch(module, @"^(nv\w*|ati\w*|amd\w*|ig\w*)\.dll$", RegexOptions.IgnoreCase) &&
            Regex.IsMatch(module, "umd|um\\d|d3d|ogl|vlk|dxx|cuda|igc|nvapi|wgf", RegexOptions.IgnoreCase);

        // Name des Grafiktreibers aus Display 4101: erstes Feld, sonst aus dem Text
        public static string TdrDriver(string first, string message)
        {
            if (Regex.IsMatch(first, @"^\w+$")) return first;
            var m = Regex.Match(message, @"\b(nvlddmkm|amdkmdag|atikmdag|igdkmd\w*)\b");
            return m.Success ? m.Groups[1].Value : first;
        }

        // Kernel-Power 41 mit Fehlercode war ein Bluescreen; meist steht er schon als Ereignis 1001 da
        public static bool HasNearBlue(IEnumerable<Vorfall> blue, DateTime when) =>
            blue.Any(b => Math.Abs((b.When - when).TotalMinutes) < 15);

        public static string Times(int count) => count + "-mal";

        static IEnumerable<Vorfall> All(AbsturzDaten d) => d.Blue.Concat(d.Off).Concat(d.Tdr).Concat(d.Apps);

        public static AbsturzKarte? Card(AbsturzDaten d, DateTime today)
        {
            int blue = d.Blue.Count, off = d.Off.Count, tdr = d.Tdr.Count + d.Apps.Count;
            var times = All(d).Select(x => x.When).OrderByDescending(x => x).ToList();
            var detail = times.Count > 0 ? "Zuletzt " + times[0].ToString("dd.MM. HH:mm", CultureInfo.InvariantCulture) + " Uhr" : "Keine in 30 Tagen";
            var days = times.Select(t => (int)Math.Floor((today.Date - t.Date).TotalDays)).Where(x => x >= 0 && x < 30).Distinct().OrderBy(x => x).ToList();
            if (blue > 0) return new AbsturzKarte { Text = blue == 1 ? "1 Bluescreen" : blue + " Bluescreens", Tone = "bad", Detail = detail, Days = days };
            if (off + tdr > 0) return new AbsturzKarte { Text = off + tdr == 1 ? "1 Vorfall" : off + tdr + " Vorfälle", Tone = "warn", Detail = detail, Days = days };
            if (!d.Log) return null;
            return new AbsturzKarte { Text = "in Ordnung", Tone = "good", Detail = detail, Days = days };
        }

        // backups: gibt es Treibersicherungen, aus denen sich eine ältere Fassung zurückholen lässt?
        public static List<Befund> Findings(AbsturzDaten d, bool backups)
        {
            var items = new List<Befund>();

            // Bluescreens, nach Fehlercode zusammengefasst (Reihenfolge wie im Protokoll: neueste zuerst)
            foreach (var group in d.Blue.OrderByDescending(x => x.When).GroupBy(x => Check(x.Code).Hex))
            {
                var first = group.First();
                var check = Check(first.Code);
                var kind = Kind(check.Kind);
                items.Add(new Befund
                {
                    Title = "Bluescreen: " + check.Name, Tone = "bad", State = kind.State, Action = kind.Action, Do = kind.Do,
                    Sub = Times(group.Count()) + ", zuletzt " + first.Text + " Uhr · Code " + check.Hex + " · " + kind.Text,
                    Short = Times(group.Count()) + ", zuletzt " + first.Text + " Uhr · " + kind.State,
                });
            }

            // Grafiktreiber: Aussetzer und Programmabstürze im Treiber
            if (d.Tdr.Count + d.Apps.Count > 0)
            {
                var last = d.Tdr.Concat(d.Apps).OrderByDescending(x => x.When).First();
                var parts = new List<string> { "zuletzt " + last.Text + " Uhr" };
                if (d.Apps.Count > 0)
                {
                    var names = d.Apps.GroupBy(x => x.App).OrderByDescending(g => g.Count()).Take(3).Select(g => g.Key + " " + g.Count() + "×");
                    parts.Add("Programme im Grafiktreiber abgestürzt: " + string.Join(", ", names));
                }
                if (d.GpuVersion.Length > 0) parts.Add("Treiber " + d.GpuVersion + (d.GpuDate.Length > 0 ? " vom " + d.GpuDate : ""));
                items.Add(new Befund
                {
                    Title = d.Tdr.Count > 0 ? "Grafiktreiber ist " + Times(d.Tdr.Count) + " ausgesetzt" : Times(d.Apps.Count) + " im Grafiktreiber abgestürzt",
                    Sub = string.Join(" · ", parts), Short = "zuletzt " + last.Text + " Uhr · Grafik", Tone = "warn", State = "Grafik", Action = "Treiber suchen", Do = "scan", Graphics = true,
                });
                if (backups)
                    items.Add(new Befund
                    {
                        Title = "Vorige Treiberfassung zurückholen", Sub = "Fingen die Aussetzer nach einem Treiber-Update an, hilft oft die vorige Fassung. PulsRig hat Sicherungen davon.",
                        Tone = "accent", Action = "Zurückholen", Do = "restore", Graphics = true, Hint = true,
                    });
            }

            // plötzliches Ausschalten ohne Bluescreen
            if (d.Off.Count > 0)
            {
                var off = d.Off.OrderByDescending(x => x.When).ToList();
                int button = off.Count(x => x.Button), sleep = off.Count(x => x.Sleep);
                var sub = Times(off.Count) + ", zuletzt " + off[0].Text + " Uhr";
                if (button > 0) sub += " · " + Times(button) + " am Ausschalter ausgemacht, der PC hing also vorher";
                if (sleep > 0) sub += " · " + Times(sleep) + " beim Standby";
                sub += " · Ursachen: Strom weg, Netzteil, Hitze oder ein eingefrorener PC. Passiert es beim Spielen, zeigt der Stabilitätstest, ob die Hardware durchhält.";
                items.Add(new Befund
                {
                    Title = "PC ist plötzlich ausgegangen", Sub = sub, Short = Times(off.Count) + ", zuletzt " + off[0].Text + " Uhr · Strom",
                    Tone = "warn", State = "Strom", Action = "Stabilitätstest", Do = "stress",
                });
            }

            if (d.Whea > 0)
                items.Add(new Befund
                {
                    Title = d.Whea == 1 ? "1 Hardwarefehler gemeldet" : d.Whea + " Hardwarefehler gemeldet", Whea = true,
                    Sub = "Zuletzt " + d.LastWhea + " Uhr · Prozessor, Speicher oder Mainboard haben Windows einen Fehler gemeldet. Oft hilft es, Übertaktung und XMP zurückzunehmen.",
                    Tone = "warn", State = "Hardware", Action = "Stabilitätstest", Do = "stress",
                });
            return items;
        }

        // Tage seit dem letzten Bluescreen oder Ausschalten (ohne Grafikaussetzer); null = keiner in 30 Tagen
        public static int? CalmDays(AbsturzDaten d, DateTime today)
        {
            var last = d.Blue.Concat(d.Off).Select(x => (DateTime?)x.When).OrderByDescending(x => x).FirstOrDefault();
            return last is { } l ? (int)Math.Floor((today.Date - l.Date).TotalDays) : (int?)null;
        }
    }
}
