using System.Security.Principal;
using System.Windows;

namespace PulsRig.App;

public partial class App : Application
{
    // dasselbe Kennzeichen wie PulsRig.ps1: Setup und Deinstallation bitten dann, PulsRig zu schließen
    static Mutex? running;

    // vor einem Update: sonst bittet das Setup darum, PulsRig zu schließen
    public static void ReleaseMark() { try { running?.Dispose(); running = null; } catch (Exception) { } }

    public static bool IsAdmin { get; } = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);

    protected override void OnExit(ExitEventArgs e)
    {
        Texte.SaveUntranslated();
        base.OnExit(e);
    }

    // -Demo wie beim PowerShell-Programm: Beispielwerte aus dem Entwurf statt echter Messungen
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Arbeit ohne Fenster für den Helfer, vor allem anderen (auch ohne das Kennzeichen, das Setups warten lässt)
        if (Hintergrund.Run(e.Args) is { } code) { Shutdown(code); return; }
        // Sora und JetBrains Mono liegen im Programm (Schriften\, OFL); fehlen sie, greifen die Ersatzschriften
        var fonts = new Uri("pack://application:,,,/");
        Resources["Sans"] = new System.Windows.Media.FontFamily(fonts, "./Schriften/#Sora, Segoe UI Variable Text, Segoe UI");
        Resources["Mono"] = new System.Windows.Media.FontFamily(fonts, "./Schriften/#JetBrains Mono, Cascadia Mono, Consolas");
        try { running = new Mutex(false, "PulsRig-8B6C1F0E-Laeuft"); } catch (Exception) { }
        Bewegung.Start();
        Texte.Start();
        var demo = e.Args.Any(a => a.Equals("-Demo", StringComparison.OrdinalIgnoreCase) || a.Equals("--demo", StringComparison.OrdinalIgnoreCase));
        // -Pruefen <Datei>: alle Werkzeuge nur prüfen lassen (ohne Schritte) und das Ergebnis in die Datei schreiben
        var check = Array.FindIndex(e.Args, a => a.Equals("-Pruefen", StringComparison.OrdinalIgnoreCase));
        if (check >= 0 && check + 1 < e.Args.Length)
        {
            var text = new System.Text.StringBuilder();
            foreach (var tool in new[] { "FixAudio", "FixDevices", "CleanDevices", "FixNetwork", "FixResolution", "IncompatibleDrivers", "CleanDisk", "OfflinePackage", "SystemInfo", "Standby", "Autostart", "DriverHistory", "GamingCheck", "Games" })
            {
                text.AppendLine("== " + tool);
                try
                {
                    var r = Werkzeugpruefung.Check(tool)!;
                    foreach (var l in r.Lines) text.AppendLine((l.Ok ? "  ok  " : "  !!  ") + l.Label + (l.Detail.Length > 0 ? " · " + l.Detail : ""));
                    if (r.Summary.Length > 0) text.AppendLine("  " + r.Summary);
                    foreach (var s in r.Steps) text.AppendLine((s.Optional ? "  (optional) " : "  Schritt: ") + s.Text);
                }
                catch (Exception ex) { text.AppendLine("  FEHLER " + ex); }
            }
            System.IO.File.WriteAllText(e.Args[check + 1], text.ToString());
            Shutdown();
            return;
        }
        var at = Array.FindIndex(e.Args, a => a.Equals("-Seite", StringComparison.OrdinalIgnoreCase));
        MainWindow = new MainWindow(demo, at >= 0 && at + 1 < e.Args.Length ? e.Args[at + 1] : "");
        MainWindow.Show();
        // wie das PowerShell-Programm beim Start: ist der Helfer eingeschaltet, aber nicht da, ihn starten - sonst
        // zeigt Optionen ihn als an, obwohl er nicht läuft
        if (!demo) Task.Run(() => { try { Helfer.Start(); } catch (Exception) { } });
    }
}
