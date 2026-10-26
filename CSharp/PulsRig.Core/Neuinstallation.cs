using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    // Neuinstallations-Begleiter wie PulsRig-Neuinstallation.ps1: vorher ein Ordner "Neuinstallation_<Datum>" mit
    // Offline-Treiberpaket und Programme.json aus "winget export", danach geführt wieder einspielen.
    public static class Neuinstallation
    {
        public const string Prefix = "Neuinstallation_";

        public static string FolderName(DateTime now) => Prefix + now.ToString("yyyy-MM-dd_HHmm", CultureInfo.InvariantCulture);

        // aus "Mozilla.Firefox" wird zum Anzeigen "Firefox", aus "Valve.Steam.Beta" "Steam Beta"
        public static string ProgramName(string id)
        {
            var match = Regex.Match(id, @"^[^.]+\.(.+)$");
            return match.Success ? match.Groups[1].Value.Replace('.', ' ') : id;
        }

        // Paketkennungen aus Programme.json (winget export), ohne Doppelte, nach Namen sortiert
        public static List<(string Id, string Name)> Programs(string json)
        {
            var ids = Regex.Matches(json ?? "", "\"PackageIdentifier\"\\s*:\\s*\"([^\"]+)\"").Cast<Match>().Select(m => m.Groups[1].Value.Trim()).Where(s => s.Length > 0);
            return ids.Distinct(StringComparer.OrdinalIgnoreCase).Select(id => (id, ProgramName(id))).OrderBy(p => p.Item2, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        public static string[] Readme(DateTime created) => new[]
        {
            "Sicherung für eine Neuinstallation vom " + created.ToString("dd.MM.yyyy HH:mm", CultureInfo.InvariantCulture),
            "",
            "1. Diesen Ordner vor der Neuinstallation auf einen USB-Stick oder ein anderes Laufwerk kopieren.",
            "2. Nach der Neuinstallation PulsRig starten: Werkzeuge → Neuinstallation → Danach einspielen.",
            "   Ohne PulsRig: im Offline-Paket \"Treiber-installieren.bat\" doppelt anklicken.",
            "3. Programme.json listet die Programme, die winget kennt. PulsRig bietet sie zum Abhaken an;",
            "   ohne PulsRig: winget import -i Programme.json",
            "",
            "Eigene Dateien, Spielstände und Einstellungen anderer Programme sind hier nicht enthalten.",
        };

        // Ergebnis von "winget install"; -1978335189: schon installiert, keine neuere Fassung
        public static (bool Ok, string Text) WingetResult(int code) => code switch
        {
            0 => (true, "installiert"),
            -1978335189 => (true, "schon vorhanden"),
            _ => (false, "fehlgeschlagen (winget-Code " + code + ")"),
        };
    }

    // Notfall-Stick wie Mode Stick in PulsRig-Arbeit-Neuinstallation.ps1: PulsRig ohne Installation in <Stick>\PulsRig,
    // das Offline-Paket der Treiber dieses PCs in dessen Ordner Treiber. Andere Dateien auf dem Stick bleiben.
    public static class Notfallstick
    {
        public const string ReadmeName = "LIESMICH-Notfall-Stick.txt";

        // das Treiberpaket braucht je nach PC 1 bis 4 GB; genau prüft es die Schätzung vor dem Export
        public const long Small = 4L << 30;

        // aus dem Programmordner (PulsRig.exe, App\, Sensoren\ …) alles außer dem Deinstaller
        public static bool Copies(string name, bool folder) =>
            folder ? name.Equals("App", StringComparison.OrdinalIgnoreCase) || name.Equals("Sensoren", StringComparison.OrdinalIgnoreCase)
                   : !name.StartsWith("unins", StringComparison.OrdinalIgnoreCase);

        public static string Label(string drive, string volumeLabel) =>
            (volumeLabel ?? "").Length > 0 ? volumeLabel + " (" + drive.TrimEnd('\\') + ")" : "USB-Stick (" + drive.TrimEnd('\\') + ")";

        public static string[] Readme(DateTime created, string computer) => new[]
        {
            "PulsRig-Notfall-Stick vom " + created.ToString("dd.MM.yyyy HH:mm", CultureInfo.InvariantCulture) + " für den PC " + computer,
            "",
            "Starten: im Ordner PulsRig die Datei PulsRig.exe doppelt anklicken - ohne Installation.",
            "Ergebnisse und geladene Treiber landen auf dem Stick im Ordner Treiber.",
            "",
            "Kein Internet, weil der Netzwerktreiber fehlt?",
            "   Treiber\\Offline-Paket_…\\Treiber-installieren.bat doppelt anklicken und danach neu starten.",
            "   Die Treiber passen zu genau diesem PC.",
        };
    }
}
