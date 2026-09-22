import XCTest
@testable import Zmole

final class CleanPresentationTests: XCTestCase {
    @MainActor
    func testPreviewAndConfirmationPropertiesAreDerivedFromOperationState() {
        let session = OperationSession<String>()
        let id = session.beginPreview()!
        XCTAssertTrue(session.isPreviewing)
        session.acceptPreview("plan", id: id)
        XCTAssertFalse(session.isPreviewing)
        XCTAssertTrue(session.canConfirm)
        XCTAssertTrue(session.beginConfirmation())
        XCTAssertTrue(session.isConfirmationPresented)
        session.cancelConfirmation()
        XCTAssertFalse(session.isConfirmationPresented)
        XCTAssertNil(session.preview)
    }
}
