using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace PulsRig.App;

// Ergebnis des Scans nach der Werkzeugliste des Entwurfs (toolList): links Urteil und Quellen, rechts je Befund eine
// Zeile mit Farbbalken, Text, Hinweis und Knopf. Installiert wird nur nach einer Rückfrage und nur mit Adminrechten
// (Treiberinstallation.cs); AMD-Treiber und Katalog-Pakete öffnen weiter die Seite, wie im PowerShell-Programm.
sealed class TreiberPage : UserControl, IPage
{
    const string Lila = "#8C6BD6", Beere = "#C0608F", Bernstein = "#F2B661", Gruen = "#5EE0A0", Grau = "#3E3150";
    readonly bool demo;
    readonly Grid root = new();
    bool stopped;
    List<Laufzeit>? runtimes;
    List<Schutzkarte>? cards;

    sealed record Zeile(string Bar, string Name, string Sub, string Hint, string Button, Action? Run, Action? Ignore = null, bool Install = false);

    public TreiberPage(bool demo)
    {
        this.demo = demo;
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        Content = root;
        Fill();
        Treiberscan.Changed += Fill;
        Treiberinstallation.Changed += Refresh;
    }

    // nach einer Installation die Laufzeiten und Grafikkarten neu lesen
    void Refresh()
    {
        if (!Treiberinstallation.Busy) { runtimes = null; cards = null; }
        Fill();
    }

    bool Ask(string title, string text, string yes) => Bestaetigung.Ask(this, title, text, yes);

    // Installieren geht nur mit Adminrechten und nur, wenn gerade nichts anderes läuft
    Action Guarded(string title, string text, string yes, Action run) => () =>
    {
        if (Treiberinstallation.Busy || Treiberscan.Running) return;
        if (!App.IsAdmin) { Ask("Adminrechte nötig", "Zum Installieren muss PulsRig als Administrator laufen. Starte es neu mit „Als Administrator ausführen“.", "Verstanden"); return; }
        if (Ask(title, text, yes)) run();
    };

    static string RestoreText => TreiberEinstellungen.Current.RestorePoint ? " Vorher legt PulsRig einen Wiederherstellungspunkt an." : "";

