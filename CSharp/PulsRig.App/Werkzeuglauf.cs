using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using PulsRig.Core;

namespace PulsRig.App;

// Was die Werkzeuge ausführen. Treiber sichern und zurückholen laufen hier in C# (wie Backup-InstalledDrivers und
// Invoke-RestoreTool); die übrigen Werkzeuge der Liste starten vorerst das PowerShell-Werkzeug (Treiber-Scan.ps1
// -Tool …) in einem eigenen Fenster: es prüft zuerst und fragt dort vor jeder Änderung.
static class Werkzeuglauf
{
    public static string Backups => Path.Combine(Belastung.Folder, "Sicherungen");
    public static Dictionary<string, (bool Busy, string Message)> State { get; } = new();
    public static event Action? Changed;
    public static bool BackupBusy { get; private set; }
    public static string? LastBackup { get; private set; }
    static readonly Dictionary<string, CancellationTokenSource> Transfers = new();
    public static bool CanCancel(string key) => Transfers.ContainsKey(key);
    public static void Cancel(string key)
    {
        if (!Transfers.TryGetValue(key, out var source)) return;
        source.Cancel();
        State[key] = (true, "Abbruch angefordert – laufender Schritt wird beendet.");
        Changed?.Invoke();
    }

    static void Transfer(string key, Func<CancellationToken, Action<string>, string> work)
    {
        if (BackupBusy || State.TryGetValue(key, out var current) && current.Busy) return;
        BackupBusy = true;
        var source = new CancellationTokenSource();
        Transfers[key] = source;
        var token = source.Token;
        var dispatcher = System.Windows.Application.Current.Dispatcher;
        void Progress(string text) => dispatcher.BeginInvoke(() =>
        {
            if (State.TryGetValue(key, out var state) && state.Busy && !token.IsCancellationRequested) { State[key] = (true, text); Changed?.Invoke(); }
        });
        Run(key, () =>
        {
            try { return work(source.Token, Progress); }
            catch (OperationCanceledException) { return "Abgebrochen. Es wurde keine neue Sicherung freigegeben."; }
            finally
            {
                dispatcher.Invoke(() => { Transfers.Remove(key); BackupBusy = false; });
                source.Dispose();
            }
        });
    }

