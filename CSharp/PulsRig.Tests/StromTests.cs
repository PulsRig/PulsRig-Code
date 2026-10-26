using PulsRig.Core;

namespace PulsRig.Tests;

public class StromTests
{
    [Fact]
    public void GemessenUndGeschaetzt()
    {
        var p = Strom.Parts(200, 80, 50);
        Assert.Equal((200 + 80 + 35) / 0.88, p.Total, 3);
        Assert.True(p.GpuMeasured && p.CpuMeasured);
        var q = Strom.Parts(null, null, null);   // wie PowerShell: 20 W Grafik, Prozessor bei 10 % Last
        Assert.Equal(20, q.Gpu);
        Assert.Equal(65 * (0.15 + 0.85 * 0.1), q.Cpu, 6);
    }

    [Fact]
    public void Jahreskosten() => Assert.Equal(204.4, Strom.YearEuro(400, 4, 0.35), 1);

    [Fact]
    public void AufzeichnungOhneLuecken()
    {
        var r = Strom.Recording(new double[] { 0, 1, 2, 200 }, new double[] { 100, 100, 100, 100 }, new double[] { 50, 50, 50, 50 }, new double[] { 40, 40, 40, 40 })!.Value;
        Assert.Equal((100 + 50 + 35) / 0.88, r.Average, 3);   // die Lücke von 198 s zählt nicht
        Assert.True(r.GpuMeasured);
    }
}

public class PingTests
{
    static Pingziel T(string kind, int lost, params double[] times) => new() { Kind = kind, Sent = 20, Lost = lost, Times = times.ToList() };

    [Fact]
    public void RouterStrenger()
    {
        Assert.Equal("good", Ping.Tone(T("home", 0, 1, 2, 1)));
        Assert.Equal("warn", Ping.Tone(T("home", 1, 1, 2, 1)));       // schon ein verlorenes Paket zu Hause fällt auf
        Assert.Equal("good", Ping.Tone(T("net", 0, 15, 16, 15)));
        Assert.Equal("warn", Ping.Tone(T("net", 0, 45, 46)));
        Assert.Equal("bad", Ping.Tone(T("net", 0, 90)));
        Assert.Equal("bad", Ping.Tone(T("net", 20)));                  // keine Antwort
    }

    [Fact]
    public void Schwankung() => Assert.Equal(10, T("net", 0, 10, 20, 10).Jitter);
}
