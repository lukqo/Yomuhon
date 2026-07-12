//
//  SourcesView.swift
//  Yomuhon
//

import SwiftUI

struct SourcesView: View {
    @StateObject private var viewModel: SourcesViewModel
    @Environment(\.yomuhonTheme) private var theme

    init(viewModel: SourcesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    header
                    availabilityCard
                    sourceList

                    #if DEBUG
                    diagnosticsCard
                    #endif
                }
                .frame(maxWidth: 880, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                .padding(.top, YomuhonSpacing.extraLarge)
                .padding(.bottom, YomuhonSpacing.grand)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .onAppear {
            viewModel.performScheduledMaintenanceIfNeeded()
        }
        .animation(theme.animation, value: viewModel.repositoryItems)
        .animation(theme.animation, value: viewModel.healthAutomationState)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text("settings.readingSources")
                .font(YomuhonTypography.largeTitle)
                .foregroundColor(theme.textPrimary)

            Text("sources.product.subtitle")
                .font(YomuhonTypography.body)
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var availabilityCard: some View {
        HStack(alignment: .center, spacing: YomuhonSpacing.large) {
            Image(systemName: viewModel.healthAutomationState == .checking ? "arrow.triangle.2.circlepath" : "books.vertical.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(theme.secondaryBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(summaryTitle)
                    .font(YomuhonTypography.headline)
                    .foregroundColor(theme.textPrimary)

                Text("sources.product.summary.message")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: YomuhonSpacing.medium)

            if viewModel.healthAutomationState == .checking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.48 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var summaryTitle: String {
        if viewModel.healthAutomationState == .checking {
            return String(localized: "sources.product.updating")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("sources.product.availableFormat", comment: ""),
            viewModel.healthyAdapterCount
        )
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text("sources.product.list.title")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(theme.textPrimary)

                Text("sources.product.list.subtitle")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.repositoryItems.isEmpty {
                YomuhonEmptyState(
                    systemImage: "books.vertical",
                    title: "sources.empty.title",
                    message: "sources.empty.message"
                )
                .frame(minHeight: 220)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.repositoryItems) { item in
                        SourceAvailabilityRow(item: item)

                        if item.id != viewModel.repositoryItems.last?.id {
                            Rectangle()
                                .fill(theme.separator.opacity(0.65))
                                .frame(height: 1)
                                .padding(.leading, 76)
                        }
                    }
                }
                .background(theme.card.opacity(theme.id == .ink ? 0.48 : 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    #if DEBUG
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            Label("sources.product.debug.title", systemImage: "wrench.and.screwdriver")
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            Text("sources.product.debug.message")
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)

            Button {
                viewModel.testAllSources()
            } label: {
                Label(viewModel.diagnosticsButtonTitle, systemImage: "stethoscope")
            }
            .buttonStyle(YomuhonSecondaryButtonStyle(theme: theme))
            .disabled(viewModel.healthAutomationState == .checking)
        }
        .padding(YomuhonSpacing.large)
        .background(theme.card.opacity(theme.id == .ink ? 0.42 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.52), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    #endif

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 560 { return YomuhonSpacing.medium }
        if width < 900 { return YomuhonSpacing.extraLarge }
        return YomuhonSpacing.grand
    }
}

private struct SourceAvailabilityRow: View {
    let item: SourceRepositoryRowItem
    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: item.isOperational ? "books.vertical.fill" : "books.vertical")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(theme.secondaryBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: YomuhonSpacing.small) {
                    Text(item.title)
                        .font(YomuhonTypography.calloutSemibold)
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(item.language)
                        .font(YomuhonTypography.captionMedium)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.secondaryBackground.opacity(0.7))
                        .clipShape(Capsule())
                }

                Text(item.statusMessage)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: YomuhonSpacing.medium)

            HStack(spacing: 7) {
                Image(systemName: item.isOperational ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                Text(item.statusTitle)
                    .lineLimit(1)
            }
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.statusTitle)
        }
        .padding(YomuhonSpacing.medium)
        .contentShape(Rectangle())
    }
}
