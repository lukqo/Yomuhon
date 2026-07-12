//
//  LibraryRepository.swift
//  Yomuhon
//

protocol LibraryRepository {
    func fetchLibrary() -> [Manga]
    func fetchReadingProgress() -> [ReadingProgress]
    func saveManga(_ manga: Manga)
    func saveReadingProgress(_ progress: ReadingProgress)
    func deleteManga(id: String)
    func deleteReadingProgress(mangaID: String)
}
