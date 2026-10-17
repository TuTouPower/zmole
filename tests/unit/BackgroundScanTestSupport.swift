import Combine
import Foundation
@testable import Zmole

/// In-memory `BackgroundScanProviding` for page tests: publishes the stored
/// results, records refresh/cancel requests, and lets tests push new results
/// through the same pipeline the real service uses.
@MainActor
final class ScanProvidingStub: BackgroundScanProviding {
    @Published var results: [BackgroundScanItem: BackgroundScanResult]
    @Published var runningItems: Set<BackgroundScanItem> = []
    @Published var failedItems: Set<BackgroundScanItem> = []
    var inProgressRows: [UninstallAppListing] = []
    private(set) var requestedItems: [BackgroundScanItem] = []
    private(set) var cancelledItems: [BackgroundScanItem] = []

    func inProgressUninstallList() -> [UninstallAppListing] {
        inProgressRows
    }

    var statePublisher: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            $results.map { _ in () },
            $runningItems.map { _ in () },
            $failedItems.map { _ in () }
        )
        .eraseToAnyPublisher()
    }

    init(results: [BackgroundScanItem: BackgroundScanResult] = [:]) {
        self.results = results
    }

    static func maintenance(
        _ item: BackgroundScanItem,
        output: String,
        capturedAt: Date = Date()
    ) -> ScanProvidingStub {
        ScanProvidingStub(results: [
            item: BackgroundScanResult(capturedAt: capturedAt, payload: .maintenance(output))
        ])
    }

    func result(for item: BackgroundScanItem) -> BackgroundScanResult? {
        results[item]
    }

    func request(_ item: BackgroundScanItem) {
        requestedItems.append(item)
    }

    func waitForScan(_ item: BackgroundScanItem) async {}

    func cancelAndWait(_ item: BackgroundScanItem) async {
        cancelledItems.append(item)
    }

    func userDidRescan(_ item: BackgroundScanItem) {
        results.removeValue(forKey: item)
    }

    func userDidRescanAndWaitForTermination(_ item: BackgroundScanItem) async {
        userDidRescan(item)
    }
}

/// Execution-only process spy for optimize/purge pages: records argv, can block
/// the execution and can cancel it.
actor MaintenanceExecutionSpy: MoleProcessControlling {
    struct Invocation: Equatable, Sendable {
        let arguments: [String]
        let stdin: Data?
    }

    private(set) var invocations: [Invocation] = []
    private(set) var cancelCount = 0

    private var executionResult: MoleCommandResult
    private var blockExecution = false
    private var continuation: CheckedContinuation<MoleCommandResult, Error>?

    init(
        executionResult: MoleCommandResult = MoleCommandResult(stdout: "done", stderr: "", exitCode: 0)
    ) {
        self.executionResult = executionResult
    }

    func setExecutionResult(_ result: MoleCommandResult) {
        executionResult = result
    }

    func setExecutionBlocked(_ blocked: Bool) {
        blockExecution = blocked
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        invocations.append(Invocation(arguments: arguments, stdin: stdin))
        guard blockExecution else { return executionResult }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() async {
        cancelCount += 1
        continuation?.resume(throwing: MoleBridgeError.cancelled)
        continuation = nil
    }

    func waitForInvocationCount(_ count: Int) async throws {
        for _ in 0..<1_000 {
            if invocations.count >= count { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        throw SpyWaitError.timeout
    }
}

enum SpyWaitError: Error {
    case timeout
}
