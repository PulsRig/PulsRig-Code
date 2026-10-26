using System.Diagnostics;
using System.IO;
using System.Management;
using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// Einen einzelnen Treiber sichern wie "Diesen Treiber sichern" in der Treiberliste des PowerShell-Programms
// (PulsRig-Arbeit-Export.ps1): das Paket oemNN.inf eines Geräts per pnputil in einen Ordner "Einzeltreiber_…".
// Nur Pakete von Drittherstellern; am installierten Treiber ändert sich nichts. Exportieren geht nur mit Adminrechten.
sealed class EinzeltreiberPage : UserControl, IPage
{
    const string Lila = "#8C6BD6";

    sealed record Paket(string Inf, string Names, string Version, string Provider);

    // Ergebnisse bleiben beim Seitenwechsel stehen
    static readonly Dictionary<string, (bool Ok, string Text)> done = new(StringComparer.OrdinalIgnoreCase);
    static string busy = "";
    static event Action? Changed;

    readonly Grid root = new();
    List<Paket>? packages;
    bool stopped;

    public EinzeltreiberPage(bool demo)
    {
        Content = root;
        Changed += Fill;
        Fill();
        if (demo)
        {
            packages = new()
            {
                new("oem42.inf", "NVIDIA GeForce RTX 3080", "32.0.15.8157", "NVIDIA"),
                new("oem7.inf", "Realtek Gaming 2.5GbE Family Controller", "10.68.1001.2023", "Realtek"),
                new("oem19.inf", "Realtek High Definition Audio · NVIDIA High Definition Audio", "6.0.9600.1", "Realtek Semiconductor Corp."),
            };
            Fill();
            return;
        }
        Task.Run(Read).ContinueWith(t => Dispatcher.BeginInvoke(() => { packages = t.IsCompletedSuccessfully ? t.Result : new(); Fill(); }));
    }

    static string Target => Werkzeuglauf.Backups;

    // die Pakete von Drittherstellern mit den Geräten, die sie nutzen
    static List<Paket> Read()
    {
        var map = new Dictionary<string, List<(string Name, string Version, string Provider)>>(StringComparer.OrdinalIgnoreCase);
        using var searcher = new ManagementObjectSearcher("SELECT DeviceName, DriverVersion, DriverProviderName, InfName FROM Win32_PnPSignedDriver");
        foreach (ManagementObject o in searcher.Get())
        {
            var inf = (o["InfName"]?.ToString() ?? "").Trim();
            var name = (o["DeviceName"]?.ToString() ?? "").Trim();
            if (name.Length == 0 || Sicherung.PackagesToBackup(new[] { inf }).Length == 0) continue;
            if (!map.TryGetValue(inf, out var list)) map[inf] = list = new();
            list.Add((name, (o["DriverVersion"]?.ToString() ?? "").Trim(), (o["DriverProviderName"]?.ToString() ?? "").Trim()));
        }
        return map.Select(p => new Paket(p.Key.ToLowerInvariant(), string.Join(" · ", p.Value.Select(d => d.Name).Distinct().Take(3)) + (p.Value.Select(d => d.Name).Distinct().Count() > 3 ? " …" : ""),
                p.Value[0].Version, p.Value[0].Provider))
            .OrderBy(p => p.Provider, StringComparer.OrdinalIgnoreCase).ThenBy(p => p.Names, StringComparer.OrdinalIgnoreCase).ToList();
    }

    void Save(Paket p)
    {
        var target = Path.Combine(Target, Sicherung.SingleFolderName(p.Inf, DateTime.Now));
        if (!Bestaetigung.Ask(this, "Treiber sichern", p.Names + "\n\nDas Treiberpaket " + p.Inf + (p.Version.Length > 0 ? " (Version " + p.Version + ")" : "") + " wird in einen eigenen Ordner kopiert.\n\nZiel: " + target + "\nAm installierten Treiber ändert sich nichts.", "Sichern")) return;
        busy = p.Inf;
        Changed?.Invoke();
        Task.Run(() =>
        {
            Directory.CreateDirectory(target);
            var code = Treiberinstallation.RunTool("pnputil.exe", "/export-driver " + p.Inf + " \"" + target + "\"").Code;
            return code == 0 ? (true, target) : (false, "Die Sicherung ist fehlgeschlagen (pnputil-Code " + code + ").");
        }).ContinueWith(t => Application.Current.Dispatcher.BeginInvoke(() =>
        {
            busy = "";
            done[p.Inf] = t.IsCompletedSuccessfully ? t.Result : (false, "Die Sicherung ist fehlgeschlagen: " + t.Exception?.InnerException?.Message);
            Changed?.Invoke();
        }));
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

        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = "Einzelnen Treiber sichern", FontSize = 26, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        left.Children.Add(new TextBlock { Text = "Das Treiberpaket eines Geräts in einen eigenen Ordner kopieren", FontSize = 13, Foreground = Ui.Res("Leise"),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 18), LineHeight = 19.5 });
        var folder = NeuinstallPage.Big("Zielordner öffnen", false);
        folder.Click += (_, _) => { Directory.CreateDirectory(Target); Open(Target); };
        left.Children.Add(folder);
        var hint = !App.IsAdmin ? "Treiber exportieren geht nur mit Adminrechten: PulsRig als Administrator starten."
            : "Zurückspielen bei Bedarf: den Ordner unter „Treiber zurückholen“ wählen.";
        left.Children.Add(new TextBlock { Text = hint, FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        left.Children.Add(new TextBlock { Text = "Ziel: " + Target, FontSize = 12, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0), LineHeight = 17 });
        root.Children.Add(new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(Lila, "2E"), Padding = new Thickness(24), Background = Ui.Tint("#160D29"), Child = left });

        var list = new StackPanel();
        if (packages == null) list.Children.Add(NeuinstallPage.Row("Lese die Treiber …", "", null));
        else if (packages.Count == 0) list.Children.Add(NeuinstallPage.Row("Keine Treiber von Drittherstellern", "Alle Treiber auf diesem PC kommen von Microsoft und stecken in Windows selbst.", ("", "good")));
        else
        {
            list.Children.Add(NeuinstallPage.Head("TREIBER VON DRITTHERSTELLERN (" + packages.Count + ")"));
            var can = busy.Length == 0 && App.IsAdmin;
            foreach (var p in packages)
            {
                var sub = string.Join(" · ", new[] { p.Provider, p.Version.Length > 0 ? "Version " + p.Version : "", p.Inf }.Where(s => s.Length > 0));
                if (busy == p.Inf) list.Children.Add(NeuinstallPage.Row(p.Names, sub, ("läuft …", "accent")));
                else if (done.TryGetValue(p.Inf, out var r))
                {
                    list.Children.Add(r.Ok ? NeuinstallPage.Row(p.Names, r.Text, ("gesichert", "good"), "Ordner öffnen", () => Open(r.Text))
                        : NeuinstallPage.Row(p.Names, r.Text, ("fehlgeschlagen", "bad"), "Nochmal", can ? () => Save(p) : null));
                }
                else list.Children.Add(NeuinstallPage.Row(p.Names, sub, null, "Sichern", can ? () => Save(p) : null));
            }
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
    }

    public void Stop()
    {
        stopped = true;
        Changed -= Fill;
    }
}
