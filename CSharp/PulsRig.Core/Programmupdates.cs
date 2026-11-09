// PulsRig.Core - Programm-Updates per winget: liest die Tabelle aus "winget upgrade" (Kopfzeile, Strichlinie,
// Zeilen) unabhängig von der Sprache - die Spalten ergeben sich aus den Anfängen der Wörter in der Kopfzeile.
// Angeboten wird nur, was aus der Quelle "winget" kommt; der Microsoft Store verlangt eine eigene Anmeldung.
using System;
using System.Collections.Generic;
using System.Linq;

namespace PulsRig.Core
{
    public sealed class Programmupdate
    {
        public string Name = "", Id = "", Version = "", Available = "", Source = "";
    }

    public static class Programmupdates
    {
        // Rückgabe von "winget upgrade --id": 0 aktualisiert; 0x8A15002B keine neuere Fassung passt;
        // 0x8A150061 Programm läuft gerade (Installer kann es nicht ersetzen)
        public static (bool Ok, string Text) Result(int code) => code switch
        {
            0 => (true, "aktualisiert"),
            -1978335189 => (true, "schon aktuell"),
            -1978335135 => (false, "läuft gerade – erst schließen"),
            _ => (false, "fehlgeschlagen (winget-Code " + code + ")"),
        };

        public static List<Programmupdate> Parse(string output)
        {
            var list = new List<Programmupdate>();
            // winget schreibt Fortschrittszeichen mit \r davor; jeweils nur das Letzte einer Zeile zählt
            var lines = (output ?? "").Replace("\r\n", "\n").Split('\n').Select(l => l.LastIndexOf('\r') is var r && r >= 0 ? l.Substring(r + 1) : l).ToList();
            var dash = lines.FindIndex(l => l.Trim().Length >= 10 && l.Trim().All(c => c == '-'));
            if (dash < 1) return list;
            var header = lines[dash - 1];
            var starts = new List<int>();
            for (var i = 0; i < header.Length; i++)
                if (header[i] != ' ' && (i == 0 || header[i - 1] == ' ')) starts.Add(i);
            if (starts.Count < 4) return list;
            for (var n = dash + 1; n < lines.Count; n++)
            {
                var line = lines[n];
                // Ende der ersten Tabelle: Leerzeile oder Fußzeile ("3 Aktualisierungen verfügbar.") ohne Spalten
                if (line.Trim().Length == 0 || line.Length <= starts[2]) break;
                string Cell(int c) => starts[c] >= line.Length ? "" : (c + 1 < starts.Count && starts[c + 1] <= line.Length
                    ? line.Substring(starts[c], starts[c + 1] - starts[c]) : line.Substring(starts[c])).Trim();
                var u = new Programmupdate { Name = Cell(0), Id = Cell(1), Version = Cell(2), Available = starts.Count > 3 ? Cell(3) : "", Source = starts.Count > 4 ? Cell(4) : "" };
                if (u.Id.Length == 0 || u.Id.IndexOf(' ') >= 0 || u.Available.Length == 0) continue;
                list.Add(u);
            }
            return list;
        }

        // nur Kennungen, die winget sicher als Argument bekommt
        public static bool IsSafeId(string id) => id.Length is > 0 and <= 128 && id.All(c => char.IsLetterOrDigit(c) || c is '.' or '-' or '_' or '+');
    }
}
