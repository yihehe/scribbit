import SwiftUI

/// Quiet identity on the open surface, independent of the optional resting wing.
/// Keep the native disclosure full-width: it is also the collapsed settings anchor.
struct NoteFooter: View {
    let isExpanded: Bool
    let toggleInformation: () -> Void

    var body: some View {
        NotchControlButton(
            symbol: isExpanded ? "chevron.down" : "chevron.up",
            identifier: "toggleNoteInformation",
            label: isExpanded ? "Hide note information and controls" : "Show note information and controls",
            help: "Expand for file path, pin, preview, and settings. Settings shortcut: ⌘,",
            action: { _ in toggleInformation() })
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .overlay(alignment: .leading) {
                HStack(spacing: 5) {
                    Image(nsImage: BrandAssets.notch)
                        .accessibilityHidden(true)
                    Text("Scribbit")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Scribbit")
                // Branding is not another command or focus target.
                .allowsHitTesting(false)
            }
            // Separate the entire row from the editor without shifting the
            // logo relative to the chevron or moving the settings anchor.
            .padding(.top, 8)
    }
}
