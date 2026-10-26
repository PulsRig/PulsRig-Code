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

    static void Run(string key, Func<string> work)
    {
        if (State.TryGetValue(key, out var s) && s.Busy) return;
        State[key] = (true, "");
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        var thread = new Thread(() =>
        {
            string message;
            try { message = work(); } catch (Exception e) { message = e.Message; }
            ui.BeginInvoke(() => { State[key] = (false, message); Changed?.Invoke(); });
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
    public static void Backup(string key) => Run(key, () =>
    {
        var target = Path.Combine(Backups, "Backup_" + DateTime.Now.ToString("yyyy-MM-dd_HHmm"));
        Directory.CreateDirectory(target);
        var code = Tool("pnputil.exe", "/export-driver * \"" + target + "\"").Code;
        if (code != 0) throw new InvalidOperationException("Die Sicherung ist fehlgeschlagen (pnputil-Code " + code + ").");
        var count = Directory.GetFiles(target, "*.inf", SearchOption.AllDirectories).Length;
        var zip = target + ".zip";
        if (File.Exists(zip)) File.Delete(zip);
        ZipFile.CreateFromDirectory(target, zip, CompressionLevel.Optimal, false);
        return count + " Treiberpakete gesichert · " + Path.GetFileName(zip);
    });

    // Sicherungen, die PulsRig angelegt hat (von Hand oder automatisch vor einem Update), neueste zuerst
    public static List<DirectoryInfo> BackupFolders()
    {
        try
        {
            return Directory.Exists(Backups)
                ? new DirectoryInfo(Backups).GetDirectories().Where(d => Sicherung.IsBackupFolder(d.Name)).OrderByDescending(d => d.LastWriteTime).ToList()
                : new();
        }
        catch (Exception) { return new(); }
    }

    // wie Invoke-RestoreTool: Windows übernimmt nur Treiber, die besser passen als die installierten
    public static void Restore(string key, DirectoryInfo folder) => Run(key, () =>
    {
        var infs = Directory.GetFiles(folder.FullName, "*.inf", SearchOption.AllDirectories).Length;
        if (infs == 0) throw new InvalidOperationException("In dieser Sicherung liegen keine Treiberpakete.");
        var message = "";
        if (TreiberEinstellungen.Current.RestorePoint)
            try
            {
                using var restore = new System.Management.ManagementClass(@"\\.\root\default", "SystemRestore", null);
                var args = restore.GetMethodParameters("CreateRestorePoint");
                args["Description"] = "PulsRig (vor Treiberwiederherstellung)";
                args["RestorePointType"] = 10;
                args["EventType"] = 100;
                restore.InvokeMethod("CreateRestorePoint", args, null);
                message = "Wiederherstellungspunkt erstellt. ";
            }
            catch (Exception) { message = "Kein Wiederherstellungspunkt. "; }
        // 259 = nichts Neueres dabei, 3010 = Neustart nötig
        var code = Tool("pnputil.exe", "/add-driver \"" + Path.Combine(folder.FullName, "*.inf") + "\" /subdirs /install").Code;
        return message + code switch
        {
            0 => infs + " Pakete eingespielt.",
            3010 => infs + " Pakete eingespielt – bitte den PC neu starten.",
            259 => "Windows hat nichts übernommen: die installierten Treiber passen gleich gut oder besser.",
            _ => "pnputil meldet Code " + code + ".",
        };
    });

    // Ergebnis der letzten Prüfung je Werkzeug und was die ausgeführten Schritte gemeldet haben
    public static Dictionary<string, Werkbefund> Results { get; } = new();
    public static Dictionary<string, List<string>> Log { get; } = new();

    public static void Check(string key, string tool) => Run(key, () =>
    {
        var result = Werkzeugpruefung.Check(tool) ?? throw new InvalidOperationException("Unbekanntes Werkzeug.");
        System.Windows.Application.Current.Dispatcher.Invoke(() => Results[key] = result);
        return "";
    });

    // führt die Schritte nacheinander aus, ein Fehlschlag hält die übrigen nicht auf; danach wird neu geprüft
    public static void Execute(string key, string tool, IReadOnlyList<Schritt> steps) => Run(key, () =>
    {
        var log = new List<string>();
        foreach (var step in steps)
        {
            try { var text = step.Run(); log.Add("✓ " + step.Text + (text.Length > 0 && text != "ok" ? " – " + text : "")); }
            catch (Exception e) { log.Add("✕ " + step.Text + " – fehlgeschlagen (" + e.Message.Trim() + ")"); }
        }
        Werkbefund? again = null;
        try { again = Werkzeugpruefung.Check(tool); } catch (Exception) { }
        System.Windows.Application.Current.Dispatcher.Invoke(() => { Log[key] = log; if (again != null) Results[key] = again; });
        return "";
    });
}
