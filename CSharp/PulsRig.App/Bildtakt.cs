namespace PulsRig.App;

// Gemeinsamer Spartakt von rund 30 Bildern je Sekunde für Animationen über CompositionTarget.Rendering: alle, die ihn
// nutzen, zeichnen im selben Bild neu, damit das Fenster je Takt nur einmal neu zusammengesetzt wird (es ist durchsichtig,
// AllowsTransparency, und jedes Zusammensetzen kostet spürbar Prozessor).
// Gezählt wird in Bildern des Bildschirms, nicht in Zeit: bei 143 Hz ergäben 30 Abschnitte je Sekunde mal 4, mal 5
// Bilder Abstand, und die Bewegung ruckelte. So wird es jedes 2. Bild bei 60 Hz, jedes 4. bei 120 bis 149 Hz.
static class Bildtakt
{
    static TimeSpan lastTime;
    static long frame;
    static double interval = 1 / 60.0;

    // true, wenn mit diesem Bild für den Zähler ein neuer Abschnitt begonnen hat; e ist das Argument von Rendering
    public static bool Neu(ref long bucket, EventArgs e)
    {
        if (e is System.Windows.Media.RenderingEventArgs r && r.RenderingTime != lastTime)
        {
            var dt = (r.RenderingTime - lastTime).TotalSeconds;
            // Bildabstand gleitend mitteln; Lücken (Fenster verdeckt, minimiert) zählen nicht
            if (dt > 0 && dt < .05) interval += (dt - interval) * .05;
            lastTime = r.RenderingTime;
            frame++;
        }
        var every = Math.Max(1, (long)(1 / (interval * 30) + .05));
        var slot = frame / every;
        if (slot == bucket) return false;
        bucket = slot;
        return true;
    }
}
