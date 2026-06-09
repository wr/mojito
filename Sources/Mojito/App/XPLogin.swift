import AppKit
import SwiftUI

/// Fake Windows XP welcome screen in the Luna palette. Click the user
/// tile to play the startup chime and fade out.
@MainActor
enum XPLogin {
    private static var activeWindow: NSWindow?
    private static var player: NSSound?

    static func start() {
        guard let frame = ParticlePanel.primaryScreenFrame() else { return }

        activeWindow?.orderOut(nil)
        activeWindow = nil
        player?.stop()
        player = nil

        // Interactive: the user tile takes clicks/hover.
        let panel = ParticlePanel.makeFullScreen(frame: frame, interactive: true, backgroundColor: .black)

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                ParticlePanel.dismiss(panel)
                player?.stop()
                player = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }

        // Preload so the click handler doesn't pay for the synchronous
        // file I/O + XOR decode — would hitch the "Welcome" transition.
        let preloadedChord = AudioBlob.load("s09")

        let host = NSHostingView(rootView: XPLoginView(
            bounds: frame.size,
            onLogin: {
                MainActor.assumeIsolated {
                    if let sound = preloadedChord {
                        player = sound
                        sound.play()
                    }
                    // Chime is ~4.8s. Fade out a beat early so the last
                    // note rings into silence.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) {
                        MainActor.assumeIsolated { dismiss() }
                    }
                }
            },
            onDismiss: dismiss
        ))
        host.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = host
        panel.orderFrontRegardless()
        activeWindow = panel

        cancelToken = EffectDismisser.register(dismiss)
    }
}

private struct XPLoginView: View {
    let bounds: CGSize
    let onLogin: () -> Void
    let onDismiss: () -> Void

    @State private var loggingIn = false
    @State private var loadingTextVisible = false
    @State private var fade: Double = 1.0
    /// Hover dims the un-pressed state; distinct from `pressed` so a
    /// brief hover doesn't trigger the row-bg gradient.
    @State private var isHovering = false
    /// Drives the blue row-bg. Cleared the instant `loadingTextVisible`
    /// fires — the "Loading…" line replaces the press highlight.
    @State private var pressed = false
    /// One-shot guard around `beginLogin` — DragGesture.onChanged can
    /// fire repeatedly.
    @State private var loginStarted = false

    // Post-click highlight gradient (deep navy → body royal).
    private let tileSelectedDeep = Color(red: 0.055, green: 0.224, blue: 0.592) // #0E3997

    // Palette sampled pixel-by-pixel from the reference image (1024×768)
    // at the noted (x,y).
    private let bodyRoyal     = Color(red: 0.353, green: 0.494, blue: 0.863) // #5A7EDC at (512,400)
    private let cloudGlow     = Color(red: 0.561, green: 0.682, blue: 0.933) // #8FAEEE at (50,100)
    private let topNavy       = Color(red: 0.000, green: 0.188, blue: 0.612) // #00309C top bar uniform
    private let bottomLeft    = Color(red: 0.200, green: 0.200, blue: 0.671) // #3333AB at (100,720)
    private let bottomRight   = Color(red: 0.027, green: 0.184, blue: 0.620) // #072F9E at (974,720)
    private let bandOrange    = Color(red: 0.902, green: 0.557, blue: 0.235) // #E68E3C at (400,672)
    private let bandOrangeDeep = Color(red: 0.640, green: 0.300, blue: 0.130) // shaded base of orange stripe
    private let topHighlight  = Color(red: 0.760, green: 0.860, blue: 0.965) // soft band under top navy bar
    private let tileYellow    = Color(red: 1.000, green: 0.835, blue: 0.290) // #FFD54A tile border
    private let tileRed       = Color(red: 0.580, green: 0.078, blue: 0.078) // tile background top
    private let tileRedDeep   = Color(red: 0.380, green: 0.040, blue: 0.040) // tile background bottom
    private let chessGold     = Color(red: 0.980, green: 0.820, blue: 0.380) // gold pieces
    private let chessGoldDark = Color(red: 0.720, green: 0.520, blue: 0.150) // shading
    private let powerRed      = Color(red: 0.898, green: 0.314, blue: 0.133) // power button
    private let powerRedDark  = Color(red: 0.667, green: 0.137, blue: 0.000) // power button deep

    // Reference splits 8.9% top / 12.2% bottom; floors for tiny screens.
    private func topBarHeight(_ h: CGFloat) -> CGFloat   { max(64, h * 0.089) }
    private func bottomBarHeight(_ h: CGFloat) -> CGFloat { max(92, h * 0.122) }

