using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class AenderungenTests
{
    static readonly DateTime Now = new(2026, 10, 26, 12, 0, 0);
    const string Gpu = @"PCI\VEN_10DE&DEV_2216";

    static Tagesbild Bild(int ago, string gpu = "1", string windows = "26100.1", string plan = "Ausbalanciert", string[]? programs = null, string[]? autostart = null) => new()
    {
        D = Aenderungen.DayKey(Now.AddDays(-ago)), Windows = windows, Plan = plan,
        Programs = (programs ?? new[] { "Steam|2.10|20260901" }).ToList(), Autostart = (autostart ?? new[] { "Steam|an" }).ToList(),
        Drivers = new() { Gpu + "|RTX 3080|" + gpu + "|DISPLAY" },
    };

    [Fact]
    public void GleicheBilderOhneAenderung()
    {
        Assert.Empty(Aenderungen.Compare(Bild(1), Bild(0)));
        Assert.Empty(Aenderungen.Compare(null, Bild(0)));
    }

    [Fact]
    public void WindowsTreiberUndEnergieplan()
    {
        var probe = new ProbeEintrag { Id = Gpu, New = "2", Source = "PulsRig", Since = Now.AddDays(-1).Ticks };
        var list = Aenderungen.Compare(Bild(1), Bild(0, gpu: "2", windows: "26100.2", plan: "Höchstleistung"), new[] { probe });
        Assert.Equal(new[] { "windows", "driver", "plan" }, list.Select(c => c.Kind));
        Assert.Equal("Stand 26100.1 → 26100.2", list[0].Sub);
        Assert.Equal("Grafiktreiber geändert: RTX 3080", list[1].Title);
        Assert.Equal("Version 1 → 2 · von PulsRig am 25.10.", list[1].Sub);
        Assert.Equal("warn", list[1].Tone);
        Assert.Equal("Ausbalanciert → Höchstleistung", list[2].Sub);
    }

    [Fact]
    public void ProgrammeUndAutostart()
    {
        var old = Bild(7, programs: new[] { "Steam|2.10|", "Discord|1|", "Alt|1|" }, autostart: new[] { "Steam|an", "Discord|aus", "Alt|an" });
        var now = Bild(0, programs: new[] { "Steam|2.11|", "Discord|1|", "OBS Studio|31|" }, autostart: new[] { "Steam|an", "Discord|an", "OBS Studio|an" });
        var list = Aenderungen.Compare(old, now);
        Assert.Equal(new[] { "Neues Programm: OBS Studio", "Entfernt: Alt", "Aktualisiert: Steam", "2 Programme starten jetzt mit Windows", "Startet nicht mehr mit Windows: Alt" },
            list.Select(c => c.Title));
        Assert.Equal("Version 31", list[0].Sub);
        Assert.Equal("Version 2.10 → 2.11", list[2].Sub);
        Assert.Equal("OBS Studio, Discord", list[3].Sub);
    }

    [Fact]
    public void AbstuerzeSeitDemVergleichstagGanzOben()
    {
        var crashes = new AbsturzDaten();
        crashes.Blue.Add(new Vorfall { When = Now.AddHours(-3) });
        crashes.Tdr.Add(new Vorfall { When = Now.AddHours(-2) });
        crashes.Off.Add(new Vorfall { When = Now.AddDays(-20) });
        var list = Aenderungen.Compare(Bild(7), Bild(0, plan: "Höchstleistung"), null, crashes);
        Assert.Equal("Abstürze seit 19.10.", list[0].Title);
        Assert.StartsWith("1 Bluescreen · 1 Aussetzer oder Ausschalten", list[0].Sub);
        Assert.Equal("bad", list[0].Tone);
        Assert.Equal("plan", list[1].Kind);
    }

    [Fact]
    public void NamenListeKuerzt()
    {
        Assert.Equal("a, b", Aenderungen.JoinNames(new[] { "a", "", "b" }));
        Assert.Equal("a, b, c, d und 2 weitere", Aenderungen.JoinNames(new[] { "a", "b", "c", "d", "e", "f" }));
    }

    [Fact]
    public void AufbewahrenAchtTageDannWoechentlich()
    {
        var saved = Enumerable.Range(1, 40).Select(i => Bild(i)).Append(new Tagesbild { D = Aenderungen.DayKey(Now), Windows = "alt" }).ToList();
        var kept = Aenderungen.Keep(saved, Bild(0), Now);
        Assert.Equal("26100.1", kept[^1].Windows);
        Assert.Single(kept, s => s.D == Aenderungen.DayKey(Now));
        Assert.DoesNotContain(kept, s => (Now - DateTime.Parse(s.D)).TotalDays > 35);
        Assert.Equal(8, kept.Count(s => (Now - DateTime.Parse(s.D)).TotalDays < 8));
        Assert.Equal(kept.OrderBy(s => s.D).Select(s => s.D), kept.Select(s => s.D));
    }

    [Fact]
    public void VergleichsbildJuengstesAltGenugSonstAeltestes()
    {
        var snaps = new List<Tagesbild> { Bild(3), Bild(1), Bild(0) };
        Assert.Equal(Bild(1).D, Aenderungen.Before(snaps, 1, Now)!.D);
        Assert.Equal(Bild(3).D, Aenderungen.Before(snaps, 7, Now)!.D);
        Assert.False(Aenderungen.Exact(Bild(3), 7, Now));
        Assert.Null(Aenderungen.Before(new List<Tagesbild> { Bild(0) }, 1, Now));
    }
}
