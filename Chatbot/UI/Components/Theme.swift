import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Black canvas, pink-to-purple glow, outlined cards.
enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.13)
    static let surfaceRaised = Color(white: 0.18)
    static let stroke = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.12)

    static let pink = Color(red: 0.96, green: 0.47, blue: 0.62)
    static let magenta = Color(red: 0.84, green: 0.30, blue: 0.83)
    static let purple = Color(red: 0.62, green: 0.24, blue: 0.95)
    static let orange = Color(red: 1.00, green: 0.66, blue: 0.40)
    static let accent = magenta

    static let gradient = LinearGradient(colors: [pink, magenta, purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let bubble = LinearGradient(colors: [Color(red: 0.88, green: 0.42, blue: 0.62), purple], startPoint: .leading, endPoint: .trailing)
    static let icon = LinearGradient(colors: [orange, pink, purple], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let display = Font.system(size: 31, weight: .medium).width(.expanded)
}

/// The soft pink/magenta glow at the top of the home screen.
struct GlowBackground: View {
    var height: CGFloat = 440

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            ZStack {
                RadialGradient(colors: [Theme.pink.opacity(0.85), .clear], center: UnitPoint(x: 0.12, y: 0.05), startRadius: 10, endRadius: 260)
                RadialGradient(colors: [Theme.magenta.opacity(0.9), .clear], center: UnitPoint(x: 0.78, y: 0.0), startRadius: 10, endRadius: 320)
                RadialGradient(colors: [Theme.purple.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 260)
            }
            .frame(height: height)
            .mask(LinearGradient(colors: [.black, .black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

/// A persona's icon in a dark circle, drawn with the orange-pink-purple gradient.
struct PersonaAvatar: View {
    var symbol: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Theme.icon)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(white: 0.08)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .opacity(0.25 + 0.75 * max(0, sin(t * 4 - Double(i) * 0.7)))
                }
            }
        }
        .accessibilityLabel("Writing")
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.8))
            TextField("Search…", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// An image thumbnail, or a document tile with its name.
struct AttachmentThumb: View {
    let attachment: Attachment
    var size: CGFloat = 64

    var body: some View {
        Group {
            if attachment.kind == .image, let image = ThumbnailCache.shared.image(for: attachment) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                    Text(attachment.filename)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(6)
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// Small icon-only button used in message action rows.
struct IconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityLabel(label)
        .help(label)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

extension EnvironmentValues {
    /// Leaves the current chat (pops on iPhone, clears the selection on Mac and iPad).
    @Entry var closeChat: () -> Void = {}
}
