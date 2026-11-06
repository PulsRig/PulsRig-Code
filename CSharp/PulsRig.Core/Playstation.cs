using System;

namespace PulsRig.Core
{
    // PS4- und PS5-Controller (DualShock 4, DualSense, DualSense Edge) sprechen kein XInput, sondern schicken ihre
    // Meldungen über HID. Diese Klasse liest eine Meldung und gibt sie im selben Aufbau zurück wie PulsRigPad.Read für
    // XInput: verbunden, Tasten (XInput-Bits), LT, RT (0–255), LX, LY, RX, RY (−32768..32767, oben positiv).
    //
    // Aufbau der Meldungen (erstes Byte = Kennung der Meldung):
    //   DualShock 4 per Kabel 0x01 und DualSense per Bluetooth im einfachen Modus 0x01 (kurz):
    //     [1..4] Sticks, [5] Steuerkreuz + Symbole, [6] L1 R1 L2 R2 Share Options L3 R3, [7] PS, [8] L2, [9] R2
    //   DualShock 4 per Bluetooth 0x11: wie oben, zwei Bytes weiter hinten
    //   DualSense per Kabel 0x01 (64 Bytes): [1..4] Sticks, [5] L2, [6] R2, [8] Steuerkreuz + Symbole, [9] Schulter
    //   DualSense per Bluetooth 0x31: wie per Kabel, ein Byte weiter hinten
    public static class Playstation
    {
        public const ushort Sony = 0x054C;

        // Name des Modells, leer = kein bekannter PlayStation-Controller
        public static string Model(int vendor, int product)
        {
            if (vendor != Sony) return "";
            switch (product)
            {
                case 0x05C4: case 0x09CC: return "DualShock 4";
                case 0x0BA0: return "DualShock 4 (Funkadapter)";
                case 0x0CE6: return "DualSense";
                case 0x0DF2: return "DualSense Edge";
                default: return "";
            }
        }

        public static bool IsDualSense(int product) => product == 0x0CE6 || product == 0x0DF2;

        // XInput-Bits wie in EingabePage.PadButtons
        public const int A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000, LB = 0x0100, RB = 0x0200, Back = 0x0020, Start = 0x0010,
            LS = 0x0040, RS = 0x0080, Up = 0x0001, Down = 0x0002, Left = 0x0004, Right = 0x0008;

        // Art der Verbindung, die eine Meldung verrät: "Kabel", "Bluetooth", "Bluetooth (einfach)"
        public static string Link(byte[] report, int product)
        {
            if (report.Length == 0) return "";
            if (report[0] == 0x31 || report[0] == 0x11) return "Bluetooth";
            if (report[0] == 0x01 && report.Length < 32) return "Bluetooth (einfach)";
            return "Kabel";
        }

        public static int[]? Read(byte[] report, int product)
        {
            if (report == null || report.Length < 10) return null;
            int sticks, buttons, l2, r2;
            if (IsDualSense(product) && report[0] == 0x01 && report.Length >= 11) { sticks = 1; l2 = 5; r2 = 6; buttons = 8; }
            else if (IsDualSense(product) && report[0] == 0x31 && report.Length >= 12) { sticks = 2; l2 = 6; r2 = 7; buttons = 9; }
            else if (report[0] == 0x01) { sticks = 1; buttons = 5; l2 = 8; r2 = 9; }                       // DS4 Kabel, DualSense einfach
            else if (report[0] == 0x11 && report.Length >= 12) { sticks = 3; buttons = 7; l2 = 10; r2 = 11; }
            else return null;

            int face = report[buttons], shoulder = report[buttons + 1];
            int bits = 0;
            // Symbole: Kreuz = A, Kreis = B, Quadrat = X, Dreieck = Y (Lage wie beim Xbox-Controller)
            if ((face & 0x20) != 0) bits |= A;
            if ((face & 0x40) != 0) bits |= B;
            if ((face & 0x10) != 0) bits |= X;
            if ((face & 0x80) != 0) bits |= Y;
            // Steuerkreuz als Richtung 0–7 im Uhrzeigersinn ab oben, 8 = keine
            switch (face & 0x0F)
            {
                case 0: bits |= Up; break;
                case 1: bits |= Up | Right; break;
                case 2: bits |= Right; break;
                case 3: bits |= Down | Right; break;
                case 4: bits |= Down; break;
                case 5: bits |= Down | Left; break;
                case 6: bits |= Left; break;
                case 7: bits |= Up | Left; break;
            }
            if ((shoulder & 0x01) != 0) bits |= LB;
            if ((shoulder & 0x02) != 0) bits |= RB;
            if ((shoulder & 0x10) != 0) bits |= Back;       // Share bzw. Create
            if ((shoulder & 0x20) != 0) bits |= Start;      // Options
            if ((shoulder & 0x40) != 0) bits |= LS;
            if ((shoulder & 0x80) != 0) bits |= RS;

            return new[] { 1, bits, (int)report[l2], (int)report[r2],
                Axis(report[sticks]), Flip(report[sticks + 1]), Axis(report[sticks + 2]), Flip(report[sticks + 3]) };
        }

        // 0..255 mit Mitte 128 → −32768..32767 wie XInput (128 genau auf 0)
        public static int Axis(byte value) => value >= 128 ? (value - 128) * 32767 / 127 : (value - 128) * 256;

        // Y-Achse: beim Controller unten groß, bei XInput oben positiv (ganz oben wäre +32768, also begrenzen)
        static int Flip(byte value) => Math.Min(32767, -Axis(value));

        // Tastennamen auf dem PlayStation-Controller
        public static string ButtonName(string xbox, int product)
        {
            bool five = IsDualSense(product);
            switch (xbox)
            {
                case "A": return "✕";
                case "B": return "○";
                case "X": return "□";
                case "Y": return "△";
                case "LB": return "L1";
                case "RB": return "R1";
                case "LT": return "L2";
                case "RT": return "R2";
                case "LS": return "L3";
                case "RS": return "R3";
                case "Back": return five ? "Create" : "Share";
                case "Start": return "Options";
                default: return xbox;
            }
        }

        // Abfragerate aus der Zahl der Meldungen in einer Sekunde, auf die übliche Stufe gerundet, wenn sie nah liegt
        public static int Rate(int reportsPerSecond)
        {
            if (reportsPerSecond <= 0) return 0;
            int best = 0;
            foreach (var s in new[] { 125, 250, 500, 1000, 2000, 4000, 8000 })
                if (best == 0 || Math.Abs(s - reportsPerSecond) < Math.Abs(best - reportsPerSecond)) best = s;
            return Math.Abs(best - reportsPerSecond) <= best * 0.1 ? best : reportsPerSecond;
        }
    }
}
