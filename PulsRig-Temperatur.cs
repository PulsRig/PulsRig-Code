// PulsRig - Temperatur des Prozessors. Wird von PulsRig-Hardware.ps1 beim ersten Bedarf übersetzt.
//
// Windows gibt die Temperatur des Prozessors nicht heraus. Zwei Wege:
//  1. LibreHardwareMonitor (Ordner "Sensoren" neben dem Programm) mit dem Treiber PawnIO. Der Treiber wird nur auf
//     Wunsch über sein eigenes, signiertes Setup installiert; gelesen werden kann nur mit Adminrechten.
//  2. Core Temp: läuft es, stellt es seine Messwerte im Speicher bereit (ohne Treiber von PulsRig, ohne Adminrechte).
// Read() liefert den Wert in °C oder NaN; Source sagt, woher er kam, Status, warum es keinen gibt.
// Die Bibliothek wird erst bei Bedarf geladen (eigene Methoden mit NoInlining), damit PulsRig ohne den Ordner läuft.

using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Reflection;
using System.Runtime.CompilerServices;

public static class PulsRigCpuTemp
{
    static readonly object Gate = new object();
    static string folder;
    static bool resolverSet;
    static bool tried;
    static object computer;      // LibreHardwareMonitor.Hardware.Computer, als object, damit diese Klasse ohne die Bibliothek lädt
    static object cpu;           // IHardware des Prozessors

    public static string Source = "";
    // none = kein Weg gefunden, noadmin = Treiber da, aber ohne Adminrechte, nodriver = PawnIO fehlt, nolib = Ordner fehlt
    public static string Status = "";
    public static string Sensor = "";
    public static double Power = double.NaN;

    public static void Init(string sensorFolder)
    {
        lock (Gate)
        {
            folder = sensorFolder;
            if (resolverSet) return;
            resolverSet = true;
            AppDomain.CurrentDomain.AssemblyResolve += Resolve;
        }
    }

    static Assembly Resolve(object sender, ResolveEventArgs args)
    {
        try
        {
            if (string.IsNullOrEmpty(folder)) return null;
            string name = new AssemblyName(args.Name).Name;
            string path = Path.Combine(folder, name + ".dll");
            return File.Exists(path) ? Assembly.LoadFrom(path) : null;
        }
        catch { return null; }
    }

    // Ist der Treiber PawnIO installiert? Er trägt sich als Dienst ein.
    public static bool DriverInstalled()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\PawnIO"))
                return key != null;
        }
        catch { return false; }
    }

    public static bool IsAdmin()
    {
        try { return new System.Security.Principal.WindowsPrincipal(System.Security.Principal.WindowsIdentity.GetCurrent()).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator); }
        catch { return false; }
    }

    public static bool LibraryPresent()
    {
        return !string.IsNullOrEmpty(folder) && File.Exists(Path.Combine(folder, "LibreHardwareMonitorLib.dll"));
    }

    public static double Read()
    {
        lock (Gate)
        {
            double value = double.NaN;
            Power = double.NaN;
            if (LibraryPresent() && DriverInstalled() && IsAdmin())
            {
                try { value = ReadLibrary(); } catch { value = double.NaN; }
                if (!double.IsNaN(value)) { Source = "LibreHardwareMonitor"; Status = "ok"; return value; }
            }
            value = ReadCoreTemp();
            if (!double.IsNaN(value)) { Source = "Core Temp"; Sensor = "Core Temp"; Status = "ok"; return value; }
            Source = "";
            if (!LibraryPresent()) Status = "nolib";
            else if (!DriverInstalled()) Status = "nodriver";
            else if (!IsAdmin()) Status = "noadmin";
            else Status = "none";
            return double.NaN;
        }
    }

    public static void Close()
    {
        lock (Gate)
        {
            try { if (computer != null) CloseLibrary(); } catch { }
            computer = null; cpu = null; tried = false;
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void CloseLibrary()
    {
        ((LibreHardwareMonitor.Hardware.Computer)computer).Close();
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static double ReadLibrary()
    {
        if (computer == null)
        {
            if (tried) return double.NaN;
            tried = true;
            var created = new LibreHardwareMonitor.Hardware.Computer { IsCpuEnabled = true };
            created.Open();
            computer = created;
            foreach (var hardware in created.Hardware)
                if (hardware.HardwareType == LibreHardwareMonitor.Hardware.HardwareType.Cpu) { cpu = hardware; break; }
        }
        var chip = cpu as LibreHardwareMonitor.Hardware.IHardware;
        if (chip == null) return double.NaN;
        chip.Update();
        // bevorzugt der Wert für den ganzen Prozessor: "CPU Package" (Intel), "Core (Tctl/Tdie)" (AMD); sonst der höchste
        double best = double.NaN, highest = double.NaN;
        string bestName = "", highestName = "";
        foreach (var sensor in chip.Sensors)
        {
            if (sensor.Value == null) continue;
            double v = (double)sensor.Value.Value;
            if (sensor.SensorType == LibreHardwareMonitor.Hardware.SensorType.Power && sensor.Name.IndexOf("Package", StringComparison.OrdinalIgnoreCase) >= 0) Power = v;
            if (sensor.SensorType != LibreHardwareMonitor.Hardware.SensorType.Temperature) continue;
            if (v <= 0 || v > 150) continue;
            string n = sensor.Name;
            if (double.IsNaN(best) && (n.IndexOf("Package", StringComparison.OrdinalIgnoreCase) >= 0 || n.IndexOf("Tctl", StringComparison.OrdinalIgnoreCase) >= 0 || n.IndexOf("Tdie", StringComparison.OrdinalIgnoreCase) >= 0))
            { best = v; bestName = n; }
            if (n.IndexOf("Distance", StringComparison.OrdinalIgnoreCase) >= 0) continue;
            if (double.IsNaN(highest) || v > highest) { highest = v; highestName = n; }
        }
        if (!double.IsNaN(best)) { Sensor = bestName; return best; }
        Sensor = highestName;
        return highest;
    }

    // Core Temp legt seine Werte im Speicherbereich "CoreTempMappingObject" ab:
    // uint Load[256], uint TjMax[128], uint CoreCount, uint CpuCount, float Temp[256], float VID, float Speed,
    // float FSB, float Multiplier, char Name[100], byte Fahrenheit, byte DeltaToTjMax
    static double ReadCoreTemp()
    {
        try
        {
            using (var map = MemoryMappedFile.OpenExisting("CoreTempMappingObject", MemoryMappedFileRights.Read))
            using (var view = map.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read))
            {
                uint cores = view.ReadUInt32(1536);
                uint cpus = view.ReadUInt32(1540);
                int count = (int)Math.Min(256, Math.Max(1, cores) * Math.Max(1, cpus));
                if (cores == 0 || cores > 256) return double.NaN;
                bool fahrenheit = view.ReadByte(2684) != 0;
                bool delta = view.ReadByte(2685) != 0;
                double highest = double.NaN;
                for (int i = 0; i < count; i++)
                {
                    double t = view.ReadSingle(1544 + 4 * i);
                    if (delta) t = view.ReadUInt32(1024 + 4 * Math.Min(127, i / (int)Math.Max(1, cores))) - t;
                    if (fahrenheit) t = (t - 32) * 5 / 9;
                    if (t <= 0 || t > 150) continue;
                    if (double.IsNaN(highest) || t > highest) highest = t;
                }
                return highest;
            }
        }
        catch { return double.NaN; }
    }
}
