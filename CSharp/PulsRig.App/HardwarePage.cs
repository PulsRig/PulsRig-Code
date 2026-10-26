using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace PulsRig.App;

// Hardware-Übersicht der Reihe Q: 4 × 2 Kacheln (Leistung, Speicher & Anzeige, Gesundheit), jede öffnet ihre Seite
sealed class HardwarePage : UserControl, IPage
{
    readonly MainWindow main;
    readonly bool demo;
    readonly Grid grid = Ui.Mosaic(4, 2, 14);
    readonly Dictionary<string, (TextBlock State, TextBlock Value, Border Bar, TextBlock Note, Border Tile)> parts = new();

    public HardwarePage(MainWindow main, bool demo)
    {
        this.main = main;
        this.demo = demo;
        Content = grid;
        var i = 0;
        foreach (var t in Hardwaremodell.Tiles(demo)) Ui.Place(grid, Tile(t), i % 4, i++ / 4);
        Ui.Arrive(grid.Children.Cast<UIElement>());
        Hw.Changed += Refresh;
        Live.Updated += Refresh;
        Live.Use();
        if (!demo) Hw.LoadAll();
    }

    Border Tile(HwTile t)
    {
        var state = Ui.Text(t.State, 11, t.StateColor);
        var head = new DockPanel();
        DockPanel.SetDock(state, Dock.Right);
        head.Children.Add(state);
        head.Children.Add(Ui.Text(t.Group, 12.5, t.Color, bold: true));
        var value = Ui.Text(t.Value, 30, "Text", bold: true, mono: true);
        var bar = new Border { Margin = new Thickness(0, 6, 0, 0) };
        var note = Ui.Text(t.Note, 11.5, "Leise");
        note.Margin = new Thickness(0, 6, 0, 0);
        var bottom = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
        bottom.Children.Add(value);
        bottom.Children.Add(bar);
        bottom.Children.Add(note);
        var name = Ui.Text(t.Name, 16, "Text", bold: true);
        name.Margin = new Thickness(0, 4, 0, 0);
        var body = new DockPanel();
        DockPanel.SetDock(head, Dock.Top);
        DockPanel.SetDock(name, Dock.Top);
        body.Children.Add(head);
        body.Children.Add(name);
        body.Children.Add(bottom);
        var tile = Ui.Tile(t.Color, t.Tint, new Thickness(18));
        tile.Child = body;
        tile.Cursor = Cursors.Hand;
        tile.MouseLeftButtonUp += (_, _) => main.Go(t.Id);
        System.Windows.Automation.AutomationProperties.SetName(tile, t.Name);
        parts[t.Id] = (state, value, bar, note, tile);
        SetBar(t);
        return tile;
    }

    void SetBar(HwTile t) => parts[t.Id].Bar.Child = Ui.Bar(t.Bar, t.Color, reuse: parts[t.Id].Bar.Child);

    void Refresh()
    {
        foreach (var t in Hardwaremodell.Tiles(demo))
        {
            if (!parts.TryGetValue(t.Id, out var p)) continue;
            p.State.Text = t.State;
            p.State.Foreground = Ui.Brush(t.StateColor);
            p.Value.Text = t.Value;
            p.Note.Text = t.Note;
            SetBar(t);
        }
    }

    bool stopped;

    public void Stop()
    {
        if (stopped) return;
        stopped = true;
        Hw.Changed -= Refresh;
        Live.Updated -= Refresh;
        Live.Release();
    }
}
