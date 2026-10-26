using System.IO;
using System.IO.Compression;
using System.Security;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace PulsRig.App;

// Bericht & Diagnose in einer ZIP-Datei wie Save-ReportZip und New-DiagnosePackage im PowerShell-Programm:
// der Prüfbericht als Webseite, die Angaben zum PC als Text und, falls gescannt, das Ergebnis des Scans.
// Nicht enthalten: Seriennummern, Benutzername und Name des PCs; wo sie in Texten stehen, kommen Platzhalter.
static class Diagnosepaket
{
    public static string LastFile { get; private set; } = "";

    // Ersetzt Benutzername und Name des PCs wie Hide-DiagnoseNames
    public static string HideNames(string text)
    {
        foreach (var (name, mark) in new[] { (Environment.UserName, "BENUTZER"), (Environment.MachineName, "PC") })
            if (name.Length >= 3) text = Regex.Replace(text, Regex.Escape(name), mark, RegexOptions.IgnoreCase);
        return text;
    }

    // Baut das Paket und gibt den Pfad zurück; Ziel ist der Desktop, sonst Downloads, sonst der Datenordner
    public static string Save()
    {
        var stamp = DateTime.Now.ToString("yyyy-MM-dd-HHmm");
        var files = new Dictionary<string, string>
        {
            ["Angaben.txt"] = HideNames(Angaben()),
            ["PulsRig-Prüfbericht-" + DateTime.Now.ToString("yyyy-MM-dd") + ".html"] = ReportHtml(),
        };
        if (Treiberscan.Last is { } scan) files["Letzter-Scan.json"] = HideNames(System.Text.Json.JsonSerializer.Serialize(scan, new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        var stress = Path.Combine(Belastung.Folder, "Stabilitaetstest.json");
        if (File.Exists(stress)) files["Stabilitaetstest.json"] = HideNames(File.ReadAllText(stress));
        if (File.Exists(Fehlerprotokoll.File)) files["PulsRig-Fehler.log"] = HideNames(File.ReadAllText(Fehlerprotokoll.File));

        // erst im Temp-Ordner packen, dann an den Zielort kopieren: so scheitert das Packen nicht am Zielordner
        var packed = Path.Combine(Path.GetTempPath(), "PulsRig-Paket-" + stamp + "-" + Environment.ProcessId + ".zip");
        try
        {
            using (var zip = ZipFile.Open(packed, ZipArchiveMode.Create))
                foreach (var (name, content) in files)
                {
                    using var writer = new StreamWriter(zip.CreateEntry(name, CompressionLevel.Optimal).Open(), new UTF8Encoding(true));
                    writer.Write(content);
                }
            Exception? last = null;
            foreach (var folder in Folders())
            {
                try
                {
                    Directory.CreateDirectory(folder);
                    var target = Path.Combine(folder, "PulsRig-Bericht-" + stamp + ".zip");
                    File.Copy(packed, target, true);
                    return LastFile = target;
                }
                catch (Exception e) { last = e; }
            }
            throw last ?? new IOException("Kein Ordner nimmt die ZIP-Datei an.");
        }
        finally { try { File.Delete(packed); } catch (Exception) { } }
    }

    // Der Desktop fällt z. B. aus, wenn der überwachte Ordnerzugriff ihn sperrt oder OneDrive ihn verschoben hat
    static IEnumerable<string> Folders()
    {
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        if (desktop.Length > 0) yield return desktop;
        var downloads = "";
        try { downloads = Environment.ExpandEnvironmentVariables(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders", "{374DE290-123F-4565-9164-39C4925E467B}", "") as string ?? ""); } catch (Exception) { }
        yield return downloads.Length > 0 ? downloads : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        yield return Belastung.Folder;
    }

    // "auf dem Desktop", "im Ordner Downloads" oder "im Datenordner von PulsRig", wie Get-DiagnosePlace
    public static string Place(string file)
    {
        var folder = Path.GetDirectoryName(file) ?? "";
        if (folder.Equals(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return "auf dem Desktop";
        if (folder.Equals(Belastung.Folder.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return "im Datenordner von PulsRig";
        return "im Ordner Downloads";
    }

    public static void ShowInFolder(string file)
    {
        try { System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + file + "\""); } catch (Exception) { }
    }

    static string Windows()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
            var build = Environment.OSVersion.Version.Build;
            // die Registrierung nennt auch auf Windows 11 noch "Windows 10"
            var name = (key?.GetValue("ProductName") as string ?? "Windows").Replace("Windows 10", build >= 22000 ? "Windows 11" : "Windows 10");
            return name + " " + (key?.GetValue("DisplayVersion") as string ?? "") + " · Build " + build + "." + key?.GetValue("UBR");
        }
        catch (Exception) { return Environment.OSVersion.VersionString; }
    }

    // Angaben zum Gerät für Bericht und Angaben.txt, wie Get-ReportDevice
    static List<(string Key, string Value)> Device()
    {
        var pairs = new List<(string, string)>();
        // die Seite Bericht & Diagnose liest Prozessor und Grafikkarte nicht selbst: dann hier nachfragen
        if ((Hw.Cpu ?? Abfragen.Cpu()) is { } cpu) pairs.Add(("Prozessor", cpu.Name + " · " + cpu.Cores + " Kerne, " + cpu.Threads + " Threads"));
        if ((Hw.Gpu ?? Abfragen.Gpu()) is { } gpu) pairs.Add(("Grafikkarte", gpu.Name + (gpu.Driver.Length > 0 ? " · Treiber " + gpu.Driver + (gpu.Date.Length > 0 ? " vom " + gpu.Date : "") : "")));
        if (Hw.Memory is { Modules.Count: > 0 } m)
        {
            var first = m.Modules[0];
            var parts = new List<string> { Ui.Gb(m.Modules.Sum(x => x.Bytes)), m.Modules.Count == 1 ? "1 Riegel" : m.Modules.Count + " Riegel" };
            if (first.Type.Length > 0) parts.Add(first.Type);
            if (first.Speed > 0) parts.Add(first.Speed.ToString("N0", Ui.De) + " MHz");
            if (first.Rated > first.Speed + 100) parts.Add("gebaut für " + first.Rated.ToString("N0", Ui.De) + " MHz");
            pairs.Add(("Arbeitsspeicher", string.Join(" · ", parts)));
        }
        if (Hw.Drives is { } d)
            foreach (var disk in d.Disks)
                pairs.Add(("Laufwerk " + disk.Number, string.Join(" · ", new[] { disk.Name, disk.Bus == "NVMe" ? "NVMe-SSD" : disk.Media, Ui.Size(disk.Size), string.Join(" ", disk.Letters.Select(l => l + ":")) }.Where(x => x.Length > 0))));
        pairs.Add(("Windows", Windows()));
        return pairs;
    }

    static string Angaben()
    {
        var b = new StringBuilder();
        b.AppendLine("PulsRig-Diagnose vom " + DateTime.Now.ToString("dd.MM.yyyy HH:mm"));
        b.AppendLine().AppendLine("== PulsRig ==");
        b.AppendLine("Oberfläche: PulsRig.App " + Core.PulsRigInfo.Version + (Neuefassung.Build.Length > 0 ? ", gebaut " + Neuefassung.Build : ""));
        b.AppendLine("Adminrechte: " + (App.IsAdmin ? "ja" : "nein"));
        b.AppendLine("Programmordner: " + AppContext.BaseDirectory);
        // woher die Temperatur des Prozessors kommt oder warum nicht (PulsRig-Temperatur.cs)
        b.AppendLine("Temperatur des Prozessors: " + (PulsRigCpuTemp.Source.Length > 0 ? PulsRigCpuTemp.Source + " (" + PulsRigCpuTemp.Sensor + ")" : "keine, Grund: " + (Live.CpuTempStatus.Length > 0 ? Live.CpuTempStatus : PulsRigCpuTemp.Status))
            + (PulsRigCpuTemp.Error.Length > 0 ? " · LibreHardwareMonitor: " + PulsRigCpuTemp.Error : ""));
        var me = System.Diagnostics.Process.GetCurrentProcess();
        b.AppendLine("Arbeitsspeicher des Programms: " + (me.WorkingSet64 / 1048576.0).ToString("N0", Ui.De) + " MB belegt");
        b.AppendLine().AppendLine("== Gerät ==");
        foreach (var (key, value) in Device()) b.AppendLine(key + ": " + value);
        b.AppendLine().AppendLine("== Prüfungen ==");
        foreach (var c in Bericht.Checks()) b.AppendLine(c.Name + " [" + c.Kind + "]: " + c.Text);
        b.AppendLine().AppendLine("== Letzter Scan ==");
        if (Treiberscan.Last is not { } s) b.AppendLine("Noch nicht gescannt.");
        else
        {
            b.AppendLine("Vom " + s.When.ToString("dd.MM.yyyy HH:mm") + " · Geräte: " + s.Devices + " · neuere Treiber: " + s.Updates.Count + " von Windows Update · Gerätefehler: " + s.Problems.Count + " · Katalog-Hinweise: " + s.Hints.Count);
            b.AppendLine("Quellen ohne Antwort: " + (s.Failed.Count > 0 ? string.Join(", ", s.Failed) : "keine"));
            if (s.SearchError.Length > 0) b.AppendLine("Windows Update: " + s.SearchError);
            foreach (var v in new[] { s.Nvidia, s.Radeon, s.Amd }) if (v != null) b.AppendLine(v.Source + " (" + v.Device + "): installiert " + v.Installed + ", neueste " + v.Latest);
            foreach (var p in s.Problems) b.AppendLine("Gerätefehler: " + p.Name + " (Code " + p.Code + ") · " + p.Id.Split("&SUBSYS")[0] + (p.Catalog.Length > 0 ? " · im Katalog: " + p.Catalog : ""));
        }
        return b.ToString();
    }

    static string E(string text) => SecurityElement.Escape(text) ?? "";

    static string ReportHtml()
    {
        var checks = Bericht.Checks();
        var verdict = Bericht.Verdict(checks);
        var checkHtml = checks.Select(c => string.Format("<div class=\"check {0}\"><div><b>{1}</b><p>{2}</p></div><span class=\"pill\">{3}</span></div>",
            c.Kind, E(c.Name), E(c.Text).Replace("\n", "<br>"), c.Kind switch { "good" => "in Ordnung", "warn" => "auffällig", "bad" => "Fehler", _ => "offen" }));
        var deviceHtml = Device().Select(p => "<tr><th>" + E(p.Key) + "</th><td>" + E(p.Value) + "</td></tr>");
        // in der Kopfzeile steht das Gerät, nicht der Name des PCs im Netzwerk: Berichte werden weitergegeben
        var name = Hw.Cpu?.Name ?? "Dieser PC";
        return Template
            .Replace("{{NAME}}", E(name))
            .Replace("{{TIME}}", DateTime.Now.ToString("dd.MM.yyyy HH:mm"))
            .Replace("{{TONE}}", verdict.Tone)
            .Replace("{{VERDICT}}", E(verdict.Title))
            .Replace("{{REST}}", E(verdict.Rest.Length > 0 ? verdict.Rest + "." : "Jede Prüfung des Berichts ist gelaufen."))
            .Replace("{{CHECKS}}", string.Join("\n", checkHtml))
            .Replace("{{DEVICE}}", string.Join("\n", deviceHtml));
    }

    // Vorlage wie $script:ReportTemplate, mit den Farben der Reihe Q: dunkel am Bildschirm, hell und sparsam auf Papier
    const string Template = """
        <!DOCTYPE html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>PulsRig Prüfbericht – {{NAME}}</title>
        <style>
          :root { --bg:#09060D; --card:#0B0710; --line:#22172F; --text:#E2DCEB; --dim:#8C819F; --a1:#8C6BD6; --a2:#A8326F; --good:#5EE0A0; --warn:#F2B661; --bad:#F07A7A; }
          * { box-sizing:border-box; }
          body { margin:0; padding:32px 16px; background:var(--bg); color:var(--text); font:15px/1.5 "Segoe UI Variable Text","Segoe UI",system-ui,sans-serif; }
          main { max-width:820px; margin:0 auto; }
          header { display:flex; justify-content:space-between; align-items:flex-end; gap:16px; flex-wrap:wrap; padding-bottom:18px; border-bottom:2px solid; border-image:linear-gradient(90deg,var(--a1),var(--a2)) 1; }
          .brand { font-size:13px; font-weight:600; letter-spacing:.14em; text-transform:uppercase; color:var(--a1); }
          h1 { margin:2px 0 0; font-size:30px; font-weight:600; letter-spacing:-.01em; }
          .meta { text-align:right; color:var(--dim); font-size:13px; }
          .meta b { display:block; color:var(--text); font-size:15px; font-weight:600; }
          .verdict { margin:24px 0 8px; padding:18px 22px; border-radius:14px; background:var(--card); border:1px solid var(--line); border-left:5px solid var(--tone); }
          .verdict b { display:block; font-size:22px; font-weight:600; color:var(--tone); }
          .verdict span { color:var(--dim); }
          .good { --tone:var(--good); } .warn { --tone:var(--warn); } .bad { --tone:var(--bad); } .open { --tone:var(--dim); }
          h2 { margin:30px 0 10px; font-size:12px; font-weight:600; letter-spacing:.14em; text-transform:uppercase; color:var(--dim); }
          .check { display:flex; gap:16px; align-items:flex-start; justify-content:space-between; padding:14px 18px; margin-bottom:8px; border-radius:12px; background:var(--card); border:1px solid var(--line); break-inside:avoid; }
          .check b { display:block; font-weight:600; }
          .check p { margin:2px 0 0; color:var(--dim); font-size:14px; }
          .pill { flex:none; padding:3px 12px; border-radius:99px; font-size:12px; font-weight:600; color:var(--tone); border:1px solid var(--tone); white-space:nowrap; }
          table { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
          th, td { padding:9px 18px; text-align:left; vertical-align:top; border-top:1px solid var(--line); }
          tr:first-child th, tr:first-child td { border-top:0; }
          th { width:30%; font-weight:400; color:var(--dim); white-space:nowrap; }
          footer { margin-top:26px; color:var(--dim); font-size:12.5px; }
          @media (max-width:560px) { th { white-space:normal; } .meta { text-align:left; } }
          @media print {
            :root { --bg:#fff; --card:#fff; --line:#cfd6e4; --text:#111827; --dim:#4b5563; --good:#047857; --warn:#b45309; --bad:#b91c1c; --a1:#111827; --a2:#111827; }
            body { padding:0; font-size:12pt; }
          }
        </style>
        </head>
        <body>
        <main>
        <header>
          <div><div class="brand">PulsRig</div><h1>Prüfbericht</h1></div>
          <div class="meta"><b>{{NAME}}</b>{{TIME}} Uhr</div>
        </header>
        <div class="verdict {{TONE}}"><b>{{VERDICT}}</b><span>{{REST}}</span></div>
        <h2>Prüfungen</h2>
        {{CHECKS}}
        <h2>Gerät</h2>
        <table>
        {{DEVICE}}
        </table>
        <footer>Der Bericht gibt wieder, was Windows und die Tests von PulsRig zum genannten Zeitpunkt gemeldet haben. Er ist kein Gutachten und keine Garantie: Fehler, die nur selten oder erst nach Stunden auftreten, kann eine kurze Prüfung übersehen.</footer>
        </main>
        </body>
        </html>
        """;
}
