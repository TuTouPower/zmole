import SwiftUI

/// Shared metrics for the four overview cards.
enum OverviewCardLayout {
    /// All four cards share one fixed height so the two rows stay aligned.
    static let cardHeight: CGFloat = 264
}

@MainActor
struct OverviewView: View {
    @ObservedObject var statusViewModel: StatusViewModel
    @ObservedObject var viewModel: OverviewViewModel
    @ObservedObject var cleanViewModel: CleanViewModel
    @ObservedObject var navigation: NavigationModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                head
                if let errorKey = viewModel.errorMessageKey {
                    VStack(spacing: 10) {
                        UtilityNotice(title: LocalizedStringKey(errorKey), isError: true)
                        Button("overview.retry") { Task { await viewModel.refreshHistory() } }
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 10) {
                        UtilityNotice(title: "overview.error_title", detail: errorMessage, isError: true)
                        Button("overview.retry") { Task { await viewModel.refreshHistory() } }
                    }
                }
                if viewModel.showBusyNotice {
                    RecoverableBusyNotice()
                }
                heroRow
                lowerRow
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(MoleTheme.background)
        .navigationTitle("overview.title")
        .task {
            // Start the estimate first: it must not wait for the history
            // command, and its task is owned by the view model so leaving the
            // page does not cancel a running scan.
            viewModel.primeEstimate(usedBytes: usedBytes)
            viewModel.startEstimate(usedBytes: usedBytes)
            await viewModel.refreshHistory()
        }
        .onChange(of: usedBytes) { newValue in
            viewModel.usedBytesDidChange(newValue)
        }
        .onChange(of: viewModel.estimateInvalidated) { invalidated in
            guard invalidated else { return }
            viewModel.startEstimate(usedBytes: usedBytes)
        }
    }

    private var head: some View {
        MolePageHead(
            title: "overview.title"
        ) {
            Button {
                Task { await statusViewModel.resample() }
            } label: {
                Label("overview.refresh", systemImage: "arrow.clockwise")
            }
            Button {
                navigation.select(.clean)
            } label: {
                if let reclaimBytes = cleanViewModel.lastReclaimBytes {
                    Label("overview.clean_entry \(OverviewMetrics.bytes(reclaimBytes))", systemImage: "sparkle")
                } else {
                    Label("overview.clean_entry_plain", systemImage: "sparkle")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(MoleTheme.accent)
        }
        .padding(.bottom, 10)
    }

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 14) {
            healthCard
            storageCard
        }
    }

    // MARK: - Health card

    private var healthCard: some View {
        let card = OverviewHealthCard.make(
            snapshot: statusViewModel.snapshot,
            reclaimBytes: cleanViewModel.lastReclaimBytes
        )
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(card.status.titleKey))
                        .font(.system(size: 22, weight: .bold))
                    Text("overview.health.body")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.muted)
                        .frame(maxWidth: 360, alignment: .leading)
                }
                Spacer(minLength: 8)
                healthRing(card)
            }
            HStack(spacing: 10) {
                ForEach(card.tiles) { tile in
                    tileView(tile)
                }
            }
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            minHeight: OverviewCardLayout.cardHeight,
            maxHeight: OverviewCardLayout.cardHeight,
            alignment: .topLeading
        )
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func healthRing(_ card: OverviewHealthCard) -> some View {
        let snapshot = statusViewModel.snapshot
        let score = (snapshot?.healthScoreAvailable == true) ? snapshot?.healthScore : nil
        let fraction = Double(min(100, max(0, score ?? 0))) / 100
        return ZStack {
            Circle()
                .stroke(MoleTheme.surface3, style: StrokeStyle(lineWidth: 12))
            if score != nil {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(MoleTheme.accentStrong, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(verbatim: card.scoreText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("overview.health.score_label")
                    .font(.system(size: 9))
                    .foregroundStyle(MoleTheme.muted)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }

    private func tileView(_ tile: OverviewTile) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(tile.titleKey))
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.subtle)
            Text(verbatim: tile.value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let note = tile.note {
                Text(LocalizedStringKey(note))
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoleTheme.surface2, in: RoundedRectangle(cornerRadius: MoleTheme.radiusMD))
    }

    // MARK: - Storage card

    private var storageCard: some View {
        let card = OverviewStorageCard.make(breakdown: viewModel.breakdown, disk: primaryDisk)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("overview.storage")
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: card.capacityText ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.muted)
                }
                Spacer()
                Text("overview.storage.estimate")
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.subtle)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: card.usedText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("overview.storage.used_label")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.muted)
                }
                Spacer()
                if let freeText = card.freeText {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("overview.storage.free_format \(freeText)")
                            .font(.system(size: 12, weight: .semibold))
                        if let percent = card.freePercentText {
                            Text("overview.storage.free_percent \(percent)")
                                .font(.system(size: 10))
                                .foregroundStyle(MoleTheme.muted)
                        }
                    }
                }
            }
            segmentedBar(card)
            if !card.isComplete {
                Text("overview.storage.incomplete")
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.muted)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(StorageSegment.allCases) { segment in
                    legendRow(segment)
                }
            }
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            minHeight: OverviewCardLayout.cardHeight,
            maxHeight: OverviewCardLayout.cardHeight,
            alignment: .topLeading
        )
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func segmentedBar(_ card: OverviewStorageCard) -> some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let freeFraction = card.freeFraction.map { min(1, max(0, $0)) }
            let usedWidth = total * CGFloat(1 - (freeFraction ?? 0))
            HStack(spacing: 2) {
                ForEach(card.segments) { segment in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segment.segment.color)
                        .frame(width: max(1, usedWidth * CGFloat(segment.fraction)))
                }
                if freeFraction != nil {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MoleTheme.surface3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func legendRow(_ segment: StorageSegment) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(segment.color)
                .frame(width: 8, height: 8)
            Text(segment.titleKey)
                .font(.system(size: 10))
                .foregroundStyle(MoleTheme.muted)
            Spacer(minLength: 8)
            Text(verbatim: viewModel.breakdown.bytes(for: segment).map(OverviewMetrics.bytes) ?? "—")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
    }

    // MARK: - Lower row

    private var lowerRow: some View {
        HStack(alignment: .top, spacing: 14) {
            activityCard
            statusGridCard
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("overview.recent")
                        .font(.system(size: 15, weight: .semibold))
                    Text("overview.recent_subtitle")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.muted)
                }
                Spacer()
                Button("overview.view_history") { navigation.select(.history) }
                    .buttonStyle(.borderless)
            }
            .padding(16)
            Divider()
            let rows = OverviewActivity.rows(from: viewModel.recentOperations)
            if rows.isEmpty {
                Text("overview.recent_empty")
                    .font(.system(size: 11))
                    .foregroundStyle(MoleTheme.subtle)
                    .padding(16)
            } else {
                ForEach(rows) { row in
                    activityRow(row)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OverviewCardLayout.cardHeight,
            maxHeight: OverviewCardLayout.cardHeight,
            alignment: .topLeading
        )
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private func activityRow(_ row: OverviewActivityRow) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(MoleTheme.accentSoft)
                Image(systemName: row.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MoleTheme.accentStrong)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.command).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(verbatim: row.time).font(.system(size: 10)).foregroundStyle(MoleTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: row.value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if let items = row.items {
                    Text("overview.items \(items)")
                        .font(.system(size: 10))
                        .foregroundStyle(MoleTheme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 16)
        }
    }

    private var statusGridCard: some View {
        let grid = OverviewStatusGrid.make(snapshot: statusViewModel.snapshot)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("overview.status_grid")
                    .font(.system(size: 15, weight: .semibold))
                Text("overview.status_grid.subtitle")
                    .font(.system(size: 10))
                    .foregroundStyle(MoleTheme.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(grid.tiles) { tile in
                    tileView(tile)
                }
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            minHeight: OverviewCardLayout.cardHeight,
            maxHeight: OverviewCardLayout.cardHeight,
            alignment: .topLeading
        )
        .background(MoleTheme.surface, in: RoundedRectangle(cornerRadius: MoleTheme.radiusLG))
        .overlay(RoundedRectangle(cornerRadius: MoleTheme.radiusLG).strokeBorder(MoleTheme.line))
    }

    private var primaryDisk: StatusSnapshot.Disk? {
        statusViewModel.snapshot.map(OverviewMetrics.init)?.primaryDisk
    }

    private var usedBytes: Int64? {
        primaryDisk?.used
    }
}

enum StorageSegment: String, CaseIterable, Identifiable, Sendable {
    case system
    case applications
    case userData
    case developer
    case other

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "overview.storage.system"
        case .applications: "overview.storage.applications"
        case .userData: "overview.storage.user_data"
        case .developer: "overview.storage.developer"
        case .other: "overview.storage.other"
        }
    }

    var color: Color {
        switch self {
        case .system: Color(red: 0.35, green: 0.39, blue: 0.85)
        case .applications: Color(red: 0.54, green: 0.45, blue: 0.79)
        case .userData: Color(red: 0.36, green: 0.61, blue: 0.79)
        case .developer: Color(red: 0.85, green: 0.65, blue: 0.36)
        case .other: Color(red: 0.73, green: 0.74, blue: 0.78)
        }
    }
}

extension StorageBreakdown {
    func bytes(for segment: StorageSegment) -> Int64? {
        switch segment {
        case .system: systemBytes
        case .applications: applicationsBytes
        case .userData: userDataBytes
        case .developer: developerBytes
        case .other: otherBytes
        }
    }
}
