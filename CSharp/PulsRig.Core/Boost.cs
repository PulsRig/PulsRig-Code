// PulsRig.Core - welche Dienste der automatische Boost anhalten darf, abgelöst aus New-AutoBoostPlan in
// Treiber-Werkzeuge.ps1. Das Anhalten selbst bleibt in PowerShell.
//
// Tabu: die Auswahl kommt aus der Einstellungsdatei im Benutzerordner und gilt darum nicht ungeprüft. Erlaubt sind nur
// Dienste aus der eigenen Liste oder Dienste anderer Hersteller (Programmdatei außerhalb von Windows). Programme
// schließt der automatische Boost nie - das steht in PowerShell fest (Apps = leer), hier gibt es dafür nichts.
using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public static class Boost
    {
        static readonly Regex SafeName = new Regex(@"^[\w.\- ]{1,80}$");

        // wie $script:BoostServices: Dienste, die beim Spielen nichts beitragen; sie werden nur angehalten, nie deaktiviert
        public static readonly string[] Services = { "WSearch", "SysMain", "Spooler", "DiagTrack", "MapsBroker", "Fax", "WerSvc", "stisvc", "DoSvc" };

        // wie $script:BoostKeep: Programme, die nie zum Schließen angeboten werden (Windows, Spiele-Starter, Grafiktreiber)
        public static readonly string[] Keep =
        {
            "explorer", "dwm", "sihost", "ShellHost", "StartMenuExperienceHost", "ShellExperienceHost", "SearchHost",
            "TextInputHost", "RuntimeBroker", "svchost", "taskhostw", "ctfmon", "conhost", "cmd", "powershell", "pwsh",
            "WindowsTerminal", "OpenConsole", "ApplicationFrameHost", "SystemSettings", "LockApp", "dllhost", "fontdrvhost",
            "csrss", "winlogon", "smartscreen", "SecurityHealthSystray", "msedgewebview2", "Widgets", "WidgetService",
            "steam", "steamwebhelper", "EpicGamesLauncher", "EpicWebHelper", "Battle.net", "EADesktop", "EABackgroundService",
            "Origin", "GalaxyClient", "GalaxyClient Helper", "upc", "UbisoftConnect", "RiotClientServices", "RiotClientUx",
            "nvcontainer", "NVDisplay.Container", "NVIDIA app", "NVIDIA Overlay", "RadeonSoftware", "AMDRSServ", "PulsRig", "PulsRig.App",
        };

        // wie $script:BoostSuggestApps: Programme, die "Boost einrichten" zum Schließen vorschlägt
        public static readonly string[] SuggestApps = { "Spotify", "OneDrive", "Teams", "ms-teams", "Skype", "Dropbox", "GoogleDriveFS", "iCloudDrive",
            "Creative Cloud", "CCXProcess", "PhoneExperienceHost", "YourPhone", "Zoom", "Slack", "Telegram", "WhatsApp" };

        // wie $script:BoostServiceKeep: Dienste anderer Hersteller, die nie angeboten werden (Grafik, Ton, Kopierschutz,
        // Spiele-Starter, Schutzprogramme, Netz, Eingabegeräte, virtuelle Maschinen)
        static readonly Regex ServiceKeep = new Regex(@"NVIDIA|\bNv|\bAMD\b|Radeon|Intel|Audio|Realtek|Rtk|Nahimic|Sonic|Dolby|DTS|THX|AntiCheat|^BEService|\bvgc\b|\bvgk\b|FACEIT|" +
            @"Steam|Epic|Origin|\bEA\b|Ubisoft|Rockstar|Battle\.net|GOG|Xbox|Gaming|GameInput|Play Games|Defend|Antivir|Security|Firewall|Bitdefender|Kaspersky|ESET|Avast|AVG|" +
            @"Norton|McAfee|Malware|VPN|Bluetooth|WLAN|Wi-?Fi|Ethernet|Killer|Thunderbolt|USB|HID|Synaptics|Wacom|VMware|VirtualBox|Docker|Hyper-V");

        // text: "Name Anzeigename Hersteller" wie in Get-BoostChoices
        public static bool IsServiceKept(string? text) => ServiceKeep.IsMatch(text ?? "");

        public static bool IsKept(string? name)
        {
            foreach (string keep in Keep) if (string.Equals(keep, name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        // powercfg /list: GUID, Name in Klammern, Stern für den aktiven Plan
        public static List<(string Guid, string Name, bool Active)> Plans(IEnumerable<string>? lines)
        {
            var plans = new List<(string, string, bool)>();
            foreach (string line in lines ?? new string[0])
            {
                var m = Regex.Match(line ?? "", @"([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\s+\((.+)\)\s*(\*?)", RegexOptions.IgnoreCase);
                if (m.Success) plans.Add((m.Groups[1].Value.ToLowerInvariant(), m.Groups[2].Value, m.Groups[3].Value.Length > 0));
            }
            return plans;
        }

        public const string Performance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";

        // wie Invoke-GameBoostTool: schon schnell, wenn der Plan nach Leistung klingt oder Höchstleistung ist
        public static bool IsFast(string guid, string name) =>
            string.Equals(guid, Performance, StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(name ?? "", "leistung|performance", RegexOptions.IgnoreCase);

        // nur Namen, die sich gefahrlos in eine WMI-Abfrage setzen lassen
        public static bool IsSafeName(string? name) => name != null && SafeName.IsMatch(name);

        // known: die eigene Liste ($script:BoostServices); pathName: Befehlszeile des Dienstes oder leer, wenn es ihn
        // nicht gibt; windir: Windows-Ordner
        public static bool IsAllowed(string? name, IEnumerable<string> known, string? pathName, string windir)
        {
            if (!IsSafeName(name)) return false;
            foreach (string entry in known) if (string.Equals(entry, name, StringComparison.OrdinalIgnoreCase)) return true;
            if (string.IsNullOrEmpty(pathName) || string.IsNullOrEmpty(windir)) return false;
            return pathName!.IndexOf(windir, StringComparison.OrdinalIgnoreCase) < 0;
        }
    }
}