    var body: some View {
        GeometryReader { geo in
            let topH = topBarHeight(geo.size.height)
            let bottomH = bottomBarHeight(geo.size.height)

            VStack(spacing: 0) {
                topNavy
                    .frame(height: topH)

                // 2px accent line softens the seam under the top bar.
                // Not a tall vertical gradient.
                topHighlight
                    .frame(height: 2)

                ZStack {
                    bodyRoyal
                    cloudGlowLayer
                    centerStage(width: geo.size.width)
                }
                .frame(maxHeight: .infinity)

                // Iconic orange stripe.
                bandOrange
                    .frame(height: 2)

                // Bottom bar: purple-navy → deep navy.
                ZStack {
                    LinearGradient(
                        colors: [bottomLeft, bottomRight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    bottomBarContent
                }
                .frame(height: bottomH)
            }
            .opacity(fade)
        }
        .frame(width: bounds.width, height: bounds.height)
        .contentShape(Rectangle())
        // Double-click anywhere bails (Esc also works via EffectDismisser).
        .onTapGesture(count: 2) { onDismiss() }
        .animation(.easeOut(duration: 0.4), value: fade)
    }

    // MARK: - Cloud glow

    /// Soft upper-left elliptical highlight. Brightest point sampled at
    /// (50,100) in the 1024×768 reference (≈ 5% in, 5% down).
    private var cloudGlowLayer: some View {
        GeometryReader { g in
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: cloudGlow,            location: 0.00),
                    .init(color: cloudGlow.opacity(0), location: 1.00)
                ]),
                center: UnitPoint(x: 0.06, y: 0.08),
                startRadius: 0,
                endRadius: max(g.size.width, g.size.height) * 0.32
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bottom bar content

    private var bottomBarContent: some View {
        HStack(spacing: 0) {
            turnOffControl
            Spacer()
            Text(verbatim: "After you log on, you can add or change accounts.\nJust go to Control Panel and click User Accounts.")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .lineSpacing(3)
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Turn off computer

    /// 28pt red glossy rounded square + label.
    private var turnOffControl: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [powerRed, powerRedDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Top gloss — fakes the XP glassy feel without a
                // separate specular layer.
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    .blur(radius: 0.5)
                    .padding(1.2)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.45), lineWidth: 1)
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }
            .frame(width: 28, height: 28)

            Text(verbatim: "Turn off computer")
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
    }

    // MARK: - Center stage (Wordmark / divider / user tile)

