using PulsRig.Core;

namespace PulsRig.Tests;

public class AufzeichnungTests
{
    static Spielsitzung Session(double gpuTemp, int rows)
    {
        var lines = new List<string> { "Spiel=cs2;Beginn=2026-10-18T10:57:33", "Sekunde;CpuTemp;GpuTemp;GpuTakt;GpuLast" };
        for (var i = 0; i < rows; i++) lines.Add($"{i * 5};70.5;{gpuTemp.ToString(System.Globalization.CultureInfo.InvariantCulture)};1900;95");
        return Aufzeichnung.Read(lines);
    }

    [Fact]
    public void KopfUndSpalten()
    {
        var s = Session(60, 4);
        Assert.Equal("cs2", s.Game);
        Assert.Equal(new DateTime(2026, 10, 18, 10, 57, 33), s.Begin);
        Assert.Equal(15, s.Seconds);
        Assert.Equal(70.5, s.Column("CpuTemp")![0]);
    }

    [Fact]
    public void KuehlUndHeiss()
    {
        Assert.Equal("good", Aufzeichnung.Summary(Session(60, 30)).Tone);
        var hot = Aufzeichnung.Summary(Session(85, 30));   // 2,5 Minuten über 83 °C
        Assert.Equal("warn", hot.Tone);
        Assert.Contains(hot.Lines, l => l.Contains("über 83 °C"));
    }

    [Fact]
    public void Drosseln()
    {
        var clock = new List<double> { 1900, 1900, 1900, 1900, 1000, 1000, 1900, 1900, 1900, 1900 };
        var load = Enumerable.Repeat(95.0, 10).ToList();
        Assert.Equal(0.2, Aufzeichnung.ThrottleShare(clock, load, 90, 0.85), 3);
    }

    [Fact]
    public void Dauer() { Assert.Equal("1:05 Std.", Aufzeichnung.Duration(3900)); Assert.Equal("12 Min.", Aufzeichnung.Duration(720)); }
}
