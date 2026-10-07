import SwiftUI
import CoreImage.CIFilterBuiltins

/// A legible presentation card for iPhone screen mirroring.
struct DemoView: View {
    @Environment(\.dismiss) private var dismiss
    private let ink = Color(red: 0.10, green: 0.17, blue: 0.19)
    private let orange = Color(red: 0.87, green: 0.32, blue: 0.16)
    private let cream = Color(red: 0.97, green: 0.96, blue: 0.93)
    private let qrImage = DemoView.makeQRCode()

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let padding: CGFloat = landscape ? 28 : 24
            let side = landscape
                ? min(geometry.size.width * 0.36, geometry.size.height * 0.70, 420)
                : min(geometry.size.width * 0.78, geometry.size.height * 0.43, 420)
            Group {
                if landscape {
                    HStack(spacing: 36) {
                        identity(landscape: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        code(side: side)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: 26) {
                        identity(landscape: false)
                        code(side: side)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(padding)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(cream.ignoresSafeArea())
        .foregroundStyle(ink)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.6))
                    .padding(12)
                    .background(.white.opacity(0.7), in: Circle())
            }
            .padding(12)
            .accessibilityLabel("Close presentation screen")
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func identity(landscape: Bool) -> some View {
        VStack(alignment: landscape ? .leading : .center, spacing: landscape ? 12 : 10) {
            Text("ON YOUR IPHONE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(orange)
            Text("Adder")
                .font(.system(size: landscape ? 76 : 72, weight: .bold, design: .rounded))
                .tracking(-3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Say it. Keep the details.")
                .font(.system(size: landscape ? 24 : 22, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("On-device voice, photos, and text.\nContacts. Calendar.")
                .font(.system(size: 16))
                .foregroundStyle(ink.opacity(0.65))
                .lineSpacing(4)
                .multilineTextAlignment(landscape ? .leading : .center)
            if landscape { Spacer(minLength: 6) }
            HStack(spacing: 12) {
                brandLogo
                Rectangle().fill(ink.opacity(0.2)).frame(width: 1, height: 24)
                Text("Open source · MIT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.6))
            }
            .padding(.top, 8)
        }
    }

    private var brandLogo: some View {
        Image("ThinkunLogo")
            .resizable().scaledToFit()
            .frame(width: 160, height: 48)
            .accessibilityLabel("Thinkun, informed interactive")
    }

    private func code(side: CGFloat) -> some View {
        VStack(spacing: 15) {
            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * 0.84, height: side * 0.84)
                    .padding(side * 0.08)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("QR code for github.com/thinkun/adder")
            }
            Text("github.com/thinkun/adder")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
            Text("Scan the repository link")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(orange)
        }
    }

    private static func makeQRCode() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("https://github.com/thinkun/adder".utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage else { return nil }
        let enlarged = output.transformed(by: CGAffineTransform(scaleX: 20, y: 20))
        guard let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(enlarged, from: enlarged.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
