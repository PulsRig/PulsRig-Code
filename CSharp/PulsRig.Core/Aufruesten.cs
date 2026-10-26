using System;
using System.Collections.Generic;
using System.Linq;

namespace PulsRig.Core
{
    // Aufrüst-Berater wie PulsRig-Aufruesten.ps1: eine Minute Messwerte im Spiel, daraus ein Satz, welches Bauteil bremst.
    // Prozessor: der am stärksten belastete Kern (CpuCoreMax) – die Gesamtlast täuscht. Grafikkarte nur bei NVIDIA sicher.
    // Die Schwellen sind bewusst grob, die Messung dauert nur eine Minute.
    public sealed class Aufruestwert
    {
        public double Mean { get; set; }
        public double Busy { get; set; }   // Anteil der Sekunden am Anschlag
    }

    public sealed class Aufruestmessung
    {
        public int Count { get; set; }
        public Aufruestwert? Core { get; set; }
        public Aufruestwert? Cpu { get; set; }
        public Aufruestwert? Gpu { get; set; }
        public Aufruestwert? Ram { get; set; }
        public double? Vram { get; set; }
    }

    public static class Aufruesten
    {
        public const int Lead = 10;      // s Vorlauf, um ins Spiel zu wechseln
        public const int Seconds = 60;   // s Messdauer

        public static Aufruestwert? Stat(IEnumerable<double?> values, double limit)
        {
            var list = values.Where(v => v.HasValue).Select(v => v!.Value).ToList();
            if (list.Count == 0) return null;
            return new Aufruestwert { Mean = list.Average(), Busy = list.Count(v => v >= limit) / (double)list.Count };
        }

        // Messwerte je Sekunde: Schlüssel wie die Messschleife (CpuCoreMax, CpuLoad, GpuLoad, Ram, GpuMemory, GpuMemoryTotal)
        public static Aufruestmessung Measure(IReadOnlyList<IDictionary<string, double?>> samples)
        {
            double? Get(IDictionary<string, double?> s, string key) => s.TryGetValue(key, out var v) ? v : null;
            var r = new Aufruestmessung
            {
                Count = samples.Count,
                Core = Stat(samples.Select(s => Get(s, "CpuCoreMax")), 90),
                Cpu = Stat(samples.Select(s => Get(s, "CpuLoad")), 90),
                Gpu = Stat(samples.Select(s => Get(s, "GpuLoad")), 95),
                Ram = Stat(samples.Select(s => Get(s, "Ram")), 90),
            };
            var vram = samples.Where(s => Get(s, "GpuMemoryTotal") > 0 && Get(s, "GpuMemory").HasValue)
                .Select(s => 100.0 * Get(s, "GpuMemory")!.Value / Get(s, "GpuMemoryTotal")!.Value).ToList();
            if (vram.Count > 0) r.Vram = vram.Average();
            return r;
        }

        public static (string Title, string Text) Verdict(Aufruestmessung m)
        {
            if (m.Count == 0) return ("Keine Messwerte", "Die Messschleife hat in dieser Minute nichts geliefert. Bitte erneut messen.");
            var tips = new List<string>();
            if (m.Ram != null && m.Ram.Mean >= 90) tips.Add("Der Arbeitsspeicher war fast voll: Windows lagert aus, das ruckelt. Mehr RAM hilft.");
            if (m.Vram >= 95) tips.Add("Der Grafikspeicher war voll: Texturdetails eine Stufe senken oder eine Karte mit mehr Speicher.");
            string title, text;
            if (m.Gpu != null && m.Gpu.Mean >= 90)
            {
                title = "Die Grafikkarte bremst";
                text = m.Core != null && m.Core.Mean >= 90
                    ? "Sie war voll ausgelastet, aber auch ein Prozessorkern stand am Anschlag: beide liegen gleichauf, eine neue Grafikkarte allein bringt weniger als gedacht."
                    : "Sie war fast die ganze Zeit voll ausgelastet. Eine stärkere Grafikkarte bringt am meisten; der Prozessor hätte noch Luft.";
            }
            else if (m.Core != null && m.Core.Mean >= 85 && (m.Gpu == null || m.Gpu.Mean < 80))
            {
                title = "Der Prozessor bremst";
                text = "Ein Kern war fast ständig am Anschlag, obwohl der Prozessor insgesamt weniger zeigt. Spiele hängen an ihrem Hauptkern: ein Prozessor mit mehr Leistung je Kern hilft, mehr Kerne allein nicht.";
                if (m.Gpu == null) text += " Die Grafikkarte konnte PulsRig nicht messen.";
            }
            else if (m.Gpu == null)
            {
                title = "Der Prozessor bremst eher nicht";
                text = "Kein Kern stand dauernd am Anschlag. Die Grafikkarte kann PulsRig ohne NVIDIA nicht messen – dann ist sie der wahrscheinliche Engpass.";
            }
            else
            {
                title = "Nichts stand am Anschlag";
                text = "Weder Grafikkarte noch Prozessor waren voll ausgelastet. Meist begrenzt ein FPS-Limit oder V-Sync – dann ist der PC schnell genug. Oder das Spiel lief nicht im Vordergrund.";
            }
            if (tips.Count > 0) text += " " + string.Join(" ", tips);
            return (title, text);
        }

        // Laufwerk des Spiels: kind ist "HDD", "SSD", "NVMe" oder leer
        public static string DriveText(string letter, string kind) => kind switch
        {
            "HDD" => "Liegt auf " + letter + ": – einer Festplatte. Auf einer SSD lädt es viel schneller und ruckelt beim Nachladen weniger.",
            "NVMe" => "Liegt auf " + letter + ": – einer NVMe-SSD. Da gibt es nichts zu verbessern.",
            "SSD" => "Liegt auf " + letter + ": – einer SSD. Das passt.",
            _ => "Liegt auf " + letter + ":; die Bauart des Laufwerks meldet Windows nicht.",
        };

        // Zeile Arbeitsspeicher wie Get-UpgradeMemory: Steckplätze, Ausbau und Hinweis
        public static (string Text, string Chip, bool Free) Memory(int modules, int slots, double maxBytes, bool laptop)
        {
            if (slots <= 0 || slots < modules) return (modules + " Riegel eingebaut; wie viele Steckplätze es gibt, meldet das BIOS nicht", "", false);
            var free = slots - modules;
            var parts = new List<string> { modules + " von " + slots + " Steckplätzen belegt" };
            if (maxBytes > 0) parts.Add("höchstens " + Math.Round(maxBytes / (1L << 30)).ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("de-DE")) + " GB laut BIOS");
            if (laptop) parts.Add("Laptop-Riegel (SO-DIMM); manche sind fest verlötet");
            else if (free > 0 && modules == 1) parts.Add("ein zweiter gleicher Riegel bringt Dual-Channel");
            else if (free > 0) parts.Add("zum Aufrüsten möglichst gleiche Riegel nehmen");
            var chip = free == 1 ? "1 Platz frei" : free > 1 ? free + " Plätze frei" : "alle belegt";
            return (string.Join(" · ", parts), chip, free > 0);
        }
    }
}
