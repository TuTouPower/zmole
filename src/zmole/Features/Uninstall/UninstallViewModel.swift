import AppKit
import Combine
import Foundation

@MainActor
final class UninstallViewModel: ObservableObject {
    @Published private(set) var listings: [UninstallAppListing] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isListing = false
    @Published private(set) var listCapturedAt: Date?
    @Published private(set) var showBusyNotice = false
    @Published private(set) var focusedAppID: String?
    @Published private(set) var iconsByPath: [String: NSImage] = [:]
    @Published private(set) var relatedPathsByID: [String: [String]] = [:]
    @Published private(set) var listErrorMessage: String?
    @Published private(set) var listWasCancelled = false

    private let process: any MoleProcessControlling
    private let listStream: UninstallListStream
    private let coordinator: OperationCoordinator
    private let targetChecker: UninstallTargetChecking
    private let iconProvider: UninstallIconProviding
    private let revealer: FileRevealing
    private weak var scan: (any BackgroundScanProviding)?

    private var relatedLoadedIDs: Set<String> = []
    private let session = OperationSession<UninstallPreviewSnapshot>()
    private let leaseCoordinator: PreviewLeaseCoordinator
    private var transientErrorKey: String?
    private var iconTask: Task<Void, Never>?

    init(
        process: any MoleProcessControlling,
        listStream: UninstallListStream,
        coordinator: OperationCoordinator,
        targetChecker: UninstallTargetChecking = LiveUninstallTargetChecker(),
        iconProvider: UninstallIconProviding = LiveUninstallIconProvider(),
        revealer: FileRevealing = LiveFileRevealer(),
        scan: (any BackgroundScanProviding)? = nil
    ) {
        self.process = process
        self.listStream = listStream
        self.coordinator = coordinator
        self.targetChecker = targetChecker
        self.iconProvider = iconProvider
        self.revealer = revealer
        self.scan = scan
        leaseCoordinator = PreviewLeaseCoordinator(coordinator: coordinator)
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        leaseCoordinator.onInvalidation = { [weak self] in
            guard let self, self.session.preview != nil else { return false }
            self.session.expirePreview(errorKey: "operation.error.stale_scan")
            return true
        }
    }

    var operationState: OperationState<UninstallPreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var isExecuting: Bool { session.isExecuting }
    var isConfirmationPresented: Bool { session.isConfirmationPresented }

    /// Rows whose identity is fully resolved (selectable/uninstallable).
    var apps: [UninstallApp] { listings.compactMap(\.uninstallApp) }

    var selectedApps: [UninstallApp] {
        apps.filter { selectedPaths.contains($0.path) }
    }

    var canUninstall: Bool {
        guard !selectedPaths.isEmpty, !isListing, !session.isBusy else { return false }
        let resolvedPaths = Set(listings.lazy.filter(\.isResolved).map(\.path))
        return selectedPaths.isSubset(of: resolvedPaths)
    }
    var canConfirm: Bool { session.canConfirm && leaseCoordinator.isCurrentPreview }
    var executionSummary: String? { session.result?.summary }
    var errorMessageKey: String? { transientErrorKey ?? session.result?.errorKey }
    var errorMessage: String? {
        if transientErrorKey != nil { return nil }
        return session.result?.summary
    }

    /// What the confirmation sheet covers: app count and known total size of
    /// the current preview.
    var confirmationDetail: String? {
        guard let preview = session.preview else { return nil }
        let bytes = preview.apps.compactMap(\.sizeBytes).reduce(0, +)
        let sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return String(localized: "uninstall.confirm_detail \(preview.apps.count) \(sizeText)")
    }

    func icon(for app: UninstallApp) -> NSImage? { iconsByPath[app.path] }

    func icon(forPath path: String) -> NSImage? { iconsByPath[path] }

    // MARK: - Listing

    func loadListIfNeeded() async {
        guard !hasLoaded else { return }
        if adoptPrewarmList() { return }
        await loadList()
    }

