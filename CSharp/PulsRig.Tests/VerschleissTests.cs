using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class VerschleissTests
{
    static Messpunkt P(string d, double gt, double gw, double gf = 50) => new() { D = d, Src = "Spiel", GT = gt, GW = gw, GF = gf };

    [Fact]
    public void MedianWieImSkript()
    {
        Assert.Equal(2.5, Verschleiss.Median(new double?[] { 4, 1, null, 2, 3, double.NaN }));
        Assert.True(double.IsNaN(Verschleiss.Median(Array.Empty<double?>())));
    }

    [Fact]
    public void ZuWenigUndZuKurz()
    {
        Assert.Equal("zu wenig Daten", Verschleiss.Trend(new[] { P("2026-10-01", 70, 200) }, 'G').State);
        var shortSpan = new[] { P("2026-10-01", 70, 200), P("2026-10-02", 70, 200), P("2026-10-03", 70, 200), P("2026-10-04", 70, 200) };
        var t = Verschleiss.Trend(shortSpan, 'G');
        Assert.Equal("sammelt noch", t.State);
        Assert.Contains("ab dem 22.10.", t.Text);
    }

    [Fact]
    public void WaermerBeiGleicherLeistungLaesstNach()
    {
        var points = new[] { P("2026-09-01", 70, 200), P("2026-09-02", 70, 200), P("2026-10-01", 77, 200, 70), P("2026-10-02", 77, 200, 70) };
        var t = Verschleiss.Trend(points, 'G');
        Assert.Equal(("warn", "lässt nach"), (t.Tone, t.State));
        Assert.Contains("7 °C wärmer", t.Text);
        Assert.Contains("Lüfter drehen 20 % schneller", t.Text);
        Assert.Equal(("lässt nach", "warn"), Verschleiss.CoolingState(points));
    }

    [Fact]
    public void ProzessorAnDerGrenzeZaehltDenTakt()
    {
        Messpunkt C(string d, double cc) => new() { D = d, Src = "Spiel", CT = 90, CW = 100, CC = cc };
        var t = Verschleiss.Trend(new[] { C("2026-09-01", 4500), C("2026-09-02", 4500), C("2026-10-01", 4200), C("2026-10-02", 4200) }, 'C');
        Assert.Equal("warn", t.Tone);
        Assert.Contains("4.200 MHz", t.Text);
    }

    [Fact]
    public void SsdLebensdauer()
    {
        var s = Verschleiss.Ssd("Samsung", new[] { ("2025-10-25", 10), ("2026-10-25", 15) });
        Assert.Equal(("good", "über 10 Jahre"), (s.Tone, s.State));
        Assert.Contains("rund 5,0 Punkte im Jahr", s.Text);
        var young = Verschleiss.Ssd("Neu", new[] { ("2026-10-20", 0), ("2026-10-25", 0) });
        Assert.Equal("0 %", young.State);
        Assert.Contains("bisher 5 Tage", young.Text);
    }

    [Fact]
    public void SpielsitzungWirdZuMesspunkt()
    {
        var lines = new List<string> { "Spiel=cs2;Beginn=2026-10-24T22:15:23", "Sekunde;GpuTemp;GpuLast;GpuWatt;GpuLuefter;CpuTemp;CpuTakt;CpuWatt" };
        for (var s = 0; s <= 1200; s += 5) lines.Add(s + ";70;95;250;55;75;4300;80");
        var p = Verschleiss.Point(Aufzeichnung.Read(lines), "x.csv");
        Assert.Equal(("Spiel", "cs2", 70.0, 4300.0, 10.0), (p.Src, p.Name, p.GT!.Value, p.CC!.Value, p.Min!.Value));
        Assert.Equal("kurz", Verschleiss.Point(Aufzeichnung.Read(lines.Take(50).ToList()), "y.csv").Src);
    }
}
