using System.Diagnostics;
using System.IO;
using System.Management;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Der Boost wie Invoke-GameBoostTool: Spielmodus, Energieplan Höchstleistung, entbehrliche Dienste anhalten und die
// Programme schließen, die unter Boost → Einrichten gewählt sind. Der Zustand liegt in Spiel-Beschleunigung.json
// beim PowerShell-Programm, damit jedes der beiden Programme den Boost des anderen ausschalten kann. Zurückgestellt
// wird nur, was sich wirklich geändert hat. Dienste kommen nur aus der eigenen Liste oder von fremden Herstellern
// (Core.Boost.IsAllowed); Programme schließt nur der Boost, den man selbst einschaltet, nie der automatische.
static class Spielboost
{
    public sealed record Plan(bool GameModeOff, (string Guid, string Name)? Active, bool SwitchPlan, List<(string Name, string Display)> Services,
        List<(string Name, long Bytes)> Apps, List<(string Name, long Bytes)> Hungry, List<string> Games, long Free, long Total);

    public sealed record Zustand(string Time, string? PowerPlan, string? PowerPlanName, List<string> Services, List<string> ClosedApps, long FreeBefore, long FreeAfter, string? Game = null);

    public static string StateFile => Path.Combine(Altdaten.Folder, "Spiel-Beschleunigung.json");

    public static bool IsOn => File.Exists(StateFile);

    public static bool Busy { get; private set; }
    public static string Step { get; private set; } = "";
    public static string Message { get; private set; } = "";
    public static event Action? Changed;

    public static Zustand? State()
    {
        try
        {
            if (!IsOn) return null;
            var j = JsonNode.Parse(File.ReadAllText(StateFile));
            long Long(string n) => j?[n] is JsonValue v && v.TryGetValue<long>(out var l) ? l : 0;
            return new(Altdaten.Text(j, "Time", ""), Altdaten.Text(j, "PowerPlan", "") is { Length: > 0 } p ? p : null, Altdaten.Text(j, "PowerPlanName", ""),
                Altdaten.List(j, "Services"), Altdaten.List(j, "ClosedApps"), Long("FreeBefore"), Long("FreeAfter"));
        }
        catch (Exception) { return new("", null, null, new(), new(), 0, 0); }
    }