    func loadList() async {
        guard !isListing, !session.isBusy else { return }
        scan?.userDidRescan(.uninstallList)
        leaseCoordinator.release()
        session.invalidate()
        selectedPaths.removeAll()
        clearTransientError()
        relatedLoadedIDs = []
        relatedPathsByID = [:]
        iconsByPath = [:]
        listings = []
        listCapturedAt = nil
        listWasCancelled = false
        await performList()
    }

    /// Streams the list into `listings`, merging later rows per path. Keeps
    /// whatever session state exists (the identity-refusal path re-scans the
    /// list while its failure stays on screen); the fresh scan replaces the
    /// listing wholesale, so removed apps do not linger.
    private func performList() async {
        guard !isListing else { return }
        listErrorMessage = nil
        isListing = true
        defer { isListing = false }

        var merged: [UninstallAppListing] = []
        var indexByPath: [String: Int] = [:]
        var seenPaths: Set<String> = []
        do {
            let rows = await listStream.rows()
            var lastPublish = Date.distantPast
            var dirty = false
            for try await row in rows {
                UninstallListMerge.merge(row, into: &merged, indexByPath: &indexByPath)
                seenPaths.insert(row.path)
                dirty = true
                // Throttle progressive publishes so the view is not rebuilt
                // once per resolved row; the wholesale assignment at the end
                // keeps the listing free of leftovers from the previous pass.
                let now = Date()
                if now.timeIntervalSince(lastPublish) >= 0.05 {
                    listings = merged
                    lastPublish = now
                    dirty = false
                }
            }
            if dirty {
                listings = merged
            }
            hasLoaded = true
        } catch let error as MoleBridgeError where error == .cancelled {
            // Keep whatever was already resolved; a cancelled scan is not a
            // failure, but it is flagged so the UI can offer to resume.
            listWasCancelled = true
        } catch {
            guard !CommandBusy.isBusy(error) else {
                showBusyNotice = true
                return
            }
            listings = []
            hasLoaded = false
            listErrorMessage = error.localizedDescription
            return
        }

        // Drop session state for rows this pass no longer reports, including
        // after a cancelled scan that already replaced the listing.
        pruneSessionState(to: seenPaths)
        if hasLoaded {
            if focusedAppID == nil || !listings.contains(where: { $0.path == focusedAppID }) {
                focusedAppID = listings.first?.path
            }
            startIconLoading()
        }
    }

    private func pruneSessionState(to seenPaths: Set<String>) {
        selectedPaths = selectedPaths.intersection(seenPaths)
        relatedLoadedIDs = relatedLoadedIDs.intersection(seenPaths)
        relatedPathsByID = relatedPathsByID.filter { seenPaths.contains($0.key) }
        iconsByPath = iconsByPath.filter { seenPaths.contains($0.key) }
    }

    func cancelList() async {
        guard isListing else { return }
        await listStream.cancel()
    }

    private func adoptPrewarmList() -> Bool {
        guard let result = scan?.result(for: .uninstallList),
              case let .uninstallRows(rows) = result.payload else { return false }
        listings = rows
        hasLoaded = true
        listCapturedAt = result.capturedAt
        focusedAppID = rows.first?.path
        startIconLoading()
        return true
    }