    static void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch (Exception) { }
    }

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        var s = demo ? null : Treiberscan.Last;
        var hero = Hero(s);
        Grid.SetColumn(hero, 0);
        root.Children.Add(hero);
        var list = new StackPanel();
        foreach (var (title, rows) in Sections(s))
        {
            if (rows.Count == 0) continue;
            var head = Ui.Text(title.ToUpperInvariant(), 11, "Leise", bold: true);
            head.Margin = new Thickness(4, list.Children.Count == 0 ? 0 : 14, 0, 8);
            list.Children.Add(head);
            foreach (var r in rows) list.Children.Add(Row(r));
        }
        if (list.Children.Count == 0)
            list.Children.Add(Ui.Text(Treiberscan.Running ? "Der Scan läuft …" : "Noch kein Ergebnis – starte den Scan links.", 13, "Leise"));
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(scroll, 2);
        root.Children.Add(scroll);
        if (!Treiberscan.Running) Ui.Arrive(list.Children.Cast<UIElement>().Take(12));
    }

    Border Hero(ScanErgebnis? s)
    {
        var color = s == null && !demo ? Lila : (demo || s!.Newer + s.Problems.Count > 0) ? Beere : Gruen;
        var glow = new RadialGradientBrush { Center = new Point(0.2, 0.1), GradientOrigin = new Point(0.2, 0.1), RadiusX = 0.9, RadiusY = 0.5 };
        glow.GradientStops.Add(new GradientStop(Ui.Hex("#1C" + color.TrimStart('#')), 0));
        glow.GradientStops.Add(new GradientStop(Colors.Transparent, 0.7));
        var panel = new DockPanel();
        var icon = new Border { Width = 64, Height = 64, CornerRadius = new CornerRadius(20), Background = Ui.Alpha(color, "1A"), BorderBrush = Ui.Alpha(color, "33"), BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Left,
            Child = new Path { Data = Geometry.Parse("M5 4h11l3 3v13H5z M8 4v5h7V4 M8 20v-6h8v6"), Stroke = Ui.Brush(color), StrokeThickness = 1.8, Width = 24, Height = 24, Stretch = Stretch.None,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round, LayoutTransform = new ScaleTransform(1.25, 1.25),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
        string title, sub;
        if (demo) { title = "Vier Treiber sind neuer."; sub = "Stand: gerade eben · 214 Geräte, 38 von Drittherstellern · gefragt: Windows Update, NVIDIA, AMD, Katalog"; }
        else if (s == null) { title = Treiberscan.Running ? "Ich schaue nach …" : "Noch kein Scan."; sub = "Der Scan fragt Windows Update, die Hersteller deiner Grafikkarte und deines Chipsatzes und den Microsoft-Katalog nach neueren Treibern."; }
        else
        {
            title = s.Newer == 0 && s.Problems.Count == 0 ? "Alle Treiber sind aktuell." : s.Newer == 1 ? "Ein Treiber ist neuer." : s.Newer > 1 ? s.Newer + " Treiber sind neuer." : s.Problems.Count == 1 ? "Ein Gerät meldet einen Fehler." : s.Problems.Count + " Geräte melden Fehler.";
            sub = "Stand: " + (s.When.Date == DateTime.Today ? "heute " : s.When.ToString("dd.MM. ")) + s.When.ToString("HH:mm") + " Uhr · " + s.Devices + " Geräte, " + s.ThirdParty + " von Drittherstellern · gefragt: " + string.Join(", ", s.Sources);
        }
        var titleBlock = new TextBlock { Text = title, FontSize = 26, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 20, 0, 0), LineHeight = 30 };
        var subBlock = new TextBlock { Text = sub, FontSize = 13, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), LineHeight = 19.5 };
        foreach (var top in new FrameworkElement[] { icon, titleBlock, subBlock }) { DockPanel.SetDock(top, Dock.Top); panel.Children.Add(top); }
        if (s is { Failed.Count: > 0 } || s is { SearchError.Length: > 0 })
        {
            var warn = new TextBlock { Text = (s.SearchError.Length > 0 ? "Windows Update: " + s.SearchError + " " : "") + (s.Failed.Count > 0 ? "Ohne Antwort: " + string.Join(", ", s.Failed) + " – dort kann noch etwas Neueres liegen." : ""),
                FontSize = 12, Foreground = Ui.Brush(Bernstein), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) };
            DockPanel.SetDock(warn, Dock.Top);
            panel.Children.Add(warn);
        }

        // unten: Hinweis wie im Entwurf und der Knopf für einen neuen Scan
        var note = new Border { CornerRadius = new CornerRadius(14), Background = Ui.Brush("#06FFFFFF"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), Padding = new Thickness(14, 12, 14, 12),
            Margin = new Thickness(0, 12, 0, 0) };
        var noteRow = new DockPanel();
        var shield = new Path { Data = Geometry.Parse("M12 3l8 3v6c0 4.5-3.4 8.2-8 9-4.6-.8-8-4.5-8-9V6z M9 12l2 2 4-4"), Stroke = Ui.Brush(Gruen), StrokeThickness = 2, Width = 24, Height = 24, Stretch = Stretch.None,
            LayoutTransform = new ScaleTransform(16 / 24.0, 16 / 24.0), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 1, 10, 0),
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round };
        noteRow.Children.Add(shield);
        var noteText = Treiberinstallation.Busy ? Treiberinstallation.Stage
            : Treiberinstallation.LastMessage.Length > 0 ? Treiberinstallation.LastMessage
            : "Installiert wird nur, was du bestätigst – Dateien kommen direkt von Windows Update, NVIDIA oder Microsoft und werden auf die Signatur geprüft. Firmware und BIOS spielt PulsRig nie ein."
              + (App.IsAdmin ? "" : " Zum Installieren PulsRig als Administrator starten.");
        noteRow.Children.Add(new TextBlock { Text = noteText,
            FontSize = 12, Foreground = Ui.Res(Treiberinstallation.Busy ? "Text" : "Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 17.5 });
        note.Child = noteRow;
        DockPanel.SetDock(note, Dock.Bottom);
        var running = Treiberscan.Running;
        var scan = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 44, Tag = "22", Margin = new Thickness(0, 16, 0, 0),
            Background = running ? Ui.Brush("#140C1D") : (Brush)Application.Current.FindResource("PulsQuer"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(running ? 1 : 0),
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center,
            Content = Ui.Text(running ? Math.Round(Treiberscan.Percent) + " % · " + Treiberscan.Stage : s == null && !demo ? "Scan starten" : "Erneut scannen", 13.5, "Text", bold: true) };
        if (!running && !demo) scan.Click += (_, _) => Treiberscan.Start();
        DockPanel.SetDock(scan, Dock.Bottom);
        panel.Children.Add(note);
        panel.Children.Add(scan);
        panel.Children.Add(new Border());

        var section = new Border { CornerRadius = new CornerRadius(24), BorderThickness = new Thickness(1), BorderBrush = Ui.Alpha(color, "2E"), Padding = new Thickness(24), Child = panel,
            Background = Ui.Tint(color == Gruen ? "#10291F" : color == Beere ? "#1B0916" : "#160D29") };
        var layer = new Grid();
        layer.Children.Add(section);
        layer.Children.Add(new Border { CornerRadius = new CornerRadius(24), Background = glow, IsHitTestVisible = false });
        return new Border { Child = layer };
    }

    List<(string, List<Zeile>)> Sections(ScanErgebnis? s)
    {
        if (demo)
            return new()
            {
                ("Neuer verfügbar", new()
                {
                    new(Beere, "NVIDIA GeForce RTX 3080", "Game Ready 566.36 vom 05.12.2024 · installiert 566.14", "neu", "Seite öffnen", null),
                    new(Beere, "Realtek – Audio – 6.0.9733.1", "Realtek High Definition Audio · installiert 6.0.9600.1", "optional", "Windows Update", null),
                    new(Beere, "Intel – Netzwerk – 23.80.0.7", "Intel Ethernet Connection I219-V · installiert 12.19.2.45", "", "Windows Update", null),
                    new(Beere, "AMD Chipsatz-Treiber 6.10.17.152", "X570-Chipsatz · installiert 5.08.02.027", "neu", "Seite öffnen", null),
                }),
                ("Aktuell", new() { new(Grau, "214 Treiber geprüft", "38 von Drittherstellern, der Rest von Microsoft", "", "Geräte-Manager", null) }),
            };
        var settings = TreiberEinstellungen.Current;
        var extra = Extras();
        if (s == null) return extra;
        var newer = new List<Zeile>();
        foreach (var v in new[] { s.Nvidia, s.Radeon, s.Amd }.Where(v => v is { IsNewer: true }))
        {
            var key = (v!.Source == "AMD" ? "amd:" : v.Source == "Radeon" ? "radeon:" : "nvidia:") + v.Latest;
            if (settings.IsIgnored(key)) continue;
            var name = v.Source == "AMD" ? "AMD Chipsatz-Treiber " + v.Latest : v.Device;
            var sub = (v.Kind + " " + v.Latest + (v.Released.Length > 0 ? " vom " + v.Released : "")).Trim() + (v.Installed.Length > 0 ? " · installiert " + v.Installed : " · nicht installiert") + (v.Size.Length > 0 ? " · " + v.Size : "");
            void Ignore() { settings.Ignore(key, name + " " + v.Latest); Fill(); }
            // NVIDIA lädt PulsRig selbst (Datei von *.nvidia.com mit NVIDIA-Signatur); AMD will die eigene Seite
            if (v.Source == "NVIDIA" && v.Url.Length > 0)
                newer.Add(new(Beere, name, sub, "neu", "Installieren", Guarded("NVIDIA " + v.Latest + " installieren?",
                    "PulsRig lädt den Treiber direkt von NVIDIA (" + (v.Size.Length > 0 ? v.Size : "einige hundert MB") + "), prüft die Signatur und startet den NVIDIA-Installer. Dort entscheidest du selbst über die Optionen." + RestoreText,
                    "Installieren", () => Treiberinstallation.InstallNvidia(v)), Ignore, true));
            else
                newer.Add(new(Beere, name, sub, "neu", "Seite öffnen", () => Open(v.Url), Ignore));
        }
        var offers = s.Updates.Where(u => !settings.IsIgnored("wu:" + u.Key + "|" + u.Title)).ToList();
        foreach (var u in offers)
        {
            var sub = (u.Device.Length > 0 ? u.Device + " · " : "") + (u.Installed.Length > 0 ? "installiert " + u.Installed : "kein Treiber installiert") + (u.NewDate is { Length: > 1 } ? " · neu vom " + u.NewDate : "") + (u.Size.Length > 0 ? " · " + u.Size : "");
            void Ignore() { settings.Ignore("wu:" + u.Key + "|" + u.Title, u.Name); Fill(); }
            // Firmware und BIOS spielt PulsRig nie selbst ein
            if (u.Firmware)
                newer.Add(new(Bernstein, u.Name, sub, "Firmware", "Windows Update", () => Open("ms-settings:windowsupdate"), Ignore));
            else
                newer.Add(new(Beere, u.Name, sub, u.Optional ? "optional" : "", "Installieren", Guarded(u.Name + " installieren?",
                    "PulsRig lädt den Treiber über Windows Update und installiert ihn. Der Bildschirm kann kurz flackern, Geräte können sich kurz abmelden." + RestoreText,
                    "Installieren", () => Treiberinstallation.InstallUpdates(new[] { u })), Ignore, true));
        }
        var installable = offers.Where(u => !u.Firmware).ToList();
        if (installable.Count > 1)
            newer.Insert(0, new(Beere, "Alle " + installable.Count + " von Windows Update", string.Join(" · ", installable.Select(u => u.Name)), "", "Alle installieren",
                Guarded(installable.Count + " Treiber installieren?", "PulsRig lädt alle Treiber von Windows Update und installiert sie nacheinander." + RestoreText, "Alle installieren",
                    () => Treiberinstallation.InstallUpdates(installable)), null, true));

        var problems = s.Problems.Select(p => p.CatalogQuery.Length > 0
            ? new Zeile(Bernstein, p.Name.Length > 0 ? p.Name : p.Id, p.Text + " (Code " + p.Code + ") · im Microsoft-Katalog: " + p.Catalog, "Treiber da", "Installieren",
                Guarded("Treiber aus dem Katalog installieren?", "PulsRig lädt das Paket " + p.Catalog + " aus dem Microsoft-Katalog, prüft Prüfsumme, Microsoft-Signatur und ob es dieses Gerät nennt, und installiert es." + RestoreText,
                    "Installieren", () => Treiberinstallation.InstallCatalog(p.CatalogQuery, "", p.Catalog, p.Id)), null, true)
            : new Zeile(p.Code == 22 ? Grau : Bernstein, p.Name.Length > 0 ? p.Name : p.Id, p.Text + " (Code " + p.Code + ") · " + p.Advice,
                p.Chipset ? "Chipsatz" : "", p.Chipset && s.Board != null ? "Treiber suchen" : "Geräte-Manager",
                () => Open(p.Chipset && s.Board != null ? s.Board.Url : "devmgmt.msc"))).ToList();

        // Katalog-Hinweise: echte Treiber lassen sich direkt installieren; reine Beschreibungen ohne Treibercode bringen nichts und fehlen
        var hints = s.Hints.Where(h => !h.NoCode).Select(h => new Zeile(Lila, h.Title, h.Device + " · installiert " + h.Installed + " · Katalog vom " + h.Date + (h.Size.Length > 0 ? " · " + h.Size : ""),
            "Katalog", h.Query.Length == 0 ? "Katalog öffnen" : "Installieren",
            h.Query.Length == 0 ? () => Open(h.Url) : Guarded(h.Title + " installieren?",
                "PulsRig lädt das Paket aus dem Microsoft-Katalog, prüft Prüfsumme, Microsoft-Signatur und ob es dieses Gerät nennt, sichert den bisherigen Treiber und installiert den neuen."
                + (System.Text.RegularExpressions.Regex.IsMatch(h.Title + " " + h.Device, "(?i)audio|media|sound") ? " Der Ton setzt dabei kurz aus." : "") + RestoreText,
                "Installieren", () => Treiberinstallation.InstallCatalog(h.Query, h.Title, h.Version, h.HardwareIds)),
            null, h.Query.Length > 0)).ToList();

        var current = new List<Zeile>();
        foreach (var v in new[] { s.Nvidia, s.Radeon, s.Amd }.Where(v => v is { IsNewer: false }))
            current.Add(new(Gruen, v!.Source == "AMD" ? "AMD Chipsatz-Treiber" : v.Device, "installiert " + v.Installed + " · neueste bei " + (v.Source == "Radeon" ? "AMD" : v.Source) + ": " + v.Latest, "aktuell", "Seite öffnen",
                () => Open(v.Source == "NVIDIA" ? "https://www.nvidia.com/de-de/geforce/drivers/" : v.Url)));
        if (s.Intel) current.Add(new(Grau, "Intel", "Intel lässt sich nicht direkt fragen – Intels Assistent prüft Grafik, WLAN und Bluetooth.", "", "Seite öffnen", () => Open("https://www.intel.de/content/www/de/de/support/detect.html")));
        if (s.RadeonHint) current.Add(new(Grau, "AMD Radeon", "Für diese Karte nennt AMD keine feste Seite – AMD Software: Adrenalin Edition prüft selbst.", "", "Seite öffnen", () => Open("https://www.amd.com/de/support/download/drivers.html")));
        current.Add(new(Grau, s.Devices + " Treiber geprüft", s.ThirdParty + " von Drittherstellern, der Rest von Microsoft" + (s.Drivers.Count > 0 ? " · neuester: " + Newest(s) : ""), "", "Geräte-Manager", () => Open("devmgmt.msc")));
        var all = new List<(string, List<Zeile>)> { ("Neuer verfügbar", newer), ("Gerätefehler", problems), ("Hinweise aus dem Microsoft-Katalog", hints), ("Aktuell", current) };
        all.AddRange(extra);
        return all;
    }

    // Grafiktreiber schützen, Laufzeitbibliotheken und Ausschlüsse: unabhängig vom Scan
    List<(string, List<Zeile>)> Extras()
    {
        var settings = TreiberEinstellungen.Current;
        try { cards ??= Treiberinstallation.ShieldStatus(); } catch (Exception) { cards = new(); }
        try { runtimes ??= Treiberinstallation.RuntimeStatus(); } catch (Exception) { runtimes = new(); }
        var shield = cards.Select(c => new Zeile(c.On ? Gruen : Grau, c.Name, c.On ? "Geschützt: Windows Update spielt für diese Karte keinen Grafiktreiber ein. Treiber vom Hersteller gehen weiter." : "Windows Update darf den Grafiktreiber ersetzen · installiert " + c.Version,
            c.On ? "geschützt" : "", c.On ? "Freigeben" : "Schützen", () =>
            {
                if (Treiberinstallation.Busy || Treiberscan.Running) return;
                if (Ask(c.On ? "Schutz aufheben?" : "Grafiktreiber schützen?", c.On
                        ? "Windows Update bietet für " + c.Name + " wieder Grafiktreiber an. Versteckte Angebote werden wieder sichtbar."
                        : "Windows Update soll den Treiber für " + c.Name + " nicht mehr überschreiben. PulsRig versteckt dafür nur die Grafiktreiber-Angebote dieser Karte – umkehrbar, ohne Richtlinie.",
                        c.On ? "Freigeben" : "Schützen"))
                    Treiberinstallation.SetShield(c.Key, !c.On);
            })).ToList();
        var libs = runtimes.Select(r => new Zeile(r.Status == "vorhanden" ? Gruen : r.Status == "veraltet" ? Bernstein : Grau, r.Name,
            (r.Status == "vorhanden" ? "vorhanden" : r.Status == "veraltet" ? "veraltet" : "fehlt – nur nötig, wenn ein Spiel danach fragt") + (r.Version.Length > 0 ? " · " + r.Version : ""),
            r.Status == "vorhanden" ? "" : r.Status, r.Url == null ? "Seite öffnen" : r.Status == "vorhanden" ? "Neu installieren" : "Installieren",
            r.Url == null ? () => Open("https://www.openal.org/downloads/") : Guarded(r.Name + " installieren?",
                "PulsRig lädt den Installer direkt von Microsoft, prüft die Signatur und startet ihn. Dort bestätigst du selbst.", "Installieren", () => Treiberinstallation.InstallRuntime(r)),
            null, r.Url != null)).ToList();
        var ignored = settings.Ignored.Select(i => new Zeile(Grau, i.Name, "wird in den Ergebnissen nicht mehr angeboten", "", "Wieder anbieten", () => { settings.Unignore(i.Key); Fill(); })).ToList();
        // Schalter wie in den Optionen des PowerShell-Programms (RestorePoint, AutoBackup)
        var safety = new List<Zeile>
        {
            new(settings.RestorePoint ? Gruen : Grau, "Wiederherstellungspunkt", settings.RestorePoint ? "Vor jeder Treiberinstallation legt PulsRig einen an (Windows höchstens einen am Tag)." : "Aus – vor Installationen wird kein Wiederherstellungspunkt angelegt.",
                settings.RestorePoint ? "an" : "aus", settings.RestorePoint ? "Ausschalten" : "Einschalten", () => { settings.RestorePoint = !settings.RestorePoint; settings.Save(); Fill(); }),
            new(settings.AutoBackup ? Gruen : Grau, "Ersetzte Treiber sichern", settings.AutoBackup ? "Vor einem Update sichert PulsRig den bisherigen Treiber von Drittherstellern (bis 300 MB je Paket)." : "Aus – ersetzte Treiber werden nicht gesichert.",
                settings.AutoBackup ? "an" : "aus", settings.AutoBackup ? "Ausschalten" : "Einschalten", () => { settings.AutoBackup = !settings.AutoBackup; settings.Save(); Fill(); }),
        };
        return new() { ("Grafiktreiber schützen", shield), ("Laufzeitbibliotheken für Spiele", libs), ("Sicherheit beim Installieren", safety), ("Ausgeschlossen", ignored) };
    }

    static string Newest(ScanErgebnis s)
    {
        var d = s.Drivers.Where(x => x.ThirdParty && x.When != null).OrderByDescending(x => x.When).FirstOrDefault();
        return d == null ? "–" : d.Name + " vom " + d.Date;
    }

    static Border Row(Zeile r)
    {
        var grid = new Grid { MinHeight = 64 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var bar = new Border { Width = 4, Height = 34, CornerRadius = new CornerRadius(2), Background = Ui.Brush(r.Bar), Margin = new Thickness(0, 0, 16, 0), Effect = r.Bar == Grau ? null : Ui.Glow(r.Bar, 10) };
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(r.Name, 15, "Text", bold: true));
        var sub = Ui.Text(r.Sub, 12.5, "Leise");
        sub.Margin = new Thickness(0, 3, 0, 0);
        sub.ToolTip = r.Sub;
        text.Children.Add(sub);
        Grid.SetColumn(text, 1);
        grid.Children.Add(bar);
        grid.Children.Add(text);
        if (r.Hint.Length > 0)
        {
            var pill = new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 4, 10, 4), Background = Ui.Alpha(r.Bar == Grau ? Lila : r.Bar, "1A"), VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 12, 0), Child = Ui.Text(r.Hint, 11.5, r.Bar == Grau ? Lila : r.Bar) };
            Grid.SetColumn(pill, 2);
            grid.Children.Add(pill);
        }
        var button = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, MinWidth = 96, Padding = new Thickness(16, 0, 16, 0), Tag = "18",
            Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(r.Button, 12.5, "Text", bold: true) };
        if (r.Run != null) button.Click += (_, _) => r.Run();
        if (r.Install && (Treiberinstallation.Busy || Treiberscan.Running)) { button.IsEnabled = false; button.Opacity = 0.5; }
        if (r.Install && !App.IsAdmin) button.ToolTip = "Nur mit Adminrechten";
        var actions = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (r.Ignore != null)
        {
            var ignore = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Width = 36, Tag = "18", Margin = new Thickness(0, 0, 8, 0), ToolTip = "Nicht mehr anbieten",
                Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1),
                HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text("✕", 12, "Leise") };
            ignore.Click += (_, _) => r.Ignore();
            actions.Children.Add(ignore);
        }
        actions.Children.Add(button);
        Grid.SetColumn(actions, 3);
        grid.Children.Add(actions);
        return new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(18), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"),
            Padding = new Thickness(20, 0, 18, 0), Margin = new Thickness(0, 0, 0, 10), Child = grid };
    }

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Treiberscan.Changed -= Fill;
        Treiberinstallation.Changed -= Refresh;
    }
}
