using System.IO;
using System.Management;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Abfragen der Hardware-Seiten, wie die Abfragen "Memory", "Drives" und "Displays" im PowerShell-Programm.
// Jede läuft im Hintergrund (Task.Run) und gibt bei einem Fehler leere Werte zurück, nie eine Ausnahme.
// Wie dort keine Get-PhysicalDisk & Co.: die Klassen MSFT_* werden direkt gelesen.

sealed record Prozessor(string Name, int Cores, int Threads, double MaxGhz);
sealed record Grafikkarte(string Name, string Driver, double MemoryBytes, string WindowsVersion = "", string Date = "");
sealed record Arbeitsspeicher(List<SpeicherRiegel> Modules, List<Steckplatz> Layout, int Slots, double MaxBytes, double Total, double Free, Speichertest? Test = null, Hardwarefehler? Hardware = null);
sealed record Laufwerk(string Number, string Name, string Media, string Bus, double Size, string Health, string[] Letters, int? Temperature, int? Wear);
sealed record Volume(string Letter, string Label, double Size, double Free, string Disk);
sealed record Laufwerke(List<Laufwerk> Disks, List<Volume> Volumes, Laufwerksstoerungen? Faults = null);
sealed record Bildschirm(string Name, int Width, int Height, int Hz, int Max, bool Primary);

static class Abfragen
{
    const string Storage = @"root\Microsoft\Windows\Storage";

    static IEnumerable<ManagementObject> Query(string wql, string scope = @"root\cimv2")
    {
        using var searcher = new ManagementObjectSearcher(scope, wql);
        foreach (ManagementObject o in searcher.Get()) yield return o;
    }

    static string Text(ManagementBaseObject o, string name) => (o[name]?.ToString() ?? "").Trim();
    static double Number(ManagementBaseObject o, string name) => o[name] is { } v ? Convert.ToDouble(v) : 0;

    public static Prozessor? Cpu()
    {
        try
        {
            var all = Query("SELECT Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed FROM Win32_Processor").ToList();
            if (all.Count == 0) return null;
            var first = all[0];
            return new Prozessor(Text(first, "Name"), (int)all.Sum(p => Number(p, "NumberOfCores")),
                (int)all.Sum(p => Number(p, "NumberOfLogicalProcessors")), Number(first, "MaxClockSpeed") / 1000);
        }
        catch (Exception) { return null; }
    }

