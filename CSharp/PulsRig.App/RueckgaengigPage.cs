using System.Windows;
using System.Windows.Controls;
using PulsRig.Core;

namespace PulsRig.App;

// Rückgängig-Zentrale: alles, was PulsRig am System geändert hat, neueste zuerst, mit Knopf zum Zurücknehmen,
// wo das sicher geht (Autostart, Boost, Treiber über die Systemwiederherstellung)
sealed class RueckgaengigPage : UserControl, IPage
{
    readonly bool demo;
    bool stopped;
    string message = "";

    public RueckgaengigPage(bool demo)
    {
        this.demo = demo;
        Rueckgaengiglauf.Changed += Fill;
        Spielboost.Changed += Fill;
        Fill();
    }

    public void Stop()
    {
        stopped = true;
        Rueckgaengiglauf.Changed -= Fill;
        Spielboost.Changed -= Fill;
    }

    List<Rueckgabe> Entries()
    {
        if (!demo) return Rueckgaengig.Load(Rueckgaengiglauf.File).AsEnumerable().Reverse().ToList();
        var now = DateTime.Now;
        return new()
        {
            new(now.AddMinutes(-20), "Boost", "Spiel-Boost für cs2 eingeschaltet", "boost"),
            new(now.AddHours(-3), "Autostart aufräumen", "Discord ausschalten", "autostart", "HKCU|Run|Discord|1"),
            new(now.AddDays(-1), "Treiber", "Treiber installiert, vorher Wiederherstellungspunkt angelegt", "restorepoint"),
            new(now.AddDays(-2), "Speicherplatz freigeben", "Temporäre Dateien löschen"),
            new(now.AddDays(-4), "Autostart aufräumen", "Steam ausschalten", "autostart", "HKCU|Run|Steam|1", Undone: true),
        };
    }

    void Fill()
    {
        if (stopped) return;
        var page = new DockPanel();
        var head = new StackPanel { Margin = new Thickness(0, 0, 0, 16) };
        head.Children.Add(Ui.Text("Rückgängig-Zentrale", 22, "Text", bold: true));
        head.Children.Add(Ui.Text("Alles, was PulsRig an deinem PC geändert hat – neueste zuerst. Wo es sicher geht, nimmst du es hier mit einem Klick zurück.", 12.5, "Leise", wrap: true));
        if (message.Length > 0)
        {
            var m = Ui.Text(message, 12.5, "Text", wrap: true);
            m.Margin = new Thickness(0, 8, 0, 0);
            head.Children.Add(m);
        }
        DockPanel.SetDock(head, Dock.Top);
        page.Children.Add(head);

        var list = new StackPanel();
        var entries = Entries();
        if (entries.Count == 0)
            list.Children.Add(Ui.Text("Noch keine Änderungen. Sobald PulsRig etwas umstellt – Autostart, Boost, Treiber oder ein Werkzeug –, steht es hier.", 13, "Leise", wrap: true));
        string? day = null;
        foreach (var a in entries)
        {
            var d = a.Time.Date == DateTime.Today ? "Heute" : a.Time.Date == DateTime.Today.AddDays(-1) ? "Gestern" : a.Time.ToString("dd.MM.yyyy");
            if (d != day)
            {
                day = d;
                var h = Ui.Text(d, 13, "Leise", bold: true);
                h.Margin = new Thickness(4, list.Children.Count == 0 ? 0 : 14, 0, 6);
                list.Children.Add(h);
            }
            list.Children.Add(Row(a));
        }
        page.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = list, Padding = new Thickness(0, 0, 6, 0) });
        Content = page;
    }

    Border Row(Rueckgabe a)
    {
        var dock = new DockPanel();
        var button = Rueckgaengiglauf.Button(a);
        if (button.Length > 0)
        {
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Tag = "12", Padding = new Thickness(14, 0, 14, 0), Background = Ui.Brush("#140C1D"),
                BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center, Content = Ui.Text(button, 12.5, bold: true) };
            b.Click += (_, _) => Undo(a);
            DockPanel.SetDock(b, Dock.Right);
            dock.Children.Add(b);
        }
        else
        {
            var state = Ui.Pill(a.Undone ? "zurückgenommen" : a.Undo == "boost" ? "schon aus" : "nur zur Übersicht", a.Undone || a.Undo == "boost" ? "#5EE0A0" : "#8A8398", 11);
            state.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(state, Dock.Right);
            dock.Children.Add(state);
        }
        var text = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
        text.Children.Add(Ui.Text(a.Text, 13.5, a.Undone ? "Leise" : "Text", bold: true, wrap: true));
        text.Children.Add(Ui.Text(a.Time.ToString("HH:mm") + " · " + a.Area + (a.Undo == "restorepoint" && !a.Undone ? " · zurück über einen Wiederherstellungspunkt von Windows" : ""), 11.5, "Leise", wrap: true));
        dock.Children.Add(text);
        return new Border { CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(1), BorderBrush = Ui.Res("KarteRand"), Padding = new Thickness(16, 12, 12, 12),
            Margin = new Thickness(0, 0, 0, 8), Background = Ui.Brush("#0B0710"), Child = dock };
    }

    void Undo(Rueckgabe a)
    {
        if (demo) { message = "Im Demo-Modus wird nichts zurückgenommen."; Fill(); return; }
        var ask = a.Undo switch
        {
            "restorepoint" => "Windows öffnet die Systemwiederherstellung. Dort wählst du den Punkt vor der Treiberinstallation – Windows startet dabei neu. Eigene Dateien bleiben erhalten, später installierte Programme und Treiber nicht.",
            "boost" => "Energieplan, angehaltene Dienste und Prioritäten werden zurückgestellt. Geschlossene Programme startest du selbst.",
            _ => "„" + a.Text + "“ wird zurückgenommen. Das wirkt ab der nächsten Anmeldung.",
        };
        if (!Bestaetigung.Ask(this, "Zurücknehmen?", ask, Rueckgaengiglauf.Button(a))) return;
        try { message = Rueckgaengiglauf.Undo(a); }
        catch (Exception e) { message = Bedienfehler.Text(e); }
        if (message.Length == 0 && a.Undo == "autostart") message = "Zurückgenommen.";
        Fill();
    }
}
