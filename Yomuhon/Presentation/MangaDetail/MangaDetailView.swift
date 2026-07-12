//
//  MangaDetailView.swift
//  Yomuhon
//

import SwiftUI

struct MangaDetailView: View {
    @ObservedObject private var viewModel: MangaDetailViewModel
    @Environment(\.yomuhonTheme) private var theme
    private let onOpenReader: ((ReaderViewModel) -> Void)?
    @State private var showsDownloadOptions = false
    @State private var presentedReaderViewModel: ReaderViewModel?
    @State private var presentsReader = false

    init(
        viewModel: MangaDetailViewModel,
        onOpenReader: ((ReaderViewModel) -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onOpenReader = onOpenReader
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    hero(width: proxy.size.width)
                    detailContent(width: proxy.size.width)
                }
                .padding(.horizontal, contentPadding(for: proxy.size.width))
                .padding(.top, proxy.size.width > 760 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large)
                .padding(.bottom, YomuhonSpacing.grand)
                .frame(maxWidth: 1180, alignment: .leading)
            }
        }
        .background(theme.background)
        .navigationTitle("Yomuhon")
        .readerPresentation(isPresented: $presentsReader, onDismiss: {
            presentedReaderViewModel = nil
            viewModel.refreshProgress()
        }) {
            if let readerViewModel = presentedReaderViewModel {
                ReaderView(
                    viewModel: readerViewModel,
                    onClose: { presentsReader = false }
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
#if DEBUG
            print("[Yomuhon][DetailUI] appear vm=\(ObjectIdentifier(viewModel)) chapters=\(viewModel.chapters.count) loading=\(viewModel.isLoadingDetails)")
#endif
            viewModel.refreshProgress()
            viewModel.loadDetailsIfNeeded()
        }
        .onReceive(viewModel.$manga) { manga in
#if DEBUG
            print("[Yomuhon][DetailUI] manga published vm=\(ObjectIdentifier(viewModel)) chapters=\(manga.chapters.count) title=\(manga.title)")
#endif
        }
        .onReceive(viewModel.$isLoadingDetails) { isLoading in
#if DEBUG
            print("[Yomuhon][DetailUI] loading published vm=\(ObjectIdentifier(viewModel)) value=\(isLoading) chapters=\(viewModel.chapters.count)")
#endif
        }
        .animation(theme.animation, value: viewModel.isLoadingDetails)
        .animation(theme.animation, value: viewModel.selectedSourceID)
    }

    @ViewBuilder
    private func hero(width: CGFloat) -> some View {
        if width < 780 {
            VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
                cover(width: 188, height: 270)
                heroCopy(width: width)
            }
        } else {
            HStack(alignment: .top, spacing: YomuhonSpacing.extraLarge) {
                cover(width: width > 1080 ? 220 : 198, height: width > 1080 ? 318 : 286)
                    .layoutPriority(0)

                heroCopy(width: width)
                    .frame(maxWidth: width > 1080 ? 700 : 620, alignment: .leading)
                    .layoutPriority(1)

                Spacer(minLength: 0)
            }
        }
    }

    private func cover(width: CGFloat, height: CGFloat) -> some View {
        CoverView(title: viewModel.title, imageURL: viewModel.coverURL, cornerRadius: 20)
            .frame(width: width, height: height)
            .clipped()
            .shadow(color: theme.shadow.opacity(0.72), radius: 16, x: 0, y: 9)
    }

    private func heroCopy(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.large) {
            VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
                Text(viewModel.title)
                    .font(detailTitleFont)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(viewModel.title.count > 64 ? 4 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                metadataLine
            }

            readingPanel

            actionRow
        }
    }

    private var metadataLine: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Label(viewModel.sourceLabel, systemImage: "globe")

            if viewModel.showsLanguageSelector {
                Label(viewModel.languagePreferenceTitle, systemImage: "text.bubble")
                    .lineLimit(1)
            }

            Text(String.localizedStringWithFormat(
                NSLocalizedString("search.chapterCount", comment: ""),
                viewModel.chapters.count
            ))
        }
        .font(YomuhonTypography.captionMedium)
        .foregroundColor(theme.textSecondary)
    }

    private var readingPanel: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(readingPanelTitle)
                        .font(YomuhonTypography.headline)
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(readingActionSubtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(String.localizedStringWithFormat(NSLocalizedString("common.percentFormat", comment: ""), Int(readingProgress * 100)))
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
            }

            YomuhonProgressBar(value: readingProgress)
        }
        .padding(YomuhonSpacing.medium)
        .frame(maxWidth: 560)
        .background(theme.card.opacity(theme.id == .ink ? 0.50 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.60), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            HStack(spacing: YomuhonSpacing.small) {
                if !viewModel.isSavedInLibrary {
                    Button {
                        viewModel.addToLibrary()
                    } label: {
                        Label("detail.addToLibrary", systemImage: "plus")
                    }
                    .buttonStyle(YomuhonSecondaryButtonStyle(theme: theme))
                }

                if let chapter = firstReadableChapter {
                    readerTrigger(for: chapter) {
                        Label(primaryReadingActionTitle, systemImage: "play.fill")
                    }
                    .buttonStyle(YomuhonPrimaryButtonStyle(theme: theme))

                    downloadMenu(for: chapter)
                } else if !viewModel.sourceIDSupportsRemotePages {
                    Text("detail.catalogOnly")
                        .font(YomuhonTypography.calloutMedium)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, YomuhonSpacing.medium)
                        .padding(.vertical, YomuhonSpacing.small)
                        .background(theme.secondaryBackground.opacity(0.72))
                        .clipShape(Capsule())
                }
            }

            if viewModel.isDownloadingManga {
                VStack(alignment: .leading, spacing: 5) {
                    YomuhonProgressBar(value: viewModel.mangaDownloadProgress)

                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("detail.downloadAll.progress", comment: ""),
                        Int(viewModel.mangaDownloadProgress * 100)
                    ))
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: 460)
            }

            if let downloadStatusMessage = viewModel.downloadStatusMessage {
                Label(downloadStatusMessage, systemImage: "arrow.down.circle")
                    .font(YomuhonTypography.caption)
                    .accessibilityIdentifier("detail.download.status")
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func downloadMenu(for chapter: Chapter) -> some View {
        Button {
            showsDownloadOptions.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isDownloading || viewModel.isDownloadingManga ? "arrow.down.circle.fill" : "arrow.down.circle")
                Text("detail.downloadMenu")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
            }
            .font(YomuhonTypography.calloutMedium)
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, YomuhonSpacing.medium)
            .padding(.vertical, YomuhonSpacing.small)
            .background(theme.card)
            .overlay(
                Capsule()
                    .strokeBorder(theme.separator, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(YomuhonPressableButtonStyle(theme: theme))
        .accessibilityIdentifier("detail.download.menu")
        .fixedSize()
        .popover(isPresented: $showsDownloadOptions, arrowEdge: .bottom) {
            downloadOptionsPopover(for: chapter)
        }
        .disabled(!viewModel.canDownload(chapter) && !viewModel.canDownloadManga)
    }

    private func downloadOptionsPopover(for chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            downloadOptionRow(
                title: downloadTitle(for: chapter),
                subtitle: "detail.downloadChapter.subtitle",
                systemImage: downloadIcon(for: chapter),
                disabled: viewModel.isDownloading || !viewModel.canDownload(chapter)
            ) {
                showsDownloadOptions = false
                viewModel.download(chapter)
            }
            .accessibilityIdentifier("detail.download.chapter")

            Divider()

            downloadOptionRow(
                title: "detail.downloadNextBatch",
                subtitle: "detail.downloadNextBatch.subtitle",
                systemImage: "arrow.down.to.line.compact",
                disabled: !viewModel.canDownloadNextBatch
            ) {
                showsDownloadOptions = false
                viewModel.downloadNextBatch()
            }

            Divider()

            downloadOptionRow(
                title: downloadAllTitle,
                subtitle: "detail.downloadRemaining.subtitle",
                systemImage: viewModel.isDownloadingManga ? "hourglass" : "square.and.arrow.down",
                disabled: !viewModel.canDownloadManga
            ) {
                showsDownloadOptions = false
                viewModel.downloadAllChapters()
            }
        }
        .padding(.vertical, 6)
        .frame(width: 310)
        .background(theme.card)
    }

    private func downloadOptionRow(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: YomuhonSpacing.medium) {
                Image(systemName: systemImage)
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(disabled ? theme.textSecondary.opacity(0.55) : theme.accent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(YomuhonTypography.calloutSemibold)
                        .foregroundColor(disabled ? theme.textSecondary : theme.textPrimary)

                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, YomuhonSpacing.medium)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func detailContent(width: CGFloat) -> some View {
        if width >= 1040 {
            HStack(alignment: .top, spacing: YomuhonSpacing.grand) {
                VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                    synopsis

                    if viewModel.showsLanguageSelector {
                        languageSelector
                    }

                    if viewModel.hasMultipleSources {
                        sourceSelector
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)

                chapters
                    .frame(maxWidth: 620, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: YomuhonSpacing.extraLarge) {
                synopsis

                if viewModel.showsLanguageSelector {
                    languageSelector
                }

                if viewModel.hasMultipleSources {
                    sourceSelector
                }

                chapters
            }
        }
    }

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            sectionHeading(title: "detail.whereToRead", subtitle: "detail.whereToRead.subtitle")

            if viewModel.canFallbackToAnotherSource {
                fallbackCallout
            }

            LazyVStack(spacing: YomuhonSpacing.small) {
                ForEach(viewModel.sourceAvailabilities) { availability in
                    SourceMiniCard(
                        availability: availability,
                        selected: availability.id == viewModel.selectedSourceID
                    ) {
                        viewModel.selectSource(availability.id)
                    }
                }
            }
        }
    }

    private var languageSelector: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(spacing: YomuhonSpacing.small) {
                Label("detail.language.title", systemImage: "text.bubble")
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                if viewModel.isCheckingLanguage {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("detail.language.perTitle")
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                }
            }

            Text("detail.language.selectorSubtitle")
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YomuhonSpacing.small) {
                    languageChip(
                        title: String(localized: "detail.language.auto"),
                        isSelected: viewModel.selectedReadingLanguageCode == nil
                    ) {
                        viewModel.selectReadingLanguage(nil)
                    }

                    ForEach(viewModel.languageOptions) { option in
                        languageChip(
                            title: option.title,
                            isSelected: viewModel.selectedReadingLanguageCode == option.code
                        ) {
                            viewModel.selectReadingLanguage(option.code)
                        }
                    }
                }
            }
            .disabled(viewModel.isCheckingLanguage)

            if let message = viewModel.languageAvailabilityMessage {
                Label(message, systemImage: viewModel.isCheckingLanguage ? "magnifyingglass" : "exclamationmark.triangle")
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(YomuhonSpacing.medium)
        .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var availableLanguageChips: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.small) {
            Text("detail.language.availableIn")
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: YomuhonSpacing.small) {
                    languageChip(
                        title: String(localized: "detail.language.auto"),
                        isSelected: viewModel.selectedExactLanguageCode == nil
                    ) {
                        viewModel.selectExactLanguage(nil)
                    }

                    ForEach(viewModel.availableLanguageCodes, id: \.self) { code in
                        languageChip(
                            title: code.yomuhonLanguageDisplayName,
                            isSelected: viewModel.selectedExactLanguageCode == code
                        ) {
                            viewModel.selectExactLanguage(code)
                        }
                    }
                }
            }
        }
    }

    private func languageChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(isSelected ? theme.background : theme.textPrimary)
                .padding(.horizontal, YomuhonSpacing.small)
                .padding(.vertical, 7)
                .background(isSelected ? theme.accent : theme.secondaryBackground.opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var fallbackCallout: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: "arrow.triangle.branch")
                .font(YomuhonTypography.calloutMedium)
                .foregroundColor(theme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("source.fallback.title")
                    .font(YomuhonTypography.calloutSemibold)
                    .foregroundColor(theme.textPrimary)

                Text(viewModel.selectedSourceAvailabilitySummary)
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                viewModel.switchToBestFallbackSource()
            } label: {
                Text("source.fallback.useBest")
                    .font(YomuhonTypography.captionMedium)
            }
            .buttonStyle(YomuhonSecondaryButtonStyle(theme: theme))
        }
        .padding(YomuhonSpacing.medium)
        .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.58), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var synopsis: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            sectionHeading(title: "detail.synopsis", subtitle: "detail.synopsis.subtitle")

            Text(viewModel.synopsis)
                .font(YomuhonTypography.body)
                .foregroundColor(readableBodyTextColor)
                .lineSpacing(4)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder
    private var chapters: some View {
        VStack(alignment: .leading, spacing: YomuhonSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("detail.chapters")
                    .font(YomuhonTypography.title)
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Text(String.localizedStringWithFormat(
                    NSLocalizedString("search.chapterCount", comment: ""),
                    viewModel.chapters.count
                ))
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
            }

            if viewModel.isCheckingLanguage {
                YomuhonLoadingState(
                    title: "detail.language.checkingTitle",
                    message: "detail.language.checking"
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(theme.card.opacity(theme.id == .ink ? 0.40 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if viewModel.shouldHideChaptersForLanguageSelection,
                      let languageMessage = viewModel.languageAvailabilityMessage {
                YomuhonEmptyState(
                    systemImage: "character.bubble",
                    title: "detail.language.noChaptersTitle",
                    message: LocalizedStringKey(languageMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(theme.card.opacity(theme.id == .ink ? 0.40 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if viewModel.isLoadingDetails {
                YomuhonLoadingState(title: "detail.loading", message: "detail.loading.message")
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(theme.card.opacity(theme.id == .ink ? 0.40 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let errorMessage = viewModel.errorMessage {
                YomuhonErrorState(
                    title: "detail.error.title",
                    message: LocalizedStringKey(errorMessage),
                    retryTitle: "common.retry",
                    retryAction: viewModel.refreshChapters
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if viewModel.chapters.isEmpty {
                YomuhonEmptyState(
                    systemImage: "book.closed",
                    title: "detail.chapters",
                    message: LocalizedStringKey(viewModel.languageAvailabilityMessage ?? String(localized: "detail.noChapters.message"))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(theme.card.opacity(theme.id == .ink ? 0.40 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                chapterList
            }
        }
    }

    private var chapterList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.chapters) { chapter in
                readerTrigger(for: chapter) {
                    ChapterLine(chapter: chapter, mangaTitle: viewModel.title, isCurrent: viewModel.currentChapterID == chapter.id)
                }
                .buttonStyle(.plain)

                if chapter.id != viewModel.chapters.last?.id {
                    Divider()
                        .padding(.leading, 68)
                }
            }
        }
        .background(theme.card.opacity(theme.id == .ink ? 0.46 : 1.0))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.60), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func readerTrigger<Content: View>(
        for chapter: Chapter,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let onOpenReader {
            Button {
                viewModel.prepareForReaderOpen()
                onOpenReader(viewModel.readerViewModel(for: chapter))
            } label: {
                content()
            }
            .accessibilityIdentifier("reader.open.\(chapter.id)")
        } else {
            Button {
                viewModel.prepareForReaderOpen()
                presentedReaderViewModel = viewModel.readerViewModel(for: chapter)
                presentsReader = true
            } label: {
                content()
            }
            .accessibilityIdentifier("reader.open.\(chapter.id)")
        }
    }

    private func sectionHeading(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(YomuhonTypography.headline)
                .foregroundColor(theme.textPrimary)

            Text(subtitle)
                .font(YomuhonTypography.caption)
                .foregroundColor(theme.textSecondary)
        }
    }

    private func contentPadding(for width: CGFloat) -> CGFloat {
        if width >= 1180 {
            return YomuhonSpacing.grand
        }

        return width >= 720 ? YomuhonSpacing.extraLarge : YomuhonSpacing.large
    }

    private var readableBodyTextColor: Color {
        theme.id == .ink ? theme.textSecondary : theme.textPrimary.opacity(0.78)
    }

    private var primaryReadingActionTitle: LocalizedStringKey {
        viewModel.currentChapterID == nil ? "detail.startReading" : "detail.continueReading"
    }

    private var downloadAllTitle: LocalizedStringKey {
        viewModel.isDownloadingManga ? "detail.downloadingManga" : "detail.downloadRemaining"
    }

    private func downloadTitle(for chapter: Chapter) -> LocalizedStringKey {
        if viewModel.isDownloading {
            return "detail.downloading"
        }

        return chapter.isDownloaded ? "downloads.status.downloaded" : "detail.downloadChapter"
    }

    private func downloadIcon(for chapter: Chapter) -> String {
        if viewModel.isDownloading {
            return "hourglass"
        }

        return chapter.isDownloaded ? "checkmark" : "arrow.down"
    }

    private var readingPanelTitle: String {
        if firstReadableChapter != nil {
            return viewModel.currentChapterID == nil
                ? String(localized: "detail.startReading")
                : String(localized: "detail.continueReading")
        }

        return viewModel.sourceIDSupportsRemotePages
            ? NSLocalizedString("detail.noChapters", comment: "")
            : NSLocalizedString("detail.catalogOnly", comment: "")
    }

    private var detailTitleFont: Font {
        viewModel.title.count > 64 ? .title.weight(.semibold) : YomuhonTypography.largeTitle
    }

    private var firstReadableChapter: Chapter? {
        let readableChapters = viewModel.chapters.filter { !$0.pages.isEmpty || viewModel.sourceIDSupportsRemotePages }

        if let currentID = viewModel.currentChapterID,
           let chapter = readableChapters.first(where: { $0.id == currentID }) {
            return chapter
        }

        return readableChapters.first
    }

    private var readingActionSubtitle: String {
        if !viewModel.sourceIDSupportsRemotePages {
            return String(localized: "detail.catalogOnly.message")
        }

        if viewModel.isLoadingDetails {
            return String(localized: "detail.loading.message")
        }

        if viewModel.chapters.isEmpty {
            if let languageMessage = viewModel.languageAvailabilityMessage {
                return languageMessage
            }

            return String(localized: "detail.noChapters.message")
        }

        if let currentID = viewModel.currentChapterID,
           let chapter = viewModel.chapters.first(where: { $0.id == currentID }) {
            return String.localizedStringWithFormat(
                NSLocalizedString("detail.continueReading.summary", comment: ""),
                chapter.primaryDisplayTitle(mangaTitle: viewModel.title),
                (viewModel.progress?.currentPage ?? 0) + 1
            )
        }

        guard let chapter = firstReadableChapter else {
            return String(localized: "detail.startReading.subtitle")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("detail.startReading.summary", comment: ""),
            chapter.primaryDisplayTitle(mangaTitle: viewModel.title),
            viewModel.chapters.count
        )
    }

    private var readingProgress: Double {
        guard let currentID = viewModel.currentChapterID,
              let chapterIndex = viewModel.chapters.firstIndex(where: { $0.id == currentID }),
              !viewModel.chapters.isEmpty else {
            return 0
        }

        return Double(chapterIndex + 1) / Double(viewModel.chapters.count)
    }
}

private struct SourceMiniCard: View {
    let availability: MangaSourceAvailability
    let selected: Bool
    let action: () -> Void

    @Environment(\.yomuhonTheme) private var theme

    private var option: MangaSourceOption { availability.option }

    var body: some View {
        Button(action: action) {
            HStack(spacing: YomuhonSpacing.medium) {
                Capsule()
                    .fill(selected ? theme.accent : theme.separator)
                    .frame(width: 4, height: 54)
                    .opacity(selected ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: YomuhonSpacing.small) {
                        Text(option.title)
                            .font(YomuhonTypography.calloutSemibold)
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        SourceStateBadge(state: availability.state)

                        if availability.hasMostChapters {
                            SourceBadge(title: "detail.source.mostChapters")
                        }

                        if availability.isRecommended && !selected {
                            SourceBadge(title: "source.recommended")
                        }
                    }

                    HStack(spacing: YomuhonSpacing.small) {
                        Label(option.language, systemImage: "text.bubble")
                            .labelStyle(.titleAndIcon)

                        Text(String.localizedStringWithFormat(
                            NSLocalizedString("search.chapterCount", comment: ""),
                            option.chapterCount
                        ))

                        Text(option.isReadable ? "detail.source.readable" : "detail.source.catalogOnly")
                    }
                    .font(YomuhonTypography.caption)
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(selected ? theme.accent : theme.textSecondary.opacity(0.62))
            }
            .padding(YomuhonSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.secondaryBackground.opacity(0.76) : theme.card.opacity(theme.id == .ink ? 0.35 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? theme.accent.opacity(0.45) : theme.separator.opacity(0.62), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SourceStateBadge: View {
    let state: SourceAvailabilityState

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Label(LocalizedStringKey(state.titleKey), systemImage: state.systemImage)
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.secondaryBackground.opacity(0.72))
            .clipShape(Capsule())
    }
}

private struct SourceBadge: View {
    let title: LocalizedStringKey

    @Environment(\.yomuhonTheme) private var theme

    var body: some View {
        Text(title)
            .font(YomuhonTypography.captionMedium)
            .foregroundColor(theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.secondaryBackground.opacity(0.72))
            .clipShape(Capsule())
    }
}

private struct ChapterLine: View {
    let chapter: Chapter
    let mangaTitle: String
    let isCurrent: Bool

    @Environment(\.yomuhonTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: YomuhonSpacing.medium) {
            Image(systemName: isCurrent ? "book.fill" : "book.closed")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(isCurrent ? theme.accent : theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.primaryDisplayTitle(mangaTitle: mangaTitle))
                    .font(YomuhonTypography.calloutMedium)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                if let subtitle = chapter.secondaryDisplayTitle(mangaTitle: mangaTitle) {
                    Text(subtitle)
                        .font(YomuhonTypography.caption)
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if chapter.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(YomuhonTypography.captionMedium)
                    .foregroundColor(theme.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(YomuhonTypography.captionMedium)
                .foregroundColor(theme.textSecondary.opacity(0.55))
        }
        .padding(YomuhonSpacing.medium)
        .contentShape(Rectangle())
        .background(isHovering ? theme.secondaryBackground.opacity(0.34) : Color.clear)
        .onHover { isHovering = $0 }
        .animation(theme.animation, value: isHovering)
    }
}


private extension Chapter {
    func primaryDisplayTitle(mangaTitle: String) -> String {
        if number > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("chapter.displayTitle", comment: ""),
                formattedNumber
            )
        }

        return realChapterTitle(mangaTitle: mangaTitle) ?? displayTitle
    }

    func secondaryDisplayTitle(mangaTitle: String) -> String? {
        guard let title = realChapterTitle(mangaTitle: mangaTitle),
              title != primaryDisplayTitle(mangaTitle: mangaTitle)
        else {
            return nil
        }

        return title
    }

    private func realChapterTitle(mangaTitle: String) -> String? {
        let cleanTitle = title?
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("yomuhon-source-url:") }
            .joined(separator: "\n")
            .decodedHTMLEntities
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let cleanTitle,
              !cleanTitle.isEmpty,
              !cleanTitle.isGenericChapterTitle,
              cleanTitle.count <= 68,
              !Self.looksLikeMangaTitle(cleanTitle, mangaTitle: mangaTitle),
              !cleanTitle.looksLikeGenericSourceChapterName
        else {
            return nil
        }

        return cleanTitle
    }

    private static func looksLikeMangaTitle(_ title: String, mangaTitle: String) -> Bool {
        let foldedTitle = title.normalizedForMangaTitleComparison
        let foldedManga = mangaTitle.normalizedForMangaTitleComparison

        guard !foldedTitle.isEmpty, !foldedManga.isEmpty else {
            return false
        }

        if foldedTitle == foldedManga {
            return true
        }

        if foldedTitle.hasPrefix(foldedManga) {
            let remainder = foldedTitle
                .dropFirst(foldedManga.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return remainder.isEmpty
                || remainder.range(of: #"^(chapter|ch)\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
                || remainder.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
        }

        return false
    }
}

fileprivate extension String {
    var isGenericChapterTitle: Bool {
        let folded = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            #"^chapter\s*[0-9]+(?:\.[0-9]+)?$"#,
            #"^ch\.?\s*[0-9]+(?:\.[0-9]+)?$"#,
            #"^capitulo\s*[0-9]+(?:\.[0-9]+)?$"#,
            #"^[0-9]+(?:\.[0-9]+)?$"#
        ]

        return patterns.contains { pattern in
            folded.range(of: pattern, options: .regularExpression) != nil
        }
    }

    var looksLikeGenericSourceChapterName: Bool {
        let folded = normalizedForMangaTitleComparison

        return folded.contains("read online")
            || folded.contains("spoils me rotten")
            || folded.range(of: #"chapter\s*[0-9]+$"#, options: .regularExpression) != nil
            || folded.range(of: #"^.+\s+chapter\s*[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    var decodedHTMLEntities: String {
        replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    var normalizedForMangaTitleComparison: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    @ViewBuilder
    func readerPresentation<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
#if os(iOS)
        fullScreenCover(
            isPresented: isPresented,
            onDismiss: onDismiss,
            content: content
        )
#else
        sheet(
            isPresented: isPresented,
            onDismiss: onDismiss,
            content: content
        )
#endif
    }
}
