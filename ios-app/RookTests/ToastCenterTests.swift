import Foundation
import Testing
@testable import Rook

/// A sleeper the test releases manually, so auto-dismiss timing is deterministic.
actor ManualSleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { waiters.count }

    func sleep() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@MainActor
@Suite("Toast center")
struct ToastCenterTests {
    private func waitUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<200 where !(await condition()) {
            await Task.yield()
        }
    }

    @Test func showsThenAutoDismisses() async {
        let sleeper = ManualSleeper()
        let center = ToastCenter(sleep: { _ in await sleeper.sleep() })
        center.show("Saved", kind: .success)
        #expect(center.current?.message == "Saved")
        #expect(center.current?.kind == .success)

        await waitUntil { await sleeper.pendingCount == 1 }
        await sleeper.releaseAll()
        await waitUntil { center.current == nil }
        #expect(center.current == nil)
    }

    @Test func newToastReplacesOldAndSurvivesOldTimer() async {
        let sleeper = ManualSleeper()
        let center = ToastCenter(sleep: { _ in await sleeper.sleep() })
        center.show("First")
        await waitUntil { await sleeper.pendingCount == 1 }
        center.show("Second", kind: .error)
        await waitUntil { await sleeper.pendingCount == 2 }
        await sleeper.releaseAll()
        // Give the cancelled first timer and the second timer a chance to run.
        await waitUntil { center.current == nil }
        #expect(center.current == nil) // second timer dismissed the second toast
    }

    @Test func staleDismissDoesNotHideNewerToast() {
        let center = ToastCenter(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        center.show("First")
        let first = center.current
        center.show("Second")
        center.dismiss(first)
        #expect(center.current?.message == "Second")
        center.dismiss()
        #expect(center.current == nil)
    }
}
