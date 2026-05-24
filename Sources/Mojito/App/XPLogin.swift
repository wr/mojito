import AppKit
import SwiftUI

/// Fake Windows XP welcome screen. Triggered by the keyword. Full-screen panel
/// with the iconic Luna palette: deep navy bars top & bottom, a royal-blue
/// background between, the iconic orange highlight rule above the bottom
/// bar, a vertical white divider, the Microsoft Windows XP wordmark on
/// the left, and a single user tile on the right. Click the tile to play
/// the XP startup chime and fade out.
@MainActor
enum XPLogin {
    private static var activeWindow: NSWindow?
    private static var player: NSSound?

    static func start() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        activeWindow?.orderOut(nil)
        activeWindow = nil
        player?.stop()
        player = nil

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        var cancelToken: (() -> Void)?
        let dismiss = {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                player?.stop()
                player = nil
                cancelToken?(); cancelToken = nil
                if activeWindow === panel { activeWindow = nil }
            }
        }

        // Pre-load the welcome chord NOW so the click handler doesn't pay
        // for the (synchronous) file I/O + XOR decode on the click thread.
        // Previously the load happened in onLogin and added a noticeable
        // hitch between the tap and the visible "Welcome" transition.
        let preloadedChord = AudioBlob.load("s09")

        let host = NSHostingView(rootView: XPLoginView(
            bounds: frame.size,
            onLogin: {
                MainActor.assumeIsolated {
                    if let sound = preloadedChord {
                        player = sound
                        sound.play()
                    }
                    // The XP startup chime is ~4.8s. Fade out a beat before
                    // the chime ends so the last note rings into silence.
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
    /// Mouse is currently over the tile — drives the dim-by-default state
    /// and the yellow icon border. Distinct from `pressed` so a brief
    /// hover doesn't trigger the row-bg gradient.
    @State private var isHovering = false
    /// Mouse is currently down on the tile — drives the blue gradient row
    /// background. Goes false again the instant `loadingTextVisible`
    /// fires (the "Loading personal settings…" beat replaces the press
    /// highlight visually).
    @State private var pressed = false
    /// Guards `beginLogin()` so the mousedown gesture's `onChanged` can
    /// fire many times but the login sequence only kicks off once.
    @State private var loginStarted = false

    // Tile-selected color from the WelcomeXP recreation: deep navy on the
    // left fading into the body royal on the right — the post-click
    // highlight gradient.
    private let tileSelectedDeep = Color(red: 0.055, green: 0.224, blue: 0.592) // #0E3997

    // Palette sampled pixel-by-pixel from the reference image (1024×768).
    // Every value below comes from a direct color pick at the noted (x,y).
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

    // Bars are proportional to screen height to match the reference's
    // 8.9% top / 12.2% bottom split, with sensible floors for tiny screens.
    private func topBarHeight(_ h: CGFloat) -> CGFloat   { max(64, h * 0.089) }
    private func bottomBarHeight(_ h: CGFloat) -> CGFloat { max(92, h * 0.122) }

    var body: some View {
        GeometryReader { geo in
            let topH = topBarHeight(geo.size.height)
            let bottomH = bottomBarHeight(geo.size.height)

            VStack(spacing: 0) {
                // Top bar — flat navy.
                topNavy
                    .frame(height: topH)

                // Thin 2px light-blue accent line directly under the top
                // navy bar — what every XP welcome-screen recreation puts
                // there to soften the seam. NOT a tall vertical gradient.
                topHighlight
                    .frame(height: 2)

                // Body — flat royal blue with the cloud glow + content.
                ZStack {
                    bodyRoyal
                    cloudGlowLayer
                    centerStage(width: geo.size.width)
                }
                .frame(maxHeight: .infinity)

                // Iconic orange separator — thin 2px horizontal stripe.
                bandOrange
                    .frame(height: 2)

                // Bottom bar — horizontal gradient from a purpler navy on
                // the left to a deeper navy on the right.
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
        // Double-click anywhere to bail (Esc also works via EffectDismisser).
        .onTapGesture(count: 2) { onDismiss() }
        .animation(.easeOut(duration: 0.4), value: fade)
    }

    // MARK: - Cloud glow

    /// Soft elliptical highlight in the upper-left of the body. Brightest
    /// sample in the reference is at (50, 100) inside a 1024×768 image —
    /// i.e. roughly 5% from the left edge and 5% into the body region.
    /// Falls back to the body color at ~25% of width / ~30% of body height.
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
            Text("After you log on, you can add or change accounts.\nJust go to Control Panel and click User Accounts.")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .lineSpacing(3)
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Turn off computer

    /// Small red glossy rounded square + label, sized ~28pt per the
    /// reference (smaller than the previous attempt).
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
                // Top gloss highlight — gives the button its glassy
                // XP feel without a separate specular layer.
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

            Text("Turn off computer")
                .font(.system(size: 15))
                .foregroundColor(.white)
        }
    }

    // MARK: - Center stage (Wordmark / divider / user tile)

    /// Two-column area with the Microsoft Windows XP wordmark on the left
    /// and the user tile on the right, separated by a long thin white
    /// line that fades to transparent at top and bottom.
    private func centerStage(width: CGFloat) -> some View {
        // Compute a divider height that scales with the stage. The real
        // XP divider runs most of the central area between the two bars.
        let dividerHeight = max(280, bounds.height - topBarHeight(bounds.height) - bottomBarHeight(bounds.height) - 120)
        return HStack(alignment: .center, spacing: 0) {
            // LEFT: pre-login it's the Microsoft Windows XP wordmark +
            // "click your user name" instructions. After the user clicks
            // their tile, this whole block swaps to the iconic italic
            // "Welcome" headline — the classic XP "loading your profile"
            // beat.
            ZStack(alignment: .trailing) {
                if loggingIn {
                    welcomeImage
                        .transition(.opacity)
                } else {
                    VStack(alignment: .trailing, spacing: 26) {
                        windowsXPWordmark
                        Text("To begin, click your user name")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 1)
                            // Push the subtitle's right edge inward so it
                            // aligns with the right edge of "Mojito" in
                            // the wordmark SVG (the "xp" superscript and
                            // some art extends ~46pt beyond the word).
                            .padding(.trailing, 46)
                    }
                    .transition(.opacity)
                }
            }
            // Quick cross-fade — "welcome" should appear simultaneously
            // with the blue row highlight, not lag behind it.
            .animation(.easeInOut(duration: 0.12), value: loggingIn)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 44)

            // Vertical divider — gradient transparent→white→transparent.
            // Only spans the central stage, not edge to edge.
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

            // RIGHT: single user tile, vertically centered. Mousedown
            // (not click) is what kicks off the login flow so the sound
            // fires the instant the press registers — matches the real
            // XP feel where the chord starts before the mouse releases.
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

    /// User-supplied wordmark asset (`v07.bin`, scrambled).
    private static let wordmarkImage: NSImage? = ImageBlob.load("v07")

    /// User-supplied "welcome" headline (`v11.bin`, scrambled). Replaces
    /// the prior system-font Text — the rasterized SVG ships its own
    /// italic + shadow treatment so we don't fight font availability.
    private static let welcomeImageAsset: NSImage? = ImageBlob.load("v11")

    @ViewBuilder
    private var welcomeImage: some View {
        if let img = Self.welcomeImageAsset {
            Image(nsImage: img)
                .resizable()
                // Template-tint to white so the SVG color is taken from
                // the foregroundStyle below regardless of the source.
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

    /// One row of the user list: square red avatar with chunky border,
    /// username, and (after login starts) the "Loading personal
    /// settings…" subtitle. Default state dims a touch; hover restores
    /// full opacity; mousedown shows the blue gradient row highlight.
    private var userTile: some View {
        // Row bg is on during the brief mousedown window, off again the
        // moment the "Loading personal settings…" subtitle appears.
        let rowBgVisible = pressed && !loadingTextVisible
        // Full opacity on hover / press / login; otherwise dim slightly.
        let fullyLit = isHovering || pressed || loggingIn
        return HStack(alignment: .top, spacing: 20) {
            userAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(currentUserName)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 1, y: 1)
                if loadingTextVisible {
                    Text("Loading your personal settings…")
                        .font(.system(size: 15, weight: .semibold))
                        // Deep XP-status blue — the welcome screen renders
                        // this line in a midnight-blue, not white or
                        // light blue.
                        .foregroundColor(Color(red: 0.06, green: 0.18, blue: 0.50))
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(fullyLit ? 1.0 : 0.6)
        .animation(.easeOut(duration: 0.15), value: fullyLit)
        // Equidistant padding: icon sits 10pt from top, bottom, and left
        // edges of the blue bg shape. Right side stretches with content.
        .padding(.leading, 10)
        .padding(.vertical, 10)
        .padding(.trailing, 14)
        .background(
            // Blue gradient row highlight, visible only during the brief
            // mousedown → "Loading…" reveal window.
            ZStack {
                // Rounded LEFT corners (14pt), square RIGHT edge — the
                // tile reads as a tab extending off-screen rather than a
                // detached pill.
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
                // 1.5px white 30% border on top / bottom / left edges
                // only. Inside the ZStack so it fades with the fill.
                ThreeSidedBorder(color: .white.opacity(0.3), width: 1.5, cornerRadius: 14)
            }
            .opacity(rowBgVisible ? 1 : 0)
        )
        .frame(maxWidth: loggingIn ? 540 : 460, alignment: .leading)
        .contentShape(Rectangle())
        // Pointing-hand cursor so the tile reads as clickable.
        .background(PointingHandCursorView())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    /// User-supplied avatar asset (`v08.bin`, scrambled).
    private static let avatarImage: NSImage? = ImageBlob.load("v08")

    /// Use the macOS account holder's full name on the tile. Falls back
    /// to "Administrator" (the canonical XP default) if the name string
    /// is empty for some reason.
    private var currentUserName: String {
        let name = NSFullUserName()
        return name.isEmpty ? "Administrator" : name
    }

    /// 80×80 user-tile avatar — bundled image on the deep-red field with
    /// rounded corners. Border is white at rest; turns yellow on hover or
    /// while the login sequence is running.
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
                    // No padding — the chess art covers the tile edge to
                    // edge so there's no red ring between the icon and
                    // the outer white/yellow border.
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

    /// Kicks off the login flow on first mousedown:
    /// - t=0: chord plays, blue row highlight appears (via `pressed`),
    ///        wordmark cross-fades to italic "Welcome"
    /// - t≈1s: row highlight vanishes, "Loading personal settings…"
    ///        (semibold) replaces it
    /// - t≈3.6s: whole panel fades out
    private func beginLogin() {
        guard !loginStarted else { return }
        loginStarted = true
        // Sound + Welcome reveal both fire on the press, no delay. The
        // row highlight is already visible because `pressed` was just
        // flipped to true by the DragGesture in `centerStage`.
        onLogin()
        // Fire `loggingIn` immediately (no withAnimation wrapper) so the
        // wordmark → "welcome" cross-fade is driven by the explicit
        // `.animation(.easeInOut(duration: 0.12), value: loggingIn)` on
        // the ZStack — matches the instant blue-bg appearance from
        // `pressed = true`.
        loggingIn = true
        // Phase 2 (~500ms in): "Loading personal settings…" replaces the
        // row highlight. `loadingTextVisible` flipping to true also
        // hides the row bg via `rowBgVisible = pressed && !loadingTextVisible`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.18)) {
                loadingTextVisible = true
            }
        }
        // Phase 3: fade the panel out a beat before the chime ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.easeOut(duration: 0.8)) {
                fade = 0
            }
        }
    }
}

/// Three-sided border with rounded left + square right corners — matches
/// the XP row highlight where the bg shape itself is left-rounded and
/// the right edge has no visible border.
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
            // Mask off the right edge — keep only top/bottom/left.
            HStack(spacing: 0) {
                Rectangle().fill(.black).frame(maxWidth: .infinity)
                Rectangle().fill(.clear).frame(width: width * 2)
            }
        )
    }
}

/// Backs the user tile with an NSView that registers a pointing-hand
/// cursor rect across its bounds. AppKit handles enter/exit automatically
/// via `resetCursorRects`, so we avoid the `NSCursor.push/.pop` stack
/// (which leaked the prior version's text cursor everywhere when the
/// view was destroyed mid-hover).
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

