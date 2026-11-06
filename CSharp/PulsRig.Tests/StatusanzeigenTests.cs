using PulsRig.Core;
namespace PulsRig.Tests;

public class StatusanzeigenTests
{
    static readonly DateTime Today = new(2026, 10, 29);
    [Fact] public void OhneDatenNichtGruen() => Assert.False(Stabilitaetsanzeige.From(null, Today).Known);
    [Fact] public void TeilprotokollIstUnbekannt()
    {
        var r = Stabilitaetsanzeige.From(new AbsturzDaten { Log = false }, Today);
        Assert.False(r.Known);
        Assert.Empty(r.Days);
        Assert.Equal("–", r.Value);
    }
    [Fact] public void KeineVorfälleIstKeineUnbegrenzteStabilitaetszusage()
    {
        var r = Stabilitaetsanzeige.From(new AbsturzDaten(), Today);
        Assert.Equal("0", r.Value);
        Assert.Equal("Vorfälle / 30 Tage", r.Label);
    }
    [Theory]
    [InlineData(0, "0", "Tage ohne Vorfall")]
    [InlineData(1, "1", "Tag ohne Vorfall")]
    [InlineData(29, "29", "Tage ohne Vorfall")]
    public void GrafikvorfallZaehlt(int days, string value, string label)
    {
        var r = Stabilitaetsanzeige.From(new AbsturzDaten { Tdr = new() { new Vorfall { When = Today.AddDays(-days) } } }, Today);
        Assert.Equal(value, r.Value);
        Assert.Equal(label, r.Label);
        Assert.Contains(days, r.Days);
    }
    [Fact] public void NeuesterVorfallAusAllenQuellen()
    {
        var d = new AbsturzDaten {
            Blue = new() { new Vorfall { When = Today.AddDays(-5) } },
            Off = new() { new Vorfall { When = Today.AddDays(-4) } },
            Apps = new() { new Vorfall { When = Today.AddDays(-2) } } };
        Assert.Equal("2", Stabilitaetsanzeige.From(d, Today).Value);
    }
    [Fact] public void AusserhalbDesFenstersZaehltNicht()
    {
        var d = new AbsturzDaten { Blue = new() { new Vorfall { When = Today.AddDays(-30) }, new Vorfall { When = Today.AddDays(1) } } };
        Assert.Empty(Stabilitaetsanzeige.From(d, Today).Days);
    }
    [Fact] public void UnbekanntIstWederGutNochSchlecht()
    {
        Assert.Equal((6, 0, 1), Spielcheck.Counts(new[] { "good", "good", "good", "good", "good", "good", "" }));
        Assert.Equal((1, 2, 2), Spielcheck.Counts(new[] { "good", "warn", "bad", "", "future" }));
        Assert.Null(Spielcheck.Score(new[] { "" }));
    }
    [Fact] public void BarAdressfensterIstKeinVram()
    {
        var text = Spielcheck.BarDescription(16384);
        Assert.Contains("16 GiB Adressbereich", text);
        Assert.Contains("nicht die Größe", text);
        Assert.DoesNotContain("16 GB", text);
    }
}