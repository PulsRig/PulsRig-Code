// PulsRig.exe - die Hülle um das Programm. Sie trägt alle Dateien des Programms in sich und startet PulsRig.ps1 in
// einer eingebauten PowerShell, statt dass powershell.exe das tut. Nach außen läuft damit "PulsRig" (Task-Manager,
// Taskleiste, Verknüpfungen) und im Programmordner liegt nur diese eine Datei; innen arbeitet derselbe Code wie bisher.
//
// Gebaut wird sie von PulsRig-Paket.ps1 mit dem Compiler, den Windows mitbringt (csc.exe von .NET Framework 4).
//
// Drei Arten, sie zu starten:
//   PulsRig.exe                 das Programm mit Fenster (PulsRig.ps1)
//   PulsRig.exe -Helfer         der Helfer neben der Uhr (siehe PulsRigHelper unten) - ohne PowerShell, klein im Speicher
//   PulsRig.exe -Boost Ein|Aus [-Spiel Name]   und   PulsRig.exe -Wochenscan
//                               Arbeit ohne Fenster für den Helfer (PulsRig-Hintergrund.ps1)
//
// PulsRig.ps1 startet sich in zwei Fällen selbst neu (Adminrechte, Obergrenze der Speicherverwaltung) und ruft dafür
// das Programm auf, in dem es gerade läuft - mit den Angaben, die powershell.exe braucht. Die Hülle nimmt deshalb
// dieselben Angaben an, überliest die für powershell.exe gedachten (-NoProfile, -ExecutionPolicy, -WindowStyle,
// -File) und reicht nur die Schalter des Programms weiter.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("PulsRig")]
[assembly: AssemblyProduct("PulsRig")]
[assembly: AssemblyDescription("Treiber, Boost, Werkzeuge")]
[assembly: AssemblyCompany("PulsRig")]

static class PulsRigStart
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr owner, string text, string caption, uint type);

    [STAThread]
    static int Main(string[] args)
    {
        Assembly self = Assembly.GetExecutingAssembly();
        string root = Path.GetDirectoryName(self.Location);

        string mode = "app";
        var switches = new Dictionary<string, object>();
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i].TrimStart('-').ToLowerInvariant())
            {
                case "executionpolicy": case "windowstyle": case "file": i++; break;   // samt ihrem Wert überlesen
                case "noelevate": switches["NoElevate"] = true; break;
                case "demo": switches["Demo"] = true; break;
                case "real": switches["Real"] = true; break;
                case "scan": switches["StartScan"] = true; break;
                case "snapshot": if (i + 1 < args.Length) switches["Snapshot"] = args[++i]; break;
                case "helfer": mode = "helper"; break;
                case "boost": mode = "background"; switches["Aufgabe"] = "Boost"; if (i + 1 < args.Length) switches["Wert"] = args[++i]; break;
                case "spiel": if (i + 1 < args.Length) switches["Spiel"] = args[++i]; break;
                case "wochenscan": mode = "background"; switches["Aufgabe"] = "Wochenscan"; break;
            }
        }
        if (mode == "helper") return PulsRigHelper.Run(self.Location);

        // Die Dateien des Programms stecken als Ressourcen in dieser Datei (PulsRig-Paket.ps1 bettet sie ein).
        // Fehlen sie - eine Hülle, die jemand von Hand gebaut hat -, starten die Skripte aus dem Ordner daneben.
        var files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string name in self.GetManifestResourceNames())
        {
            using (Stream stream = self.GetManifestResourceStream(name))
            using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                files[name] = reader.ReadToEnd();
        }
        string scriptName = mode == "background" ? "PulsRig-Hintergrund.ps1" : "PulsRig.ps1";
        bool embedded = files.ContainsKey(scriptName);
        string script = Path.Combine(root, scriptName);
        if (!embedded && !File.Exists(script))
        {
            if (mode == "app") MessageBoxW(IntPtr.Zero, scriptName + " fehlt im Ordner des Programms:\n" + root, "PulsRig", 0x10);
            return 2;
        }

        try
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            state.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;   // gilt nur für diesen Prozess
            state.ApartmentState = ApartmentState.STA;                            // die Oberfläche (WPF) verlangt das
            state.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (Runspace space = RunspaceFactory.CreateRunspace(state))
            {
                space.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = space;
                    space.SessionStateProxy.SetVariable("PulsRigRoot", root);
                    if (embedded)
                    {
                        space.SessionStateProxy.SetVariable("PulsRigEmbedded", files);
                        shell.AddScript(files[scriptName]);
                    }
                    else shell.AddCommand(script);
                    foreach (KeyValuePair<string, object> entry in switches) shell.AddParameter(entry.Key, entry.Value);
                    Collection<PSObject> output = shell.Invoke();
                    // Fehler, die das Programm nicht selbst gefangen hat, enden hier - sonst bliebe ein Start ohne Fenster stumm
                    if (shell.InvocationStateInfo.State == PSInvocationState.Failed && shell.InvocationStateInfo.Reason != null)
                        throw shell.InvocationStateInfo.Reason;
                    // die Arbeit ohne Fenster meldet ihr Ergebnis als Zahl zurück (Wochenscan: neuere Treiber)
                    if (mode == "background" && output.Count > 0)
                    {
                        int code;
                        if (int.TryParse(Convert.ToString(output[output.Count - 1]), out code)) return code;
                    }
                }
            }
            return 0;
        }
        catch (Exception problem)
        {
            Exception inner = problem.InnerException ?? problem;
            try
            {
                string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PulsRig");
                Directory.CreateDirectory(folder);
                File.AppendAllText(Path.Combine(folder, "PulsRig-Fehler.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + (mode == "app" ? "Start" : "Hintergrund") + ": " + inner + Environment.NewLine, new UTF8Encoding(true));
            }
            catch { }
            if (mode == "app") MessageBoxW(IntPtr.Zero, "PulsRig konnte nicht starten:\n\n" + inner.Message, "PulsRig", 0x10);
            return -1;
        }
    }
}

