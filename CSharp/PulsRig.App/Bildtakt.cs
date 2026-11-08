namespace PulsRig.App;

// Gemeinsamer Takt von 30 Bildern je Sekunde für Animationen über CompositionTarget.Rendering: alle, die ihn nutzen,
// zeichnen im selben Bild neu, damit das Fenster je Takt nur einmal neu zusammengesetzt wird (es ist durchsichtig,
// AllowsTransparency, und jedes Zusammensetzen kostet spürbar Prozessor).
static class Bildtakt
{
    static readonly System.Diagnostics.Stopwatch Uhr = System.Diagnostics.Stopwatch.StartNew();

    // true, wenn seit dem letzten Aufruf mit demselben Zähler ein neuer Abschnitt von 1/30 s begonnen hat
    public static bool Neu(ref long bucket)
    {
        var now = (long)(Uhr.Elapsed.TotalSeconds * 30);
        if (now == bucket) return false;
        bucket = now;
        return true;
    }
}
