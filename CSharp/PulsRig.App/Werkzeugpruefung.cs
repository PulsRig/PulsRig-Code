using System.Diagnostics;
using System.IO;
using System.Management;
using System.Net.Http;
using System.Security.Principal;
using System.ServiceProcess;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Ein Werkzeug prüft zuerst (Check) und schlägt dann Schritte vor; ausgeführt wird erst nach der Rückfrage auf der
// Seite. Optionale Schritte (riskanter oder meist unnötig) bekommen eine eigene Frage, wie Confirm-Action -Optional.
sealed record Pruefzeile(bool Ok, string Label, string Detail = "");
// Admin: braucht Adminrechte; Ask: vorher fragen (nicht beim bloßen Öffnen einer Seite von Windows)
sealed record Schritt(string Text, Func<string> Run, bool Optional = false, bool Admin = true, bool Ask = true);
sealed record Werkbefund(List<Pruefzeile> Lines, string Summary, List<Schritt> Steps, string Question = "Jetzt ausführen?");

// Prüfungen und Reparaturen aus Treiber-Werkzeuge.ps1 (Invoke-*Tool), Ablauf und Regeln unverändert
static partial class Werkzeugpruefung
{
    static IEnumerable<ManagementObject> Query(string wql, string scope = @"root\cimv2")
    {
        using var searcher = new ManagementObjectSearcher(scope, wql);
        foreach (ManagementObject o in searcher.Get()) yield return o;
    }

    static string T(ManagementBaseObject o, string name) => (o[name]?.ToString() ?? "").Trim();