// Der Helfer neben der Uhr. Er läuft ohne PowerShell und ohne Fenster und tut nur drei Dinge:
//   - ein Menü am Symbol: PulsRig öffnen, Boost ein/aus, nach Treibern sehen, Helfer beenden
//   - Boost automatisch: Läuft eines der in PulsRig gewählten Spiele, schaltet er den Boost ein, danach wieder aus.
//     Dafür muss er mit Adminrechten laufen (Aufgabe "PulsRig Helfer", von PulsRig angelegt); ohne sie würde Windows
//     bei jedem Spielstart nachfragen - dann bleibt der automatische Boost aus.
//   - einmal pro Woche nach Treibern sehen und nur dann eine Meldung zeigen, wenn es neuere gibt.
//   - beim Spielen Temperaturen, Last und Takt aufzeichnen (PulsRig-Aufzeichnung.cs), auch per Menü für alles andere.
// Die Arbeit selbst erledigt PulsRig.exe ohne Fenster (-Boost, -Wochenscan). Einstellungen liest er aus derselben
// Datei wie das Programm; aus ihr übernimmt er nur Schalter und Namen von Spielen, nie Pfade oder Befehle.
static class PulsRigHelper
{
    static NotifyIcon icon;
    static ToolStripMenuItem boostItem, openItem, scanItem, recordItem, quitItem;
    static int recordMissing;        // wie oft hintereinander das aufgezeichnete Spiel nicht mehr lief
    static string exe, outDir, settingsPath, statePath, scanPath;
    static DateTime settingsTime = DateTime.MinValue, started = DateTime.Now;
    static Dictionary<string, object> settings = new Dictionary<string, object>();
    static bool admin, english;
    static string autoGame;          // das Spiel, für das der Helfer den Boost eingeschaltet hat
    static int missing;              // wie oft hintereinander das Spiel nicht mehr lief
    static Process pending;          // laufende Arbeit ohne Fenster
    static string pendingKind;       // "boost-ein", "boost-aus", "scan", "scan-hand"
    static bool balloonOpensScan;

    public static int Run(string exePath)
    {
        bool created;
        using (var mark = new Mutex(true, "PulsRig-8B6C1F0E-Helfer", out created))
        {
            if (!created) return 0;   // läuft schon
            exe = exePath;
            string root = Path.GetDirectoryName(exePath);
            bool installed = root.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), StringComparison.OrdinalIgnoreCase);
            outDir = installed ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PulsRig") : Path.Combine(root, "Treiber");
            settingsPath = Path.Combine(outDir, "PulsRig-Einstellungen.json");
            statePath = Path.Combine(outDir, "Spiel-Beschleunigung.json");
            scanPath = Path.Combine(outDir, "PulsRig-Hintergrund-Scan.json");
            admin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            ReadSettings();
            if (!Flag("Helper", false)) return 0;   // in PulsRig abgeschaltet
            Log("Helfer gestartet, " + (admin ? "mit Adminrechten" : "ohne Adminrechte") + ", Boost automatisch: " + (Flag("AutoBoost", false) ? "an, Spiele: " + string.Join(", ", Games().ToArray()) : "aus"));

