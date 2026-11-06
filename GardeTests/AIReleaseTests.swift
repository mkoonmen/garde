import Testing
import Foundation
@testable import Garde

@Suite("Chef model safety")
struct AIReleaseTests {
    @Test("A GPU fault reported from several threads counts once this launch")
    func callbacksCountOnce() async {
        let faults = LaunchModelFaults()
        #expect(faults.message == nil)
        let claims = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<16 { group.addTask { faults.recordGPU("Metal error") } }
            var count = 0
            for await isFirst in group {
                if isFirst { count += 1 }
            }
            return count
        }
        #expect(claims == 1)
        faults.recordTimeout()
        #expect(faults.message == "Metal error")
    }

    @Test("Timeout returns even if the model ignores cancellation")
    func timeoutWins() async {
        let gate = ModelGate()
        let faults = LaunchModelFaults()
        // A broken implementation still lets the suite finish and report the failure.
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await gate.release()
        }
        defer { watchdog.cancel() }
        do {
            _ = try await AITimeout.run(seconds: 0.05, onTimeout: { faults.recordTimeout() }) {
                await gate.wait()
                return 1
            }
            Issue.record("Expected a timeout")
        } catch {
            #expect(error is AITimeoutError)
        }
        #expect(faults.message == "timed out")
        let watchdogRan = await gate.isReleased
        #expect(!watchdogRan)
        await gate.release()
        #expect(faults.recordGPU("Metal error"))
    }

    @Test("A successful response keeps the local model available")
    func returnsBeforeDeadline() async throws {
        let faults = LaunchModelFaults()
        let value = try await AITimeout.run(seconds: 2, onTimeout: { faults.recordTimeout() }) { 7 }
        #expect(value == 7)
        #expect(faults.message == nil)
    }

    @MainActor
    @Test("Leaving the foreground interrupts Qwen while Apple requests keep running")
    func onlyLocalWorkIsInterrupted() async throws {
        let requests = LocalModelRequests()
        let faults = LaunchModelFaults()
        let appleGate = ModelGate()
        let localGate = ModelGate()
        let (starts, started) = AsyncStream<ChefBrain>.makeStream()
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            started.finish()
            await localGate.release()
            await appleGate.release()
        }
        defer { watchdog.cancel() }

        let apple = Task {
            try await requests.run(brain: .apple) {
                started.yield(.apple)
                await appleGate.wait()
                try Task.checkCancellation()
                return "Apple finished"
            }
        }
        let local = Task {
            try await requests.run(brain: .local8B) {
                try await AITimeout.run(seconds: 3, onTimeout: { faults.recordTimeout() }) {
                    started.yield(.local8B)
                    await localGate.wait() // Represents Metal work already submitted.
                    return "late result"
                }
            }
        }
        var iterator = starts.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(Set([first, second].compactMap { $0 }) == [.apple, .local8B])

        requests.setActive(false)
        do {
            _ = try await local.value
            Issue.record("Interrupted Qwen response was delivered")
        } catch { #expect(error is LocalModelInterrupted) }
        #expect(faults.message == nil)
        do {
            _ = try await requests.run(brain: .local8B) { 1 }
            Issue.record("New Qwen response started while inactive")
        } catch { #expect(error is LocalModelInterrupted) }

        let appleScan = try await requests.run(brain: .apple) { "Apple scan" }
        #expect(appleScan == "Apple scan")
        await localGate.release()
        await appleGate.release()
        let appleReply = try await apple.value
        #expect(appleReply == "Apple finished")
        requests.setActive(true)
        let localRetry = try await requests.run(brain: .local8B) { "Qwen resumed" }
        #expect(localRetry == "Qwen resumed")
    }

    private actor ModelGate {
        private(set) var isReleased = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isReleased else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }
}
