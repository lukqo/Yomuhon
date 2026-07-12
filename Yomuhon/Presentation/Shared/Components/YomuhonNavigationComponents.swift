//
//  YomuhonNavigationComponents.swift
//  Yomuhon
//

import SwiftUI

struct YomuhonNavigationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    var isEnabled = true
}

struct YomuhonSidebar: View {
    let items: [YomuhonNavigationItem]
    @Binding var selectedID: String
    let onSelect: (YomuhonNavigationItem) -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Button {
                        guard item.isEnabled else {
                            return
                        }

                        selectedID = item.id
                        onSelect(item)
                    } label: {
                        YomuhonSidebarRow(
                            title: item.title,
                            systemImage: item.systemImage,
                            isSelected: selectedID == item.id
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isEnabled)
                    .listRowInsets(EdgeInsets(top: YomuhonSpacing.small, leading: YomuhonSpacing.small, bottom: YomuhonSpacing.small, trailing: YomuhonSpacing.small))
                    .listRowBackground(theme.sidebar)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: safePositiveDimension(YomuhonLayout.sidebarMinWidth, fallback: 240))
        .background(theme.sidebar)
    }
}

struct YomuhonToolbar<Search: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let search: Search
    let actions: Actions

    @Environment(\.yomuhonTheme) private var theme

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder search: () -> Search,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.search = search()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: YomuhonSpacing.large) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(title)
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: YomuhonSpacing.medium)

            search

            HStack(spacing: YomuhonSpacing.small) {
                actions
            }
        }
        .padding(.horizontal, YomuhonSpacing.large)
        .padding(.vertical, YomuhonSpacing.medium)
        .background(theme.background)
    }
}

extension YomuhonToolbar where Search == EmptyView {
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.search = EmptyView()
        self.actions = actions()
    }
}

extension YomuhonToolbar where Actions == EmptyView {
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder search: () -> Search
    ) {
        self.title = title
        self.subtitle = subtitle
        self.search = search()
        self.actions = EmptyView()
    }
}

extension YomuhonToolbar where Search == EmptyView, Actions == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.search = EmptyView()
        self.actions = EmptyView()
    }
}

struct YomuhonTabBar<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    let content: Content

    init(selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        _selection = selection
        self.content = content()
    }

    var body: some View {
        TabView(selection: $selection) {
            content
        }
    }
}

struct YomuhonIconButton: View {
    let systemName: String
    let accessibilityLabel: LocalizedStringKey
    var isSelected = false
    var isEnabled = true
    let action: () -> Void

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(YomuhonTypography.calloutSemibold)
                .foregroundColor(isSelected ? theme.accent : theme.textSecondary)
                .frame(
                    width: safePositiveDimension(YomuhonSpacing.extraLarge, fallback: 40),
                    height: safePositiveDimension(YomuhonSpacing.extraLarge, fallback: 40)
                )
                .background(isSelected ? theme.secondaryBackground.opacity(0.72) : theme.card.opacity(0))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(YomuhonPressableButtonStyle(theme: theme))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel(accessibilityLabel)
    }
}
