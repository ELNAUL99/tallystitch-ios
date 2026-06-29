import SwiftUI
import TallystitchCore

// Routing root — mirrors the RN entry + (app)/_layout gates:
//   - still loading            → spinner
//   - no session               → auth flow
//   - trial expired, no sub    → locked screen
//   - brand-new account        → onboarding
//   - otherwise                → the tab shell
struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var profile: ProfileStore

    var body: some View {
        Group {
            if auth.loading || (auth.isSignedIn && profile.loading) {
                ProgressView().tint(Palette.clay600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.cream50)
            } else if !auth.isSignedIn {
                AuthFlowView()
            } else if let p = profile.profile, !Access.hasAppAccess(status: p.subscriptionStatus, trialEndsAt: p.trialEndsAt) {
                LockedView()
            } else if let p = profile.profile, p.businessName == nil, p.onboardingCompletedAt == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        // A recovery deep link lands the user in a session but must set a new
        // password first — show that over whatever's underneath.
        .fullScreenCover(isPresented: $auth.passwordRecovery) {
            SetNewPasswordView()
        }
        // Surface a failed sign-in / recovery link instead of stranding the user.
        .alert("Couldn't sign you in",
               isPresented: Binding(get: { auth.linkError != nil },
                                    set: { if !$0 { auth.linkError = nil } })) {
            Button("OK", role: .cancel) { auth.linkError = nil }
        } message: {
            Text(auth.linkError ?? "")
        }
        // Refetch the profile whenever the signed-in user changes.
        .task(id: auth.session?.user.id) {
            if auth.isSignedIn { await profile.refresh() } else { profile.clear() }
        }
    }
}

struct LockedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Your free trial has ended").font(.title2.weight(.semibold))
            Text("Manage your subscription on the web to keep using Tallystitch. Your data is safe.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink500)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.cream50)
    }
}
