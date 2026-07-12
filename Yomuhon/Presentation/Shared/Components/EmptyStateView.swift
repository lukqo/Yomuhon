//
//  EmptyStateView.swift
//  Yomuhon
//

import SwiftUI

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        YomuhonEmptyState(title: title, message: message)
    }
}