            Application.EnableVisualStyles();
            var menu = new ContextMenuStrip();
            openItem = new ToolStripMenuItem("", null, delegate { Open(false); });
            boostItem = new ToolStripMenuItem("", null, delegate { ToggleBoost(); });
            scanItem = new ToolStripMenuItem("", null, delegate { StartWork("-Wochenscan", "scan-hand"); });
            recordItem = new ToolStripMenuItem("", null, delegate { if (PulsRigRecorder.Active) StopRecording("per Menü"); else StartRecording(Say("Manuell", "Manual"), true); UpdateTexts(); });
            quitItem = new ToolStripMenuItem("", null, delegate { Application.Exit(); });
            menu.Items.AddRange(new ToolStripItem[] { openItem, boostItem, scanItem, recordItem, new ToolStripSeparator(), quitItem });
            menu.Opening += delegate { UpdateTexts(); };
            icon = new NotifyIcon();
            try { icon.Icon = Icon.ExtractAssociatedIcon(exe); } catch { icon.Icon = SystemIcons.Application; }
            icon.Text = "PulsRig";
            icon.ContextMenuStrip = menu;
            icon.DoubleClick += delegate { Open(false); };
            icon.BalloonTipClicked += delegate { Open(balloonOpensScan); };
            UpdateTexts();
            icon.Visible = true;

