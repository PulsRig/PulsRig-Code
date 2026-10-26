using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Threading;
using PulsRig.Core;

namespace PulsRig.App;

// Englisch wie im PowerShell-Programm: der Quelltext bleibt deutsch, übersetzt wird, was ins Fenster kommt. Statt
// jede Stelle anzufassen, sucht die App nach jedem Neuaufbau des Fensters (höchstens alle 150 ms) die neuen
// TextBlocks, übersetzt sie und übersetzt sie wieder, wenn sich ihr Text ändert. Die Wörter kommen aus
// PulsRig-Englisch.ps1, das im Programm steckt.
static class Texte
{
    public static Sprache? English { get; private set; }
    public static bool IsEnglish => English != null;

    static readonly DependencyPropertyDescriptor TextChanged = DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty, typeof(TextBlock));
    static readonly ConditionalWeakTable<TextBlock, object> Seen = new();
    static bool busy, pending;

    public static void Start()
    {
        var env = Environment.GetEnvironmentVariable("PULSRIG_SPRACHE");
        var language = env is "de" or "en" ? env : Altdaten.Text(Altdaten.Settings(), "Language", "de");
        if (language != "en") return;
        try
        {
            using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Englisch.ps1"))?.Stream;
            if (stream != null) English = Sprache.Load(new StreamReader(stream).ReadToEnd());
        }
        catch (Exception) { }
    }

    public static string T(string text) => English?.T(text) ?? text;

    // für jedes Fenster (Hauptfenster, Rückfragen) einmal aufrufen
    public static void Attach(Window window)
    {
        if (English == null) return;
        window.LayoutUpdated += (_, _) =>
        {
            if (pending) return;
            pending = true;
            var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(150) };
            timer.Tick += (_, _) => { timer.Stop(); pending = false; Walk(window); };
            timer.Start();
        };
    }

    static void Walk(DependencyObject node)
    {
        if (node is TextBlock block && !Seen.TryGetValue(block, out _))
        {
            Seen.Add(block, new object());
            Translate(block);
            TextChanged.AddValueChanged(block, Changed);
        }
        if (node is not (Visual or System.Windows.Media.Media3D.Visual3D)) return;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++) Walk(VisualTreeHelper.GetChild(node, i));
    }

    static void Changed(object? sender, EventArgs e) { if (sender is TextBlock b) Translate(b); }

    static void Translate(TextBlock block)
    {
        if (busy || English == null) return;
        busy = true;
        try
        {
            // mit mehreren Runs (Hervorhebungen) jeden Teil einzeln, sonst den ganzen Text
            var runs = block.Inlines.OfType<Run>().ToList();
            if (runs.Count > 1 && runs.Count == block.Inlines.Count) foreach (var run in runs) { var t = English.T(run.Text); if (t != run.Text) run.Text = t; }
            else if (block.Text is { Length: > 0 } text) { var t = English.T(text); if (t != text) block.Text = t; }
        }
        finally { busy = false; }
    }

    // was nicht übersetzt wurde, für die Wortliste (wie Unuebersetzt.txt im Probelauf)
    public static void SaveUntranslated()
    {
        if (English == null || English.Untranslated.Count == 0) return;
        try
        {
            Directory.CreateDirectory(Belastung.Folder);
            // mit dem, was frühere Läufe gesammelt haben, und ohne das, was inzwischen übersetzt ist
            var file = Path.Combine(Belastung.Folder, "Unuebersetzt.txt");
            var all = new HashSet<string>(English.Untranslated, StringComparer.Ordinal);
            if (File.Exists(file)) foreach (var line in File.ReadAllLines(file)) if (line.Length > 0 && English.T(line) == line) all.Add(line);
            File.WriteAllLines(file, all.OrderBy(x => x, StringComparer.Ordinal));
        }
        catch (Exception) { }
    }
}

// Bewegung wie Update-Motion: Aus, Ruhig, Normal, Lebendig (Einstellungen Motion und Animations).
// Speed verkürzt oder verlängert Übergänge; aus heißt: ohne Übergänge
static class Bewegung
{
    public static string Level { get; private set; } = "Normal";
    public static bool Off => Level == "Aus";
    public static double Speed => Level switch { "Ruhig" => 0.6, "Lebendig" => 1.45, _ => 1.0 };

    public static void Start()
    {
        var settings = Altdaten.Settings();
        var motion = Altdaten.Text(settings, "Motion", "Normal");
        Level = !Altdaten.Flag(settings, "Animations", true) ? "Aus" : motion is "Ruhig" or "Lebendig" ? motion : "Normal";
    }

    public static TimeSpan Time(double ms) => Off ? TimeSpan.Zero : TimeSpan.FromMilliseconds(ms / Speed);

    public static void Set(string level)
    {
        Level = level;
        Altdaten.Change(s =>
        {
            s["Animations"] = level != "Aus";
            if (level != "Aus") s["Motion"] = level;
        });
    }
}
