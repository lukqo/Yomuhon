//
//  ReaderView.swift
//  Yomuhon
//

import SwiftUI
import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

struct ReaderView: View {
    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.yomuhonTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var controlsAutoHideWorkItem: DispatchWorkItem?
    @State private var showsQuickMenu = false
    @State private var readerViewportWidth: CGFloat = 0
    @State private var readerProgressFrame: CGRect = .zero
    @State private var pencilHoverLocation: CGPoint?
    @State private var pencilHoverPageIndex: Int?
    #if os(macOS)
    @State private var keyboardMonitor: Any?
    #endif
    private let onClose: (() -> Void)?

    init(viewModel: ReaderViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            readerBackground
                .ignoresSafeArea()

            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                ApplePencilReaderInteractionView(
                    onHoverChanged: handlePencilHoverChanged,
                    onPencilTap: handlePencilTap,
                    onPencilDoubleTap: handlePencilDoubleTap
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            #endif

            if viewModel.isLoadingPages {
                loadingState
            } else if viewModel.pages.isEmpty {
                emptyState
            } else {
                content
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleControls()
                    }
            }

            if viewModel.showsControls, !viewModel.pages.isEmpty {
                readerHUD
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
            }

            if let message = viewModel.chapterTransitionMessage {
                chapterTransitionToast(message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .accessibilityIdentifier(readerContentAccessibilityIdentifier)
        .onAppear {
            viewModel.markOpened()
            viewModel.loadPagesIfNeeded()
            prefetchNearbyPages()
            viewModel.handleReaderPositionChanged()
            scheduleControlsAutoHide()
            #if os(macOS)
            installKeyboardMonitorIfNeeded()
            #endif
        }
        .onDisappear {
            viewModel.flushProgress()
            cancelControlsAutoHide()
            #if os(macOS)
            removeKeyboardMonitor()
            #endif
        }
        .onChange(of: viewModel.showsControls) { isShowing in
            if isShowing {
                scheduleControlsAutoHide()
            } else {
                readerProgressFrame = .zero
                pencilHoverPageIndex = nil
                cancelControlsAutoHide()
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _ in
            prefetchNearbyPages()
            viewModel.handleReaderPositionChanged()
        }
        .onChange(of: viewModel.pages) { _ in
            prefetchNearbyPages()
            viewModel.handleReaderPositionChanged()
        }
        .onChange(of: viewModel.prefetchedNextChapterPreviewPages) { _ in
            prefetchNextChapterPreviewImages()
        }
        .onChange(of: viewModel.readingMode) { newMode in
            if newMode != .paged {
                pencilHoverPageIndex = nil
                readerProgressFrame = .zero
            }
            viewModel.handleReaderPositionChanged()
        }
        .onPreferenceChange(ReaderProgressFramePreferenceKey.self) { frame in
            readerProgressFrame = frame
            updatePencilHoverPageIndex()
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.showsControls)
        .animation(theme.animation, value: viewModel.readingMode)
        .animation(theme.animation, value: viewModel.currentPageIndex)
        .animation(theme.animation, value: viewModel.isLoadingPages)
        #if os(macOS)
        .focusable()
        .onMoveCommand(perform: handleMoveCommand)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.readingMode {
        case .paged:
            pagedContent
        case .webtoon:
            webtoonContent
        }
    }

    private var pagedContent: some View {
        GeometryReader { proxy in
            ZStack {
                pagedPageCanvas(proxy: proxy)
                    .id("\(viewModel.currentPage?.id ?? "empty")-\(viewModel.fitMode.rawValue)")

                HStack(spacing: 0) {
                    pageTurnZone(isEnabled: viewModel.canGoBackward, action: goBackward)

                    Spacer(minLength: safePositiveDimension(YomuhonSpacing.grand, fallback: 64))

                    pageTurnZone(isEnabled: viewModel.canGoForward, action: goForward)
                }
            }
            .onAppear {
                readerViewportWidth = proxy.size.width
            }
            .onChange(of: proxy.size.width) { newWidth in
                readerViewportWidth = newWidth
            }
        }
    }

    private var usesDoublePageSpread: Bool {
        viewModel.readingMode == .paged
            && viewModel.isDoublePageEnabled
            && viewModel.fitMode != .fitWidth
            && readerViewportWidth >= 900
    }

    private var pageAdvanceStep: Int {
        usesDoublePageSpread ? 2 : 1
    }

    @ViewBuilder
    private func pagedPageCanvas(proxy: GeometryProxy) -> some View {
        if usesDoublePageSpread {
            HStack(spacing: 2) {
                PageCanvas(
                    page: viewModel.currentPage,
                    title: viewModel.chapterTitle,
                    fitMode: .fitPage,
                    sourceID: viewModel.manga.sourceID,
                    refererURL: viewModel.pageRefererURL
                )

                if let nextPage = viewModel.page(at: viewModel.currentPageIndex + 1) {
                    PageCanvas(
                        page: nextPage,
                        title: viewModel.chapterTitle,
                        fitMode: .fitPage,
                        sourceID: viewModel.manga.sourceID,
                        refererURL: viewModel.pageRefererURL
                    )
                }
            }
            .frame(
                width: safePositiveDimension(proxy.size.width, fallback: YomuhonLayout.readerPageMaxWidth * 1.6),
                height: safePositiveDimension(proxy.size.height, fallback: YomuhonLayout.readerPageMaxHeight)
            )
            .padding(.horizontal, YomuhonSpacing.small)
        } else {
            switch viewModel.fitMode {
            case .fitPage:
                PageCanvas(page: viewModel.currentPage, title: viewModel.chapterTitle, fitMode: .fitPage, sourceID: viewModel.manga.sourceID, refererURL: viewModel.pageRefererURL)
                    .frame(
                        width: safePositiveDimension(proxy.size.width, fallback: YomuhonLayout.readerPageMaxWidth),
                        height: safePositiveDimension(proxy.size.height, fallback: YomuhonLayout.readerPageMaxHeight)
                    )
                    .padding(.horizontal, YomuhonSpacing.small)

            case .fitWidth:
                ScrollView(.vertical, showsIndicators: false) {
                    PageCanvas(page: viewModel.currentPage, title: viewModel.chapterTitle, fitMode: .fitWidth, sourceID: viewModel.manga.sourceID, refererURL: viewModel.pageRefererURL)
                        .frame(
                            width: safePositiveDimension(proxy.size.width - 36, fallback: YomuhonLayout.readerPageMaxWidth),
                            height: safePositiveDimension(proxy.size.height * 1.55, fallback: YomuhonLayout.readerPageMaxHeight * 1.35)
                        )
                        .padding(.vertical, YomuhonSpacing.medium)
                }

            case .fitHeight:
                PageCanvas(page: viewModel.currentPage, title: viewModel.chapterTitle, fitMode: .fitHeight, sourceID: viewModel.manga.sourceID, refererURL: viewModel.pageRefererURL)
                    .frame(
                        width: safePositiveDimension(proxy.size.width * 0.56, fallback: YomuhonLayout.readerPageMaxWidth * 0.56),
                        height: safePositiveDimension(proxy.size.height, fallback: YomuhonLayout.readerPageMaxHeight)
                    )
            }
        }
    }

    private var webtoonContent: some View {
        ScrollView {
            LazyVStack(spacing: YomuhonSpacing.small) {
                ForEach(viewModel.pages) { page in
                    PageCanvas(page: page, title: viewModel.chapterTitle, fitMode: .fitWidth, sourceID: viewModel.manga.sourceID, refererURL: viewModel.pageRefererURL)
                        .frame(maxWidth: safePositiveDimension(YomuhonLayout.readerPageMaxWidth, fallback: 640))
                        .aspectRatio(YomuhonLayout.readerPageAspectRatio, contentMode: .fit)
                        .onAppear {
                            viewModel.setVisiblePage(page)
                        }
                }
            }
            .padding(.horizontal, webtoonHorizontalPadding)
            .padding(.vertical, YomuhonSpacing.small)
        }
        .id(viewModel.readingMode)
    }

    private func chapterTransitionToast(_ message: String) -> some View {
        Text(message)
            .font(YomuhonTypography.calloutSemibold)
            .foregroundColor(viewModel.isDarkHUDEnabled ? Color.white.opacity(0.94) : Color.black.opacity(0.86))
            .padding(.horizontal, YomuhonSpacing.large)
            .padding(.vertical, YomuhonSpacing.small)
            .background(viewModel.isDarkHUDEnabled ? Color.black.opacity(0.70) : Color.white.opacity(0.86))
            .overlay(
                Capsule()
                    .strokeBorder(viewModel.isDarkHUDEnabled ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
    }

    private var readerHUD: some View {
        VStack(spacing: YomuhonSpacing.small) {
            YomuhonReaderHUD(
                title: viewModel.title,
                subtitle: viewModel.chapterTitle,
                progress: viewModel.progress,
                progressLabel: viewModel.readingMode == .paged ? viewModel.pageLabel : nil,
                hoverProgressLabel: pencilProgressLabel,
                showsBottomControls: viewModel.readingMode == .paged,
                closeAction: closeReader,
                isDark: viewModel.isDarkHUDEnabled
            ) {
                HStack(spacing: YomuhonSpacing.small) {
                    ReaderRoundButton(systemName: "book", label: "reader.mode", action: switchMode, isDark: viewModel.isDarkHUDEnabled)

                    ReaderRoundButton(systemName: "ellipsis", label: "reader.quickMenu", action: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showsQuickMenu.toggle()
                        }
                        scheduleControlsAutoHide()
                    }, isDark: viewModel.isDarkHUDEnabled)
                }
            } bottomControls: {
                ReaderRoundButton(
                    systemName: "backward.end",
                    label: "reader.previousPage",
                    action: goBackward,
                    isDark: viewModel.isDarkHUDEnabled
                )
                .disabled(!viewModel.canGoBackward)
                .opacity(viewModel.canGoBackward ? 1 : 0.34)

                ReaderRoundButton(
                    systemName: "pause.fill",
                    label: "reader.toggleHUD",
                    action: toggleControls,
                    isDark: viewModel.isDarkHUDEnabled
                )

                ReaderRoundButton(
                    systemName: "forward.end",
                    label: "reader.nextPage",
                    action: goForward,
                    isDark: viewModel.isDarkHUDEnabled
                )
                .disabled(!viewModel.canGoForward)
                .opacity(viewModel.canGoForward ? 1 : 0.34)

                ReaderRoundButton(
                    systemName: viewModel.fitMode.systemImage,
                    label: "reader.fit",
                    action: cycleFitMode,
                    isDark: viewModel.isDarkHUDEnabled
                )
            }

            if showsQuickMenu {
                readerQuickMenu
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.bottom, 6)
    }

    private var readerQuickMenu: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            quickMenuChip(icon: "rectangle.portrait", title: "reader.mode.paged", selected: viewModel.readingMode == .paged) {
                viewModel.handleReadingModeChange(.paged)
                revealControls()
            }

            quickMenuChip(icon: "rectangle.stack", title: "reader.mode.webtoon", selected: viewModel.readingMode == .webtoon) {
                viewModel.handleReadingModeChange(.webtoon)
                revealControls()
            }

            quickMenuChip(icon: "rectangle.split.2x1", title: "reader.mode.doublePage", selected: viewModel.isDoublePageEnabled) {
                viewModel.toggleDoublePageMode()
                revealControls()
            }
            .disabled(viewModel.readingMode != .paged)
            .opacity(viewModel.readingMode == .paged ? 1 : 0.42)

            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.18))

            ForEach(ReaderFitMode.allCases) { mode in
                quickMenuChip(icon: mode.systemImage, title: mode.title, selected: viewModel.fitMode == mode) {
                    viewModel.setFitMode(mode)
                    revealControls()
                }
            }

            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.18))

