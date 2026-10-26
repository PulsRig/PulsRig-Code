// PulsRig.Core - Laufwerke ohne die Windows-Module. Abgelöst aus Treiber-Werkzeuge.ps1 (Get-DiskList, Get-PartitionList,
// Get-VolumeList): die Abfrage über CIM bleibt beim Aufrufer, hier steht, wie aus den Rohwerten die Wörter werden, die
// auch Get-PhysicalDisk und Get-Volume liefern.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PulsRig.Core
{
    public static class Laufwerke
    {
        static readonly Dictionary<int, string> MediaWords = new Dictionary<int, string> { { 3, "HDD" }, { 4, "SSD" }, { 5, "SCM" } };
        static readonly Dictionary<int, string> BusWords = new Dictionary<int, string>
        {
            { 1, "SCSI" }, { 2, "ATAPI" }, { 3, "ATA" }, { 4, "1394" }, { 5, "SSA" }, { 6, "Fibre Channel" }, { 7, "USB" }, { 8, "RAID" },
            { 9, "iSCSI" }, { 10, "SAS" }, { 11, "SATA" }, { 12, "SD" }, { 13, "MMC" }, { 15, "File Backed Virtual" }, { 16, "Storage Spaces" }, { 17, "NVMe" }
        };
        static readonly Dictionary<int, string> HealthWords = new Dictionary<int, string> { { 0, "Healthy" }, { 1, "Warning" }, { 2, "Unhealthy" } };
        static readonly Dictionary<int, string> StatusWords = new Dictionary<int, string> { { 2, "OK" } };

        // Windows liefert Art, Anschluss und Zustand als Zahl - es sei denn, eines der Module ist doch geladen (etwa nach
        // der Netzwerk-Reparatur): dann stehen dort schon Wörter. Beides wird zum selben Wort.
        public static string CimWord(object? value, IDictionary<int, string> map, string fallback)
        {
            string text = Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? "";
            if (int.TryParse(text, out int number)) return map.TryGetValue(number, out string? word) ? word : fallback;
            return text.Length > 0 ? text : fallback;
        }

        public static string MediaType(object? value) => CimWord(value, MediaWords, "Unspecified");
        public static string BusType(object? value) => CimWord(value, BusWords, "Unknown");
        public static string Health(object? value) => CimWord(value, HealthWords, "Unknown");

        // OperationalStatus ist eine Liste; unbekannte Zahlen bleiben als Zahl stehen
        public static string OperationalStatus(object? value)
        {
            var words = new List<string>();
            if (value is System.Collections.IEnumerable list && !(value is string))
                foreach (object? item in list) words.Add(CimWord(item, StatusWords, Convert.ToString(item) ?? ""));
            else if (value != null) words.Add(CimWord(value, StatusWords, Convert.ToString(value) ?? ""));
            return string.Join(", ", words);
        }

        // Buchstabe eines Laufwerks als Text; Windows liefert ein Zeichen, bei Partitionen ohne Buchstaben das Zeichen 0
        public static string DriveLetter(object? value)
        {
            int code;
            if (value is char c) code = c;
            else if (value is string s) code = s.Length == 1 ? s[0] : 0;
            else
            {
                try { code = Convert.ToInt32(value); }
                catch (Exception) { code = 0; }
            }
            return code >= 65 && code <= 122 ? char.ToUpperInvariant((char)code).ToString() : "";
        }

        // Manche Laufwerke (etwa ältere Festplatten von WD) meldet Windows mit der Bauart "Unspecified". Dann helfen zwei
        // Fragen direkt an das Laufwerk: hat es eine Suchzeit (Lesekopf, der sich bewegen muss), ist es eine Festplatte;
        // beantwortet es das nicht (so die WD10EARS beim Nutzer), entscheidet TRIM: das können nur SSDs. Beides geht ohne
        // Adminrechte; antwortet das Laufwerk auf keine der Fragen, bleibt es bei "Unspecified".
        public static string ResolveMedia(string media, object? number)
        {
            if (media != "Unspecified") return media;
            try
            {
                int disk = Convert.ToInt32(Convert.ToString(number, System.Globalization.CultureInfo.InvariantCulture));
                switch (Flag(disk, 7)) { case 1: return "HDD"; case 0: return "SSD"; }
                switch (Flag(disk, 8)) { case 1: return "SSD"; case 0: return "HDD"; }
            }
            catch (Exception) { }
            return media;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PropertyQuery { public int PropertyId; public int QueryType; public int Extra; }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(IntPtr device, uint code, ref PropertyQuery input, int inputSize, byte[] output, int outputSize, out int returned, IntPtr overlapped);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);

        // Ja/Nein-Eigenschaft eines Laufwerks (7 = Suchzeit, 8 = TRIM): 1 = ja, 0 = nein, -1 = keine Antwort
        public static int Flag(int number, int property)
        {
            // Zugriff 0 genügt für die Abfrage der Eigenschaften und braucht keine Adminrechte
            IntPtr device = CreateFile(@"\\.\PhysicalDrive" + number, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (device == new IntPtr(-1)) return -1;
            try
            {
                var query = new PropertyQuery { PropertyId = property };
                byte[] output = new byte[16];
                if (!DeviceIoControl(device, 0x2D1400, ref query, Marshal.SizeOf(typeof(PropertyQuery)), output, output.Length, out int returned, IntPtr.Zero) || returned < 9) return -1;
                return output[8] != 0 ? 1 : 0;
            }
            finally { CloseHandle(device); }
        }
    }
}
