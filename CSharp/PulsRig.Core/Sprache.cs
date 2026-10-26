// PulsRig.Core - Übersetzung der Oberfläche wie T in PulsRig-Sprache.ps1. Die Wörter stehen weiter in
// PulsRig-Englisch.ps1 (Words: Paare deutsch/englisch, Patterns: @{ R = '…'; F = '…' }); diese Datei liest sie,
// ohne PowerShell: einfach gequotete Strings ('' ist ein Apostroph), Kommentare ab # außerhalb der Strings.
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public sealed class Sprache
    {
        readonly Dictionary<string, string> words = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly List<(Regex R, string F)> patterns = new List<(Regex, string)>();
        public HashSet<string> Untranslated { get; } = new HashSet<string>(StringComparer.Ordinal);
        public int Count => words.Count;
        public int PatternCount => patterns.Count;

        // die Strings einer PowerShell-Datei in Reihenfolge, Kommentare übersprungen
        static List<string> Strings(string text)
        {
            var list = new List<string>();
            for (int i = 0; i < text.Length; i++)
            {
                char c = text[i];
                if (c == '#') { while (i < text.Length && text[i] != '\n') i++; continue; }
                if (c != '\'') continue;
                var s = new StringBuilder();
                for (i++; i < text.Length; i++)
                {
                    if (text[i] == '\'') { if (i + 1 < text.Length && text[i + 1] == '\'') { s.Append('\''); i++; continue; } break; }
                    s.Append(text[i]);
                }
                list.Add(s.ToString());
            }
            return list;
        }

        public static Sprache Load(string table)
        {
            var sprache = new Sprache();
            // "Patterns" steht auch im Kopfkommentar - gemeint ist die Zeile "Patterns = @("
            var m = Regex.Match(table, @"^\s*Patterns\s*=\s*@\(", RegexOptions.Multiline);
            int split = m.Success ? m.Index : table.Length;
            var words = Strings(table.Substring(0, split));
            for (int i = 0; i + 1 < words.Count; i += 2) sprache.words[words[i]] = words[i + 1];
            var pats = Strings(table.Substring(split));
            for (int i = 0; i + 1 < pats.Count; i += 2)
                try { sprache.patterns.Add((new Regex(pats[i]), pats[i + 1])); } catch (ArgumentException) { }
            return sprache;
        }

        static readonly Regex Letters = new Regex("[A-Za-zÄÖÜäöüß]{2}");

        // wie T: genaues Wort, sonst an " · " und Zeilenumbruch zerlegt, sonst das erste passende Muster
        public string T(string? text)
        {
            if (string.IsNullOrEmpty(text)) return text ?? "";
            if (words.TryGetValue(text!, out string? found)) return found;
            if (!Letters.IsMatch(text)) return text;
            foreach (string separator in new[] { " · ", "\n" })
                if (text.Contains(separator))
                {
                    var parts = text.Split(new[] { separator }, StringSplitOptions.None);
                    for (int i = 0; i < parts.Length; i++) parts[i] = T(parts[i]);
                    return string.Join(separator, parts);
                }
            foreach (var (r, f) in patterns)
            {
                var match = r.Match(text);
                if (!match.Success) continue;
                string result = f;
                for (int i = match.Groups.Count - 1; i >= 1; i--)
                {
                    string value = match.Groups[i].Value;
                    result = result.Replace("{T:" + i + "}", T(value)).Replace("$" + i, value);
                }
                return result;
            }
            // Einrückung und Leerzeichen am Ende bleiben stehen (wie TL)
            string core = text.Trim();
            if (core.Length > 0 && core.Length < text.Length)
            {
                string t = T(core);
                if (!ReferenceEquals(t, core) && t != core) return text.Replace(core, t);
            }
            Untranslated.Add(text);
            return text;
        }
    }
}
