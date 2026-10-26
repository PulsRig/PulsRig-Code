using PulsRig.Core;

namespace PulsRig.App;

// Zwischenspeicher der Abfragen: jede läuft beim ersten Bedarf einmal im Hintergrund, "Neu einlesen" fragt erneut.
// Changed kommt auf dem Oberflächen-Thread, sobald eine Abfrage fertig ist.
static class Hw
{
    public static Prozessor? Cpu { get; private set; }
    public static Grafikkarte? Gpu { get; private set; }
    public static Arbeitsspeicher? Memory { get; private set; }
    public static Laufwerke? Drives { get; private set; }
    public static List<Bildschirm>? Displays { get; private set; }
    public static AbsturzDaten? Crashes { get; private set; }
    public static event Action? Changed;

    static readonly HashSet<string> Running = new();

    public static void Load(string what, bool again = false)
    {
        bool known = what switch
        {
            "cpu" => Cpu != null, "gpu" => Gpu != null, "ram" => Memory != null, "drives" => Drives != null, "display" => Displays != null, "crash" => Crashes != null, _ => true,
        };
        if ((known && !again) || !Running.Add(what)) return;
        var ui = System.Windows.Application.Current.Dispatcher;
        Task.Run(() =>
        {
            object? result = what switch
            {
                "cpu" => Abfragen.Cpu(), "gpu" => Abfragen.Gpu(), "ram" => Abfragen.Memory(), "drives" => Abfragen.Drives(), "display" => Abfragen.Displays(), "crash" => Ereignisse.Crashes(), _ => null,
            };
            ui.BeginInvoke(() =>
            {
                Running.Remove(what);
                switch (what)
                {
                    case "cpu": Cpu = result as Prozessor; break;
                    case "gpu": Gpu = result as Grafikkarte; break;
                    case "ram": Memory = result as Arbeitsspeicher; break;
                    case "drives":
                        Drives = result as Laufwerke;
                        // Verlauf je Tag für Laufwerke und SSD-Abnutzung (Verschleiß)
                        if (Drives is { } d) Task.Run(() => Verschleissdaten.AddDrives(d));
                        break;
                    case "display": Displays = result as List<Bildschirm>; break;
                    case "crash": Crashes = result as AbsturzDaten; break;
                }
                Changed?.Invoke();
            });
        });
    }

    // Seiten neu zeichnen, wenn sich außerhalb der Abfragen etwas geändert hat (ZIP gespeichert, Scan fertig)
    public static void Touch() => Changed?.Invoke();

    public static void LoadAll()
    {
        foreach (var what in new[] { "cpu", "gpu", "ram", "drives", "display", "crash" }) Load(what);
    }

    // Zustand des Arbeitsspeichers wie Get-MemoryCardState
    public static (string Text, string Tone) MemoryState(Arbeitsspeicher m)
    {
        var failed = m.Test is { Ok: false };
        if (m.Modules.Count == 0) return failed ? ("Speicherfehler", "bad") : ("Riegel unbekannt", "");
        var placement = Speicher.Placement(m.Layout);
        var channels = Speicher.Channels(m.Modules, m.Layout.Count);
        if (failed) return ("Speicherfehler", "bad");
        if (placement.State == "bad") return ("falsch gesteckt", "warn");
        if (m.Hardware is { Count: > 0 }) return ("Hardwarefehler", "warn");
        if (channels is { Hint.Length: > 0 }) return (channels.Name, "warn");
        return (Ui.Gb(m.Modules.Sum(x => x.Bytes)), placement.State == "good" ? "good" : "");
    }

    // Laufwerke wie Get-DriveCardState: auffällig ist, was Windows nicht gesund nennt oder Störungen protokolliert hat
    public static (string Text, string Tone) DriveState(Laufwerke d)
    {
        if (d.Disks.Count == 0) return ("keine Angaben", "");
        var bad = d.Disks.Count(x => x.Health != "Healthy" || Faults(d, x.Number) > 0);
        return bad > 0 ? (bad + " auffällig", "warn") : d.Faults is { Resets: > 0 } ? ("auffällig", "warn") : ("in Ordnung", "good");
    }

    public static int Faults(Laufwerke d, string disk) => d.Faults?.Disks.TryGetValue(disk, out var f) == true ? f.Count : 0;

    public static (string Text, string Tone) DisplayState(List<Bildschirm> list)
    {
        if (list.Count == 0) return ("keine Angaben", "");
        var slow = list.Count(x => x.Max > x.Hz);
        return slow > 0 ? (slow + " zu langsam", "warn") : (list.Count == 1 ? list[0].Hz + " Hz" : list.Count + " Bildschirme", "good");
    }

    // Kurzname für Kacheln: "NVIDIA GeForce RTX 3080" → "RTX 3080", "AMD Ryzen 7 5800X3D 8-Core Processor" → "Ryzen 7 5800X3D"
    public static string Short(string name)
    {
        var n = name.Replace("(R)", "").Replace("(TM)", "").Replace("NVIDIA GeForce ", "").Replace("AMD Radeon ", "Radeon ");
        n = System.Text.RegularExpressions.Regex.Replace(n, @"\s+\d+-Core Processor|\s+Processor|\s+CPU @.*$|^Intel\s+Core\s+|^AMD\s+", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return n.Trim();
    }
}
