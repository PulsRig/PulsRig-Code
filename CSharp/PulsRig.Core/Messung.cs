// PulsRig.Core - die Messschleife der Sensoren, abgelöst aus PulsRig-Hardware.ps1. Grafikkarte über nvidia-smi,
// Last und Takt des Prozessors und der belegte Arbeitsspeicher aus den Leistungszählern von Windows. Die Temperatur
// des Prozessors steckt nicht hier (PulsRig-Temperatur.cs braucht LibreHardwareMonitor), der Aufrufer ergänzt sie.
//
// Next() wartet auf den nächsten Sekundentakt und gibt die Werte unter denselben Schlüsseln zurück wie bisher die
// Schleife in PowerShell (GpuTemp, CpuLoad, CpuCoreMax, Ram ...). Fehlt ein Wert, fehlt sein Schlüssel.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace PulsRig.Core
{
    public sealed class Messung : IDisposable
    {
        Process? nvidia;
        readonly PerformanceCounter? load;
        readonly PerformanceCounter? performance;
        // je logischem Kern die belegte Zeit: alle Kerne kommen je Takt aus einer einzigen Abfrage der Kategorie
        // (ReadCategory). Ein eigener Zähler je Kern liest die ganze Kategorie jedes Mal neu - bei 16 Kernen 16-mal.
        readonly PerformanceCounterCategory? coreCategory;
        Dictionary<string, CounterSample>? coreLast;
        readonly PerformanceCounter? available;
        readonly double baseMhz;
        readonly double totalMb;

        public int NvidiaPid { get; private set; }

        // nvidiaExe: Pfad zu nvidia-smi.exe oder leer; baseMhz: MaxClockSpeed aus Win32_Processor. Beides sucht der
        // Aufrufer, damit der Probelauf auf einem vorgetäuschten System (PulsRig-Fremdsystem.ps1) auch hier greift.
        public Messung(string? nvidiaExe, double baseMhz)
        {
            this.baseMhz = baseMhz;
            if (!string.IsNullOrEmpty(nvidiaExe)) StartNvidia(nvidiaExe!);
            foreach (var name in new[] { new[] { "Processor Information", "% Processor Utility" }, new[] { "Processor", "% Processor Time" } })
            {
                try { load = new PerformanceCounter(name[0], name[1], "_Total"); load.NextValue(); break; }
                catch (Exception) { load = null; }
            }
            try { performance = new PerformanceCounter("Processor Information", "% Processor Performance", "_Total"); performance.NextValue(); }
            catch (Exception) { performance = null; }
            // je logischem Kern ein Zähler: für den Aufrüst-Berater zählt der am stärksten belastete Kern, nicht der Mittelwert
            try
            {
                coreCategory = new PerformanceCounterCategory(load?.CategoryName ?? "Processor");
                CoreMax();   // erster Stand: der nächste Takt hat damit einen Vergleichswert
            }
            catch (Exception) { coreCategory = null; }
            // Arbeitsspeicher: die Gesamtgröße einmal lesen, den freien Rest danach aus einem Leistungszähler - das kostet
            // im Sekundentakt viel weniger als jedes Mal eine Abfrage an Windows
            try
            {
                totalMb = TotalMemoryMb();
                available = new PerformanceCounter("Memory", "Available MBytes");
                available.NextValue();
            }
            catch (Exception) { available = null; }
        }

        void StartNvidia(string exe)
        {
            try
            {
                var start = new ProcessStartInfo
                {
                    FileName = exe,
                    // -i 0: bei mehreren NVIDIA-Karten käme sonst je Karte eine Zeile und die Werte sprängen hin und her
                    Arguments = "-i 0 --query-gpu=name,temperature.gpu,fan.speed,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits -l 1",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true,
                };
                nvidia = Process.Start(start);
                // endet mit PulsRig, auch nach Absturz oder Beenden im Task-Manager
                Kindprozess.Bind(nvidia);
                NvidiaPid = nvidia?.Id ?? 0;
            }
            catch (Exception) { nvidia = null; }
        }

        // Der am stärksten belastete Kern seit dem letzten Aufruf in Prozent; null beim ersten Aufruf oder ohne Zähler.
        // Je Kern die belegte Zeit, nicht "% Processor Utility": die rechnet den Turbotakt mit ein und lag bei einem
        // Kern schon über 100 %, wenn er nur kurz (etwa beim Seitenwechsel) zu 85 % beschäftigt war
        double? CoreMax()
        {
            if (coreCategory == null) return null;
            var data = coreCategory.ReadCategory();
            if (!data.Contains(CoreCounter)) return null;
            var now = new Dictionary<string, CounterSample>();
            double top = 0.0;
            bool any = false;
            foreach (InstanceData item in data[CoreCounter].Values)
            {
                if (item.InstanceName.Contains("_Total")) continue;
                now[item.InstanceName] = item.Sample;
                if (coreLast != null && coreLast.TryGetValue(item.InstanceName, out CounterSample old))
                {
                    top = Math.Max(top, CounterSample.Calculate(old, item.Sample));
                    any = true;
                }
            }
            coreLast = now;
            return any ? top : (double?)null;
        }

        const string CoreCounter = "% Processor Time";

        public static double? Number(string? text) =>
            double.TryParse((text ?? "").Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out double value) ? value : (double?)null;

        // Zeile von nvidia-smi in die Werte übernehmen; "[N/A]" (etwa ohne Lüfter) ergibt keinen Wert
        public static void ParseNvidiaLine(string? line, IDictionary values)
        {
            string[] parts = (line ?? "").Split(',');
            if (parts.Length < 7) return;
            values["GpuName"] = parts[0].Trim();
            string[] keys = { "GpuTemp", "GpuFan", "GpuLoad", "GpuMemory", "GpuMemoryTotal", "GpuPower" };
            for (int i = 0; i < keys.Length; i++) values[keys[i]] = Number(parts[i + 1]);
        }

        // Ein Takt. Hashtable statt Dictionary, damit PowerShell die Werte wie bisher als $values.CpuLoad liest.
        public Hashtable Next()
        {
            var values = new Hashtable(StringComparer.OrdinalIgnoreCase);
            if (nvidia != null && !nvidia.HasExited)
            {
                // die Zeile des NVIDIA-Werkzeugs gibt zugleich den Sekundentakt vor
                string? line = null;
                try { line = nvidia.StandardOutput.ReadLine(); } catch (Exception) { }
                // keine Zeile heißt: das Werkzeug ist gerade zu Ende gegangen. Ohne Pause liefe die Schleife ungebremst,
                // bis Windows den Prozess als beendet meldet
                if (line == null) Thread.Sleep(1000);
                else ParseNvidiaLine(line, values);
            }
            else Thread.Sleep(1000);
            try { if (load != null) values["CpuLoad"] = Math.Min(100.0, load.NextValue()); } catch (Exception) { }
            try { if (CoreMax() is double top) values["CpuCoreMax"] = Math.Min(100.0, top); } catch (Exception) { }
            try { if (performance != null && baseMhz > 0) values["CpuClock"] = baseMhz * performance.NextValue() / 100.0 / 1000.0; } catch (Exception) { }
            try { if (available != null && totalMb > 0) values["Ram"] = Math.Max(0.0, 100.0 * (1.0 - available.NextValue() / totalMb)); } catch (Exception) { }
            return values;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct MemoryStatus
        {
            public uint Length, Load;
            public ulong TotalPhys, AvailPhys, TotalPageFile, AvailPageFile, TotalVirtual, AvailVirtual, AvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

        // dieselbe Größe wie TotalVisibleMemorySize von Win32_OperatingSystem
        static double TotalMemoryMb()
        {
            var status = new MemoryStatus { Length = (uint)Marshal.SizeOf(typeof(MemoryStatus)) };
            return GlobalMemoryStatusEx(ref status) ? status.TotalPhys / 1024.0 / 1024.0 : 0.0;
        }

        public void Dispose()
        {
            if (nvidia != null) { try { if (!nvidia.HasExited) nvidia.Kill(); } catch (Exception) { } nvidia.Dispose(); nvidia = null; }
            load?.Dispose(); performance?.Dispose(); available?.Dispose();
            coreLast = null;
        }
    }
}
