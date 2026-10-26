using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Neuinstallation wie PulsRig-Neuinstallation.ps1: vorher Treiber (Offline-Paket) und Programmliste (winget export) in
// einen Ordner "Neuinstallation_<Datum>" sichern, danach geführt einspielen – Treiber, Spielkomponenten, dann die
// Programme zum Abhaken. Programme installiert PulsRig nur, wenn sie abgehakt sind; Treiber nur mit Adminrechten.
sealed class NeuinstallPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";

    // Arbeit läuft weiter, wenn man die Seite verlässt; Stand bleibt bis zum Beenden
    static string busy = "", message = "";
    static readonly Dictionary<string, string> installed = new(StringComparer.OrdinalIgnoreCase);
    static event Action? Changed;
    static int lastTab;
    static string? folder;

    readonly MainWindow main;
    readonly Grid root = new();
    readonly HashSet<string> picked = new(StringComparer.OrdinalIgnoreCase);
    List<string> found = new();
    List<(string Id, string Name)> programs = new();
    int tab;
    bool winget, stopped;
    ScrollViewer? scroll;

    public NeuinstallPage(MainWindow main, int? start = null)
    {
        this.main = main;
        tab = lastTab = start ?? lastTab;
        Content = root;
        Changed += Fill;
        Fill();
        Task.Run(() => (Find(), Winget() != null)).ContinueWith(t => Dispatcher.BeginInvoke(() =>
        {
            if (!t.IsCompletedSuccessfully) return;
            (found, winget) = t.Result;
            if (folder == null && found.Count > 0) folder = found[0];
            LoadPrograms();
            Fill();
        }));
    }

    static string Target => Belastung.Folder;

    static string? Winget()
    {
        var local = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");
        if (File.Exists(local)) return local;
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
            try { var f = Path.Combine(dir.Trim(), "winget.exe"); if (dir.Length > 0 && File.Exists(f)) return f; } catch (Exception) { }
        return null;
    }

    // Sicherungen im Zielordner und auf allen Laufwerken (oberste Ebene und eine darunter, z.B. USB-Stick\PulsRig)
    static List<string> Find()
    {
        var roots = new List<string> { Target };
        string[] skip = { "Windows", "Program Files", "Program Files (x86)", "ProgramData", "Users", "$Recycle.Bin" };
        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (!drive.IsReady || drive.DriveType is not (DriveType.Fixed or DriveType.Removable)) continue;
                roots.Add(drive.RootDirectory.FullName);
                roots.AddRange(drive.RootDirectory.GetDirectories().Where(d => !d.Attributes.HasFlag(FileAttributes.ReparsePoint) && !skip.Contains(d.Name, StringComparer.OrdinalIgnoreCase)).Select(d => d.FullName));
            }
            catch (Exception) { }
        }
        var list = new List<DirectoryInfo>();
        foreach (var r in roots.Distinct(StringComparer.OrdinalIgnoreCase))
            try { if (Directory.Exists(r)) list.AddRange(new DirectoryInfo(r).GetDirectories(Neuinstallation.Prefix + "*")); } catch (Exception) { }
        return list.OrderByDescending(d => d.Name, StringComparer.Ordinal).Select(d => d.FullName).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    void LoadPrograms()
    {
        programs = new();
        picked.Clear();
        try { if (folder != null && File.Exists(Path.Combine(folder, "Programme.json"))) programs = Neuinstallation.Programs(File.ReadAllText(Path.Combine(folder, "Programme.json"))); } catch (Exception) { }
    }

    static void Run(string what, Func<string> work)
    {
        if (busy.Length > 0) return;
        busy = what;
        message = "";
        Changed?.Invoke();
        var ui = Application.Current.Dispatcher;
        Task.Run(() => { try { return work(); } catch (Exception e) { return e.Message; } })
            .ContinueWith(t => ui.BeginInvoke(() => { busy = ""; message = t.Result; Changed?.Invoke(); }));
    }

    static (int Code, string Output) Tool(string file, string arguments)
    {
        using var p = Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })!;
        p.StandardError.ReadToEndAsync();
        var output = p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        return (p.ExitCode, output);
    }

    // wie Mode Save: Ordner mit Offline-Paket, Programme.json und LIESMICH.txt
    void Save()
    {
        if (!Bestaetigung.Ask(this, "Neuinstallation vorbereiten", "PulsRig legt einen Ordner „Neuinstallation_…“ mit allen Treibern und der Programmliste an.\n\nZiel: " + Target + "\nAm System ändert sich nichts.", "Sichern")) return;
        Run("save", () =>
        {
            var now = DateTime.Now;
            var dir = Path.Combine(Target, Neuinstallation.FolderName(now));
            Directory.CreateDirectory(dir);
            var drivers = Werkzeugpruefung.OfflinePackage(dir);
            var list = "winget fehlt – keine Programmliste";
            if (Winget() is { } w)
            {
                var file = Path.Combine(dir, "Programme.json");
                // nur die Quelle "winget": der Microsoft Store verlangt eine eigene Zustimmung und Anmeldung
                var code = Tool(w, "export -o \"" + file + "\" -s winget --accept-source-agreements --disable-interactivity").Code;
                list = File.Exists(file) ? Neuinstallation.Programs(File.ReadAllText(file)).Count + " Programme in der Liste" : "Programmliste fehlgeschlagen (winget-Code " + code + ")";
            }
            File.WriteAllLines(Path.Combine(dir, "LIESMICH.txt"), Neuinstallation.Readme(now), System.Text.Encoding.UTF8);
            folder = dir;
            return "Fertig · " + drivers.Split(" · ")[0] + " · " + list + " · " + dir;
        });
    }

    // wie Mode Drivers: Treiber aus dem neuesten Offline-Paket im Ordner einspielen
    void Drivers()
    {
        var package = folder == null ? null : new DirectoryInfo(folder).GetDirectories("Offline-Paket_*").OrderByDescending(d => d.Name, StringComparer.Ordinal).FirstOrDefault();
        var drivers = package == null ? null : Path.Combine(package.FullName, "Treiber");
        if (drivers == null || !Directory.Exists(drivers)) { message = "In diesem Ordner steckt kein Offline-Treiberpaket."; Fill(); return; }
        var count = Directory.GetFiles(drivers, "*.inf", SearchOption.AllDirectories).Length;
        if (!Bestaetigung.Ask(this, "Treiber einspielen", count + " Treiberpakete aus " + package!.Name + " jetzt einspielen?\n\nDanach den PC neu starten.", "Einspielen")) return;
        Run("drivers", () =>
        {
            var code = Tool(Path.Combine(Environment.SystemDirectory, "pnputil.exe"), "/add-driver \"" + Path.Combine(drivers, "*.inf") + "\" /subdirs /install").Code;
            // 3010: fertig, Neustart nötig; 259: nichts Neues für die vorhandenen Geräte
            return code is 0 or 259 or 3010 ? "Treiber eingespielt. Bitte den PC danach neu starten." : "pnputil meldet Code " + code + " - einzelne Treiber passten evtl. nicht zu den Geräten.";
        });
    }

    // wie Mode Programs: die abgehakten Programme nacheinander mit winget
    void Install()
    {
        var ids = programs.Where(p => picked.Contains(p.Id)).ToList();
        if (ids.Count == 0) return;
        var names = string.Join("\n", ids.Take(3).Select(p => "• " + p.Name)) + (ids.Count > 3 ? "\n• und " + (ids.Count - 3) + " weitere" : "");
        if (!Bestaetigung.Ask(this, "Programme installieren", (ids.Count == 1 ? "Ein Programm wird mit winget installiert." : ids.Count + " Programme werden nacheinander mit winget installiert.") + "\n\n" + names + "\nFragt ein Installer nach Adminrechten, dort selbst bestätigen.", "Installieren")) return;
        Run("programs", () =>
        {
            var w = Winget() ?? throw new InvalidOperationException("winget fehlt auf diesem PC. Den „App-Installer“ aus dem Microsoft Store installieren und es noch einmal versuchen.");
            var done = 0;
            foreach (var (id, _) in ids)
            {
                Application.Current.Dispatcher.Invoke(() => { installed[id] = "läuft …"; Changed?.Invoke(); });
                var r = Neuinstallation.WingetResult(Tool(w, "install --id " + id + " -e -s winget --accept-package-agreements --accept-source-agreements --disable-interactivity").Code);
                if (r.Ok) done++;
                Application.Current.Dispatcher.Invoke(() => { installed[id] = r.Text; Changed?.Invoke(); });
            }
            return done + " von " + ids.Count + " Programmen sind da." + (done < ids.Count ? " Die übrigen beim Hersteller laden – manche Programme lassen sich nur dort installieren." : "");
        });
    }

    static List<DriveInfo> Sticks()
    {
        var list = new List<DriveInfo>();
        foreach (var d in DriveInfo.GetDrives())
            try { if (d.DriveType == DriveType.Removable && d.IsReady) list.Add(d); } catch (Exception) { }
        return list;
    }

    static string Gb(long bytes) => (bytes / (double)(1L << 30)).ToString("N1", Ui.De) + " GB";

    // wie Mode Stick: PulsRig ohne Installation auf den Stick, daneben das Offline-Paket in Treiber\
    void Stick(string drive)
    {
        var source = Altdaten.ProgramRoot;
        var target = Path.Combine(drive, "PulsRig");
        if (!Bestaetigung.Ask(this, "Notfall-Stick einrichten", "PulsRig kopiert sich auf den Stick und legt daneben ein Offline-Paket mit den Treibern dieses PCs an.\n\nZiel: " + target + "\nAndere Dateien auf dem Stick bleiben unberührt.", "Einrichten")) return;
        Run("stick", () =>
        {
            void Copy(DirectoryInfo from, string to)
            {
                Directory.CreateDirectory(to);
                foreach (var f in from.GetFiles()) f.CopyTo(Path.Combine(to, f.Name), true);
                foreach (var d in from.GetDirectories()) if (!d.Attributes.HasFlag(FileAttributes.ReparsePoint)) Copy(d, Path.Combine(to, d.Name));
            }
            var dir = new DirectoryInfo(source!);
            var copied = 0;
            Directory.CreateDirectory(Path.Combine(target, "Treiber"));
            foreach (var f in dir.GetFiles().Where(f => Notfallstick.Copies(f.Name, false))) { f.CopyTo(Path.Combine(target, f.Name), true); copied++; }
            foreach (var d in dir.GetDirectories().Where(d => Notfallstick.Copies(d.Name, true))) { Copy(d, Path.Combine(target, d.Name)); copied++; }
            var need = Werkzeugpruefung.OfflineSize();
            var free = new DriveInfo(drive).AvailableFreeSpace;
            var drivers = need > free
                ? "Zu wenig Platz für die Treiber – es fehlen etwa " + Gb(need - free) + ". Einen größeren Stick nehmen oder dort Platz schaffen."
                : Werkzeugpruefung.OfflinePackage(Path.Combine(target, "Treiber")).Split(" · ")[0];
            File.WriteAllLines(Path.Combine(target, Notfallstick.ReadmeName), Notfallstick.Readme(DateTime.Now, Environment.MachineName), System.Text.Encoding.UTF8);
            return (need > free ? "PulsRig ist auf dem Stick, das Treiberpaket fehlt aber. " : "Fertig · ") + drivers + " · " + target;
        });
    }

    void PickFolder()
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "Ordner der Sicherung wählen (Neuinstallation_…)" };
        if (folder != null) dialog.InitialDirectory = folder;
        if (dialog.ShowDialog() != true) return;
        folder = dialog.FolderName;
        LoadPrograms();
        Fill();
    }

    static void Open(string path) { try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + path + "\"") { UseShellExecute = true }); } catch (Exception) { } }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.ColumnDefinitions.Clear();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });

        // links: Schritt wählen und Hauptknopf
        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "Neuinstallation", FontSize = 26, FontWeight = FontWeights.SemiBold });
        left.Children.Add(new TextBlock { Text = "Vorher Treiber und Programmliste sichern, danach geführt einspielen", FontSize = 13, Foreground = Ui.Res("Leise"),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        foreach (var (i, label) in new[] { (0, "Vorher sichern"), (1, "Danach einspielen"), (2, "Notfall-Stick") })
        {
            var b = Big(label, i == tab);
            b.Click += (_, _) => { tab = lastTab = i; scroll = null; Fill(); };
            left.Children.Add(b);
        }
        var selected = programs.Count(p => picked.Contains(p.Id));
        Button? primary = null;
        if (tab == 0)
        {
            primary = Big(busy == "save" ? "Sichert …" : "Sicherung erstellen", true);
            primary.IsEnabled = busy.Length == 0 && App.IsAdmin;
            primary.Click += (_, _) => Save();
        }
        else if (tab == 2)
        {
            primary = Big("Neu suchen", false);
            primary.IsEnabled = busy.Length == 0;
            primary.Click += (_, _) => Fill();
        }
        else if (programs.Count > 0)
        {
            primary = Big(busy == "programs" ? "Installiert …" : selected > 0 ? selected + " installieren" : "Programme abhaken", true);
            primary.IsEnabled = busy.Length == 0 && selected > 0;
            primary.Click += (_, _) => Install();
        }
        if (primary != null)
        {
            primary.Margin = new Thickness(0, 18, 0, 0);
            primary.Opacity = primary.IsEnabled ? 1 : 0.5;
            left.Children.Add(primary);
        }
        var hint = message.Length > 0 ? message
            : tab == 0 ? App.IsAdmin ? "Den fertigen Ordner vor der Neuinstallation auf einen USB-Stick kopieren." : "Treiber exportieren geht nur mit Adminrechten: PulsRig als Administrator starten."
            : tab == 2 ? Altdaten.ProgramRoot == null ? "Den Notfall-Stick richtet nur das installierte PulsRig ein."
                : !App.IsAdmin ? "Treiber exportieren geht nur mit Adminrechten: PulsRig als Administrator starten."
                : "Dateien auf dem Stick bleiben, PulsRig legt nur den Ordner „PulsRig“ an."
            : "Der Reihe nach: Treiber, Spielkomponenten, dann die Programme abhaken.";
        left.Children.Add(new TextBlock { Text = hint, FontSize = 12, Foreground = Ui.Res(message.Length > 0 ? "Text" : "Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        var list = new StackPanel();
        if (tab == 0)
        {
            list.Children.Add(Head("KOMMT IN DIE SICHERUNG"));
            list.Children.Add(Row("Treiber", "Offline-Paket aller Treiber von Drittherstellern, auch ohne Internet einspielbar", ("dabei", "good")));
            list.Children.Add(Row("Programmliste", "Programme, die winget kennt – danach zum Abhaken und Installieren", winget ? ("dabei", "good") : ("winget fehlt", "warn")));
            list.Children.Add(Head("SELBST SICHERN"));
            list.Children.Add(Row("Eigene Dateien und Spielstände", "Dokumente, Bilder, Browser-Daten und Spielstände ohne Cloud – die sichert PulsRig nicht", ("nicht dabei", "warn")));
            if (found.Count > 0)
            {
                list.Children.Add(Head("LETZTE SICHERUNG"));
                var last = found[0];
                list.Children.Add(Row(Path.GetFileName(last), last, null, "Ordner öffnen", () => Open(last)));
            }
        }
        else if (tab == 2)
        {
            list.Children.Add(Head("USB-STICKS"));
            var sticks = Sticks();
            var can = busy.Length == 0 && App.IsAdmin && Altdaten.ProgramRoot != null;
            foreach (var s in sticks)
            {
                var target = Path.Combine(s.RootDirectory.FullName, "PulsRig");
                var done = File.Exists(Path.Combine(target, Notfallstick.ReadmeName));
                var small = s.AvailableFreeSpace < Notfallstick.Small;
                var drive = s.RootDirectory.FullName;
                list.Children.Add(Row(Notfallstick.Label(s.Name, s.VolumeLabel), (s.AvailableFreeSpace / (double)(1L << 30)).ToString("N1", Ui.De) + " von " + Gb(s.TotalSize) + " frei",
                    busy == "stick" ? ("läuft …", "accent") : done ? ("eingerichtet", "good") : small ? ("wenig Platz", "warn") : null,
                    done ? "Erneuern" : "Einrichten", can ? () => Stick(drive) : null));
                if (done) list.Children.Add(Row("PulsRig auf dem Stick", target, null, "Ordner öffnen", () => Open(target)));
            }
            if (sticks.Count == 0) list.Children.Add(Row("Kein USB-Stick gefunden", "Stick einstecken und „Neu suchen“ wählen.", ("", "warn")));
            list.Children.Add(Head("KOMMT AUF DEN STICK"));
            list.Children.Add(Row("PulsRig ohne Installation", "Startet auf jedem Windows-PC direkt vom Stick", ("dabei", "good")));
            list.Children.Add(Row("Treiber dieses PCs", "Offline-Paket – rettet den Netzwerktreiber, wenn nach einer Neuinstallation das Internet fehlt", ("dabei", "good")));
        }
        else if (folder == null)
            list.Children.Add(Row("Keine Sicherung gefunden", "Weder im Zielordner noch auf den Laufwerken liegt ein Ordner „Neuinstallation_…“. USB-Stick einstecken oder den Ordner selbst wählen.", ("", "warn"), "Ordner wählen", PickFolder));
        else
        {
            list.Children.Add(Row(Path.GetFileName(folder), folder, null, "Anderer Ordner", PickFolder));
            list.Children.Add(Head("1 · TREIBER"));
            list.Children.Add(Row("Treiber einspielen", App.IsAdmin ? "Alle Treiber aus dem Offline-Paket, danach neu starten" : "Alle Treiber aus dem Offline-Paket – geht nur mit Adminrechten", busy == "drivers" ? ("läuft …", "accent") : null,
                "Jetzt einspielen", App.IsAdmin && busy.Length == 0 ? Drivers : null));
            list.Children.Add(Head("2 · SPIELKOMPONENTEN"));
            list.Children.Add(Row("Spielkomponenten", "Visual C++, DirectX und XNA prüfen und nachinstallieren", null, "Prüfen", () => main.Go("drivers")));
            list.Children.Add(Head(programs.Count > 0 ? "3 · PROGRAMME (" + programs.Count + ")" : "3 · PROGRAMME"));
            if (programs.Count == 0) list.Children.Add(Row("Keine Programmliste", "In dieser Sicherung fehlt Programme.json", null));
            else
            {
                var all = programs.All(p => picked.Contains(p.Id));
                list.Children.Add(Row(all ? "Keine auswählen" : "Alle auswählen", "", null, all ? "Keine" : "Alle", busy.Length > 0 ? null : () =>
                {
                    if (all) picked.Clear(); else foreach (var p in programs) picked.Add(p.Id);
                    Fill();
                }));
                foreach (var (id, name) in programs) list.Children.Add(Check(id, name));
            }
        }
        // beim Abhaken nicht nach oben springen
        var offset = scroll?.VerticalOffset ?? 0;
        scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        if (offset > 0) { var s = scroll; s.Loaded += (_, _) => s.ScrollToVerticalOffset(offset); }
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    UIElement Check(string id, string name)
    {
        var box = new CheckBox { IsChecked = picked.Contains(id), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0), IsEnabled = busy.Length == 0 };
        box.Checked += (_, _) => { picked.Add(id); Fill(); };
        box.Unchecked += (_, _) => { picked.Remove(id); Fill(); };
        var grid = new Grid { MinHeight = 48 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(box);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 6, 12, 6) };
        text.Children.Add(Ui.Text(name, 13.5, "Text", bold: true));
        text.Children.Add(Ui.Text(id, 11.5, "Leise"));
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (installed.TryGetValue(id, out var state))
        {
            var color = state.StartsWith("fehl") ? Beere : state.StartsWith("läuft") ? Bernstein : Gruen;
            var pill = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Center, Child = Ui.Text(state, 11, color) };
            Grid.SetColumn(pill, 2);
            grid.Children.Add(pill);
        }
        var row = new Border { CornerRadius = new CornerRadius(14), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 6), Child = grid, Cursor = System.Windows.Input.Cursors.Hand };
        row.MouseLeftButtonUp += (_, e) => { if (busy.Length == 0 && e.OriginalSource is not CheckBox) box.IsChecked = !box.IsChecked; };
        return row;
    }

    internal static Button Big(string label, bool on) => new()
    {
        Style = (Style)Application.Current.FindResource("Flach"), Height = 42, Tag = "14", Margin = new Thickness(0, 0, 0, 8), Padding = new Thickness(16, 0, 16, 0),
        Background = on ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(on ? 0 : 1),
        HorizontalContentAlignment = HorizontalAlignment.Left, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 13.5, "Text", bold: true),
    };

    internal static TextBlock Head(string text) => new() { Text = text, FontSize = 10.5, FontFamily = (FontFamily)Application.Current.FindResource("Mono"), Foreground = Ui.Res("Leise"), Margin = new Thickness(2, 6, 0, 8) };

    internal static Border Row(string title, string sub, (string Text, string Tone)? state, string action = "", Action? run = null)
    {
        var color = state?.Tone switch { "good" => Gruen, "warn" => Bernstein, "bad" => Beere, _ => Lila };
        var grid = new Grid { MinHeight = 60 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border { Width = 4, Height = 30, CornerRadius = new CornerRadius(2), Background = Ui.Brush(state == null ? "#22172F" : color), Margin = new Thickness(0, 0, 16, 0) });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(title, 14.5, "Text", bold: true));
        if (sub.Length > 0)
        {
            var s = Ui.Text(sub, 12.5, "Leise");
            s.TextWrapping = TextWrapping.Wrap;
            s.Margin = new Thickness(0, 3, 0, 0);
            text.Children.Add(s);
        }
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (state is { Text.Length: > 0 } st)
        {
            var pill = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(color, "1A"), VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 12, 0), Child = Ui.Text(st.Text, 11, color) };
            Grid.SetColumn(pill, 2);
            grid.Children.Add(pill);
        }
        if (action.Length > 0)
        {
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 34, MinWidth = 96, Padding = new Thickness(14, 0, 14, 0), Tag = "17", VerticalAlignment = VerticalAlignment.Center,
                Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), HorizontalContentAlignment = HorizontalAlignment.Center,
                Content = Ui.Text(action, 12.5, "Text", bold: true), IsEnabled = run != null, Opacity = run != null ? 1 : 0.5 };
            if (run != null) b.Click += (_, _) => run();
            Grid.SetColumn(b, 3);
            grid.Children.Add(b);
        }
        return new Border { CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
            Padding = new Thickness(16, 0, 16, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid };
    }

    public void Stop()
    {
        stopped = true;
        Changed -= Fill;
    }
}