    static void Run(string key, Func<string> work)
    {
        if (State.TryGetValue(key, out var s) && s.Busy) return;
        State[key] = (true, "");
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        var thread = new Thread(() =>
        {
            string message;
            try { message = work(); } catch (Exception e) { message = Fehlermeldung.Text(e); }
            ui.BeginInvoke(() => { ForgetBackups(); State[key] = (false, message); Changed?.Invoke(); });
        }) { IsBackground = true };
        // Windows Update (Treiberverlauf) und WScript.Shell (Autostart) sprechen COM und wollen einen STA-Thread
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    static (int Code, string Output) Tool(string file, string arguments)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, file), arguments) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return (process.ExitCode, output);
    }

    // wie Backup-InstalledDrivers: alle Pakete von Drittherstellern exportieren, dazu eine ZIP-Datei daneben
    public static void Backup(string key)
    {
        if (BackupBusy || State.TryGetValue(key, out var active) && active.Busy) return;
        LastBackup = null;
        Transfer(key, (token, progress) =>
        {
                var target = Sicherungsablage.Create(Backups, folder =>
                {
                    var code = Tool("pnputil.exe", "/export-driver * \"" + folder + "\"").Code;
                    if (code != 0) throw new TreiberWerkzeugException(code);
                }, progress: progress, cancellationToken: token);
                var count = Sicherungsablage.Inspect(target).Packages;
                System.Windows.Application.Current.Dispatcher.Invoke(() => LastBackup = target);
                return count + " Treiberpakete gesichert · " + Path.GetFileName(target + ".zip");
        });
    }

    // Sicherungen, die PulsRig angelegt hat (von Hand oder automatisch vor einem Update), neueste zuerst
    // Die Suche liest jede Datei der Sicherungen (eine halbe Sekunde auf dem Oberflächen-Thread) und die Werkzeug-Seite
    // fragt beim Aufbau dreimal: deshalb gemerkt, bis sich einer der Ordner ändert, ein Werkzeug fertig wird oder 5 Minuten um sind
    static (List<DirectoryInfo> List, DateTime Stamp, DateTime At)? backupCache;
    public static void ForgetBackups() => backupCache = null;

    public static List<DirectoryInfo> BackupFolders()
    {
        try
        {
            static DateTime Stamp(string dir) => Directory.Exists(dir) ? Directory.GetLastWriteTimeUtc(dir) : DateTime.MinValue;
            var stamp = new[] { Stamp(Backups), Stamp(Altdaten.Folder) }.Max();
            if (backupCache is { } c && c.Stamp == stamp && DateTime.UtcNow - c.At < TimeSpan.FromMinutes(5)) return c.List.ToList();
            var list = Sicherungsablage.Find(Backups, Altdaten.Folder);
            backupCache = (list, stamp, DateTime.UtcNow);
            return list.ToList();
        }
        catch (Exception) { return new(); }
    }

    public static void Import(string key, string archive) => Transfer(key, (token, progress) =>
    {
        var target = Sicherungsablage.Import(archive, Backups, progress, token);
        return "ZIP-Sicherung geprüft und abgelegt. Zum Einspielen die Sicherung erneut auswählen. · " + Path.GetFileName(target);
    });

    // wie Invoke-RestoreTool: Windows übernimmt nur Treiber, die besser passen als die installierten
    public static void Restore(string key, DirectoryInfo folder) => Run(key, () =>
    {
        Sicherungsablage.Inspect(folder.FullName, verify: true);
        if (!App.IsAdmin) throw new InvalidOperationException("Zum Einspielen muss PulsRig als Administrator laufen.");
        var message = "";
        if (TreiberEinstellungen.Current.RestorePoint)
            try
            {
                using var restore = new System.Management.ManagementClass(@"\\.\root\default", "SystemRestore", null);
                var args = restore.GetMethodParameters("CreateRestorePoint");
                args["Description"] = "PulsRig (vor Treiberwiederherstellung)";
                args["RestorePointType"] = 10;
                args["EventType"] = 100;
                var result = restore.InvokeMethod("CreateRestorePoint", args, null);
                var status = Convert.ToInt32(result?["ReturnValue"] ?? -1);
                Sicherungsablage.RequireRestorePoint(status);
                message = "Wiederherstellungspunkt erstellt. ";
            }
            catch (Exception e) { throw new InvalidOperationException("Kein bestätigter Wiederherstellungspunkt. Die Treiber wurden nicht eingespielt. " + e.Message); }
        // 259 = nichts Neueres dabei, 3010 = Neustart nötig
        var code = Tool("pnputil.exe", "/add-driver \"" + Path.Combine(folder.FullName, "*.inf") + "\" /subdirs /install").Code;
        return message + (code switch
        {
            0 => "Windows hat die Treiberpakete verarbeitet. Bereits passende Treiber können unverändert bleiben.",
            3010 => "Windows hat die Treiberpakete verarbeitet – bitte den PC neu starten.",
            259 => "Windows hat nichts übernommen: die installierten Treiber passen gleich gut oder besser.",
            _ => throw new TreiberWerkzeugException(code),
        });
    });

    // Ergebnis der letzten Prüfung je Werkzeug und was die ausgeführten Schritte gemeldet haben
    public static Dictionary<string, Werkbefund> Results { get; } = new();
    public static Dictionary<string, DateTime> CheckedAt { get; } = new();
    public static Dictionary<string, List<string>> Log { get; } = new();

    public static void Check(string key, string tool) => Run(key, () =>
    {
        var result = Werkzeugpruefung.Check(tool) ?? throw new InvalidOperationException("Unbekanntes Werkzeug.");
        System.Windows.Application.Current.Dispatcher.Invoke(() => { Results[key] = result; CheckedAt[key] = DateTime.Now; });
        return "";
    });

    // führt die Schritte nacheinander aus, ein Fehlschlag hält die übrigen nicht auf; danach wird neu geprüft
    public static void Execute(string key, string tool, IReadOnlyList<Schritt> steps) => Run(key, () =>
    {
        var log = new List<string>();
        foreach (var step in steps)
        {
            try { var text = step.Run(); log.Add("✓ " + step.Text + (text.Length > 0 && text != "ok" ? " – " + text : "")); }
            catch (Exception e) { log.Add("✕ " + step.Text + " – " + Fehlermeldung.Text(e)); }
        }
        Werkbefund? again = null;
        try { again = Werkzeugpruefung.Check(tool); } catch (Exception) { }
        System.Windows.Application.Current.Dispatcher.Invoke(() => { Log[key] = log; if (again != null) { Results[key] = again; CheckedAt[key] = DateTime.Now; } });
        return "";
    });
}
