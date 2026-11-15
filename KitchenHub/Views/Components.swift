import SwiftUI
import CoreImage.CIFilterBuiltins

/// Rounded card surface using adaptive system colours (works in light and dark mode).
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Color.accentColor) }
            Text(title).font(.title2.bold())
        }
    }
}

struct RecipeImage: View {
    let url: String?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.orange.opacity(0.35), Color.pink.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let s = url, let local = RecipePhotoStore.image(for: s) {
                // Imported photos/screenshots: show the top of the page (where the title
                // usually is) rather than the middle, which is often blank on a screenshot.
                Color.clear.overlay(alignment: .top) {
                    Image(uiImage: local).resizable().scaledToFill()
                }
            } else if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "fork.knife").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9))
    }
}

struct QRCodeView: View {
    let text: String
    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Pill showing time/serves metadata.
struct MetaPill: View {
    let symbol: String
    let text: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// A tappable chip that starts a timer for a duration found in a method step.
struct TimerChip: View {
    @Environment(TimerStore.self) private var timers
    @Environment(HubModel.self) private var hub
    let match: DurationDetector.Match
    let label: String
    var large = false

    var body: some View {
        Button {
            timers.start(label: label, seconds: TimeInterval(match.seconds))
            hub.show(Toast(message: "\(TimeInterval(match.seconds).clockText) timer started", symbol: "timer"))
        } label: {
            Label(match.label, systemImage: "timer")
                .font(large ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .padding(.horizontal, large ? 18 : 12).padding(.vertical, large ? 10 : 6)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
