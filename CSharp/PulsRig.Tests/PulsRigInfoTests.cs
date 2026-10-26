using System.IO;
using System.Text.RegularExpressions;
using PulsRig.Core;

namespace PulsRig.Tests;

public class PulsRigInfoTests
{
    [Fact]
    public void NameStimmt() => Assert.Equal("PulsRig", PulsRigInfo.Name);

    // die App zeigt dieselbe Fassung wie das PowerShell-Programm
    [Fact]
    public void VersionWieInPowerShell()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            var file = Path.Combine(dir.FullName, "PulsRig.ps1");
            if (!File.Exists(file)) continue;
            var version = Regex.Match(File.ReadAllText(file), @"\$script:Version = '([^']+)'").Groups[1].Value;
            Assert.True(version == PulsRigInfo.Version, "PulsRig.ps1 hat " + version + ", Core " + PulsRigInfo.Version);
            return;
        }
        Assert.Fail("PulsRig.ps1 nicht gefunden");
    }
}