            quickMenuChip(icon: viewModel.isDarkHUDEnabled ? "moon.fill" : "sun.max", title: "reader.hud.dark", selected: viewModel.isDarkHUDEnabled) {
                viewModel.toggleDarkHUD()
                revealControls()
            }
        }
        .padding(.horizontal, YomuhonSpacing.medium)
        .padding(.vertical, YomuhonSpacing.small)
        .background(viewModel.isDarkHUDEnabled ? Color.black.opacity(0.68) : Color.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(viewModel.isDarkHUDEnabled ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private func quickMenuChip(icon: String, title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(YomuhonTypography.calloutMedium)

                Text(title)
                    .font(YomuhonTypography.caption)
                    .lineLimit(1)
            }
            .foregroundColor(viewModel.isDarkHUDEnabled ? Color.white.opacity(selected ? 0.94 : 0.62) : Color.black.opacity(selected ? 0.86 : 0.58))
            .frame(width: 82, height: 58)
            .background(viewModel.isDarkHUDEnabled ? Color.white.opacity(selected ? 0.13 : 0.06) : Color.black.opacity(selected ? 0.08 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var readerBackground: some View {
        viewModel.isDarkHUDEnabled
            ? Color(red: 0.018, green: 0.018, blue: 0.020)
            : Color(red: 0.965, green: 0.965, blue: 0.955)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let errorMessage = viewModel.errorMessage {
            YomuhonErrorState(
                title: "reader.pages.error.title",
                message: LocalizedStringKey(errorMessage),
                retryTitle: "common.retry",
                retryAction: viewModel.retryLoadingPages
            )
        } else {
            YomuhonEmptyState(
                systemImage: "doc.text.image",
                title: "reader.empty.title",
                message: "reader.empty.message"
            )
        }
    }

    private var loadingState: some View {
        YomuhonLoadingState(
            title: "reader.pages.loading",
            message: "reader.pages.loading.message"
        )
    }

    private var webtoonHorizontalPadding: CGFloat {
        #if os(iOS)
        return YomuhonSpacing.large
        #else
        return YomuhonSpacing.extraLarge
        #endif
    }

    #if os(macOS)
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            goBackward()
        case .right:
            goForward()
        default:
            break
        }
    }
    #endif

    private func pageTurnZone(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readerContentAccessibilityIdentifier: String {
        guard !viewModel.pages.isEmpty else {
            return "reader.content.empty"
        }

        return viewModel.pages.allSatisfy { $0.localFileURL != nil }
            ? "reader.content.local"
            : "reader.content.remote"
    }

    private func closeReader() {
        // Persist the exact chapter/page before RootView removes the immersive
        // reader layer. Detail refreshes on the next main-loop turn.
        viewModel.flushProgress()

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func cycleFitMode() {
        let allModes = ReaderFitMode.allCases
        guard let currentIndex = allModes.firstIndex(of: viewModel.fitMode) else {
            viewModel.setFitMode(.fitPage)
            return
        }

        let nextIndex = allModes.index(after: currentIndex)
        viewModel.setFitMode(nextIndex == allModes.endIndex ? allModes[0] : allModes[nextIndex])
        revealControls()
    }

    private func switchMode() {
        let nextMode: ReadingMode = viewModel.readingMode == .paged ? .webtoon : .paged
        viewModel.handleReadingModeChange(nextMode)
        revealControls()
    }

    private func goBackward() {
        viewModel.goBackward(pageStep: pageAdvanceStep)
        revealControls()
    }

    private func goForward() {
        viewModel.goForward(pageStep: pageAdvanceStep)
        revealControls()
    }

    private func toggleControls() {
        if viewModel.showsControls {
            showsQuickMenu = false
        }

        withAnimation(YomuhonMotion.relaxed) {
            viewModel.toggleControls()
        }
    }

    private var pencilProgressLabel: String? {
        guard viewModel.readingMode == .paged,
              let pageIndex = pencilHoverPageIndex
        else {
            return nil
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("reader.pageNumberFormat", comment: ""),
            pageIndex + 1
        )
    }

    private func updatePencilHoverPageIndex() {
        guard viewModel.readingMode == .paged,
              viewModel.showsControls,
              let location = pencilHoverLocation,
              readerProgressFrame.width > 0,
              readerProgressFrame.contains(location)
        else {
            pencilHoverPageIndex = nil
            return
        }

        let rawFraction = Double((location.x - readerProgressFrame.minX) / readerProgressFrame.width)
        pencilHoverPageIndex = ReaderViewModel.pageIndex(
            forProgressFraction: rawFraction,
            pageCount: viewModel.pages.count
        )
    }

    #if os(iOS)
    private func handlePencilHoverChanged(isHovering: Bool, location: CGPoint?) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        pencilHoverLocation = isHovering ? location : nil
        updatePencilHoverPageIndex()

        if isHovering {
            revealControls()
        } else {
            scheduleControlsAutoHide()
        }
    }

    private func handlePencilTap(at location: CGPoint) {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              viewModel.readingMode == .paged,
              viewModel.showsControls,
              readerProgressFrame.width > 0,
              readerProgressFrame.contains(location)
        else {
            return
        }

        let rawFraction = Double((location.x - readerProgressFrame.minX) / readerProgressFrame.width)
        guard let pageIndex = ReaderViewModel.pageIndex(
            forProgressFraction: rawFraction,
            pageCount: viewModel.pages.count
        ) else {
            return
        }

        viewModel.jumpToPage(at: pageIndex)
        pencilHoverPageIndex = pageIndex
        revealControls()
    }

    private func handlePencilDoubleTap() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        toggleControls()
    }
    #endif

    private func revealControls() {
        if !viewModel.showsControls {
            withAnimation(YomuhonMotion.relaxed) {
                viewModel.toggleControls()
            }
        } else {
            scheduleControlsAutoHide()
        }
    }

    private func scheduleControlsAutoHide() {
        cancelControlsAutoHide()

        guard viewModel.showsControls, !viewModel.pages.isEmpty else {
            return
        }

        let activeViewModel = viewModel
        let workItem = DispatchWorkItem { [weak activeViewModel] in
            guard let activeViewModel,
                  activeViewModel.showsControls,
                  !showsQuickMenu
            else {
                return
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                activeViewModel.toggleControls()
            }
        }

        controlsAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    private func prefetchNearbyPages() {
        ReaderImageDataCache.shared.prefetch(
            pages: viewModel.pagesToPrefetch(radius: usesDoublePageSpread ? 3 : 2),
            sourceID: viewModel.manga.sourceID,
            refererURL: viewModel.pageRefererURL
        )
    }

    private func prefetchNextChapterPreviewImages() {
        guard !viewModel.prefetchedNextChapterPreviewPages.isEmpty else { return }
        ReaderImageDataCache.shared.prefetch(
            pages: viewModel.prefetchedNextChapterPreviewPages,
            sourceID: viewModel.manga.sourceID,
            refererURL: viewModel.prefetchedNextChapterRefererURL
        )
    }

    #if os(macOS)
    private func installKeyboardMonitorIfNeeded() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

            guard event.keyCode == 49,
                  modifiers.intersection(blockedModifiers).isEmpty
            else {
                return event
            }

            DispatchQueue.main.async {
                goForward()
            }
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }
    #endif

    private func cancelControlsAutoHide() {
        controlsAutoHideWorkItem?.cancel()
        controlsAutoHideWorkItem = nil
    }
}

#if os(iOS)
private struct ApplePencilReaderInteractionView: UIViewRepresentable {
    let onHoverChanged: (Bool, CGPoint?) -> Void
    let onPencilTap: (CGPoint) -> Void
    let onPencilDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHoverChanged: onHoverChanged,
            onPencilTap: onPencilTap,
            onPencilDoubleTap: onPencilDoubleTap
        )
    }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AttachmentView, context: Context) {
        context.coordinator.onHoverChanged = onHoverChanged
        context.coordinator.onPencilTap = onPencilTap
        context.coordinator.onPencilDoubleTap = onPencilDoubleTap
        context.coordinator.attachIfNeeded(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attachIfNeeded(to: window)
        }
    }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var onHoverChanged: (Bool, CGPoint?) -> Void
        var onPencilTap: (CGPoint) -> Void
        var onPencilDoubleTap: () -> Void

        private weak var attachedView: UIView?
        private var pencilInteraction: UIPencilInteraction?
        private var hoverRecognizer: UIHoverGestureRecognizer?
        private var tapRecognizer: UITapGestureRecognizer?

        init(
            onHoverChanged: @escaping (Bool, CGPoint?) -> Void,
            onPencilTap: @escaping (CGPoint) -> Void,
            onPencilDoubleTap: @escaping () -> Void
        ) {
            self.onHoverChanged = onHoverChanged
            self.onPencilTap = onPencilTap
            self.onPencilDoubleTap = onPencilDoubleTap
        }

        func attachIfNeeded(to view: UIView?) {
            guard let view else { return }
            guard attachedView !== view else { return }

            detach()
            attachedView = view

            let pencilInteraction = UIPencilInteraction()
            pencilInteraction.delegate = self
            view.addInteraction(pencilInteraction)
            self.pencilInteraction = pencilInteraction

            let hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            hoverRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            hoverRecognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(hoverRecognizer)
            self.hoverRecognizer = hoverRecognizer

            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tapRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            tapRecognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(tapRecognizer)
            self.tapRecognizer = tapRecognizer
        }

        func detach() {
            if let attachedView, let pencilInteraction {
                attachedView.removeInteraction(pencilInteraction)
            }
            if let attachedView, let hoverRecognizer {
                attachedView.removeGestureRecognizer(hoverRecognizer)
            }
            if let attachedView, let tapRecognizer {
                attachedView.removeGestureRecognizer(tapRecognizer)
            }

            attachedView = nil
            pencilInteraction = nil
            hoverRecognizer = nil
            tapRecognizer = nil
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            DispatchQueue.main.async { [onPencilDoubleTap] in
                onPencilDoubleTap()
            }
        }

        @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
            guard let attachedView else { return }

            switch recognizer.state {
            case .began, .changed:
                let location = recognizer.location(in: attachedView)
                onHoverChanged(true, location)
            case .ended, .cancelled, .failed:
                onHoverChanged(false, nil)
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let attachedView else { return }
            onPencilTap(recognizer.location(in: attachedView))
        }
    }
}
#endif

