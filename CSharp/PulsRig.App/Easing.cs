using System.Windows;
using System.Windows.Media.Animation;

namespace PulsRig.App;

// cubic-bezier(x1, y1, x2, y2) aus dem Entwurf; EasingMode bleibt EaseIn, damit die Kurve unverändert gilt
abstract class CubicBezierEase : EasingFunctionBase
{
    protected CubicBezierEase() => EasingMode = EasingMode.EaseIn;
    protected abstract (double X1, double Y1, double X2, double Y2) Points { get; }

    protected override double EaseInCore(double t)
    {
        var (x1, y1, x2, y2) = Points;
        // x(s) = t nach s lösen (Newton), dann y(s)
        var s = t;
        for (var i = 0; i < 8; i++)
        {
            var dx = DBez(s, x1, x2);
            if (Math.Abs(dx) < 1e-6) break;
            s = Math.Clamp(s - (Bez(s, x1, x2) - t) / dx, 0, 1);
        }
        return Bez(s, y1, y2);
    }

    static double Bez(double s, double a, double b) => 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s;
    static double DBez(double s, double a, double b) => 3 * (1 - s) * (1 - s) * a + 6 * (1 - s) * s * (b - a) + 3 * s * s * (1 - b);
}

// Seitenwechsel und Einblenden: cubic-bezier(.2,.8,.2,1)
sealed class PageEase : CubicBezierEase
{
    protected override (double, double, double, double) Points => (0.2, 0.8, 0.2, 1);
    protected override Freezable CreateInstanceCore() => new PageEase();
}

// Lichtwellen und Funken: cubic-bezier(.2,.7,.3,1)
sealed class WaveEase : CubicBezierEase
{
    protected override (double, double, double, double) Points => (0.2, 0.7, 0.3, 1);
    protected override Freezable CreateInstanceCore() => new WaveEase();
}