    // wie Invoke-Native: Rückgabe ist die Ausgabe, ein unerwarteter Code ist ein Fehler
    static string Native(string file, string arguments, params int[] ok)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, file), arguments) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        if (!(ok.Length == 0 ? new[] { 0 } : ok).Contains(process.ExitCode)) throw new InvalidOperationException(file + " meldet Code " + process.ExitCode);
        return output;
    }

    static string SafetyPoint()
    {
        if (!TreiberEinstellungen.Current.RestorePoint) return "";
        try
        {
            using var restore = new ManagementClass(@"\\.\root\default", "SystemRestore", null);
            var args = restore.GetMethodParameters("CreateRestorePoint");
            args["Description"] = "PulsRig (vor einer Reparatur)";
            args["RestorePointType"] = 12;   // MODIFY_SETTINGS
            args["EventType"] = 100;
            restore.InvokeMethod("CreateRestorePoint", args, null);
            return "Wiederherstellungspunkt erstellt";
        }
        catch (Exception) { return "kein Wiederherstellungspunkt (Computerschutz aus?)"; }
    }

    static Schritt Safety() => new("Wiederherstellungspunkt anlegen", SafetyPoint);

    public static Werkbefund? Check(string tool) => tool switch
    {
        "FixAudio" => Audio(),
        "FixDevices" => Devices(),
        "CleanDevices" => CleanDevices(),
        "FixNetwork" => Network(),
        "FixResolution" => Resolution(),
        "IncompatibleDrivers" => Incompatible(),
        "CleanDisk" => CleanDisk(),
        "OfflinePackage" => Offline(),
        "SystemInfo" => SystemInfo(),
        "Standby" => Standby(),
        "Autostart" => Autostart(),
        "DriverHistory" => DriverHistory(),
        "GamingCheck" => GamingCheck(),
        "Games" => Games(),
        _ => null,
    };

    // --- Ton ---------------------------------------------------------------------------------------------------------

    static Werkbefund Audio()
    {
        var lines = new List<Pruefzeile>();
        var steps = new List<Schritt>();
        foreach (var name in new[] { "AudioEndpointBuilder", "Audiosrv" })
        {
            using var service = new ServiceController(name);
            var startType = service.StartType;
            var ok = service.Status == ServiceControllerStatus.Running && startType != ServiceStartMode.Disabled;
            lines.Add(new(ok, "Dienst „" + service.DisplayName + "“", (service.Status == ServiceControllerStatus.Running ? "läuft" : "gestoppt") + ", Starttyp " + (startType == ServiceStartMode.Automatic ? "automatisch" : startType == ServiceStartMode.Manual ? "manuell" : startType.ToString())));
            if (!ok) steps.Add(new("Dienst " + name + " auf automatischen Start stellen und starten", () =>
            {
                Native("sc.exe", "config " + name + " start= auto");
                using var s = new ServiceController(name);
                if (s.Status != ServiceControllerStatus.Running) { s.Start(); s.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(20)); }
                return "ok";
            }));
        }
        // {0.0.0...} = Wiedergabe; Geräte der Klassen MEDIA und AudioEndpoint mit Fehlern
        var outputs = Query("SELECT Name, DeviceID FROM Win32_PnPEntity WHERE PNPClass = 'AudioEndpoint'").Where(d => T(d, "DeviceID").Contains("{0.0.0.")).ToList();
        lines.Add(new(outputs.Count > 0, "Wiedergabegeräte", outputs.Count + " gefunden" + (outputs.Count > 0 ? ": " + string.Join(", ", outputs.Select(o => T(o, "Name"))) : "")));
        var audio = Query("SELECT Name, DeviceID, ConfigManagerErrorCode, PNPClass FROM Win32_PnPEntity WHERE PNPClass = 'MEDIA' OR PNPClass = 'AudioEndpoint'").ToList();
        var broken = audio.Where(d => Convert.ToInt32(d["ConfigManagerErrorCode"]) is not (0 or 22 or 45)).ToList();
        lines.Add(new(broken.Count == 0, "Audiogeräte ohne Fehler", string.Join(", ", broken.Select(d => T(d, "Name") + " (Code " + d["ConfigManagerErrorCode"] + ")"))));
        foreach (var d in broken)
        {
            var id = T(d, "DeviceID");
            steps.Add(new("Gerät neu starten: " + T(d, "Name"), () => { Native("pnputil.exe", "/restart-device \"" + id + "\"", 0, 3010); return "ok"; }));
        }
        try
        {
            var muted = Core.Audio.GetMute();
            var level = Core.Audio.GetVolume();
            lines.Add(new(!muted, "Standardgerät nicht stumm", muted ? "ist stummgeschaltet" : ""));
            lines.Add(new(level >= 0.05, "Lautstärke", Math.Round(level * 100) + " %"));
            if (muted) steps.Add(new("Stummschaltung des Standardgeräts aufheben", () => { Core.Audio.SetMute(false); return "ok"; }));
            if (level < 0.05) steps.Add(new("Lautstärke auf 30 % stellen", () => { Core.Audio.SetVolume(0.3f); return "ok"; }));
        }
        catch (Exception) { lines.Add(new(false, "Standard-Wiedergabegerät", "keines festgelegt oder nicht ansprechbar")); }
        var restart = new Schritt("Audiodienste neu starten", () =>
        {
            using (var b = new ServiceController("AudioEndpointBuilder")) { if (b.Status == ServiceControllerStatus.Running) { b.Stop(); b.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(20)); } b.Start(); }
            using (var a = new ServiceController("Audiosrv")) { a.Refresh(); if (a.Status != ServiceControllerStatus.Running) { a.Start(); a.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(20)); } }
            return "ok";
        }, Optional: steps.Count == 0);
        steps.Add(restart);
        return new(lines, steps.Count == 1 ? "Keine Ursache gefunden. Prüfe, ob in Windows das richtige Wiedergabegerät gewählt ist (Klick auf das Lautsprechersymbol). Ein Neustart der Audiodienste hilft bei hängendem Ton." : "", steps);
    }

    // --- Gerätefehler -------------------------------------------------------------------------------------------------

    sealed record Geraet(string Name, string Id, int Code, string HardwareId);

    static List<Geraet> ProblemDevices() => Query("SELECT Name, DeviceID, ConfigManagerErrorCode, HardwareID FROM Win32_PnPEntity WHERE ConfigManagerErrorCode <> 0")
        .Select(d => new Geraet(T(d, "Name"), T(d, "DeviceID"), Convert.ToInt32(d["ConfigManagerErrorCode"]), (d["HardwareID"] as string[])?.FirstOrDefault() ?? "")).ToList();

    static List<Geraet> StillBroken(IEnumerable<Geraet> devices)
    {
        var ids = devices.Select(d => d.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return ProblemDevices().Where(d => ids.Contains(d.Id) && d.Code != 22).ToList();
    }

    static Werkbefund Devices()
    {
        var problems = ProblemDevices();
        var lines = problems.Select(p => new Pruefzeile(false, p.Name.Length > 0 ? p.Name : p.Id, Geraetefehler.Get(p.Code).Text + " (Code " + p.Code + ")")).ToList();
        if (problems.Count == 0) return new(new() { new(true, "Geräte", "Kein Gerät meldet einen Fehler.") }, "", new());
        string Fix(Geraet p) => Geraetefehler.Get(p.Code).Fix;
        var notes = new List<string>();
        var reboot = problems.Count(p => Fix(p) == "Reboot");
        var firmware = problems.Count(p => Fix(p) == "Firmware");
        if (reboot > 0) notes.Add(reboot + " Gerät(e) brauchen nur einen Neustart des PCs (bei USB-Geräten: ab- und wieder anstecken).");
        if (firmware > 0) notes.Add(firmware + " Gerät(e): Die Ursache liegt im BIOS oder an der Hardware – BIOS-Einstellungen prüfen, BIOS aktualisieren, Gerät umstecken.");
        var steps = new List<Schritt>();
        var broken = problems.Where(p => Fix(p) == "Driver").ToList();
        if (broken.Count > 0)
        {
            steps.Add(Safety());
            steps.Add(new("Hardware neu erkennen", () => { Native("pnputil.exe", "/scan-devices"); return "ok"; }));
            steps.Add(new("Passende Treiber bei Windows Update suchen und installieren", () => DriversFor(broken)));
            steps.Add(new("Geräte neu starten", () =>
            {
                foreach (var d in StillBroken(broken)) try { Native("pnputil.exe", "/restart-device \"" + d.Id + "\"", 0, 3010); } catch (Exception) { }
                var left = StillBroken(broken);
                return left.Count == 0 ? "alle Geräte arbeiten wieder" : left.Count + " melden weiter einen Fehler";
            }));
            // ohne Treiber (Code 28) bringt Entfernen nichts - das Gerät käme genauso zurück
            steps.Add(new("Geräte, die weiter Fehler melden, entfernen und neu erkennen lassen", () =>
            {
                var removable = StillBroken(broken).Where(d => d.Code != 28).ToList();
                foreach (var d in removable) try { Native("pnputil.exe", "/remove-device \"" + d.Id + "\"", 0, 3010); } catch (Exception) { }
                Native("pnputil.exe", "/scan-devices");
                return removable.Count + " entfernt";
            }, Optional: true));
        }
        foreach (var d in problems.Where(p => Fix(p) == "Disabled"))
            steps.Add(new("Deaktiviertes Gerät wieder aktivieren: " + d.Name, () => { Native("pnputil.exe", "/enable-device \"" + d.Id + "\"", 0, 3010); return "ok"; }, Optional: true));
        if (problems.Any(p => p.Code == 28)) notes.Add("Für Geräte ohne Treiber zeigt die Treiber-Seite, was der Microsoft-Katalog hat.");
        return new(lines, string.Join(" ", notes), steps, broken.Count > 0 ? "Reparatur für " + broken.Count + " Gerät(e) versuchen (Treiber suchen, Gerät neu starten)?" : "Jetzt ausführen?");
    }

    // wie der Teil von Invoke-FixDevicesTool mit Find-DriverUpdates: nur Angebote für genau diese Geräte
    static string DriversFor(List<Geraet> devices)
    {
        var ids = devices.Select(d => d.HardwareId).Where(i => i.Length > 0).ToHashSet(StringComparer.OrdinalIgnoreCase);
        dynamic session = Activator.CreateInstance(Type.GetTypeFromProgID("Microsoft.Update.Session")!)!;
        session.ClientApplicationID = "PulsRig";
        dynamic result = session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Driver'");
        dynamic collection = Activator.CreateInstance(Type.GetTypeFromProgID("Microsoft.Update.UpdateColl")!)!;
        for (var i = 0; i < (int)result.Updates.Count; i++)
        {
            var u = result.Updates.Item(i);
            if (ids.Contains((string)u.DriverHardwareID) && (bool)u.EulaAccepted) collection.Add(u);
        }
        if ((int)collection.Count == 0) return "Windows Update hat für diese Geräte keinen Treiber";
        var downloader = session.CreateUpdateDownloader();
        downloader.Updates = collection;
        downloader.Download();
        var installer = session.CreateUpdateInstaller();
        installer.Updates = collection;
        installer.Install();
        return (int)collection.Count + " Treiber installiert";
    }

    // --- Gerätedaten ----------------------------------------------------------------------------------------------------

    // Einträge nicht mehr angeschlossener Hardware (Code 45), eng gefasst wie Select-CleanableDevices
    static Werkbefund CleanDevices()
    {
        var all = Geraeteliste.All();
        var absent = all.Where(d => !d.Present).ToList();
        var cleanable = all.Where(d => Geraete.IsCleanable(d.Present, d.InstanceId, d.Class)).ToList();
        var lines = new List<Pruefzeile> { new(true, "Geräteeinträge", all.Count + ", davon " + absent.Count + " zu nicht mehr angeschlossener Hardware") };
        foreach (var g in cleanable.GroupBy(d => d.Class).OrderByDescending(g => g.Count()))
            lines.Add(new(false, g.Count() + " × " + (g.Key.Length > 0 ? g.Key : "ohne Klasse"), string.Join(", ", g.Select(d => d.Name).Where(n => n.Length > 0).Distinct().Take(3))));
        if (cleanable.Count == 0) return new(lines, "Nichts zu bereinigen.", new());
        var ids = cleanable.Select(d => d.InstanceId).ToList();
        return new(lines, cleanable.Count + " Einträge lassen sich gefahrlos entfernen (Windows legt sie beim erneuten Anschließen neu an)."
                + (absent.Count > cleanable.Count ? " Unangetastet bleiben " + (absent.Count - cleanable.Count) + " Einträge (Bluetooth, Drucker, Netzwerk und andere, die oft nur ausgeschaltet sind)." : ""),
            new() { Safety(), new(cleanable.Count + " Einträge entfernen", () =>
            {
                var removed = 0;
                foreach (var id in ids) try { Native("pnputil.exe", "/remove-device \"" + id + "\"", 0, 3010); removed++; } catch (Exception) { }
                return removed + " von " + ids.Count + " entfernt";
            }) }, cleanable.Count + " Einträge entfernen?");
    }

    // --- Netzwerk -------------------------------------------------------------------------------------------------------

    sealed record Netzstand(List<(string Name, string Description, string Status, string Speed)> Adapters, bool Dhcp, List<Pruefzeile> Checks)
    {
        public bool Healthy => Checks.All(c => c.Ok);
    }

    static Netzstand NetworkState()
    {
        const string Space = @"root\StandardCimv2";
        var adapters = new List<(string, string, string, string)>();
        try
        {
            foreach (var a in Query("SELECT Name, InterfaceDescription, InterfaceAdminStatus, MediaConnectState, Speed, ConnectorPresent, Hidden FROM MSFT_NetAdapter", Space))
                if (a["ConnectorPresent"] is true && a["Hidden"] is not true)
                    adapters.Add((T(a, "Name"), T(a, "InterfaceDescription"), Netzwerk.Status(a["InterfaceAdminStatus"], a["MediaConnectState"]), Netzwerk.LinkSpeed(Convert.ToDouble(a["Speed"] ?? 0))));
        }
        catch (Exception) { }
        var routed = new HashSet<int>();
        var addresses = 0;
        var dhcp = false;
        string? dnsServer = null;
        try
        {
            foreach (var r in Query("SELECT DestinationPrefix, InterfaceIndex FROM MSFT_NetRoute", Space)) if (Netzwerk.IsDefaultRoute(r["DestinationPrefix"])) routed.Add(Convert.ToInt32(r["InterfaceIndex"]));
            addresses = Query("SELECT IPAddress, AddressFamily, InterfaceIndex FROM MSFT_NetIPAddress", Space).Count(a => Netzwerk.IsIPv4(a["AddressFamily"]) && routed.Contains(Convert.ToInt32(a["InterfaceIndex"])) && Netzwerk.IsUsableAddress(T(a, "IPAddress")));
            dhcp = Query("SELECT AddressFamily, InterfaceIndex, Dhcp FROM MSFT_NetIPInterface", Space).Any(i => Netzwerk.IsIPv4(i["AddressFamily"]) && routed.Contains(Convert.ToInt32(i["InterfaceIndex"])) && Netzwerk.IsDhcp(i["Dhcp"]));
            dnsServer = Query("SELECT AddressFamily, ServerAddresses FROM MSFT_DNSClientServerAddress", Space).Where(d => Netzwerk.IsIPv4(d["AddressFamily"])).SelectMany(d => (d["ServerAddresses"] as string[]) ?? Array.Empty<string>()).FirstOrDefault(s => s.Length > 0);
        }
        catch (Exception) { }
        var internet = Netzwerk.TcpPort("1.1.1.1", 443) || Netzwerk.TcpPort("8.8.8.8", 443);
        var dns = false;
        // direkt beim eingestellten Server fragen, damit kein Zwischenspeicher antwortet
        if (dnsServer != null) try { dns = Netzwerk.IsDnsAnswer(Native("nslookup.exe", "-type=A -timeout=4 www.microsoft.com " + dnsServer, 0, 1).Split('\n')); } catch (Exception) { }
        var web = false;
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            web = Netzwerk.IsConnectTest(client.GetStringAsync("http://www.msftconnecttest.com/connecttest.txt").GetAwaiter().GetResult());
        }
        catch (Exception) { }
        return new(adapters, dhcp, new()
        {
            new(adapters.Any(a => a.Item3 == "Up"), "Netzwerkadapter verbunden"),
            new(addresses > 0, "IP-Adresse und Gateway"),
            new(internet, "Internet erreichbar"),
            new(dns, "Namensauflösung (DNS)"),
            new(web, "Webseiten abrufbar"),
        });
    }

    static Werkbefund Network()
    {
        var state = NetworkState();
        var lines = state.Adapters.Select(a => new Pruefzeile(a.Status == "Up", "Adapter " + a.Name, a.Description + " · " + (a.Status == "Up" ? "verbunden, " + a.Speed : a.Status == "Disabled" ? "deaktiviert" : "getrennt"))).ToList();
        lines.AddRange(state.Checks);
        if (state.Adapters.Count == 0) return new(lines, "Windows kennt keinen Netzwerkadapter – vermutlich fehlt der Treiber. Dafür „Gerätefehler reparieren“ oder das Offline-Paket verwenden.", new());
        // Stufe 1 harmlos, Stufe 2 startet die Adapter neu, Stufe 3 nur auf eigene Zustimmung
        var steps = new List<Schritt>
        {
            new("DNS-Zwischenspeicher leeren" + (state.Dhcp ? ", IP-Adresse neu anfordern" : ""), () =>
            {
                Native("ipconfig.exe", "/flushdns");
                // /release meldet Code 1, wenn ein Adapter gerade getrennt ist - das ist kein Fehler
                if (state.Dhcp) { Native("ipconfig.exe", "/release", 0, 1); Native("ipconfig.exe", "/renew", 0, 1); }
                return NetworkState().Healthy ? "die Verbindung funktioniert wieder" : "ok";
            }),
        };
        if (!state.Healthy)
            steps.Add(new("Netzwerkadapter neu starten", () =>
            {
                if (NetworkState().Healthy) return "nicht nötig, die Verbindung funktioniert";
                foreach (var a in Query("SELECT * FROM MSFT_NetAdapter WHERE ConnectorPresent = TRUE", @"root\StandardCimv2"))
                    try { a.InvokeMethod("Restart", null); } catch (Exception) { }
                Thread.Sleep(8000);
                return NetworkState().Healthy ? "die Verbindung funktioniert wieder" : "hat nicht geholfen";
            }));
        steps.Add(new("Netzwerkeinstellungen von Windows zurücksetzen (Winsock und TCP/IP) – fest eingetragene IP-Adressen gehen verloren, danach Neustart", () =>
        {
            var point = SafetyPoint();
            Native("netsh.exe", "winsock reset");
            Native("netsh.exe", "int ip reset", 0, 1);
            return (point.Length > 0 ? point + ", " : "") + "bitte den PC jetzt neu starten";
        }, Optional: true));
        var summary = state.Healthy ? "Die Verbindung funktioniert. Leeren und Erneuern geht trotzdem." : !state.Checks[0].Ok ? "Kein Adapter ist verbunden – zuerst Kabel bzw. WLAN prüfen." : "";
        return new(lines, summary, steps, state.Healthy ? "Trotzdem DNS-Zwischenspeicher leeren und die Adresse erneuern?" : "Reparatur starten (die Verbindung bricht dabei kurz ab)?");
    }

    // --- Bildauflösung --------------------------------------------------------------------------------------------------

    static Werkbefund Resolution()
    {
        var lines = new List<Pruefzeile>();
        var adapters = Query("SELECT Name, Service, ConfigManagerErrorCode FROM Win32_PnPEntity WHERE PNPClass = 'Display'").ToList();
        var withoutDriver = 0;
        foreach (var a in adapters)
        {
            var basic = T(a, "Service") == "BasicDisplay";
            var code = Convert.ToInt32(a["ConfigManagerErrorCode"] ?? 0);
            var ok = !basic && code is 0 or 22;
            if (!ok) withoutDriver++;
            lines.Add(new(ok, "Grafikkarte " + T(a, "Name"), basic ? "läuft nur mit dem Windows-Standardtreiber" : !ok ? "meldet Fehlercode " + code : "Treiber geladen"));
        }
        var names = new Dictionary<string, string>();
        var native = new Dictionary<string, (int W, int H)>();
        try
        {
            foreach (var m in Query("SELECT InstanceName, UserFriendlyName FROM WmiMonitorID", @"root\wmi"))
                names[T(m, "InstanceName").Split('\\').ElementAtOrDefault(1) ?? ""] = new string(((ushort[]?)m["UserFriendlyName"] ?? Array.Empty<ushort>()).Where(c => c != 0).Select(c => (char)c).ToArray());
            foreach (var m in Query("SELECT InstanceName, MonitorSourceModes, PreferredMonitorSourceModeIndex FROM WmiMonitorListedSupportedSourceModes", @"root\wmi"))
            {
                var modes = (ManagementBaseObject[])m["MonitorSourceModes"];
                var preferred = modes[Convert.ToInt32(m["PreferredMonitorSourceModeIndex"])];
                native[T(m, "InstanceName").Split('\\').ElementAtOrDefault(1) ?? ""] = (Convert.ToInt32(preferred["HorizontalActivePixels"]), Convert.ToInt32(preferred["VerticalActivePixels"]));
            }
        }
        catch (Exception) { }
        var steps = new List<Schritt>();
        foreach (var d in Display.GetDisplays())
        {
            var code = (d.MonitorId ?? "").Split('\\').ElementAtOrDefault(1) ?? "";
            (int W, int H)? best = native.TryGetValue(code, out var n) ? n : null;
            if (best == null && d.Modes.Count > 0) { var l = d.Modes.OrderByDescending(m => m.Width * m.Height).First(); best = (l.Width, l.Height); }
            var c = d.Current;
            // hochkant gedrehte Bildschirme melden Breite und Höhe vertauscht
            var isNative = best != null && c != null && ((c.Width == best.Value.W && c.Height == best.Value.H) || (c.Width == best.Value.H && c.Height == best.Value.W));
            var name = names.TryGetValue(code, out var nm) && nm.Length > 0 ? nm : "Bildschirm";
            lines.Add(new(isNative, "Bildschirm " + name, c == null ? "" : c.Width + "×" + c.Height + " bei " + c.Frequency + " Hz" + (best != null ? ", empfohlen " + best.Value.W + "×" + best.Value.H : "")));
            if (isNative || best == null || withoutDriver > 0) continue;
            var rate = Anzeige.SelectRefreshRate(d.Modes.Where(m => m.Width == best.Value.W && m.Height == best.Value.H).Select(m => m.Frequency), c?.Frequency ?? 0);
            if (rate <= 0) { lines.Add(new(false, name, "Der Treiber bietet die empfohlene Auflösung nicht an – Kabel und Anschluss prüfen.")); continue; }
            var (w, h, device) = (best.Value.W, best.Value.H, d.Device);
            steps.Add(new(name + " auf " + w + "×" + h + " bei " + rate + " Hz stellen", () =>
            {
                // erst nur prüfen lassen, ob der Treiber den Modus annimmt
                var test = Display.SetMode(device, w, h, rate, true);
                if (test != 0) throw new InvalidOperationException("der Treiber lehnt den Modus ab (Code " + test + ")");
                var result = Display.SetMode(device, w, h, rate, false);
                return result == 0 ? "ok" : throw new InvalidOperationException("Windows meldet Code " + result);
            }));
        }
        if (withoutDriver > 0) return new(lines, "Ursache: Der Grafikkarte fehlt ihr Treiber – ohne ihn bietet Windows nur niedrige Auflösungen an. Die Treiber-Seite sucht und installiert ihn.", new());
        return new(lines, steps.Count == 0 ? "Alle Bildschirme laufen in ihrer empfohlenen Auflösung. Wirkt das Bild trotzdem unscharf oder zu groß, liegt es meist an der Skalierung (Anzeigeeinstellungen von Windows)." : "", steps);
    }

    // --- Inkompatible Treiber -------------------------------------------------------------------------------------------

    static Werkbefund Incompatible()
    {
        var integrity = false;
        try { integrity = Query("SELECT SecurityServicesRunning FROM Win32_DeviceGuard", @"root\Microsoft\Windows\DeviceGuard").Any(g => ((uint[]?)g["SecurityServicesRunning"] ?? Array.Empty<uint>()).Contains(2u)); } catch (Exception) { }
        var lines = new List<Pruefzeile> { new(true, "Kernisolierung (Speicher-Integrität)", integrity ? "eingeschaltet" : "ausgeschaltet") };
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var services = Query("SELECT Name, PathName, State FROM Win32_SystemDriver").Where(s => T(s, "PathName").Length > 0).Select(s => (Name: T(s, "Name"), Path: Core.Treiber.ResolveDriverPath(T(s, "PathName"), windir), Running: T(s, "State") == "Running")).ToList();
        var files = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in Directory.GetFiles(Path.Combine(windir, @"System32\drivers"), "*.sys")) files[f] = f;
        foreach (var s in services) if (s.Path.EndsWith(".sys", StringComparison.OrdinalIgnoreCase) && File.Exists(s.Path)) files[s.Path] = s.Path;
        TreiberPaket[]? packages = null;
        var inUse = Query("SELECT InfName FROM Win32_PnPSignedDriver").Select(d => T(d, "InfName").ToLowerInvariant()).Where(i => i.Length > 0).ToHashSet();
        var removable = new List<TreiberPaket>();
        var store = Path.Combine(windir, @"System32\DriverStore\FileRepository");
        foreach (var path in files.Values.OrderBy(p => p))
        {
            string[] issues;
            try { issues = Core.Treiber.HvciIssues(path); } catch (Exception) { continue; }
            if (issues.Length == 0) continue;
            var name = Path.GetFileName(path);
            var service = services.FirstOrDefault(s => Path.GetFileName(s.Path).Equals(name, StringComparison.OrdinalIgnoreCase));
            packages ??= Sicherung.ParsePackages(Native("pnputil.exe", "/enum-drivers").Split('\n').Select(l => l.TrimEnd('\r')));
            // der Ordner im Treiberspeicher trägt den Namen der INF-Datei, zu der die Treiberdatei gehört
            var folder = Directory.GetDirectories(store).FirstOrDefault(d => File.Exists(Path.Combine(d, name)));
            var package = folder == null ? null : packages.FirstOrDefault(p => p.Original.Equals(System.Text.RegularExpressions.Regex.Replace(Path.GetFileName(folder), @"\.inf_.*$", ".inf"), StringComparison.OrdinalIgnoreCase));
            var company = "";
            try { company = FileVersionInfo.GetVersionInfo(path).CompanyName ?? ""; } catch (Exception) { }
            var used = service.Running || (package != null && inUse.Contains(package.Published.ToLowerInvariant()));
            lines.Add(new(false, name + (company.Length > 0 ? " (" + company + ")" : ""), string.Join("; ", issues) + " · " +
                (used ? "wird gerade verwendet – beim Hersteller nach einer neueren Version suchen" : package != null ? "derzeit unbenutzt, Paket " + package.Published + " (" + package.Original + ")" : "kein eigenes Treiberpaket – gehört zu Windows oder einem Programm")));
            if (!used && package != null && removable.All(p => p.Published != package.Published)) removable.Add(package);
        }
        if (lines.Count == 1) return new(lines, "Keine inkompatiblen Treiber gefunden.", new());
        var summary = (integrity ? "" : "Solange solche Treiber installiert sind, lässt sich die Speicher-Integrität in Windows-Sicherheit nicht einschalten. ")
            + (removable.Count > 0 ? "Unbenutzte Pakete lassen sich entfernen; wird das Gerät später wieder angeschlossen, braucht es einen neuen Treiber." : "");
        var steps = new List<Schritt>();
        if (removable.Count > 0)
        {
            steps.Add(Safety());
            foreach (var p in removable) steps.Add(new("Entferne " + p.Published + " (" + p.Original + ")", () => { Native("pnputil.exe", "/delete-driver " + p.Published + " /uninstall", 0, 3010); return "ok"; }));
        }
        return new(lines, summary.Trim(), steps, removable.Count + " unbenutzte(s) Treiberpaket(e) entfernen?");
    }

    // --- Speicherplatz --------------------------------------------------------------------------------------------------

    static string Size(long bytes) => bytes >= 1L << 30 ? (bytes / (double)(1L << 30)).ToString("N1", Ui.De) + " GB" : (bytes / (double)(1 << 20)).ToString("N0", Ui.De) + " MB";

    // wie Get-CleanTargets und Get-ShaderCacheTarget; was gelöscht werden darf, entscheidet Core (Tabu-Regeln:
    // kein Papierkorb, keine Treibersicherungen, keine Speicherabbilder, keine Junctions)
    static Werkbefund CleanDisk()
    {
        var admin = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        var windir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var targets = new List<(string Name, FileInfo[] Files, bool Admin)>
        {
            ("Temporäre Dateien", Aufraeumen.CleanableFiles(Path.GetTempPath(), 2), false),
            ("Temporäre Dateien von Windows", Aufraeumen.CleanableFiles(Path.Combine(windir, "Temp"), 2), true),
            ("Alte Downloads von Windows Update", Aufraeumen.CleanableFiles(Path.Combine(windir, @"SoftwareDistribution\Download"), 7), true),
            ("Fehlerberichte von Windows", new[] { Path.Combine(programData, @"Microsoft\Windows\WER\ReportArchive"), Path.Combine(programData, @"Microsoft\Windows\WER\ReportQueue"), Path.Combine(local, @"Microsoft\Windows\WER\ReportArchive") }
                .SelectMany(p => Aufraeumen.CleanableFiles(p, 7)).ToArray(), true),
            ("Von PulsRig geladene Installer", Aufraeumen.CleanableFiles(Path.Combine(Belastung.Folder, "Downloads"), 7), false),
        };
        var low = Path.Combine(Path.GetDirectoryName(local)!, "LocalLow");
        var shaderPaths = new List<string>
        {
            Path.Combine(local, @"NVIDIA\DXCache"), Path.Combine(local, @"NVIDIA\GLCache"), Path.Combine(local, @"NVIDIA Corporation\NV_Cache"), Path.Combine(low, @"NVIDIA\PerDriverVersion\DXCache"),
            Path.Combine(local, @"AMD\DxCache"), Path.Combine(local, @"AMD\DxcCache"), Path.Combine(local, @"AMD\GLCache"), Path.Combine(local, @"AMD\VkCache"), Path.Combine(low, @"Intel\ShaderCache"), Path.Combine(local, "D3DSCache"),
        };
        // Steam: der Shader-Cache jeder Spielebibliothek (Ordner aus libraryfolders.vdf)
        try
        {
            if (Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath", null) is string steam)
            {
                steam = steam.Replace('/', '\\');
                var libraries = new List<string> { steam };
                var list = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                if (File.Exists(list)) foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(File.ReadAllText(list), "\"path\"\\s+\"([^\"]+)\"")) libraries.Add(m.Groups[1].Value.Replace(@"\\", @"\"));
                shaderPaths.AddRange(libraries.Distinct(StringComparer.OrdinalIgnoreCase).Select(l => Path.Combine(l, @"steamapps\shadercache")));
            }
        }
        catch (Exception) { }
        var shader = shaderPaths.SelectMany(p => Aufraeumen.CleanableFiles(p, 0)).ToArray();

        long Sum(IEnumerable<FileInfo> f) => f.Sum(x => { try { return x.Length; } catch (Exception) { return 0L; } });
        var drive = new DriveInfo(Path.GetPathRoot(windir)!);
        var lines = new List<Pruefzeile> { new(true, "Laufwerk " + drive.Name.TrimEnd('\\'), Size(drive.AvailableFreeSpace) + " frei") };
        foreach (var t in targets) lines.Add(new(true, t.Name, Size(Sum(t.Files)) + (t.Admin && !admin ? " (nur mit Adminrechten)" : "")));
        lines.Add(new(true, "Shader-Cache von Grafiktreibern und Steam", Size(Sum(shader))));
        var usable = targets.Where(t => Sum(t.Files) >= 1 << 20 && (!t.Admin || admin)).ToList();
        var total = usable.Sum(t => Sum(t.Files));
        var steps = new List<Schritt>();
        static string Delete(IEnumerable<FileInfo> files)
        {
            long bytes = 0;
            foreach (var f in files) try { var l = f.Length; File.Delete(f.FullName); bytes += l; } catch (Exception) { }   // gesperrt: bleibt
            return Size(bytes) + " freigegeben";
        }
        if (total >= 1 << 20) steps.Add(new("Temporäre Dateien und alte Downloads löschen (" + Size(total) + ")", () => Delete(usable.SelectMany(t => t.Files))));
        if (Sum(shader) >= 1 << 20)
            steps.Add(new("Shader-Cache löschen (" + Size(Sum(shader)) + ") – Spiele ruckeln danach beim ersten Start kurz, während sie neu übersetzen", () => Delete(shader), Optional: true));
        // alte Fassungen im Treiberspeicher: je Treiber bleiben die zwei neuesten, Benutztes bleibt immer
        List<(Treiberpaket Package, long Bytes)> packages;
        try { packages = OldPackages(); }
        catch (Exception e) { packages = new(); lines.Add(new(false, "Alte Treiberpakete", "Der Treiberspeicher ließ sich nicht lesen (" + e.Message.Trim() + ")")); }
        var packBytes = packages.Sum(p => p.Bytes);
        lines.Add(new(true, "Alte Treiberpakete", packages.Count == 0 ? "keine" : packages.Count + " Pakete, " + Size(packBytes) + (admin ? "" : " (nur mit Adminrechten)")));
        foreach (var (p, bytes) in packages.Take(8))
            lines.Add(new(true, "  " + p.Provider + " · " + ClassName(p.ClassGuid), "Version " + p.Version + " – " + Size(bytes)));
        if (packages.Count > 8) lines.Add(new(true, "  und " + (packages.Count - 8) + " weitere"));
        if (packages.Count > 0)
            steps.Add(new(packages.Count + " alte Treiberpakete entfernen (" + Size(packBytes) + ")", () =>
            {
                int removed = 0; long freed = 0;
                // ohne /force: ein Paket, das doch noch gebraucht wird, lehnt pnputil ab - es bleibt
                foreach (var (p, bytes) in packages)
                    try { Native("pnputil.exe", "/delete-driver " + p.Inf); removed++; freed += bytes; } catch (Exception) { }
                return removed + " entfernt, " + Size(freed) + " freigegeben" + (removed < packages.Count ? " (" + (packages.Count - removed) + " noch in Gebrauch, sie bleiben)" : "");
            }, Optional: true));
        return new(lines, (steps.Count == 0 ? "Nichts zu bereinigen. " : "") + "Nicht angefasst werden: Papierkorb, gesicherte Treiber, Speicherabbilder nach Bluescreens und je Treiber die zwei neuesten Fassungen.", steps, steps.Count > 0 && !steps[0].Optional ? steps[0].Text + "?" : "Jetzt ausführen?");
    }

    // --- Offline-Paket --------------------------------------------------------------------------------------------------

    // wie Get-OfflinePackageSize: Größe aller Treiber von Drittherstellern im Treiberspeicher
    public static long OfflineSize()
    {
        var store = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\DriverStore\FileRepository");
        long size = 0;
        foreach (var name in OfflinePaket.OriginalNames(Native("pnputil.exe", "/enum-drivers").Split('\n').Select(l => l.TrimEnd('\r'))))
            foreach (var dir in Directory.GetDirectories(store, name + "_*"))
                try { size += new DirectoryInfo(dir).EnumerateFiles("*", SearchOption.AllDirectories).Sum(f => f.Length); } catch (Exception) { }
        return size;
    }

    static Werkbefund Offline()
    {
        var size = OfflineSize();
        var target = Werkzeuglauf.Backups;
        return new(new() { new(true, "Größe etwa", Size(size)), new(true, "Ziel", target) },
            "Das Paket enthält alle installierten Treiber von Drittherstellern samt Startdatei zum Einspielen – gedacht für diesen PC nach einer Neuinstallation von Windows, auch ohne Internet.",
            new() { new("Offline-Paket erstellen", () => OfflinePackage(target)) }, "Offline-Paket erstellen?");
    }

    // wie New-OfflinePackage: alle Treiber von Drittherstellern samt Startdatei in "Offline-Paket_<Datum>" unter root
    public static string OfflinePackage(string root)
    {
        var folder = Path.Combine(root, "Offline-Paket_" + DateTime.Now.ToString("yyyy-MM-dd_HHmm"));
        var drivers = Path.Combine(folder, "Treiber");
        Directory.CreateDirectory(drivers);
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "pnputil.exe"), "/export-driver * \"" + drivers + "\"") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true };
        using var p = Process.Start(start)!;
        p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        if (p.ExitCode != 0)
        {
            // ein halbes Paket hilft niemandem und belegt nur Platz
            try { Directory.Delete(folder, true); } catch (Exception) { }
            throw new InvalidOperationException(OfflinePaket.ExportError(p.ExitCode));
        }
        File.WriteAllLines(Path.Combine(folder, "Treiber-installieren.bat"), OfflinePaket.Starter(), System.Text.Encoding.ASCII);
        File.WriteAllLines(Path.Combine(folder, "LIESMICH.txt"), OfflinePaket.Readme(DateTime.Now), System.Text.Encoding.UTF8);
        var files = new DirectoryInfo(drivers).GetFiles("*", SearchOption.AllDirectories);
        return files.Count(f => f.Extension.Equals(".inf", StringComparison.OrdinalIgnoreCase)) + " Treiberpakete, " + Size(files.Sum(f => f.Length)) + " · " + folder;
    }

    // --- Systeminformationen ------------------------------------------------------------------------------------------

    static Werkbefund SystemInfo()
    {
        var lines = new List<Pruefzeile>();
        void Add(string label, string detail) => lines.Add(new(true, label, detail));
        string Date(object? d) { try { return ManagementDateTimeConverter.ToDateTime(d?.ToString()).ToString("dd.MM.yyyy"); } catch (Exception) { return ""; } }
        var os = Query("SELECT Caption, BuildNumber, InstallDate, LastBootUpTime FROM Win32_OperatingSystem").First();
        const string Cv = @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion";
        Add("Windows", T(os, "Caption") + ", Version " + Registry.GetValue(Cv, "DisplayVersion", "") + " (Build " + T(os, "BuildNumber") + "." + Registry.GetValue(Cv, "UBR", "") + ")");
        Add("Installiert", Date(os["InstallDate"]) + ", läuft seit " + ManagementDateTimeConverter.ToDateTime(T(os, "LastBootUpTime")).ToString("dd.MM.yyyy HH:mm"));
        var system = Query("SELECT Manufacturer, Model, TotalPhysicalMemory FROM Win32_ComputerSystem").First();
        if (!Systeminfo.IsPlaceholder(T(system, "Manufacturer"))) Add("System", T(system, "Manufacturer") + " " + T(system, "Model"));
        var board = Query("SELECT Manufacturer, Product FROM Win32_BaseBoard").First();
        Add("Mainboard", T(board, "Manufacturer") + " " + T(board, "Product"));
        var bios = Query("SELECT SMBIOSBIOSVersion, ReleaseDate FROM Win32_BIOS").First();
        Add("BIOS", T(bios, "SMBIOSBIOSVersion") + " vom " + Date(bios["ReleaseDate"]));
        var cpu = Query("SELECT Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed FROM Win32_Processor").First();
        Add("Prozessor", T(cpu, "Name") + " · " + cpu["NumberOfCores"] + " Kerne, " + cpu["NumberOfLogicalProcessors"] + " Threads, bis " + (Convert.ToDouble(cpu["MaxClockSpeed"]) / 1000).ToString("N1", Ui.De) + " GHz");
        Add("Arbeitsspeicher", (Convert.ToDouble(system["TotalPhysicalMemory"]) / (1L << 30)).ToString("N0", Ui.De) + " GB");
        foreach (var m in Query("SELECT BankLabel, DeviceLocator, Capacity, ConfiguredClockSpeed, PartNumber FROM Win32_PhysicalMemory"))
            Add("  " + (T(m, "BankLabel") + " " + T(m, "DeviceLocator")).Trim(), (Convert.ToDouble(m["Capacity"]) / (1L << 30)).ToString("N0", Ui.De) + " GB, " + m["ConfiguredClockSpeed"] + " MHz, " + T(m, "PartNumber"));
        // Win32_VideoController kennt höchstens 4 GB Speicher - die echte Größe steht in der Registry
        var memory = new Dictionary<string, long>();
        try
        {
            using var cls = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}");
            foreach (var sub in cls?.GetSubKeyNames().Where(n => n.StartsWith('0')) ?? Enumerable.Empty<string>())
            {
                using var k = cls!.OpenSubKey(sub);
                if (k?.GetValue("DriverDesc") is string desc && k.GetValue("HardwareInformation.qwMemorySize") is long bytes) memory[desc] = bytes;
            }
        }
        catch (Exception) { }
        foreach (var g in Query("SELECT Name, AdapterRAM, DriverVersion FROM Win32_VideoController"))
            Add("Grafik", T(g, "Name") + ", " + (Systeminfo.GpuMemory(memory.GetValueOrDefault(T(g, "Name")), Convert.ToInt64(g["AdapterRAM"] ?? 0L)) / (double)(1L << 30)).ToString("N0", Ui.De) + " GB, Treiber " + T(g, "DriverVersion"));
        foreach (var v in Query("SELECT DeviceID, Size, FreeSpace FROM Win32_LogicalDisk WHERE DriveType = 3"))
            Add("Laufwerk " + T(v, "DeviceID"), Size(Convert.ToInt64(v["Size"] ?? 0L)) + ", davon " + Size(Convert.ToInt64(v["FreeSpace"] ?? 0L)) + " frei");
        foreach (var s in Query("SELECT Name FROM Win32_SoundDevice")) Add("Audio", T(s, "Name"));
        var problems = ProblemDevices().Count(p => p.Code != 45);
        Add("Geräte mit Fehlern", problems.ToString());
        return new(lines, "", new() { new("Als Textdatei speichern", () =>
        {
            Directory.CreateDirectory(Belastung.Folder);
            var file = Path.Combine(Belastung.Folder, "Systeminformationen.txt");
            File.WriteAllLines(file, lines.Select(l => l.Label + ": " + l.Detail), System.Text.Encoding.UTF8);
            return "gespeichert: " + file;
        }, Optional: true) });
    }
}
