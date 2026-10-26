using PulsRig.Core;

namespace PulsRig.App;

sealed record Tempo(string Letter, DateTime When, double Read, double Write, double Small, string Error);

// Tempomessung je Laufwerksbuchstabe wie die Abfrage DriveSpeed in PulsRig-Hardware.ps1 (Messung in PulsRig.Core).
// Die Ergebnisse gelten für diese Sitzung; Changed kommt auf dem Oberflächen-Thread.
static class Tempotest
{
    public static Dictionary<string, Tempo> Results { get; } = new();
    public static string Measuring { get; private set; } = "";
    public static event Action? Changed;

    public static void Start(string letter)
    {
        if (Measuring.Length > 0) return;
        Measuring = letter;
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        Task.Run(() =>
        {
            var result = Run(letter);
            ui.BeginInvoke(() => { Results[letter] = result; Measuring = ""; Changed?.Invoke(); });
        });
    }

    public static Tempo Run(string letter)
    {
        try
        {
            if (new System.IO.DriveInfo(letter + ":").AvailableFreeSpace < 3L * 1024 * 1024 * 1024) return Fail(letter, "Für die Messung müssen mindestens 3 GB frei sein.");
            // Ordner auf diesem Laufwerk, in den sicher geschrieben werden darf; zuletzt das Hauptverzeichnis
            var folders = new List<string>();
            var temp = System.IO.Path.GetTempPath();
            if (temp.StartsWith(letter + ":", StringComparison.OrdinalIgnoreCase) && System.IO.Directory.Exists(temp)) folders.Add(temp);
            folders.Add(letter + @":\");
            foreach (var folder in folders)
            {
                var v = Laufwerkstempo.Run(System.IO.Path.Combine(folder, "PulsRig-Tempotest.tmp"), 1L << 30, 5.0);
                if (v[0] >= 0) return new(letter, DateTime.Now, v[1], v[0], v[2], "");
            }
            return Fail(letter, "Auf dieses Laufwerk darf ohne Adminrechte nicht geschrieben werden.");
        }
        catch (Exception e) { return Fail(letter, (e.InnerException ?? e).Message); }
    }

    static Tempo Fail(string letter, string error) => new(letter, DateTime.Now, 0, 0, 0, error);

    public static string Speed(double v) => v < 10 ? v.ToString("N1", Ui.De) : v.ToString("N0", Ui.De);
}
