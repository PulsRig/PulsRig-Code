// PulsRig.Core - Bausteine für Standby-Detektiv, Autostart, Gaming-Check und alte Treiberpakete, abgelöst aus
// PulsRig-Standby.ps1, PulsRig-Autostart.ps1, PulsRig-Spielcheck.ps1 und Get-OldDriverPackages. Gelesen wird in der
// App (Ereignisprotokoll, powercfg, Registry); hier steht, wie die Rohwerte gedeutet werden.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    // ein Paket im Treiberspeicher (HKLM\SYSTEM\DriverDatabase\DriverPackages)
    public sealed class Treiberpaket
    {
        public string Inf { get; set; } = "";          // oem12.inf
        public string Original { get; set; } = "";     // nv_dispi.inf
        public string Provider { get; set; } = "";
        public string ClassGuid { get; set; } = "";
        public DateTime Date { get; set; }
        public Version Version { get; set; } = new Version(0, 0);
        public string Folder { get; set; } = "";       // Ordnername in FileRepository
    }

    public static class Treiberspeicher
    {
        // Wert "Version" eines Pakets: 8 Byte, Klassen-GUID (16), Treiberdatum als FILETIME (8), Version als vier
        // 16-Bit-Zahlen von hinten nach vorn (8). Kürzer heißt: unbekannt.
        public static bool ParseVersion(byte[]? raw, out string classGuid, out DateTime date, out Version version)
        {
            classGuid = ""; date = DateTime.MinValue; version = new Version(0, 0);
            if (raw == null || raw.Length < 40) return false;
            var guid = new byte[16];
            Array.Copy(raw, 8, guid, 0, 16);
            classGuid = new Guid(guid).ToString("B");
            long time = BitConverter.ToInt64(raw, 24);
            try { date = time > 0 ? DateTime.FromFileTimeUtc(time) : DateTime.MinValue; } catch (ArgumentOutOfRangeException) { }
            version = new Version(BitConverter.ToUInt16(raw, 38), BitConverter.ToUInt16(raw, 36), BitConverter.ToUInt16(raw, 34), BitConverter.ToUInt16(raw, 32));
            return true;
        }

        // wie Get-OldDriverPackages: je Treiber (Originalname, Anbieter, Klasse) bleiben die zwei neuesten Fassungen,
        // was ein Gerät gerade benutzt, bleibt immer; nur oem*.inf (Drittanbieter)
        public static List<Treiberpaket> Old(IEnumerable<Treiberpaket> packages, ICollection<string> inUse)
        {
            var old = new List<Treiberpaket>();
            var used = new HashSet<string>(inUse.Select(i => i.ToLowerInvariant()));
            foreach (var group in packages.Where(p => Regex.IsMatch(p.Inf, @"^oem\d+\.inf$", RegexOptions.IgnoreCase))
                .GroupBy(p => (p.Original.ToLowerInvariant() + "|" + p.Provider + "|" + p.ClassGuid.ToLowerInvariant())))
            {
                if (group.Count() < 3) continue;
                foreach (var p in group.OrderByDescending(p => p.Version).ThenByDescending(p => p.Date).Skip(2))
                    if (!used.Contains(p.Inf.ToLowerInvariant())) old.Add(p);
            }
            return old;
        }

        public static readonly Dictionary<string, string> ClassWords = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "Display", "Grafik" }, { "Net", "Netzwerk" }, { "Media", "Audio" }, { "System", "System" }, { "USB", "USB" }, { "Bluetooth", "Bluetooth" },
            { "HIDClass", "Eingabegerät" }, { "Monitor", "Monitor" }, { "SoftwareComponent", "Softwarekomponente" }, { "Extension", "Erweiterung" }, { "Firmware", "Firmware" },
        };

        public static string ClassWord(string? className) => ClassWords.TryGetValue(className ?? "", out string? word) ? word : className ?? "";
    }

    public sealed class Weckquelle
    {
        public string Key { get; set; } = "";
        public string Title { get; set; } = "";
        public string Hint { get; set; } = "";
        public string Open { get; set; } = "";   // devmgmt, timers oder leer
    }

    public static class Standby
    {
        // wie Get-WakeKind: Art der Weckquelle aus Quelle und Besitzer des Aufweck-Timers
        public static Weckquelle WakeKind(string? source, string? owner)
        {
            string text = (source ?? "") + " " + (owner ?? "");
            if (!string.IsNullOrWhiteSpace(owner) || Regex.IsMatch(text, @"Timer|Zeitgeber|geplante|scheduled|\\Microsoft\\Windows\\", RegexOptions.IgnoreCase))
                return new Weckquelle { Key = "timer", Title = "Geplante Aufgabe weckt den PC", Hint = "Aufweck-Timer lassen sich in den Energieoptionen abschalten", Open = "timers" };
            if (Regex.IsMatch(text, "Maus|Mouse|Tastatur|Keyboard|HID|Eingabe", RegexOptions.IgnoreCase))
                return new Weckquelle { Key = "input", Title = "Maus oder Tastatur weckt den PC", Hint = "Schon ein Ruckeln am Tisch reicht. Im Geräte-Manager lässt sich das je Gerät abschalten", Open = "devmgmt" };
            if (Regex.IsMatch(text, @"Ethernet|Network|Netzwerk|Wi-?Fi|WLAN|LAN|Realtek|Killer|Intel\(R\).*Connection", RegexOptions.IgnoreCase))
                return new Weckquelle { Key = "net", Title = "Netzwerkkarte weckt den PC", Hint = "Wake-on-LAN oder Netzwerkverkehr. Im Geräte-Manager unter Energieverwaltung abschaltbar", Open = "devmgmt" };
            if (Regex.IsMatch(text, "Power Button|Netzschalter|Ein/Aus|Betriebsschalter", RegexOptions.IgnoreCase))
                return new Weckquelle { Key = "button", Title = "Netzschalter", Hint = "Der PC wurde von Hand aufgeweckt" };
            if (string.IsNullOrWhiteSpace(source))
                return new Weckquelle { Key = "unknown", Title = "Ohne erkennbaren Grund aufgewacht", Hint = "Windows nennt keine Quelle; oft ein USB-Gerät oder das BIOS", Open = "devmgmt" };
            return new Weckquelle { Key = "dev:" + source!.Trim(), Title = source.Trim() + " weckt den PC", Hint = "Im Geräte-Manager unter Energieverwaltung abschaltbar", Open = "devmgmt" };
        }

        // powercfg /query: die beiden letzten Hex-Zahlen sind Netzbetrieb und Akku - gemeint ist der Netzbetrieb
        public static int? PlanValue(string? output)
        {
            var hex = Regex.Matches(output ?? "", "0x[0-9a-fA-F]{8}").Cast<Match>().Select(m => m.Value).ToList();
            return hex.Count >= 2 ? Convert.ToInt32(hex[hex.Count - 2], 16) : (int?)null;
        }

        // powercfg /devicequery wake_armed: "NONE"/"KEINE" heißt keine
        public static List<string> Armed(IEnumerable<string>? lines) =>
            (lines ?? Enumerable.Empty<string>()).Select(l => (l ?? "").Trim()).Where(l => l.Length > 0 && !Regex.IsMatch(l, "^(NONE|KEINE)$", RegexOptions.IgnoreCase)).Distinct().ToList();

        // powercfg /requests: Abschnitte "SYSTEM:", Einträge "[PROCESS] \Device\...\chrome.exe", darunter der Grund.
        // null heißt: Windows hat nichts herausgegeben (ohne Adminrechte)
        public static List<(string Section, string Kind, string Name, string Why)>? Requests(IList<string>? lines)
        {
            if (lines == null || !lines.Any(l => Regex.IsMatch(l.Trim(), "^[A-Z]+:$"))) return null;
            var list = new List<(string, string, string, string)>();
            string section = "";
            for (int i = 0; i < lines.Count; i++)
            {
                string line = lines[i].Trim();
                Match m;
                if ((m = Regex.Match(line, "^([A-Z]+):$")).Success) { section = m.Groups[1].Value; continue; }
                if (!(m = Regex.Match(line, @"^\[(\w+)\]\s*(.+)$")).Success) continue;
                string next = i + 1 < lines.Count ? lines[i + 1].Trim() : "";
                string why = next.Length > 0 && !Regex.IsMatch(next, @"^\[|^[A-Z]+:$") ? next : "";
                string name = m.Groups[2].Value.Trim();
                int slash = name.LastIndexOf('\\');
                list.Add((section, m.Groups[1].Value, slash >= 0 ? name.Substring(slash + 1) : name, why));
            }
            return list;
        }

        public static string RequestText(string section) => section switch
        {
            "DISPLAY" => "hält den Bildschirm an",
            "SYSTEM" => "verhindert den Standby",
            "AWAYMODE" => "hält den Abwesenheitsmodus",
            "EXECUTION" => "arbeitet im Hintergrund weiter",
            _ => "hält den PC wach",
        };

        public static string KindWord(string kind) => kind switch { "PROCESS" => "Programm", "SERVICE" => "Dienst", "DRIVER" => "Treiber", _ => kind };
    }

    public static class Autostart
    {
        // eingeschaltet, solange Windows unter StartupApproved nichts anderes vermerkt; ungerades erstes Byte = aus
        public static bool IsEnabled(byte[]? approved) => approved == null || approved.Length == 0 || (approved[0] & 1) == 0;

        // wie der Task-Manager: erstes Byte 2 = an, 3 = aus, beim Ausschalten dazu der Zeitpunkt
        public static byte[] Approved(bool on, DateTime now)
        {
            var bytes = new byte[12];
            bytes[0] = (byte)(on ? 2 : 3);
            if (!on) BitConverter.GetBytes(now.ToFileTime()).CopyTo(bytes, 4);
            return bytes;
        }

        // die Programmdatei aus einer Befehlszeile: in Anführungszeichen oder bis ".exe"
        public static string CommandFile(string? command)
        {
            string text = Environment.ExpandEnvironmentVariables((command ?? "").Trim());
            Match m;
            if ((m = Regex.Match(text, "^\"([^\"]+)\"")).Success) return m.Groups[1].Value;
            if ((m = Regex.Match(text, @"^(.+?\.exe)\b", RegexOptions.IgnoreCase)).Success) return m.Groups[1].Value;
            return text.Split(' ')[0];
        }

        // verwaist: der Eintrag startet nichts (leerer Befehl) oder nennt einen festen Pfad, an dem keine Datei mehr liegt
        public static bool IsOrphan(string? file, Func<string, bool> exists) =>
            string.IsNullOrWhiteSpace(file) || Regex.IsMatch(file, @"^([A-Za-z]:\\|\\\\)") && !exists(file!);

        // eine Zeile für eine .reg-Datei, die einen entfernten Wert zurückbringt (REG_SZ als Text, REG_EXPAND_SZ als hex(2))
        public static string RegLine(string name, string value, bool expand)
        {
            static string Quote(string t) => "\"" + t.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
            if (!expand) return Quote(name) + "=" + Quote(value);
            var bytes = System.Text.Encoding.Unicode.GetBytes(value + "\0");
            return Quote(name) + "=hex(2):" + string.Join(",", bytes.Select(b => b.ToString("x2")));
        }

        // der Name, unter dem man ein Programm kennt: Beschreibung der Programmdatei, sonst der Name des Eintrags
        public static string Title(string name, string? description)
        {
            string plain = Regex.Replace(name ?? "", @"\.lnk$", "", RegexOptions.IgnoreCase);
            return !string.IsNullOrWhiteSpace(description) && description!.Trim().Length <= 40 ? description.Trim() : plain;
        }
    }

    public static class Spielcheck
    {
        // wie Get-GameScore: grün 2, gelb 1, rot 0; graue Punkte (leer) zählen nicht
        public static int? Score(IEnumerable<string> tones)
        {
            var rated = tones.Where(t => !string.IsNullOrEmpty(t)).ToList();
            if (rated.Count == 0) return null;
            int points = rated.Sum(t => t == "good" ? 2 : t == "warn" ? 1 : 0);
            return (int)Math.Round(points * 100.0 / (rated.Count * 2), MidpointRounding.AwayFromZero);
        }

        static readonly string[] FastPlans = { "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "e9a42b02-d5df-448d-aa00-03f14749eb61" };

        // Energieplan: good = Höchstleistung, bad = Energiesparen, warn = Ausbalanciert (auf dem Notebook good)
        public static string PlanTone(string guid, string name, bool battery)
        {
            if (FastPlans.Contains(guid.ToLowerInvariant()) || Regex.IsMatch(name, "Höchstleistung|Ultimat|High performance|Ultimate|Hohe Leistung|Bitsum", RegexOptions.IgnoreCase)) return "good";
            if (guid.ToLowerInvariant() == "a1841308-3541-4fab-bc81-f71556f20b4a" || Regex.IsMatch(name, "Energiespar|Power saver", RegexOptions.IgnoreCase)) return "bad";
            return name.Length == 0 ? "" : battery ? "good" : "warn";
        }

        // powercfg /getactivescheme: GUID und Name in Klammern
        public static (string Guid, string Name) ActivePlan(string? output)
        {
            var m = Regex.Match(output ?? "", @"([0-9a-fA-F\-]{36})\s+\((.+)\)");
            return m.Success ? (m.Groups[1].Value.ToLowerInvariant(), m.Groups[2].Value.Trim()) : ("", "");
        }

        // nvidia-smi -q -d MEMORY: Größe des Fensters BAR1 in MiB (mit Resizable BAR so groß wie der Grafikspeicher)
        public static int? Bar1(string? output)
        {
            var m = Regex.Match(output ?? "", @"BAR1 Memory Usage\s+Total\s*:\s*(\d+)\s*MiB");
            return m.Success ? int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) : (int?)null;
        }

        // Spielebibliotheken: der Ordnername ist der Name des Spiels
        public static string GameName(string path)
        {
            var m = Regex.Match(path ?? "", @"\\(?:steamapps\\common|Epic Games|GOG Galaxy\\Games|XboxGames)\\([^\\]+)\\", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value : "";
        }
    }
}
