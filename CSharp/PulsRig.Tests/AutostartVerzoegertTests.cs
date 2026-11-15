using PulsRig.Core;

namespace PulsRig.Tests;

public class AutostartVerzoegertTests
{
    [Fact]
    public void SplitsQuotedCommand()
    {
        var (file, args) = Autostart.SplitCommand("\"C:\\Program Files\\Steam\\steam.exe\" -silent");
        Assert.Equal(@"C:\Program Files\Steam\steam.exe", file);
        Assert.Equal("-silent", args);
    }

    [Fact]
    public void SplitsPlainCommand()
    {
        Assert.Equal((@"C:\Tools\a b.exe", "/min"), Autostart.SplitCommand(@"C:\Tools\a b.exe /min"));
        Assert.Equal((@"C:\x.bat", ""), Autostart.SplitCommand(@"C:\x.bat"));
    }

    [Fact]
    public void TaskNameIsSafe() => Assert.Equal("Discord_Update", Autostart.TaskName("Discord/Update"));
}
