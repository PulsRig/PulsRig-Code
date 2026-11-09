using PulsRig.Core;

namespace PulsRig.Tests;

public class ProgrammupdatesTests
{
    [Fact]
    public void ReadsGermanTable()
    {
        var output = "   - \r   | \r\n" +
            "Name                         ID                          Version      Verfügbar    Quelle\n" +
            "------------------------------------------------------------------------------------------\n" +
            "Mozilla Firefox (x64 de)     Mozilla.Firefox             119.0        120.0.1      winget\n" +
            "7-Zip 23.01 (x64)            7zip.7zip                   23.01        24.08        winget\n" +
            "Microsoft Visual C++ 2015-…  Microsoft.VCRedist.2015+.x… 14.36.32532  14.40.33810  winget\n" +
            "3 Aktualisierungen verfügbar.\n";
        var list = Programmupdates.Parse(output);
        Assert.Equal(3, list.Count);
        Assert.Equal("Mozilla Firefox (x64 de)", list[0].Name);
        Assert.Equal("Mozilla.Firefox", list[0].Id);
        Assert.Equal("119.0", list[0].Version);
        Assert.Equal("120.0.1", list[0].Available);
        Assert.Equal("winget", list[0].Source);
        Assert.True(Programmupdates.IsSafeId(list[1].Id));
        Assert.False(Programmupdates.IsSafeId(list[2].Id));   // von winget gekürzt
    }

    [Fact]
    public void NothingToUpdate()
    {
        Assert.Empty(Programmupdates.Parse("Es wurde kein installiertes Paket gefunden, das den Eingabekriterien entspricht."));
        Assert.Empty(Programmupdates.Parse(""));
    }

    [Fact]
    public void Codes()
    {
        Assert.True(Programmupdates.Result(0).Ok);
        Assert.True(Programmupdates.Result(-1978335189).Ok);
        Assert.False(Programmupdates.Result(5).Ok);
        Assert.False(Programmupdates.IsSafeId("a b"));
        Assert.False(Programmupdates.IsSafeId("x\" --source evil"));
    }
}
