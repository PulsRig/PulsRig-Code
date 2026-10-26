// PulsRig.Core - reine Prüfungen der Werkzeuge, abgelöst aus Treiber-Werkzeuge.ps1. Was etwas ändert (Treiber
// installieren, Geräte entfernen, Auflösung setzen), bleibt in PowerShell; hier steht nur, was erlaubt ist.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public static class Downloads
    {
        // Geladen wird nur über https und nur von erlaubten Rechnern (Muster wie "*.nvidia.com", wie -like in PowerShell)
        public static bool IsAllowed(string? url, IEnumerable<string>? allowedHosts)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out Uri? uri) || uri.Scheme != Uri.UriSchemeHttps) return false;
            foreach (string pattern in allowedHosts ?? Enumerable.Empty<string>())
            {
                if (string.IsNullOrEmpty(pattern)) continue;
                string regex = "^" + Regex.Escape(pattern).Replace(@"\*", ".*").Replace(@"\?", ".") + "$";
                if (Regex.IsMatch(uri.Host, regex, RegexOptions.IgnoreCase)) return true;
            }
            return false;
        }
    }

    public static class Treiber
    {
        // Prüft den Aufbau einer Treiberdatei gegen die Regeln der Kernisolierung (Speicher-Integrität): kein Abschnitt
        // darf zugleich beschreibbar und ausführbar sein, und alle müssen seitenweise ausgerichtet sein. Eine Prüfung der
        // Datei, nicht des laufenden Treibers. Keine PE-Datei oder kein Zugriff: keine Beanstandung.
        public static string[] HvciIssues(string path)
        {
            var issues = new List<string>();
            try
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                using var reader = new BinaryReader(stream);
                if (stream.Length < 0x100 || reader.ReadUInt16() != 0x5A4D) return issues.ToArray();
                stream.Position = 0x3C;
                int pe = reader.ReadInt32();
                if (pe <= 0 || pe + 0x108 > stream.Length) return issues.ToArray();
                stream.Position = pe;
                if (reader.ReadUInt32() != 0x4550) return issues.ToArray();
                stream.Position = pe + 6;
                int sections = reader.ReadUInt16();
                stream.Position = pe + 20;
                int optionalSize = reader.ReadUInt16();
                stream.Position = pe + 24 + 32;
                if (reader.ReadUInt32() < 0x1000) issues.Add("Abschnitte nicht seitenweise ausgerichtet");
                for (int i = 0; i < sections; i++)
                {
                    stream.Position = pe + 24 + optionalSize + 40 * i;
                    string name = Encoding.ASCII.GetString(reader.ReadBytes(8)).Trim('\0');
                    stream.Position += 28;
                    uint flags = reader.ReadUInt32();
                    // Abschnitte, die Windows nach dem Start verwirft (meist INIT), zählen nicht: viele mit Windows
                    // gelieferte Treiber haben sie so, und Windows beanstandet sie nicht
                    bool discardable = (flags & 0x02000000) != 0;
                    if ((flags & 0x20000000) != 0 && (flags & 0x80000000) != 0 && !discardable)
                        issues.Add($"Abschnitt {name} ist zugleich beschreibbar und ausführbar");
                }
            }
            catch (Exception) { }   // abgeschnittene oder gesperrte Datei: was bis dahin gefunden ist, gilt
            return issues.ToArray();
        }

        // Pfad eines Kerneltreibers aus Win32_SystemDriver.PathName: \??\, \SystemRoot\ und System32\ auflösen
        public static string ResolveDriverPath(string? pathName, string windir)
        {
            string path = Regex.Replace((pathName ?? "").Trim('"'), @"^\\\?\?\\", "");
            if (path.StartsWith(@"\SystemRoot\", StringComparison.OrdinalIgnoreCase)) return Path.Combine(windir, path.Substring(12));
            if (path.StartsWith(@"System32\", StringComparison.OrdinalIgnoreCase)) return Path.Combine(windir, path);
            return path;
        }

        // Pfad der Programmdatei eines Dienstes aus seiner Befehlszeile
        public static string ResolveServicePath(string? pathName)
        {
            string text = pathName ?? "";
            var match = Regex.Match(text, "^\\s*\"([^\"]+)\"");
            if (match.Success) return match.Groups[1].Value;
            match = Regex.Match(text, @"^\s*(.+?\.exe)", RegexOptions.IgnoreCase);
            return match.Success ? match.Groups[1].Value : text;
        }
    }

    public static class Geraete
    {
        // Einträge nicht mehr angeschlossener Hardware, die bereinigt werden dürfen. Bewusst eng gefasst: Bluetooth-
        // Kopplungen, Drucker und (virtuelle) Netzwerkadapter sind oft nur gerade aus und bleiben unangetastet.
        public static bool IsCleanable(bool present, string? instanceId, string? deviceClass)
        {
            if (present || instanceId == null) return false;
            if (!Regex.IsMatch(instanceId, @"^(USB|USBSTOR|HID|SCSI|STORAGE|DISPLAY|HDAUDIO|SWD\\WPDBUSENUM)\\", RegexOptions.IgnoreCase)) return false;
            if (Regex.IsMatch(instanceId, @"BTH|\{0000[0-9A-F]{4}-0000-1000-8000-00805F9B34FB\}", RegexOptions.IgnoreCase)) return false;
            string[] keep = { "Bluetooth", "Net", "Printer", "PrintQueue" };
            return !keep.Contains(deviceClass ?? "", StringComparer.OrdinalIgnoreCase);
        }

        // ein Name für die Geräteklasse, unter dem man sich etwas vorstellen kann
        public static string Group(string? deviceClass) => (deviceClass ?? "").ToLowerInvariant() switch
        {
            "hidclass" or "keyboard" or "mouse" => "Eingabegeräte",
            "usb" => "USB-Geräte und Hubs",
            "diskdrive" or "wpd" or "volume" or "cdrom" => "Speicher und Laufwerke",
            "media" or "audioendpoint" => "Audio",
            "display" or "monitor" => "Grafik und Bildschirme",
            "camera" or "image" => "Kameras",
            "" => "Ohne Geräteklasse",
            _ => deviceClass!,
        };
    }

    public static class Anzeige
    {
        // Bildwiederholrate für die empfohlene Auflösung: die aktuelle, sonst 60 Hz, sonst die höchste; 0 = keine
        public static int SelectRefreshRate(IEnumerable<int> nativeRates, int current)
        {
            var rates = nativeRates.Distinct().OrderBy(r => r).ToList();
            if (rates.Count == 0) return 0;
            if (current > 0 && rates.Contains(current)) return current;
            if (rates.Contains(60)) return 60;
            return rates[rates.Count - 1];
        }
    }
}
