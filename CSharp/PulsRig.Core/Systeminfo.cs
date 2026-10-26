// PulsRig.Core - Bausteine für Systeminformationen, Offline-Treiberpaket und Treiberverlauf, abgelöst aus
// Treiber-Werkzeuge.ps1. Die Abfragen (CIM, Registry, Windows Update, pnputil) bleiben in PowerShell; hier steht,
// wie die Rohwerte gelesen und in Wörter gefasst werden.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public static class Systeminfo
    {
        // Eigenbau-PCs tragen statt eines Herstellers Platzhalter aus dem BIOS
        public static bool IsPlaceholder(string? manufacturer) =>
            Regex.IsMatch(manufacturer ?? "", "To Be Filled|System manufacturer|Default string", RegexOptions.IgnoreCase);

        // unknown: das Wort für "weder SSD noch Festplatte" - im Text "Laufwerk", in der Tabelle "unbekannt"
        public static string DiskType(string? mediaType, string unknown) =>
            mediaType == "SSD" ? "SSD" : mediaType == "HDD" ? "Festplatte" : unknown;

        public static string Health(string? healthStatus) => healthStatus == "Healthy" ? "in Ordnung" : healthStatus ?? "";

        // Win32_VideoController kennt höchstens 4 GB - die echte Größe steht in der Registry (qwMemorySize)
        public static long GpuMemory(long registryBytes, long adapterRam) => registryBytes > 0 ? registryBytes : adapterRam;

        // DriverDate der Grafikkarte in der Registry, etwa "10-3-2026"
        public static DateTime? DriverDate(string? text) =>
            DateTime.TryParseExact(text ?? "", "M-d-yyyy", CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime date) ? date : (DateTime?)null;

        public static bool IsThirdParty(string? provider) =>
            !string.IsNullOrEmpty(provider) && !provider!.StartsWith("Microsoft", StringComparison.OrdinalIgnoreCase);
    }

    public static class OfflinePaket
    {
        // Ursprüngliche Namen der Treiberpakete aus "pnputil /enum-drivers" (deutsch und englisch), ohne Doppelte
        public static string[] OriginalNames(IEnumerable<string>? lines)
        {
            var names = new List<string>();
            foreach (string line in lines ?? Enumerable.Empty<string>())
            {
                var match = Regex.Match(line ?? "", @"^\s*Original\s?name\s*:\s*(\S+\.inf)\s*$", RegexOptions.IgnoreCase);
                if (match.Success && !names.Contains(match.Groups[1].Value)) names.Add(match.Groups[1].Value);
            }
            return names.ToArray();
        }

        // Startdatei im Paket: holt sich Adminrechte und spielt alle Treiber ein (nur ASCII, cmd liest kein UTF-8)
        public static string[] Starter() => new[]
        {
            "@echo off",
            "rem Spielt alle Treiber aus dem Ordner \"Treiber\" ein. Fordert dafuer Adminrechte an.",
            "fltmc >nul 2>&1",
            "if errorlevel 1 (",
            "    powershell.exe -NoProfile -Command \"Start-Process -FilePath '%~f0' -Verb RunAs\"",
            "    exit /b",
            ")",
            "pnputil.exe /add-driver \"%~dp0Treiber\\*.inf\" /subdirs /install",
            "echo.",
            "echo Fertig. Bitte den PC neu starten.",
            "pause",
        };

        public static string[] Readme(DateTime created) => new[]
        {
            "Offline-Treiberpaket vom " + created.ToString("dd.MM.yyyy HH:mm", CultureInfo.InvariantCulture),
            "",
            "1. Diesen Ordner auf einen USB-Stick kopieren.",
            "2. Nach der Neuinstallation von Windows \"Treiber-installieren.bat\" doppelt anklicken",
            "   und die Abfrage der Adminrechte bestätigen.",
            "3. Den PC neu starten.",
            "",
            "Die Treiber passen zu genau diesem PC. Welche enthalten sind, steht in Hardware-Bericht.csv.",
        };

        // Meldung, wenn pnputil beim Export scheitert; 112 heißt: Datenträger voll
        public static string ExportError(int code) => code == 112
            ? "Der Export ist abgebrochen: Auf dem Ziellaufwerk ist kein Platz mehr."
            : $"Der Export ist fehlgeschlagen (pnputil-Code {code}).";
    }

    public static class Verlauf
    {
        // Treiber heißen bei Windows Update "Hersteller - Klasse - Version"
        public static bool IsDriverUpdate(string? title) =>
            !string.IsNullOrEmpty(title) && (Regex.IsMatch(title, @" - [^-]+ - \d+(\.\d+){2,}\s*$")
                || Regex.IsMatch(title, "driver|treiber|firmware", RegexOptions.IgnoreCase));

        public static string Result(int resultCode) => resultCode switch
        {
            2 => "installiert",
            3 => "mit Hinweisen",
            4 => "fehlgeschlagen",
            5 => "abgebrochen",
            _ => "unvollständig",
        };

        // Geräte eines Treiberpakets: zwei mit Namen, der Rest gezählt
        public static string Devices(IList<string> names) => names.Count > 2
            ? $"{names[0]}, {names[1]} und {names.Count - 2} weitere"
            : string.Join(", ", names);
    }
}
