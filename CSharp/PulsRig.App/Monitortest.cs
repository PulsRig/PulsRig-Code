using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

namespace PulsRig.App;

// Monitor-Test wie PulsRig-Monitor.ps1: Farbflächen im Vollbild für tote und hängende Pixel, Lichthöfe, ungleichmäßige
// Ausleuchtung und Farbstufen, dazu ein Bewegungsbild für Schlieren. Er öffnet sich auf dem Bildschirm, auf dem PulsRig
// steht. Weiter mit Leertaste, Pfeil rechts oder Klick, zurück mit Pfeil links oder Rechtsklick, H zeigt den Hinweis,
// Esc beendet. Geändert wird nichts.
sealed class Monitortest : Window
{
    public static readonly (string Name, string Color, string Hint)[] Screens =
    {
        ("Schwarz", "#000000", "Leuchtende Punkte sind hängende Pixel. Helle Flecken an den Rändern sind Lichthöfe – im dunklen Raum am besten zu sehen."),
        ("Weiß", "#FFFFFF", "Dunkle Punkte sind tote Pixel. Gelbliche oder fleckige Bereiche zeigen eine ungleichmäßige Ausleuchtung."),
        ("Rot", "#FF0000", "Ein Punkt in einer anderen Farbe ist ein defektes Subpixel."),
        ("Grün", "#00FF00", "Ein Punkt in einer anderen Farbe ist ein defektes Subpixel."),
        ("Blau", "#0000FF", "Ein Punkt in einer anderen Farbe ist ein defektes Subpixel."),
        ("Grau", "#7F7F7F", "Wolkige Flecken oder dunklere Ecken zeigen eine ungleichmäßige Ausleuchtung."),
        ("Farbverlauf", "gradient", "Der Verlauf sollte gleichmäßig sein. Deutliche Stufen oder Streifen deuten auf wenig Farbtiefe oder eine falsche Einstellung."),
        ("Bewegung", "motion", "Zieht der Block Schlieren oder einen Schatten hinter sich her? Ruckelt er, läuft der Bildschirm womöglich nicht mit seiner vollen Bildwiederholrate."),
    };

    readonly Rectangle plane = new() { Fill = Brushes.Black };
    readonly Canvas motion = new() { Visibility = Visibility.Collapsed, ClipToBounds = true };
    readonly Border block = new() { Width = 160, Height = 160, Background = Brushes.White, RenderTransform = new TranslateTransform() };
    readonly Border hint;
    readonly TextBlock title = new() { FontSize = 17, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White };
    readonly TextBlock text = new() { FontSize = 14, Foreground = new SolidColorBrush(Color.FromRgb(0xC8, 0xD2, 0xE6)), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) };
    int index;

    public static void Open(Window owner)
    {
        // auf dem Bildschirm, auf dem PulsRig steht: dorthin setzen und dort ganz aufziehen
        var test = new Monitortest { Left = owner.Left + 40, Top = owner.Top + 40, Width = 400, Height = 300 };
        test.Closed += (_, _) => owner.Activate();
        test.Show();
        test.Activate();
    }

    Monitortest()
    {
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        Background = Brushes.Black;
        Cursor = Cursors.None;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Title = "Monitor-Test";
        motion.Children.Add(block);
        var stack = new StackPanel();
        stack.Children.Add(title);
        stack.Children.Add(text);
        stack.Children.Add(new TextBlock { Text = "Leertaste oder Klick: weiter · Pfeil links: zurück · H: Hinweis · Esc: beenden", FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(0x8B, 0x97, 0xB0)), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) });
        hint = new Border { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 60), MaxWidth = 760,
            Padding = new Thickness(22, 16, 22, 16), CornerRadius = new CornerRadius(16), Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x10, 0x18, 0x28)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1), Child = stack };
        var grid = new Grid();
        grid.Children.Add(plane);
        grid.Children.Add(motion);
        grid.Children.Add(hint);
        Content = grid;
        Loaded += (_, _) => { WindowState = WindowState.Maximized; Paint(); };
        KeyDown += (_, e) =>
        {
            switch (e.Key)
            {
                case Key.Space or Key.Right or Key.Enter or Key.PageDown: Step(1); break;
                case Key.Left or Key.Back or Key.PageUp: Step(-1); break;
                case Key.H: ShowHint(); break;
                case Key.Escape: Close(); break;
            }
        };
        MouseLeftButtonUp += (_, _) => Step(1);
        MouseRightButtonUp += (_, _) => Step(-1);
        SizeChanged += (_, _) => { if (Screens[index].Color == "motion") Paint(); };
    }

    void Step(int way)
    {
        var next = index + way;
        if (next < 0) return;
        if (next >= Screens.Length) { Close(); return; }
        index = next;
        Paint();
    }

    void Paint()
    {

        var (name, color, about) = Screens[index];
        var move = (TranslateTransform)block.RenderTransform;
        move.BeginAnimation(TranslateTransform.XProperty, null);
        motion.Visibility = Visibility.Collapsed;
        switch (color)
        {
            case "gradient":
                plane.Fill = new LinearGradientBrush(Colors.Black, Colors.White, 0);
                break;
            case "motion":
                plane.Fill = new SolidColorBrush(Color.FromRgb(64, 64, 64));
                motion.Visibility = Visibility.Visible;
                // der Block gleitet gleichmäßig von links nach rechts und zurück, in der Mitte der Höhe
                var width = Math.Max(800.0, ActualWidth);
                Canvas.SetTop(block, Math.Max(0, (ActualHeight - 160) / 2));
                move.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, width - 160, TimeSpan.FromSeconds(2.2)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
                break;
            default:
                plane.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
                break;
        }
        title.Text = Texte.T((index + 1) + " von " + Screens.Length + ": " + name);
        text.Text = Texte.T(about);
        ShowHint();
    }

    // Hinweis einblenden und nach ein paar Sekunden verblassen lassen, damit er beim Suchen nicht stört
    void ShowHint()
    {
        hint.BeginAnimation(OpacityProperty, null);
        hint.Opacity = 1;
        hint.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(700)) { BeginTime = TimeSpan.FromSeconds(3.5) });
    }
}
