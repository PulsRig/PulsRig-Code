using System.Management;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PulsRig.Core;

namespace PulsRig.App;

// Ping-Test wie PulsRig-Ping.ps1: 20 Runden gleichzeitig zum Router (Standard-Gateway des Adapters mit dem Weg ins
// Internet) und zu Cloudflare, Google und Quad9 - die antworten zuverlässig, viele Spieleserver nicht. Daraus die
// Einordnung: liegt ein Problem zu Hause (WLAN, Router) oder auf dem Weg zum Anbieter?
sealed class PingPage : UserControl, IPage
{
    const int Rounds = 20;
    readonly MainWindow window;
    readonly Grid root = new();
    List<Pingziel>? targets;
    string link = "";
    bool stopped, busy;

    public PingPage(MainWindow window)
    {
        this.window = window;
        Content = root;
        Measure();
    }

    void Measure()
    {
        if (busy) return;
        busy = true;
        targets = null;
        Fill();
        Task.Run(async () =>
        {
            var (list, kind) = await Run();
            await Dispatcher.BeginInvoke(() => { targets = list; link = kind; busy = false; Fill(); });
        });
    }

    static async Task<(List<Pingziel>, string)> Run()
    {
        var list = new List<Pingziel>();
        var link = "";
        try
        {
            ManagementObject? best = null;
            uint bestMetric = uint.MaxValue;
            using (var s = new ManagementObjectSearcher("SELECT Index, InterfaceIndex, DefaultIPGateway, IPConnectionMetric FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE"))
                foreach (ManagementObject o in s.Get())
                {
                    var gw = (o["DefaultIPGateway"] as string[] ?? Array.Empty<string>()).FirstOrDefault(g => System.Text.RegularExpressions.Regex.IsMatch(g, @"^\d+\.\d+\.\d+\.\d+$"));
                    var metric = Convert.ToUInt32(o["IPConnectionMetric"] ?? uint.MaxValue);
                    if (gw != null && metric < bestMetric) { best = o; bestMetric = metric; }
                }
            if (best != null)
            {
                var gw = (best["DefaultIPGateway"] as string[])!.First(g => System.Text.RegularExpressions.Regex.IsMatch(g, @"^\d+\.\d+\.\d+\.\d+$"));
                list.Add(new() { Name = "Router", Address = gw, Kind = "home" });
                // WLAN oder Kabel: aus dem Medium des Adapters (9 = WLAN), notfalls aus dem Namen
                var wifi = false;
                try
                {
                    using var n = new ManagementObjectSearcher(@"root\StandardCimv2", "SELECT NdisPhysicalMedium FROM MSFT_NetAdapter WHERE InterfaceIndex = " + best["InterfaceIndex"]);
                    foreach (ManagementObject a in n.Get()) wifi = Convert.ToInt32(a["NdisPhysicalMedium"] ?? 0) == 9;
                }
                catch (Exception) { }
                if (!wifi)
                    using (var a = new ManagementObjectSearcher("SELECT Name, NetConnectionID FROM Win32_NetworkAdapter WHERE Index = " + best["Index"]))
                        foreach (ManagementObject o in a.Get())
                            wifi = System.Text.RegularExpressions.Regex.IsMatch(o["Name"] + " " + o["NetConnectionID"], @"Wi-?Fi|WLAN|Wireless|802\.11", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                link = wifi ? "wifi" : "cable";
            }
        }
        catch (Exception) { }
        list.Add(new() { Name = "Cloudflare", Address = "1.1.1.1", Kind = "net" });
        list.Add(new() { Name = "Google", Address = "8.8.8.8", Kind = "net" });
        list.Add(new() { Name = "Quad9", Address = "9.9.9.9", Kind = "net" });
        // alle Ziele je Runde gleichzeitig: 20 Runden dauern so nur rund acht Sekunden
        for (var round = 0; round < Rounds; round++)
        {
            var pending = list.Select(async t =>
            {
                using var ping = new System.Net.NetworkInformation.Ping();
                t.Sent++;
                try
                {
                    var reply = await ping.SendPingAsync(t.Address, 1000);
                    if (reply.Status == System.Net.NetworkInformation.IPStatus.Success) t.Times.Add(reply.RoundtripTime); else t.Lost++;
                }
                catch (Exception) { t.Lost++; }
            }).ToList();
            await Task.WhenAll(pending);
            await Task.Delay(250);
        }
        return (list, link);
    }

    static string Color(string tone) => tone switch { "good" => "#5EE0A0", "warn" => "#F2B661", "bad" => "#E06B7A", _ => "#8C6BD6" };

    void Fill()
    {
        if (stopped) return;
        root.Children.Clear();
        root.RowDefinitions.Clear();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var again = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 36, Padding = new Thickness(16, 0, 16, 0), Tag = "18", IsEnabled = !busy,
            Background = (Brush)Application.Current.FindResource("PulsQuer"), VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text(busy ? "Misst …" : "Neu messen", 12.5, "Text", bold: true) };
        again.Click += (_, _) => Measure();
        DockPanel.SetDock(again, Dock.Right);
        head.Children.Add(again);
        var title = new StackPanel();
        title.Children.Add(Ui.Text("Ping-Test", 22, "Text", bold: true));
        title.Children.Add(Ui.Text("Wie schnell und stabil die Verbindung ist – zu Hause und ins Internet", 12.5, "Leise"));
        head.Children.Add(title);
        root.Children.Add(head);

        var list = new StackPanel();
        if (targets == null) list.Children.Add(Ui.Text("Messe 20 Runden zu Router und Internet (etwa zehn Sekunden) …", 13, "Leise"));
        else
        {
            var router = targets.FirstOrDefault(t => t.Kind == "home");
            var reach = targets.Where(t => t.Kind == "net" && t.Avg != null).OrderBy(t => t.Avg).ToList();
            var best = reach.FirstOrDefault();
            var routerTone = router != null ? Core.Ping.Tone(router) : "";
            var netTone = best != null ? Core.Ping.Tone(best) : "bad";
            list.Children.Add(Section("EINORDNUNG"));
            if (reach.Count == 0)
            {
                var row = Row("Keine Antwort aus dem Internet", "Keiner der drei Anbieter hat geantwortet. Entweder ist die Verbindung weg, oder eine Firewall blockiert Ping.", "bad", "keine Antwort");
                list.Children.Add(row);
                var fix = new Button { Style = (Style)Application.Current.FindResource("Flach"), Height = 34, Padding = new Thickness(14, 0, 14, 0), Tag = "17", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 10),
                    Background = Ui.Brush("#140C1D"), BorderBrush = Ui.Res("KarteRand"), BorderThickness = new Thickness(1), VerticalContentAlignment = VerticalAlignment.Center, Content = Ui.Text("Netzwerk reparieren", 12, "Text", bold: true) };
                fix.Click += (_, _) => { window.GoTop("tools"); window.Go("repair"); };
                list.Children.Add(fix);
            }
            else if (routerTone == "warn")
                list.Children.Add(Row("Das Problem liegt zu Hause", link == "wifi" ? "Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Typisch für WLAN: näher an den Router, ein anderes Funkband (5 GHz) oder ein Netzwerkkabel helfen meist."
                    : "Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Kabel, Anschluss und Router prüfen; ein Neustart des Routers hilft oft.", "warn", ""));
            else if (netTone == "good")
                list.Children.Add(Row("Alles im grünen Bereich", "Zu Hause stabil, ins Internet " + best!.Avg!.Value.ToString("N0", Ui.De) + " ms ohne nennenswerte Schwankung. Das reicht auch für schnelle Shooter.", "good", ""));
            else
                list.Children.Add(Row("Zu Hause stabil, der Weg ins Internet nicht", "Bis zum Router ist alles in Ordnung; die Verzögerung oder die Aussetzer entstehen beim Anbieter oder auf dem Weg dorthin. Zu einer anderen Tageszeit noch einmal messen; bleibt es so, hilft nur der Anbieter.", netTone, ""));
            if (link.Length > 0)
                list.Children.Add(Row(link == "wifi" ? "Verbunden über WLAN" : "Verbunden über Kabel", link == "wifi" ? "Für Spiele ist ein Netzwerkkabel stabiler: WLAN schwankt durch Wände, Nachbarnetze und andere Geräte." : "Die stabilste Verbindung für Spiele.", link == "wifi" ? "" : "good", ""));
            list.Children.Add(Section("MESSUNG (20 RUNDEN JE ZIEL)"));
            foreach (var t in targets)
            {
                var label = t.Kind == "home" ? "Router (zu Hause)" : t.Name + " (Internet)";
                if (t.Avg == null) { list.Children.Add(Row(label, "Keine Antwort von " + t.Address, "bad", "keine Antwort")); continue; }
                list.Children.Add(Row(label, "Schnitt " + t.Avg.Value.ToString("N0", Ui.De) + " ms · schnellste " + t.Min!.Value.ToString("N0", Ui.De) + " · langsamste " + t.Max!.Value.ToString("N0", Ui.De)
                    + " · Schwankung " + t.Jitter!.Value.ToString("N0", Ui.De) + " ms · " + t.LossPercent + " % verloren", Core.Ping.Tone(t), Core.Ping.Ms(t.Avg.Value)));
            }
            list.Children.Add(Section("SO LIEST MAN DAS"));
            list.Children.Add(Row("Ping (Verzögerung)", "Bis 30 ms ist sehr gut, bis 60 ms für die meisten Spiele in Ordnung. Zum Spieleserver kommt je nach Entfernung noch etwas dazu.", "", ""));
            list.Children.Add(Row("Schwankung und Verlust", "Stärker als ein hoher Ping stören Sprünge und verlorene Pakete: Figuren springen, Treffer zählen nicht. Mehr als 1 % Verlust spürt man.", "", ""));
        }
        var scroll = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
    }

    static TextBlock Section(string text) { var t = Ui.Text(text, 10, "Leise", mono: true); t.Margin = new Thickness(2, 10, 0, 8); return t; }

    static Border Row(string title, string sub, string tone, string state)
    {
        var c = Color(tone);
        var grid = new Grid { MinHeight = 58 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border { Width = 4, Height = 30, CornerRadius = new CornerRadius(2), Background = Ui.Brush(c), Margin = new Thickness(0, 0, 16, 0), Effect = Ui.Glow(c, 8) });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 10, 12, 10) };
        text.Children.Add(Ui.Text(title, 14, "Text", bold: true));
        text.Children.Add(new TextBlock { Text = sub, FontSize = 12, Foreground = Ui.Res("Leise"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        if (state.Length > 0) { var s = Ui.Text(state, 13, c, bold: true, mono: true); s.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(s, 2); grid.Children.Add(s); }
        return new Border { Style = (Style)Application.Current.FindResource("Kachel"), CornerRadius = new CornerRadius(16), Background = Ui.Brush("#0B0710"), BorderBrush = Ui.Brush("#1A1224"),
            Padding = new Thickness(18, 0, 18, 0), Margin = new Thickness(0, 0, 0, 8), Child = grid };
    }

    public void Stop() => stopped = true;
}
