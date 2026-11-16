import AppKit
import SwiftUI
import ScribbitCore

/// View state only. AppSettings and Service Management remain controller-owned.
@MainActor
final class SettingsPopupState: ObservableObject {
    @Published var indicator = false
    @Published var launchAtLogin = false
    @Published var loginRequiresApproval = false
}

struct AboutInfo: Equatable {
    let name: String
    let version: String?

    init(infoDictionary: [String: Any]?) {
        func text(_ key: String) -> String? {
            guard let value = infoDictionary?[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        name = text("CFBundleDisplayName") ?? text("CFBundleName") ?? "Scribbit"
        version = text("CFBundleShortVersionString")
    }
    var versionText: String { version.map { "Version \($0)" } ?? "" }
}

struct SettingsPopupView: View {
    @ObservedObject var model: NoteModel
    @ObservedObject var settings: SettingsPopupState
    var canChangeLogin = true
    let choose: () -> Void
    let create: () -> Void
    let save: () -> Void
    let saveCopy: () -> Void
    let close: () -> Void
    let loginChanged: () -> Void
    let indicatorChanged: () -> Void
    let speedChanged: (Double) -> Void
    let hoverDelayChanged: (Double) -> Void
    let about: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scribbit Settings").font(.headline)
            HStack {
                Button("Choose File…", action: choose)
                Button("New File…", action: create)
            }
            HStack {
                Group {
                    Button("Save Now", action: save)
                    Button("Save a Copy…", action: saveCopy)
                }.disabled(!model.isOpen)
                Spacer()
                Button("Done", action: close)
            }
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { settings.launchAtLogin }, set: { _ in loginChanged() }))
                .disabled(!canChangeLogin)
            if settings.loginRequiresApproval {
                Button("Approve in Login Settings…", action: loginChanged)
                    .disabled(!canChangeLogin)
                Text("macOS requires approval before Scribbit can launch at login.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Show frog beside notch", isOn: Binding(
                get: { settings.indicator }, set: { _ in indicatorChanged() }))
            HStack {
                Text("Animation speed")
                Spacer()
                Text(AnimationSpeed.label(model.animationSpeed))
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { model.animationSpeed }, set: speedChanged),
                   in: AnimationSpeed.range, step: 0.25)
                .accessibilityLabel("Animation speed")
            HStack {
                Text("Hover to open")
                Spacer()
                Text(HoverDelay.label(model.hoverDelay)).monospacedDigit()
            }
            Slider(value: Binding(get: { model.hoverDelay }, set: { value in
                hoverDelayChanged(HoverDelay.normalized(value))
            }), in: HoverDelay.range, step: HoverDelay.step)
                .accessibilityLabel("Hover delay before opening")
                .accessibilityIdentifier("hoverDelaySlider")
            Divider()
            HStack {
                Button("About", action: about)
                Spacer()
                Button("Quit Scribbit", action: quit)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 320)
        .disabled(model.isBusy)
        .accessibilityIdentifier("settingsPopup")
    }
}

/// Native controls provide visible, stable popover anchors for both the gear
/// and Command-comma's collapsed-section fallback, without deferred layout.
struct NotchControlButton: NSViewRepresentable {
    let symbol: String
    let identifier: String
    let label: String
    let help: String
    var action: (NSButton) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol,
            accessibilityDescription: label)!, target: context.coordinator,
            action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        configure(button)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
        configure(button)
    }
    private func configure(_ button: NSButton) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = help
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject {
        var action: (NSButton) -> Void
        init(action: @escaping (NSButton) -> Void) { self.action = action }
        @objc func open(_ sender: NSButton) { action(sender) }
    }
}
