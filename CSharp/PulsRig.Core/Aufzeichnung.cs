// PulsRig.Core - Spielsitzungen wie Read-Recording, Get-ThrottleShare und Get-RecordingSummary in
// PulsRig-Aufzeichnung.ps1. Der Helfer (PulsRig-Aufzeichnung.cs) schreibt je Sitzung eine Datei: Kopfzeile
// "Spiel=…;Beginn=yyyy-MM-ddTHH:mm:ss", dann die Spaltennamen, dann alle 5 Sekunden eine Zeile (Punkt als Komma).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public sealed class Spielsitzung
    {
        public string Game = "";
        public DateTime Begin;
        public Dictionary<string, List<double>> Data = new Dictionary<string, List<double>>();
        public double Seconds => Column("Sekunde") is { Count: > 0 } s ? s[s.Count - 1] : 0;
        public List<double>? Column(string name) => Data.TryGetValue(name, out var list) ? list : null;
    }

    public sealed class Sitzungsbild
    {
        public List<string> Lines = new List<string>();
        public string Tone = "good";
        public double? CpuAvg, CpuMax, GpuAvg, GpuMax;
    }

    public static class Aufzeichnung
    {
        public static Spielsitzung Read(IList<string> lines)
        {
            var s = new Spielsitzung { Begin = DateTime.Now };
            if (lines.Count < 2) return s;
            foreach (string part in lines[0].Split(';'))
            {
                var m = Regex.Match(part, @"^(\w+)=(.*)$");
                if (!m.Success) continue;
                if (m.Groups[1].Value == "Spiel") s.Game = m.Groups[2].Value;
                if (m.Groups[1].Value == "Beginn" && DateTime.TryParseExact(m.Groups[2].Value, "yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime b)) s.Begin = b;
            }
            string[] names = lines[1].Split(';');
            foreach (string n in names) s.Data[n] = new List<double>();
            for (int i = 2; i < lines.Count; i++)
            {
                string[] cells = lines[i].Split(';');
                if (cells.Length != names.Length) continue;
                for (int c = 0; c < names.Length; c++)
                    s.Data[names[c]].Add(double.TryParse(cells[c], NumberStyles.Float, CultureInfo.InvariantCulture, out double v) ? v : double.NaN);
            }
            return s;
        }

        static (double Avg, double Max)? Stats(List<double>? list)
        {
            var values = list?.Where(v => !double.IsNaN(v)).ToList();
            return values == null || values.Count == 0 ? ((double, double)?)null : (values.Average(), values.Max());
        }

        // Anteil der Zeit unter Last, in der der Takt deutlich unter dem üblichen Takt unter Last derselben Sitzung lag
        public static double ThrottleShare(List<double>? clock, List<double>? load, double minLoad, double drop)
        {
            if (clock == null || load == null) return 0;
            var loaded = new List<double>();
            for (int i = 0; i < clock.Count && i < load.Count; i++) if (load[i] >= minLoad && clock[i] > 0) loaded.Add(clock[i]);
            if (loaded.Count < 6) return 0;
            var sorted = loaded.OrderBy(v => v).ToList();
            double median = sorted[sorted.Count / 2];
            return loaded.Count(v => v < median * drop) / (double)loaded.Count;
        }

        // wie Get-RecordingSummary: je Satz eine Zeile, dazu ein Ton
        public static Sitzungsbild Summary(Spielsitzung s)
        {
            var r = new Sitzungsbild();
            var de = CultureInfo.GetCultureInfo("de-DE");
            var cpu = Stats(s.Column("CpuTemp"));
            var gpu = Stats(s.Column("GpuTemp"));
            if (cpu != null) { r.CpuAvg = cpu.Value.Avg; r.CpuMax = cpu.Value.Max; }
            if (gpu != null) { r.GpuAvg = gpu.Value.Avg; r.GpuMax = gpu.Value.Max; }
            var parts = new List<string>();
            if (cpu != null) parts.Add(string.Format(de, "Prozessor im Schnitt {0:N0} °C, höchstens {1:N0} °C", cpu.Value.Avg, cpu.Value.Max));
            if (gpu != null) parts.Add(string.Format(de, "Grafikkarte im Schnitt {0:N0} °C, höchstens {1:N0} °C", gpu.Value.Avg, gpu.Value.Max));
            if (parts.Count > 0) r.Lines.Add(string.Join(" · ", parts) + ".");
            if (cpu == null) r.Lines.Add("Die Temperatur des Prozessors fehlt: Sensoren → Freischalten, oder Core Temp laufen lassen.");
            const double step = 5.0;
            if (cpu != null)
            {
                double hot = s.Column("CpuTemp")!.Count(v => v >= 88) * step / 60;
                if (hot >= 1) r.Lines.Add(string.Format(de, "{0:N0} Minuten lief der Prozessor an seiner Temperaturgrenze.", hot));
                if (cpu.Value.Max >= 95) r.Tone = "warn";
            }
            if (gpu != null)
            {
                double hot = s.Column("GpuTemp")!.Count(v => v >= 83) * step / 60;
                if (hot >= 1) { r.Lines.Add(string.Format(de, "{0:N0} Minuten war die Grafikkarte über 83 °C – dort beginnen viele zu drosseln.", hot)); r.Tone = "warn"; }
            }
            double cpuThrottle = ThrottleShare(s.Column("CpuTakt"), s.Column("CpuLast"), 50, 0.8);
            double gpuThrottle = ThrottleShare(s.Column("GpuTakt"), s.Column("GpuLast"), 90, 0.85);
            if (gpuThrottle >= 0.1) { r.Lines.Add(string.Format(de, "Die Grafikkarte hat unter Last in {0:N0} % der Zeit deutlich weniger Takt gehabt als sonst: Sie drosselt, meist wegen Hitze oder Strombegrenzung.", 100 * gpuThrottle)); r.Tone = "warn"; }
            if (cpuThrottle >= 0.1) { r.Lines.Add(string.Format(de, "Der Prozessor hat unter Last in {0:N0} % der Zeit deutlich weniger Takt gehabt als sonst.", 100 * cpuThrottle)); r.Tone = "warn"; }
            if (r.Tone == "good" && (cpu != null || gpu != null)) r.Lines.Add("Kein Drosseln zu sehen: Die Kühlung kommt mit dem Spiel zurecht.");
            return r;
        }

        public static string Duration(double seconds)
        {
            var span = TimeSpan.FromSeconds(seconds);
            return span.TotalHours >= 1 ? string.Format("{0}:{1:00} Std.", (int)Math.Floor(span.TotalHours), span.Minutes) : string.Format("{0} Min.", (int)Math.Round(span.TotalMinutes));
        }
    }
}
