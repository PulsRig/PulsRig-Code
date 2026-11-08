using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PulsRig.App;

// Ring-Animation aus dem Nova-HUD (frame() in hud.html), Bild für Bild über OnRender gezeichnet: außen zwei feine Ringe und
// der gezackte Puls-Bogen mit Lichtpunkt, im Knopf (Sphere) die rotierende Partikel-Kugel. Kein DropShadowEffect: das
// Glühen ist ein breiter, blasser Strich unter dem feinen und ein radialer Verlauf um den Punkt. Die Partikel-Kugel
// wird als ein Bild gerechnet (DrawSphere).
public sealed class NovaRing : FrameworkElement
{
    static readonly Color Lila = Color.FromRgb(109, 67, 201), Beere = Color.FromRgb(168, 50, 111), Hell = Color.FromRgb(177, 159, 224);
    // Maß des HUD: der Knopf hat dort den Radius 0,29 W, hier 76
    const double W = 262, C = 120, Steps = 90, Band = W * .02 - 1.5;
    const int N = 520, Tones = 8, Alphas = 16;
    static readonly (double X, double Y, double Z, double Ph)[] Points = Build();
    static readonly Pen[] Rings =
    {
        Frozen(new Pen(new SolidColorBrush(Color.FromArgb(56, 90, 70, 130)), 1)),
        Frozen(new Pen(new SolidColorBrush(Color.FromArgb(31, 90, 70, 130)), 1)),
    };
    static readonly Brush Glow = Frozen(new RadialGradientBrush(new GradientStopCollection
        { new(Color.FromArgb(255, 255, 255, 255), 0), new(Color.FromArgb(110, 230, 220, 255), 0.3), new(Color.FromArgb(0, 177, 159, 224), 1) }));

    public bool Sphere { get; init; }
    double s, energy, sweep;

    public void Update(double time, double energy, double sweep)
    {
        s = time; this.energy = energy; this.sweep = sweep;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (Sphere) DrawSphere(dc); else DrawRing(dc);
    }

    void DrawRing(DrawingContext dc)
    {
        dc.DrawEllipse(null, Rings[0], new Point(C, C), W * .4, W * .4);
        dc.DrawEllipse(null, Rings[1], new Point(C, C), W * .36, W * .36);

        double a0 = Math.PI * .58 + sweep, span = 1.25 + energy * 1.3, R = W * .38;
        var geometry = new StreamGeometry();
        using (var g = geometry.Open())
        {
            for (var i = 0; i <= Steps; i++)
            {
                double f = i / Steps, a = a0 + f * span;
                var jag = (Math.Sin(f * 61 + s * 6) * .6 + Math.Sin(f * 23 - s * 3)) * (2.5 + energy * 12) * Math.Sin(f * Math.PI);
                var spike = Math.Pow(Math.Max(0, Math.Sin(f * 9 + s * 2)), 14) * (4 + energy * 16) * (i % 2 == 1 ? 1 : -.6);
                // weich begrenzt, damit der Bogen zwischen den beiden feinen Ringen bleibt (0,36 W bis 0,4 W)
                var r = R + Band * Math.Tanh((jag + spike) / Band);
                var p = new Point(C + Math.Cos(a) * r, C + Math.Sin(a) * r);
                if (i == 0) g.BeginFigure(p, false, false); else g.LineTo(p, true, true);
            }
        }
        geometry.Freeze();
        var start = new Point(C + Math.Cos(a0) * R, C + Math.Sin(a0) * R);
        var end = new Point(C + Math.Cos(a0 + span) * R, C + Math.Sin(a0 + span) * R);
        var line = new LinearGradientBrush(Color.FromArgb(0, Lila.R, Lila.G, Lila.B), Color.FromArgb(242, Hell.R, Hell.G, Hell.B), start, end)
            { MappingMode = BrushMappingMode.Absolute };
        var halo = new LinearGradientBrush(Color.FromArgb(0, Lila.R, Lila.G, Lila.B), Color.FromArgb(45, Lila.R, Lila.G, Lila.B), start, end)
            { MappingMode = BrushMappingMode.Absolute };
        dc.DrawGeometry(null, new Pen(halo, 4) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, geometry);
        dc.DrawGeometry(null, new Pen(line, 1.3) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, geometry);

        dc.DrawEllipse(Glow, null, end, 9, 9);
        dc.DrawEllipse(Brushes.White, null, end, 2.6, 2.6);
    }

