import XCTest
@testable import Zmole

final class UninstallListStreamParserTests: XCTestCase {
    func testParserReadsIdentityAndFullRows() throws {
        let identity = try XCTUnwrap(UninstallListStreamParser.listing(
            from: "{\"path\":\"/Applications/Alpha.app\",\"name\":\"Alpha\"}"
        ))
        XCTAssertEqual(identity.path, "/Applications/Alpha.app")
        XCTAssertEqual(identity.name, "Alpha")
        XCTAssertNil(identity.bundleID)
        XCTAssertNil(identity.sizeText)
        XCTAssertFalse(identity.isResolved)

        let full = try XCTUnwrap(UninstallListStreamParser.listing(
            from: """
            {"path":"/Applications/Alpha.app","name":"Alpha","bundle_id":"com.example.alpha","uninstall_name":"Alpha Token","source":"Homebrew","size":"2.5 MB","version":"1.2.3","last_used_epoch":1700000000}
            """
        ))
        XCTAssertEqual(full.bundleID, "com.example.alpha")
        XCTAssertEqual(full.uninstallName, "Alpha Token")
        XCTAssertEqual(full.source, "Homebrew")
        XCTAssertEqual(full.sizeBytes, 2_500_000)
        XCTAssertEqual(full.version, "1.2.3")
        XCTAssertEqual(full.lastUsed, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(full.isResolved)
        XCTAssertEqual(full.uninstallApp?.uninstallName, "Alpha Token")
    }

    func testParserSkipsMarkersAndMalformedLines() {
        XCTAssertNil(UninstallListStreamParser.listing(from: "{\"event\":\"done\"}"))
        XCTAssertNil(UninstallListStreamParser.listing(from: "not json"))
        XCTAssertNil(UninstallListStreamParser.listing(from: "{\"name\":\"NoPath\"}"))
    }

    func testParserTreatsNAAndZeroSizesAsUnknown() throws {
        let na = try XCTUnwrap(UninstallListStreamParser.listing(
            from: "{\"path\":\"/A.app\",\"name\":\"A\",\"size\":\"N/A\"}"
        ))
        XCTAssertNil(na.sizeText, "unknown sizes never become zero")
        XCTAssertNil(na.sizeBytes)

        let zero = try XCTUnwrap(UninstallListStreamParser.listing(
            from: "{\"path\":\"/A.app\",\"name\":\"A\",\"size\":\"0\"}"
        ))
        XCTAssertNil(zero.sizeText)
    }
}

@MainActor
final class UninstallStreamingAssemblyTests: XCTestCase {
    func testStreamingInitializerTurnsCommandLinesIntoRows() async throws {
        let streaming = ScriptedMoleStreaming(lines: [
            "{\"path\":\"/Applications/Alpha.app\",\"name\":\"Alpha\"}",
            "not json",
            "{\"path\":\"/Applications/Alpha.app\",\"name\":\"Alpha\",\"bundle_id\":\"com.example.alpha\",\"uninstall_name\":\"Alpha\",\"source\":\"App\",\"size\":\"1.5 GB\",\"version\":\"2.0\",\"last_used_epoch\":1700000000}",
            "{\"event\":\"done\"}"
        ])
        let stream = UninstallListStream(streaming: streaming)

        var rows: [UninstallAppListing] = []
        for try await row in await stream.rows() {
            rows.append(row)
        }

        XCTAssertEqual(streaming.invocations, [["uninstall", "--list-stream"]])
        XCTAssertEqual(rows.count, 2, "markers and malformed lines are skipped")
        XCTAssertEqual(rows[0].name, "Alpha")
        XCTAssertNil(rows[0].sizeText, "the identity row carries no size yet")
        XCTAssertEqual(rows[1].sizeBytes, 1_500_000_000)
        XCTAssertEqual(rows[1].version, "2.0")
        XCTAssertEqual(rows[1].lastUsed, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(rows[1].isResolved)
    }
}

final class ScriptedMoleStreaming: MoleStreaming, @unchecked Sendable {
    private let lines: [String]
    private let lock = NSLock()
    private var recordedInvocations: [[String]] = []

