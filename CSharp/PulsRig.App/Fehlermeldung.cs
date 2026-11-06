using PulsRig.Core;

namespace PulsRig.App;

static class Fehlermeldung
{
    public static string Text(Exception error)
    {
        Fehlerprotokoll.Write(error);
        return Bedienfehler.Text(error);
    }
}
