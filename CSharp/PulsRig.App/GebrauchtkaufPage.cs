using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// Gebrauchtkauf-Check: Angaben der Anzeige eingeben, Prüfung laufen lassen, Urteil und Bericht. Die Felder sind nicht
// vorbelegt, sonst stimmte der Abgleich immer; leere Felder zählen als nicht geprüft.
sealed class GebrauchtkaufPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0";
    // Stabilitätstest und Temperatur zählen nur aus diesem Lauf: Auf dem Stick läge sonst das Ergebnis eines anderen PCs
    static readonly string[] Kept = { "Zustand der Laufwerke", "Steckplätze des Arbeitsspeichers", "Abstürze in 30 Tagen", "Gemeldete Hardwarefehler" };
    static readonly string[] Stress = { "Stabilitätstest", "Höchsttemperatur unter Last" };

    readonly StackPanel root = new();
    readonly TextBox cpu = Box(), gpu = Box(), ram = Box(), disk = Box();
    readonly Action onStress;
    string phase = "input", saved = "";
    bool stressed, stopped;
    KaufUrteil? verdict;
    List<Abgleich> compare = new();
    List<(string Name, string Text, string Kind)> rows = new();
    // Bauteile aus dem PC-Scheckheft des Verkäufers (Bericht als HTML), werden gegen den PC gehalten
    List<HeftTeil>? logbook;
    string logbookName = "";

    public GebrauchtkaufPage()
    {
        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        onStress = () => Dispatcher.BeginInvoke(() =>
        {
            if (stopped || phase != "stress") return;
            if (Belastung.Running) Fill();
            else Evaluate();
        });
        Belastung.Changed += onStress;
        Hw.LoadAll();
        Fill();
    }

    static TextBox Box() => new() { Height = 34, FontSize = 14, VerticalContentAlignment = VerticalAlignment.Center, Padding = new Thickness(8, 0, 8, 0), Margin = new Thickness(0, 4, 0, 12),
        Background = Ui.Brush("#0B0710"), Foreground = Ui.Res("Text"), CaretBrush = Ui.Res("Text"), BorderBrush = Ui.Res("KarteRand") };

    static Button Knopf(string text, RoutedEventHandler click)
    {
        var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(16, 0, 16, 0), Tag = "17", Margin = new Thickness(0, 8, 10, 0),
            Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), Content = Ui.Text(text, 13, "Text", bold: true) };
        b.Click += click;
        return b;
    }

    static string Color(string tone) => tone switch { "good" => Gruen, "warn" => Bernstein, "bad" => Beere, _ => Lila };

    void Field(string label, TextBox box)
    {
        root.Children.Add(Ui.Text(label, 12.5, "Halbleise", bold: true));
        System.Windows.Automation.AutomationProperties.SetName(box, label);
        root.Children.Add(box);
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.Children.Add(Ui.Text("GEBRAUCHTKAUF-CHECK", 10, "Leise", mono: true));
        if (phase == "input") FillInput();
        else if (phase == "stress") FillStress();
        else if (phase == "wait") root.Children.Add(Line("Werte die Prüfung aus …", ""));
        else FillDone();
    }

    void FillInput()
    {
        root.Children.Add(Line("Was steht in der Anzeige?", "Trag ein, was der Verkäufer verspricht. Leere Felder werden nicht geprüft."));
        if (saved.Length > 0) root.Children.Add(Line("Die Auswertung hat nicht geklappt", saved));
        Field("Prozessor", cpu);
        Field("Grafikkarte", gpu);
        Field("Arbeitsspeicher (z. B. 16 GB)", ram);
        Field("Größtes Laufwerk (z. B. 1 TB)", disk);
        root.Children.Add(Line("PC-Scheckheft des Verkäufers", logbookName.Length > 0 && logbook == null ? logbookName : logbook == null ? "Hat der Verkäufer ein Scheckheft aus PulsRig mitgegeben, lade es hier: Die Bauteile darin werden gegen den PC gehalten."
            : logbookName + ": " + logbook.Count + " Bauteile geladen, sie werden mitgeprüft."));
        var load = new WrapPanel();
        load.Children.Add(Knopf(logbook == null ? "Scheckheft laden" : "Anderes Scheckheft laden", (_, _) => LoadLogbook()));
        root.Children.Add(load);
        if (!App.IsAdmin) root.Children.Add(Line("Ohne Adminrechte", "Angaben der Laufwerke und Teile des Ereignisprotokolls können fehlen. Für die volle Prüfung PulsRig als Administrator starten."));
        var buttons = new WrapPanel();
        buttons.Children.Add(Knopf("Prüfen mit 5 Minuten Stabilitätstest", (_, _) => StartStress()));
        buttons.Children.Add(Knopf("Prüfen ohne Stabilitätstest", (_, _) => Evaluate()));
        root.Children.Add(buttons);
    }

    void FillStress()
    {
        root.Children.Add(Line("Stabilitätstest läuft", Belastung.State + " Prozessor und Grafikkarte laufen 5 Minuten unter Volllast."));
        var buttons = new WrapPanel();
        buttons.Children.Add(Knopf("Test abbrechen", (_, _) => Belastung.Cancel()));
        root.Children.Add(buttons);
    }

    void FillDone()
    {
        root.Children.Add(Ui.Text(verdict!.Title, 24, Color(verdict.Tone), bold: true, wrap: true));
        root.Children.Add(Line("", Gebrauchtkauf.Limit));
        foreach (var c in compare)
            root.Children.Add(Row(c.Name, c.State == "open" ? "nicht geprüft" : "Anzeige: " + c.Stated + " · gefunden: " + c.Found + (c.State == "warn" ? " · " + Gebrauchtkauf.More : ""),c.State == "open" ? "" : c.State));
        foreach (var r in rows) root.Children.Add(Row(r.Name, r.Text, r.Kind == "open" ? "" : r.Kind));
        var buttons = new WrapPanel();
        buttons.Children.Add(Knopf("Bericht speichern und öffnen", (_, _) => Save()));
        buttons.Children.Add(Knopf("Neu beginnen", (_, _) => { phase = "input"; saved = ""; stressed = false; Fill(); }));
        root.Children.Add(buttons);
        if (saved.Length > 0) root.Children.Add(Line("", saved));
    }

    static Border Line(string title, string text)
    {
        var s = new StackPanel { Margin = new Thickness(0, 10, 0, 10) };
        if (title.Length > 0) s.Children.Add(Ui.Text(title, 16, "Text", bold: true, wrap: true));
        if (text.Length > 0) s.Children.Add(Ui.Text(text, 12.5, "Leise", wrap: true));
        return new Border { Child = s };
    }

    static Border Row(string title, string text, string tone)
    {
        var s = new StackPanel { Margin = new Thickness(14, 10, 12, 10) };
        s.Children.Add(Ui.Text(title, 14, "Text", bold: true, wrap: true));
        s.Children.Add(Ui.Text(text, 12.5, "Leise", wrap: true));
        return new Border { Child = s, CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 0, 0, 8), Background = Ui.Brush("#0B0710"),
            BorderBrush = Ui.Brush(tone.Length == 0 ? "#22172F" : Color(tone)), BorderThickness = new Thickness(3, 1, 1, 1) };
    }

    void StartStress()
    {
        phase = "stress";
        stressed = true;
        Belastung.What = "both";
        Belastung.Minutes = 5;
        Belastung.Start();
        Fill();
    }

    async void Evaluate()
    {
        phase = "wait";
        saved = "";
        Fill();
        // eine Abfrage, die scheitert, bleibt leer: nach 30 Sekunden zählt sie als nicht prüfbar
        try { await Compare(); }
        catch (Exception e)
        {
            // async void: ein Fehler hier beendet sonst die ganze App
            Fehlerprotokoll.Write(e);
            if (stopped) return;
            saved = Fehlermeldung.Text(e);
            phase = "input";
            Fill();
        }
    }

    async Task Compare()
    {
        for (var i = 0; i < 100 && !stopped && (Hw.Cpu == null || Hw.Gpu == null || Hw.Memory == null || Hw.Drives == null || Hw.Crashes == null); i++) await Task.Delay(300);
        if (stopped) return;
        var battery = await Task.Run(AkkuPage.Cell);
        if (stopped) return;

        compare = new()
        {
            Gebrauchtkauf.Name("Prozessor", cpu.Text, Hw.Cpu?.Name ?? ""),
            Gebrauchtkauf.Name("Grafikkarte", gpu.Text, Hw.Gpu?.Name ?? ""),
            Gebrauchtkauf.Size("Arbeitsspeicher", ram.Text, (Hw.Memory?.Modules.Sum(x => x.Bytes) ?? 0) / (1L << 30), 0.03),
            Gebrauchtkauf.Size("Größtes Laufwerk", disk.Text, (Hw.Drives?.Disks.Select(x => x.Size).DefaultIfEmpty(0).Max() ?? 0) / 1e9, 0.05),
        };
        if (logbook != null)
        {
            var found = new List<HeftTeil>();
            if (Hw.Cpu?.Name is { Length: > 0 } c) found.Add(new HeftTeil { Kind = "Prozessor", Name = c.Trim() });
            if (Hw.Gpu?.Name is { Length: > 0 } g) found.Add(new HeftTeil { Kind = "Grafikkarte", Name = g.Trim() });
            if (Hw.Memory is { } m) found.Add(new HeftTeil { Kind = "Arbeitsspeicher", Size = Math.Round((m.Modules.Sum(x => x.Bytes) is > 0 and var b ? b : m.Total) / (1L << 30)) });
            foreach (var d in Hw.Drives?.Disks.Where(d => d.Bus != "USB") ?? Enumerable.Empty<Laufwerk>()) found.Add(new HeftTeil { Kind = "Laufwerk", Name = d.Name.Trim(), Size = Math.Round(d.Size / 1e9) });
            compare.AddRange(Scheckheft.Compare(logbook, found).Select(a => new Abgleich("Scheckheft: " + a.Name, a.Stated, a.Found, a.State)));
        }
        rows = Bericht.Checks().Where(c => Kept.Contains(c.Name) || stressed && Stress.Contains(c.Name)).Select(c => (c.Name, c.Text, c.Kind)).ToList();
        if (!stressed) rows.Insert(0, ("Stabilitätstest", "Nicht gelaufen.", "open"));
        if (battery is { } cell)
        {
            if (Akku.Health(cell.Design, cell.Full) is { } h)
                rows.Add(("Akku", "Fasst noch " + h.Percent + " % von neu" + (cell.Cycles > 0 ? ", " + cell.Cycles.ToString("N0", Ui.De) + " Ladezyklen." : "."), h.Tone is "good" or "bad" ? h.Tone : "warn"));
            else rows.Add(("Akku", "Windows gibt die Kapazität nicht heraus.", "open"));
        }
        verdict = Gebrauchtkauf.Verdict(compare.Count(c => c.State == "bad"), rows.Count(r => r.Kind == "bad"), compare.Count(c => c.State == "warn") + rows.Count(r => r.Kind == "warn"),
            compare.Count(c => c.State == "open") + rows.Count(r => r.Kind == "open"));
        phase = "done";
        Fill();
    }

    void LoadLogbook()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Title = "PC-Scheckheft laden", Filter = "PC-Scheckheft (*.html)|*.html;*.htm|Alle Dateien|*.*" };
        if (dialog.ShowDialog() != true) return;
        try
        {
            logbook = Scheckheft.PartsFromHtml(File.ReadAllText(dialog.FileName));
            logbookName = logbook == null ? Path.GetFileName(dialog.FileName) + " ist kein PC-Scheckheft aus PulsRig." : Path.GetFileName(dialog.FileName);
        }
        catch (Exception e) { logbook = null; logbookName = Bedienfehler.Text(e); }
        Fill();
    }

    void Save()
    {
        try
        {
            var folder = Altdaten.Portable is { } stick ? Path.Combine(stick, "Gebrauchtkauf") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "PulsRig");
            Directory.CreateDirectory(folder);
            var file = Path.Combine(folder, "Gebrauchtkauf-Check-" + DateTime.Now.ToString("yyyy-MM-dd-HHmm") + ".html");
            File.WriteAllText(file, Gebrauchtkauf.Html(verdict!, DateTime.Now, compare, rows));
            saved = "Gespeichert: " + file;
            Process.Start(new ProcessStartInfo(file) { UseShellExecute = true });
        }
        catch (Exception e) { saved = Bedienfehler.Text(e); }
        Fill();
    }

    public void Stop()
    {
        stopped = true;
        Belastung.Changed -= onStress;
        if (phase == "stress" && Belastung.Running) Belastung.Cancel();
    }
}