    /// Icons arrive after the list is already interactive; the list never
    /// blocks on a synchronous icon read.
    private func startIconLoading() {
        iconTask?.cancel()
        iconTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for listing in listings where iconsByPath[listing.path] == nil {
                guard !Task.isCancelled else { return }
                if let icon = await iconProvider.icon(forAppAt: listing.path) {
                    iconsByPath[listing.path] = icon
                }
            }
        }
    }

    // MARK: - Selection

    func toggleSelection(_ app: UninstallApp) {
        toggleSelection(path: app.path)
    }

    func toggleSelection(path: String) {
        guard !isListing, !session.isBusy else { return }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
        leaseCoordinator.release()
        session.invalidate()
        clearTransientError()
    }

    func clearSelection() {
        guard !isListing, !session.isBusy else { return }
        selectedPaths.removeAll()
        leaseCoordinator.release()
        session.invalidate()
        clearTransientError()
    }

    // MARK: - Detail

    var focusedApp: UninstallApp? {
        guard let focusedAppID else { return nil }
        return apps.first { $0.path == focusedAppID }
    }

    func focus(path: String) {
        focusedAppID = path
    }

    /// nil until that app's own dry-run has run; empty means the dry-run found
    /// no related paths. Related files are never inferred from the list JSON.
    func relatedPaths(for app: UninstallApp) -> [String]? {
        relatedLoadedIDs.contains(app.path) ? (relatedPathsByID[app.path] ?? []) : nil
    }

    func revealInFinder(_ app: UninstallApp) {
        Task { await revealer.reveal(path: app.path) }
    }

    /// Runs the related-files dry-run on demand. It holds the uninstall lease so
    /// it cannot run concurrently with a batch preview/execution on the shared
    /// single-slot command bridge.
    func loadRelatedFiles(for app: UninstallApp) async {
        guard !relatedLoadedIDs.contains(app.path), !session.isBusy, !isListing else { return }
        guard (try? UninstallSelectionValidator.batch(selectedIDs: [app.path], apps: apps)) != nil else {
            relatedLoadedIDs.insert(app.path)
            relatedPathsByID[app.path] = []
            return
        }
        guard let lease = coordinator.acquire(.uninstall) else { return }
        defer { lease.release() }

        // Leave the app unmarked on failure so the detail can retry rather than
        // permanently reporting "no related files" after a transient busy error.
        guard let result = try? await process.run(
            ["uninstall", "--dry-run", app.uninstallName],
            stdin: Self.confirmationInput,
            timeout: 120
        ), result.exitCode == 0 else {
            transientErrorKey = "uninstall.error.related_failed"
            objectWillChange.send()
            return
        }
        relatedLoadedIDs.insert(app.path)
        relatedPathsByID[app.path] = Self.relatedPaths(from: result.stdout)
    }

    static func relatedPaths(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let line = MaintenanceOutput.stripANSI(String(rawLine))
                guard let start = firstPathIndex(in: line) else { return nil }
                let path = stripTrailingSize(from: String(line[start...]))
                    .trimmingCharacters(in: .whitespaces)
                return path.isEmpty ? nil : path
            }
            .filter { $0.hasPrefix("/") || $0.hasPrefix("~/") }
    }

    /// First `/`- or `~/`-leading substring in a preview line, skipping the
    /// leading "✓"/"System:"/"Review only:" decorations mole prints.
    private static func firstPathIndex(in line: String) -> String.Index? {
        let slash = line.firstIndex(of: "/")
        let tilde = line.range(of: "~/")?.lowerBound
        switch (slash, tilde) {
        case let (.some(slashIndex), .some(tildeIndex)):
            return min(slashIndex, tildeIndex)
        case let (.some(slashIndex), .none):
            return slashIndex
        case let (.none, .some(tildeIndex)):
            return tildeIndex
        case (.none, .none):
            return nil
        }
    }

    /// Drops the trailing ` <size>` token that `format_uninstall_preview_path`
    /// appends (e.g. `"/p 1.4GB"` -> `"/p"`).
    private static func stripTrailingSize(from path: String) -> String {
        guard let lastSpace = path.lastIndex(of: " ") else { return path }
        let tail = String(path[path.index(after: lastSpace)...])
        let sizePattern = #"^\d+(\.\d+)?\s?(B|KB|MB|GB|TB|PB|KiB|MiB|GiB|TiB)$"#
        guard tail.range(of: sizePattern, options: [.regularExpression, .caseInsensitive]) != nil else {
            return path
        }
        return String(path[..<lastSpace])
    }

    // MARK: - Confirmation / execution

    /// Opens the confirmation sheet for the current selection. Associated
    /// files stay an optional per-app check, not a gating step.
    func requestConfirmation() {
        guard canUninstall else { return }
        leaseCoordinator.release()
        session.invalidate()
        clearTransientError()
        let batch: [UninstallApp]
        do {
            batch = try UninstallSelectionValidator.batch(selectedIDs: selectedPaths, apps: apps)
        } catch {
            setTransientError(error)
            return
        }
        leaseCoordinator.captureGeneration()
        session.adoptPreview(
            UninstallPreviewSnapshot(
                generation: UUID(),
                apps: batch,
                selectedIDs: selectedPaths,
                output: ""
            )
        )
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
        leaseCoordinator.release()
    }

    func confirmExecution() async {
        guard session.isConfirmationPresented, canConfirm,
              let currentPreview = session.preview else { return }
        guard leaseCoordinator.acquire(.uninstall) else {
            showBusyNotice = true
            session.cancelConfirmation()
            return
        }
        showBusyNotice = false
        guard let execution = session.beginExecution() else {
            leaseCoordinator.release()
            return
        }
        leaseCoordinator.invalidateAndRecapture()

        do {
            // Confirm-time check stays cheap: path + bundle identity. The
            // session list is reused; no full size scan is run.
            for app in currentPreview.apps where !(await targetChecker.stillMatches(app)) {
                throw UninstallViewModelError.changedTarget
            }
            selectedPaths = Set(currentPreview.selectedIDs)
            let result = try await process.run(
                ["uninstall"] + currentPreview.apps.map(\.uninstallName),
                stdin: Self.confirmationInput,
                timeout: 600
            )
            leaseCoordinator.markDataModified()
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            let operationResult = UninstallBatchResultParser.result(
                result,
                expectedCount: currentPreview.apps.count
            )
            session.finish(operationResult, id: execution.id)
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
            if operationResult.status == .succeeded {
                pruneRemoved(paths: Set(currentPreview.apps.map(\.path)))
            } else if operationResult.status == .partial {
                // Partially removed: succeeded and failed targets cannot be
                // told apart reliably from the summary, so re-scan instead of
                // leaving stale rows selectable.
                await performList()
            }
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: execution.id
            )
            leaseCoordinator.invalidatePreviews()
            leaseCoordinator.release()
        } catch {
            guard session.accepts(execution.id) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                session.invalidate()
                leaseCoordinator.invalidatePreviews()
                leaseCoordinator.release()
                return
            }
            let result: OperationResult
            if let commandError = error as? MoleBridgeError,
               case let .commandFailed(commandResult) = commandError {
                result = UninstallBatchResultParser.result(
                    commandResult,
                    expectedCount: currentPreview.apps.count
                )
            } else if let domainError = error as? UninstallViewModelError {
                result = OperationResult(status: .failed, errorKey: domainError.errorKey)
            } else {
                result = OperationResult(status: .failed, summary: error.localizedDescription, errorKey: "uninstall.error.failed")
            }
            session.fail(result, id: execution.id)
            leaseCoordinator.release()
            if (error as? UninstallViewModelError) == .changedTarget {
                // Identity changed since preview: refuse and re-scan the list
                // while the refusal stays visible.
                await performList()
            }
        }
    }

    func cancelExecution() async {
        guard let operationID = session.beginExecutionCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
            id: operationID
        )
        leaseCoordinator.invalidatePreviews()
        leaseCoordinator.release()
    }

    private func clearTransientError() {
        transientErrorKey = nil
        objectWillChange.send()
    }

    private func setTransientError(_ error: Error) {
        transientErrorKey = (error as? UninstallViewModelError)?.errorKey
            ?? "uninstall.error.failed"
        objectWillChange.send()
    }

    private func pruneRemoved(paths: Set<String>) {
        listings.removeAll { paths.contains($0.path) }
        selectedPaths.subtract(paths)
        relatedLoadedIDs.subtract(paths)
        relatedPathsByID = relatedPathsByID.filter { !paths.contains($0.key) }
        iconsByPath = iconsByPath.filter { !paths.contains($0.key) }
    }

    private static let confirmationInput = Data("y\n".utf8)
}
