import SwiftUI

/// Icon, title and one-line subtitle at the top of a setup screen or sheet.
/// Follow it with `OnboardingHeader.contentSpacing` before the content.
struct OnboardingHeader: View {
    static let contentSpacing: CGFloat = 22
    /// A grouped `Form` already insets its first section by about 20 pt.
    static let formSpacing: CGFloat = contentSpacing - 20

    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 480)
    }
}
