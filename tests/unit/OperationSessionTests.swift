import XCTest
@testable import Zmole

final class OperationSessionTests: XCTestCase {
    @MainActor
    func testLatePreviewCannotReplaceNewGeneration() {
        let session = OperationSession<String>()
        let first = session.beginPreview()!
        session.invalidate()
        let second = session.beginPreview()!

        session.acceptPreview("late", id: first)

        XCTAssertEqual(session.state, .previewing(second))
        session.acceptPreview("current", id: second)
        XCTAssertEqual(session.preview, "current")
    }

    @MainActor
    func testCancellationConvergesAndRejectsLateResult() {
        let session = OperationSession<String>()
        let id = session.beginPreview()!
        session.acceptPreview("plan", id: id)
        XCTAssertTrue(session.beginConfirmation())
        let execution = session.beginExecution()!
        XCTAssertEqual(execution.id, id)
        XCTAssertEqual(session.beginExecutionCancellation(), id)

        session.finishCancelled(
            OperationResult(status: .cancelled, errorKey: "cancelled"),
            id: id
        )
        session.finish(OperationResult(status: .succeeded), id: id)

        XCTAssertFalse(session.isBusy)
        XCTAssertEqual(session.result?.status, .cancelled)
    }

    @MainActor
    func testStateDoesNotRepresentPreviewAndExecutionAtOnce() {
        let session = OperationSession<String>()
        let id = session.beginPreview()!
        session.acceptPreview("plan", id: id)
        XCTAssertFalse(session.isPreviewing)
        XCTAssertTrue(session.canConfirm)
        XCTAssertTrue(session.beginConfirmation())
        XCTAssertTrue(session.beginExecution() != nil)
        XCTAssertFalse(session.canConfirm)
        XCTAssertTrue(session.isExecuting)
    }

    @MainActor
    func testCoordinatorSerializesWritesAndInvalidatesPreviews() {
        let coordinator = OperationCoordinator()
        let lease = coordinator.acquire(.clean)
        XCTAssertNotNil(lease)
        XCTAssertNil(coordinator.acquire(.uninstall))
        lease?.release()

        let generation = coordinator.invalidationGeneration
        coordinator.invalidatePreviews()
        XCTAssertFalse(coordinator.isCurrent(generation))
        let protectionLease = coordinator.acquire(.protectionRules)
        XCTAssertNotNil(protectionLease)
        protectionLease?.release()
    }
}
