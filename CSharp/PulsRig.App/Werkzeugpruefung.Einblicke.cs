using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.IO;
using System.Text;
using System.Text.Json.Nodes;
using System.Xml.Linq;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Werkzeuge, die vor allem zeigen: Standby-Detektiv, Autostart, Treiberverlauf, Gaming-Check und Spiele, dazu die
// alten Treiberpakete für "Speicherplatz freigeben". Wie im PowerShell-Programm ändert Standby-Detektiv und
// Gaming-Check nichts selbst: ihre Schritte öffnen nur die Seite von Windows, an der man es einstellt.
static partial class Werkzeugpruefung
{
    // Ausgabe von powercfg & Co. in der OEM-Codepage der Konsole, sonst stimmen die Umlaute nicht
    static (int Code, List<string> Lines) Console(string file, string arguments)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, file), arguments) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true,
            StandardOutputEncoding = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage) };
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return (process.ExitCode, output.Split('\n').Select(l => l.TrimEnd('\r')).ToList());
    }

    static Schritt Open(string text, string target, string arguments = "") => new(text, () =>
    {
        Process.Start(new ProcessStartInfo(target, arguments) { UseShellExecute = true });
        return "geöffnet";
    }, Optional: true, Admin: false, Ask: false);

    static string Times(int n) => n == 1 ? "1-mal" : n + "-mal";

    // --- Alte Treiberpakete (Speicherplatz) -------------------------------------------------------------------------

    // Klassenname zur GUID, wie ihn Windows unter Control\Class führt, in Wörtern wie Get-OldDriverPackages
    static string ClassName(string guid)
    {
        try { return Treiberspeicher.ClassWord(Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\" + guid, "Class", "") as string); }
        catch (Exception) { return ""; }
    }

    // Pakete aus HKLM\SYSTEM\DriverDatabase (unabhängig von der Sprache, anders als pnputil /enum-drivers)
    static List<(Treiberpaket Package, long Bytes)> OldPackages()
    {
        var packages = new List<Treiberpaket>();
        using (var root = Registry.LocalMachine.OpenSubKey(@"SYSTEM\DriverDatabase\DriverPackages"))
            foreach (var folder in root?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                using var key = root!.OpenSubKey(folder);
                if (key?.GetValue("") is not string inf || !Treiberspeicher.ParseVersion(key.GetValue("Version") as byte[], out var guid, out var date, out var version)) continue;
                packages.Add(new() { Inf = inf, Original = key.GetValue("InfName") as string ?? "", Provider = key.GetValue("Provider") as string ?? "", ClassGuid = guid, Date = date, Version = version, Folder = folder });
            }
        var inUse = Query("SELECT InfName FROM Win32_PnPSignedDriver").Select(d => T(d, "InfName")).Where(i => i.Length > 0).ToList();
        var store = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\DriverStore\FileRepository");
        return Treiberspeicher.Old(packages, inUse).Select(p =>
        {
            long bytes = 0;
            try { bytes = new DirectoryInfo(Path.Combine(store, p.Folder)).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length); } catch (Exception) { }
            return (p, bytes);
        }).OrderByDescending(x => x.bytes).ToList();
    }

    // --- Standby-Detektiv ---------------------------------------------------------------------------------------------

    // wie die Abfrage "Standby": Aufwachen der letzten 14 Tage, wer wecken darf, Aufweck-Timer, Standby-Zeit, was wach hält
    static Werkbefund Standby()
    {
        var lines = new List<Pruefzeile>();
        var wakes = new List<(DateTime When, string Source, string Owner)>();
        var log = true;
        try
        {
            var query = "*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1 and TimeCreated[timediff(@SystemTime) <= " + (long)TimeSpan.FromDays(14).TotalMilliseconds + "]]]";
            using var reader = new EventLogReader(new EventLogQuery("System", PathType.LogName, query) { ReverseDirection = true });
            for (var e = reader.ReadEvent(); e != null; e = reader.ReadEvent())
                using (e)
                {
                    // Feldnamen aus dem XML, damit die Sprache von Windows keine Rolle spielt
                    XNamespace ns = "http://schemas.microsoft.com/win/2004/08/events/event";
                    var fields = XDocument.Parse(e.ToXml()).Descendants(ns + "Data").ToDictionary(d => (string?)d.Attribute("Name") ?? "", d => d.Value.Trim());
                    wakes.Add((e.TimeCreated ?? DateTime.Now, fields.GetValueOrDefault("WakeSourceText", ""), fields.GetValueOrDefault("WakeTimerOwner", "")));
                }
        }
        catch (EventLogNotFoundException) { }
        catch (Exception) { log = false; }

        var opens = new HashSet<string>();
        if (wakes.Count == 0) lines.Add(new(log, log ? "Kein Aufwachen aus dem Standby in 14 Tagen" : "Das Ereignisprotokoll ist nicht lesbar"));
        foreach (var group in wakes.GroupBy(w => Core.Standby.WakeKind(w.Source, w.Owner).Key).OrderByDescending(g => g.Count()).Take(5))
        {
            var list = group.ToList();
            var kind = Core.Standby.WakeKind(list[0].Source, list[0].Owner);
            var night = list.Count(w => w.When.Hour < 6);
            var names = list.Select(w => w.Owner.Length > 0 ? w.Owner : w.Source).Where(n => n.Length > 0).Distinct().Take(2).ToList();
            var parts = new List<string> { Times(list.Count) + " in 14 Tagen, zuletzt " + list[0].When.ToString("dd.MM. HH:mm") + " Uhr" };
            if (night > 0) parts.Add(Times(night) + " nachts");
            if (names.Count > 0 && !kind.Key.StartsWith("dev:")) parts.Add(string.Join(", ", names));
            parts.Add(kind.Hint);
            lines.Add(new(night == 0, kind.Title, string.Join(" · ", parts)));
            if (kind.Open.Length > 0) opens.Add(kind.Open);
        }

        var armed = Core.Standby.Armed(Console("powercfg.exe", "/devicequery wake_armed").Lines);
        lines.Add(new(true, armed.Count == 0 ? "Kein Gerät darf den PC wecken" : armed.Count == 1 ? "1 Gerät darf den PC wecken" : armed.Count + " Geräte dürfen den PC wecken",
            armed.Count == 0 ? "Nur Netzschalter und geplante Aufgaben können ihn aufwecken." : string.Join(", ", armed.Take(3)) + (armed.Count > 3 ? " und " + (armed.Count - 3) + " weitere" : "")));
        if (armed.Count > 0) opens.Add("devmgmt");
        int? Plan(string setting) { try { return Core.Standby.PlanValue(string.Join("\n", Console("powercfg.exe", "/query SCHEME_CURRENT SUB_SLEEP " + setting).Lines)); } catch (Exception) { return null; } }
        switch (Plan("RTCWAKE"))
        {
            case 0: lines.Add(new(true, "Aufweck-Timer sind aus", "Geplante Aufgaben können den PC nicht wecken.")); break;
            case 1: lines.Add(new(true, "Aufweck-Timer sind erlaubt", "Geplante Aufgaben wie Windows Update dürfen den PC wecken.")); opens.Add("timers"); break;
            case 2: lines.Add(new(true, "Nur wichtige Aufweck-Timer", "Nur wichtige Aufgaben von Windows dürfen den PC wecken, etwa ein Neustart nach Updates.")); opens.Add("timers"); break;
        }

        var idle = Plan("STANDBYIDLE");
        if (idle == 0) { lines.Add(new(false, "Standby ist ausgeschaltet", "Im Energieplan steht „Nie“: der PC geht nicht von selbst in den Standby. Das ist der häufigste Grund.")); opens.Add("sleep"); }
        else if (idle is { } seconds)
        {
            var minutes = (int)Math.Round(seconds / 60.0);
            lines.Add(new(true, "Standby nach " + (minutes >= 60 && minutes % 60 == 0 ? minutes / 60 + " Stunden" : minutes + " Minuten") + " ohne Bedienung", "So steht es im Energieplan."));
            opens.Add("sleep");
        }
        List<(string Section, string Kind, string Name, string Why)>? requests = null;
        try { var (code, output) = Console("powercfg.exe", "/requests"); if (code == 0) requests = Core.Standby.Requests(output); } catch (Exception) { }
        if (requests == null) lines.Add(new(true, "Was den PC gerade wach hält, verrät Windows nur mit Adminrechten", "PulsRig als Administrator starten und neu prüfen."));
        else if (requests.Count == 0) lines.Add(new(true, "Gerade hält nichts den PC wach", "Kein Programm, Dienst oder Treiber verhindert den Standby."));
        else foreach (var r in requests.Take(5))
                lines.Add(new(false, r.Name + " " + Core.Standby.RequestText(r.Section), string.Join(" · ", new[] { Core.Standby.KindWord(r.Kind), r.Why }.Where(x => x.Length > 0))));

        var steps = new List<Schritt>();
        if (opens.Contains("devmgmt")) steps.Add(Open("Geräte-Manager öffnen", "devmgmt.msc"));
        if (opens.Contains("timers")) steps.Add(Open("Energieoptionen öffnen (Aufweck-Timer)", "control.exe", "powercfg.cpl,,3"));
        if (opens.Contains("sleep")) steps.Add(Open("Energiesparen in den Einstellungen", "ms-settings:powersleep"));
        return new(lines, "Ereignisprotokoll der letzten 14 Tage und Energieplan. PulsRig ändert hier nichts; im Geräte-Manager: Gerät doppelklicken → Energieverwaltung → „Gerät kann den Computer aus dem Standby aktivieren“.", steps);
    }

    // --- Autostart ----------------------------------------------------------------------------------------------------

    const string Approved = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved";

    // Source: der Run-Schlüssel (ohne Hive) oder die Datei im Autostart-Ordner
    internal sealed record Starteintrag(string Name, string File, string Company, string Description, bool Machine, string Folder, string Where, bool Enabled, bool Exists, string Source)
    {
        // Rest eines deinstallierten Programms: der Eintrag zeigt auf eine Datei, die es nicht mehr gibt
        public bool Orphan => Core.Autostart.IsOrphan(File, System.IO.File.Exists);
    }

    static RegistryKey Hive(bool machine) => machine ? Registry.LocalMachine : Registry.CurrentUser;

    static Starteintrag Entry(string name, string file, bool machine, string folder, string where, string source)
    {
        string company = "", description = "";
        var exists = file.Length > 0 && File.Exists(file);
        try { if (exists) { var info = FileVersionInfo.GetVersionInfo(file); company = (info.CompanyName ?? "").Trim(); description = (info.FileDescription ?? "").Trim(); } } catch (Exception) { }
        byte[]? approved = null;
        try { using var key = Hive(machine).OpenSubKey(Approved + "\\" + folder); approved = key?.GetValue(name) as byte[]; } catch (Exception) { }
        return new(name, file, company, description, machine, folder, where, Core.Autostart.IsEnabled(approved), exists, source);
    }

    // wie die Abfrage "Autostart": Run-Schlüssel und Autostart-Ordner; Aufgaben und Dienste zeigt auch der Task-Manager dort nicht
    internal static List<Starteintrag> StartEntries()
    {
        var entries = new List<Starteintrag>();
        foreach (var (machine, path, folder) in new[] { (false, @"Software\Microsoft\Windows\CurrentVersion\Run", "Run"), (true, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "Run"), (true, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run", "Run32") })
            try
            {
                using var key = Hive(machine).OpenSubKey(path);
                foreach (var name in key?.GetValueNames() ?? Array.Empty<string>())
                    if (name.Length > 0) entries.Add(Entry(name, Core.Autostart.CommandFile(key!.GetValue(name)?.ToString()), machine, folder, machine ? "Alle Benutzer" : "Benutzer", path));
            }
            catch (Exception) { }
        dynamic? shell = null;
        try { shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!); } catch (Exception) { }
        foreach (var (machine, path) in new[] { (false, Environment.GetFolderPath(Environment.SpecialFolder.Startup)), (true, Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup)) })
        {
            if (path.Length == 0 || !Directory.Exists(path)) continue;
            foreach (var file in new DirectoryInfo(path).GetFiles().Where(f => !f.Name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)))
            {
                var target = file.FullName;
                if (file.Extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase) && shell != null) try { target = (string)shell!.CreateShortcut(file.FullName).TargetPath; } catch (Exception) { }
                entries.Add(Entry(file.Name, target, machine, "StartupFolder", machine ? "Alle Benutzer" : "Benutzer", file.FullName));
            }
        }
        return entries.OrderBy(e => !e.Enabled).ThenBy(e => Core.Autostart.Title(e.Name, e.Description)).ToList();
    }

    // Ausgeschaltet wird wie im Task-Manager: der Eintrag bleibt, Windows vermerkt unter StartupApproved "nicht starten"
    static Werkbefund Autostart()
    {
        var entries = StartEntries();
        var lines = new List<Pruefzeile>();
        var steps = new List<Schritt>();
        if (entries.Count == 0) lines.Add(new(true, "Beim Anmelden startet kein Programm von selbst"));
        var orphans = entries.Where(e => e.Orphan).ToList();
        foreach (var e in entries)
        {
            var title = Core.Autostart.Title(e.Name, e.Description);
            if (e.Orphan)
            {
                // nur nennen, ob vom Programm noch ein Ordner da ist; gelöscht wird allein der Eintrag
                var folder = e.File.Length > 0 ? Path.GetDirectoryName(e.File) ?? "" : "";
                var rest = e.File.Length == 0 ? "" : folder.Length > 0 && Directory.Exists(folder) ? "Ordner " + folder + " liegt noch da" : "keine Programmdateien mehr da";
                lines.Add(new(false, title, string.Join(" · ", new[] { e.File.Length > 0 ? "Programm deinstalliert" : "Eintrag ohne Befehl, startet nichts", Path.GetFileName(e.File), e.Where, rest }.Where(p => p.Length > 0)),
                    RemoveStep(e, title), Button: "Entfernen"));
                continue;
            }
            var parts = new[] { e.Company, e.File.Length > 0 ? Path.GetFileName(e.File) : "", e.Where }.Where(p => p.Length > 0);
            var on = !e.Enabled;
            lines.Add(new(true, title, string.Join(" · ", parts), new(title + (on ? " einschalten" : " ausschalten"), () =>
            {
                using var key = Hive(e.Machine).CreateSubKey(Approved + "\\" + e.Folder);
                key.SetValue(e.Name, Core.Autostart.Approved(on, DateTime.Now), RegistryValueKind.Binary);
                return on ? "startet wieder mit Windows" : "startet nicht mehr mit Windows";
            }, Optional: true, Admin: e.Machine, Ask: false), On: e.Enabled));
        }
        if (orphans.Count > 1)
            steps.Add(new("Alle " + orphans.Count + " Reste entfernen", () => string.Join("; ", orphans.Select(e => RemoveStep(e, Core.Autostart.Title(e.Name, e.Description)).Run())), Optional: true, Admin: orphans.Any(e => e.Machine)));
        var active = entries.Where(e => !e.Orphan).ToList();
        return new(lines, active.Count(e => e.Enabled) + " von " + active.Count + " starten mit Windows. Der Schalter wirkt ab der nächsten Anmeldung und lässt sich jederzeit zurücknehmen, auch im Task-Manager. Einträge für alle Benutzer nur mit Adminrechten."
            + (orphans.Count == 0 ? "" : orphans.Count == 1 ? " Ein Eintrag ist der Rest eines deinstallierten Programms." : " " + orphans.Count + " Einträge sind Reste deinstallierter Programme.")
            + (orphans.Count == 0 ? "" : " Entfernen löscht nur den Autostart-Eintrag und legt vorher eine Sicherung an; Programmdateien bleiben unberührt."), steps);
    }

    // Rest entfernen: Run-Wert vorher als .reg-Datei sichern (Doppelklick holt ihn zurück), eine Verknüpfung nur verschieben
    static Schritt RemoveStep(Starteintrag e, string title) => new(title + " aus dem Autostart entfernen", () =>
    {
        var backup = Path.Combine(Werkzeuglauf.Backups, "Autostart");
        Directory.CreateDirectory(backup);
        var stamp = DateTime.Now.ToString("yyyy-MM-dd_HHmmss") + "_" + string.Concat(e.Name.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        if (e.Folder == "StartupFolder")
        {
            File.Move(e.Source, Path.Combine(backup, stamp));
        }
        else
        {
            using var key = Hive(e.Machine).OpenSubKey(e.Source, true) ?? throw new InvalidOperationException("Eintrag nicht mehr da");
            var value = key.GetValue(e.Name, "", RegistryValueOptions.DoNotExpandEnvironmentNames)?.ToString() ?? "";
            var reg = "Windows Registry Editor Version 5.00\r\n\r\n[" + (e.Machine ? "HKEY_LOCAL_MACHINE\\" : "HKEY_CURRENT_USER\\") + e.Source + "]\r\n"
                + Core.Autostart.RegLine(e.Name, value, key.GetValueKind(e.Name) == RegistryValueKind.ExpandString) + "\r\n";
            File.WriteAllText(Path.Combine(backup, stamp + ".reg"), reg, Encoding.Unicode);
            key.DeleteValue(e.Name);
        }
        try { using var approved = Hive(e.Machine).OpenSubKey(Approved + "\\" + e.Folder, true); approved?.DeleteValue(e.Name, false); } catch (Exception) { }
        return "entfernt, Sicherung in " + backup;
    }, Optional: true, Admin: e.Machine);

    // --- Treiberverlauf -----------------------------------------------------------------------------------------------

    // wie Get-DriverHistory: was Windows Update an Treibern eingespielt hat und wann welches Treiberpaket dazukam
    static Werkbefund DriverHistory()
    {
        var lines = new List<Pruefzeile>();
        var updates = new List<(DateTime When, string Title, string Result, bool Removed, bool Ok)>();
        try
        {
            dynamic searcher = ((dynamic)Activator.CreateInstance(Type.GetTypeFromProgID("Microsoft.Update.Session")!)!).CreateUpdateSearcher();
            int total = searcher.GetTotalHistoryCount();
            if (total > 0)
                foreach (dynamic entry in searcher.QueryHistory(0, Math.Min(total, 400)))
                {
                    string title = entry.Title ?? "";
                    if (!Verlauf.IsDriverUpdate(title)) continue;
                    int code = entry.ResultCode;
                    updates.Add((((DateTime)entry.Date).ToLocalTime(), title, Verlauf.Result(code), (int)entry.Operation == 2, code is 2 or 3));
                }
        }
        catch (Exception) { lines.Add(new(false, "Windows Update", "Der Verlauf ließ sich nicht lesen")); }
        lines.Add(new(true, "WINDOWS UPDATE", updates.Count == 0 ? "keine Treiber im Verlauf" : updates.Count + " Treiber, die neuesten zuerst"));
        foreach (var u in updates.OrderByDescending(u => u.When).Take(12))
            lines.Add(new(u.Ok, "  " + u.When.ToString("dd.MM.yyyy HH:mm"), u.Title + " · " + (u.Removed ? "entfernt" : u.Result)));

        var inf = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "INF");
        var packages = Query("SELECT InfName, DeviceName, DriverProviderName, DriverVersion FROM Win32_PnPSignedDriver")
            .Where(d => T(d, "InfName").StartsWith("oem", StringComparison.OrdinalIgnoreCase))
            .GroupBy(d => T(d, "InfName").ToLowerInvariant())
            .Select(g =>
            {
                var file = new FileInfo(Path.Combine(inf, g.Key));
                return (Added: file.Exists ? file.CreationTime : DateTime.MinValue, First: g.First(), Names: g.Select(d => T(d, "DeviceName")).Where(n => n.Length > 0).Distinct().ToList());
            })
            .Where(p => p.Added > DateTime.MinValue).OrderByDescending(p => p.Added).ToList();
        lines.Add(new(true, "TREIBERPAKETE", packages.Count + " von Drittherstellern in Gebrauch, zuletzt hinzugekommen zuerst"));
        foreach (var p in packages.Take(12))
            lines.Add(new(true, "  " + p.Added.ToString("dd.MM.yyyy"), T(p.First, "DriverProviderName") + " " + T(p.First, "DriverVersion") + " · " + Verlauf.Devices(p.Names)));
        return new(lines, "Gibt es nach einem Treiber Probleme, holt „Treiber zurückholen“ eine Sicherung zurück; ein Update nimmt der Wiederherstellungspunkt von vorher zurück.", new());
    }

    // --- Gaming-Check -------------------------------------------------------------------------------------------------

    // Wert der letzten Prüfung, für die Kachel auf der Startseite
    public static int? GameScore { get; private set; }

    // wie Get-GameChecks: sieben Punkte mit Ampel; Wert 0 bis 100 (grün 2, gelb 1, rot 0, grau zählt nicht)
    static Werkbefund GamingCheck()
    {
        var checks = new List<(string Name, string Tone, string State, string Text, Schritt? Open)>();
        var displays = Abfragen.Displays();
        if (displays.Count == 0) checks.Add(("Bildwiederholrate", "", "nicht lesbar", "Windows nennt die Bildschirmmodi nicht.", null));
        else if (displays.Where(d => d.Max > d.Hz + 1).OrderByDescending(d => d.Max).FirstOrDefault() is { } slow)
            checks.Add(("Bildwiederholrate", "bad", slow.Hz + " Hz", slow.Name + " läuft mit " + slow.Hz + " statt " + slow.Max + " Hz: unter „Erweiterte Anzeige“ umstellen.", Open("Erweiterte Anzeige öffnen", "ms-settings:display-advanced")));
        else
        {
            var d = displays.FirstOrDefault(x => x.Primary) ?? displays[0];
            checks.Add(("Bildwiederholrate", "good", d.Hz + " Hz", displays.Count > 1 ? "Alle Bildschirme laufen mit der höchsten Rate, die sie bei dieser Auflösung können." : d.Name + " läuft mit der höchsten Rate, die er bei dieser Auflösung kann.", null));
        }

        int? bar = null;
        var smi = Abfragen.NvidiaSmi();
        if (smi.Length > 0)
            try
            {
                using var p = Process.Start(new ProcessStartInfo(smi, "-q -d MEMORY") { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true })!;
                bar = Spielcheck.Bar1(p.StandardOutput.ReadToEnd());
                p.WaitForExit();
            }
            catch (Exception) { }
        if (bar is > 256) checks.Add(("Resizable BAR", "good", "an", "Die Grafikkarte erreicht ihren ganzen Speicher auf einmal (" + Math.Round(bar.Value / 1024.0) + " GB). Das bringt in vielen neuen Spielen ein paar Prozent.", null));
        else if (bar != null) checks.Add(("Resizable BAR", "warn", "aus", "Im BIOS „Above 4G Decoding“ und „Re-Size BAR“ einschalten: bringt in neuen Spielen ein paar Prozent. PulsRig ändert am BIOS nichts.", null));
        else checks.Add(("Resizable BAR", "", "nicht prüfbar", "Lässt sich nur bei NVIDIA-Grafikkarten auslesen.", null));

        var graphics = Open("Grafikeinstellungen öffnen", "ms-settings:display-advancedgraphics");
        switch (Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\GraphicsDrivers", "HwSchMode", null) as int?)
        {
            case 2: checks.Add(("GPU-Planung", "good", "an", "Die hardwarebeschleunigte GPU-Planung ist an. Sie ist Voraussetzung für Frame Generation (DLSS 3 und neuer).", null)); break;
            case 1: checks.Add(("GPU-Planung", "warn", "aus", "Unter Grafikeinstellungen einschalten und neu starten. Nötig für Frame Generation (DLSS 3 und neuer).", graphics)); break;
            default: checks.Add(("GPU-Planung", "", "Vorgabe", "Nicht festgelegt: Windows entscheidet selbst. Unter Grafikeinstellungen steht, ob sie an ist.", graphics)); break;
        }

        bool? hvci = null;
        try { hvci = Query("SELECT SecurityServicesRunning FROM Win32_DeviceGuard", @"root\Microsoft\Windows\DeviceGuard").Select(g => g["SecurityServicesRunning"] as uint[]).FirstOrDefault()?.Contains(2u); }
        catch (Exception)
        {
            if (Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity", "Enabled", null) is int on) hvci = on == 1;
        }
        // an ist gelb, nie rot: sie kostet etwas Leistung, schützt aber - abschalten ist eine Abwägung
        checks.Add(hvci switch
        {
            true => ("Kernisolierung", "warn", "an", "Schützt vor Schadtreibern, kostet in manchen Spielen 5–10 %. Abschalten ist eine Abwägung.", Open("Kernisolierung öffnen", "windowsdefender://coreisolation")),
            false => ("Kernisolierung", "good", "aus", "Keine Bremse durch die Speicher-Integrität. Dafür fehlt dieser zusätzliche Schutz vor Schadtreibern.", null),
            _ => ("Kernisolierung", "", "nicht lesbar", "Windows gibt den Zustand auf diesem PC nicht heraus.", null),
        });

        var (guid, plan) = Spielcheck.ActivePlan(string.Join("\n", Console("powercfg.exe", "/getactivescheme").Lines));
        var battery = false;
        try { battery = Query("SELECT Name FROM Win32_Battery").Any(); } catch (Exception) { }
        var planTone = Spielcheck.PlanTone(guid, plan, battery);
        checks.Add(planTone switch
        {
            "good" => ("Energieplan", "good", plan, battery && !plan.Contains("Höchst") ? "Für ein Notebook die richtige Wahl; zum Spielen ans Netzteil." : "Der Prozessor darf jederzeit voll takten.", null),
            "bad" => ("Energieplan", "bad", plan, "Bremst Prozessor und Grafik. Der Boost stellt fürs Spielen auf Höchstleistung um.", null),
            "warn" => ("Energieplan", "warn", plan, "Für Spiele in Ordnung, taktet aber träger hoch. Der Boost stellt beim Spielen um.", null),
            _ => ("Energieplan", "", "nicht lesbar", "Windows nennt den aktiven Energieplan nicht.", null),
        });

        var memory = Speicher.Profile(Abfragen.Memory().Modules);
        if (memory?.Tone == "Good") checks.Add(("Arbeitsspeicher (XMP)", "good", "voller Takt", memory.Title, null));
        else if (memory?.Tone == "Warn")
            checks.Add(("Arbeitsspeicher (XMP)", memory.Rated - memory.Now >= 400 ? "bad" : "warn", memory.Now.ToString("N0", Ui.De) + " MHz", "Läuft mit " + memory.Now.ToString("N0", Ui.De) + " statt " + memory.Rated.ToString("N0", Ui.De) + " MHz: im BIOS XMP, DOCP oder EXPO einschalten.", null));
        else checks.Add(("Arbeitsspeicher (XMP)", "", memory != null ? memory.Now.ToString("N0", Ui.De) + " MHz" : "nicht lesbar", "Für welchen Takt die Riegel gebaut sind, verrät Windows bei diesem Modell nicht.", null));

        // fehlt der Wert, ist der Spielmodus an (Vorgabe von Windows)
        var gameMode = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\GameBar", "AutoGameModeEnabled", null) is not int mode || mode != 0;
        checks.Add(gameMode ? ("Spielmodus", "good", "an", "Windows gibt laufenden Spielen Vorrang und hält Updates zurück.", null)
            : ("Spielmodus", "warn", "aus", "Einschalten: Windows gibt laufenden Spielen dann Vorrang.", Open("Spielmodus öffnen", "ms-settings:gaming-gamemode")));

        var score = Spielcheck.Score(checks.Select(c => c.Tone));
        GameScore = score;
        var lines = checks.Select(c => new Pruefzeile(c.Tone != "warn" && c.Tone != "bad", c.Name + " · " + c.State, c.Text)).ToList();
        var steps = checks.Where(c => c.Open != null).Select(c => c.Open!).GroupBy(s => s.Text).Select(g => g.First()).ToList();
        var todo = checks.Count(c => c.Tone is "warn" or "bad");
        return new(lines, (score is { } s ? s + " von 100 · " : "") + checks.Count(c => c.Tone == "good") + " grün" + (todo > 0 ? ", " + todo + " zu prüfen" : "") + ". PulsRig ändert hier nichts: die Knöpfe öffnen die Stelle, an der man es einstellt.", steps);
    }

    // --- Spiele & Aufzeichnung ----------------------------------------------------------------------------------------

    static string OldFolder() => Altdaten.Folder;

    static List<string> SettingList(JsonObject? settings, string name) => Altdaten.List(settings, name);

    // wie Invoke-GamesAction 'record'/'unrecord': die eigene Liste der Aufzeichnung, nicht die des Boosts
    static string SetRecording(string exe, bool on)
    {
        Altdaten.Change(settings =>
        {
            var list = Altdaten.List(settings, "RecordList").Where(x => !x.Equals(exe, StringComparison.OrdinalIgnoreCase)).ToList();
            if (on) { list.Add(exe); if (!Altdaten.Flag(settings, "RecordGames", true)) settings["RecordGames"] = true; }
            settings["RecordList"] = Altdaten.Array(list);
        });
        return on ? "wird beim nächsten Spielen aufgezeichnet (Helfer neben der Uhr)" : "wird nicht mehr aufgezeichnet";
    }

    // wie Get-KnownGames: Spiele, die Windows erkannt hat (Spielleiste), je Programmdatei einmal
    public static Dictionary<string, (string Name, string Exe, string Path)> KnownGames()
    {
        var games = new Dictionary<string, (string Name, string Exe, string Path)>(StringComparer.OrdinalIgnoreCase);
        using (var store = Registry.CurrentUser.OpenSubKey(@"System\GameConfigStore\Children"))
            foreach (var child in store?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                using var key = store!.OpenSubKey(child);
                if (key?.GetValue("MatchedExeFullPath") is not string path || !File.Exists(path)) continue;
                // Plattformen, die Windows als Spiel führt, die aber keines sind (Google Play Games)
                if (path.Contains(@"\Google\Play Games\", StringComparison.OrdinalIgnoreCase)) continue;
                var exe = Path.GetFileNameWithoutExtension(path);
                if (games.ContainsKey(exe)) continue;
                var name = Spielcheck.GameName(path);
                if (name.Length == 0) try { name = (FileVersionInfo.GetVersionInfo(path).FileDescription ?? "").Trim(); } catch (Exception) { }
                games[exe] = (name.Length > 0 ? name : exe, exe, path);
            }
        return games;
    }

    // wie New-GameRow: jedes Spiel mit Laufwerk, letzter Aufzeichnung und Zustand
    static Werkbefund Games()
    {
        var games = KnownGames();
        var settings = Altdaten.Settings();
        var boost = SettingList(settings, "BoostGames");
        var own = SettingList(settings, "RecordList");
        var records = Path.Combine(OldFolder(), "Aufzeichnungen");
        var files = Directory.Exists(records) ? new DirectoryInfo(records).GetFiles("*.csv").OrderByDescending(f => f.Name).ToList() : new();
        var drives = Abfragen.Drives();
        string Kind(string path)
        {
            var letter = path.Length > 1 && path[1] == ':' ? path[..1].ToUpperInvariant() : "";
            var disk = drives.Disks.FirstOrDefault(d => d.Letters.Contains(letter));
            var where = letter.Length > 0 ? letter + ":" : "unbekanntes Laufwerk";
            return disk == null ? where : disk.Media == "HDD" ? where + " Festplatte (HDD): lädt langsamer, beim Nachladen sind Ruckler möglich" : disk.Bus == "NVMe" ? where + " NVMe-SSD" : disk.Media == "SSD" ? where + " SSD" : where;
        }
        var running = Process.GetProcesses().Select(p => { try { return p.ProcessName; } catch (Exception) { return ""; } }).ToHashSet(StringComparer.OrdinalIgnoreCase);

        var lines = new List<Pruefzeile>();
        var steps = new List<Schritt>();
        if (games.Count == 0) lines.Add(new(true, "Windows kennt noch keine Spiele", "Sobald ein Spiel einmal gelaufen ist, steht es hier."));
        foreach (var g in games.Values.OrderBy(g => running.Contains(g.Exe) ? 0 : 1).ThenBy(g => Kind(g.Path).Contains("HDD") ? 0 : 1).ThenBy(g => g.Name))
        {
            var where = Kind(g.Path);
            var parts = new List<string> { where };
            if (running.Contains(g.Exe)) parts.Add("läuft gerade");
            var isBoost = boost.Contains(g.Exe, StringComparer.OrdinalIgnoreCase);
            var isOwn = own.Contains(g.Exe, StringComparer.OrdinalIgnoreCase);
            var file = files.FirstOrDefault(f => f.Name.EndsWith("_" + g.Exe + ".csv", StringComparison.OrdinalIgnoreCase));
            var warm = false;
            if (file != null)
            {
                // wie New-GameRow: letzte Sitzung mit Dauer, höchsten Temperaturen und Drosseln
                try
                {
                    var rec = SensorPage.Read(file.FullName);
                    var sum = Aufzeichnung.Summary(rec);
                    var de = System.Globalization.CultureInfo.GetCultureInfo("de-DE");
                    parts.Add("zuletzt gespielt " + rec.Begin.ToString("dd.MM.") + " (" + Aufzeichnung.Duration(rec.Seconds) + ")");
                    if (sum.CpuMax is double cpuMax) parts.Add(string.Format(de, "Prozessor bis {0:N0} °C", cpuMax));
                    if (sum.GpuMax is double gpuMax) parts.Add(string.Format(de, "Grafikkarte bis {0:N0} °C", gpuMax));
                    warm = sum.Tone == "warn";
                    parts.Add(warm ? "zu warm oder gedrosselt" : "kein Drosseln");
                }
                catch (Exception) { parts.Add("letzte Sitzung nicht lesbar"); }
                parts.Add("Verlauf unter Sensoren");
            }
            else if (isBoost || isOwn) parts.Add("wird beim nächsten Spielen aufgezeichnet");
            else parts.Add("wird nicht aufgezeichnet");
            if (isBoost) parts.Add("Boost-Spiel");
            lines.Add(new(!where.Contains("HDD") && !warm, g.Name, string.Join(" · ", parts)));
            var exe = g.Exe;
            // Boost-Spiele werden immer aufgezeichnet; abwählen lässt sich nur die eigene Liste
            if (!isBoost && !isOwn) steps.Add(new(g.Name + " aufzeichnen", () => SetRecording(exe, true), Optional: true, Admin: false, Ask: false));
            else if (isOwn && !isBoost) steps.Add(new(g.Name + " nicht aufzeichnen", () => SetRecording(exe, false), Optional: true, Admin: false, Ask: false));
        }
        return new(lines, games.Count + " Spiele · aufgezeichnet werden die Boost-Spiele und die hier gewählten – „Aufzeichnen“ schaltet keinen Boost ein. Aufgezeichnet wird im Helfer neben der Uhr.", steps);
    }
}
