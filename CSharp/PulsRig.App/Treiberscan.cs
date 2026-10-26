using System.IO;
using System.Management;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Ergebnis des Scans wie die Rückgabe von PulsRig-Arbeit-Scan.ps1. Geladen und installiert wird hier nichts:
// Laden und Installieren steht in Treiberinstallation.cs.
sealed record Treiber(string Name, string Class, string Version, string Date, string Provider, string HardwareId, int Count, bool ThirdParty, string Catalog, DateTime? When);
sealed record Problemgeraet(string Name, int Code, string Text, string Advice, string Id, bool Chipset, string Catalog = "", string CatalogQuery = "");
sealed record UpdateAngebot(string Id, string Name, string Device, string Class, string Installed, string NewDate, string Size, bool Optional, bool Firmware, string Key = "", string Title = "");
sealed record HerstellerAngebot(string Source, string Device, string Kind, string Installed, string Latest, string Released, string Size, string Url, bool IsNewer);
sealed record KatalogHinweis(string Title, string Date, string Size, string Device, string Installed, string Url, bool NoCode, string Query = "", string Version = "", string HardwareIds = "");
sealed record ScanErgebnis(DateTime When, int Devices, int ThirdParty, List<Treiber> Drivers, List<Problemgeraet> Problems, BoardSearch? Board,
    List<UpdateAngebot> Updates, HerstellerAngebot? Nvidia, HerstellerAngebot? Amd, HerstellerAngebot? Radeon, List<KatalogHinweis> Hints,
    List<string> Failed, List<string> Sources, bool Intel, bool RadeonHint, string SearchError)
{
    // neuere Treiber insgesamt: Windows Update und die Hersteller, die PulsRig selbst fragt
    public int Newer => Updates.Count + new[] { Nvidia, Amd, Radeon }.Count(x => x is { IsNewer: true });
}

// Scan im Hintergrund; Changed kommt auf dem Oberflächen-Thread bei jedem Schritt und am Ende.
// Das letzte Ergebnis bleibt im Datenordner, damit Startseite und Treiber-Seite es nach dem Neustart kennen.
static class Treiberscan
{
    public static ScanErgebnis? Last { get; private set; } = Load();
    public static bool Running { get; private set; }
    public static double Percent { get; private set; }
    public static string Stage { get; private set; } = "";
    public static List<string> Names { get; private set; } = new();
    public static event Action? Changed;

    static string File => Path.Combine(Belastung.Folder, "Letzter-Scan.json");
    static readonly HttpClient Web = new() { Timeout = TimeSpan.FromSeconds(30) };

