// PulsRig.Core - Spielprofile: pro Spiel, was der automatische Boost beim Start tut. Gespeichert unter "GameProfiles"
// der gemeinsamen Einstellungen, je Programmname (ohne ".exe") ein Objekt mit vier Schaltern. Fehlt ein Schalter oder
// das ganze Profil, gilt "an" - so verhält sich ein Spiel ohne Profil genau wie vorher.
// Tabu bleibt: ein Profil kann dem Boost nur etwas wegnehmen, nie mehr erlauben (Dienste prüft weiter Boost.IsAllowed).
using System;
using System.Collections.Generic;

namespace PulsRig.Core
{
    public sealed class Spielprofil
    {
        public static readonly string[] Keys = { "PowerPlan", "Services", "Priority", "Record" };

        public bool PowerPlan = true, Services = true, Priority = true, Record = true;

        public bool IsDefault => PowerPlan && Services && Priority && Record;

        public bool Get(string key) => key switch { "PowerPlan" => PowerPlan, "Services" => Services, "Priority" => Priority, "Record" => Record, _ => true };

        public void Set(string key, bool value)
        {
            switch (key)
            {
                case "PowerPlan": PowerPlan = value; break;
                case "Services": Services = value; break;
                case "Priority": Priority = value; break;
                case "Record": Record = value; break;
            }
        }

        // flag liefert den gespeicherten Schalter oder null, wenn er fehlt
        public static Spielprofil From(Func<string, bool?> flag)
        {
            var p = new Spielprofil();
            foreach (var key in Keys) p.Set(key, flag(key) ?? true);
            return p;
        }

        public static string Label(string key) => key switch
        {
            "PowerPlan" => "Energieplan", "Services" => "Dienste anhalten", "Priority" => "Spiel bevorzugen", "Record" => "Aufzeichnen", _ => key,
        };

        // kurz für die Liste, z. B. "Energieplan, Spiel bevorzugen · ohne Dienste anhalten, Aufzeichnen"
        public string Describe()
        {
            if (IsDefault) return "Alles an";
            var on = new List<string>();
            var off = new List<string>();
            foreach (var key in Keys) (Get(key) ? on : off).Add(Label(key));
            return on.Count == 0 ? "Alles aus" : string.Join(", ", on) + " · ohne " + string.Join(", ", off);
        }
    }
}