    init(lines: [String]) {
        self.lines = lines
    }

    var invocations: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInvocations
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        lock.lock()
        recordedInvocations.append(arguments)
        lock.unlock()
        let lines = lines
        return AsyncThrowingStream { continuation in
            for line in lines {
                continuation.yield(.stdoutLine(Data(line.utf8)))
            }
            continuation.finish()
        }
    }

    func cancel() async {}
}

@MainActor
final class UninstallStreamProgressTests: XCTestCase {
    func testListingsAppearBeforeSizesFinish() async throws {
        let gate = AsyncGate()
        let stream = UninstallListStream(
            open: {
                AsyncThrowingStream { continuation in
                    let task = Task {
                        continuation.yield(UninstallAppListing(
                            path: "/Applications/Alpha.app",
                            name: "Alpha",
                            bundleID: nil,
                            uninstallName: nil,
                            source: nil,
                            sizeText: nil,
                            version: nil,
                            lastUsed: nil
                        ))
                        await gate.wait()
                        continuation.yield(UninstallAppListing(
                            path: "/Applications/Alpha.app",
                            name: "Alpha",
                            bundleID: "com.example.alpha",
                            uninstallName: "Alpha",
                            source: "App",
                            sizeText: "2 MB",
                            version: "1.0",
                            lastUsed: nil
                        ))
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            cancel: { await gate.open() }
        )
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            listStream: stream,
            coordinator: OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: true),
            iconProvider: NoopIconProvider()
        )

        let load = Task { @MainActor in await viewModel.loadList() }
        try await waitUntil { viewModel.listings.count == 1 }
        XCTAssertTrue(viewModel.isListing)
        XCTAssertEqual(viewModel.listings.first?.name, "Alpha")
        XCTAssertNil(viewModel.listings.first?.sizeText, "a row without size is computing, never zero")
        XCTAssertTrue(viewModel.apps.isEmpty, "unresolved identities cannot be previewed yet")

        await gate.open()
        await load.value
        XCTAssertEqual(viewModel.listings.first?.sizeText, "2 MB")
        XCTAssertEqual(viewModel.listings.first?.version, "1.0")
        XCTAssertFalse(viewModel.isListing)
    }

    func testIconsLoadAfterTheListIsAlreadyVisible() async throws {
        let iconGate = AsyncGate()
        let iconStore = RecordingIconProvider.Store()
        let iconProvider = GatedIconProvider(gate: iconGate, store: iconStore)
        let rows = UninstallFixture.rows(from: """
        [{"name":"Alpha","bundle_id":"com.example.alpha","uninstall_name":"Alpha","path":"/Applications/Alpha.app","size":"1 MB"}]
        """)
        let viewModel = UninstallViewModel(
            process: StubProcess(),
            listStream: UninstallFixture.stream(rows: rows),
            coordinator: OperationCoordinator(),
            targetChecker: FixedTargetChecker(matches: true),
            iconProvider: iconProvider
        )

        await viewModel.loadList()

        XCTAssertEqual(viewModel.listings.count, 1, "the list is interactive without icons")
        XCTAssertNil(viewModel.icon(forPath: "/Applications/Alpha.app"))

        await iconGate.open()
        try await waitUntil { viewModel.icon(forPath: "/Applications/Alpha.app") != nil }
        XCTAssertEqual(iconStore.recorded, ["/Applications/Alpha.app"])
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}

actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters = []
        for continuation in continuations {
            continuation.resume()
        }
    }
}

struct GatedIconProvider: UninstallIconProviding {
    let gate: AsyncGate
    let store: RecordingIconProvider.Store

    func icon(forAppAt path: String) async -> NSImage? {
        store.record(path)
        await gate.wait()
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}
