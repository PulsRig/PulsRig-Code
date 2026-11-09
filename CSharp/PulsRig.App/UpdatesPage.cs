using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// Programm-Updates: "winget upgrade" listet veraltete Programme (Core.Programmupdates), aktualisiert wird nur auf Klick –
// einzeln oder alle nach Rückfrage. Nur die Quelle "winget"; Programme aus dem Store aktualisiert der Store selbst.
// Läuft weiter, wenn man die Seite verlässt.
sealed class UpdatesPage : UserControl, IPage
{
    static string busy = "", message = "";
    static List<Programmupdate>? found;
    static readonly Dictionary<string, (bool Ok, string Text)> results = new(StringComparer.OrdinalIgnoreCase);
    static event Action? Changed;

    readonly Grid root = new();
    bool stopped;

    public UpdatesPage()
    {
        Content = root;
        Changed += Fill;
        Fill();
        if (found == null && busy.Length == 0) Search();
    }

    static string? Winget()
    {
        var local = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");
        if (File.Exists(local)) return local;
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
            try { var f = Path.Combine(dir.Trim(), "winget.exe"); if (dir.Length > 0 && File.Exists(f)) return f; } catch (Exception) { }
        return null;
    }

    static (int Code, string Output) Tool(string file, string arguments)
    {
        using var p = Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8 })!;
        p.StandardError.ReadToEndAsync();
        var output = p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        return (p.ExitCode, output);
    }

    const string Missing = "winget fehlt auf diesem PC. Den „App-Installer“ aus dem Microsoft Store installieren und es noch einmal versuchen.";

    static void Run(string what, Func<string> work)
    {
        if (busy.Length > 0) return;
        busy = what;
        message = "";
        Changed?.Invoke();
        var ui = Application.Current.Dispatcher;
        Task.Run(() => { try { return work(); } catch (Exception e) { return Fehlermeldung.Text(e); } })
            .ContinueWith(t => ui.BeginInvoke(() => { busy = ""; message = t.Result; Changed?.Invoke(); }));
    }

    static void Search() => Run("search", () =>
    {
        var w = Winget() ?? throw new InvalidOperationException(Missing);
        var list = Programmupdates.Parse(Tool(w, "upgrade -s winget --accept-source-agreements --disable-interactivity").Output);
        Application.Current.Dispatcher.Invoke(() => { found = list; results.Clear(); });
        return "";
    });

    void Upgrade(List<Programmupdate> items)
    {
        if (items.Count == 0) return;
        var names = string.Join("\n", items.Take(3).Select(u => "• " + u.Name + "  " + u.Version + " → " + u.Available)) + (items.Count > 3 ? "\n• und " + (items.Count - 3) + " weitere" : "");
        if (!Bestaetigung.Ask(this, "Programme aktualisieren", (items.Count == 1 ? "Ein Programm wird mit winget aktualisiert." : items.Count + " Programme werden nacheinander mit winget aktualisiert.")
            + "\n\n" + names + "\n\nLaufende Programme vorher schließen. Fragt ein Installer nach Adminrechten, dort selbst bestätigen.", "Aktualisieren")) return;
        Run("upgrade", () =>
        {
            var w = Winget() ?? throw new InvalidOperationException(Missing);
            var done = 0;
            foreach (var u in items)
            {
                Application.Current.Dispatcher.Invoke(() => { results[u.Id] = (true, "läuft …"); Changed?.Invoke(); });
                var r = Programmupdates.Result(Tool(w, "upgrade --id " + u.Id + " -e -s winget --accept-package-agreements --accept-source-agreements --disable-interactivity").Code);
                if (r.Ok) done++;
                Application.Current.Dispatcher.Invoke(() => { results[u.Id] = r; Changed?.Invoke(); });
            }
            // nicht zurücknehmbar, aber im Protokoll sichtbar
            Rueckgaengiglauf.Record("Programm-Updates", done == 1 && items.Count == 1 ? items[0].Name + " aktualisiert" : done + " von " + items.Count + " Programmen aktualisiert");
            return done + " von " + items.Count + " Programmen sind aktuell.";
        });
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        var list = new StackPanel();
        var idle = busy.Length == 0;
        var open = found?.Where(u => Programmupdates.IsSafeId(u.Id) && !(results.TryGetValue(u.Id, out var r) && r.Ok)).ToList() ?? new();

        var state = busy == "search" ? ("sucht …", "accent") : found == null ? ("", "") : found.Count == 0 ? ("alles aktuell", "good") : (found.Count + (found.Count == 1 ? " Update" : " Updates"), "warn");
        list.Children.Add(NeuinstallPage.Row("Veraltete Programme", "Was winget kennt und wofür es eine neuere Fassung gibt. PulsRig aktualisiert nur, was du anklickst.",
            state.Item1.Length > 0 ? state : null, "Neu suchen", idle ? Search : null));
        if (open.Count > 1)
            list.Children.Add(NeuinstallPage.Row("Alle aktualisieren", "Nacheinander, ohne weitere Fragen von winget", null, "Alle (" + open.Count + ")", idle ? () => Upgrade(open) : null));
        if (message.Length > 0) list.Children.Add(NeuinstallPage.Row(message, "", null));

        if (found is { Count: > 0 })
        {
            list.Children.Add(NeuinstallPage.Head("PROGRAMME"));
            foreach (var u in found)
            {
                var safe = Programmupdates.IsSafeId(u.Id);
                (string, string)? pill = results.TryGetValue(u.Id, out var r) ? (r.Text, r.Text == "läuft …" ? "accent" : r.Ok ? "good" : "bad") : (u.Available, "warn");
                list.Children.Add(NeuinstallPage.Row(u.Name, u.Id + " · " + u.Version + " → " + u.Available + (safe ? "" : " · Name von winget gekürzt, bitte im Programm selbst aktualisieren"),
                    pill, safe ? "Aktualisieren" : "", idle && safe && !(r.Ok && r.Text != "läuft …") ? () => Upgrade(new() { u }) : null));
            }
        }
        root.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) });
    }

    public void Stop()
    {
        stopped = true;
        Changed -= Fill;
    }
}
