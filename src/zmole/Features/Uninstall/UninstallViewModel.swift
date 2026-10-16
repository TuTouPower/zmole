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

    private let process: any MoleProcessControlling
    private let listStream: UninstallListStream
    private let coordinator: OperationCoordinator
    private let targetChecker: UninstallTargetChecking
    private let iconProvider: UninstallIconProviding
    private let revealer: FileRevealing
    private weak var prewarm: (any PrewarmResultProviding)?

    private var relatedLoadedIDs: Set<String> = []
    private let session = OperationSession<UninstallPreviewSnapshot>()
    private var lease: OperationLease?
    private var previewCoordinatorGeneration: UInt64?
    private var transientErrorKey: String?
    private var iconTask: Task<Void, Never>?
    private var coordinatorSubscription: AnyCancellable?

    init(
        process: any MoleProcessControlling,
        listStream: UninstallListStream,
        coordinator: OperationCoordinator,
        targetChecker: UninstallTargetChecking = LiveUninstallTargetChecker(),
        iconProvider: UninstallIconProviding = LiveUninstallIconProvider(),
        revealer: FileRevealing = LiveFileRevealer(),
        prewarm: (any PrewarmResultProviding)? = nil
    ) {
        self.process = process
        self.listStream = listStream
        self.coordinator = coordinator
        self.targetChecker = targetChecker
        self.iconProvider = iconProvider
        self.revealer = revealer
        self.prewarm = prewarm
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        coordinatorSubscription = coordinator.$invalidationGeneration.sink { [weak self] generation in
            self?.expirePreviewIfNeeded(generation: generation)
        }
    }

    var operationState: OperationState<UninstallPreviewSnapshot> { session.state }
    var result: OperationResult? { session.result }
    var preview: UninstallPreviewSnapshot? { session.preview }
    var isPreviewing: Bool { session.isPreviewing }
    var isExecuting: Bool { session.isExecuting }
    var isConfirmationPresented: Bool { session.isConfirmationPresented }

    /// Rows whose identity is fully resolved (previewable/uninstallable).
    var apps: [UninstallApp] { listings.compactMap(\.uninstallApp) }

    /// Kept for call sites that bound selection to application ids.
    var selectedIDs: Set<String> { selectedPaths }

    var selectedApps: [UninstallApp] {
        apps.filter { selectedPaths.contains($0.path) }
    }

    var canPreview: Bool {
        !selectedPaths.isEmpty && !isListing && !session.isBusy
            && selectedPaths.allSatisfy { path in
                listings.contains { $0.path == path && $0.isResolved }
            }
    }
    var canConfirm: Bool { session.canConfirm && isCurrentPreview }
    var executionSummary: String? { session.result?.summary }
    var errorMessageKey: String? { transientErrorKey ?? session.result?.errorKey }
    var errorMessage: String? {
        if transientErrorKey != nil { return nil }
        return session.result?.summary
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
        prewarm?.userDidRescan(.uninstallList)
        releaseLease()
        session.invalidate()
        selectedPaths.removeAll()
        clearTransientError()
        relatedLoadedIDs = []
        relatedPathsByID = [:]
        iconsByPath = [:]
        listings = []
        listCapturedAt = nil
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
            for try await row in rows {
                UninstallListMerge.merge(row, into: &merged, indexByPath: &indexByPath)
                seenPaths.insert(row.path)
                // Publish each pass so rows show up while the scan is still
                // resolving sizes; the wholesale assignment at the end keeps
                // the listing free of leftovers from the previous pass.
                listings = merged
            }
            hasLoaded = true
        } catch let error as MoleBridgeError where error == .cancelled {
            // Keep whatever was already resolved; a cancelled scan is not a
            // failure and must not show as one.
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
        guard let result = prewarm?.takeResult(.uninstallList),
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

    func cancelPreview() async {
        guard let operationID = session.beginPreviewCancellation() else { return }
        await process.cancel()
        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
            id: operationID
        )
        releaseLease()
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
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    func selectAll(_ ids: Set<String>) {
        guard !isListing, !session.isBusy else { return }
        let all = Set(listings.map(\.path))
        selectedPaths = ids.isEmpty ? all : all.intersection(ids)
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    func clearSelection() {
        guard !isListing, !session.isBusy else { return }
        selectedPaths.removeAll()
        releaseLease()
        session.invalidate()
        clearTransientError()
    }

    // MARK: - Detail

    var focusedApp: UninstallApp? {
        guard let focusedAppID else { return nil }
        return apps.first { $0.path == focusedAppID }
    }

    func focus(_ app: UninstallApp) {
        focusedAppID = app.path
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
            return
        }
        relatedLoadedIDs.insert(app.path)
        relatedPathsByID[app.path] = Self.relatedPaths(from: result.stdout)
    }

    static func relatedPaths(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") || $0.hasPrefix("~/") }
    }

    // MARK: - Preview / execution

    func previewUninstall() async {
        guard !isListing, !session.isBusy else { return }
        releaseLease()
        session.invalidate()
        clearTransientError()
        let batch: [UninstallApp]
        do {
            batch = try UninstallSelectionValidator.batch(selectedIDs: selectedPaths, apps: apps)
        } catch {
            setTransientError(error)
            return
        }
        guard let newLease = coordinator.acquire(.uninstall) else {
            showBusyNotice = true
            return
        }
        lease = newLease
        guard let operationID = session.beginPreview() else {
            releaseLease()
            return
        }
        showBusyNotice = false
        previewCoordinatorGeneration = coordinator.invalidationGeneration

        do {
            let result = try await process.run(
                ["uninstall", "--dry-run"] + batch.map(\.uninstallName),
                stdin: Self.confirmationInput,
                timeout: 120
            )
            guard session.accepts(operationID), !session.isCancelling(operationID) else { return }
            guard coordinator.isCurrent(previewCoordinatorGeneration ?? 0) else {
                session.fail(
                    OperationResult(status: .failed, errorKey: "operation.error.stale_preview"),
                    id: operationID
                )
                releaseLease()
                return
            }
            guard result.exitCode == 0 else {
                throw MoleBridgeError.commandFailed(result)
            }
            session.acceptPreview(
                UninstallPreviewSnapshot(
                    generation: operationID,
                    apps: batch,
                    selectedIDs: selectedPaths,
                    output: outputSummary(result)
                ),
                id: operationID
            )
            releaseLease(clearPreviewGeneration: false)
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: operationID
            )
            releaseLease()
        } catch {
            guard session.accepts(operationID) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                releaseLease()
                return
            }
            let summary = (error as? MoleBridgeError).flatMap { commandError -> String? in
                if case let .commandFailed(result) = commandError { return outputSummary(result) }
                return commandError.localizedDescription
            }
            session.fail(
                OperationResult(status: .failed, summary: summary, errorKey: "uninstall.error.failed"),
                id: operationID
            )
            releaseLease()
        }
    }

    func requestConfirmation() {
        guard canConfirm else { return }
        _ = session.beginConfirmation()
    }

    func cancelConfirmation() {
        guard session.isConfirmationPresented else { return }
        session.cancelConfirmation()
        releaseLease()
    }

    func confirmExecution() async {
        guard session.isConfirmationPresented, canConfirm,
              let currentPreview = session.preview,
              let previewID = operationID(for: session.state) else { return }
        guard let newLease = coordinator.acquire(.uninstall) else {
            showBusyNotice = true
            session.cancelConfirmation()
            return
        }
        lease = newLease
        showBusyNotice = false
        guard let execution = session.beginExecution() else {
            releaseLease()
            return
        }
        coordinator.invalidatePreviews()
        previewCoordinatorGeneration = coordinator.invalidationGeneration

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
            guard session.accepts(execution.id), !session.isCancelling(execution.id) else { return }
            let operationResult = UninstallBatchResultParser.result(
                result,
                expectedCount: currentPreview.apps.count
            )
            session.finish(operationResult, id: execution.id)
            coordinator.invalidatePreviews()
            releaseLease()
        } catch let error as MoleBridgeError where error == .cancelled {
            session.finishCancelled(
                OperationResult(status: .cancelled, errorKey: "uninstall.cancelled"),
                id: execution.id
            )
            coordinator.invalidatePreviews()
            releaseLease()
        } catch {
            guard session.accepts(execution.id) else { return }
            if CommandBusy.isBusy(error) {
                showBusyNotice = true
                coordinator.invalidatePreviews()
                releaseLease()
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
            releaseLease()
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
        coordinator.invalidatePreviews()
        releaseLease()
    }

    private func operationID(for state: OperationState<UninstallPreviewSnapshot>) -> UUID? {
        switch state {
        case let .ready(id, _), let .confirming(id, _), let .executing(id, _): return id
        default: return nil
        }
    }

    private var isCurrentPreview: Bool {
        guard let generation = previewCoordinatorGeneration else { return false }
        return coordinator.isCurrent(generation)
    }

    private func expirePreviewIfNeeded(generation: UInt64) {
        guard let previewGeneration = previewCoordinatorGeneration,
              previewGeneration != generation,
              session.preview != nil else { return }
        session.expirePreview(errorKey: "operation.error.stale_preview")
        previewCoordinatorGeneration = nil
    }

    private func releaseLease(clearPreviewGeneration: Bool = true) {
        lease?.release()
        lease = nil
        if clearPreviewGeneration {
            previewCoordinatorGeneration = nil
        }
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

    private func outputSummary(_ result: MoleCommandResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let confirmationInput = Data("y\n".utf8)
}
