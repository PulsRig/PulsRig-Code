using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class ProbezeitTests
{
    static readonly DateTime Now = new(2026, 10, 25, 12, 0, 0);
    static TreiberStand Gpu(string version) => new() { Id = @"PCI\VEN_10DE&DEV_2216\4", Name = "NVIDIA GeForce RTX 3080", Version = version, Class = "DISPLAY" };

    [Fact]
    public void ErsterStartMerktNurDieStaende()
    {
        var known = new Dictionary<string, TreiberStand>();
        var list = Probezeit.Update(known, new(), new[] { Gpu("1") }, new Dictionary<string, long>(), new AbsturzDaten(), Now, 0);
        Assert.Empty(list);
        Assert.Equal("1", known[Gpu("1").Id].Version);
    }

    [Fact]
    public void NeueVersionStartetProbezeitAbInstallation()
    {
        var known = new Dictionary<string, TreiberStand> { [Gpu("1").Id] = Gpu("1") };
        var at = Now.AddDays(-2).Ticks;
        var installs = new Dictionary<string, long> { [Gpu("1").Id.ToUpperInvariant()] = at };
        var list = Probezeit.Update(known, new(), new[] { Gpu("2") }, installs, new AbsturzDaten(), Now, at + TimeSpan.FromHours(1).Ticks);
        var e = Assert.Single(list);
        Assert.Equal(("1", "2", at, "PulsRig", "läuft"), (e.Old, e.New, e.Since, e.Source, e.Verdict));
        Assert.Equal(14, e.BeforeDays);
    }

    [Fact]
    public void HaeufungMachtAuffaelligUndRuheBestanden()
    {
        var since = Now.AddDays(-3).Ticks;
        var crashes = new AbsturzDaten();
        crashes.Tdr.Add(new Vorfall { When = Now.AddDays(-1) });
        crashes.Blue.Add(new Vorfall { When = Now.AddDays(-2) });
        var entry = new ProbeEintrag { Id = "x", Class = "DISPLAY", Since = since };
        var list = Probezeit.Update(new() { ["y"] = new TreiberStand() }, new() { entry }, Array.Empty<TreiberStand>(), new Dictionary<string, long>(), crashes, Now, 0);
        Assert.Equal(("auffällig", 2, 0), (list[0].Verdict, list[0].After, list[0].Before));
        Assert.NotNull(Probezeit.Warning(list, Now));
        Assert.Equal("Seit dem neuen Grafiktreiber 2 Abstürze oder Aussetzer", Probezeit.WarnTitle(list[0]));

        // ein Netzwerktreiber zählt Aussetzer der Grafik nicht
        var net = new ProbeEintrag { Id = "n", Class = "NET", Since = Now.AddDays(-8).Ticks };
        list = Probezeit.Update(new() { ["y"] = new TreiberStand() }, new() { net }, Array.Empty<TreiberStand>(), new Dictionary<string, long>(), crashes, Now, 0);
        Assert.Equal(("bestanden", true, 1), (list[0].Verdict, list[0].Done, list[0].After));
    }

    [Fact]
    public void TexteWieImPowerShellProgramm()
    {
        var e = new ProbeEintrag { Name = "RTX", Class = "DISPLAY", Old = "1", New = "2", Since = new DateTime(2026, 10, 14).Ticks, BeforeDays = 14, Source = "Windows" };
        Assert.Equal("RTX, neu seit 14.10. (Version 2, vorher 1). In den 14 Tagen davor: keine.", Probezeit.Text(e));
        Assert.Equal("Treiber 2 seit 14.10., vorher 1 · von Windows Update oder von Hand · Tag 7 von 7 · seitdem keine Abstürze", Probezeit.Sub(e, Now));
    }
}