private struct PageCanvas: View {
    let page: Page?
    let title: String
    let fitMode: ReaderFitMode
    let sourceID: String
    let refererURL: URL?

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        ZStack {
            if let imageURL = page?.localFileURL {
                PlatformImageView(url: imageURL)
            } else if let imageURL = page?.imageURL {
                RemotePageImageView(url: imageURL, title: title, page: page, fitMode: fitMode, sourceID: sourceID, refererURL: refererURL)
            } else {
                PagePlaceholder(kind: .placeholder, title: title, page: page)
            }
        }
        .background(theme.background)
    }
}

private struct PagePlaceholder: View {
    enum Kind {
        case loading
        case unavailable
        case placeholder
    }

    let kind: Kind
    let title: String
    let page: Page?

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        ZStack {
            theme.secondaryBackground

            VStack(spacing: YomuhonSpacing.medium) {
                icon

                VStack(spacing: YomuhonSpacing.small) {
                    Text(primaryText)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let page {
                        Text(String.localizedStringWithFormat(NSLocalizedString("reader.pageNumberFormat", comment: ""), page.index + 1))
                            .font(YomuhonTypography.caption)
                            .foregroundColor(theme.textSecondary)
                    }
                }
            }
            .padding(YomuhonSpacing.large)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .loading:
            ProgressView()
                .scaleEffect(YomuhonLayout.loadingIndicatorScale)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle")
                .font(YomuhonTypography.largeTitle.weight(.light))
                .foregroundColor(theme.textSecondary.opacity(0.62))
        case .placeholder:
            Image(systemName: "photo")
                .font(YomuhonTypography.largeTitle.weight(.light))
                .foregroundColor(theme.textSecondary.opacity(0.62))
        }
    }

    private var primaryText: LocalizedStringKey {
        switch kind {
        case .loading:
            return "reader.page.loading"
        case .unavailable:
            return "reader.page.unavailable"
        case .placeholder:
            return LocalizedStringKey(title)
        }
    }
}


