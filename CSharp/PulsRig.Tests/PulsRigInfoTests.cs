using PulsRig.Core;

namespace PulsRig.Tests;

public class PulsRigInfoTests
{
    [Fact]
    public void NameStimmt() => Assert.Equal("PulsRig", PulsRigInfo.Name);

    // PulsRig-Paket.ps1 liest die Version aus PulsRigInfo.cs und macht daraus Dateinamen ("0.7 Beta" -> "0.7-Beta")
    [Fact]
    public void VersionTaugtFuerDateinamen() => Assert.Matches(@"^\d+\.\d+( [A-Za-z]+)?$", PulsRigInfo.Version);
}
