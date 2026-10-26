// PulsRig.Core - die Logik von PulsRig ohne Oberfläche. Läuft als .NET Standard 2.0 sowohl in Windows PowerShell 5.1
// (Add-Type -Path PulsRig.Core.dll, solange das Programm noch PowerShell ist) als auch in der neuen Oberfläche auf .NET 10.
namespace PulsRig.Core
{
    public static class PulsRigInfo
    {
        public const string Name = "PulsRig";

        // muss zu $script:Version in PulsRig.ps1 passen (Test PulsRigInfoTests)
        public const string Version = "0.7 Beta";
    }
}

namespace PulsRig.Core
{
    using System;
    using System.Globalization;
    using System.Text.RegularExpressions;

    // Neue Fassung wie Read-VersionNote und Test-NewerBuild in PulsRig.ps1: version.json bei GitHub nennt Version,
    // Baudatum und die Setup-Datei. Geladen werden darf nur eine Setup-Datei aus den Releases des eigenen Projekts,
    // mit Prüfsumme und glaubhafter Größe; sonst bleibt es beim Verweis auf die Webseite.
    public static class Fassung
    {
        public const string Repo = "PulsRig/PulsRig";

        // "13.10.2026 18:45 · Stand abc1234" -> Baudatum; null in der Werkstatt (ohne Zeile)
        public static DateTime? BuildTime(string? text) =>
            text != null && text.Length >= 16 && DateTime.TryParseExact(text.Substring(0, 16), "dd.MM.yyyy HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime t) ? t : (DateTime?)null;

        public static bool IsNewer(string? mine, string? theirs) => BuildTime(mine) is DateTime own && BuildTime(theirs) is DateTime other && other > own;

        public static bool IsValidVersion(string? version) => Regex.IsMatch(version ?? "", @"^[\w .\-]{1,30}$");

        // die Setup-Datei nur mit Adresse aus den eigenen Releases, SHA-256 und 200 KB bis 60 MB
        public static bool IsValidSetup(string? url, string? sha256, long bytes, string repo = Repo) =>
            Regex.IsMatch(url ?? "", @"^https://github\.com/" + Regex.Escape(repo) + @"/releases/download/[\w.\-]{1,60}/PulsRig-Setup-[\w.\-]{1,40}\.exe$")
            && Regex.IsMatch(sha256 ?? "", "^[0-9a-fA-F]{64}$") && bytes >= 200 * 1024 && bytes <= 60L * 1024 * 1024;
    }
}
