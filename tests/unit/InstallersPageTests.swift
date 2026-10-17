import XCTest
@testable import Zmole

@MainActor
final class InstallersPageTests: XCTestCase {
    func testScanUsesOnlyNonInteractiveListing() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)

        await viewModel.scan()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations, [["installer", "--list-json"]])
        XCTAssertEqual(viewModel.candidates.count, 3)
    }

    func testScanIsSkippedWithoutFullDiskAccess() async {
        let spy = InstallerRunnerSpy()
        let monitor = FullDiskAccessMonitor(probe: { false })
        let viewModel = InstallersViewModel(
            interface: InstallerInterface { arguments in await spy.run(arguments) },
            coordinator: OperationCoordinator(),
            accessMonitor: monitor
        )

        await viewModel.loadListIfNeeded()
        await viewModel.scan()

        let invocations = await spy.invocations
        XCTAssertTrue(
            invocations.isEmpty,
            "without Full Disk Access the installer scan must not run"
        )
        XCTAssertTrue(viewModel.candidates.isEmpty)
    }

    func testNoRemovalBeforeConfirmation() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.scan()
        viewModel.toggleSelection(viewModel.candidates[0])

        let beforeConfirm = await spy.removalInvocations
        XCTAssertTrue(beforeConfirm.isEmpty)

        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()
        let afterCancel = await spy.removalInvocations
        XCTAssertTrue(afterCancel.isEmpty)
    }

    func testConfirmRemovalUsesOnlySelectedListedPaths() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.scan()
        XCTAssertEqual(viewModel.candidates.count, 3)
        let first = Self.fixture[0]
        let third = Self.fixture[2]
        let middle = Self.fixture[1]
        viewModel.toggleSelection(first)
        viewModel.toggleSelection(third)

        viewModel.requestConfirmation()
        await viewModel.confirmRemoval()

        let removals = await spy.removalInvocations
        XCTAssertEqual(removals.count, 2)
        for invocation in removals {
            XCTAssertEqual(Array(invocation.prefix(2)), ["installer", "--remove"])
        }
        let removedPaths = removals.compactMap { $0.count >= 3 ? $0[2] : nil }
        XCTAssertEqual(Set(removedPaths), Set([first.path, third.path]))
        XCTAssertFalse(removedPaths.contains(middle.path))
    }

    func testNewScanInvalidatesSelectionAndConfirmation() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.scan()
        viewModel.toggleSelection(viewModel.candidates[0])
        viewModel.requestConfirmation()
        XCTAssertTrue(viewModel.isConfirmationPresented)

        await viewModel.scan()
        XCTAssertTrue(viewModel.selectedPaths.isEmpty)
        XCTAssertFalse(viewModel.canConfirm)
        XCTAssertFalse(viewModel.isConfirmationPresented)
    }

    func testRejectedPathsAreKeptWithReason() async {
        let spy = InstallerRunnerSpy(failingPaths: [Self.fixture[1].path])
        let viewModel = makeViewModel(spy)
        await viewModel.scan()
        let selected = [viewModel.candidates[0], viewModel.candidates[1]]
        selected.forEach(viewModel.toggleSelection)

        viewModel.requestConfirmation()
        await viewModel.confirmRemoval()

        XCTAssertEqual(viewModel.failures.map(\.path), [Self.fixture[1].path])
        XCTAssertEqual(viewModel.failures.first?.reason, "changed since scan")
        XCTAssertTrue(viewModel.selectedPaths.contains(Self.fixture[1].path))
        XCTAssertFalse(viewModel.candidates.contains { $0.path == Self.fixture[0].path })
    }

    func testTrashWordingIsPresent() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("src/zmole/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: sourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        for key in ["installers.trash_note", "installers.confirm_summary"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let zh = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
            let value = try XCTUnwrap((zh["stringUnit"] as? [String: Any])?["value"] as? String)
            XCTAssertTrue(value.contains("废纸篓"), "\(key) must mention 废纸篓")
        }
    }

    func testConfirmationDetailIncludesSelectedCount() async {
        let viewModel = makeViewModel(InstallerRunnerSpy())
        await viewModel.scan()
        viewModel.toggleSelection(Self.fixture[0])
        viewModel.toggleSelection(Self.fixture[1])
        XCTAssertTrue(viewModel.confirmationDetail.contains("2"))
    }

    func testRemovalRequiresFreshConfirmationAfterCancel() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.scan()
        viewModel.toggleSelection(Self.fixture[0])
        viewModel.requestConfirmation()
        viewModel.cancelConfirmation()

        // Without a new confirmation, an explicit removal attempt is a no-op.
        await viewModel.confirmRemoval()
        var removals = await spy.removalInvocations
        XCTAssertTrue(removals.isEmpty)

        viewModel.requestConfirmation()
        await viewModel.confirmRemoval()
        removals = await spy.removalInvocations
        XCTAssertEqual(removals.count, 1)
    }

    func testBatchRemovalUsesTheSameListingWithoutRescanning() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.loadListIfNeeded()
        let first = Self.fixture[0]
        let second = Self.fixture[1]
        viewModel.toggleSelection(first)
        viewModel.toggleSelection(second)

        viewModel.requestConfirmation()
        await viewModel.confirmRemoval()

        let invocations = await spy.invocations
        let listCalls = invocations.filter { $0 == ["installer", "--list-json"] }
        XCTAssertEqual(listCalls.count, 1, "the scan roots are traversed once, at listing time")
        let removals = await spy.removalInvocations
        XCTAssertEqual(removals.count, 2, "each file is verified and removed individually")
    }

    func testPageReentryReusesTheSessionList() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.loadListIfNeeded()
        await viewModel.loadListIfNeeded()
        await viewModel.loadListIfNeeded()

        let invocations = await spy.invocations
        XCTAssertEqual(invocations.filter { $0 == ["installer", "--list-json"] }.count, 1)
    }

    func testSelectionCannotOutliveItsSessionList() async {
        let spy = InstallerRunnerSpy()
        let viewModel = makeViewModel(spy)
        await viewModel.loadListIfNeeded()
        viewModel.toggleSelection(Self.fixture[0])
        XCTAssertTrue(
            viewModel.selectedPaths.isSubset(of: Set(viewModel.candidates.map(\.path))),
            "selection is always derived from the session list"
        )

        // Re-scanning replaces the session list; the old selection and its
        // confirmation are gone, so nothing can be removed from a stale list.
        await viewModel.scan()
        XCTAssertTrue(viewModel.selectedPaths.isSubset(of: Set(viewModel.candidates.map(\.path))))
        XCTAssertFalse(viewModel.canConfirm)
        await viewModel.confirmRemoval()
        let removals = await spy.removalInvocations
        XCTAssertTrue(removals.isEmpty, "a stale confirmation must not remove anything")
    }

    private func makeViewModel(_ spy: InstallerRunnerSpy) -> InstallersViewModel {
        InstallersViewModel(
            interface: InstallerInterface { arguments in await spy.run(arguments) },
            coordinator: OperationCoordinator()
        )
    }

    private static let fixture: [InstallerCandidate] = [
        InstallerCandidate(path: "/Users/demo/Downloads/A.dmg", sizeBytes: 100, source: "Downloads", identity: "1"),
        InstallerCandidate(path: "/Users/demo/Downloads/B.pkg", sizeBytes: 200, source: "Downloads", identity: "2"),
        InstallerCandidate(path: "/Users/demo/Downloads/C.zip", sizeBytes: 300, source: "Downloads", identity: "3")
    ]

    nonisolated fileprivate static let listJSON = """
    [{"path":"/Users/demo/Downloads/A.dmg","size_bytes":100,"source":"Downloads","identity":"1"},{"path":"/Users/demo/Downloads/B.pkg","size_bytes":200,"source":"Downloads","identity":"2"},{"path":"/Users/demo/Downloads/C.zip","size_bytes":300,"source":"Downloads","identity":"3"}]
    """
}

private actor InstallerRunnerSpy {
    private(set) var invocations: [[String]] = []
    private(set) var removalInvocations: [[String]] = []
    private let failingPaths: Set<String>

    init(failingPaths: Set<String> = []) {
        self.failingPaths = failingPaths
    }

    func run(_ arguments: [String]) async -> MoleCommandResult {
        invocations.append(arguments)
        if arguments == ["installer", "--list-json"] {
            return MoleCommandResult(stdout: InstallersPageTests.listJSON, stderr: "", exitCode: 0)
        }
        if arguments.first == "installer", arguments.contains("--remove") {
            removalInvocations.append(arguments)
            let path = arguments.count > 2 ? arguments[2] : ""
            if failingPaths.contains(path) {
                return MoleCommandResult(stdout: "", stderr: "changed since scan", exitCode: 1)
            }
            return MoleCommandResult(stdout: "Moved to Trash", stderr: "", exitCode: 0)
        }
        return MoleCommandResult(stdout: "[]", stderr: "", exitCode: 0)
    }
}
