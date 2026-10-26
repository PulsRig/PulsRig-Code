// PulsRig.Core - Netzwerkadapter ohne die Windows-Module. Abgelöst aus Treiber-Werkzeuge.ps1 (Get-NetAdapterList,
// Get-NetIPv4List): die Abfrage über CIM bleibt beim Aufrufer, hier stehen die Wörter wie bei Get-NetAdapter.
using System;
using System.Globalization;
using System.Text;

namespace PulsRig.Core
{
    public static class Netzwerk
    {
        static string Text(object? value) => Convert.ToString(value, CultureInfo.InvariantCulture) ?? "";

        public static string Status(object? adminStatus, object? mediaConnectState)
        {
            string admin = Text(adminStatus), media = Text(mediaConnectState);
            if (admin == "2" || admin.Equals("Down", StringComparison.OrdinalIgnoreCase)) return "Disabled";
            if (media == "1" || media.Equals("Connected", StringComparison.OrdinalIgnoreCase)) return "Up";
            if (media == "2" || media.Equals("Disconnected", StringComparison.OrdinalIgnoreCase)) return "Disconnected";
            return "Not Present";
        }

        // Zahlen im Format der eingestellten Sprache, wie bisher mit -f in PowerShell ("2,5 Gbps")
        public static string LinkSpeed(double speed)
        {
            if (speed >= 1e9) return string.Format(CultureInfo.CurrentCulture, "{0:0.#} Gbps", speed / 1e9);
            if (speed >= 1e6) return string.Format(CultureInfo.CurrentCulture, "{0:0.#} Mbps", speed / 1e6);
            if (speed > 0) return string.Format(CultureInfo.CurrentCulture, "{0:0.#} Kbps", speed / 1e3);
            return "";
        }

        // "001122AABBCC" oder "00:11:22:aa:bb:cc" -> "00-11-22-AA-BB-CC"
        public static string MacAddress(object? permanentAddress)
        {
            var hex = new StringBuilder();
            foreach (char c in Text(permanentAddress)) if (Uri.IsHexDigit(c)) hex.Append(char.ToUpperInvariant(c));
            if (hex.Length != 12) return "";
            var mac = new StringBuilder();
            for (int i = 0; i < 12; i += 2) { if (i > 0) mac.Append('-'); mac.Append(hex[i]).Append(hex[i + 1]); }
            return mac.ToString();
        }

        public static bool IsIPv4(object? addressFamily)
        {
            string family = Text(addressFamily);
            return family == "2" || family.Equals("IPv4", StringComparison.OrdinalIgnoreCase);
        }

        // --- "Netzwerkfehler beheben": Auswertung der Prüfungen (abgelöst aus Get-NetworkState, Test-TcpPort) ---

        public static bool IsDefaultRoute(object? destinationPrefix) => Text(destinationPrefix) == "0.0.0.0/0";

        // 169.254.x.x vergibt Windows sich selbst, wenn kein Router antwortet - das zählt nicht als Adresse
        public static bool IsUsableAddress(string? address) =>
            !string.IsNullOrEmpty(address) && !address!.StartsWith("169.254.", StringComparison.Ordinal);

        public static bool IsDhcp(object? dhcp)
        {
            string value = Text(dhcp);
            return value == "1" || value.Equals("Enabled", StringComparison.OrdinalIgnoreCase);
        }

        // Ausgabe von nslookup: "Name:" steht nur da, wenn der Server geantwortet hat
        public static bool IsDnsAnswer(System.Collections.Generic.IEnumerable<string>? lines)
        {
            foreach (string line in lines ?? new string[0])
                if (line != null && System.Text.RegularExpressions.Regex.IsMatch(line, @"^Name:\s", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) return true;
            return false;
        }

        // Antwort von www.msftconnecttest.com/connecttest.txt; ein WLAN mit Anmeldeseite liefert etwas anderes
        public static bool IsConnectTest(string? content) =>
            content != null && content.IndexOf("Microsoft Connect Test", StringComparison.OrdinalIgnoreCase) >= 0;

        public static bool TcpPort(string address, int port, int timeoutMs = 3000)
        {
            using var client = new System.Net.Sockets.TcpClient();
            try
            {
                var pending = client.BeginConnect(address, port, null, null);
                if (!pending.AsyncWaitHandle.WaitOne(timeoutMs)) return false;
                client.EndConnect(pending);
                return true;
            }
            catch (Exception) { return false; }
        }
    }
}
