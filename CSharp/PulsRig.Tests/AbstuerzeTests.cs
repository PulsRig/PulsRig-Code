using PulsRig.Core;

namespace PulsRig.Tests;

public class AbstuerzeTests
{
    static Vorfall At(int day, int hour = 12, uint code = 0) => new() { When = new DateTime(2026, 10, day, hour, 0, 0), Code = code };

    [Theory]
    [InlineData(0x7Eu, "0x7E", "driver")]
    [InlineData(0x1000007Eu, "0x7E", "driver")]
    [InlineData(0x116u, "0x116", "graphics")]
    [InlineData(0x124u, "0x124", "hardware")]
    [InlineData(0x1Au, "0x1A", "memory")]
    [InlineData(0xEFu, "0xEF", "disk")]
    [InlineData(0x999u, "0x999", "unknown")]
    [InlineData(0xFFFFFFFFu, "0xFFFFFFF", "unknown")]
    public void Fehlercode(uint code, string hex, string kind)
    {
        var c = Abstuerze.Check(code);
        Assert.Equal(hex, c.Hex);
        Assert.Equal(kind, c.Kind);
    }

    [Theory]
    [InlineData("0x0000007e", 0x7Eu)]
    [InlineData("0x00000000000000d1", 0xD1u)]
    [InlineData("278", 278u)]
    [InlineData("", 0u)]
    [InlineData("abc", 0u)]
    public void CodeAusDemEreignis(string text, uint expected) => Assert.Equal(expected, Abstuerze.ParseCode(text));

    [Theory]
    [InlineData("nvwgf2umx.dll", true)]
    [InlineData("amdxx64.dll", true)]
    [InlineData("igd10iumd64.dll", true)]
    [InlineData("nvcuda64.dll", true)]
    [InlineData("ntdll.dll", false)]
    [InlineData("nvspcap64.dll", false)]
    public void ModulImGrafiktreiber(string module, bool expected) => Assert.Equal(expected, Abstuerze.IsGraphicsModule(module));

    [Fact]
    public void BluescreenNichtDoppelt()
    {
        var blue = new List<Vorfall> { At(20, 10) };
        Assert.True(Abstuerze.HasNearBlue(blue, new DateTime(2026, 10, 20, 10, 10, 0)));
        Assert.False(Abstuerze.HasNearBlue(blue, new DateTime(2026, 10, 20, 10, 20, 0)));
    }

    [Fact]
    public void BefundeZusammengefasst()
    {
        var d = new AbsturzDaten
        {
            Blue = { At(24, 10, 0x116), At(20, 9, 0x1000007E), At(12, 22, 0x116) },
            Off = { new Vorfall { When = new DateTime(2026, 10, 22, 1, 2, 0), Button = true } },
            Tdr = { At(23) },
            GpuVersion = "32.0.15.6614",
        };
        var f = Abstuerze.Findings(d, backups: true);
        Assert.Equal(new[] { "Bluescreen: Grafiktreiber reagierte nicht mehr", "Bluescreen: Ein Treiber hat einen Fehler nicht abgefangen", "Grafiktreiber ist 1-mal ausgesetzt", "Vorige Treiberfassung zurückholen", "PC ist plötzlich ausgegangen" },
            f.Select(x => x.Title));
        Assert.StartsWith("2-mal, zuletzt 24.10. 10:00 Uhr · Code 0x116", f[0].Sub);
        Assert.Contains("am Ausschalter ausgemacht", f[4].Sub);
        Assert.DoesNotContain(Abstuerze.Findings(d, backups: false), x => x.Hint);
    }

    [Fact]
    public void KarteUndRuhigeTage()
    {
        var today = new DateTime(2026, 10, 25);
        var calm = new AbsturzDaten();
        Assert.Equal("in Ordnung", Abstuerze.Card(calm, today)!.Tone == "good" ? "in Ordnung" : "");
        Assert.Null(Abstuerze.CalmDays(calm, today));
        Assert.Null(Abstuerze.Card(new AbsturzDaten { Log = false }, today));
        var d = new AbsturzDaten { Blue = { At(6) }, Tdr = { At(20) } };
        var card = Abstuerze.Card(d, today)!;
        Assert.Equal("1 Bluescreen", card.Text);
        Assert.Equal(new[] { 5, 19 }, card.Days);
        // Grafikaussetzer zählen nicht als Absturz
        Assert.Equal(19, Abstuerze.CalmDays(d, today));
    }

    [Fact]
    public void TempoLangsam()
    {
        Assert.True(Laufwerkstempo.Slow(20, 100));
        Assert.True(Laufwerkstempo.Slow(100, 10));
        Assert.False(Laufwerkstempo.Slow(150, 120));
        Assert.Equal(1.0, Laufwerkstempo.Bar(5000, 3500));
        Assert.Equal(0.0, Laufwerkstempo.Bar(0, 3500));
    }
}
