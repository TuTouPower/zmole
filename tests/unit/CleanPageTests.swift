import XCTest
@testable import Zmole

@MainActor
final class CleanPageTests: XCTestCase {
    func testStageCatalogCoversBundledCleanSections() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/mole/bin/clean.sh")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        var names: [String] = []
        for line in source.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: "start_section \"") else { continue }
            let rest = line[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { continue }
            names.append(String(rest[..<end]))
        }

        XCTAssertFalse(names.isEmpty, "no start_section calls found in bundled clean.sh")
        for name in names {
            XCTAssertNotNil(
                CleanStageCatalog.key(for: name),
                "missing localization key for bundled clean section: \(name)"
            )
        }
    }

    func testStageParsingStripsANSIAndLocalizesKnownSection() {
        let line = "\u{001B}[1m\u{001B}[35m➤ Browsers\u{001B}[0m"
        let stage = CleanStageCatalog.stage(fromLine: line)
        XCTAssertEqual(stage?.raw, "Browsers")
        XCTAssertEqual(stage?.localizedKey, "clean.stage.browsers")

        XCTAssertNil(CleanStageCatalog.stage(fromLine: "  /Users/example/Library/Caches"))

        let unknown = CleanStageCatalog.stage(fromLine: "➤ Something new")
        XCTAssertEqual(unknown?.raw, "Something new")
        XCTAssertNil(unknown?.localizedKey)
    }

    func testLastStagePicksFinalSection() {
        let output = "➤ App caches\n  /a\n➤ Browsers\n  /b\n"
        XCTAssertEqual(CleanStageCatalog.lastStage(in: output)?.raw, "Browsers")
    }

    func testReclaimBytesParseHumanSizes() {
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("2.4 GB"), 2_400_000_000)
        XCTAssertEqual(CleanPreviewParser.parseHumanSize("512 MB, 18 items"), 512_000_000)
        XCTAssertNil(CleanPreviewParser.parseHumanSize("size unknown"))
    }

    func testPreviewUsesDryRunAndExecutesOnlyAfterConfirmation() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-argv")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let process = CleanPageProcess(previewFileURL: listURL, contents: Self.fixture)
        let viewModel = CleanViewModel(
            process: process,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )

        await viewModel.previewClean()
        let afterPreview = await process.arguments
        XCTAssertEqual(afterPreview, [["clean", "--dry-run"]])
        XCTAssertTrue(viewModel.canConfirm)

        viewModel.requestConfirmation()
        await viewModel.confirmExecution()
        let afterExecution = await process.arguments
        XCTAssertEqual(afterExecution, [["clean", "--dry-run"], ["clean"]])
    }

    func testReclaimBadgeOnlyAfterSuccessfulPreview() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-badge")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        // 2.4 GB + 512 MB from the fixture, asserted directly instead of via the
        // parser under test.
        let expected: Int64 = 2_400_000_000 + 512_000_000

        let success = CleanPageProcess(previewFileURL: listURL, contents: Self.fixture)
        let successViewModel = CleanViewModel(
            process: success,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )
        XCTAssertNil(successViewModel.lastReclaimBytes)
        await successViewModel.previewClean()
        XCTAssertEqual(successViewModel.lastReclaimBytes, expected)

        let failure = CleanPageProcess(previewFileURL: listURL, contents: "", exitCode: 9)
        let failureViewModel = CleanViewModel(
            process: failure,
            previewStore: CleanPreviewStore(fileURL: listURL)
        )
        await failureViewModel.previewClean()
        XCTAssertNil(failureViewModel.lastReclaimBytes)
        XCTAssertNil(failureViewModel.preview)
    }

    func testStreamingPreviewShowsLiveStageAndAcceptsPreview() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-stream")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let streaming = CleanPageStreaming(
            previewFileURL: listURL,
            contents: Self.fixture,
            lines: ["scanning", "➤ Browsers", "  /Users/example/Library/Caches/a"]
        )
        let viewModel = CleanViewModel(
            process: CleanPageProcess(previewFileURL: listURL, contents: Self.fixture),
            previewStore: CleanPreviewStore(fileURL: listURL),
            coordinator: OperationCoordinator(),
            streaming: streaming
        )

        await viewModel.previewClean()

        XCTAssertEqual(streaming.recordedArguments, [["clean", "--dry-run"]])
        XCTAssertEqual(viewModel.currentStage?.raw, "Browsers")
        XCTAssertEqual(viewModel.currentStage?.localizedKey, "clean.stage.browsers")
        XCTAssertNotNil(viewModel.preview)
        XCTAssertTrue(viewModel.canConfirm)
        XCTAssertEqual(viewModel.lastReclaimBytes, 2_400_000_000 + 512_000_000)
    }

    func testCancelPreviewCancelsTheStreamingProcess() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-cancel-stream")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let streaming = CleanPageStreaming(
            previewFileURL: listURL,
            contents: Self.fixture,
            lines: [],
            block: true
        )
        let viewModel = CleanViewModel(
            process: CleanPageProcess(previewFileURL: listURL, contents: Self.fixture),
            previewStore: CleanPreviewStore(fileURL: listURL),
            coordinator: OperationCoordinator(),
            streaming: streaming
        )

        let preview = Task { @MainActor in await viewModel.previewClean() }
        for _ in 0..<1_000 where !viewModel.isPreviewing {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(viewModel.isPreviewing)

        await viewModel.cancelPreview()
        await preview.value

        XCTAssertGreaterThanOrEqual(streaming.cancelCount, 1)
        XCTAssertFalse(viewModel.isPreviewing)
        XCTAssertNil(viewModel.preview)
    }

    func testCleanViewHasNoSubsetExecutionControl() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Features/Clean/CleanView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for forbidden in ["Toggle(", "Checkbox", "selectedEntries", "cleanSelected", "selectAll"] {
            XCTAssertFalse(source.contains(forbidden), "CleanView must not offer subset execution: \(forbidden)")
        }
    }

    func testStageLocalizationKeysHaveThreeLocales() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for section in CleanStageCatalog.sections {
            let key = try XCTUnwrap(CleanStageCatalog.key(for: section))
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "missing \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "zh-Hans", "zh-Hant"] {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
                let value = try XCTUnwrap((localization["stringUnit"] as? [String: Any])?["value"] as? String)
                XCTAssertFalse(value.isEmpty)
            }
        }
    }

    func testProtectingPathInvalidatesCurrentPreview() async throws {
        let directory = try makeTemporaryDirectory(prefix: "clean-page-protect")
        defer { try? FileManager.default.removeItem(at: directory) }
        let listURL = directory.appendingPathComponent("clean-list.txt")
        let whitelistURL = directory.appendingPathComponent("whitelist")
        try "# header\n".write(to: whitelistURL, atomically: true, encoding: .utf8)
        let coordinator = OperationCoordinator()

        let process = CleanPageProcess(previewFileURL: listURL, contents: Self.fixture)
        let cleanViewModel = CleanViewModel(
            process: process,
            previewStore: CleanPreviewStore(fileURL: listURL),
            coordinator: coordinator
        )
        let whitelistViewModel = WhitelistViewModel(
            store: WhitelistStore(fileURL: whitelistURL),
            coordinator: coordinator
        )

        await cleanViewModel.previewClean()
        XCTAssertNotNil(cleanViewModel.preview)
        XCTAssertTrue(cleanViewModel.canConfirm)

        whitelistViewModel.load()
        whitelistViewModel.newPattern = "/Users/example/Library/Caches/a"
        whitelistViewModel.addPattern()
        whitelistViewModel.save()

        XCTAssertNil(cleanViewModel.preview)
        XCTAssertFalse(cleanViewModel.canConfirm)
        XCTAssertNil(cleanViewModel.lastReclaimBytes)
    }

    func testZhHansCleanCopyMentionsTrash() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in ["clean.execution_note", "clean.confirm_summary", "clean.subtitle"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
            let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
            XCTAssertTrue(value.contains("废纸篓"), "\(key) must mention 废纸篓")
            XCTAssertFalse(value.contains("永久删除"), "\(key) must not say 永久删除")
        }
    }

    private static let fixture = """
    # Mole Cleanup Preview
    === Browsers ===
    /Users/example/Library/Caches/a  # 2.4 GB, 18 items
    === Developer tools ===
    /Users/example/.npm  # 512 MB
    """

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor CleanPageProcess: MoleProcessControlling {
    private(set) var arguments: [[String]] = []
    private let previewFileURL: URL
    private let contents: String
    private let exitCode: Int32

    init(previewFileURL: URL, contents: String, exitCode: Int32 = 0) {
        self.previewFileURL = previewFileURL
        self.contents = contents
        self.exitCode = exitCode
    }

    func run(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> MoleCommandResult {
        self.arguments.append(arguments)
        if arguments == ["clean", "--dry-run"] {
            if exitCode == 0 {
                try contents.write(to: previewFileURL, atomically: true, encoding: .utf8)
            }
            return MoleCommandResult(stdout: "➤ Browsers\n", stderr: "", exitCode: exitCode)
        }
        return MoleCommandResult(stdout: "cleaned", stderr: "", exitCode: 0)
    }

    func cancel() async {}
}

private final class CleanPageStreaming: MoleStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var arguments: [[String]] = []
    private var cancellationCount = 0
    private var continuation: AsyncThrowingStream<MoleOutputEvent, Error>.Continuation?
    private let previewFileURL: URL
    private let contents: String
    private let lines: [String]
    private let block: Bool

    init(previewFileURL: URL, contents: String, lines: [String], block: Bool = false) {
        self.previewFileURL = previewFileURL
        self.contents = contents
        self.lines = lines
        self.block = block
    }

    var recordedArguments: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return arguments
    }

    var cancelCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancellationCount
    }

    func stream(
        _ arguments: [String],
        stdin: Data?,
        timeout: TimeInterval?
    ) async -> AsyncThrowingStream<MoleOutputEvent, Error> {
        lock.lock()
        self.arguments.append(arguments)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            guard !block else { return }
            Task {
                if !contents.isEmpty {
                    try? contents.write(to: previewFileURL, atomically: true, encoding: .utf8)
                }
                for line in lines {
                    continuation.yield(.stdoutLine(Data(line.utf8)))
                }
                continuation.finish()
            }
        }
    }

    func cancel() async {
        lock.lock()
        cancellationCount += 1
        let continuation = self.continuation
        lock.unlock()
        continuation?.finish(throwing: MoleBridgeError.cancelled)
    }
}
