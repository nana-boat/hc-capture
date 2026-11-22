import Foundation

/// The finger colour chosen automatically for this phone, kept between launches.
/// Chosen on the first chest or table recording whose finger pulse passes all quality checks,
/// then used for every recording. Chosen again automatically only after 3 failed recordings in a row.
enum ColourProfile {
    static var channel: String? {
        get { UserDefaults.standard.string(forKey: "hc.ppgChannel") }
        set { UserDefaults.standard.set(newValue, forKey: "hc.ppgChannel") }
    }
    /// Increases each time a new colour is chosen, so recordings from different choices are never mixed.
    static var setup: Int {
        get { UserDefaults.standard.integer(forKey: "hc.colourSetup") }
        set { UserDefaults.standard.set(newValue, forKey: "hc.colourSetup") }
    }
    static var fails: Int {
        get { UserDefaults.standard.integer(forKey: "hc.colourFails") }
        set { UserDefaults.standard.set(newValue, forKey: "hc.colourFails") }
    }
    static var chosenOn: String? {
        get { UserDefaults.standard.string(forKey: "hc.colourChosenOn") }
        set { UserDefaults.standard.set(newValue, forKey: "hc.colourChosenOn") }
    }

    static func name(_ c: String?) -> String {
        switch c {
        case "r": return "red"
        case "g": return "green"
        case "b": return "blue"
        default: return "not chosen"
        }
    }
}
