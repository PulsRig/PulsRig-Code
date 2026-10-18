// PulsRig - Aufzeichnung beim Spielen. Läuft im Helfer neben der Uhr (PulsRig-Start.cs, PulsRigHelper) und wird
// zusammen mit PulsRig-Temperatur.cs in PulsRig.exe übersetzt.
//
// Läuft eines der gewählten Spiele, schreibt der Helfer alle 5 Sekunden eine Zeile in eine eigene Datei im Ordner
// "Aufzeichnungen" neben den Einstellungen: Prozessor (Temperatur, Last, Takt, Leistung) und Grafikkarte (Temperatur,
// Last, Leistung, Lüfter, Takt; nur NVIDIA, über einen einzigen nvidia-smi, der selbst im 5-Sekunden-Takt liefert).
// Die Datei wird nach jeder Zeile geschrieben: PulsRig kann eine laufende Sitzung schon ansehen.
// Kürzer als eine Minute wird nicht behalten (Startprogramme, Abstürze beim Laden), länger als 12 Stunden nicht
// fortgesetzt; es bleiben die letzten 30 Sitzungen.

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;

public static class PulsRigRecorder
{
    public const string Header = "Sekunde;CpuTemp;CpuLast;CpuTakt;CpuWatt;GpuTemp;GpuLast;GpuWatt;GpuLuefter;GpuTakt";
    static StreamWriter writer;
    static string path, game;
    static DateTime start;
    static Process smi;
    static volatile string smiLine = "";
    static PerformanceCounter load, performance;
    static double baseMhz;
    static int rows;

    public static bool Active { get { return writer != null; } }
    public static string Game { get { return game; } }
    public static bool Manual;

    public static string Folder(string outDir) { return Path.Combine(outDir, "Aufzeichnungen"); }

    public static void Start(string outDir, string name, string sensorFolder, bool manual)
    {
        if (writer != null) return;
        string folder = Folder(outDir);
        Directory.CreateDirectory(folder);
        Prune(folder);
        game = name;
        Manual = manual;
        start = DateTime.Now;
        rows = 0;
        string safe = string.Join("_", name.Split(Path.GetInvalidFileNameChars()));
        path = Path.Combine(folder, start.ToString("yyyy-MM-dd_HH-mm-ss") + "_" + safe + ".csv");
        writer = new StreamWriter(path, false, new UTF8Encoding(false));
        writer.AutoFlush = true;
        writer.WriteLine("# PulsRig-Aufzeichnung;Spiel=" + name + ";Beginn=" + start.ToString("yyyy-MM-ddTHH:mm:ss") + ";Takt=5");
        writer.WriteLine(Header);

        try { PulsRigCpuTemp.Init(sensorFolder); } catch { }
        try
        {
            load = new PerformanceCounter("Processor Information", "% Processor Utility", "_Total");
            load.NextValue();
        }
        catch { load = null; }
        try
        {
            performance = new PerformanceCounter("Processor Information", "% Processor Performance", "_Total");
            performance.NextValue();
            using (var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0"))
                baseMhz = key == null ? 0 : Convert.ToDouble(key.GetValue("~MHz", 0));
        }
        catch { performance = null; }
        StartSmi();
    }

    static void StartSmi()
    {
        try
        {
            string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "nvidia-smi.exe");
            if (!File.Exists(exe)) return;
            var info = new ProcessStartInfo(exe, "-i 0 --query-gpu=temperature.gpu,utilization.gpu,power.draw,fan.speed,clocks.gr --format=csv,noheader,nounits -l 5")
            { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
            smi = new Process { StartInfo = info };
            smi.OutputDataReceived += delegate (object sender, DataReceivedEventArgs e) { if (e.Data != null) smiLine = e.Data; };
            smi.Start();
            smi.BeginOutputReadLine();
        }
        catch { smi = null; }
    }

    static string Number(double value, string format)
    {
        return double.IsNaN(value) || double.IsInfinity(value) ? "" : value.ToString(format, CultureInfo.InvariantCulture);
    }

    static double Parse(string text)
    {
        double value;
        return double.TryParse((text ?? "").Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out value) ? value : double.NaN;
    }

    // eine Zeile; gibt false zurück, wenn die Sitzung zu lang geworden ist
    public static bool Sample()
    {
        if (writer == null) return false;
        double seconds = (DateTime.Now - start).TotalSeconds;
        if (seconds > 12 * 3600) return false;
        double cpuTemp = double.NaN, cpuLoad = double.NaN, cpuClock = double.NaN, cpuPower = double.NaN;
        try { cpuTemp = PulsRigCpuTemp.Read(); cpuPower = PulsRigCpuTemp.Power; } catch { }
        try { if (load != null) cpuLoad = Math.Min(100, load.NextValue()); } catch { }
        try { if (performance != null && baseMhz > 0) cpuClock = baseMhz * performance.NextValue() / 100.0; } catch { }
        string[] gpu = (smiLine ?? "").Split(',');
        double gpuTemp = double.NaN, gpuLoad = double.NaN, gpuPower = double.NaN, gpuFan = double.NaN, gpuClock = double.NaN;
        if (gpu.Length >= 5) { gpuTemp = Parse(gpu[0]); gpuLoad = Parse(gpu[1]); gpuPower = Parse(gpu[2]); gpuFan = Parse(gpu[3]); gpuClock = Parse(gpu[4]); }
        try
        {
            writer.WriteLine(string.Join(";", new[] {
                Number(Math.Round(seconds), "0"), Number(cpuTemp, "0.0"), Number(cpuLoad, "0"), Number(cpuClock, "0"), Number(cpuPower, "0.0"),
                Number(gpuTemp, "0"), Number(gpuLoad, "0"), Number(gpuPower, "0.0"), Number(gpuFan, "0"), Number(gpuClock, "0") }));
            rows++;
        }
        catch { return false; }
        return true;
    }

    // beendet die Sitzung; Ergebnis: Dauer in Minuten (0, wenn sie zu kurz war und gelöscht wurde)
    public static double Stop()
    {
        if (writer == null) return 0;
        double minutes = (DateTime.Now - start).TotalMinutes;
        try { writer.Dispose(); } catch { }
        writer = null;
        try { if (smi != null && !smi.HasExited) smi.Kill(); } catch { }
        try { if (smi != null) smi.Dispose(); } catch { }
        smi = null; smiLine = "";
        try { if (load != null) load.Dispose(); if (performance != null) performance.Dispose(); } catch { }
        load = null; performance = null;
        try { PulsRigCpuTemp.Close(); } catch { }
        game = null;
        if (minutes < 1 || rows < 3) { try { File.Delete(path); } catch { } return 0; }
        return minutes;
    }

    // es bleiben die neuesten 29, damit mit der neuen 30 da sind
    static void Prune(string folder)
    {
        try
        {
            var files = new DirectoryInfo(folder).GetFiles("*.csv");
            Array.Sort(files, delegate (FileInfo a, FileInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
            for (int i = 29; i < files.Length; i++) { try { files[i].Delete(); } catch { } }
        }
        catch { }
    }
}
