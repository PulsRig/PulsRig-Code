using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace PulsRig.Core
{
    // Ruckler-Detektiv ohne Bildzeiten: Der Helfer schreibt beim Spielen alle 5 Sekunden mit, welches Programm neben dem
    // Spiel am meisten rechnet, wie beschäftigt die Laufwerke sind, wie viel Zeit Treiber-Unterbrechungen kosten und wie
    // viel Arbeitsspeicher frei ist (PulsRig-Aufzeichnung.cs). Hier wird daraus, wann etwas dazwischengefunkt hat und wer
    // – dazu, was Windows zur selben Zeit protokolliert hat (Updates, Defender-Scans). Kurze Ruckler unter 5 Sekunden
    // können durchrutschen; das sagt die Seite auch so.
    public sealed class RucklerEreignis
    {
        public DateTime When { get; set; }
        // update oder defender
        public string Kind { get; set; } = "";
        public string Text { get; set; } = "";
    }

    public sealed class RucklerBefund
    {
        public string Title { get; set; } = "";
        public string Text { get; set; } = "";
        // warn oder leer
        public string Tone { get; set; } = "warn";
        // boost, defender, update, autostart, drivers, drives oder leer
        public string Action { get; set; } = "";
        // Sekunden der Sitzung, in denen es auffiel (für die Zeitleiste)
        public List<double> Seconds { get; set; } = new List<double>();
        public double Total { get; set; }
    }

    public sealed class RucklerErgebnis
    {
        public bool Supported { get; set; }
        public List<RucklerBefund> Findings { get; set; } = new List<RucklerBefund>();
        public string Summary { get; set; } = "";
    }

    public static class Ruckler
    {
        const double Step = 5;
        static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

        // Schwellen: ein Programm neben dem Spiel mit mehr als 12 % des ganzen Prozessors (bei vollem Prozessor schon
        // ab 6 %), Laufwerke zu 90 % beschäftigt, über 5 % Zeit für Treiber-Unterbrechungen, unter 800 MB frei
        public const double OtherLimit = 12, OtherLimitBusy = 6, DiskLimit = 90, DpcLimit = 5, RamLimit = 800;

        sealed class Bekannt
        {
            public Bekannt(string name, string text, string action) { Name = name; Text = text; Action = action; }
            public string Name { get; }
            public string Text { get; }
            public string Action { get; }
        }

        static readonly Dictionary<string, Bekannt> Known = new Dictionary<string, Bekannt>(StringComparer.OrdinalIgnoreCase)
        {
            ["MsMpEng"] = new Bekannt("Windows Defender", "Der Virenschutz prüft Dateien, oft während das Spiel nachlädt. In Windows-Sicherheit lässt sich der geplante Scan auf eine Zeit legen, zu der du nicht spielst.", "defender"),
            ["MpDefenderCoreService"] = new Bekannt("Windows Defender", "Der Virenschutz prüft Dateien, oft während das Spiel nachlädt.", "defender"),
            ["NisSrv"] = new Bekannt("Windows Defender (Netzwerkprüfung)", "Der Virenschutz prüft den Netzwerkverkehr.", "defender"),
            ["TiWorker"] = new Bekannt("Windows Update (Installation)", "Windows hat während des Spielens Updates eingerichtet. Unter Nutzungszeit legst du fest, wann Windows das nicht tun soll.", "update"),
            ["TrustedInstaller"] = new Bekannt("Windows Update (Installation)", "Windows hat während des Spielens Updates eingerichtet.", "update"),
            ["MoUsoCoreWorker"] = new Bekannt("Windows Update", "Windows hat nach Updates gesucht oder sie geladen.", "update"),
            ["usocoreworker"] = new Bekannt("Windows Update", "Windows hat nach Updates gesucht oder sie geladen.", "update"),
            ["wuauclt"] = new Bekannt("Windows Update", "Windows hat nach Updates gesucht oder sie geladen.", "update"),
            ["SearchIndexer"] = new Bekannt("Windows-Suche", "Die Suche hat neue Dateien eingelesen, etwa nach einem Spiel-Update.", ""),
            ["SearchProtocolHost"] = new Bekannt("Windows-Suche", "Die Suche hat neue Dateien eingelesen.", ""),
            ["CompatTelRunner"] = new Bekannt("Windows-Kompatibilitätsprüfung", "Windows sammelt Angaben über installierte Programme; läuft meist nur selten.", ""),
            ["OneDrive"] = new Bekannt("OneDrive", "OneDrive hat Dateien abgeglichen. Beim Spielen lässt es sich anhalten (Symbol neben der Uhr → Synchronisierung anhalten).", "autostart"),
            ["Dropbox"] = new Bekannt("Dropbox", "Dropbox hat Dateien abgeglichen.", "autostart"),
            ["GoogleDriveFS"] = new Bekannt("Google Drive", "Google Drive hat Dateien abgeglichen.", "autostart"),
            ["chrome"] = new Bekannt("Google Chrome", "Offene Tabs oder ein Video im Hintergrund kosten Rechenzeit.", "boost"),
            ["msedge"] = new Bekannt("Microsoft Edge", "Offene Tabs oder ein Video im Hintergrund kosten Rechenzeit.", "boost"),
            ["firefox"] = new Bekannt("Firefox", "Offene Tabs oder ein Video im Hintergrund kosten Rechenzeit.", "boost"),
            ["opera"] = new Bekannt("Opera", "Offene Tabs oder ein Video im Hintergrund kosten Rechenzeit.", "boost"),
            ["brave"] = new Bekannt("Brave", "Offene Tabs oder ein Video im Hintergrund kosten Rechenzeit.", "boost"),
            ["Discord"] = new Bekannt("Discord", "Overlay, Bildschirmübertragung oder animierte Inhalte kosten Rechenzeit.", "boost"),
            ["steamwebhelper"] = new Bekannt("Steam (Oberfläche)", "Das Steam-Fenster oder Overlay hat gerechnet.", "boost"),
            ["steam"] = new Bekannt("Steam", "Steam hat geladen oder Shader vorbereitet. Downloads lassen sich beim Spielen pausieren.", "boost"),
            ["EpicGamesLauncher"] = new Bekannt("Epic Games Launcher", "Der Launcher hat geladen oder aktualisiert.", "boost"),
            ["EADesktop"] = new Bekannt("EA App", "Die EA App hat geladen oder aktualisiert.", "boost"),
            ["Battle.net"] = new Bekannt("Battle.net", "Battle.net hat geladen oder aktualisiert.", "boost"),
            ["upc"] = new Bekannt("Ubisoft Connect", "Ubisoft Connect hat geladen oder aktualisiert.", "boost"),
            ["obs64"] = new Bekannt("OBS Studio", "Die Aufnahme braucht Rechenzeit; bei Rucklern auf Aufnahme über die Grafikkarte (NVENC/AMF) stellen.", ""),
        };

        public static string FriendlyName(string process) => Known.TryGetValue(process, out var k) ? k.Name : process;

        static double At(List<double>? list, int i) => list != null && i < list.Count ? list[i] : double.NaN;

        static string Clock(DateTime begin, double second) => begin.AddSeconds(second).ToString("HH:mm", De);

        static string Minutes(double seconds) => seconds < 60 ? "unter einer Minute" : seconds < 120 ? "rund eine Minute" : "rund " + Math.Round(seconds / 60).ToString("N0", De) + " Minuten";

        // Momente zählen: zusammenhängende Zeilen gelten als ein Moment
        static int Moments(List<double> seconds) => seconds.Count == 0 ? 0 : 1 + seconds.Zip(seconds.Skip(1), (a, b) => b - a > Step + 1 ? 1 : 0).Sum();

        static string Times(DateTime begin, List<double> seconds)
        {
            var starts = new List<double>();
            for (var i = 0; i < seconds.Count; i++) if (i == 0 || seconds[i] - seconds[i - 1] > Step + 1) starts.Add(seconds[i]);
            var shown = starts.Take(4).Select(s => Clock(begin, s)).ToList();
            return string.Join(", ", shown) + (starts.Count > 4 ? " und " + (starts.Count - 4) + " weitere Male" : "");
        }

        public static RucklerErgebnis Analyze(Spielsitzung s, IEnumerable<RucklerEreignis>? events = null)
        {
            var r = new RucklerErgebnis();
            var other = s.Column("StoerCpu");
            if (other == null) { r.Summary = "Diese Sitzung wurde vor dem Ruckler-Detektiv aufgezeichnet. Ab der nächsten Spielsitzung schreibt der Helfer mit, was neben dem Spiel läuft."; return r; }
            r.Supported = true;
            var seconds = s.Column("Sekunde") ?? new List<double>();
            var names = s.Texts.TryGetValue("Stoerer", out var t) ? t : new List<string>();
            var cpu = s.Column("CpuLast");
            var disk = s.Column("Platte");
            var dpc = s.Column("Dpc");
            var ram = s.Column("RamFrei");

            var byProcess = new Dictionary<string, (List<double> At, double Peak)>(StringComparer.OrdinalIgnoreCase);
            var diskAt = new List<double>();
            var dpcAt = new List<double>();
            var ramAt = new List<double>();
            double dpcPeak = 0, ramLow = double.MaxValue;
            for (var i = 0; i < seconds.Count; i++)
            {
                var sec = seconds[i];
                var o = At(other, i);
                var busy = At(cpu, i) >= 85;
                var name = i < names.Count ? names[i].Trim() : "";
                if (name.Length > 0 && !double.IsNaN(o) && o >= (busy ? OtherLimitBusy : OtherLimit))
                {
                    if (!byProcess.TryGetValue(name, out var p)) p = (new List<double>(), 0);
                    p.At.Add(sec);
                    byProcess[name] = (p.At, Math.Max(p.Peak, o));
                }
                if (At(disk, i) >= DiskLimit) diskAt.Add(sec);
                var d = At(dpc, i);
                if (d >= DpcLimit) { dpcAt.Add(sec); dpcPeak = Math.Max(dpcPeak, d); }
                var free = At(ram, i);
                if (!double.IsNaN(free) && free < RamLimit) { ramAt.Add(sec); ramLow = Math.Min(ramLow, free); }
            }

            // gleich benannte Bekannte (zwei Defender-Prozesse) zusammenfassen
            foreach (var group in byProcess.GroupBy(p => FriendlyName(p.Key)))
            {
                var at = group.SelectMany(g => g.Value.At).Distinct().OrderBy(x => x).ToList();
                var peak = group.Max(g => g.Value.Peak);
                var first = group.First().Key;
                Known.TryGetValue(first, out var known);
                if (Moments(at) == 0) continue;
                r.Findings.Add(new RucklerBefund
                {
                    Title = group.Key + " hat dazwischengefunkt",
                    Text = Minutes(at.Count * Step) + " lang bis zu " + peak.ToString("N0", De) + " % des Prozessors, um " + Times(s.Begin, at) + ". "
                        + (known?.Text ?? "Ein Programm neben dem Spiel hat viel gerechnet. Beim Spielen schließen oder den Boost nutzen, der Hintergrundprogramme zurückstellt."),
                    Action = known?.Action ?? "boost", Seconds = at, Total = at.Count * Step,
                });
            }
            if (diskAt.Count > 0)
                r.Findings.Add(new RucklerBefund
                {
                    Title = "Laufwerk ausgelastet",
                    Text = Minutes(diskAt.Count * Step) + " lang waren die Laufwerke fast durchgehend beschäftigt, um " + Times(s.Begin, diskAt) + ". Liegt das Spiel auf einer Festplatte (HDD), ruckelt es beim Nachladen; auf einer SSD nicht. Auch Downloads und Virenscans im Hintergrund lasten das Laufwerk aus.",
                    Action = "drives", Seconds = diskAt, Total = diskAt.Count * Step,
                });
            if (dpcAt.Count > 0)
                r.Findings.Add(new RucklerBefund
                {
                    Title = "Treiber haben den Prozessor aufgehalten",
                    Text = Minutes(dpcAt.Count * Step) + " lang gingen bis zu " + dpcPeak.ToString("N1", De) + " % der Rechenzeit an Treiber-Unterbrechungen (sonst unter 2 %), um " + Times(s.Begin, dpcAt) + ". Typisch für veraltete WLAN-, Netzwerk- oder Tontreiber: Ein Treiber-Scan zeigt neuere.",
                    Action = "drivers", Seconds = dpcAt, Total = dpcAt.Count * Step,
                });
            if (ramAt.Count > 0)
                r.Findings.Add(new RucklerBefund
                {
                    Title = "Arbeitsspeicher knapp",
                    Text = Minutes(ramAt.Count * Step) + " lang waren weniger als " + RamLimit.ToString("N0", De) + " MB frei (zuletzt " + ramLow.ToString("N0", De) + " MB), um " + Times(s.Begin, ramAt) + ". Dann lagert Windows auf das Laufwerk aus – das ruckelt. Programme neben dem Spiel schließen; dauerhaft hilft mehr Arbeitsspeicher.",
                    Action = "boost", Seconds = ramAt, Total = ramAt.Count * Step,
                });

            // was Windows zur selben Zeit protokolliert hat
            var end = s.Begin.AddSeconds(Math.Max(s.Seconds, Step));
            foreach (var e in (events ?? Enumerable.Empty<RucklerEreignis>()).Where(e => e.When >= s.Begin && e.When <= end).GroupBy(e => e.Kind))
            {
                var list = e.OrderBy(x => x.When).ToList();
                var times = string.Join(", ", list.Take(4).Select(x => x.When.ToString("HH:mm", De)));
                var at = list.Select(x => (x.When - s.Begin).TotalSeconds).ToList();
                if (e.Key == "update")
                    r.Findings.Add(new RucklerBefund { Title = "Windows Update während des Spielens", Text = "Um " + times + " hat Windows Updates eingerichtet: " + string.Join(", ", list.Select(x => x.Text).Distinct().Take(3)) + ". Unter Nutzungszeit legst du fest, wann Windows das nicht tun soll.", Action = "update", Seconds = at, Total = 0 });
                else if (e.Key == "defender")
                    r.Findings.Add(new RucklerBefund { Title = "Virenscan während des Spielens", Text = "Um " + times + " hat Windows Defender einen Scan begonnen. Der geplante Scan lässt sich in Windows-Sicherheit auf eine andere Zeit legen.", Action = "defender", Seconds = at, Total = 0 });
            }

            r.Findings = r.Findings.OrderByDescending(f => f.Total).ToList();
            r.Summary = r.Findings.Count == 0
                ? "Nichts gefunden, was dazwischengefunkt hat: kein Programm neben dem Spiel, kein volles Laufwerk, keine Treiber-Unterbrechungen, genug Arbeitsspeicher. Gemessen wird alle 5 Sekunden – sehr kurze Ruckler können durchrutschen. Dann liegt es oft am Spiel selbst (Shader werden beim ersten Start übersetzt) oder an Einstellungen: Der Gaming-Check prüft sie."
                : r.Findings.Count == 1 ? "1 möglicher Grund für Ruckler" : r.Findings.Count + " mögliche Gründe für Ruckler, der häufigste zuerst";
            return r;
        }
    }
}