private struct RemotePageImageView: View {
    let url: URL
    let title: String
    let page: Page?
    let fitMode: ReaderFitMode
    let sourceID: String
    let refererURL: URL?

    @StateObject private var loader = RemotePageImageLoader()

    var body: some View {
        Group {
            if loader.isLoading {
                PagePlaceholder(kind: .loading, title: title, page: page)
            } else if let image = loader.image {
                fittedImage(image)
            } else {
                PagePlaceholder(kind: .unavailable, title: title, page: page)
            }
        }
        .onAppear {
            loader.load(url: url, sourceID: sourceID, refererURL: refererURL)
        }
        .onChange(of: url) { newURL in
            loader.load(url: newURL, sourceID: sourceID, refererURL: refererURL)
        }
    }

    @ViewBuilder
    private func fittedImage(_ image: Image) -> some View {
        switch fitMode {
        case .fitPage, .fitHeight:
            image
                .resizable()
                .scaledToFit()
        case .fitWidth:
            image
                .resizable()
                .scaledToFit()
        }
    }
}

private final class RemotePageImageLoader: ObservableObject {
    @Published var image: Image?
    @Published var isLoading = false

    private var task: URLSessionDataTask?
    private var currentURL: URL?

    func load(url: URL, sourceID: String, refererURL: URL?) {
        guard currentURL != url else { return }

        currentURL = url
        image = nil
        isLoading = true
        task?.cancel()

        if let cachedData = ReaderImageDataCache.shared.data(for: url),
           let cachedImage = Self.platformImage(from: cachedData) {
            image = cachedImage
            isLoading = false
            return
        }

        ReaderImageDataCache.shared.removeInvalidData(for: url)
        load(
            url: url,
            sourceID: sourceID,
            referers: ReaderImageDataCache.refererCandidates(
                for: url,
                sourceID: sourceID,
                refererURL: refererURL
            )
        )
    }

