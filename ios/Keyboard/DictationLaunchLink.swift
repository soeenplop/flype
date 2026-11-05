import FlypeCore
import SwiftUI
import UIKit

struct DictationLaunchLink: View {
    let url: URL?
    var session: VoiceSessionState? = nil
    var action: (() -> Void)? = nil
    var willOpen: ((URL) -> Bool)? = nil
    var tablet = false
    var body: some View {
        Group {
            if let session {
                Button {
                    action?()
                } label: {
                    if session.phase.isWorking {
                        ProgressView().tint(Color(uiColor: .label))
                    } else {
                        Image(systemName: session.phase == .recording ? "waveform" : "mic.fill")
                    }
                }
                .disabled(session.phase.isWorking)
                .accessibilityLabel(
                    L10n.text(
                        session.phase == .recording
                            ? "Transkription stoppen und einfügen" : "Transkription direkt starten"))
            } else if let url {
                Link(destination: url) {
                    Image(systemName: "mic.fill")
                }
                .accessibilityLabel(L10n.text("Transkription starten; aktiviert Flype"))
            } else {
                Button {
                } label: {
                    Image(systemName: "mic.slash")
                }
                .disabled(true)
                .opacity(0.45)
                .accessibilityLabel(L10n.text("Mikrofon benötigt vollen Zugriff"))
            }
        }
        .font(.system(size: tablet ? 20 : 18))
        .buttonStyle(KeyboardMicrophoneKeyStyle(tablet: tablet))
        .environment(
            \.openURL,
            OpenURLAction { requestedURL in
                // Runs for touch and accessibility before the system opens the Link.
                if requestedURL == url, willOpen?(requestedURL) == false { return .discarded }
                return .systemAction(requestedURL)
            })
    }
}

/// Matches the UIKit function keys while retaining the public SwiftUI Link.
private struct KeyboardMicrophoneKeyStyle: ButtonStyle {
    var tablet = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.leading, tablet ? 14 : 0)
            .padding(.bottom, tablet ? 11 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: tablet ? .bottomLeading : .center)
            .foregroundStyle(Color(uiColor: KeyboardKeyAppearance.foreground))
            .background(
                Color(
                    uiColor: configuration.isPressed
                        ? KeyboardKeyAppearance.pressedSurface
                        : tablet ? KeyboardKeyAppearance.characterSurface : KeyboardKeyAppearance.functionSurface),
                in: RoundedRectangle(
                    cornerRadius: tablet
                        ? KeyboardKeyAppearance.tabletCornerRadius : KeyboardKeyAppearance.cornerRadius,
                    style: .continuous)
            )
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIDevice.current.playInputClick() }
            }
    }
}
