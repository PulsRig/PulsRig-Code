#if NET
using System;
using System.IO;
using System.Net.Http;
using System.Security;

namespace PulsRig.Core;

public sealed class TreiberWerkzeugException : Exception
{
    public int Code { get; }
    public TreiberWerkzeugException(int code) : base("pnputil meldet Code " + code + ".") => Code = code;
}

// Technische Einzelheiten werden von der App protokolliert. Hier entstehen nur Erklärung und nächster Schritt.
public static class Bedienfehler
{
    public static string Text(Exception error)
    {
        // Nur technische Aufgaben-/Reflexionshüllen abstreifen; InvalidDataException kann einen
        // aussagekräftigen ZIP-Fehler mit einer weniger hilfreichen inneren I/O-Ausnahme enthalten.
        while (error.InnerException != null && (error is System.Reflection.TargetInvocationException || error is AggregateException a && a.InnerExceptions.Count == 1))
            error = error.InnerException;
        var code = error is TreiberWerkzeugException tool ? tool.Code : error.HResult & 0xFFFF;
        if (error is OperationCanceledException) return "Der Vorgang wurde abgebrochen. Du kannst ihn bei Bedarf erneut starten.";
        if (error is UnauthorizedAccessException or SecurityException || code == 5)
            return "Der Zugriff wurde verweigert. Wähle einen zugänglichen Ordner. Für Treibereingriffe starte PulsRig als Administrator.";
        if (error is FileNotFoundException or DirectoryNotFoundException || error is TreiberWerkzeugException && code is 2 or 3)
            return "Die benötigte Datei oder der Ordner wurde nicht gefunden. Prüfe, ob das Laufwerk verbunden ist, und wähle die Datei oder Sicherung erneut aus.";
        if (error is PathTooLongException)
            return "Der Dateipfad ist zu lang. Kopiere die Sicherung in einen Ordner mit kürzerem Pfad und versuche es erneut.";
        if (error is IOException or TreiberWerkzeugException && code is 112 or 39)
            return "Auf dem Ziellaufwerk ist nicht genug Platz frei. Gib Speicherplatz frei oder wähle ein anderes Ziel und starte den Vorgang erneut.";
        if (error is IOException && code is 32 or 33)
            return "Eine benötigte Datei wird gerade verwendet. Schließe das Programm, das auf die Datei zugreift, und versuche es erneut.";
        if (error is IOException && code is 21 or 55 or 1167)
            return "Das Laufwerk ist nicht erreichbar. Verbinde es erneut und prüfe, ob du den Ordner im Datei-Explorer öffnen kannst.";
        if (error.Message.StartsWith("Kein bestätigter Wiederherstellungspunkt", StringComparison.Ordinal))
            return "Windows hat keinen Wiederherstellungspunkt bestätigt. Die Treiber wurden nicht eingespielt. Prüfe den Computerschutz von Windows und versuche es danach erneut.";
        if (error is InvalidDataException)
        {
            var reason = error.Source == "PulsRig.Core" ? error.Message : "Die Sicherung oder ZIP-Datei ist beschädigt oder nicht lesbar.";
            return reason + "\nVerwende eine unveränderte Sicherung oder erstelle sie erneut. Vorhandene Sicherungen werden nicht überschrieben.";
        }
        if (error is HttpRequestException or TimeoutException)
            return "Die Verbindung konnte nicht abgeschlossen werden. Prüfe deine Internetverbindung und versuche es später erneut.";
        if (error is TreiberWerkzeugException)
            return "Windows konnte den Treiberauftrag nicht erfolgreich abschließen. Prüfe die Geräte im Geräte-Manager. Weitere Einzelheiten stehen im Fehlerprotokoll von PulsRig.";
        if (error is IOException)
            return "Die Datei konnte nicht gelesen oder geschrieben werden. Prüfe Laufwerk, freien Speicherplatz und Zugriffsrechte und versuche es erneut.";
        if (error is InvalidOperationException && error.Source is "PulsRig.App" or "PulsRig.Core")
            return error.Message + "\nPrüfe die Angaben und versuche es erneut. Wenn der Fehler bleibt, erstelle unter „Bericht & Diagnose“ ein Diagnosepaket.";
        return "Der Vorgang konnte nicht abgeschlossen werden. Versuche es erneut. Wenn der Fehler bleibt, erstelle unter „Bericht & Diagnose“ ein Diagnosepaket; die technischen Einzelheiten stehen im Fehlerprotokoll.";
    }
}
#endif
