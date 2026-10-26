using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class AkkuTests
{
    const string Xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <BatteryReport xmlns="http://schemas.microsoft.com/battery/2012">
          <Batteries>
            <Battery><Id>DELL 7FHD</Id><Manufacturer>SMP</Manufacturer><Chemistry>LION</Chemistry><DesignCapacity>56000</DesignCapacity><FullChargeCapacity>44800</FullChargeCapacity><CycleCount>312</CycleCount></Battery>
          </Batteries>
          <RuntimeEstimates>
            <FullChargeCapacity><ActiveRuntime>PT3H4M5S</ActiveRuntime></FullChargeCapacity>
            <DesignCapacity><ActiveRuntime>PT3H50M</ActiveRuntime></DesignCapacity>
          </RuntimeEstimates>
          <History>
            <HistoryEntry LocalStartDate="x"><LocalStartDate>2026-08-01</LocalStartDate><FullChargeCapacity>50000</FullChargeCapacity><DesignCapacity>56000</DesignCapacity></HistoryEntry>
            <HistoryEntry><LocalStartDate>2026-08-15</LocalStartDate><FullChargeCapacity>1</FullChargeCapacity><DesignCapacity>56000</DesignCapacity></HistoryEntry>
            <HistoryEntry><LocalStartDate>2026-09-01</LocalStartDate><FullChargeCapacity>44800</FullChargeCapacity><DesignCapacity>56000</DesignCapacity></HistoryEntry>
          </History>
        </BatteryReport>
        """;

    [Fact]
    public void LiestDenBericht()
    {
        var r = Akku.Parse(Xml.Trim());
        var b = Assert.Single(r.Batteries);
        Assert.Equal("DELL 7FHD", b.Name);
        Assert.Equal(312, b.Cycles);
        Assert.Equal(44800, b.Full);
        Assert.Equal("3 Std. 4 Min.", Akku.Time(r.Runtime));
        Assert.Equal(2, r.History.Count);
        Assert.Equal(50000, r.History[0].Full);   // der erste Eintrag des Monats zählt
    }

    [Theory]
    [InlineData(56000, 44800, 80, "good")]
    [InlineData(56000, 36000, 64, "warn")]
    [InlineData(56000, 20000, 36, "bad")]
    [InlineData(50000, 51000, 100, "good")]
    public void Zustand(double design, double full, int percent, string tone) => Assert.Equal((percent, tone), Akku.Health(design, full));

    [Fact]
    public void OhneWerteKeinZustand() => Assert.Null(Akku.Health(0, 100));

    [Fact]
    public void KurzeZeitLeer() => Assert.Equal("", Akku.Time("PT30S"));

    [Fact]
    public void VerlaufErsterUndLetzteFuenf()
    {
        var months = Enumerable.Range(1, 9).Select(i => new AkkuMonat { Month = "2026-" + i.ToString("00"), Full = 1, Design = 1 });
        var pick = Akku.Pick(months);
        Assert.Equal(new[] { "2026-01", "2026-05", "2026-06", "2026-07", "2026-08", "2026-09" }, pick.Select(m => m.Month));
    }
}

public class AufruestTests
{
    static IDictionary<string, double?> S(double? core, double? cpu, double? gpu, double? ram) =>
        new Dictionary<string, double?> { ["CpuCoreMax"] = core, ["CpuLoad"] = cpu, ["GpuLoad"] = gpu, ["Ram"] = ram };

    [Fact]
    public void GrafikkarteBremst()
    {
        var m = Aufruesten.Measure(Enumerable.Repeat(S(60, 30, 98, 50), 60).ToList());
        Assert.Equal("Die Grafikkarte bremst", Aufruesten.Verdict(m).Title);
        Assert.Equal(1.0, m.Gpu!.Busy);
    }

    [Fact]
    public void ProzessorBremstTrotzNiedrigerGesamtlast()
    {
        var m = Aufruesten.Measure(Enumerable.Repeat(S(95, 30, 60, 50), 60).ToList());
        Assert.Equal("Der Prozessor bremst", Aufruesten.Verdict(m).Title);
    }

    [Fact]
    public void OhneNvidia()
    {
        var m = Aufruesten.Measure(Enumerable.Repeat(S(50, 30, null, 50), 60).ToList());
        Assert.Null(m.Gpu);
        Assert.Equal("Der Prozessor bremst eher nicht", Aufruesten.Verdict(m).Title);
    }

    [Fact]
    public void VollerSpeicherAlsHinweis()
    {
        var m = Aufruesten.Measure(Enumerable.Repeat(S(50, 30, 50, 95), 60).ToList());
        var v = Aufruesten.Verdict(m);
        Assert.Equal("Nichts stand am Anschlag", v.Title);
        Assert.Contains("Mehr RAM hilft", v.Text);
    }

    [Fact]
    public void KeineWerte() => Assert.Equal("Keine Messwerte", Aufruesten.Verdict(Aufruesten.Measure(new List<IDictionary<string, double?>>())).Title);

    [Fact]
    public void Steckplaetze()
    {
        Assert.Equal(("1 von 2 Steckplätzen belegt · höchstens 64 GB laut BIOS · ein zweiter gleicher Riegel bringt Dual-Channel", "1 Platz frei", true),
            Aufruesten.Memory(1, 2, 64.0 * (1L << 30), false));
        Assert.Equal("alle belegt", Aufruesten.Memory(4, 4, 0, false).Chip);
        Assert.Equal("", Aufruesten.Memory(2, 0, 0, false).Chip);
    }
}

public class NeuinstallationTests
{
    [Theory]
    [InlineData("Mozilla.Firefox", "Firefox")]
    [InlineData("Valve.Steam.Beta", "Steam Beta")]
    [InlineData("7zip", "7zip")]
    public void Name(string id, string name) => Assert.Equal(name, Neuinstallation.ProgramName(id));

    [Fact]
    public void ListeAusWingetExport()
    {
        const string json = "{\"Sources\":[{\"Packages\":[{\"PackageIdentifier\":\"Valve.Steam\"},{\"PackageIdentifier\" : \"Mozilla.Firefox\"},{\"PackageIdentifier\":\"Valve.Steam\"}]}]}";
        Assert.Equal(new[] { "Mozilla.Firefox", "Valve.Steam" }, Neuinstallation.Programs(json).Select(p => p.Id));
    }

    [Fact]
    public void Ordnername() => Assert.Equal("Neuinstallation_2026-10-25_1730", Neuinstallation.FolderName(new DateTime(2026, 10, 25, 17, 30, 0)));

    [Fact]
    public void SchonVorhandenZaehlt() => Assert.True(Neuinstallation.WingetResult(-1978335189).Ok);
}

public class NotfallstickTests
{
    [Theory]
    [InlineData("PulsRig.exe", false, true)]
    [InlineData("PulsRig.Core.dll", false, true)]
    [InlineData("unins000.exe", false, false)]
    [InlineData("unins000.dat", false, false)]
    [InlineData("App", true, true)]
    [InlineData("Sensoren", true, true)]
    [InlineData("Treiber", true, false)]
    public void WasMitkommt(string name, bool folder, bool copies) => Assert.Equal(copies, Notfallstick.Copies(name, folder));

    [Theory]
    [InlineData("F:\\", "", "USB-Stick (F:)")]
    [InlineData("F:\\", "SANDISK", "SANDISK (F:)")]
    public void Name(string drive, string label, string text) => Assert.Equal(text, Notfallstick.Label(drive, label));

    [Fact]
    public void LiesmichNenntExeUndTreiber()
    {
        var lines = Notfallstick.Readme(new DateTime(2026, 10, 25, 20, 15, 0), "SPIELE-PC");
        Assert.Equal("PulsRig-Notfall-Stick vom 25.10.2026 20:15 für den PC SPIELE-PC", lines[0]);
        Assert.Contains(lines, l => l.Contains("PulsRig.exe"));
        Assert.Contains(lines, l => l.Contains("Treiber-installieren.bat"));
    }
}