    /// Two columns separated by a transparent→white→transparent divider:
    /// wordmark on the left, user tile on the right.
    private func centerStage(width: CGFloat) -> some View {
        let dividerHeight = max(280, bounds.height - topBarHeight(bounds.height) - bottomBarHeight(bounds.height) - 120)
        return HStack(alignment: .center, spacing: 0) {
            // Pre-login: wordmark + instructions. Once the tile is
            // pressed, swap to the italic "Welcome" headline.
            ZStack(alignment: .trailing) {
                if loggingIn {
                    welcomeImage
                        .transition(.opacity)
                } else {
                    VStack(alignment: .trailing, spacing: 26) {
                        windowsXPWordmark
                        Text(verbatim: "To begin, click your user name")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 1)
                            // Pull subtitle's right edge in to align with
                            // "Mojito" — the "xp" + art extends ~46pt past.
                            .padding(.trailing, 46)
                    }
                    .transition(.opacity)
                }
            }
            // 120ms so "Welcome" appears with the blue row highlight,
            // not after it.
            .animation(.easeInOut(duration: 0.12), value: loggingIn)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 44)

            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.0), location: 0.00),
                    .init(color: Color.white.opacity(0.85), location: 0.50),
                    .init(color: Color.white.opacity(0.0), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1, height: dividerHeight)

            // Mousedown (not click) kicks off the login so the chord fires
            // before the mouse releases — matches the real XP feel.
            VStack(alignment: .leading, spacing: 12) {
                userTile
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !pressed { pressed = true }
                                beginLogin()
                            }
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 44)
        }
    }

    // MARK: - Microsoft Windows XP wordmark + "welcome" headline

    /// Bundled wordmark (`v07.bin`, scrambled).
    private static let wordmarkImage: NSImage? = ImageBlob.load("v07")

    /// Bundled "welcome" headline (`v11.bin`, scrambled). Pre-rendered so
    /// we don't depend on a specific system italic being available.
    private static let welcomeImageAsset: NSImage? = ImageBlob.load("v11")

    @ViewBuilder
    private var welcomeImage: some View {
        if let img = Self.welcomeImageAsset {
            Image(nsImage: img)
                .resizable()
                // Template-tint so the foregroundStyle below wins over
                // the source SVG color.
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 50)
                .foregroundStyle(.white)
                .shadow(color: tileSelectedDeep.opacity(0.7), radius: 0, x: 3, y: 3)
        }
    }

    @ViewBuilder
    private var windowsXPWordmark: some View {
        if let img = Self.wordmarkImage {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 150)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
        }
    }

    // MARK: - User tile

    /// User-list row: avatar + username, plus the "Loading…" subtitle
    /// once login starts. Dim until hover/press; blue row-bg on press.
    private var userTile: some View {
        // Row bg replaces the press highlight when "Loading…" appears.
        let rowBgVisible = pressed && !loadingTextVisible
        let fullyLit = isHovering || pressed || loggingIn
        return HStack(alignment: .top, spacing: 20) {
            userAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(currentUserName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 1, y: 1)
                if loadingTextVisible {
                    Text(verbatim: "Loading your personal settings…")
                        .font(.system(size: 15, weight: .semibold))
                        // Midnight blue per the reference, not light blue.
                        .foregroundColor(Color(red: 0.06, green: 0.18, blue: 0.50))
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(fullyLit ? 1.0 : 0.6)
        .animation(.easeOut(duration: 0.15), value: fullyLit)
        // Icon sits 10pt from top/bottom/left of the bg shape.
        .padding(.leading, 10)
        .padding(.vertical, 10)
        .padding(.trailing, 14)
        .background(
            // Visible only between mousedown and the "Loading…" reveal.
            ZStack {
                // Square right edge so the tile reads as a tab running
                // off-screen, not a detached pill.
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 14, bottomLeading: 14,
                                       bottomTrailing: 0, topTrailing: 0),
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [tileSelectedDeep, bodyRoyal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // Inside the ZStack so the border fades with the fill.
                ThreeSidedBorder(color: .white.opacity(0.3), width: 1.5, cornerRadius: 14)
            }
            .opacity(rowBgVisible ? 1 : 0)
        )
        .frame(maxWidth: loggingIn ? 540 : 460, alignment: .leading)
        .contentShape(Rectangle())
        .background(PointingHandCursorView())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    /// Bundled avatar (`v08.bin`, scrambled).
    private static let avatarImage: NSImage? = ImageBlob.load("v08")

    /// Fall back to "Administrator" (the canonical XP default).
    private var currentUserName: String {
        let name = NSFullUserName()
        return name.isEmpty ? "Administrator" : name
    }

    /// White border at rest, yellow on hover / during login.
    private var userAvatar: some View {
        let corner: CGFloat = 6
        let highlighted = isHovering || pressed || loggingIn
        return ZStack {
            LinearGradient(
                colors: [tileRed, tileRedDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            if let img = Self.avatarImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // No padding — art covers edge to edge, no red ring.
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(highlighted ? tileYellow : Color.white, lineWidth: highlighted ? 3 : 2)
        )
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 1)
    }

    /// Login flow:
    /// - t=0: chord plays, blue row-bg shows (`pressed` just flipped),
    ///        wordmark cross-fades to "Welcome"
    /// - t≈0.5s: row-bg vanishes, "Loading personal settings…" replaces it
    /// - t≈3.6s: panel fades out
    private func beginLogin() {
        guard !loginStarted else { return }
        loginStarted = true
        onLogin()
        // No withAnimation wrapper — the explicit `.animation(...)`
        // on the ZStack drives the 120ms cross-fade.
        loggingIn = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.18)) {
                loadingTextVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.easeOut(duration: 0.8)) {
                fade = 0
            }
        }
    }
}

/// Rounded left + square right, no right-edge border.
private struct ThreeSidedBorder: View {
    let color: Color
    let width: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: cornerRadius, bottomLeading: cornerRadius,
                               bottomTrailing: 0, topTrailing: 0),
            style: .continuous
        )
        .strokeBorder(color, lineWidth: width)
        .mask(
            // Keep only top/bottom/left.
            HStack(spacing: 0) {
                Rectangle().fill(.black).frame(maxWidth: .infinity)
                Rectangle().fill(.clear).frame(width: width * 2)
            }
        )
    }
}

/// Cursor rect via AppKit's `resetCursorRects` — avoids the
/// `NSCursor.push/.pop` stack, which leaked the text cursor when the
/// view was destroyed mid-hover.
private struct PointingHandCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorRectView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CursorRectView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

