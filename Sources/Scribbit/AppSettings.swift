import Foundation
import ScribbitCore

/// Isolated GUI tests use RAM-only settings. They must never register login items
/// or read/write a production bookmark through the normal startup flow.
@MainActor
final class AppSettings {
    private let defaults: UserDefaults?
    private var memory: [String: Any] = [:]
    init(isolated: Bool) { defaults = isolated ? nil : .standard }
    private func value(_ key: String) -> Any? { defaults?.object(forKey: key) ?? memory[key] }
    private func set(_ value: Any?, key: String) {
        if let defaults { defaults.set(value, forKey: key) }
        else { memory[key] = value }
    }
    var bookmark: Data? {
        get { value("noteBookmark") as? Data }
        set { set(newValue, key: "noteBookmark") }
    }
    var didOfferLogin: Bool {
        get { value("didOfferLogin") as? Bool ?? false }
        set { set(newValue, key: "didOfferLogin") }
    }
    var indicator: Bool {
        get { value("showNotchIndicator") as? Bool ?? false }
        set { set(newValue, key: "showNotchIndicator") }
    }
    var animationSpeed: Double {
        get { AnimationSpeed.normalized(value("animationSpeed") as? Double ?? 1) }
        set { set(AnimationSpeed.normalized(newValue), key: "animationSpeed") }
    }
    var hoverDelay: Double {
        get { HoverDelay.normalized(value("hoverDelay") as? Double ?? HoverDelay.defaultValue) }
        set { set(HoverDelay.normalized(newValue), key: "hoverDelay") }
    }

}
