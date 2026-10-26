using PulsRig.Core;

namespace PulsRig.Tests;

public class TreiberspeicherTests
{
    [Fact]
    public void VersionAusDerRegistry()
    {
        // amdgpio2.inf, so wie er in DriverDatabase\DriverPackages steht
        var raw = Convert.FromHexString("00FF0900000000007DE9364D25E3CE11BFC108002BE10318008069AF1C21DC0186000000020002000000000000000000");
        Assert.True(Treiberspeicher.ParseVersion(raw, out var guid, out var date, out var version));
        Assert.Equal("{4d36e97d-e325-11ce-bfc1-08002be10318}", guid);
        Assert.Equal(new Version(2, 2, 0, 134), version);
        Assert.Equal(2025, date.Year);
    }

    [Fact]
    public void ZuKurzIstUnbekannt() => Assert.False(Treiberspeicher.ParseVersion(new byte[10], out _, out _, out _));

    static Treiberpaket P(string inf, string version, string original = "nv_dispi.inf") =>
        new() { Inf = inf, Original = original, Provider = "NVIDIA", ClassGuid = "{4d36e968-e325-11ce-bfc1-08002be10318}", Version = Version.Parse(version) };

    [Fact]
    public void ZweiNeuesteBleiben()
    {
        var old = Treiberspeicher.Old(new[] { P("oem1.inf", "32.0.15.1"), P("oem2.inf", "32.0.15.3"), P("oem3.inf", "32.0.15.2"), P("oem4.inf", "31.0.1.0") }, new List<string>());
        Assert.Equal(new[] { "oem1.inf", "oem4.inf" }, old.Select(p => p.Inf).OrderBy(i => i));
    }

    [Fact]
    public void BenutztesBleibt()
    {
        var old = Treiberspeicher.Old(new[] { P("oem1.inf", "1.0"), P("oem2.inf", "2.0"), P("oem3.inf", "3.0") }, new List<string> { "OEM1.INF" });
        Assert.Empty(old);
    }

    [Fact]
    public void NurZweiFassungenHeisstNichts() => Assert.Empty(Treiberspeicher.Old(new[] { P("oem1.inf", "1.0"), P("oem2.inf", "2.0") }, new List<string>()));

    [Fact]
    public void WindowsEigeneBleiben() => Assert.Empty(Treiberspeicher.Old(new[] { P("a.inf", "1.0"), P("b.inf", "2.0"), P("c.inf", "3.0") }, new List<string>()));
}

public class StandbyTests
{
    [Theory]
    [InlineData("HID-konforme Maus", "", "input")]
    [InlineData("Intel(R) Ethernet Connection I219-V", "", "net")]
    [InlineData("", @"\Microsoft\Windows\UpdateOrchestrator\Reboot", "timer")]
    [InlineData("Netzschalter", "", "button")]
    [InlineData("", "", "unknown")]
    [InlineData("USB-Root-Hub", "", "dev:USB-Root-Hub")]
    public void ArtDerWeckquelle(string source, string owner, string key) => Assert.Equal(key, Standby.WakeKind(source, owner).Key);

    [Fact]
    public void WertDesEnergieplans() =>
        Assert.Equal(1800, Standby.PlanValue("Index der aktuellen Wechselstromeinstellung: 0x00000708\nIndex der aktuellen Gleichstromeinstellung: 0x00000384"));

    [Fact]
    public void KeinGeraetDarfWecken() => Assert.Empty(Standby.Armed(new[] { "KEINE", "" }));

    [Fact]
    public void AnfragenMitGrund()
    {
        var r = Standby.Requests(new[] { "DISPLAY:", "[PROCESS] \\Device\\HarddiskVolume3\\Program Files\\Google\\chrome.exe", "Video Wake Lock", "", "SYSTEM:", "Keine.", "AWAYMODE:", "Keine." })!;
        Assert.Single(r);
        Assert.Equal(("DISPLAY", "PROCESS", "chrome.exe", "Video Wake Lock"), r[0]);
    }

    [Fact]
    public void OhneAdminrechteNichts() => Assert.Null(Standby.Requests(new[] { "Für diesen Vorgang sind Administratorrechte erforderlich." }));
}

public class AutostartTests
{
    [Fact]
    public void ZustandWieImTaskManager()
    {
        Assert.True(Autostart.IsEnabled(null));
        Assert.True(Autostart.IsEnabled(Autostart.Approved(true, DateTime.Now)));
        Assert.False(Autostart.IsEnabled(Autostart.Approved(false, DateTime.Now)));
        Assert.Equal(12, Autostart.Approved(false, DateTime.Now).Length);
    }

    [Theory]
    [InlineData("\"C:\\Program Files\\Steam\\steam.exe\" -silent", "C:\\Program Files\\Steam\\steam.exe")]
    [InlineData("C:\\Tools\\helfer.exe /min", "C:\\Tools\\helfer.exe")]
    public void ProgrammdateiAusDerBefehlszeile(string command, string file) => Assert.Equal(file, Autostart.CommandFile(command));

    [Fact]
    public void NameAusBeschreibung()
    {
        Assert.Equal("Steam Client Bootstrapper", Autostart.Title("Steam", "Steam Client Bootstrapper"));
        Assert.Equal("Discord", Autostart.Title("Discord.lnk", ""));
    }
}

public class SpielcheckTests
{
    [Fact]
    public void WertOhneGraue() => Assert.Equal(75, Spielcheck.Score(new[] { "good", "warn", "", "good", "warn" }));

    [Fact]
    public void NichtsPruefbar() => Assert.Null(Spielcheck.Score(new[] { "", "" }));

    [Theory]
    [InlineData("8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c", "Höchstleistung", false, "good")]
    [InlineData("a1841308-3541-4fab-bc81-f71556f20b4a", "Energiesparmodus", false, "bad")]
    [InlineData("381b4222-f694-41f0-9685-ff5bb260df2e", "Ausbalanciert", false, "warn")]
    [InlineData("381b4222-f694-41f0-9685-ff5bb260df2e", "Ausbalanciert", true, "good")]
    public void Energieplan(string guid, string name, bool battery, string tone) => Assert.Equal(tone, Spielcheck.PlanTone(guid, name, battery));

    [Fact]
    public void AktiverPlan() =>
        Assert.Equal(("381b4222-f694-41f0-9685-ff5bb260df2e", "Ausbalanciert"), Spielcheck.ActivePlan("GUID des Energieschemas: 381b4222-f694-41f0-9685-ff5bb260df2e  (Ausbalanciert)"));

    [Fact]
    public void ResizableBar() => Assert.Equal(16384, Spielcheck.Bar1("    BAR1 Memory Usage\n        Total                             : 16384 MiB"));

    [Fact]
    public void NameAusDerBibliothek() => Assert.Equal("Cyberpunk 2077", Spielcheck.GameName(@"D:\SteamLibrary\steamapps\common\Cyberpunk 2077\bin\x64\Cyberpunk2077.exe"));
}