    // Die Kugel entsteht in einem eigenen Bild (WriteableBitmap, in Bildschirmpixeln) statt aus 520 einzelnen DrawEllipse:
    // so geht je Bild nur ein Befehl an WPF. Jeder Punkt wird mit weicher Kante (Abdeckung je Pixel) eingemischt,
    // Farbe und Deckkraft in denselben Stufen wie zuvor.
    WriteableBitmap? bitmap;
    int[] pixels = [];
    double scale = 1;

    void DrawSphere(DrawingContext dc)
    {
        const double K = 76, SR = K * .82;
        var dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
        var size = (int)Math.Ceiling(2 * K * dpi);
        if (bitmap is null || bitmap.PixelWidth != size)
        {
            bitmap = new WriteableBitmap(size, size, 96 * dpi, 96 * dpi, PixelFormats.Pbgra32, null);
            pixels = new int[size * size];
            scale = dpi;
        }
        Array.Clear(pixels);
        double clip = (K - 3) * scale, cx = K * scale;
        double rot = s * (.2 + energy * 2.7), cr = Math.Cos(rot), sr = Math.Sin(rot), ct = Math.Cos(.35), st = Math.Sin(.35);
        foreach (var (x0, y0, z0, ph) in Points)
        {
            var w = 1 + energy * .2 * Math.Sin(ph * 3 + s * 5 + y0 * 6);
            double x = (x0 * cr - z0 * sr) * w, z = (x0 * sr + z0 * cr) * w, y = y0 * w;
            var y2 = y * ct - z * st; z = y * st + z * ct; y = y2;
            double d = Math.Clamp((z + 1.3) / 2.3, 0, 1), m = Math.Clamp((x + 1) / 2, 0, 1);
            var alpha = Math.Min(1, (.04 + d * .3) * (.5 + energy * 1.4));
            var r = (.45 + d * 1.05) * scale;
            var tone = (int)(m * (Tones - 1) + .5) / (Tones - 1.0);
            Dot(cx + x * SR * scale, cx + y * SR * scale, r, (int)(alpha * (Alphas - 1) + .5) / (Alphas - 1.0),
                Lila.R + (Beere.R - Lila.R) * tone, Lila.G + (Beere.G - Lila.G) * tone, Lila.B + (Beere.B - Lila.B) * tone, cx, clip, size);
        }
        bitmap.WritePixels(new Int32Rect(0, 0, size, size), pixels, size * 4, 0);
        dc.DrawImage(bitmap, new Rect(0, 0, size / scale, size / scale));
    }

    void Dot(double px, double py, double r, double a, double cR, double cG, double cB, double c, double clip, int size)
    {
        int x0 = Math.Max(0, (int)(px - r - 1)), x1 = Math.Min(size - 1, (int)(px + r + 1));
        int y0 = Math.Max(0, (int)(py - r - 1)), y1 = Math.Min(size - 1, (int)(py + r + 1));
        // kleine Punkte nicht unter einem halben Pixel Radius, damit sie nicht flackern
        var rr = Math.Max(r, .5);
        for (var y = y0; y <= y1; y++)
            for (var x = x0; x <= x1; x++)
            {
                double fx = x + .5, fy = y + .5;
                double dx = fx - c, dy = fy - c, edge = clip - Math.Sqrt(dx * dx + dy * dy) + .5;
                if (edge <= 0) continue;
                dx = fx - px; dy = fy - py;
                var cov = Math.Clamp(rr - Math.Sqrt(dx * dx + dy * dy) + .5, 0, 1) * Math.Min(1, edge) * a;
                if (cov <= 0) continue;
                var i = y * size + x;
                var o = pixels[i];
                double k = 1 - cov;
                int A = (int)(cov * 255 + ((o >> 24) & 255) * k + .5), R = (int)(cov * cR + ((o >> 16) & 255) * k + .5),
                    G = (int)(cov * cG + ((o >> 8) & 255) * k + .5), B = (int)(cov * cB + (o & 255) * k + .5);
                pixels[i] = A << 24 | R << 16 | G << 8 | B;
            }
    }

    static (double, double, double, double)[] Build()
    {
        var random = new Random(7);
        var points = new (double, double, double, double)[N];
        for (var i = 0; i < N; i++)
        {
            double y = 1 - i / (N - 1.0) * 2, r = Math.Sqrt(1 - y * y), t = i * 2.39996;
            points[i] = (Math.Cos(t) * r, y, Math.Sin(t) * r, random.NextDouble() * 6.28);
        }
        return points;
    }

    static T Frozen<T>(T f) where T : Freezable { f.Freeze(); return f; }
}
