using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace PulsRig.App;

// Fensterknöpfe oben rechts im Stil der Reihe Q:
// Minimieren – der Strich leuchtet lila auf und streckt sich; Schließen – Beere-Fläche, das X dreht sich um 90°.
// Bei „Bewegung aus“ wechseln nur die Farben, ohne Animation.
public partial class MainWindow
{
    static readonly Color FkLeise = Color.FromRgb(0xA3, 0x97, 0xB5);
    static readonly Color FkLila = Color.FromRgb(0x8C, 0x6B, 0xD6);
    static readonly Color FkPink = Color.FromRgb(0xC0, 0x60, 0x8F);

    void Fensterknopf_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not Button b || b.Content is not Path p || p.Tag is "fertig") return;
        p.Tag = "fertig";
        var close = b == CloseButton;

        var stroke = new SolidColorBrush(FkLeise);
        p.Stroke = stroke;
        var rotate = new RotateTransform(0);
        var scale = new ScaleTransform(1, 1);
        p.RenderTransform = new TransformGroup { Children = { scale, rotate } };
        var glow = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 0, Color = close ? FkPink : FkLila, Opacity = 0 };
        p.Effect = glow;

        // Fläche: Minimieren dunkles Lila mit Rand, Schließen Verlauf Lila→Beere
        var back = close
            ? new LinearGradientBrush(Color.FromRgb(0x6D, 0x43, 0xC9), Color.FromRgb(0xA8, 0x32, 0x6F), 0) { Opacity = 0 }
            : (Brush)new SolidColorBrush(Color.FromArgb(0x2E, 0x8C, 0x6B, 0xD6)) { Opacity = 0 };
        var rim = new SolidColorBrush(close ? Color.FromArgb(0x70, 0xC0, 0x60, 0x8F) : Color.FromArgb(0x60, 0x8C, 0x6B, 0xD6)) { Opacity = 0 };
        b.Background = back;
        b.BorderBrush = rim;

        void Go(bool on)
        {
            var t = Bewegung.Time(on ? 240 : 200);
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            DoubleAnimation A(double to) => new(to, t) { EasingFunction = ease };
            back.BeginAnimation(Brush.OpacityProperty, A(on ? 1 : 0));
            rim.BeginAnimation(Brush.OpacityProperty, A(on ? 1 : 0));
            stroke.BeginAnimation(SolidColorBrush.ColorProperty,
                new ColorAnimation(on ? (close ? Colors.White : Color.FromRgb(0xD8, 0xC8, 0xFF)) : FkLeise, t) { EasingFunction = ease });
            glow.BeginAnimation(DropShadowEffect.OpacityProperty, A(on ? 0.9 : 0));
            if (Bewegung.Off)
            {
                rotate.BeginAnimation(RotateTransform.AngleProperty, null);
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, null);
                return;
            }
            if (close)
                rotate.BeginAnimation(RotateTransform.AngleProperty,
                    new DoubleAnimation(on ? 90 : 0, Bewegung.Time(320)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 } });
            else
                scale.BeginAnimation(ScaleTransform.ScaleXProperty,
                    new DoubleAnimation(on ? 1.45 : 1, Bewegung.Time(260)) { EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.5 } });
        }

        b.MouseEnter += (_, _) => Go(true);
        b.MouseLeave += (_, _) => Go(false);
        b.PreviewMouseLeftButtonDown += (_, _) => { if (!Bewegung.Off) scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.8, 1, Bewegung.Time(180))); };
    }
}
