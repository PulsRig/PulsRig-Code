using System.IO;
using PulsRig.Core;

namespace PulsRig.Tests;

public class SpracheTests
{
    // die echte Wortliste der App (CSharp\PulsRig.App\Englisch.ps1, beim Bauen neben die Tests kopiert)
    static Sprache English() => Sprache.Load(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Englisch.ps1")));

    [Fact]
    public void WoerterUndMuster()
    {
        var en = English();
        // so viele, wie PowerShell aus derselben Datei liest (Paare, davon einige doppelt, und Muster)
        Assert.InRange(en.Count, 1900, 2100);
        Assert.Equal(709, en.PatternCount);
        Assert.Equal("Tools", en.T("Werkzeuge"));
        Assert.Equal("No admin rights", en.T("Ohne Adminrechte"));
        Assert.Equal("No answer from 1.1.1.1", en.T("Keine Antwort von 1.1.1.1"));
        Assert.Equal("Internet 12 ms", en.T("Internet 12 ms"));
    }

    [Fact]
    public void ZusammengesetztUndUnbekannt()
    {
        var en = Sprache.Load("@{\n Words = @(\n 'Scan', 'Scan'\n 'Werkzeuge', 'Tools' # Kommentar mit 'Strich'\n 'Don''t', 'Nicht'\n )\n Patterns = @(\n @{ R = '^(\\d+) Laufwerke$'; F = '$1 drives' }\n )\n}");
        Assert.Equal("Tools · 3 drives", en.T("Werkzeuge · 3 Laufwerke"));
        Assert.Equal("Nicht", en.T("Don't"));
        Assert.Equal("  Tools", en.T("  Werkzeuge"));
        Assert.Equal("12,5 GB", en.T("12,5 GB"));
        Assert.Equal("Unbekannt", en.T("Unbekannt"));
        Assert.Contains("Unbekannt", en.Untranslated);
    }
}