    public static Grafikkarte? Gpu()
    {
        try
        {
            // die erste echte Karte; Fernzugriff und Basisanzeige zählen nicht
            var card = Query("SELECT Name, DriverVersion, DriverDate, AdapterRAM, PNPDeviceID FROM Win32_VideoController")
                .FirstOrDefault(v => !Text(v, "Name").Contains("Basic", StringComparison.OrdinalIgnoreCase) && !Text(v, "Name").Contains("Remote", StringComparison.OrdinalIgnoreCase));
            if (card == null) return null;
            var name = Text(card, "Name");
            var version = Text(card, "DriverVersion");
            var driver = name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) ? Hersteller.NvidiaVersion(version) ?? version : version;
            var date = "";
            try { if (Text(card, "DriverDate").Length > 0) date = ManagementDateTimeConverter.ToDateTime(Text(card, "DriverDate")).ToString("dd.MM.yyyy"); } catch (Exception) { }
            return new Grafikkarte(name, driver, Systeminfo.GpuMemory(GpuRegistryMemory(name), (long)Number(card, "AdapterRAM")), version, date);
        }
        catch (Exception) { return null; }
    }

    // AdapterRAM endet bei 4 GB; die volle Größe steht beim Treiber in der Registrierung (qwMemorySize)
    static long GpuRegistryMemory(string name)
    {
        try
        {
            using var classKey = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}");
            if (classKey == null) return 0;
            foreach (var sub in classKey.GetSubKeyNames())
            {
                using var key = classKey.OpenSubKey(sub);
                if (key?.GetValue("DriverDesc") as string != name) continue;
                if (key.GetValue("HardwareInformation.qwMemorySize") is long bytes) return bytes;
            }
        }
        catch (Exception) { }
        return 0;
    }

    public static Arbeitsspeicher Memory()
    {
        var modules = new List<SpeicherRiegel>();
        try
        {
            foreach (var m in Query("SELECT * FROM Win32_PhysicalMemory"))
            {
                var configured = (int)Number(m, "ConfiguredClockSpeed");
                var voltage = (int)Number(m, "ConfiguredVoltage");
                modules.Add(new SpeicherRiegel
                {
                    Slot = Text(m, "DeviceLocator"), Bank = Text(m, "BankLabel"), Maker = Speicher.Maker(Text(m, "Manufacturer")),
                    Part = Text(m, "PartNumber"), Bytes = Number(m, "Capacity"),
                    Speed = configured > 0 ? configured : (int)Number(m, "Speed"), Rated = (int)Number(m, "Speed"), Voltage = voltage,
                    Type = Speicher.TypeName((int)Number(m, "SMBIOSMemoryType")), Laptop = (int)Number(m, "FormFactor") == 12,
                });
            }
        }
        catch (Exception) { }
        int slots = 0;
        double maxBytes = 0;
        try
        {
            foreach (var a in Query("SELECT MemoryDevices, MaxCapacity, MaxCapacityEx FROM Win32_PhysicalMemoryArray"))
            {
                slots += (int)Number(a, "MemoryDevices");
                var ex = Number(a, "MaxCapacityEx");
                maxBytes += (ex > 0 ? ex : Number(a, "MaxCapacity")) * 1024;
            }
        }
        catch (Exception) { }
        var layout = new List<Steckplatz>();
        try
        {
            var raw = Query("SELECT SMBiosData FROM MSSmBios_RawSMBiosTables", @"root\wmi").FirstOrDefault()?["SMBiosData"] as byte[];
            layout = Speicher.ParseSmbios(raw, modules.Count);
        }
        catch (Exception) { }
        double total = 0, free = 0;
        try
        {
            var os = Query("SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem").First();
            total = Number(os, "TotalVisibleMemorySize") * 1024;
            free = Number(os, "FreePhysicalMemory") * 1024;
        }
        catch (Exception) { }
        return new Arbeitsspeicher(modules, Speicher.Layout(modules, layout, slots), slots, maxBytes, total, free, Ereignisse.MemoryTest(), Ereignisse.Whea90());
    }

    public static Laufwerke Drives()
    {
        var letters = new Dictionary<string, List<string>>();
        var diskOfLetter = new Dictionary<string, string>();
        try
        {
            foreach (var p in Query("SELECT DriveLetter, DiskNumber FROM MSFT_Partition", Storage))
            {
                var letter = Core.Laufwerke.DriveLetter(p["DriveLetter"]);
                if (letter.Length == 0) continue;
                var disk = Text(p, "DiskNumber");
                diskOfLetter[letter] = disk;
                if (!letters.TryGetValue(disk, out var list)) letters[disk] = list = new List<string>();
                list.Add(letter);
            }
        }
        catch (Exception) { }
        var volumes = new List<Volume>();
        try
        {
            foreach (var v in Query("SELECT DriveLetter, FileSystemLabel, Size, SizeRemaining FROM MSFT_Volume", Storage))
            {
                var letter = Core.Laufwerke.DriveLetter(v["DriveLetter"]);
                if (letter.Length == 0 || Number(v, "Size") <= 0) continue;
                volumes.Add(new Volume(letter, Text(v, "FileSystemLabel"), Number(v, "Size"), Number(v, "SizeRemaining"), diskOfLetter.GetValueOrDefault(letter, "")));
            }
        }
        catch (Exception) { }
        var disks = new List<Laufwerk>();
        try
        {
            foreach (var d in Query("SELECT * FROM MSFT_PhysicalDisk", Storage))
            {
                var number = Text(d, "DeviceId");
                int? temperature = null, wear = null;
                // Temperatur und Abnutzung gibt Windows nur mit Adminrechten heraus
                try
                {
                    foreach (ManagementObject c in d.GetRelated("MSFT_StorageReliabilityCounter"))
                    {
                        if (c["Temperature"] is { } t && Convert.ToInt32(t) > 0) temperature = Convert.ToInt32(t);
                        if (c["Wear"] is { } w) wear = Convert.ToInt32(w);
                        break;
                    }
                }
                catch (Exception) { }
                disks.Add(new Laufwerk(number, Text(d, "FriendlyName"),
                    Core.Laufwerke.ResolveMedia(Core.Laufwerke.MediaType(d["MediaType"]), d["DeviceId"]),
                    Core.Laufwerke.BusType(d["BusType"]), Number(d, "Size"), Core.Laufwerke.Health(d["HealthStatus"]),
                    letters.GetValueOrDefault(number, new List<string>()).OrderBy(l => l).ToArray(), temperature, wear));
            }
        }
        catch (Exception) { }
        return new Laufwerke(disks.OrderBy(d => int.TryParse(d.Number, out var n) ? n : 99).ToList(), volumes.OrderBy(v => v.Letter).ToList(), Ereignisse.DiskFaults());
    }

    public static List<Bildschirm> Displays()
    {
        var list = new List<Bildschirm>();
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var m in Query("SELECT InstanceName, UserFriendlyName FROM WmiMonitorID", @"root\wmi"))
            {
                var code = Text(m, "InstanceName").Split('\\').ElementAtOrDefault(1) ?? "";
                if (m["UserFriendlyName"] is ushort[] chars) names[code] = new string(chars.Where(c => c != 0).Select(c => (char)c).ToArray());
            }
        }
        catch (Exception) { }
        try
        {
            foreach (var d in Display.GetDisplays())
            {
                if (d.Current == null) continue;
                var code = (d.MonitorId ?? "").Split('\\').ElementAtOrDefault(1) ?? "";
                var rates = d.Modes.Where(m => m.Width == d.Current.Width && m.Height == d.Current.Height).Select(m => m.Frequency).ToList();
                list.Add(new Bildschirm(names.GetValueOrDefault(code, "Bildschirm"), d.Current.Width, d.Current.Height, d.Current.Frequency,
                    rates.Count > 0 ? rates.Max() : d.Current.Frequency, d.Primary));
            }
        }
        catch (Exception) { }
        return list;
    }

    public static string NvidiaSmi()
    {
        var places = new[]
        {
            Path.Combine(Environment.SystemDirectory, "nvidia-smi.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "NVIDIA Corporation", "NVSMI", "nvidia-smi.exe"),
        };
        return places.FirstOrDefault(File.Exists) ?? "";
    }
}
