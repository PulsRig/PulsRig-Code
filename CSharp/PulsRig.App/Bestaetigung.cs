using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using PulsRig.Core;

namespace PulsRig.App;

static class Bestaetigung
{
    // reine Hinweise: nur ein Knopf, „Abbrechen“ daneben wäre dasselbe
    static readonly string[] InfoOnly = { "Verstanden", "Schließen", "OK" };

    // Rückfrage im Stil der Reihe Q; true nur bei „Ja“
    public static bool Ask(FrameworkElement owner, string title, string text, string yes)
    {
        var panel = new StackPanel { Width = 440 };
        panel.Children.Add(new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold, Foreground = Ui.Res("Text"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(new TextBlock { Text = text, FontSize = 13, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 19.5, Margin = new Thickness(0, 10, 0, 20) });
        return Show(owner, panel, InfoOnly.Contains(yes) ? new[] { (yes, true) } : new[] { ("Abbrechen", false), (yes, true) });
    }

    // Über PulsRig: Zeichen mit Puls, Name und Fassung, Kurzbeschreibung, Zustand als Plaketten, nur „Schließen“
    public static void About(FrameworkElement owner)
    {
        var panel = new StackPanel { Width = 460 };
        var head = new DockPanel();
        var logo = new Border { Width = 64, Height = 64, CornerRadius = new CornerRadius(20), Background = (Brush)Application.Current.FindResource("PulsQuer"), Margin = new Thickness(0, 0, 18, 0),
            Effect = Ui.Glow("#A8326F", 28, 0.45),
            Child = new Path { Data = Geometry.Parse("M3 12h4l2-5 4 10 2-5h6"), Stroke = Ui.Brush("#08030E"), StrokeThickness = 2.4, StrokeLineJoin = PenLineJoin.Round,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, Width = 24, Height = 24, Stretch = Stretch.None,
                LayoutTransform = new ScaleTransform(1.4, 1.4), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
        DockPanel.SetDock(logo, Dock.Left);
        head.Children.Add(logo);
        var name = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        name.Children.Add(new TextBlock { Text = "PulsRig", FontSize = 28, FontWeight = FontWeights.SemiBold, Foreground = Ui.Res("Text") });
        name.Children.Add(new TextBlock { Text = "Fassung " + PulsRigInfo.Version, FontSize = 12, FontFamily = Ui.Mono, Foreground = Ui.Res("Leise"), Margin = new Thickness(0, 2, 0, 0) });
        head.Children.Add(name);
        panel.Children.Add(head);

        panel.Children.Add(new TextBlock { Text = "Treiber. Boost. Werkzeuge.", FontSize = 15, FontWeight = FontWeights.SemiBold, Foreground = (Brush)Application.Current.FindResource("PulsQuer"), Margin = new Thickness(0, 22, 0, 0) });
        panel.Children.Add(new TextBlock { Text = "Sucht neuere Treiber, beschleunigt den PC fürs Spielen und bringt Werkzeuge für Treiber, Geräte und Spiele mit. Fehler bitte mit Bericht & Diagnose melden.",
            FontSize = 13, Foreground = Ui.Res("Halbleise"), TextWrapping = TextWrapping.Wrap, LineHeight = 19.5, Margin = new Thickness(0, 6, 0, 0) });

        var chips = new WrapPanel { Margin = new Thickness(0, 18, 0, 22) };
        chips.Children.Add(Chip(App.IsAdmin ? "Adminrechte: Installieren und Reparieren möglich" : "Ohne Adminrechte: nur Scannen", App.IsAdmin ? "#5EE0A0" : "#F2B661"));
        chips.Children.Add(Chip("Quelltext unter GPL-3.0", "#8C6BD6"));
        panel.Children.Add(chips);
        Show(owner, panel, new[] { ("Schließen", true) });
    }

    static Border Chip(string text, string color)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = Ui.Brush(color), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 7, 0) });
        row.Children.Add(Ui.Text(text, 11.5, color));
        return new Border { CornerRadius = new CornerRadius(999), Padding = new Thickness(10, 5, 12, 6), Margin = new Thickness(0, 0, 8, 8), Background = Ui.Alpha(color, "14"),
            BorderBrush = Ui.Alpha(color, "2E"), BorderThickness = new Thickness(1), Child = row };
    }

    static bool Show(FrameworkElement owner, StackPanel panel, (string Label, bool Primary)[] choices)
    {
        var window = new Window { WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ResizeMode = ResizeMode.NoResize,
            SizeToContent = SizeToContent.WidthAndHeight, WindowStartupLocation = WindowStartupLocation.CenterOwner, Owner = Window.GetWindow(owner), ShowInTaskbar = false };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var answer = false;
        foreach (var (label, primary) in choices)
        {
            var b = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 40, MinWidth = 110, Padding = new Thickness(18, 0, 18, 0), Tag = "18", Margin = new Thickness(10, 0, 0, 0),
                Background = primary ? (Brush)Application.Current.FindResource("PulsQuer") : Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(primary ? 0 : 1),
                HorizontalContentAlignment = HorizontalAlignment.Center, VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(label, 13, "Text", bold: true),
                IsCancel = !primary || choices.Length == 1, IsDefault = primary };
            b.Click += (_, _) => { answer = primary; window.Close(); };
            buttons.Children.Add(b);
        }
        panel.Children.Add(buttons);
        window.Content = new Border { CornerRadius = new CornerRadius(24), Background = Ui.Brush("#120A1A"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), Padding = new Thickness(26), Child = panel };
        Texte.Attach(window);
        window.ShowDialog();
        return answer;
    }
}
