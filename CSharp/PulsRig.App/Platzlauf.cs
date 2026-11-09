using PulsRig.Core;

namespace PulsRig.App;

// Speicher-Analyse je Laufwerksbuchstabe (Platzanalyse in PulsRig.Core), läuft im Hintergrund weiter, auch wenn
// die Seite gewechselt wird. Ergebnisse gelten für diese Sitzung; Changed kommt auf dem Oberflächen-Thread.
static class Platzlauf
{
    public static Dictionary<string, Platzergebnis> Results { get; } = new();
    public static Dictionary<string, string> Errors { get; } = new();
    public static string Running { get; private set; } = "";
    public static long Seen { get; private set; }
    public static event Action? Changed;
    static CancellationTokenSource? cancel;

    public static void Start(string letter)
    {
        if (Running.Length > 0) return;
        Running = letter;
        Seen = 0;
        Errors.Remove(letter);
        cancel = new CancellationTokenSource();
        var token = cancel.Token;
        var ui = System.Windows.Application.Current.Dispatcher;
        var last = DateTime.MinValue;
        Changed?.Invoke();
        Task.Run(() =>
        {
            Platzergebnis? result = null;
            string error = "";
            try
            {
                result = Platzanalyse.Run(letter + @":\", token, n =>
                {
                    if ((DateTime.Now - last).TotalMilliseconds < 400) return;
                    last = DateTime.Now;
                    ui.BeginInvoke(() => { Seen = n; Changed?.Invoke(); });
                });
            }
            catch (OperationCanceledException) { }
            catch (Exception e) { error = Bedienfehler.Text(e); }
            ui.BeginInvoke(() =>
            {
                if (result != null) Results[letter] = result;
                if (error.Length > 0) Errors[letter] = error;
                Running = "";
                Changed?.Invoke();
            });
        });
    }

    public static void Cancel() => cancel?.Cancel();

    public static void Reveal(string path, bool select)
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", select ? "/select,\"" + path + "\"" : "\"" + path + "\"") { UseShellExecute = true });
        }
        catch (Exception) { }
    }

    // Demo: erfundene Belegung für Screenshots
    public static Platzergebnis Demo()
    {
        Platzordner F(string path, long gb, params Platzordner[] kids)
        {
            var n = new Platzordner { Path = path, Size = gb << 30, Art = Platzanalyse.Art(path) };
            n.Children.AddRange(kids);
            return n;
        }
        var root = F(@"C:\", 590,
            F(@"C:\Program Files (x86)", 212, F(@"C:\Program Files (x86)\Steam", 198, F(@"C:\Program Files (x86)\Steam\steamapps", 197))),
            F(@"C:\Users", 168, F(@"C:\Users\Spieler", 166, F(@"C:\Users\Spieler\Videos", 74), F(@"C:\Users\Spieler\Downloads", 51), F(@"C:\Users\Spieler\AppData", 38))),
            F(@"C:\Windows", 38), F(@"C:\Program Files", 31), F(@"C:\pagefile.sys", 0), F(@"C:\ProgramData", 12));
        var files = new List<Platzdatei>
        {
            new(@"C:\Users\Spieler\Videos\Aufnahme 2026-10-30.mp4", 18L << 30, DateTime.Today.AddDays(-10)),
            new(@"C:\Users\Spieler\Downloads\Win11_24H2_German_x64.iso", 6L << 30, DateTime.Today.AddDays(-40)),
            new(@"C:\Users\Spieler\Downloads\Spiel-Setup.exe", 4L << 30, DateTime.Today.AddDays(-90)),
        }.OrderByDescending(x => x.Size).ToList();
        return new(root, files, 3, TimeSpan.FromSeconds(41));
    }
}
