// PulsRig.Core - Stromverbrauch wie Get-PowerParts und Get-RecordingEnergy in PulsRig-Strom.ps1: Grafikkarte
// gemessen (nvidia-smi) oder pauschal, Prozessor gemessen (LibreHardwareMonitor) oder aus Auslastung × Nennleistung,
// der Rest pauschal, dazu der Verlust im Netzteil. Eine Schätzung - ein Messgerät an der Steckdose ist genauer.
using System;
using System.Collections.Generic;

namespace PulsRig.Core
{
    public sealed class Stromteile
    {
        public double Gpu, Cpu, Rest, Total, Load;
        public bool GpuMeasured, CpuMeasured;
    }

    public static class Strom
    {
        public const double Rest = 35.0;         // W für Mainboard, Arbeitsspeicher, Laufwerke, Lüfter
        public const double GpuGuess = 20.0;     // W für eine Grafikkarte ohne Messwert
        public const double CpuRated = 65.0;     // W Nennleistung, wenn der Prozessor nicht gemessen wird
        public const double Efficiency = 0.88;   // Wirkungsgrad des Netzteils

        public static Stromteile Parts(double? gpuPower, double? cpuPower, double? cpuLoad)
        {
            double load = cpuLoad ?? 10.0;
            var p = new Stromteile
            {
                Gpu = gpuPower ?? GpuGuess,
                Cpu = cpuPower ?? CpuRated * (0.15 + 0.85 * load / 100.0),
                Rest = Rest,
                GpuMeasured = gpuPower != null,
                CpuMeasured = cpuPower != null,
                Load = load,
            };
            p.Total = (p.Gpu + p.Cpu + p.Rest) / Efficiency;
            return p;
        }

        // Euro im Jahr aus mittleren Watt, Stunden am Tag und Preis je kWh
        public static double YearEuro(double watt, double hoursPerDay, double pricePerKwh) => watt / 1000.0 * hoursPerDay * pricePerKwh * 365;

        // Energie einer Aufzeichnung: jede Zeile mit dem Abstand zur vorigen gewichtet, Lücken über 60 s zählen nicht.
        // seconds, gpu, cpu, load: Spalten Sekunde, GpuWatt, CpuWatt, CpuLast (NaN = kein Wert). null ohne Zeilen.
        public static (double Kwh, double Average, bool GpuMeasured, bool CpuMeasured)? Recording(IList<double> seconds, IList<double>? gpu, IList<double>? cpu, IList<double>? load)
        {
            if (seconds.Count < 2) return null;
            double? At(IList<double>? list, int i) => list != null && i < list.Count && !double.IsNaN(list[i]) ? list[i] : (double?)null;
            double ws = 0, total = 0, gpuS = 0, cpuS = 0;
            for (int i = 1; i < seconds.Count; i++)
            {
                double step = seconds[i] - seconds[i - 1];
                if (double.IsNaN(step) || step <= 0 || step > 60) continue;
                var p = Parts(At(gpu, i), At(cpu, i), At(load, i));
                ws += p.Total * step;
                total += step;
                if (p.GpuMeasured) gpuS += step;
                if (p.CpuMeasured) cpuS += step;
            }
            if (total <= 0) return null;
            return (ws / 3600.0 / 1000.0, ws / total, gpuS >= total / 2, cpuS >= total / 2);
        }
    }
}

namespace PulsRig.Core
{
    using System.Linq;

    // Ping-Test wie die Abfrage Ping und Get-PingTone in PulsRig-Ping.ps1: Router (home) und drei DNS-Anbieter (net)
    public sealed class Pingziel
    {
        public string Name = "", Address = "", Kind = "";
        public int Sent, Lost;
        public List<double> Times = new List<double>();
        public double? Avg => Times.Count > 0 ? Times.Average() : (double?)null;
        public double? Min => Times.Count > 0 ? Times.Min() : (double?)null;
        public double? Max => Times.Count > 0 ? Times.Max() : (double?)null;
        // Schwankung: mittlerer Unterschied zwischen zwei aufeinanderfolgenden Antworten
        public double? Jitter => Times.Count == 0 ? (double?)null : Times.Count == 1 ? 0 : Enumerable.Range(1, Times.Count - 1).Average(i => Math.Abs(Times[i] - Times[i - 1]));
        public int LossPercent => (int)Math.Round(100.0 * Lost / Math.Max(1, Sent));
    }

    public static class Ping
    {
        public static string Tone(Pingziel t)
        {
            if (t.Avg is not double avg) return "bad";
            double loss = 100.0 * t.Lost / Math.Max(1, t.Sent), jitter = t.Jitter ?? 0;
            if (t.Kind == "home") return loss > 0 || avg > 20 || jitter > 10 ? "warn" : "good";
            if (loss >= 5 || avg > 80) return "bad";
            return loss > 0 || avg > 40 || jitter > 15 ? "warn" : "good";
        }

        public static string Ms(double ms) => ms < 1 ? "unter 1 ms" : ms.ToString("N0", System.Globalization.CultureInfo.GetCultureInfo("de-DE")) + " ms";
    }
}
