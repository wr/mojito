import SwiftUI

struct OnboardingRoot: View {
    /// Adding a screen is a one-line change — dots, nav guards, and
    /// content switch all derive from this enum.
    private enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case done

        var isFirst: Bool { self == .welcome }
        var isLast: Bool { self == .done }
    }

    @EnvironmentObject private var permissions: PermissionsCoordinator
    @State private var step: Step
    /// `.trailing` = forward, `.leading` = back.
    @State private var transitionEdge: Edge = .trailing
    @FocusState private var focused: Bool

    init() {
        _step = State(initialValue: Self.resumeStep())
    }

    /// Where to open onboarding. A fresh Accessibility grant sometimes only
    /// registers after a quit+reopen, so we persist the current step and
    /// resume there rather than bouncing the user back to the welcome screen.
    /// The step is cleared on completion; the celebratory final step is never
    /// resumed into.
    private static func resumeStep() -> Step {
        if let raw = UserDefaults.standard.object(forKey: PrefsKey.onboardingStep) as? Int,
           let saved = Step(rawValue: raw), saved != .done {
            return saved
        }
        return .welcome
    }

    var body: some View {
        ZStack {
            VisualEffect(material: .windowBackground, blending: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // `.id(step)` is required so SwiftUI treats each step as
                // a distinct view for transition matching.
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
        .onChange(of: step) { _, new in
            UserDefaults.standard.set(new.rawValue, forKey: PrefsKey.onboardingStep)
        }
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

            // Saves a trip to the menu bar for users tweaking prefs
            // right after setup.
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
        completeOnboarding()
        NotificationCenter.default.post(name: .mojitoShouldOpenSettings, object: nil)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: PrefsKey.onboardingComplete)
        UserDefaults.standard.removeObject(forKey: PrefsKey.onboardingStep)
        NotificationCenter.default.post(name: .mojitoOnboardingFinished, object: nil)
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return String(localized: "Get started")
        case .done:    return String(localized: "Done")
        default:       return String(localized: "Continue")
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
            completeOnboarding()
        } else {
            goForward()
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
    static let mojitoShouldOpenSettings = Notification.Name("mojitoShouldOpenSettings")
    /// Re-runs guided setup without resetting onboarding state.
    static let mojitoShouldShowOnboarding = Notification.Name("mojitoShouldShowOnboarding")
}
