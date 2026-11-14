import Foundation
import Testing
@testable import RookFeatures

final class FakeStepCounter: StepCounting, @unchecked Sendable {
    let accessValue = Locked(StepAccess.available)
    let total = Locked<Result<Int, Error>>(.success(0))
    let queries = Locked<[(Date, Date)]>([])
    let streamStarts = Locked<[Date]>([])
    /// Values each live stream yields before finishing.
    var updates: [Int] = []
    /// Called before each live value is delivered (lets tests move the clock).
    var beforeUpdate: (@Sendable (Int) -> Void)?
    /// Simulates tapping "Don't Allow" on the Motion & Fitness prompt the first query shows.
    var denyOnQuery = false

    var access: StepAccess { accessValue.get() }

    func steps(from start: Date, to end: Date) async throws -> Int {
        queries.mutate { $0.append((start, end)) }
        if denyOnQuery {
            accessValue.set(.denied)
            throw TestError()
        }
        return try total.get().get()
    }

    func stepUpdates(from start: Date) -> AsyncStream<Int> {
        streamStarts.mutate { $0.append(start) }
        let values = streamStarts.get().count == 1 ? updates : []
        let hook = beforeUpdate
        return AsyncStream { continuation in
            for value in values {
                hook?(value)
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}

@MainActor
@Suite("Steps")
struct StepsModelTests {
    let counter = FakeStepCounter()

    func makeModel(clock: Clock = Clock { dashNow }) -> StepsModel {
        StepsModel(counter: counter, clock: clock, calendar: nyCalendar)
    }

    @Test func readsTodaysStepsFromMidnight() async {
        counter.total.set(.success(4_321))
        let model = makeModel()
        #expect(model.state == .loading)
        await model.refresh()
        #expect(model.state == .count(4_321))
        let (start, end) = counter.queries.get()[0]
        #expect(start == nyCalendar.startOfDay(for: dashNow))
        #expect(end == dashNow)
    }

    @Test func unavailableAndDeniedSkipTheQuery() async {
        let model = makeModel()
        counter.accessValue.set(.unavailable)
        await model.refresh()
        #expect(model.state == .unavailable)
        counter.accessValue.set(.denied)
        await model.refresh()
        #expect(model.state == .denied)
        #expect(counter.queries.get().isEmpty)
    }

    @Test func deniedAtThePrompt() async {
        counter.denyOnQuery = true
        let model = makeModel()
        await model.refresh()
        #expect(model.state == .denied)
    }

    @Test func failureKeepsLastCount() async {
        counter.total.set(.success(100))
        let model = makeModel()
        await model.refresh()
        counter.total.set(.failure(TestError()))
        await model.refresh()
        #expect(model.state == .count(100))
    }

    @Test func firstReadFailingShowsUnavailable() async {
        counter.total.set(.failure(TestError()))
        let model = makeModel()
        await model.refresh()
        #expect(model.state == .unavailable)
    }

    @Test func trackFollowsLiveUpdates() async {
        counter.total.set(.success(10))
        counter.updates = [12, 15]
        let model = makeModel()
        await model.track()
        #expect(model.state == .count(15))
        #expect(counter.streamStarts.get() == [nyCalendar.startOfDay(for: dashNow)])
    }

    @Test func trackRestartsAtMidnight() async {
        let now = Locked(dashNow)
        let tomorrow = nyCalendar.date(byAdding: .day, value: 1, to: nyCalendar.startOfDay(for: dashNow))!
        counter.total.set(.success(9_000))
        counter.updates = [9_100, 9_200]
        counter.beforeUpdate = { value in if value == 9_200 { now.set(tomorrow.addingTimeInterval(60)) } }
        let model = makeModel(clock: Clock { now.get() })
        await model.track()
        // The post-midnight update is dropped and today's total is re-read from the new midnight.
        #expect(counter.streamStarts.get() == [nyCalendar.startOfDay(for: dashNow), tomorrow])
        #expect(counter.queries.get().last?.0 == tomorrow)
    }

    @Test func trackStopsWhenStepsUnavailable() async {
        counter.accessValue.set(.unavailable)
        let model = makeModel()
        await model.track()
        #expect(model.state == .unavailable)
        #expect(counter.streamStarts.get().isEmpty)
    }
}