    private func load(url: URL, sourceID: String, referers: [String?]) {
        var remainingReferers = referers
        let referer = remainingReferers.isEmpty ? nil : remainingReferers.removeFirst()
        var request = ReaderImageDataCache.request(for: url, sourceID: sourceID, referer: referer)
        request.timeoutInterval = 18

        let startedAt = Date()
        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let acceptedData: Data?
            if let data,
               ReaderImageDataCache.isAcceptableImageResponse(response, data: data),
               Self.platformImage(from: data) != nil {
                acceptedData = data
                ReaderImageDataCache.shared.store(data, for: url)
            } else {
                acceptedData = nil
            }

            if acceptedData == nil, !remainingReferers.isEmpty {
                DispatchQueue.main.async {
                    guard self?.currentURL == url else { return }
                    self?.load(url: url, sourceID: sourceID, referers: remainingReferers)
                }
                return
            }

            let loadedImage = acceptedData.flatMap(Self.platformImage(from:))
            if loadedImage != nil {
                SourceMetricsStore.shared.recordSuccess(
                    sourceID: sourceID,
                    operation: .image,
                    latency: Date().timeIntervalSince(startedAt)
                )
            } else if !Self.isCancellation(error) {
                SourceMetricsStore.shared.recordFailure(
                    sourceID: sourceID,
                    operation: .image
                )
            }

            DispatchQueue.main.async {
                guard self?.currentURL == url else { return }
                self?.image = loadedImage
                self?.isLoading = false
            }
        }

