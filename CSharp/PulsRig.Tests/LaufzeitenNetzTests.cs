using PulsRig.Core;

namespace PulsRig.Tests;

public class LaufzeitenTests
{
    static readonly string[] Names =
    {
        "Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.30501",
        "Microsoft Visual C++ 2013 Redistributable (x86) - 12.0.40664",
        "Microsoft Visual C++ 2013 x64 Minimum Runtime - 12.0.40664",      // Teilpaket, zählt nicht
        "Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.40.33810",
    };
    static readonly string[] Versions = { "12.0.30501.0", "12.0.40664.0", "12.0.40664.0", "14.40.33810.0" };
    const string V2013 = @"Visual C\+\+ 2013 Redistributable";

    [Fact]
    public void Veraltet()
    {
        var status = Laufzeiten.Evaluate(Names, Versions, V2013, true, "12.0.40664");
        Assert.Equal("veraltet", status.Status);
        Assert.Equal("12.0.30501.0", status.Version);
    }

    [Fact]
    public void Aktuell() => Assert.Equal("vorhanden", Laufzeiten.Evaluate(Names, Versions, V2013, false, "12.0.40664").Status);

    [Fact]
    public void Fehlt() => Assert.Equal("fehlt", Laufzeiten.Evaluate(Names, Versions, @"Visual C\+\+ 2015-2022|Visual C\+\+ \(2015", false, null).Status);

    [Fact]
    public void OhneBekannteLetzteFassung() => Assert.Equal("vorhanden", Laufzeiten.Evaluate(Names, Versions, @"Visual C\+\+ (2015|2017|2019|2022|v14)\S* Redistributable", true, null).Status);

    [Fact]
    public void KaputteVersion()
    {
        var status = Laufzeiten.Evaluate(new[] { "Microsoft Visual C++ 2012 Redistributable (x64)" }, new[] { "kaputt" }, @"Visual C\+\+ 2012 Redistributable", true, "11.0.61030");
        Assert.Equal("vorhanden", status.Status);
        Assert.Equal("", status.Version);
    }
}

public class NetzPruefungTests
{
    [Fact]
    public void Adressen()
    {
        Assert.True(Netzwerk.IsUsableAddress("192.168.178.20"));
        Assert.False(Netzwerk.IsUsableAddress("169.254.10.3"));
        Assert.False(Netzwerk.IsUsableAddress(""));
        Assert.True(Netzwerk.IsDefaultRoute("0.0.0.0/0"));
        Assert.False(Netzwerk.IsDefaultRoute("192.168.178.0/24"));
        Assert.True(Netzwerk.IsDhcp((byte)1));
        Assert.True(Netzwerk.IsDhcp("Enabled"));
        Assert.False(Netzwerk.IsDhcp(0));
    }

    [Fact]
    public void Antworten()
    {
        Assert.True(Netzwerk.IsDnsAnswer(new[] { "Server:  fritz.box", "Address:  192.168.178.1", "", "Name:    www.microsoft.com" }));
        Assert.False(Netzwerk.IsDnsAnswer(new[] { "Server:  fritz.box", "*** Zeitüberschreitung" }));
        Assert.True(Netzwerk.IsConnectTest("Microsoft Connect Test"));
        Assert.False(Netzwerk.IsConnectTest("<html>Bitte im Hotel-WLAN anmelden</html>"));
    }

    [Fact]
    public void GeschlossenerPort() => Assert.False(Netzwerk.TcpPort("127.0.0.1", 1, 500));
}
