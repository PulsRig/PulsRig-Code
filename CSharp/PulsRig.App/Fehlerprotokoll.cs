using System.IO;

namespace PulsRig.App;

// unerwartete Fehler der App, im Datenordner; das Diagnosepaket nimmt die Datei mit. Bleibt klein: über 512 KB fängt sie neu an
static class Fehlerprotokoll
{
    static readonly object Gate = new();

    public static string File => Path.Combine(Altdaten.Folder, "PulsRig-Fehler.log");

    public static void Write(Exception e)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Altdaten.Folder);
                if (new FileInfo(File) is { Exists: true, Length: > 512 * 1024 }) System.IO.File.Delete(File);
                System.IO.File.AppendAllText(File, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + typeof(App).Assembly.GetName().Version + Environment.NewLine + e + Environment.NewLine + Environment.NewLine);
            }
        }
        catch (Exception) { }
    }
}
