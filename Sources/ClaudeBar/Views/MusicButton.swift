import SwiftUI

/// 🎵: the office's lofi music on or off (dimmed when off). In the Office tab beside Follow, and in the popup's header.
struct MusicButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let on = state.settings.sounds.music
        Button { state.toggleMusic() } label: {
            Image(systemName: on ? "music.note" : "speaker.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.6))
                .frame(width: 24, height: 20)
                .background(Capsule().fill(on ? Theme.working.opacity(0.2) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(on ? "Lofi music on: click to turn it off" : "Lofi music off: click to turn it on")
        .accessibilityLabel(on ? "Turn music off" : "Turn music on")
    }
}
