//
//  OnboardingView.swift
//  Yomuhon
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.yomuhonTheme) private var theme
    @State private var page = 0

    private let steps = OnboardingStep.all

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 32) {
                Spacer(minLength: 8)

                TabView(selection: $page) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        OnboardingCard(step: step, index: index, total: steps.count)
                            .tag(index)
                            .padding(.horizontal, 8)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #else
                .tabViewStyle(.automatic)
                #endif
                .frame(maxWidth: min(proxy.size.width - 64, 460), maxHeight: 420)

                VStack(spacing: 16) {
                    Button(action: primaryAction) {
                        Text(page == steps.count - 1 ? "onboarding.getStarted" : "onboarding.next")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(YomuhonPrimaryButtonStyle(theme: theme))

                    Button("onboarding.skip", action: onFinish)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .buttonStyle(.plain)
                }

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
    }

    private func primaryAction() {
        if page == steps.count - 1 {
            onFinish()
        } else {
            withAnimation(theme.animation) { page += 1 }
        }
    }
}

private struct OnboardingStep {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey

    static let all: [OnboardingStep] = [
        OnboardingStep(systemImage: "books.vertical.fill", titleKey: "onboarding.step1.title", subtitleKey: "onboarding.step1.subtitle"),
        OnboardingStep(systemImage: "arrow.down.circle.fill", titleKey: "onboarding.step2.title", subtitleKey: "onboarding.step2.subtitle"),
        OnboardingStep(systemImage: "book.closed.fill", titleKey: "onboarding.step3.title", subtitleKey: "onboarding.step3.subtitle")
    ]
}

private struct OnboardingCard: View {
    let step: OnboardingStep
    let index: Int
    let total: Int

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Text(String.localizedStringWithFormat(NSLocalizedString("onboarding.stepProgressFormat", comment: ""), index + 1, total))
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.secondaryBackground)
                    .frame(width: 200, height: 240)
                Image(systemName: step.systemImage)
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(theme.textPrimary.opacity(0.85))
            }

            VStack(spacing: 8) {
                Text(step.titleKey)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)
                Text(step.subtitleKey)
                    .font(YomuhonTypography.body)
                    .foregroundColor(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)

            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? theme.textPrimary : theme.separator)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
