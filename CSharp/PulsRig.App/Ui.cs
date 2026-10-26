using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;

namespace PulsRig.App;

// Seiten mit eigener Messung oder eigenem Takt räumen beim Verlassen auf
interface IPage
{
    void Stop();
}

// Bausteine der Reihe Q, die mehrere Seiten brauchen
static class Ui
{
    public static readonly System.Globalization.CultureInfo De = System.Globalization.CultureInfo.GetCultureInfo("de-DE");
    public static Color Hex(string s) => (Color)ColorConverter.ConvertFromString(s);
    public static SolidColorBrush Brush(string s) => new(Hex(s));
    public static Brush Res(string key) => (Brush)Application.Current.FindResource(key);
    public static FontFamily Mono => (FontFamily)Application.Current.FindResource("Mono");

    // Kachelgrund wie linear-gradient(160deg, Farbton, #09060D 75%)
    public static Brush Tint(string tint)
    {
        var brush = new LinearGradientBrush { StartPoint = new Point(0.33, 0), EndPoint = new Point(0.67, 1) };
        brush.GradientStops.Add(new GradientStop(Hex(tint), 0));
        brush.GradientStops.Add(new GradientStop(Hex("#09060D"), 0.75));
        return brush;
    }

    // Farbe mit Deckkraft in Hex wie im Entwurf ("#6D43C9" + "2E")
    public static SolidColorBrush Alpha(string color, string alpha) => Brush("#" + alpha + color.TrimStart('#'));

    public static Border Tile(string color, string tint, Thickness? padding = null)
    {
        var tile = new Border { Style = (Style)Application.Current.FindResource("Kachel"), Background = Tint(tint), BorderBrush = Alpha(color, "2E") };
        if (padding != null) tile.Padding = padding.Value;
        return tile;
    }

    public static TextBlock Text(string text, double size, string? color = null, bool bold = false, bool mono = false)
    {
        var t = new TextBlock { Text = text, FontSize = size, TextTrimming = TextTrimming.CharacterEllipsis };
        if (color != null) t.Foreground = color.StartsWith('#') ? Brush(color) : Res(color);
        if (bold) t.FontWeight = FontWeights.SemiBold;
        if (mono) t.FontFamily = Mono;
        return t;
    }

    // Balken mit Verlauf von der Farbe nach Beere; Anteil 0..1. Mit reuse (ein früher gebauter Balken) gleitet der
    // vorhandene Balken zum neuen Anteil, statt dass ein neuer springt: für Werte, die sich jede Sekunde ändern
    public static Border Bar(double share, string color, double height = 6, string? fill = null, object? reuse = null)
    {
        var part = Math.Clamp(share, 0, 1);
        if (reuse is Border { Tag: double[] old, Child: Border moving } same && same.Height == height)
        {
            old[0] = part;
            moving.Background = fill != null ? Brush(fill) : new LinearGradientBrush(Hex(color), Hex("#A8326F"), 0);
            if (same.ActualWidth > 0)
                moving.BeginAnimation(FrameworkElement.WidthProperty, new DoubleAnimation(same.ActualWidth * part, TimeSpan.FromMilliseconds(700)) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } });
            return same;
        }
        var fillBrush = fill != null ? (Brush)Brush(fill) : new LinearGradientBrush(Hex(color), Hex("#A8326F"), 0);
        var bar = new Border { Height = height, CornerRadius = new CornerRadius(height / 2), Background = fillBrush, HorizontalAlignment = HorizontalAlignment.Left };
        var share0 = new[] { part };
        var track = new Border { Height = height, CornerRadius = new CornerRadius(height / 2), Background = Brush("#10FFFFFF"), Child = bar, Tag = share0 };
        track.SizeChanged += (_, e) => { bar.BeginAnimation(FrameworkElement.WidthProperty, null); bar.Width = e.NewSize.Width * share0[0]; };
        return track;
    }

    // Raster mit Spalten und Reihen gleicher Größe und festem Abstand (Abstand als eigene Spalte/Reihe)
    public static Grid Mosaic(int columns, int rows, double gap)
    {
        var g = new Grid();
        for (var c = 0; c < columns; c++)
        {
            if (c > 0) g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(gap) });
            g.ColumnDefinitions.Add(new ColumnDefinition());
        }
        for (var r = 0; r < rows; r++)
        {
            if (r > 0) g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(gap) });
            g.RowDefinitions.Add(new RowDefinition());
        }
        return g;
    }

    public static void Place(Grid grid, UIElement e, int column, int row, int columnSpan = 1, int rowSpan = 1)
    {
        Grid.SetColumn(e, column * 2);
        Grid.SetRow(e, row * 2);
        Grid.SetColumnSpan(e, columnSpan * 2 - 1);
        Grid.SetRowSpan(e, rowSpan * 2 - 1);
        grid.Children.Add(e);
    }

    // Kacheln kommen nacheinander herein (je 40 ms später), wie beim Öffnen einer Seite im Entwurf
    public static void Arrive(IEnumerable<UIElement> items)
    {
        var i = 0;
        foreach (var item in items)
        {
            item.Opacity = 0;
            item.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, Bewegung.Time(380))
                { BeginTime = Bewegung.Time(40 * i++), EasingFunction = new PageEase() });
        }
    }

    public static void Blink(FrameworkElement e) => ((Storyboard)Application.Current.FindResource("Blinken")).Begin(e, true);

    public static DropShadowEffect Glow(string color, double blur, double opacity = 1) =>
        new() { BlurRadius = blur, ShadowDepth = 0, Color = Hex(color), Opacity = opacity };

    // Größe wie im PowerShell-Programm (Format-DriveSize): ab 1000 GB in TB mit zwei Stellen
    const double GB = 1024.0 * 1024 * 1024;
    public static string Size(double bytes) =>
        bytes >= 1000 * GB ? (bytes / (1024 * GB)).ToString("N2") + " TB" : (bytes / GB).ToString("N0") + " GB";
    public static string Gb(double bytes, string format = "N0") => (bytes / GB).ToString(format) + " GB";
}
