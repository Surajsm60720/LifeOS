import SwiftUI

/// Full-screen gate shown whenever `AppLockManager.isLocked` is true.
/// Presented as a `fullScreenCover` so it also covers any sheet that was
/// open when the app was backgrounded.
struct AppLockScreen: View {
    let appLock: AppLockManager

    var body: some View {
        ZStack {
            LifeOSTheme.canvas.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: appLock.mode.systemImage)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(LifeOSTheme.accent)

                VStack(spacing: 6) {
                    Text("LifeOS is Locked")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Unlock with \(appLock.biometryName) or your passcode.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Haptics.light()
                    appLock.authenticate()
                } label: {
                    Label("Unlock", systemImage: appLock.mode.systemImage)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeOSTheme.accent)
                .padding(.top, 4)

                if let error = appLock.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled()
        .onAppear { appLock.authenticate() }
    }
}