            var timer = new System.Windows.Forms.Timer();
            timer.Interval = 5000;
            timer.Tick += delegate { try { Tick(); } catch { } };
            timer.Start();
            Application.Run();
            timer.Stop();
            if (PulsRigRecorder.Active) StopRecording("Helfer beendet");
            icon.Visible = false;
            icon.Dispose();
        }
        return 0;
    }

    static string Say(string de, string en) { return english ? en : de; }

    static void UpdateTexts()
    {
        bool on = File.Exists(statePath);
        openItem.Text = Say("PulsRig öffnen", "Open PulsRig");
        boostItem.Text = on ? Say("Boost ausschalten", "Switch boost off") : Say("Boost einschalten", "Switch boost on");
        boostItem.Enabled = pending == null;
        scanItem.Text = Say("Jetzt nach Treibern sehen", "Check for drivers now");
        scanItem.Enabled = pending == null;
        recordItem.Text = PulsRigRecorder.Active
            ? Say("Aufzeichnung beenden", "Stop recording") + (PulsRigRecorder.Manual ? "" : " (" + PulsRigRecorder.Game + ")")
            : Say("Temperaturen aufzeichnen", "Record temperatures");
        quitItem.Text = Say("Helfer beenden", "Quit helper");
        icon.Text = on ? Say("PulsRig – Boost an", "PulsRig – boost on") : "PulsRig";
    }

    static void ReadSettings()
    {
        try
        {
            if (!File.Exists(settingsPath)) return;
            DateTime time = File.GetLastWriteTime(settingsPath);
            if (time == settingsTime) return;
            settingsTime = time;
            var parsed = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(settingsPath, Encoding.UTF8));
            if (parsed != null) settings = parsed;
            english = Convert.ToString(Value("Language")) == "en";
        }
        catch { }
    }

    static object Value(string key) { object value; return settings.TryGetValue(key, out value) ? value : null; }
    static bool Flag(string key, bool fallback) { object value = Value(key); return value is bool ? (bool)value : fallback; }

    // die in PulsRig gewählten Spiele: Namen von Programmdateien ohne ".exe"
    static List<string> Games() { return GameList("BoostGames"); }

    // aufgezeichnet werden die Boost-Spiele und die, die nur aufgezeichnet werden sollen (ohne Boost)
    static List<string> RecordedGames()
    {
        var games = GameList("BoostGames");
        foreach (string name in GameList("RecordList")) if (!games.Contains(name)) games.Add(name);
        return games;
    }

    static List<string> GameList(string key)
    {
        var games = new List<string>();
        var list = Value(key) as IEnumerable;
        if (list == null || list is string) return games;
        foreach (object entry in list)
        {
            string name = Path.GetFileNameWithoutExtension(Convert.ToString(entry));
            if (!string.IsNullOrEmpty(name) && name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0) games.Add(name);
        }
        return games;
    }

    static void Open(bool scan)
    {
        try { Process.Start(new ProcessStartInfo(exe, scan ? "-Scan" : "") { UseShellExecute = true }); } catch { }
    }

    static void Balloon(string title, string text, bool opensScan)
    {
        balloonOpensScan = opensScan;
        icon.ShowBalloonTip(8000, title, text, ToolTipIcon.Info);
    }

    // Arbeit ohne Fenster starten; der Boost braucht Adminrechte - ohne sie fragt Windows einmal nach
    static void StartWork(string arguments, string kind)
    {
        if (pending != null) return;
        try
        {
            var start = new ProcessStartInfo(exe, arguments) { UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden };
            if (kind.StartsWith("boost") && !admin) start.Verb = "runas";
            pending = Process.Start(start);
            pendingKind = kind;
        }
        catch { pending = null; }   // Abfrage abgelehnt
        UpdateTexts();
    }

    // eine Zeile im gemeinsamen Protokoll mit PulsRig-Hintergrund.ps1 (landet im Diagnose-Paket)
    static void Log(string text)
    {
        try { File.AppendAllText(Path.Combine(outDir, "PulsRig-Hintergrund.log"), DateTime.Now.ToString("dd.MM. HH:mm:ss") + "  " + text + "\r\n", new UTF8Encoding(false)); }
        catch { }
    }

    static void ToggleBoost()
    {
        Log("Helfer: Boost per Rechtsklick " + (File.Exists(statePath) ? "aus" : "ein"));
        if (File.Exists(statePath)) { StartWork("-Boost Aus", "boost-aus"); autoGame = null; }
        else StartWork("-Boost Ein", "boost-ein");
    }

    // das erste der aufzuzeichnenden Spiele, das gerade läuft, sonst null
    static string RunningGame()
    {
        foreach (string game in RecordedGames())
        {
            Process[] found = Process.GetProcessesByName(game);
            foreach (Process process in found) process.Dispose();
            if (found.Length > 0) return game;
        }
        return null;
    }

    static void StartRecording(string name, bool manual)
    {
        try
        {
            PulsRigRecorder.Start(outDir, name, Path.Combine(Path.GetDirectoryName(exe), "Sensoren"), manual);
            recordMissing = 0;
            Log("Helfer: Aufzeichnung begonnen (" + name + ")");
        }
        catch (Exception problem) { Log("Helfer: Aufzeichnung nicht möglich: " + problem.Message); }
    }

    static void StopRecording(string why)
    {
        string name = PulsRigRecorder.Game;
        double minutes = PulsRigRecorder.Stop();
        Log("Helfer: Aufzeichnung " + (minutes > 0 ? "gespeichert, " + Math.Round(minutes) + " Minuten" : "verworfen (kürzer als eine Minute)") + " (" + name + ", " + why + ")");
    }

    // alle 5 Sekunden: eine Zeile schreiben; beginnen, wenn ein gewähltes Spiel läuft, enden, wenn es 15 Sekunden fehlt
    static void Record()
    {
        if (PulsRigRecorder.Active && !PulsRigRecorder.Sample()) { StopRecording("länger als 12 Stunden"); return; }
        if (PulsRigRecorder.Active && PulsRigRecorder.Manual) return;   // von Hand begonnen: endet nur von Hand
        bool wanted = Flag("RecordGames", true);
        if (!PulsRigRecorder.Active)
        {
            if (!wanted) return;
            string running = RunningGame();
            if (running != null) StartRecording(running, false);
            return;
        }
        string game = PulsRigRecorder.Game;
        bool still = false;
        try { Process[] found = Process.GetProcessesByName(game); foreach (Process process in found) process.Dispose(); still = found.Length > 0; } catch { }
        if (still && wanted) { recordMissing = 0; return; }
        recordMissing++;
        if (recordMissing >= 3 || !wanted) StopRecording(wanted ? "Spiel beendet" : "abgeschaltet");
    }

    static void Tick()
    {
        ReadSettings();
        if (!Flag("Helper", false)) { Application.Exit(); return; }   // in PulsRig abgeschaltet
        // vor allem anderen: auch während der Boost umschaltet, läuft die Aufzeichnung weiter
        try { Record(); } catch { }
        if (pending != null)
        {
            if (!pending.HasExited) return;
            int code = 0;
            try { code = pending.ExitCode; } catch { }
            string kind = pendingKind;
            pending.Dispose();
            pending = null;
            Finish(kind, code);
            UpdateTexts();
            return;
        }

        // Boost automatisch: nur mit Adminrechten, sonst käme bei jedem Spielstart eine Abfrage von Windows
        if (admin && Flag("AutoBoost", false))
        {
            string running = null;
            foreach (string game in Games())
            {
                Process[] found = Process.GetProcessesByName(game);
                foreach (Process process in found) process.Dispose();
                if (found.Length > 0) { running = game; break; }
            }
            if (autoGame == null && running != null && !File.Exists(statePath))
            {
                Log("Helfer: " + running + " gestartet");
                autoGame = running;
                missing = 0;
                StartWork("-Boost Ein -Spiel \"" + running + "\"", "boost-ein");
                return;
            }
            if (autoGame != null)
            {
                if (running == null) missing++; else missing = 0;
                if (missing >= 3)   // 15 Sekunden kein Spiel mehr
                {
                    Log("Helfer: " + autoGame + " läuft nicht mehr");
                    if (File.Exists(statePath)) { StartWork("-Boost Aus", "boost-aus"); return; }
                    autoGame = null;
                    missing = 0;
                }
            }
        }

        // einmal pro Woche nach Treibern sehen - frühestens zwei Minuten nach dem Start, damit die Anmeldung nicht leidet
        if (Flag("WeeklyScan", true) && (DateTime.Now - started).TotalMinutes >= 2 && WeeklyDue())
            StartWork("-Wochenscan", "scan");
    }

    static bool WeeklyDue()
    {
        try
        {
            if (!File.Exists(scanPath)) return true;
            return (DateTime.Now - File.GetLastWriteTime(scanPath)).TotalDays >= 7;
        }
        catch { return false; }
    }

    static void Finish(string kind, int code)
    {
        if (kind == "boost-ein")
        {
            if (File.Exists(statePath))
            {
                Log("Helfer: Boost ist an" + (autoGame != null ? " (für " + autoGame + ")" : ""));
                Balloon(Say("Boost eingeschaltet", "Boost switched on"), autoGame != null ? Say("Für " + autoGame + ". Nach dem Spiel schaltet er sich wieder aus.", "For " + autoGame + ". It switches off again after the game.") : Say("Energieplan und Dienste sind umgestellt.", "Power plan and services are switched."), false);
            }
            else
            {
                // nichts umzustellen (alles schon so eingestellt) oder abgelehnt: autoGame bleibt stehen,
                // damit der Helfer es nicht alle 5 Sekunden neu versucht, solange das Spiel läuft
                Log("Helfer: Boost nicht eingeschaltet, Ergebnis " + code);
                if (autoGame == null)
                    Balloon(Say("Nichts umzustellen", "Nothing to switch"), Say("Energieplan und Dienste sind schon so eingestellt.", "Power plan and services are already set."), false);
            }
        }
        else if (kind == "boost-aus")
        {
            Log("Helfer: Boost ist " + (File.Exists(statePath) ? "noch an" : "aus"));
            if (!File.Exists(statePath))
                Balloon(Say("Boost ausgeschaltet", "Boost switched off"), autoGame != null ? Say(autoGame + " wurde beendet - alles ist zurückgestellt.", autoGame + " was closed - everything is restored.") : Say("Alles ist zurückgestellt.", "Everything is restored."), false);
            autoGame = null;
            missing = 0;
        }
        else if (kind == "scan" || kind == "scan-hand")
        {
            if (code > 0)
                Balloon(Say(code == 1 ? "1 neuerer Treiber" : code + " neuere Treiber", code == 1 ? "1 newer driver" : code + " newer drivers"), Say("Ein Klick öffnet PulsRig und zeigt die Liste.", "Click to open PulsRig and see the list."), true);
            else if (kind == "scan-hand")
                Balloon(Say("Alles aktuell", "All up to date"), code < 0 ? Say("Die Suche ist fehlgeschlagen.", "The search failed.") : Say("Keine neueren Treiber gefunden.", "No newer drivers found."), false);
        }
    }
}
