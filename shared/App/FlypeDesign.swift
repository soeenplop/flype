import FlypeCore
import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

enum FlypeDesign {
    static var accent: Color {
        #if os(iOS)
            Color(
                uiColor: UIColor {
                    $0.userInterfaceStyle == .dark
                        ? UIColor(red: 0.75, green: 0.65, blue: 0.92, alpha: 1)
                        : UIColor(red: 0.41, green: 0.28, blue: 0.64, alpha: 1)
                })
        #else
            Color(
                nsColor: NSColor(name: nil) {
                    $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(red: 0.75, green: 0.65, blue: 0.92, alpha: 1)
                        : NSColor(red: 0.41, green: 0.28, blue: 0.64, alpha: 1)
                })
        #endif
    }
    static var onAccent: Color {
        #if os(iOS)
            Color(
                uiColor: UIColor {
                    $0.userInterfaceStyle == .dark ? UIColor(red: 0.13, green: 0.08, blue: 0.20, alpha: 1) : .white
                })
        #else
            Color(
                nsColor: NSColor(name: nil) {
                    $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(red: 0.13, green: 0.08, blue: 0.20, alpha: 1) : .white
                })
        #endif
    }
    static let ink = Color.primary
    static var paper: Color {
        #if os(iOS)
            Color(
                uiColor: UIColor {
                    $0.userInterfaceStyle == .dark
                        ? UIColor(white: 0.075, alpha: 1) : UIColor(red: 0.985, green: 0.981, blue: 0.972, alpha: 1)
                })
        #else
            Color(
                nsColor: NSColor(name: nil) {
                    $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0.075, alpha: 1) : NSColor(red: 0.985, green: 0.981, blue: 0.972, alpha: 1)
                })
        #endif
    }
    static var surface: Color {
        #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
        #else
            Color(nsColor: .controlBackgroundColor)
        #endif
    }
    static let soft = accent.opacity(0.055)
    #if os(iOS)
        /// The iPad sidebar puts white text on the tint, which the light dark-mode accent cannot carry.
        static var navigationTint: Color {
            Color(
                uiColor: UIColor {
                    $0.userInterfaceStyle == .dark
                        ? UIColor(red: 0.50, green: 0.38, blue: 0.78, alpha: 1)
                        : UIColor(red: 0.41, green: 0.28, blue: 0.64, alpha: 1)
                })
        }
    #endif
}

/// Keeps primary actions legible even when macOS dims an inactive window's native controls.
struct FlypePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? FlypeDesign.onAccent : Color.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .background(
                isEnabled ? FlypeDesign.accent : FlypeDesign.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled && configuration.isPressed ? 0.82 : 1)
    }
}

struct FlypeBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform").font(.system(size: 17, weight: .medium)).foregroundStyle(FlypeDesign.accent)
            Text(verbatim: "flype").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1.6)
        }.accessibilityElement(children: .combine)
    }
}

struct FlypePage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
        }.background(FlypeDesign.paper)
    }
}

struct FlypeCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct FlypeRow: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 23).foregroundStyle(.secondary)
            Text(L10n.text(title)).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let detail {
                Text(L10n.text(detail)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.font(.subheadline).padding(.vertical, 15).contentShape(Rectangle())
    }
}

struct FlypePrivacyNote: View {
    var body: some View {
        Label(L10n.text("Deine Stimme bleibt auf deinem Gerät."), systemImage: "lock")
            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

struct FlypeLanguageSettings: View {
    var locked = false
    var body: some View {
        Section {
            FlypeLanguageChoices(locked: locked)
        } header: {
            Text(L10n.text("Sprachen"))
        }
    }
}

/// A content-sized variant for an existing scroll view; never nests a Form or List.
struct FlypeLanguageCard: View {
    var locked = false
    var body: some View {
        FlypeCard { FlypeLanguageChoices(locked: locked, stacked: true) }
    }
}

private struct FlypeLanguageChoices: View {
    var locked = false
    var stacked = false
    @AppStorage("dictationLanguage", store: FlypePreferences.defaults) private var dictationLanguage = "de"
    @AppStorage("interfaceLanguage", store: FlypePreferences.defaults) private var interfaceLanguage = "system"
    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("Transkriptionssprache")).font(.subheadline).foregroundStyle(.secondary)
                    dictationPicker.labelsHidden().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("App-Sprache")).font(.subheadline).foregroundStyle(.secondary)
                    interfacePicker.labelsHidden().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Divider()
            } else {
                dictationPicker
                interfacePicker
            }
            Text(
                L10n.text(
                    locked
                        ? "Beende die Mikrofonbereitschaft, um die Transkriptionssprache zu wechseln."
                        : "Menüs und Transkriptionen können unterschiedliche Sprachen verwenden.")
            )
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var dictationPicker: some View {
        Picker(L10n.text("Transkriptionssprache"), selection: $dictationLanguage) {
            ForEach(FlypeLanguage.allCases, id: \.rawValue) { Text(verbatim: $0.name).tag($0.rawValue) }
        }.pickerStyle(.menu).disabled(locked)
    }
    private var interfacePicker: some View {
        Picker(L10n.text("App-Sprache"), selection: $interfaceLanguage) {
            Text(L10n.text("Wie dein Gerät")).tag("system")
            ForEach(FlypeLanguage.allCases, id: \.rawValue) { Text(verbatim: $0.name).tag($0.rawValue) }
        }.pickerStyle(.menu)
    }
}
