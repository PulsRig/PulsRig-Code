// PulsRig.Core - Bausteine für Treibersicherung, Wiederherstellen und Gerätefehler, abgelöst aus
// Treiber-Werkzeuge.ps1 und Treiber-Scan.ps1. pnputil, CIM und alle Eingriffe bleiben in PowerShell.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace PulsRig.Core
{
    public sealed class TreiberPaket
    {
        public string Published { get; set; } = "";
        public string Original { get; set; } = "";
        public string Provider { get; set; } = "";
    }

    public static class Sicherung
    {
        // Ordner, aus denen "Wiederherstellen" Treiber einspielen kann
        public static bool IsBackupFolder(string? name) =>
            name != null && (name.StartsWith("Backup_", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Offline-Paket_", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Auto-Sicherung_", StringComparison.OrdinalIgnoreCase)
                || name.StartsWith("Einzeltreiber_", StringComparison.OrdinalIgnoreCase));

        // Antwort auf "Nummer der Sicherung": 1..count, sonst die neueste (Index 0)
        public static int PickIndex(string? answer, int count)
        {
            string text = (answer ?? "").Trim();
            if (text.Length == 0 || !text.All(char.IsDigit) || text.Length > 9) return 0;
            int number = int.Parse(text, CultureInfo.InvariantCulture);
            return number >= 1 && number <= count ? number - 1 : 0;
        }

        public static string AutoFolderName(DateTime time) =>
            "Auto-Sicherung_" + time.ToString("yyyy-MM-dd_HHmm", CultureInfo.InvariantCulture);

        // Vor einem Update gesichert werden nur Pakete von Drittherstellern (oemNN.inf), jedes einmal
        public static string[] PackagesToBackup(IEnumerable<string?>? infNames) =>
            (infNames ?? Enumerable.Empty<string?>())
                .Where(name => name != null && name.StartsWith("oem", StringComparison.OrdinalIgnoreCase)
                    && name.EndsWith(".inf", StringComparison.OrdinalIgnoreCase))
                .Select(name => name!.ToLowerInvariant()).Distinct().OrderBy(name => name, StringComparer.Ordinal).ToArray();

        // wie PulsRig-Arbeit-Export.ps1: "Einzeltreiber_oem12_2026-10-26_1430"
        public static string SingleFolderName(string inf, DateTime time) =>
            "Einzeltreiber_" + FolderName(inf) + "_" + time.ToString("yyyy-MM-dd_HHmm", CultureInfo.InvariantCulture);

        public static string FolderName(string original) =>
            original.EndsWith(".inf", StringComparison.OrdinalIgnoreCase) ? original.Substring(0, original.Length - 4) : original;

        // oemNN.inf -> ursprünglicher Name, aus der (übersetzten) Ausgabe von "pnputil /enum-drivers" nach Position gelesen
        public static TreiberPaket[] ParsePackages(IEnumerable<string?>? lines)
        {
            var result = new List<TreiberPaket>();
            var values = new List<string>();
            void Flush()
            {
                if (values.Count >= 3 && System.Text.RegularExpressions.Regex.IsMatch(values[0], @"^oem\d+\.inf$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                    result.Add(new TreiberPaket { Published = values[0], Original = values[1], Provider = values[2] });
                values.Clear();
            }
            int empty = 0;
            foreach (string? raw in lines ?? Enumerable.Empty<string?>())
            {
                string line = raw ?? "";
                // wie bisher trennt nur eine wirklich leere Zeile die Blöcke
                if (line.Length == 0) { if (++empty == 1) Flush(); continue; }
                empty = 0;
                int colon = line.IndexOf(':');
                if (colon >= 0) values.Add(line.Substring(colon + 1).Trim());
            }
            Flush();
            return result.ToArray();
        }
    }

    public sealed class FehlerInfo
    {
        public string Text { get; set; } = "";
        public string Fix { get; set; } = "";
        public string Advice { get; set; } = "";
    }

    public static class Geraetefehler
    {
        // Fehlercodes des Geräte-Managers: Bedeutung und wo die Abhilfe liegt.
        //   Driver = Treiber erneuern, Reboot = Neustart genügt, Firmware = BIOS oder Hardware, Disabled, Info = kein Fehler
        static readonly Dictionary<int, string[]> Codes = new Dictionary<int, string[]>
        {
            [1] = new[] { "falsch konfiguriert", "Driver" },
            [3] = new[] { "Treiber beschädigt oder zu wenig Speicher", "Driver" },
            [9] = new[] { "Gerätekennung ungültig", "Firmware" },
            [10] = new[] { "Gerät kann nicht gestartet werden", "Driver" },
            [12] = new[] { "nicht genug freie Ressourcen (Konflikt)", "Firmware" },
            [14] = new[] { "Neustart erforderlich", "Reboot" },
            [16] = new[] { "Ressourcen nicht vollständig erkannt", "Firmware" },
            [18] = new[] { "Treiber muss neu installiert werden", "Driver" },
            [19] = new[] { "Registrierungseinträge des Geräts beschädigt", "Driver" },
            [21] = new[] { "Gerät wird gerade entfernt", "Reboot" },
            [22] = new[] { "deaktiviert", "Disabled" },
            [24] = new[] { "Gerät fehlt oder ist fehlerhaft", "Driver" },
            [28] = new[] { "kein Treiber installiert", "Driver" },
            [29] = new[] { "im BIOS deaktiviert", "Firmware" },
            [31] = new[] { "Treiber kann nicht geladen werden", "Driver" },
            [32] = new[] { "Treiberdienst deaktiviert", "Driver" },
            [33] = new[] { "benötigte Ressourcen nicht ermittelbar", "Firmware" },
            [34] = new[] { "muss von Hand konfiguriert werden", "Firmware" },
            [35] = new[] { "BIOS liefert zu wenig Angaben zum Gerät", "Firmware" },
            [36] = new[] { "Interrupt-Konflikt", "Firmware" },
            [37] = new[] { "Treiber konnte nicht initialisiert werden", "Driver" },
            [38] = new[] { "alte Treiberinstanz noch im Speicher", "Reboot" },
            [39] = new[] { "Treiber fehlt oder ist beschädigt", "Driver" },
            [40] = new[] { "Registrierungseintrag des Treiberdienstes fehlerhaft", "Driver" },
            [41] = new[] { "Treiber geladen, Gerät aber nicht gefunden", "Driver" },
            [42] = new[] { "doppeltes Gerät erkannt", "Reboot" },
            [43] = new[] { "Gerät hat einen Fehler gemeldet", "Driver" },
            [44] = new[] { "von einem Programm oder Dienst angehalten", "Reboot" },
            [45] = new[] { "nicht angeschlossen", "Info" },
            [46] = new[] { "Windows fährt gerade herunter", "Reboot" },
            [47] = new[] { "zum sicheren Entfernen vorbereitet", "Reboot" },
            [48] = new[] { "Treiber von Windows wegen bekannter Probleme blockiert", "Driver" },
            [49] = new[] { "Registrierung zu groß", "Info" },
            [50] = new[] { "Einstellungen des Geräts nicht anwendbar", "Driver" },
            [51] = new[] { "wartet auf ein anderes Gerät", "Reboot" },
            [52] = new[] { "Treibersignatur ungültig", "Driver" },
            [53] = new[] { "für den Kernel-Debugger reserviert", "Info" },
            [54] = new[] { "Gerät ausgefallen, wird zurückgesetzt", "Reboot" },
        };

        static readonly Dictionary<string, string> Advices = new Dictionary<string, string>
        {
            ["Driver"] = "Treiber erneuern",
            ["Reboot"] = "PC neu starten",
            ["Firmware"] = "BIOS und Hardware prüfen",
            ["Disabled"] = "im Geräte-Manager aktivieren",
            ["Info"] = "-",
        };

        public static FehlerInfo Get(int code)
        {
            string[] entry = Codes.TryGetValue(code, out string[]? known) ? known : new[] { "unbekannter Fehler", "Driver" };
            return new FehlerInfo { Text = entry[0], Fix = entry[1], Advice = Advices[entry[1]] };
        }
    }
}
