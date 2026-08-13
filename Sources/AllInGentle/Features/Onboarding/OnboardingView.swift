import SwiftUI

/// First-launch onboarding sheet with three steps.
public struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step: Step = .welcome

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.large) {
            stepContent

            HStack(spacing: AGSpacing.small) {
                if step != .welcome {
                    AGButton("onboarding.back", systemImage: "chevron.left", variant: .ghost) {
                        withAnimation { step = step.previous }
                    }
                }

                Spacer()

                AGButton(
                    step == .ready ? "onboarding.finish" : "onboarding.next",
                    systemImage: step == .ready ? "checkmark" : "chevron.right",
                    variant: .primary
                ) {
                    withAnimation {
                        if step == .ready {
                            appState.dismissOnboarding()
                        } else {
                            step = step.next
                        }
                    }
                }
            }
        }
        .padding(AGSpacing.xLarge)
        .frame(minWidth: 520, maxWidth: 560, minHeight: 320, maxHeight: 400, alignment: .topLeading)
        .background(AGColors.background)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingStep(
                systemImage: "sparkles",
                titleKey: "onboarding.welcome.title",
                messageKey: "onboarding.welcome.message"
            )
        case .integrations:
            OnboardingStep(
                systemImage: "network",
                titleKey: "onboarding.integrations.title",
                messageKey: "onboarding.integrations.message"
            )
        case .ready:
            OnboardingStep(
                systemImage: "arrow.right.circle",
                titleKey: "onboarding.ready.title",
                messageKey: "onboarding.ready.message"
            )
        }
    }

    private enum Step: CaseIterable {
        case welcome, integrations, ready

        var next: Step {
            switch self {
            case .welcome: return .integrations
            case .integrations: return .ready
            case .ready: return .ready
            }
        }

        var previous: Step {
            switch self {
            case .welcome: return .welcome
            case .integrations: return .welcome
            case .ready: return .integrations
            }
        }
    }
}

private struct OnboardingStep: View {
    let systemImage: String
    let titleKey: String
    let messageKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: AGSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: AGSpacing.xxLarge, weight: .light))
                .foregroundStyle(AGColors.accent)

            Text(L(titleKey))
                .font(AGTypography.title)
                .foregroundStyle(AGColors.textPrimary)

            Text(L(messageKey))
                .font(AGTypography.body)
                .foregroundStyle(AGColors.textSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