        task?.resume()
    }

    private static func isCancellation(_ error: Error?) -> Bool {
        guard let error = error as? URLError else { return false }
        return error.code == .cancelled
    }

    fileprivate static func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #elseif canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }

    deinit {
        task?.cancel()
    }
}

enum ReaderCacheMaintenance {
    static func clearImageCache() {
        ReaderImageDataCache.shared.removeAll()
    }

    static func enforceImageCacheLimit() {
        ReaderImageDataCache.shared.enforceDiskLimit()
    }
}

/// Shared, discardable reader cache. Explicit downloads remain in Application
/// Support and are never trimmed by this cache.
private final class ReaderImageDataCache {
    static let shared = ReaderImageDataCache()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var inFlightURLs = Set<URL>()
    private var cacheGeneration = 0
    private let maintenanceQueue = DispatchQueue(label: "com.yomuhon.reader-image-cache", qos: .utility)
    private let directoryURL: URL?

    private var maximumDiskBytes: Int64 {
        let configuredMegabytes = UserDefaults.standard.integer(
            forKey: ReaderPreferenceKeys.imageCacheMaximumMegabytes
        )
        let megabytes = configuredMegabytes > 0
            ? configuredMegabytes
            : ReaderImageCacheSize.standard.rawValue
        return Int64(megabytes) * 1024 * 1024
    }

