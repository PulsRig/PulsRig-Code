using System.IO.Compression;
using System.Security;
using PulsRig.Core;

namespace PulsRig.Tests;

public class BedienfehlerTests
{
    [Fact]
    public void NativeMessagesAndPrivatePathsAreNotShown()
    {
        var text = Bedienfehler.Text(new DirectoryNotFoundException(@"Could not find C:\Private\secret"));
        Assert.Contains("wähle", text);
        Assert.DoesNotContain("Could not", text);
        Assert.DoesNotContain("Private", text);
    }

    [Theory]
    [InlineData(112, "Platz")]
    [InlineData(39, "Platz")]
    [InlineData(32, "verwendet")]
    [InlineData(21, "Laufwerk")]
    public void IoErrorsGiveSpecificNextAction(int code, string expected) =>
        Assert.Contains(expected, Bedienfehler.Text(new IOException("native message", unchecked((int)0x80070000) | code)));

    [Theory]
    [InlineData(5, "Administrator")]
    [InlineData(112, "Speicherplatz")]
    [InlineData(2, "erneut aus")]
    [InlineData(87, "Geräte-Manager")]
    public void DriverExitCodesAreExplained(int code, string next) => Assert.Contains(next, Bedienfehler.Text(new TreiberWerkzeugException(code)));

    [Fact]
    public void WrappedAccessDeniedIsRecognized() =>
        Assert.Contains("Zugriff", Bedienfehler.Text(new AggregateException(new SecurityException("Requested registry access is not allowed")))) ;

    [Fact]
    public void CorruptZipHasRecoveryAdvice()
    {
        using var stream = new MemoryStream(new byte[] { 1, 2, 3 });
        var error = Assert.Throws<InvalidDataException>(() => new ZipArchive(stream));
        var text = Bedienfehler.Text(error);
        Assert.Contains("unveränderte Sicherung", text);
        Assert.DoesNotContain(error.Message, text);
    }

    [Fact]
    public void OwnValidationReasonIsKept()
    {
        var error = Assert.Throws<InvalidDataException>(() => Sicherungsablage.Inspect(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"))));
        Assert.Contains("Sicherungsordner ist nicht mehr vorhanden", Bedienfehler.Text(error));
    }

    [Fact]
    public void RestorePointFailureDoesNotSuggestDriversWereInstalled()
    {
        var error = Assert.Throws<InvalidOperationException>(() => Sicherungsablage.RequireRestorePoint(5));
        var text = Bedienfehler.Text(error);
        Assert.Contains("nicht eingespielt", text);
        Assert.Contains("Computerschutz", text);
    }
}
