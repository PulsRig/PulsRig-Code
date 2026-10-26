using System.Diagnostics;
using System.IO;
using System.Management;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Einstellungen der neuen Oberfläche, Schlüssel wie in PulsRig-Einstellungen.json: Ignored ("wu:<Kennung>|<Titel>",
// "nvidia:<Version>" …) und GpuShield ("PCI\VEN_xxxx&DEV_xxxx").
sealed class Ausschluss { public string Key { get; set; } = ""; public string Name { get; set; } = ""; }
sealed class TreiberEinstellungen
{
    public List<Ausschluss> Ignored { get; set; } = new();
    public List<string> GpuShield { get; set; } = new();
    public bool RestorePoint { get; set; } = true;
    public bool AutoBackup { get; set; } = true;

    static string File => Path.Combine(Belastung.Folder, "Einstellungen.json");
    public static TreiberEinstellungen Current { get; } = Load();

    static TreiberEinstellungen Load()
    {
        try
        {
            var s = System.IO.File.Exists(File) ? JsonSerializer.Deserialize<TreiberEinstellungen>(System.IO.File.ReadAllText(File)) ?? new() : new();
            s.GpuShield = s.GpuShield.Where(k => Regex.IsMatch(k, @"^PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}$")).Distinct().ToList();
            s.Ignored = s.Ignored.Where(i => i.Key.Length > 0).ToList();
            return s;
        }
        catch (Exception) { return new(); }
    }

    public void Save()
    {
        try { Directory.CreateDirectory(Belastung.Folder); System.IO.File.WriteAllText(File, JsonSerializer.Serialize(this)); } catch (Exception) { }
    }

    public bool IsIgnored(string key) => Ignored.Any(i => i.Key == key);
    public void Ignore(string key, string name) { if (!IsIgnored(key)) { Ignored.Add(new() { Key = key, Name = name }); Save(); } }
    public void Unignore(string key) { Ignored.RemoveAll(i => i.Key == key); Save(); }
}

sealed record Laufzeit(string Name, string Status, string Version, string? Url, string? File);
sealed record Schutzkarte(string Key, string Name, string Version, bool On, int Hidden, int Offered);

// Laden, Prüfen und Installieren wie Treiber-Scan.ps1 und Treiber-Werkzeuge.ps1. Installiert wird nur nach einer
// Bestätigung auf der Treiber-Seite und nur mit Adminrechten; jede fremde Datei wird erst unter einer Sperre auf die
// Signatur des Herstellers geprüft und dann gestartet, so lässt sie sich dazwischen nicht austauschen.
static class Treiberinstallation
{
    public static bool Busy { get; private set; }
    public static string Stage { get; private set; } = "";
    public static string LastMessage { get; private set; } = "";
    public static bool RebootRequired { get; private set; }
    public static event Action? Changed;

    static readonly HttpClient Web = new() { Timeout = TimeSpan.FromMinutes(30) };
    static string Downloads => Path.Combine(Belastung.Folder, "Downloads");

    // Arbeit im Hintergrund auf einem STA-Thread (Windows Update spricht COM); Meldungen kommen auf dem Oberflächen-Thread
    static void Run(string stage, Func<Action<string>, string> work, bool rescan = false)
    {
        if (Busy) return;
        Busy = true;
        Stage = stage;
        LastMessage = "";
        Changed?.Invoke();
        var ui = System.Windows.Application.Current.Dispatcher;
        void Report(string text) => ui.BeginInvoke(() => { Stage = text; Changed?.Invoke(); });
        var thread = new Thread(() =>
        {
            string message;
            try { message = work(Report); }
            catch (COMException e) { message = ScanText.UpdateError(e.HResult, e.Message); }
            catch (Exception e) { message = e.Message; }
            ui.BeginInvoke(() =>
            {
                Busy = false;
                Stage = "";
                LastMessage = message;
                Changed?.Invoke();
                if (rescan) Treiberscan.Start();
            });
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    // --- Signatur --------------------------------------------------------------------------------------------------

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
    static extern int WinVerifyTrust(IntPtr hwnd, ref Guid action, ref WinTrustData data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WinTrustFileInfo { public int Size; public string Path; public IntPtr File; public IntPtr Known; }

    [StructLayout(LayoutKind.Sequential)]
    struct WinTrustData
    {
        public int Size; public IntPtr Policy; public IntPtr SipData; public int UiChoice; public int Revocation; public int UnionChoice;
        public IntPtr FileInfo; public int StateAction; public IntPtr StateData; public IntPtr Url; public int ProviderFlags; public int UiContext; public IntPtr Signature;
    }

    // wie Test-FileSigner: gültige Authenticode-Signatur (Windows prüft Kette und Sperrlisten) und passender Herausgeber
    public static bool HasSigner(string path, string signerPattern)
    {
        var info = new WinTrustFileInfo { Size = Marshal.SizeOf<WinTrustFileInfo>(), Path = path };
        var infoPtr = Marshal.AllocHGlobal(info.Size);
        try
        {
            Marshal.StructureToPtr(info, infoPtr, false);
            var data = new WinTrustData { Size = Marshal.SizeOf<WinTrustData>(), UiChoice = 2, Revocation = 0, UnionChoice = 1, FileInfo = infoPtr, StateAction = 0, ProviderFlags = 0x80 };
            var action = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");   // WINTRUST_ACTION_GENERIC_VERIFY_V2
            if (WinVerifyTrust(IntPtr.Zero, ref action, ref data) != 0) return false;
#pragma warning disable SYSLIB0057
            using var cert = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
#pragma warning restore SYSLIB0057
            return Regex.IsMatch(cert.Subject, signerPattern);
        }
        catch (Exception) { return false; }
        finally { Marshal.DestroyStructure<WinTrustFileInfo>(infoPtr); Marshal.FreeHGlobal(infoPtr); }
    }

    // lädt nur von erlaubten Adressen, immer frisch, und behält die Datei nur mit passender Signatur
    static string Download(string url, string fileName, string signer, string[] hosts, Action<string> report, string label)
    {
        if (!Core.Downloads.IsAllowed(url, hosts)) throw new InvalidOperationException("Unerwartete Adresse: " + url);
        Directory.CreateDirectory(Downloads);
        var file = Path.Combine(Downloads, Path.GetFileName(fileName));
        if (System.IO.File.Exists(file)) System.IO.File.Delete(file);
        using (var response = Web.Send(new HttpRequestMessage(HttpMethod.Get, url), HttpCompletionOption.ResponseHeadersRead))
        {
            response.EnsureSuccessStatusCode();
            // eine Weiterleitung (aka.ms) muss ebenfalls auf einem erlaubten Rechner enden
            var final = response.RequestMessage?.RequestUri?.AbsoluteUri ?? url;
            if (!Core.Downloads.IsAllowed(final, hosts)) throw new InvalidOperationException("Unerwartete Adresse: " + final);
            var total = response.Content.Headers.ContentLength ?? 0;
            using var source = response.Content.ReadAsStream();
            using var target = System.IO.File.Create(file);
            var buffer = new byte[1 << 16];
            long done = 0, shown = -1;
            int read;
            while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
            {
                target.Write(buffer, 0, read);
                done += read;
                var percent = total > 0 ? done * 100 / total : -1;
                if (percent != shown && percent >= 0) { shown = percent; report("Lade " + label + " … " + percent + " %"); }
            }
        }
        if (!HasSigner(file, signer))
        {
            System.IO.File.Delete(file);
            throw new InvalidOperationException("Die geladene Datei trägt keine gültige Signatur des Herstellers und wurde verworfen.");
        }
        return file;
    }

    // wie Start-SignedInstaller: Datei gesperrt, Signatur unter der Sperre geprüft, dann gestartet und abgewartet
    static int StartSigned(string path, string signer)
    {
        using var guard = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (!HasSigner(path, signer)) throw new InvalidOperationException("Die Datei " + Path.GetFileName(path) + " trägt keine gültige Signatur des Herstellers und wird nicht gestartet.");
        var start = path.EndsWith(".msi", StringComparison.OrdinalIgnoreCase)
            ? new ProcessStartInfo("msiexec.exe", "/i \"" + path + "\"") { UseShellExecute = true }
            : new ProcessStartInfo(path) { UseShellExecute = true };
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Der Installer ließ sich nicht starten.");
        process.WaitForExit();
        return process.ExitCode;
    }

    // --- Wiederherstellungspunkt -----------------------------------------------------------------------------------

    // wie New-DriverRestorePoint (Checkpoint-Computer): Art 10 = Treiberinstallation; Windows legt höchstens einen am Tag an
    static string RestorePoint()
    {
        if (!TreiberEinstellungen.Current.RestorePoint) return "";
        try
        {
            using var restore = new ManagementClass(@"\\.\root\default", "SystemRestore", null);
            var args = restore.GetMethodParameters("CreateRestorePoint");
            args["Description"] = "PulsRig (vor Treiberinstallation)";
            args["RestorePointType"] = 10;
            args["EventType"] = 100;
            var result = restore.InvokeMethod("CreateRestorePoint", args, null);
            var code = Convert.ToInt32(result?["ReturnValue"] ?? 0);
            return code == 0 ? "Wiederherstellungspunkt erstellt. " : "Kein neuer Wiederherstellungspunkt (Code " + code + "). ";
        }
        catch (Exception) { return "Kein Wiederherstellungspunkt – vermutlich ist der Computerschutz für C: aus. "; }
    }

    static dynamic NewSession()
    {
        var type = Type.GetTypeFromProgID("Microsoft.Update.Session") ?? throw new InvalidOperationException("Windows Update ist auf diesem PC nicht verfügbar.");
        dynamic session = Activator.CreateInstance(type)!;
        session.ClientApplicationID = "PulsRig";
        return session;
    }

    static dynamic NewCollection() => Activator.CreateInstance(Type.GetTypeFromProgID("Microsoft.Update.UpdateColl")!)!;

    // --- Windows Update ----------------------------------------------------------------------------------------------

    // wie Save-DriverUpdates und Install-DriverUpdates: die gewählten Angebote frisch suchen, laden, installieren
    public static void InstallUpdates(IReadOnlyList<UpdateAngebot> offers) => Run("Bereite die Installation vor …", report =>
    {
        Probezeitlauf.MarkInstall();
        var session = NewSession();
        var collection = NewCollection();
        var skipped = new List<string>();
        foreach (var offer in offers)
        {
            if (offer.Firmware) { skipped.Add(offer.Name + " (Firmware)"); continue; }
            dynamic result = session.CreateUpdateSearcher().Search("UpdateID='" + offer.Id + "'");
            if ((int)result.Updates.Count == 0) { skipped.Add(offer.Name + " (nicht mehr angeboten)"); continue; }
            var update = result.Updates.Item(0);
            if (!(bool)update.EulaAccepted) { skipped.Add(offer.Name + " (Lizenz in Windows Update bestätigen)"); continue; }
            collection.Add(update);
        }
        if ((int)collection.Count == 0) return "Nichts installiert. " + string.Join(", ", skipped);
        var message = RestorePoint() + BackupReplaced(offers.Select(o => o.Key));
        report("Lade " + (int)collection.Count + " Treiber von Windows Update …");
        var downloader = session.CreateUpdateDownloader();
        downloader.Updates = collection;
        downloader.Download();
        report("Installiere – der Bildschirm kann kurz flackern …");
        var installer = session.CreateUpdateInstaller();
        installer.Updates = collection;
        dynamic outcome = installer.Install();
        int ok = 0, failed = 0;
        for (var i = 0; i < (int)collection.Count; i++)
            if ((int)outcome.GetUpdateResult(i).ResultCode is 2 or 3) ok++; else failed++;
        if ((bool)outcome.RebootRequired) RebootRequired = true;
        message += ok + " installiert" + (failed > 0 ? ", " + failed + " fehlgeschlagen" : "") + "." + (skipped.Count > 0 ? " Übersprungen: " + string.Join(", ", skipped) + "." : "");
        return message + (RebootRequired ? " Bitte den PC neu starten." : "");
    }, rescan: true);

    // --- Sicherung der ersetzten Treiber ---------------------------------------------------------------------------

    // wie Backup-ReplacedDrivers: die bisherigen Pakete von Drittherstellern (oemNN.inf) vor dem Update exportieren,
    // jedes höchstens 300 MB groß; zurückholen über den Geräte-Manager mit diesem Ordner
    static string BackupReplaced(IEnumerable<string> hardwareIds)
    {
        if (!TreiberEinstellungen.Current.AutoBackup) return "";
        return BackupNow(hardwareIds);
    }

    static string BackupNow(IEnumerable<string> hardwareIds)
    {
        var infs = new List<string>();
        foreach (var id in hardwareIds.Where(i => i.Length > 0))
            try
            {
                using var searcher = new ManagementObjectSearcher("SELECT InfName FROM Win32_PnPSignedDriver WHERE HardWareID = '" + id.Replace("\\", "\\\\").Replace("'", "\\'") + "'");
                foreach (ManagementObject d in searcher.Get()) infs.Add(d["InfName"]?.ToString() ?? "");
            }
            catch (Exception) { }
        var packages = Sicherung.PackagesToBackup(infs);
        if (packages.Length == 0) return "";
        var originals = Sicherung.ParsePackages(RunTool("pnputil.exe", "/enum-drivers").Output.Split('\n').Select(l => l.TrimEnd('\r')))
            .GroupBy(p => p.Published.ToLowerInvariant()).ToDictionary(g => g.Key, g => g.First().Original);
        var target = Path.Combine(Belastung.Folder, "Sicherungen", Sicherung.AutoFolderName(DateTime.Now));
        var store = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\DriverStore\FileRepository");
        var saved = 0;
        foreach (var package in packages)
        {
            if (!originals.TryGetValue(package, out var original) || original.Length == 0) continue;
            // der Treiberspeicher kann mehrere Fassungen enthalten - die größte entscheidet, ob sich das Sichern lohnt
            long bytes = 0;
            try
            {
                foreach (var dir in Directory.GetDirectories(store, Sicherung.FolderName(original) + "_*"))
                    bytes = Math.Max(bytes, new DirectoryInfo(dir).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length));
            }
            catch (Exception) { }
            if (bytes > 300L * 1024 * 1024) continue;
            var folder = Path.Combine(target, Sicherung.FolderName(original));
            Directory.CreateDirectory(folder);
            if (RunTool("pnputil.exe", "/export-driver " + package + " \"" + folder + "\"").Code == 0) saved++;
        }
        return saved > 0 ? "Bisherige Treiber gesichert (" + saved + " Paket(e)). " : "";
    }

    internal static (int Code, string Output) RunTool(string file, string arguments)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, file), arguments) { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return (process.ExitCode, output);
    }

    // --- Microsoft-Katalog -------------------------------------------------------------------------------------------

    // wie Get-CatalogDownload: Adresse und Prüfsumme der Datei aus dem Download-Dialog des Katalogs
    static (string Url, string Sha256) CatalogDownload(string updateId)
    {
        if (!Regex.IsMatch(updateId, "^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$")) throw new InvalidOperationException("Unerwartete Kennung im Katalog.");
        var body = new FormUrlEncodedContent(new Dictionary<string, string> { ["updateIDs"] = "[{\"size\":0,\"languages\":\"\",\"uidInfo\":\"" + updateId + "\",\"updateID\":\"" + updateId + "\"}]" });
        using var response = Web.PostAsync("https://www.catalog.update.microsoft.com/DownloadDialog.aspx", body).GetAwaiter().GetResult();
        response.EnsureSuccessStatusCode();
        var content = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        var url = Regex.Match(content, @"downloadInformation\[0\]\.files\[0\]\.url = '([^']+)'").Groups[1].Value;
        var sha = Regex.Match(content, @"downloadInformation\[0\]\.files\[0\]\.sha256 = '([^']+)'").Groups[1].Value;
        if (url.Length == 0) throw new InvalidOperationException("Der Katalog nennt zu diesem Treiber keine Datei.");
        return (url, sha);
    }

    // wie Install-CatalogDriver: den passenden Eintrag frisch suchen (die Kennung steht nicht im Zwischenspeicher),
    // laden, Adresse, Prüfsumme, Signatur und Gerät prüfen und mit pnputil installieren. Gearbeitet wird in einem Ordner
    // unter ProgramData, auf den nur Administratoren und das System Zugriff haben; er muss nach dem Sperren leer sein.
    public static void InstallCatalog(string query, string title, string version, string hardwareIds) => Run("Suche das Paket im Microsoft-Katalog …", report =>
    {
        Probezeitlauf.MarkInstall();
        var rows = version.Length > 0 ? Treiberscan.SearchCatalog(version + " " + query) : Array.Empty<KatalogTreffer>();
        if (rows.Length == 0) rows = Treiberscan.SearchCatalog(query);
        var row = rows.FirstOrDefault(r => r.Title == title && (version.Length == 0 || r.Version?.ToString() == version))
            ?? rows.FirstOrDefault(r => version.Length > 0 && r.Version?.ToString() == version)
            ?? throw new InvalidOperationException("Der Katalog führt dieses Paket nicht mehr.");
        var (url, sha) = CatalogDownload(row.Id);
        var uri = new Uri(url);
        if (!Core.Downloads.IsAllowed(url, new[] { "*.windowsupdate.com", "*.delivery.mp.microsoft.com", "download.microsoft.com" }) || !uri.AbsolutePath.EndsWith(".cab", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Unerwartete Adresse: " + url);
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PulsRig", "Katalog-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            RunTool("icacls.exe", "\"" + folder + "\" /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F");
            if (Directory.EnumerateFileSystemEntries(folder).Any()) throw new InvalidOperationException("Im Arbeitsordner liegt etwas, das nicht von PulsRig stammt – abgebrochen.");
            var cab = Path.Combine(folder, "Treiber.cab");
            report("Lade " + row.Title + " …");
            using (var response = Web.Send(new HttpRequestMessage(HttpMethod.Get, uri), HttpCompletionOption.ResponseHeadersRead))
            {
                response.EnsureSuccessStatusCode();
                using var target = System.IO.File.Create(cab);
                response.Content.ReadAsStream().CopyTo(target);
            }
            string hash;
            using (var stream = System.IO.File.OpenRead(cab)) hash = Convert.ToBase64String(System.Security.Cryptography.SHA256.HashData(stream));
            if (sha.Length == 0 || hash != sha) throw new InvalidOperationException("Die geladene Datei ist nicht die, die der Katalog nennt (Prüfsumme weicht ab).");
            if (!HasSigner(cab, "O=Microsoft Corporation")) throw new InvalidOperationException("Die geladene Datei trägt keine gültige Signatur von Microsoft und wurde verworfen.");
            var files = Path.Combine(folder, "Dateien");
            Directory.CreateDirectory(files);
            var expand = RunTool("expand.exe", "\"" + cab + "\" -F:* \"" + files + "\"");
            if (expand.Code != 0) throw new InvalidOperationException("Das Paket ließ sich nicht entpacken (Code " + expand.Code + ").");
            var infs = Directory.GetFiles(files, "*.inf", SearchOption.AllDirectories);
            if (!infs.Any(f => System.IO.File.ReadAllText(f).Contains(query, StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("Das Paket nennt dieses Gerät nicht und wurde verworfen.");
            var message = RestorePoint() + BackupReplaced(hardwareIds.Split('|'));
            report("Installiere " + row.Title + " …");
            // 3010 = Neustart nötig, 259 = hinzugefügt, aber kein Gerät hat ihn übernommen
            var code = RunTool("pnputil.exe", "/add-driver \"" + Path.Combine(files, "*.inf") + "\" /subdirs /install").Code;
            if (code == 3010) RebootRequired = true;
            return message + (code switch
            {
                0 => "Installiert: " + row.Title + ".",
                3010 => "Installiert: " + row.Title + ". Bitte den PC neu starten.",
                259 => "Das Paket ist hinzugefügt, aber kein Gerät hat es übernommen.",
                _ => "pnputil meldet Code " + code + ".",
            });
        }
        finally { try { Directory.Delete(folder, true); } catch (Exception) { } }
    }, rescan: true);

    // --- NVIDIA ------------------------------------------------------------------------------------------------------

    public static void InstallNvidia(HerstellerAngebot offer) => Run("Lade NVIDIA-Treiber " + offer.Latest + " …", report =>
    {
        Probezeitlauf.MarkInstall();
        var name = Path.GetFileName(new Uri(offer.Url).LocalPath);
        var file = Download(offer.Url, name, "O=NVIDIA Corporation", new[] { "*.nvidia.com" }, report, "NVIDIA " + offer.Latest);
        var message = RestorePoint();
        report("NVIDIA-Installer läuft – bitte dem Assistenten folgen …");
        var code = StartSigned(file, "O=NVIDIA Corporation");
        return message + (code == 0 ? "NVIDIA-Installer beendet." : "NVIDIA-Installer beendet (Code " + code + ").");
    }, rescan: true);

    // --- Schutz der Grafikkarte -------------------------------------------------------------------------------------

    // wie Get-ShieldGpus und Find-GpuDriverOffers: je Grafikkarte, wie viele Angebote versteckt und wie viele offen sind
    public static List<Schutzkarte> ShieldStatus()
    {
        var cards = new List<Schutzkarte>();
        var seen = new HashSet<string>();
        using (var searcher = new ManagementObjectSearcher("SELECT Name, DriverVersion, PNPDeviceID FROM Win32_VideoController"))
            foreach (ManagementObject v in searcher.Get())
            {
                var key = ScanGeraete.GpuShieldKey(v["PNPDeviceID"]?.ToString());
                if (key.Length == 0 || !seen.Add(key)) continue;
                cards.Add(new(key, v["Name"]?.ToString() ?? "", v["DriverVersion"]?.ToString() ?? "", TreiberEinstellungen.Current.GpuShield.Contains(key), 0, 0));
            }
        return cards;
    }

    static List<dynamic> GpuOffers(dynamic session, IEnumerable<string> keys, bool hidden)
    {
        var list = new List<dynamic>();
        var wanted = keys.ToHashSet();
        if (wanted.Count == 0) return list;
        dynamic result = session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=" + (hidden ? 1 : 0) + " and Type='Driver'");
        for (var i = 0; i < (int)result.Updates.Count; i++)
        {
            var u = result.Updates.Item(i);
            if ((string)u.DriverClass is not ("Display" or "Video")) continue;
            if (wanted.Contains(ScanGeraete.GpuShieldKey((string)u.DriverHardwareID))) list.Add(u);
        }
        return list;
    }

    // vor jedem Scan: neu angebotene Treiber geschützter Karten verstecken (wie der Scan im PowerShell-Programm)
    public static void ApplyShield(dynamic session)
    {
        foreach (var u in GpuOffers(session, TreiberEinstellungen.Current.GpuShield, false)) u.IsHidden = true;
    }

    // Schalter je Karte: Schützen versteckt die Angebote für genau diese Karte, Freigeben zeigt sie wieder
    public static void SetShield(string key, bool on) => Run(on ? "Schütze den Grafiktreiber …" : "Gebe den Grafiktreiber frei …", _ =>
    {
        var settings = TreiberEinstellungen.Current;
        settings.GpuShield.Remove(key);
        if (on) settings.GpuShield.Add(key);
        settings.Save();
        var changed = 0;
        foreach (var u in GpuOffers(NewSession(), new[] { key }, !on)) { u.IsHidden = on; changed++; }
        return (on ? "Geschützt" : "Freigegeben") + (changed > 0 ? ": " + changed + " Angebot(e) von Windows Update " + (on ? "versteckt." : "wieder sichtbar.") : ".");
    }, rescan: true);

    // --- Laufzeitbibliotheken ----------------------------------------------------------------------------------------

    static readonly (string Name, string Pattern, string? Latest, string X64, string X86)[] VcRuntimes =
    {
        ("Visual C++ 2005", @"Visual C\+\+ 2005 Redistributable", null,
            "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.EXE",
            "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE"),
        ("Visual C++ 2008", @"Visual C\+\+ 2008 Redistributable", null,
            "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe",
            "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe"),
        ("Visual C++ 2010", @"Visual C\+\+ 2010\s+x\d\d Redistributable", null,
            "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x64.exe",
            "https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe"),
        ("Visual C++ 2012", @"Visual C\+\+ 2012 Redistributable", "11.0.61030",
            "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe",
            "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe"),
        ("Visual C++ 2013", @"Visual C\+\+ 2013 Redistributable", "12.0.40664", "https://aka.ms/highdpimfc2013x64enu", "https://aka.ms/highdpimfc2013x86enu"),
        ("Visual C++ 2015-2022", @"Visual C\+\+ (2015|2017|2019|2022|v14)\S* Redistributable", null,
            "https://aka.ms/vs/17/release/vc_redist.x64.exe", "https://aka.ms/vs/17/release/vc_redist.x86.exe"),
    };

    // wie Get-RuntimeStatus
    public static List<Laufzeit> RuntimeStatus()
    {
        var names = new List<string>();
        var versions = new List<string>();
        foreach (var root in new[] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" })
        {
            using var key = Registry.LocalMachine.OpenSubKey(root);
            if (key == null) continue;
            foreach (var sub in key.GetSubKeyNames())
            {
                using var entry = key.OpenSubKey(sub);
                var name = entry?.GetValue("DisplayName") as string;
                if (!Laufzeiten.IsRuntimeEntry(name)) continue;
                names.Add(name!);
                versions.Add(entry?.GetValue("DisplayVersion") as string ?? "");
            }
        }
        var list = new List<Laufzeit>();
        foreach (var r in VcRuntimes)
            foreach (var x64 in new[] { true, false })
            {
                var found = Laufzeiten.Evaluate(names, versions, r.Pattern, x64, r.Latest);
                var arch = x64 ? "x64" : "x86";
                list.Add(new(r.Name + " (" + arch + ")", found.Status, found.Version, x64 ? r.X64 : r.X86, "vcredist_" + Regex.Replace(r.Name, @"\D", "") + "_" + arch + ".exe"));
            }
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        bool Has(string folder, string file) => System.IO.File.Exists(Path.Combine(windir, folder, file));
        var wow = Directory.Exists(Path.Combine(windir, "SysWOW64"));
        var directX = new[] { "d3dx9_43.dll", "d3dx10_43.dll", "d3dx11_43.dll", "D3DCompiler_43.dll", "xinput1_3.dll", "XAudio2_7.dll", "X3DAudio1_7.dll" };
        var missing = directX.Where(f => !Has("System32", f) || (wow && !Has("SysWOW64", f))).ToList();
        list.Add(new("DirectX-Zusatzbibliotheken (9 bis 11)", missing.Count == 0 ? "vorhanden" : "fehlt", missing.Count > 0 ? "es fehlen: " + string.Join(", ", missing) : "",
            "https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe", "dxwebsetup.exe"));
        var xna = false;
        foreach (var path in new[] { @"SOFTWARE\WOW6432Node\Microsoft\XNA\Framework\v4.0", @"SOFTWARE\Microsoft\XNA\Framework\v4.0" })
        {
            using var key = Registry.LocalMachine.OpenSubKey(path);
            if (key?.GetValue("Installed") is int one && one == 1) xna = true;
        }
        list.Add(new("XNA Framework 4.0", xna ? "vorhanden" : "fehlt", "",
            "https://download.microsoft.com/download/A/C/2/AC2C903B-E6E8-42C2-9FD7-BEBAC362A930/xnafx40_redist.msi", "xnafx40_redist.msi"));
        var openAl = Has("System32", "OpenAL32.dll") || Has("SysWOW64", "OpenAL32.dll");
        list.Add(new("OpenAL", openAl ? "vorhanden" : "fehlt", openAl ? "" : "nicht von Microsoft – nur von Hand: openal.org", null, null));
        return list;
    }

    // wie Invoke-GameRuntimesTool: direkt von Microsoft laden, Signatur prüfen, der Installer fragt selbst nach
    public static void InstallRuntime(Laufzeit runtime) => Run("Lade " + runtime.Name + " …", report =>
    {
        var file = Download(runtime.Url!, runtime.File!, "O=Microsoft Corporation", new[] { "aka.ms", "download.microsoft.com", "download.visualstudio.microsoft.com" }, report, runtime.Name);
        report(runtime.Name + ": Installer läuft – dort bitte selbst bestätigen …");
        var code = StartSigned(file, "O=Microsoft Corporation");
        // 3010 = installiert, Neustart nötig; 1638 = eine neuere Fassung ist schon da
        return runtime.Name + (code is 0 or 3010 or 1638 ? ": fertig." : ": Installer beendet mit Code " + code + ".");
    });
}
