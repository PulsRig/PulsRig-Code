using System.Windows;
using System.Windows.Media;

namespace PulsRig.App;

// Live-Verlauf, der flüssig läuft: die Messung liefert einmal je Sekunde einen Wert, die Linie gleitet in der Zeit bis
// zum nächsten Wert Bild für Bild um einen Schritt nach links (CompositionTarget.Rendering), der neue Punkt schiebt sich
// von rechts herein. Gezeichnet wird direkt (OnRender) ohne Leuchteffekt; der Schein ist eine breite, blasse Linie
// darunter, die nichts extra kostet. Dasselbe Element bleibt über alle Takte stehen, nur die Werte wechseln.
sealed class Livelinie : FrameworkElement
{
    double[] values = Array.Empty<double>();
    DateTime pushed = DateTime.MinValue;
    DateTime last = DateTime.MinValue;
    TimeSpan step = TimeSpan.FromSeconds(1);
    bool rendering;
    readonly Pen line, glow;
    readonly Brush? fill;
    public double Low { get; set; }
    public double High { get; set; } = 100;
    // Fenster: so viele Werte passen in die Breite (fehlende stehen links leer)
    public int Window { get; set; } = Live.Keep;

    public Livelinie(string color, string? light = null, bool area = true, double thickness = 2)
    {
        line = new Pen(Ui.Brush(light ?? color), thickness) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        line.Freeze();
        glow = new Pen(Ui.Brush("#33" + color.TrimStart('#')), thickness + 5) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        glow.Freeze();
        if (area)
        {
            fill = new LinearGradientBrush(Ui.Hex("#59" + color.TrimStart('#')), Ui.Hex("#00" + color.TrimStart('#')), 90);
            fill.Freeze();
        }
        ClipToBounds = true;
        Loaded += (_, _) => Run(true);
        Unloaded += (_, _) => Run(false);
    }

    void Run(bool on)
    {
        if (on == rendering) return;
        rendering = on;
        if (on) CompositionTarget.Rendering += Frame;
        else CompositionTarget.Rendering -= Frame;
    }

    // neue Messreihe; tick ist der Takt der Messung (Live.Tick): nur bei einem neuen Takt gleitet die Linie, sonst steht sie
    long tick = -1;
    public void Set(IReadOnlyList<double> next, long at)
    {
        var now = DateTime.Now;
        var added = at != tick && tick >= 0 && next.Count > 0;
        tick = at;
        if (added && last != DateTime.MinValue)
        {
            var gap = now - last;
            if (gap > TimeSpan.FromMilliseconds(300) && gap < TimeSpan.FromSeconds(5)) step = gap;
        }
        pushed = added ? now : DateTime.MinValue;
        if (added) last = now;
        values = next.ToArray();
        InvalidateVisual();
    }

    double Progress => pushed == DateTime.MinValue ? 1 : Math.Clamp((DateTime.Now - pushed) / step, 0, 1);

    void Frame(object? sender, EventArgs e)
    {
        if (pushed == DateTime.MinValue) return;
        InvalidateVisual();
        if (Progress >= 1) pushed = DateTime.MinValue;
    }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        var n = values.Length;
        if (n < 2 || w <= 0 || h <= 0) return;
        // Abstand zweier Werte; der jüngste steht bei p = 1 am rechten Rand, bei p = 0 einen Schritt weiter rechts
        var dx = w / Math.Max(Window - 2, 1);
        var p = Progress;
        double Y(double v) => h - 2 - (Math.Clamp(v, Low, High) - Low) / Math.Max(High - Low, 1e-9) * (h - 6);
        var points = new Point[n];
        for (var i = 0; i < n; i++) points[i] = new Point(w - (n - 1 - i) * dx + (1 - p) * dx, Y(values[i]));

        var stroke = new StreamGeometry();
        using (var g = stroke.Open())
        {
            g.BeginFigure(points[0], false, false);
            g.PolyLineTo(points.Skip(1).ToList(), true, true);
        }
        stroke.Freeze();
        if (fill != null)
        {
            var area = new StreamGeometry();
            using (var g = area.Open())
            {
                g.BeginFigure(new Point(points[0].X, h), true, true);
                g.PolyLineTo(points.Append(new Point(points[^1].X, h)).ToList(), false, true);
            }
            area.Freeze();
            dc.DrawGeometry(fill, null, area);
        }
        dc.DrawGeometry(null, glow, stroke);
        dc.DrawGeometry(null, line, stroke);
    }
}
