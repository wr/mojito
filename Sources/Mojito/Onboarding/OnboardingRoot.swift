import SwiftUI

struct OnboardingRoot: View {
    /// Ordered set of onboarding screens. Adding a screen here is the entire
    /// change — the dot indicator, navigation guards, and content switch all
    /// derive from this enum.
    private enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case done

        var isFirst: Bool { self == .welcome }
        var isLast: Bool { self == .done }
    }

    @EnvironmentObject private var permissions: PermissionsCoordinator
    @State private var step: Step = .welcome
    /// Direction of the most recent step transition. Drives slide direction —
    /// trailing for forward navigation, leading for back.
    @State private var transitionEdge: Edge = .trailing
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VisualEffect(material: .windowBackground, blending: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Slide each step in/out: forward navigation slides the new step in
                // from the trailing edge and the old one out to the leading edge;
                // back navigation does the reverse. `.id(step)` is required so SwiftUI
                // treats each step as a distinct view for transition matching.
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 36)
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                    .id(step.rawValue)
                    .transition(.asymmetric(
                        insertion: .move(edge: transitionEdge).combined(with: .opacity),
                        removal: .move(edge: oppositeEdge(of: transitionEdge)).combined(with: .opacity)
                    ))
                    .clipped()

                footer
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
            }
        }
        .frame(width: 600, height: 520)
        .focusable()
        .focused($focused)
        .onAppear {
            permissions.startMonitoring(interval: 0.5)
            focused = true
        }
        .onChange(of: permissions.accessibility) { _, _ in advanceIfPermissionsSatisfied() }
        .onChange(of: permissions.inputMonitoring) { _, _ in advanceIfPermissionsSatisfied() }
        .onKeyPress(.return) {
            if primaryEnabled { primaryAction() }
            return .handled
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:           WelcomeStep()
        case .permissions:
            PermissionsStep(
                accessibilityGranted: permissions.accessibility,
                inputMonitoringGranted: permissions.inputMonitoring,
                promptAccessibility: { _ = permissions.promptAccessibility() },
                promptInputMonitoring: { _ = permissions.promptInputMonitoring() },
                openAccessibilitySettings: permissions.openAccessibilitySettings,
                openInputMonitoringSettings: permissions.openInputMonitoringSettings
            )
        case .done:              DoneStep()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { stepCase in
                    Circle()
                        .fill(stepCase == step ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if !step.isFirst && !step.isLast {
                Button("Back") { goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            // Final step gets a secondary "Open settings" action alongside
            // "Done" — saves a trip to the menu bar for users who want to
            // tweak prefs immediately after finishing setup.
            if step.isLast {
                Button("Open settings") { finishAndOpenSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button(primaryLabel) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!primaryEnabled)
        }
    }

    private func finishAndOpenSettings() {
        UserDefaults.standard.set(true, forKey: PrefsKey.onboardingComplete)
        NotificationCenter.default.post(name: .mojitoOnboardingFinished, object: nil)
        NotificationCenter.default.post(name: .mojitoShouldOpenSettings, object: nil)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Get started"
        case .done:    return "Done"
        default:       return "Continue"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .permissions: return permissions.accessibility && permissions.inputMonitoring
        default:           return true
        }
    }

    private func primaryAction() {
        if step.isLast {
            UserDefaults.standard.set(true, forKey: PrefsKey.onboardingComplete)
            NotificationCenter.default.post(name: .mojitoOnboardingFinished, object: nil)
        } else {
            goForward()
            advanceIfPermissionsSatisfied()
        }
    }

    private func goForward() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        transitionEdge = .trailing
        withAnimation(.easeInOut(duration: 0.32)) { step = next }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        transitionEdge = .leading
        withAnimation(.easeInOut(duration: 0.32)) { step = prev }
    }

    /// If the user lands on the permissions step (manually, or from a forward-arrow click)
    /// and both permissions are already granted, skip ahead. Same for the live-permission
    /// transition — granting both should auto-advance without forcing a button press.
    private func advanceIfPermissionsSatisfied() {
        guard step == .permissions,
              permissions.accessibility,
              permissions.inputMonitoring else { return }
        goForward()
    }

    private func oppositeEdge(of edge: Edge) -> Edge {
        switch edge {
        case .leading: return .trailing
        case .trailing: return .leading
        case .top: return .bottom
        case .bottom: return .top
        }
    }
}

extension Notification.Name {
    static let mojitoOnboardingFinished = Notification.Name("mojitoOnboardingFinished")
    /// Posted by the "Open settings" secondary action on the final onboarding
    /// step, and by the menu-bar's Settings command. `AppDelegate` listens
    /// and routes to its `SettingsWindowController`.
    static let mojitoShouldOpenSettings = Notification.Name("mojitoShouldOpenSettings")
    /// Posted by the menu bar's Option-Settings… alternate item. Re-runs the
    /// guided setup without resetting onboarding state.
    static let mojitoShouldShowOnboarding = Notification.Name("mojitoShouldShowOnboarding")
}
