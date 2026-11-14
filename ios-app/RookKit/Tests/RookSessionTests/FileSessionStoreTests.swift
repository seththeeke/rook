import Foundation
import Testing
import RookModels
@testable import RookSession

@Suite("Session persistence")
struct FileSessionStoreTests {
    private func tempStore() -> (FileSessionStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rook-tests-\(UUID().uuidString)")
            .appendingPathExtension("json")
        return (FileSessionStore(fileURL: url), url)
    }

    @Test func roundTripsMidWorkoutState() throws {
        let (store, url) = tempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        var s = makeSession()
        s.setWeight(135, unit: .lbs)
        s.advance()
        s.startDuration(at: at(30))
        s.pause(at: at(40))
        try store.save(s)
        let loaded = try #require(store.load())
        #expect(loaded == s)
        #expect(loaded.elapsedSeconds(at: at(100)) == s.elapsedSeconds(at: at(100)))
        #expect(loaded.durationElapsedSeconds(at: at(100)) == 10)
    }

    @Test func emptyStoreLoadsNil() {
        let (store, _) = tempStore()
        #expect(store.load() == nil)
        #expect(throws: Never.self) { try store.clear() }
    }

    @Test func clearRemovesSession() throws {
        let (store, url) = tempStore()
        try store.save(makeSession())
        try store.clear()
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptFileIsDiscarded() throws {
        let (store, url) = tempStore()
        try Data("not json".utf8).write(to: url)
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unknownVersionIsDiscarded() throws {
        let (store, url) = tempStore()
        try store.save(makeSession())
        let raw = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: #""version":1"#, with: #""version":99"#)
        try raw.write(to: url, atomically: true, encoding: .utf8)
        #expect(store.load() == nil)
    }
}
