using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PulsRig.App;

// Seiten, die in späteren Blöcken von Schritt 8 entstehen
sealed class Platzhalter : Border
{
    public Platzhalter(string name)
    {
        Style = (Style)Application.Current.FindResource("Kachel");
        BorderBrush = (Brush)Application.Current.FindResource("KarteRand");
        Background = (Brush)Application.Current.FindResource("Karte");
        Child = new TextBlock
        {
            Text = name + " – kommt in einem späteren Block",
            Foreground = (Brush)Application.Current.FindResource("Leise"),
            FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
    }
}
