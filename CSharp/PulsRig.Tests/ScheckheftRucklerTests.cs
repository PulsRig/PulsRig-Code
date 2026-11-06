using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class ScheckheftTests
{
    static readonly DateTime Now = new(2026, 11, 2, 12, 0, 0);

    static List<HeftTeil> Teile(string gpu = "RTX 3080", double ram = 16, params string[] disks) =>
        new List<HeftTeil> { new() { Kind = "Prozessor", Name = "Ryzen 5 3600" }, new() { Kind = "Grafikkarte", Name = gpu }, new() { Kind = "Arbeitsspeicher", Size = ram } }
            .Concat((disks.Length == 0 ? new[] { "Samsung 970|1000" } : disks).Select(d => new HeftTeil { Kind = "Laufwerk", Name = d.Split('|')[0], Size = double.Parse(d.Split('|')[1]) })).ToList();

    [Fact]
    public void BauteileGetauschtUndLaufwerkDazu()
    {
        var list = Scheckheft.PartChanges(Teile(), Teile("RTX 4070", 32, "Samsung 970|1000", "Crucial P3|2000"), Now);
        Assert.Equal(new[] { "Grafikkarte getauscht", "Arbeitsspeicher erweitert", "Neues Laufwerk" }, list.Select(e => e.Title));
        Assert.Contains("16 GB → 32 GB", list[1].Sub);
        Assert.Empty(Scheckheft.PartChanges(Teile(), Teile(), Now));
        Assert.Empty(Scheckheft.PartChanges(null, Teile(), Now));
    }

    [Fact]
    public void MergeBehaeltHandeintraegeUndErsetztMonatswerte()
    {
        var hand = new HeftEintrag { D = "2026-10-01 10:00", Kind = "cleaning", Title = "Entstaubt", Manual = true };
        var temp = new HeftEintrag { D = "2026-10-05 23:59", Kind = "temp", Title = "alt", Key = "temp|2026-10" };
        var bench = new HeftEintrag { D = "2026-09-01 10:00", Kind = "test", Title = "Benchmark", Key = "bench|01.09.2026 10:00" };
        var merged = Scheckheft.Merge(new[] { hand, temp, bench }, new[] { new HeftEintrag { D = "2026-10-20 23:59", Kind = "temp", Title = "neu", Key = "temp|2026-10" } });
        Assert.Equal(3, merged.Count);
        Assert.Equal("neu", merged.First(e => e.Key == "temp|2026-10").Title);
        Assert.Contains(merged, e => e.Manual && e.Title == "Entstaubt");
        Assert.Contains(merged, e => e.Key.StartsWith("bench|"));
    }

    [Fact]
    public void TemperaturenJeMonatOhneStresstest()
    {
        var points = new[]
        {
            new Messpunkt { D = "2026-10-03", Src = "Sitzung", GT = 70, CT = 75 },
            new Messpunkt { D = "2026-10-20", Src = "Sitzung", GT = 74 },
            new Messpunkt { D = "2026-10-21", Src = "Stresstest", GT = 90 },
        };
        var list = Scheckheft.Temperatures(points);
        Assert.Single(list);
        Assert.Contains("Grafikkarte höchstens 74 °C", list[0].Sub);
        Assert.Contains("2 Sitzungen", list[0].Sub);
    }

    [Fact]
    public void BerichtOhnePrivatesUndLesbarFuerGebrauchtkauf()
    {
        var parts = Teile();
        var html = Scheckheft.Html(new[] { Scheckheft.Start(parts, Now) }, parts, Now);
        Assert.DoesNotContain(Environment.UserName, html);
        Assert.DoesNotContain(Environment.MachineName, html);
        var read = Scheckheft.PartsFromHtml(html);
        Assert.NotNull(read);
        Assert.Equal(parts.Select(p => p.Line), read!.Select(p => p.Line));
        var compare = Scheckheft.Compare(read, Teile("RTX 3060"));
        Assert.Equal("bad", compare.First(c => c.Name == "Grafikkarte").State);
        Assert.Equal("good", compare.First(c => c.Name == "Laufwerke").State);
        Assert.Null(Scheckheft.PartsFromHtml("<html></html>"));
    }

    [Fact]
    public void HinweisZumEntstauben()
    {
        var old = new HeftEintrag { D = "2025-06-01 10:00", Kind = "hardware", Title = "Scheckheft begonnen" };
        Assert.NotNull(Scheckheft.CleaningHint(new[] { old }, Now));
        Assert.Null(Scheckheft.CleaningHint(new[] { old, new HeftEintrag { D = "2026-08-01 10:00", Kind = "cleaning", Manual = true } }, Now));
        Assert.Null(Scheckheft.CleaningHint(new[] { new HeftEintrag { D = "2026-10-01 10:00", Kind = "test" } }, Now));
    }
}

public class RucklerTests
{
    static Spielsitzung Sitzung(Func<int, (double Other, string Name, double Disk, double Dpc, double Ram)> row, int rows = 60)
    {
        var lines = new List<string> { "# PulsRig-Aufzeichnung;Spiel=Spiel;Beginn=2026-11-02T20:00:00;Takt=5", "Sekunde;CpuLast;StoerCpu;Platte;Dpc;RamFrei;Stoerer" };
        for (var i = 0; i < rows; i++)
        {
            var r = row(i);
            lines.Add(string.Join(";", (i * 5).ToString(), "60", r.Other.ToString(System.Globalization.CultureInfo.InvariantCulture), r.Disk.ToString(), r.Dpc.ToString(System.Globalization.CultureInfo.InvariantCulture), r.Ram.ToString(), r.Name));
        }
        return Aufzeichnung.Read(lines);
    }

    [Fact]
    public void AlteAufzeichnungOhneSpalten()
    {
        var s = Aufzeichnung.Read(new[] { "# PulsRig-Aufzeichnung;Spiel=X;Beginn=2026-11-02T20:00:00", "Sekunde;CpuTemp", "0;50", "5;51" });
        Assert.False(Ruckler.Analyze(s).Supported);
    }

    [Fact]
    public void RuhigeSitzung()
    {
        var r = Ruckler.Analyze(Sitzung(_ => (2, "Discord", 10, 0.5, 6000)));
        Assert.True(r.Supported);
        Assert.Empty(r.Findings);
    }

    [Fact]
    public void DefenderUndLaufwerkUndUpdate()
    {
        var s = Sitzung(i => i is >= 10 and < 14 ? (25, "MsMpEng", 95, 0.5, 6000) : (2, "Discord", 10, 0.5, 6000));
        Assert.Equal("MsMpEng", s.Texts["Stoerer"][10]);
        var update = new RucklerEreignis { When = s.Begin.AddMinutes(3), Kind = "update", Text = "KB5000001" };
        var outside = new RucklerEreignis { When = s.Begin.AddHours(-2), Kind = "defender" };
        var r = Ruckler.Analyze(s, new[] { update, outside });
        Assert.Equal(new[] { "Windows Defender hat dazwischengefunkt", "Laufwerk ausgelastet", "Windows Update während des Spielens" }, r.Findings.Select(f => f.Title));
        Assert.Equal("defender", r.Findings[0].Action);
        Assert.Contains("20:00", r.Findings[0].Text);
    }

    [Fact]
    public void TreiberUndArbeitsspeicher()
    {
        var r = Ruckler.Analyze(Sitzung(i => i < 6 ? (1, "", 10, 9.5, 500) : (1, "", 10, 0.5, 6000)));
        Assert.Contains(r.Findings, f => f.Action == "drivers");
        Assert.Contains(r.Findings, f => f.Title == "Arbeitsspeicher knapp");
    }
}