    private init() {
        memoryCache.totalCostLimit = 128 * 1024 * 1024

        directoryURL = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Yomuhon", isDirectory: true)
        .appendingPathComponent("ImageCache-v2", isDirectory: true)

        if let directoryURL {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        maintenanceQueue.async { [weak self] in
            self?.trimDiskCacheIfNeeded()
        }
    }

    func data(for url: URL) -> Data? {
        if let data = memoryCache.object(forKey: url as NSURL) {
            return data as Data
        }

        guard let fileURL = fileURL(for: url),
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty else { return }

        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        guard let fileURL = fileURL(for: url) else { return }
        try? data.write(to: fileURL, options: .atomic)

        maintenanceQueue.async { [weak self] in
            self?.trimDiskCacheIfNeeded()
        }
    }

    func removeInvalidData(for url: URL) {
        memoryCache.removeObject(forKey: url as NSURL)
        if let fileURL = fileURL(for: url) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func enforceDiskLimit() {
        maintenanceQueue.async { [weak self] in
            self?.trimDiskCacheIfNeeded()
        }
    }

    func removeAll() {
        memoryCache.removeAllObjects()
        lock.lock()
        cacheGeneration += 1
        inFlightURLs.removeAll()
        lock.unlock()

        guard let directoryURL else { return }
        maintenanceQueue.async { [fileManager] in
            try? fileManager.removeItem(at: directoryURL)
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func prefetch(pages: [Page], sourceID: String, refererURL: URL?) {
        for url in pages.compactMap(\.imageURL) {
            guard data(for: url) == nil, let generation = beginPrefetch(url) else { continue }

            Self.fetchData(
                from: url,
                sourceID: sourceID,
                referers: Self.refererCandidates(for: url, sourceID: sourceID, refererURL: refererURL)
            ) { [weak self] data in
                defer { self?.endPrefetch(url) }
                guard let self,
                      let data,
                      self.isCurrentCacheGeneration(generation)
                else {
                    return
                }
                self.store(data, for: url)
            }
        }
    }

    private func beginPrefetch(_ url: URL) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard inFlightURLs.insert(url).inserted else { return nil }
        return cacheGeneration
    }

    private func endPrefetch(_ url: URL) {
        lock.lock()
        inFlightURLs.remove(url)
        lock.unlock()
    }

    private func isCurrentCacheGeneration(_ generation: Int) -> Bool {
        lock.lock()
        let isCurrent = generation == cacheGeneration
        lock.unlock()
        return isCurrent
    }

    static func request(for url: URL, sourceID: String, referer: String?) -> URLRequest {
        var request = URLRequest(url: url)

        if let config = sourceConfig(for: sourceID) {
            for (key, value) in config.network?.headers ?? [:] {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 Yomuhon/1.0", forHTTPHeaderField: "User-Agent")
        }
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    static func refererCandidates(for imageURL: URL, sourceID: String, refererURL: URL?) -> [String?] {
        var candidates: [String?] = []

        if let refererURL {
            candidates.append(refererURL.absoluteString)
            candidates.append(originString(for: refererURL))
        }

        if let config = sourceConfig(for: sourceID) {
            let base = config.baseURL.absoluteString
            candidates.append(base.hasSuffix("/") ? base : base + "/")
        }

        candidates.append(originString(for: imageURL))
        candidates.append(nil)

        var seen = Set<String>()
        return candidates.filter { value in
            guard let value else { return true }
            return seen.insert(value).inserted
        }
    }

    static func isAcceptableImageResponse(_ response: URLResponse?, data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        if let mimeType = response?.mimeType?.lowercased(), mimeType.hasPrefix("image/") {
            return true
        }

        return hasKnownImageSignature(data)
    }

    private static func fetchData(
        from url: URL,
        sourceID: String,
        referers: [String?],
        completion: @escaping (Data?) -> Void
    ) {
        var remaining = referers
        let referer = remaining.isEmpty ? nil : remaining.removeFirst()
        var request = request(for: url, sourceID: sourceID, referer: referer)
        request.timeoutInterval = 18

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, isAcceptableImageResponse(response, data: data) {
                completion(data)
                return
            }

            guard !remaining.isEmpty else {
                completion(nil)
                return
            }

            fetchData(from: url, sourceID: sourceID, referers: remaining, completion: completion)
        }
        .resume()
    }

    private static func sourceConfig(for sourceID: String) -> DeclarativeSourceConfig? {
        DeclarativeRemoteConfigLoader.availableConfigs()
            .first(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame })
    }

    private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url?.absoluteString else { return nil }
        return origin.hasSuffix("/") ? origin : origin + "/"
    }

    private static func hasKnownImageSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return true }
        if bytes.count >= 8, bytes[0...7].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true }
        if bytes.count >= 6, String(bytes: bytes[0..<6], encoding: .ascii)?.hasPrefix("GIF8") == true { return true }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" { return true }
        if bytes.count >= 12,
           String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" { return true }
        return false
    }

    private func fileURL(for url: URL) -> URL? {
        directoryURL?.appendingPathComponent(url.absoluteString.stableCacheFileName)
    }

    private func trimDiskCacheIfNeeded() {
        guard let directoryURL,
              let resourceKeys = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return
        }

        let files: [(url: URL, size: Int64, date: Date)] = resourceKeys.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }

        var totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
        guard totalBytes > maximumDiskBytes else { return }

        for file in files.sorted(by: { $0.date < $1.date }) where totalBytes > maximumDiskBytes {
            try? fileManager.removeItem(at: file.url)
            totalBytes -= file.size
        }
    }
}


private struct PlatformImageView: View {
    let url: URL

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        #if os(macOS)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background(theme.secondaryBackground)
        } else {
            PagePlaceholder(kind: .unavailable, title: "", page: nil)
        }
        #elseif canImport(UIKit)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .background(theme.secondaryBackground)
        } else {
            PagePlaceholder(kind: .unavailable, title: "", page: nil)
        }
        #else
        PagePlaceholder(kind: .unavailable, title: "", page: nil)
        #endif
    }
}

private extension String {
    var stableCacheFileName: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

