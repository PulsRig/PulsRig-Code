using PulsRig.Core;

namespace PulsRig.Tests;

public class SpielprofilTests
{
    [Fact]
    public void MissingFlagsMeanOn()
    {
        var p = Spielprofil.From(_ => null);
        Assert.True(p.IsDefault);
        Assert.Equal("Alles an", p.Describe());
    }

    [Fact]
    public void StoredFlagsAreRead()
    {
        var p = Spielprofil.From(key => key == "Services" ? false : key == "Record" ? false : null);
        Assert.True(p.PowerPlan);
        Assert.False(p.Services);
        Assert.True(p.Priority);
        Assert.False(p.Record);
        Assert.Equal("Energieplan, Spiel bevorzugen · ohne Dienste anhalten, Aufzeichnen", p.Describe());
    }

    [Fact]
    public void AllOff()
    {
        var p = new Spielprofil();
        foreach (var key in Spielprofil.Keys) p.Set(key, false);
        Assert.Equal("Alles aus", p.Describe());
        Assert.True(p.Get("Unbekannt"));
    }
}