    static (int Code, string Output) Tool(string file, string arguments)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, file), arguments) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true,
            StandardOutputEncoding = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage) };
        using var p = Process.Start(start)!;
        var output = p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        return (p.ExitCode, output);
    }

    static long FreeMemory()
    {
        try
        {
            using var s = new ManagementObjectSearcher("SELECT FreePhysicalMemory, TotalVisibleMemorySize FROM Win32_OperatingSystem");
            foreach (ManagementObject o in s.Get()) return Convert.ToInt64(o["FreePhysicalMemory"]) * 1024;
        }
        catch (Exception) { }
        return 0;
    }

    static long TotalMemory()
    {
        try
        {
            using var s = new ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem");
            foreach (ManagementObject o in s.Get()) return Convert.ToInt64(o["TotalPhysicalMemory"]);
        }
        catch (Exception) { }
        return 0;
    }

    // Programme der eigenen Sitzung, je Name zusammengefasst
    static List<(string Name, long Bytes)> Programs(Func<string, bool> pick)
    {
        var session = Process.GetCurrentProcess().SessionId;
        return Process.GetProcesses().Where(p => { try { return p.SessionId == session && !Core.Boost.IsKept(p.ProcessName) && pick(p.ProcessName); } catch (Exception) { return false; } })
            .GroupBy(p => p.ProcessName, StringComparer.OrdinalIgnoreCase)
            .Select(g => (g.Key, g.Sum(p => { try { return p.WorkingSet64; } catch (Exception) { return 0L; } })))
            .OrderByDescending(x => x.Item2).ToList();
    }

    // was der Boost beim Einschalten anfassen würde; ändert nichts
    public static Plan Prepare()
    {
        var settings = Altdaten.Settings();
        var choice = settings["Boost"];
        var gameMode = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\GameBar", "AutoGameModeEnabled", null) is int g && g == 0 && Altdaten.Flag(choice, "GameMode", true);
        var plans = Core.Boost.Plans(Tool("powercfg.exe", "/list").Output.Split('\n'));
        var active = plans.FirstOrDefault(p => p.Active);
        var fast = active.Guid != null && Core.Boost.IsFast(active.Guid, active.Name);
        var switchPlan = !fast && plans.Any(p => p.Guid == Core.Boost.Performance) && Altdaten.Flag(choice, "PowerPlan", true);
        // fehlt die Auswahl, gelten die Vorgaben; jeder Name muss die Prüfung von Core bestehen
        var names = choice?["Services"] is JsonArray ? Altdaten.List(choice, "Services") : Core.Boost.Services.ToList();
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var services = new List<(string, string)>();
        foreach (var name in names.Where(Core.Boost.IsSafeName).Distinct(StringComparer.OrdinalIgnoreCase))
            try
            {
                using var service = new ServiceController(name);
                if (service.Status != ServiceControllerStatus.Running) continue;
                string? path = null;
                using (var s = new ManagementObjectSearcher("SELECT PathName FROM Win32_Service WHERE Name = '" + name + "'"))
                    foreach (ManagementObject o in s.Get()) path = o["PathName"]?.ToString();
                if (Core.Boost.IsAllowed(name, Core.Boost.Services, path, windir)) services.Add((name, service.DisplayName));
            }
            catch (Exception) { }   // gibt es nicht
        var apps = Altdaten.List(choice, "Apps");
        return new(gameMode, active.Guid != null ? (active.Guid, active.Name) : null, switchPlan, services,
            Programs(n => apps.Contains(n, StringComparer.OrdinalIgnoreCase)), Programs(_ => true).Take(3).ToList(), Altdaten.List(settings, "BoostGames"), FreeMemory(), TotalMemory());
    }

    static void Run(Action<Action<string>> work)
    {
        if (Busy) return;
        Busy = true;
        Message = "";
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        new Thread(() =>
        {
            var message = "";
            try { work(text => ui.BeginInvoke(() => { Step = text; Changed?.Invoke(); })); }
            catch (Exception e) { message = e.Message; }
            ui.BeginInvoke(() => { Busy = false; Step = ""; Message = message; Changed?.Invoke(); });
        }) { IsBackground = true }.Start();
    }

    // wie Stop-AppGroup: Fenster schließen lassen (8 Sekunden), was dann noch offen ist, bleibt offen; danach nur
    // noch Hintergrundprozesse desselben Programms beenden
    static bool Close(string name)
    {
        var session = Process.GetCurrentProcess().SessionId;
        var all = Process.GetProcessesByName(name).Where(p => { try { return p.SessionId == session; } catch (Exception) { return false; } }).ToList();
        var windows = all.Where(p => { try { return p.MainWindowHandle != IntPtr.Zero; } catch (Exception) { return false; } }).ToList();
        foreach (var p in windows) try { p.CloseMainWindow(); } catch (Exception) { }
        var deadline = DateTime.Now.AddSeconds(8);
        while (DateTime.Now < deadline && windows.Any(p => { try { p.Refresh(); return !p.HasExited; } catch (Exception) { return false; } })) Thread.Sleep(400);
        if (windows.Any(p => { try { return !p.HasExited; } catch (Exception) { return false; } })) return false;   // wartet vermutlich auf "Speichern?"
        foreach (var p in Process.GetProcessesByName(name)) try { if (p.SessionId == session) p.Kill(); } catch (Exception) { }
        return true;
    }

    public static void On(Plan plan, bool closeApps) => Run(report => TurnOn(plan, closeApps, report));

    // ohne Fenster für den Helfer (Boost automatisch): schließt nie Programme und leert nie die Zwischenablage.
    // Ist nichts umzustellen, bleibt der Boost aus – der Helfer meldet dann „Nichts umzustellen“.
    public static bool OnQuietly(string? game)
    {
        if (IsOn) return true;
        var plan = Prepare() with { Apps = new() };
        if (!plan.GameModeOff && !plan.SwitchPlan && plan.Services.Count == 0) return false;
        TurnOn(plan, false, _ => { }, game);
        return true;
    }

    public static void OffQuietly() { if (IsOn) TurnOff(_ => { }); }

    static void TurnOn(Plan plan, bool closeApps, Action<string> report, string? game = null)
    {
        var before = FreeMemory();
        if (plan.GameModeOff)
        {
            report("Spielmodus wird eingeschaltet …");
            Registry.SetValue(@"HKEY_CURRENT_USER\Software\Microsoft\GameBar", "AutoGameModeEnabled", 1, RegistryValueKind.DWord);
        }
        if (plan.SwitchPlan)
        {
            report("Energieplan auf Höchstleistung …");
            Tool("powercfg.exe", "/setactive " + Core.Boost.Performance);
        }
        var stopped = new List<string>();
        if (plan.Services.Count > 0) report("Dienste werden pausiert …");
        foreach (var (name, _) in plan.Services)
            try
            {
                using var service = new ServiceController(name);
                service.Stop();
                service.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(20));
                stopped.Add(name);
            }
            catch (Exception) { }
        var closed = new List<string>();
        if (closeApps && plan.Apps.Count > 0)
        {
            report("Programme werden geschlossen …");
            foreach (var (name, _) in plan.Apps) if (Close(name)) closed.Add(name);
        }
        report("Arbeitsspeicher wird frei …");
        // Zwischenablage leeren, wenn unter Einrichten gewählt (die Zwischenablage gehört dem Fenster-Thread)
        if (game == null && Altdaten.Flag(Altdaten.Settings()["Boost"], "Clipboard", false))
            try { System.Windows.Application.Current.Dispatcher.Invoke(System.Windows.Clipboard.Clear); } catch (Exception) { }
        var now = Core.Boost.Plans(Tool("powercfg.exe", "/list").Output.Split('\n')).FirstOrDefault(p => p.Active);
        var planChanged = plan.SwitchPlan && plan.Active != null && now.Guid != null && now.Guid != plan.Active.Value.Guid;
        Save(new(DateTime.Now.ToString("dd.MM.yyyy HH:mm"), planChanged ? plan.Active!.Value.Guid : null, planChanged ? plan.Active!.Value.Name : null, stopped, closed, before, before, game));
        Thread.Sleep(2000);
        Save(new(DateTime.Now.ToString("dd.MM.yyyy HH:mm"), planChanged ? plan.Active!.Value.Guid : null, planChanged ? plan.Active!.Value.Name : null, stopped, closed, before, FreeMemory(), game));
    }

    // wie Invoke-GameBoostOff: Energieplan zurück, Dienste wieder starten; geschlossene Programme startet man selbst
    public static void Off() => Run(TurnOff);

    static void TurnOff(Action<string> report)
    {
        var state = State();
        if (state?.PowerPlan is { } guid) { report("Energieplan wird zurückgestellt …"); Tool("powercfg.exe", "/setactive " + guid); }
        if (state?.Services.Count > 0) report("Dienste starten wieder …");
        foreach (var name in state?.Services ?? new())
            try { using var service = new ServiceController(name); if (service.Status == ServiceControllerStatus.Stopped) service.Start(); } catch (Exception) { }
        File.Delete(StateFile);
    }

    // dieselben Felder wie im PowerShell-Programm (ConvertTo-Json), damit es den Zustand lesen kann
    static void Save(Zustand s)
    {
        var json = new JsonObject
        {
            ["Time"] = s.Time, ["PowerPlan"] = s.PowerPlan, ["PowerPlanName"] = s.PowerPlanName,
            ["Services"] = Altdaten.Array(s.Services), ["ClosedApps"] = Altdaten.Array(s.ClosedApps), ["FreeBefore"] = s.FreeBefore, ["FreeAfter"] = s.FreeAfter,
        };
        // für die Boost-Seite: für welches Spiel der Helfer ihn eingeschaltet hat
        if (s.Game != null) json["Game"] = s.Game;
        Directory.CreateDirectory(Altdaten.Folder);
        File.WriteAllText(StateFile, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(true));
    }
}
