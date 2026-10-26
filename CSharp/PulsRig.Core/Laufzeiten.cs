// PulsRig.Core - Bewertung der Laufzeitbibliotheken für Spiele ("Fehlende Spiel-DLLs beheben"), abgelöst aus
// Get-RuntimeStatus in Treiber-Werkzeuge.ps1. Die Einträge aus der Registry liest weiter PowerShell.
using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public sealed class LaufzeitStatus
    {
        public string Status { get; set; } = "fehlt";     // vorhanden, veraltet, fehlt
        public string Version { get; set; } = "";
    }

    public static class Laufzeiten
    {
        // Pakete, die keine Laufzeit sind, obwohl "Visual C++" im Namen steht
        public static bool IsRuntimeEntry(string? displayName) =>
            displayName != null && Regex.IsMatch(displayName, @"Visual C\+\+", RegexOptions.IgnoreCase)
            && !Regex.IsMatch(displayName, "Minimum|Additional|Debug", RegexOptions.IgnoreCase);

        // names/versions: DisplayName und DisplayVersion der installierten Einträge (gleich lang); pattern: Muster der
        // Fassung (etwa "Visual C\+\+ 2013 Redistributable"); latest: letzte veröffentlichte Version oder leer
        public static LaufzeitStatus Evaluate(IList<string> names, IList<string> versions, string pattern, bool x64, string? latest)
        {
            var result = new LaufzeitStatus();
            bool any = false;
            Version? best = null;
            for (int i = 0; i < names.Count; i++)
            {
                string name = names[i] ?? "";
                if (!IsRuntimeEntry(name) || !Regex.IsMatch(name, pattern, RegexOptions.IgnoreCase)) continue;
                if (Regex.IsMatch(name, "x64", RegexOptions.IgnoreCase) != x64) continue;
                any = true;
                if (i < versions.Count && System.Version.TryParse(versions[i], out Version? version) && (best == null || version > best)) best = version;
            }
            if (!any) return result;
            result.Status = "vorhanden";
            result.Version = best?.ToString() ?? "";
            if (!string.IsNullOrEmpty(latest) && best != null && best < System.Version.Parse(latest)) result.Status = "veraltet";
            return result;
        }
    }
}