    static Treiberscan() => Web.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) PulsRig");

    static ScanErgebnis? Load()
    {
        try { return System.IO.File.Exists(File) ? JsonSerializer.Deserialize<ScanErgebnis>(System.IO.File.ReadAllText(File)) : null; }
        catch (Exception) { return null; }
    }

    public static void Start()
    {
        if (Running) return;
        Running = true;
        Percent = 0;
        Stage = "Lese Geräte und installierte Treiber …";
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        void Report(double percent, string text, List<string>? names = null) =>
            ui.BeginInvoke(() => { Percent = percent; Stage = text; if (names != null) Names = names; Changed?.Invoke(); });
        // Windows Update spricht COM und will einen eigenen STA-Thread
        var thread = new Thread(() =>
        {
            ScanErgebnis? result = null;
            try { result = Run(Report); } catch (Exception) { }
            ui.BeginInvoke(() =>
            {
                Running = false;
                Percent = 100;
                if (result != null)
                {
                    Last = result;
                    try { Directory.CreateDirectory(Belastung.Folder); System.IO.File.WriteAllText(File, JsonSerializer.Serialize(result)); } catch (Exception) { }
                }
                Changed?.Invoke();
                Hw.Touch();
            });
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    // der Wochenscan des Helfers ohne Fenster, wie PulsRig-Hintergrund.ps1: zählt die neueren Treiber ohne Firmware
    // (außer unter Optionen gewählt) und ohne Ausgeschlossene; die Liste landet in PulsRig-Hintergrund-Scan.json.
    // Das Ergebnis ist die Zahl, -1 wenn die Suche fehlschlug.
    public static int Weekly(Action<string> log)
    {
        ScanErgebnis? result = null;
        Exception? problem = null;
        var thread = new Thread(() => { try { result = Run((_, _, _) => { }); } catch (Exception e) { problem = e; } });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (result == null) { log("Suche fehlgeschlagen: " + problem?.Message); return -1; }
        Last = result;
        try { Directory.CreateDirectory(Belastung.Folder); System.IO.File.WriteAllText(File, JsonSerializer.Serialize(result)); } catch (Exception) { }
        if (result.SearchError.Length > 0) log("Windows Update: " + result.SearchError);
        foreach (var f in result.Failed) log(f + ": nicht erreichbar");

        var settings = Altdaten.Settings();
        var ignored = TreiberEinstellungen.Current;
        var nvidia = Altdaten.Flag(settings, "Nvidia", true);
        var names = new List<string>();
        foreach (var u in result.Updates)
        {
            if (u.Firmware && !Altdaten.Flag(settings, "Firmware", false)) continue;
            if (ignored.IsIgnored("wu:" + u.Key + "|" + u.Title)) continue;
            // was NVIDIA selbst liefert, zählt unten
            if (nvidia && u.Class == "Display" && (u.Title + " " + u.Name).Contains("NVIDIA", StringComparison.OrdinalIgnoreCase)) continue;
            names.Add(u.Title.Length > 0 ? u.Title : u.Name);
        }
        if (nvidia)
            foreach (var (v, key, label) in new[] { (result.Nvidia, "nvidia:", "NVIDIA "), (result.Amd, "amd:", "AMD-Chipsatz "), (result.Radeon, "radeon:", "AMD Adrenalin ") })
                if (v is { IsNewer: true } && !ignored.IsIgnored(key + v.Latest)) names.Add(label + v.Latest);
        var json = new System.Text.Json.Nodes.JsonObject { ["Time"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm"), ["Count"] = names.Count, ["Names"] = Altdaten.Array(names) };
        Directory.CreateDirectory(Altdaten.Folder);
        System.IO.File.WriteAllText(Path.Combine(Altdaten.Folder, "PulsRig-Hintergrund-Scan.json"), json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new System.Text.UTF8Encoding(true));
        log("Neuere Treiber: " + names.Count + (names.Count > 0 ? " (" + string.Join(", ", names) + ")" : ""));
        return names.Count;
    }

    static IEnumerable<ManagementObject> Query(string wql)
    {
        using var searcher = new ManagementObjectSearcher(@"root\cimv2", wql);
        foreach (ManagementObject o in searcher.Get()) yield return o;
    }

    static string T(ManagementBaseObject o, string name) => (o[name]?.ToString() ?? "").Trim();

    sealed record Installiert(string DeviceName, string DeviceClass, string DriverVersion, string Provider, string HardwareId, string DeviceId, DateTime? Date);

    static ScanErgebnis Run(Action<double, string, List<string>?> report)
    {
        var installed = InstalledDrivers();
        report(16, "Frage Windows Update nach neueren Treibern …", installed.Select(d => d.DeviceName).Distinct().ToList());

        var problems = new List<Problemgeraet>();
        try
        {
            foreach (var p in Query("SELECT Name, ConfigManagerErrorCode, DeviceID, HardwareID FROM Win32_PnPEntity WHERE ConfigManagerErrorCode <> 0"))
            {
                var code = Convert.ToInt32(p["ConfigManagerErrorCode"]);
                var issue = Core.Geraetefehler.Get(code);
                var id = (p["HardwareID"] as string[])?.FirstOrDefault() ?? "";
                problems.Add(new(T(p, "Name"), code, issue.Text, issue.Advice, id, ScanGeraete.IsChipsetDevice(T(p, "Name"), code, T(p, "DeviceID"))));
            }
        }
        catch (Exception) { }
        // fehlt der Chipsatz-Treiber, nennt das Ergebnis das Mainboard und eine Suche nach dessen Treiber
        BoardSearch? board = null;
        if (problems.Any(p => p.Chipset))
        {
            try
            {
                var system = Query("SELECT Manufacturer, Model FROM Win32_ComputerSystem").First();
                var b = Query("SELECT Manufacturer, Product FROM Win32_BaseBoard").First();
                board = ScanGeraete.BoardDriverSearch(T(system, "Manufacturer"), T(system, "Model"), T(b, "Manufacturer"), T(b, "Product"));
            }
            catch (Exception) { }
        }

        var searchError = "";
        var updates = new List<(dynamic Update, string Id, bool Optional)>();
        try { updates = FindDriverUpdates(); }
        catch (COMException e) { searchError = ScanText.UpdateError(e.HResult, e.Message); }
        catch (Exception e) { searchError = e.Message; }

        report(58, "Frage NVIDIA und AMD nach den neuesten Treibern …", null);
        var failed = new List<string>();
        var gpus = new List<(string Name, string Version, string Pnp)>();
        string cpuMaker = "", cpuName = "", socket = "", boardMaker = "", boardProduct = "";
        try
        {
            gpus = Query("SELECT Name, DriverVersion, PNPDeviceID FROM Win32_VideoController").Select(v => (T(v, "Name"), T(v, "DriverVersion"), T(v, "PNPDeviceID"))).ToList();
            var cpu = Query("SELECT Manufacturer, Name, SocketDesignation FROM Win32_Processor").First();
            (cpuMaker, cpuName, socket) = (T(cpu, "Manufacturer"), Regex.Replace(T(cpu, "Name"), @"\s+", " "), T(cpu, "SocketDesignation"));
            var b = Query("SELECT Manufacturer, Product FROM Win32_BaseBoard").First();
            (boardMaker, boardProduct) = (T(b, "Manufacturer"), T(b, "Product"));
        }
        catch (Exception) { }

        HerstellerAngebot? nvidia = null, amd = null, radeon = null;
        try { nvidia = NvidiaUpdate(gpus); } catch (Exception) { failed.Add("NVIDIA"); }
        // den Grafiktreiber liefert NVIDIA selbst immer mindestens so aktuell wie Windows Update
        if (nvidia != null)
            updates = updates.Where(u => !(((string)u.Update.DriverClass) is "Display" or "Video" && Regex.IsMatch((string)u.Update.Title + " " + (string)u.Update.DriverProvider, "NVIDIA", RegexOptions.IgnoreCase))).ToList();
        try { amd = AmdChipsetUpdate(cpuMaker + " " + cpuName, cpuName, socket, boardProduct); } catch (Exception) { failed.Add("AMD"); }
        try { radeon = RadeonUpdate(gpus); } catch (Exception) { if (!failed.Contains("AMD")) failed.Add("AMD"); }

        var offers = new List<UpdateAngebot>();
        List<(string Id, string Name)>? allDevices = null;
        foreach (var (u, id, optional) in updates)
        {
            string key = u.DriverHardwareID ?? "";
            var current = installed.FirstOrDefault(d => d.HardwareId.Equals(key, StringComparison.OrdinalIgnoreCase));
            // ist kein Treiber dazu installiert, sagt wenigstens der Name des Geräts, worum es geht
            var deviceName = "";
            if (current == null)
            {
                try
                {
                    allDevices ??= Query("SELECT Name, HardwareID FROM Win32_PnPEntity").SelectMany(p => ((p["HardwareID"] as string[]) ?? Array.Empty<string>()).Select(h => (h, T(p, "Name")))).ToList();
                    deviceName = allDevices.FirstOrDefault(x => x.Id.Equals(key, StringComparison.OrdinalIgnoreCase)).Name ?? "";
                }
                catch (Exception) { }
            }
            string title = u.Title ?? "";
            string cls = u.DriverClass ?? "";
            DateTime? newDate = null;
            try { newDate = (DateTime)u.DriverVerDate; } catch (Exception) { }
            decimal size = 0;
            try { size = Convert.ToDecimal(u.MaxDownloadSize); } catch (Exception) { }
            offers.Add(new(id, ScanText.FormatUpdateTitle(title), deviceName, cls,
                current != null ? ScanText.FormatDriverText(current.DriverVersion, current.Date) : "", ScanText.FormatDate(newDate),
                size > 0 ? ((double)size / 1048576).ToString("N1", Ui.De) + " MB" : "", optional,
                cls == "Firmware" || Regex.IsMatch(title, "Firmware|BIOS|UEFI", RegexOptions.IgnoreCase), key, title));
        }

        report(66, "Durchsuche den Microsoft-Katalog …", null);
        var hints = new List<KatalogHinweis>();
        try { hints = CatalogHints(installed); } catch (Exception) { failed.Add("Katalog"); }

        // Geräte ohne Treiber: steht im Katalog einer? Beim ersten Fehlschlag hört die Nachfrage auf, höchstens acht Geräte
        var osName = Environment.OSVersion.Version.Build >= 22000 ? "Windows 11" : "Windows 10";
        var osVersion = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "DisplayVersion", "") as string ?? "";
        var asked = 0;
        for (var i = 0; i < problems.Count; i++)
        {
            var p = problems[i];
            if (p.Code != 28 || p.Id.Length == 0) continue;
            if (asked++ >= 8) break;
            try
            {
                var query = Katalog.Query(p.Id);
                if (query == null) continue;
                var row = KatalogAuswahl.MissingDriver(SearchCatalog(query), osName, osVersion);
                if (row != null) problems[i] = p with { Catalog = row.Version?.ToString() ?? "", CatalogQuery = query };
            }
            catch (Exception) { break; }
        }

        report(93, "Fasse zusammen …", null);
        var gpuNames = gpus.Select(g => g.Name).ToList();
        var sources = new List<string> { "Windows Update" };
        if (gpuNames.Any(n => n.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase))) sources.Add("NVIDIA");
        if (cpuMaker.Contains("AMD", StringComparison.OrdinalIgnoreCase)) sources.Add("AMD");
        sources.Add("Katalog");
        var intel = cpuMaker.Contains("Intel", StringComparison.OrdinalIgnoreCase) || gpuNames.Any(n => n.Contains("Intel", StringComparison.OrdinalIgnoreCase));
        var radeonGpu = gpuNames.Any(n => Regex.IsMatch(n, "Radeon|^AMD "));

        // alle Treiber für die Liste "Aktuell"; gleiche Einträge (z. B. mehrere PCI-Brücken) zusammengefasst
        var drivers = installed.GroupBy(d => (d.DeviceClass, d.DeviceName, d.DriverVersion)).Select(g =>
        {
            var d = g.First();
            var query = Katalog.Query(d.HardwareId);
            var third = d.Provider.Length > 0 && !d.Provider.StartsWith("Microsoft", StringComparison.OrdinalIgnoreCase);
            return new Treiber(d.DeviceName, d.DeviceClass, d.DriverVersion, ScanText.FormatDate(d.Date), d.Provider, d.HardwareId, g.Count(), third, query != null ? Katalog.Url(query) : "", d.Date);
        }).ToList();

        return new(DateTime.Now, installed.Count, installed.Count(d => d.Provider.Length > 0 && !d.Provider.StartsWith("Microsoft", StringComparison.OrdinalIgnoreCase)),
            drivers, problems, board, offers, nvidia, amd, radeon, hints, failed, sources, intel, radeonGpu && radeon == null, searchError);
    }

    // wie Get-InstalledDrivers mit Get-DriverDate: das Datum aus der Registrierung ist genauer als das der WMI-Klasse
    static List<Installiert> InstalledDrivers()
    {
        var list = new List<Installiert>();
        foreach (var d in Query("SELECT DeviceName, DeviceClass, DriverVersion, DriverProviderName, HardWareID, DeviceID, DriverDate FROM Win32_PnPSignedDriver"))
        {
            var name = T(d, "DeviceName");
            var version = T(d, "DriverVersion");
            if (name.Length == 0 || version.Length == 0) continue;
            DateTime? date = null;
            try
            {
                var driverKey = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\" + T(d, "DeviceID"), "Driver", null) as string;
                if (driverKey != null)
                {
                    var classKey = @"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\" + driverKey;
                    if (Registry.GetValue(classKey, "DriverDateData", null) is byte[] { Length: >= 8 } data) date = DateTime.FromFileTimeUtc(BitConverter.ToInt64(data, 0));
                    else if (Registry.GetValue(classKey, "DriverDate", null) is string text) date = DateTime.ParseExact(text, "M-d-yyyy", System.Globalization.CultureInfo.InvariantCulture);
                }
            }
            catch (Exception) { }
            if (date == null && T(d, "DriverDate").Length > 0) try { date = ManagementDateTimeConverter.ToDateTime(T(d, "DriverDate")); } catch (Exception) { }
            list.Add(new(name, T(d, "DeviceClass"), version, T(d, "DriverProviderName"), T(d, "HardWareID"), T(d, "DeviceID"), date));
        }
        return list.OrderBy(d => d.DeviceClass).ThenBy(d => d.DeviceName).ToList();
    }

    // wie Find-DriverUpdates: zuerst direkt bei Microsoft (umgeht z. B. einen Firmen-WSUS), dann die Standardquelle;
    // die "optionalen Updates" aus den Windows-Einstellungen liefert nur eine eigene Abfrage
    static List<(dynamic, string, bool)> FindDriverUpdates()
    {
        var type = Type.GetTypeFromProgID("Microsoft.Update.Session") ?? throw new InvalidOperationException("Windows Update ist auf diesem PC nicht verfügbar.");
        dynamic session = Activator.CreateInstance(type)!;
        session.ClientApplicationID = "PulsRig";
        // neu angebotene Treiber geschützter Grafikkarten zuerst verstecken
        try { Treiberinstallation.ApplyShield(session); } catch (Exception) { }
        const string Base = "IsInstalled=0 and IsHidden=0 and Type='Driver'";
        var seen = new HashSet<string>();
        var list = new List<(dynamic, string, bool)>();
        foreach (var (criteria, optional) in new[] { (Base, false), (Base + " and DeploymentAction='OptionalInstallation'", true) })
        {
            dynamic result;
            try { result = Search(session, criteria); }
            catch (Exception) when (optional) { continue; }   // ältere Windows-Versionen kennen das Kriterium nicht
            for (var i = 0; i < (int)result.Updates.Count; i++)
            {
                var update = result.Updates.Item(i);
                string id = update.Identity.UpdateID;
                if (seen.Add(id)) list.Add((update, id, optional));
            }
        }
        return list;
    }

    static dynamic Search(dynamic session, string criteria)
    {
        Exception? first = null;
        foreach (var selection in new[] { 2, 0 })
        {
            try
            {
                var searcher = session.CreateUpdateSearcher();
                searcher.ServerSelection = selection;
                return searcher.Search(criteria);
            }
            catch (Exception e) { first ??= e; }
        }
        throw first!;
    }

    static string Get(string url, bool english = false)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (english) request.Headers.AcceptLanguage.ParseAdd("en-US");
        using var response = Web.Send(request);
        response.EnsureSuccessStatusCode();
        return response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
    }

    // wie Get-NvidiaUpdate: Modell in NVIDIAs Produktliste suchen, dann den neuesten Game-Ready-Treiber (WHQL, DCH)
    static HerstellerAngebot? NvidiaUpdate(List<(string Name, string Version, string Pnp)> gpus)
    {
        var gpu = gpus.FirstOrDefault(g => g.Name.Contains("NVIDIA", StringComparison.OrdinalIgnoreCase));
        if (gpu.Name == null) return null;
        // NVIDIA führt neuere Karten mit "NVIDIA" davor, ältere ohne: auf beiden Seiten ohne vergleichen
        static string Plain(string name) => Regex.Replace(Regex.Replace(name, @"^\s*NVIDIA\s+", "", RegexOptions.IgnoreCase), @"\s+", " ").Trim();
        static string Field(XElement e, string name) => e.Attribute(name)?.Value ?? e.Element(name)?.Value ?? "";
        var product = Plain(gpu.Name);
        var installed = Hersteller.NvidiaVersion(gpu.Version);
        const string Lookup = "https://www.nvidia.com/Download/API/lookupValueSearch.aspx";
        var hits = XDocument.Parse(Get(Lookup + "?TypeID=3")).Descendants("LookupValue").Where(v => Plain(Field(v, "Name")).Equals(product, StringComparison.OrdinalIgnoreCase)).ToList();
        if (hits.Count == 0) throw new InvalidOperationException("Das Modell steht nicht in der NVIDIA-Produktliste.");
        var hit = hits[0];
        if (hits.Count > 1)
        {
            // gleicher Name in Desktop- und Notebook-Serie: der Akku entscheidet
            var notebookSeries = XDocument.Parse(Get(Lookup + "?TypeID=2")).Descendants("LookupValue").Where(v => Field(v, "Name").Contains("Notebook")).Select(v => Field(v, "Value")).ToHashSet();
            var notebook = false;
            try { notebook = Query("SELECT Name FROM Win32_Battery").Any(); } catch (Exception) { }
            hit = hits.FirstOrDefault(h => notebookSeries.Contains(Field(h, "ParentID")) == notebook) ?? hit;
        }
        var os = Environment.OSVersion.Version.Build >= 22000 ? 135 : 57;
        var json = Get("https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup" +
            "&psid=" + Field(hit, "ParentID") + "&pfid=" + Field(hit, "Value") + "&osID=" + os +
            "&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=0&sort1=0&numberOfResults=1");
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (!root.TryGetProperty("Success", out var ok) || ok.ToString() != "1" || !root.TryGetProperty("IDS", out var ids) || ids.GetArrayLength() == 0)
            throw new InvalidOperationException("NVIDIA hat keinen passenden Treiber gemeldet.");
        var info = ids[0].GetProperty("downloadInfo");
        string S(string name) => info.TryGetProperty(name, out var v) ? v.ToString() : "";
        var latest = S("Version");
        var released = S("ReleaseDateTime");
        try { released = ScanText.FormatDate(DateTime.Parse(released, System.Globalization.CultureInfo.InvariantCulture)); } catch (Exception) { }
        var newer = false;
        try { newer = installed != null && Version.Parse(latest) > Version.Parse(installed); } catch (Exception) { }
        // "Game Ready" ist NVIDIAs auf neue Spiele abgestimmte Treiberlinie
        return new("NVIDIA", gpu.Name, Regex.IsMatch(S("Name"), "Game(%20| )Ready") ? "Game Ready" : "Treiber", installed ?? "", latest, released, S("DownloadURLFileSize"), S("DownloadURL"), newer);
    }

    // wie Get-AmdChipsetUpdate: neueste Fassung von AMDs Seite, installierte aus der Programmliste (höchste zählt)
    static HerstellerAngebot? AmdChipsetUpdate(string cpuText, string cpuName, string socket, string boardProduct)
    {
        if (!cpuText.Contains("AMD", StringComparison.OrdinalIgnoreCase)) return null;
        var found = Hersteller.AmdChipset(boardProduct, socket);
        if (found == null) return null;
        // gelesen wird die englische Seite (feste Beschriftungen), gezeigt wird dem Nutzer die deutsche
        var content = Get(found.Url.Replace("/de/support/", "/en/support/"));
        var latest = Hersteller.AmdChipsetLatest(content) ?? throw new InvalidOperationException("Die Seite von AMD nennt keine Version.");
        var details = Hersteller.AmdChipsetDetails(content, latest);
        Version? installed = null;
        var installedText = "";
        foreach (var root in new[] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" })
        {
            using var key = Registry.LocalMachine.OpenSubKey(root);
            if (key == null) continue;
            foreach (var name in key.GetSubKeyNames())
            {
                using var entry = key.OpenSubKey(name);
                if (!Regex.IsMatch(entry?.GetValue("DisplayName") as string ?? "", "^AMD[ _]Chipset[ _](Software|Drivers)$")) continue;
                var text = entry?.GetValue("DisplayVersion") as string ?? "";
                if (Version.TryParse(text, out var v) && (installed == null || v > installed)) { installed = v; installedText = text; }
            }
        }
        var newer = false;
        try { newer = installed == null || Version.Parse(latest) > installed; } catch (Exception) { }
        return new("AMD", found.Chipset + "-Chipsatz · " + cpuName, "Chipsatz", installedText, latest, details.Length > 1 ? details[1] : "", details.Length > 0 ? details[0] : "", found.Url, newer);
    }

    // wie Get-RadeonUpdate: die Adrenalin-Fassung steht im Schlüssel des Treibers
    static HerstellerAngebot? RadeonUpdate(List<(string Name, string Version, string Pnp)> gpus)
    {
        var gpu = gpus.FirstOrDefault(g => g.Name.Contains("Radeon", StringComparison.OrdinalIgnoreCase) && Hersteller.RadeonPage(g.Name) != null);
        if (gpu.Name == null) return null;
        var page = Hersteller.RadeonPage(gpu.Name)!;
        var content = Get(page.Replace("/de/support/", "/en/support/"));
        var latest = Hersteller.RadeonLatest(content) ?? throw new InvalidOperationException("Die Seite von AMD nennt keine Version.");
        var installed = "";
        try
        {
            var driverKey = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\" + gpu.Pnp, "Driver", null) as string;
            if (driverKey != null) installed = (Registry.GetValue(@"HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\" + driverKey, "RadeonSoftwareVersion", "") as string ?? "").Trim();
        }
        catch (Exception) { }
        var newer = false;
        try { newer = installed.Length > 0 && Version.Parse(latest) > Version.Parse(installed); } catch (Exception) { }
        return new("Radeon", Hersteller.GpuName(gpu.Name), "Adrenalin", installed, latest, Hersteller.ReleaseDate(content), "", page, newer);
    }

    public static KatalogTreffer[] SearchCatalog(string query)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Katalog.Url(query));
        request.Headers.AcceptLanguage.ParseAdd("en-US");
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        using var response = Web.Send(request, cts.Token);
        response.EnsureSuccessStatusCode();
        return Katalog.ParseRows(response.Content.ReadAsStringAsync().GetAwaiter().GetResult());
    }

    sealed class CacheRow { public string Title { get; set; } = ""; public string Products { get; set; } = ""; public string Size { get; set; } = ""; public long Bytes { get; set; } public string Date { get; set; } = ""; public string Version { get; set; } = ""; }
    sealed class CacheEntry { public string Time { get; set; } = ""; public List<CacheRow> Rows { get; set; } = new(); }

    // wie Find-CatalogHints: je Treiberlinie eines Drittherstellers ein neuerer Eintrag im Katalog?
    // Antworten gelten einen Tag; die Datei teilt sich die App mit dem PowerShell-Programm.
    static List<KatalogHinweis> CatalogHints(List<Installiert> installed)
    {
        var osName = Environment.OSVersion.Version.Build >= 22000 ? "Windows 11" : "Windows 10";
        var services = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        try { foreach (var p in Query("SELECT DeviceID, Service FROM Win32_PnPEntity")) services[T(p, "DeviceID")] = T(p, "Service").Length > 0; } catch (Exception) { }
        var groups = installed.Where(d => d.HardwareId.Length > 0 && d.Provider.Length > 0 && !d.Provider.StartsWith("Microsoft", StringComparison.OrdinalIgnoreCase))
            .Select(d => (Query: Katalog.Query(d.HardwareId), Driver: d)).Where(x => x.Query != null).GroupBy(x => x.Query!).OrderBy(g => g.Key).ToList();

        var cachePath = Path.Combine(Path.GetTempPath(), "PulsRig-Katalog.json");
        var cache = new Dictionary<string, CacheEntry>();
        try
        {
            if (System.IO.File.Exists(cachePath))
                foreach (var (key, entry) in JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(System.IO.File.ReadAllText(cachePath)) ?? new())
                {
                    var stamp = DateTime.ParseExact(entry.Time, "yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture);
                    if (stamp <= DateTime.Now && (DateTime.Now - stamp).TotalHours < 24) cache[key] = entry;
                }
        }
        catch (Exception) { cache.Clear(); }

        static KatalogTreffer[] Rows(CacheEntry e) => e.Rows.Select(r => new KatalogTreffer { Title = r.Title, Products = r.Products, Size = r.Size, Bytes = r.Bytes,
            Date = DateTime.ParseExact(r.Date, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), Version = Version.TryParse(r.Version, out var v) ? v : null }).ToArray();

        var found = new List<(Installiert Driver, KatalogTreffer Entry, string Url, bool HasService)>();
        int failures = 0, rowsSeen = 0;
        foreach (var group in groups)
        {
            KatalogTreffer[] rows;
            if (cache.TryGetValue(group.Key, out var cached)) rows = Rows(cached);
            else
            {
                try
                {
                    rows = SearchCatalog(group.Key);
                    failures = 0;
                    cache[group.Key] = new CacheEntry { Time = DateTime.Now.ToString("yyyy-MM-dd HH:mm"), Rows = rows.Select(r => new CacheRow { Title = r.Title, Products = r.Products, Size = r.Size, Bytes = r.Bytes, Date = r.Date.ToString("yyyy-MM-dd"), Version = r.Version?.ToString() ?? "" }).ToList() };
                }
                catch (Exception e)
                {
                    if (++failures >= 3) throw new InvalidOperationException("Der Katalog antwortet nicht (" + e.Message + ").");
                    continue;
                }
            }
            rowsSeen += rows.Length;
            foreach (var (_, driver) in group)
            {
                var entry = KatalogAuswahl.Candidate(driver.DriverVersion, driver.Provider, driver.Date, rows, osName);
                if (entry != null) found.Add((driver, entry, Katalog.Url(entry.Version + " " + group.Key), services.GetValueOrDefault(driver.DeviceId)));
            }
        }
        try { System.IO.File.WriteAllText(cachePath, JsonSerializer.Serialize(cache)); } catch (Exception) { }
        if (groups.Count > 0 && rowsSeen == 0) throw new InvalidOperationException("Der Katalog lieferte keine auswertbaren Treffer.");

        return found.GroupBy(x => x.Entry.Title + "|" + x.Entry.Version).Select(g =>
        {
            var first = g.First();
            // winzige Pakete ohne Dienst sind meist nur eine Beschreibung des Geräts, kein Treibercode
            var tiny = first.Entry.Bytes > 0 && first.Entry.Bytes < 200 * 1024 && !g.Any(x => x.HasService);
            return new KatalogHinweis(first.Entry.Title, ScanText.FormatDate(first.Entry.Date), first.Entry.Size, string.Join(", ", g.Select(x => x.Driver.DeviceName).Distinct()),
                ScanText.FormatDriverText(first.Driver.DriverVersion, first.Driver.Date), first.Url, tiny, Katalog.Query(first.Driver.HardwareId) ?? "", first.Entry.Version?.ToString() ?? "", string.Join("|", g.Select(x => x.Driver.HardwareId).Distinct()));
        }).ToList();
    }
}
