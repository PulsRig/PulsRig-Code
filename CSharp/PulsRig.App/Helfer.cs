using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

namespace PulsRig.App;

// Der Helfer neben der Uhr wie PulsRig-Helfer.ps1. Er selbst steckt in PulsRig.exe (PulsRig-Start.cs, PulsRigHelper)
// und liest seine Schalter aus den Einstellungen; die App richtet nur den Start mit Windows ein und startet ihn.
// Mit Adminrechten als Aufgabe "PulsRig Helfer" mit höchsten Rechten (nur dann ist der automatische Boost möglich),
// sonst als Autostart-Eintrag. Beides nur im installierten Programm: eine Aufgabe mit höchsten Rechten darf nur auf
// eine Datei unter "Programme" zeigen, die niemand ohne Adminrechte austauschen kann.
static class Helfer
{
    const string Task = "PulsRig Helfer", RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run", RunName = "PulsRig-Helfer";

    // PulsRig.exe neben der App oder einen Ordner darüber, nur unter "Programme"
    public static string? Exe
    {
        get
        {
            var programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            foreach (var dir in new[] { AppContext.BaseDirectory, Path.GetDirectoryName(AppContext.BaseDirectory.TrimEnd('\\')) ?? "" })
            {
                var exe = Path.Combine(dir, "PulsRig.exe");
                if (dir.StartsWith(programs, StringComparison.OrdinalIgnoreCase) && File.Exists(exe)) return exe;
            }
            return null;
        }
    }

    public static bool Running
    {
        get
        {
            try { using var mark = Mutex.OpenExisting("PulsRig-8B6C1F0E-Helfer"); return true; }
            // läuft er mit Adminrechten, darf ein Fenster ohne sie die Marke nicht öffnen – sie gibt es aber
            catch (UnauthorizedAccessException) { return true; }
            catch (Exception) { return false; }
        }
    }

    static int Schtasks(string arguments)
    {
        using var p = Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe"), arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })!;
        p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        return p.ExitCode;
    }

    public static bool HasTask => Schtasks("/Query /TN \"" + Task + "\"") == 0;

    // ein Satz zum Zustand, wie Get-HelperStatus
    public static string Status()
    {
        if (Exe == null) return "Den Helfer gibt es nur im installierten Programm.";
        if (!Altdaten.Flag(Altdaten.Settings(), "Helper", false)) return "Ausgeschaltet.";
        var running = Running;
        if (HasTask) return running ? "Läuft und startet mit Windows – mit Adminrechten, Boost automatisch ist möglich." : "Startet mit Windows – mit Adminrechten, Boost automatisch ist möglich.";
        return running ? "Läuft ohne Adminrechte: Boost automatisch ist so nicht möglich. PulsRig einmal als Admin starten und den Helfer neu einschalten." : "Startet mit Windows, ohne Adminrechte: Boost automatisch ist so nicht möglich.";
    }

    // wie Update-Helper: Start mit Windows einrichten oder zurücknehmen, und starten, wenn er laufen soll
    public static void Set(bool on)
    {
        Altdaten.Change(s => s["Helper"] = on);
        var exe = Exe;
        if (exe == null) return;
        if (on)
        {
            if (App.IsAdmin)
            {
                // beim Anmelden des eigenen Benutzers, mit höchsten Rechten, ohne Zeitlimit und auch im Akkubetrieb -
                // wie Register-ScheduledTask; schtasks kann das nur über eine Aufgabe als XML
                var user = System.Security.SecurityElement.Escape(Environment.UserDomainName + "\\" + Environment.UserName);
                var xml = Path.Combine(Path.GetTempPath(), "PulsRig-Helfer-Aufgabe.xml");
                File.WriteAllText(xml, $"""
                    <?xml version="1.0" encoding="UTF-16"?>
                    <Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
                      <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>{user}</UserId></LogonTrigger></Triggers>
                      <Principals><Principal id="Author"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
                      <Settings>
                        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
                        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
                        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
                        <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
                      </Settings>
                      <Actions Context="Author"><Exec><Command>{System.Security.SecurityElement.Escape(exe)}</Command><Arguments>-Helfer</Arguments></Exec></Actions>
                    </Task>
                    """, System.Text.Encoding.Unicode);
                try { Schtasks("/Create /F /TN \"" + Task + "\" /XML \"" + xml + "\""); }
                finally { try { File.Delete(xml); } catch (Exception) { } }
                RemoveRunEntry();
            }
            else if (!HasTask)
            {
                using var key = Registry.CurrentUser.CreateSubKey(RunKey);
                key.SetValue(RunName, "\"" + exe + "\" -Helfer");
            }
            Start();
        }
        else
        {
            // der laufende Helfer liest die Einstellung und beendet sich selbst
            if (App.IsAdmin && HasTask) Schtasks("/Delete /F /TN \"" + Task + "\"");
            RemoveRunEntry();
        }
    }

    static void RemoveRunEntry()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, true);
        key?.DeleteValue(RunName, false);
    }

    public static void Start()
    {
        var exe = Exe;
        if (exe == null || !Altdaten.Flag(Altdaten.Settings(), "Helper", false) || Running) return;
        // über die Aufgabe startet er mit höchsten Rechten, sonst mit denen dieses Fensters
        if (HasTask && Schtasks("/Run /TN \"" + Task + "\"") == 0) return;
        Process.Start(new ProcessStartInfo(exe, "-Helfer") { UseShellExecute = true });
    }
}
