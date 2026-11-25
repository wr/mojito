import Testing
@testable import Mojito

struct ControlAccessTests {

    private func resolve(
        trusted: Bool = true,
        scopedGrants: Bool = true,
        launchReadingValid: Bool = true,
        canPostAtLaunch: Bool = true,
        keysArriving: Bool = false
    ) -> ControlAccess {
        ControlAccess.resolve(
            trusted: trusted,
            scopedGrants: scopedGrants,
            launchReadingValid: launchReadingValid,
            canPostAtLaunch: canPostAtLaunch,
            keysArriving: keysArriving
        )
    }

    @Test func untrustedIsNoneWhateverElseSays() {
        #expect(resolve(trusted: false) == .none)
        #expect(resolve(trusted: false, scopedGrants: false) == .none)
        #expect(resolve(trusted: false, keysArriving: true) == .none)
    }

    @Test func systemsWithoutScopedGrantsAreFullOnceTrusted() {
        #expect(resolve(scopedGrants: false, launchReadingValid: false, canPostAtLaunch: false) == .full)
    }

    @Test func trustedAtLaunchWithPostAccessIsFull() {
        #expect(resolve(canPostAtLaunch: true) == .full)
    }

    @Test func trustedAtLaunchWithoutPostAccessIsLimited() {
        #expect(resolve(canPostAtLaunch: false) == .limited)
    }

    @Test func grantThatArrivedWhileRunningIsUnverified() {
        #expect(resolve(launchReadingValid: false, canPostAtLaunch: false) == .unverified)
        #expect(resolve(launchReadingValid: false, canPostAtLaunch: true) == .unverified)
    }

    @Test func aKeyThroughTheTapProvesFullAccess() {
        #expect(resolve(canPostAtLaunch: false, keysArriving: true) == .full)
        #expect(resolve(launchReadingValid: false, canPostAtLaunch: false, keysArriving: true) == .full)
    }

    @Test func onlyLimitedBlocksUse() {
        #expect(ControlAccess.full.isUsable)
        #expect(ControlAccess.unverified.isUsable)
        #expect(!ControlAccess.limited.isUsable)
        #expect(!ControlAccess.none.isUsable)
    }
}
