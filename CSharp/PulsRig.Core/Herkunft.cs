// PulsRig.Core - Herkunft-Anzeige: woher ein Treiberpaket kommt und wer es signiert hat.
// Windows Update erkennt PulsRig an den installierten Updates (Titel "Hersteller - Klasse - Version"),
// den Rest an der Signatur: von Microsoft geprüft (WHQL), nur vom Hersteller signiert oder gar nicht signiert.

using System;
using System.Collections.Generic;
using System.Linq;
namespace PulsRig.Core;

public static class Herkunft
{
    public const string Whql = "Microsoft Windows Hardware Compatibility Publisher";

    // Text für die Liste und ob man genauer hinsehen sollte
    public static (string Text, bool Warn) Of(bool signed, string signer, string provider, string version, IEnumerable<string> updateTitles)
    {
        signer = (signer ?? "").Trim();
        if (!signed && signer.Length == 0) return ("nicht signiert – Herkunft unklar", true);
        var check = signer == Whql || signer.StartsWith("Microsoft Windows", StringComparison.OrdinalIgnoreCase) ? "von Microsoft geprüft" : signer.Length > 0 ? "signiert von " + signer : "signiert";
        if (FromWindowsUpdate(provider, version, updateTitles)) return ("über Windows Update · " + check, false);
        return ("vom Hersteller oder von Hand installiert · " + check, false);
    }

    public static bool FromWindowsUpdate(string provider, string version, IEnumerable<string> updateTitles)
    {
        if (string.IsNullOrWhiteSpace(version)) return false;
        var word = (provider ?? "").Trim().Split(' ', ',', '.').FirstOrDefault(w => w.Length > 1) ?? "";
        return updateTitles.Any(t => t.Contains(version) && (word.Length == 0 || t.IndexOf(word, StringComparison.OrdinalIgnoreCase) >= 0));
    }
}
