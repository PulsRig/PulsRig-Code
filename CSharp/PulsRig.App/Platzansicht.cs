using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using PulsRig.Core;

namespace PulsRig.App;

// Speicher-Analyse auf der Laufwerksseite: links die größten Ordner (anklicken = hineingehen), rechts die größten
// Dateien im gewählten Ordner (anklicken = im Explorer zeigen). PulsRig löscht hier nichts selbst.
sealed class Platzansicht : UserControl
{
    readonly bool demo;
    readonly Action back;
    string letter = "";
    string folder = "";

    public Platzansicht(bool demo, Action back)
    {
        this.demo = demo;
        this.back = back;
    }

    public void Show(string driveLetter)
    {
        if (driveLetter != letter) { letter = driveLetter; folder = ""; }
        var result = demo ? Platzlauf.Demo() : Platzlauf.Results.GetValueOrDefault(letter);
        var page = new DockPanel();
        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 16) };
        var backButton = Knopf("‹ Laufwerke", back);
        backButton.Margin = new Thickness(0, 0, 16, 0);
        DockPanel.SetDock(backButton, Dock.Left);
        head.Children.Add(backButton);
        var title = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        title.Children.Add(Ui.Text("Was belegt " + letter + ":?", 22, "Text", bold: true));
        Content = page;

        if (!demo && Platzlauf.Running == letter)
        {
            title.Children.Add(Ui.Text("Durchsucht das Laufwerk – das dauert je nach Größe ein bis wenige Minuten.", 12.5, "Leise"));
            var stop = Knopf("Abbrechen", Platzlauf.Cancel);
            DockPanel.SetDock(stop, Dock.Right);
            head.Children.Add(stop);
            head.Children.Add(title);
            DockPanel.SetDock(head, Dock.Top);
            page.Children.Add(head);
            var wait = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
            wait.Children.Add(Ui.Text(Count(Platzlauf.Seen) + " Dateien gezählt …", 20, "Text", bold: true, mono: true));
            wait.Children.Add(Ui.Text("Du kannst die Seite verlassen, die Analyse läuft weiter.", 12.5, "Leise"));
            page.Children.Add(wait);
            return;
        }
        if (result == null)
        {
            var reason = Platzlauf.Errors.GetValueOrDefault(letter) ?? (Platzlauf.Running.Length > 0 ? "Gerade wird Laufwerk " + Platzlauf.Running + ": analysiert. Danach ist dieses dran." : "Die Analyse wurde abgebrochen.");
            title.Children.Add(Ui.Text(reason, 12.5, "Leise", wrap: true));
            if (Platzlauf.Running.Length == 0)
            {
                var again = Knopf("Analysieren", () => Platzlauf.Start(letter));
                DockPanel.SetDock(again, Dock.Right);
                head.Children.Add(again);
            }
            head.Children.Add(title);
            page.Children.Add(head);
            return;
        }

        var node = Find(result.Root, folder) ?? result.Root;
        folder = node == result.Root ? "" : node.Path;
        var summary = Size(result.Root.Size) + " in " + Count(result.Root.Files) + " Dateien · " + Math.Max(1, Math.Round(result.Duration.TotalSeconds)) + " s";
        if (result.Skipped > 0) summary += " · " + result.Skipped + " Ordner" + " ohne Leserecht" + (App.IsAdmin ? "" : " (mit Adminrechten mehr)");
        title.Children.Add(Ui.Text(summary, 12.5, "Leise"));
        var tools = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var explorer = Knopf("Im Explorer öffnen", () => Platzlauf.Reveal(node.Path, false));
        explorer.Margin = new Thickness(0, 0, 8, 0);
        tools.Children.Add(explorer);
        if (!demo) tools.Children.Add(Knopf("Neu analysieren", () => { Platzlauf.Results.Remove(letter); Platzlauf.Start(letter); }));
        DockPanel.SetDock(tools, Dock.Right);
        head.Children.Add(tools);
        head.Children.Add(title);
        DockPanel.SetDock(head, Dock.Top);
        page.Children.Add(head);

        // Pfad zum gewählten Ordner, jedes Stück anklickbar
        var crumbs = new WrapPanel { Margin = new Thickness(0, 0, 0, 12) };
        var chain = new List<Platzordner>();
        for (var n = node; n != null; n = Elternordner(result.Root, n)) chain.Insert(0, n);
        foreach (var n in chain)
        {
            if (crumbs.Children.Count > 0) crumbs.Children.Add(Ui.Text("  ›  ", 13, "Leise"));
            var target = n;
            var t = Ui.Text(n == result.Root ? letter + ":" : n.Name, 13, n == node ? "Text" : "Leise", bold: n == node);
            if (n != node) { t.Cursor = Cursors.Hand; t.MouseLeftButtonUp += (_, _) => { folder = target == result.Root ? "" : target.Path; Show(letter); }; }
            crumbs.Children.Add(t);
        }
        DockPanel.SetDock(crumbs, Dock.Top);
        page.Children.Add(crumbs);

        // Übersicht wie in den Windows-Einstellungen, nur auf der obersten Ebene
        if (node == result.Root)
        {
            var kinds = new System.Windows.Controls.Primitives.UniformGrid { Columns = 4 };
            foreach (var k in Platzanalyse.Kategorien(result.Root).Where(k => k.Size >= 1 << 20))
            {
                var path = k.Path;
                Action click = path.Length > 0 ? () => { folder = path; Show(letter); } : () => { };
                kinds.Children.Add(Row(k.Name, Hinweis(k.Name), k.Size, result.Root.Size, click, path.Length > 0 ? "Hineinschauen" : "", Farbe(k.Name)));
            }
            var overview = Panel("Übersicht", kinds);
            overview.Margin = new Thickness(0, 0, 0, 14);
            DockPanel.SetDock(overview, Dock.Top);
            page.Children.Add(overview);
        }

        var columns = new Grid();
        columns.ColumnDefinitions.Add(new ColumnDefinition());
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        columns.ColumnDefinitions.Add(new ColumnDefinition());

        // links: Ordner
        var folders = new StackPanel();
        var shown = node.Children.Where(c => c.Size > 0).Take(30).ToList();
        var loose = node.Size - node.Children.Sum(c => c.Size);
        foreach (var c in shown)
        {
            var target = c;
            Action? open = c.Children.Count > 0 ? () => { folder = target.Path; Show(letter); } : null;
            // fremde Bereiche nur bis zur ersten Ebene darunter (z. B. das einzelne Spiel), nicht bis in seine Dateien
            // Zwischenebenen wie Steam › steamapps › common bleiben offen, damit man bis zum einzelnen Spiel kommt
            // Windows und Papierkorb gar nicht, Spiele und Programme nur über Sammelordner bis zum einzelnen Eintrag
            if (c.Art is Platzart.System or Platzart.Papierkorb) open = null;
            else if (c.Art != Platzart.Eigene && node.Art != Platzart.Eigene && !Durchgang(c.Name)) open = null;
            var sub = c.Art == Platzart.Eigene ? Count(c.Files) + " Dateien" + (open == null ? "" : "  ›") : Bereich(c.Art) + (open == null ? "" : "  ›");
            folders.Children.Add(Row(c.Name, sub, c.Size, node.Size, open ?? (() => Platzlauf.Reveal(target.Path, false)),
                open != null ? "Hineinschauen" : "Im Explorer öffnen", Farbe(c.Art)));
        }
        if (loose >= 1 << 20 && shown.Count > 0) folders.Children.Add(Row("Dateien direkt hier", "", loose, node.Size, () => Platzlauf.Reveal(node.Path, false), "Im Explorer öffnen"));
        if (folders.Children.Count == 0) folders.Children.Add(Ui.Text("Keine Unterordner.", 12.5, "Leise"));
        Ui.Place(columns, Panel("Größte Ordner", folders), 0, 0);

        // rechts: Dateien in diesem Ordner
        var files = new StackPanel();
        var prefix = node.Path.EndsWith('\\') ? node.Path : node.Path + "\\";
        var inside = node.Art != Platzart.Eigene ? new List<Platzdatei>() : result.Biggest.Where(f => f.Path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)).Take(25).ToList();
        var top = inside.Count > 0 ? inside[0].Size : 1;
        foreach (var f in inside)
        {
            var path = f.Path;
            var where = System.IO.Path.GetDirectoryName(f.Path) ?? "";
            files.Children.Add(Row(System.IO.Path.GetFileName(f.Path), Kurz(where) + " · " + f.Changed.ToString("dd.MM.yyyy"), f.Size, top,
                () => Platzlauf.Reveal(path, true), "Im Explorer zeigen"));
        }
        if (inside.Count == 0) files.Children.Add(Ui.Text(node.Art switch
        {
            Platzart.Spiel => "Spieldateien zeigt PulsRig nicht einzeln – das Spiel braucht sie. Wenn du Platz brauchst, deinstalliere das Spiel im Launcher (Steam, Epic, Xbox …).",
            Platzart.Programm => "Programmdateien zeigt PulsRig nicht einzeln. Wenn du Platz brauchst, deinstalliere das Programm unter Einstellungen › Apps.",
            Platzart.System => "Das gehört zu Windows und bleibt, wie es ist. Alte Update-Reste räumt „Speicherplatz freigeben“ unter Werkzeuge auf.",
            Platzart.Papierkorb => "Der Papierkorb wird über den Desktop geleert – PulsRig fasst ihn nicht an.",
            _ => "Hier liegen keine großen eigenen Dateien.",
        }, 12.5, "Leise", wrap: true));
        var filesPanel = Panel("Deine größten Dateien", files);
        Ui.Place(columns, filesPanel, 2, 0);

        var note = Ui.Text("Rechts stehen nur deine eigenen Dateien wie Videos, Downloads oder ISO-Abbilder – keine Dateien von Spielen, Programmen oder Windows. PulsRig löscht nichts selbst, Anklicken öffnet den Explorer.", 12, "Leise", wrap: true);
        note.Margin = new Thickness(0, 12, 0, 0);
        DockPanel.SetDock(note, Dock.Bottom);
        page.Children.Add(note);
        page.Children.Add(columns);
    }

    static bool Durchgang(string name) => name.ToLowerInvariant() is "steam" or "steamapps" or "common" or "steamlibrary" or "epic games" or "xboxgames" or "gog games"
        or "program files" or "program files (x86)" or "riot games" or "ea games" or "ubisoft game launcher" or "games";

    // eine Farbe je Bereich, gleich in Übersicht und Ordnerliste
    static string Farbe(Platzart art) => art switch
    {
        Platzart.Spiel or Platzart.Programm => "#6D43C9",
        Platzart.System => "#4F8FE8",
        Platzart.Papierkorb => "#E5646E",
        _ => "#3DCB8F",
    };

    static string Farbe(string kind) => kind switch
    {
        "Apps & Spiele" => Farbe(Platzart.Programm),
        "Windows" => Farbe(Platzart.System),
        "Papierkorb" => Farbe(Platzart.Papierkorb),
        "Temporäre Dateien" => "#F2B661",
        "Andere" => "#8A8398",
        _ => Farbe(Platzart.Eigene),
    };

    static string Hinweis(string kind) => kind switch
    {
        "Apps & Spiele" => "unter Apps oder im Launcher deinstallieren",
        "Windows" => "nicht anfassen",
        "Temporäre Dateien" => "räumt „Speicherplatz freigeben“ unter Werkzeuge auf",
        "Papierkorb" => "über den Desktop leeren",
        "Andere" => "sonstige Ordner",
        _ => "deine Dateien  ›",
    };

    static string Bereich(Platzart art) => art switch
    {
        Platzart.Spiel => "Spiel · im Launcher deinstallieren",
        Platzart.Programm => "Programm · unter Apps deinstallieren",
        Platzart.System => "Windows · nicht anfassen",
        Platzart.Papierkorb => "Papierkorb",
        _ => "",
    };

    // Benutzerordner kürzen: aus dem vollen Pfad wird z. B. nur "Downloads"
    static string Kurz(string folder)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (folder.StartsWith(home + "\\", StringComparison.OrdinalIgnoreCase)) return folder[(home.Length + 1)..];
        return string.Equals(folder, home, StringComparison.OrdinalIgnoreCase) ? "Benutzerordner" : folder;
    }

    static Platzordner? Find(Platzordner root, string path)
    {
        if (path.Length == 0) return root;
        foreach (var c in root.Children)
        {
            if (string.Equals(c.Path, path, StringComparison.OrdinalIgnoreCase)) return c;
            if (path.StartsWith(c.Path + "\\", StringComparison.OrdinalIgnoreCase)) return Find(c, path);
        }
        return null;
    }

    static Platzordner? Elternordner(Platzordner root, Platzordner node)
    {
        if (node == root) return null;
        foreach (var c in root.Children)
        {
            if (c == node) return root;
            if (node.Path.StartsWith(c.Path + "\\", StringComparison.OrdinalIgnoreCase)) return Elternordner(c, node);
        }
        return null;
    }

    static Border Panel(string title, UIElement list)
    {
        var dock = new DockPanel();
        var head = Ui.Text(title, 14, "Text", bold: true);
        head.Margin = new Thickness(0, 0, 0, 12);
        DockPanel.SetDock(head, Dock.Top);
        dock.Children.Add(head);
        dock.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = list, Padding = new Thickness(0, 0, 6, 0) });
        return new Border { CornerRadius = new CornerRadius(20), BorderThickness = new Thickness(1), BorderBrush = Ui.Res("KarteRand"), Padding = new Thickness(18),
            Background = new System.Windows.Media.LinearGradientBrush(Ui.Hex("#0B0710"), Ui.Hex("#09060D"), 90), Child = dock };
    }

    static Border Row(string name, string sub, long size, long whole, Action click, string tip, string? fill = null)
    {
        var top = new DockPanel();
        var value = Ui.Text(Size(size), 12.5, "Text", mono: true);
        value.Margin = new Thickness(12, 0, 0, 0);
        DockPanel.SetDock(value, Dock.Right);
        top.Children.Add(value);
        top.Children.Add(Ui.Text(name, 13, "Text", bold: true));
        var stack = new StackPanel();
        stack.Children.Add(top);
        if (sub.Length > 0) stack.Children.Add(Ui.Text(sub, 11.5, "Leise"));
        // kleine Anteile bleiben als Strich sichtbar
        var bar = Ui.Bar(whole > 0 && size > 0 ? Math.Max(0.012, (double)size / whole) : 0, "#6D43C9", 6, fill);
        bar.Margin = new Thickness(0, 6, 0, 0);
        stack.Children.Add(bar);
        var row = new Border { Padding = new Thickness(10, 8, 10, 8), CornerRadius = new CornerRadius(10), Background = System.Windows.Media.Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, Child = stack };
        row.MouseEnter += (_, _) => row.Background = Ui.Brush("#140C1D");
        row.MouseLeave += (_, _) => row.Background = System.Windows.Media.Brushes.Transparent;
        row.MouseLeftButtonUp += (_, _) => click();
        return row;
    }

    static Button Knopf(string text, Action click)
    {
        var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 38, Tag = "12", Padding = new Thickness(16, 0, 16, 0), Background = Ui.Brush("#140C1D"),
            BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(text, 13, bold: true) };
        b.Click += (_, _) => click();
        return b;
    }

    public static string Count(long n) => n.ToString("N0", Ui.De);

    // feiner als Ui.Size, weil hier auch kleine Ordner stehen
    public static string Size(double bytes) =>
        bytes >= 1000.0 * (1 << 30) ? Ui.Size(bytes)
        : bytes >= 10.0 * (1 << 30) ? (bytes / (1 << 30)).ToString("N0", Ui.De) + " GB"
        : bytes >= 1 << 30 ? (bytes / (1 << 30)).ToString("N1", Ui.De) + " GB"
        : bytes >= 1 << 20 ? (bytes / (1 << 20)).ToString("N0", Ui.De) + " MB"
        : (bytes / 1024).ToString("N0", Ui.De) + " KB";
}
