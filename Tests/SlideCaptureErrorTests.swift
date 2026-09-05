import Testing
import Foundation
import ScreenCaptureKit
@testable import OneToOne

@Suite("SlideCaptureError")
struct SlideCaptureErrorTests {

    @Test("domaine SCStream + code userDeclined = refus d'autorisation")
    func recognizesUserDeclined() {
        let error = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == true)
    }

    @Test("domaine SCStream avec un autre code : pas un refus")
    func rejectsWrongCode() {
        let error = NSError(domain: SCStreamErrorDomain, code: -1, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == false)
    }

    @Test("le code userDeclined dans un autre domaine : pas un refus")
    func rejectsWrongDomain() {
        let error = NSError(domain: NSCocoaErrorDomain, code: SCStreamError.Code.userDeclined.rawValue, userInfo: nil)
        #expect(SlideCaptureError.isPermissionDenial(error) == false)
    }

    @Test("une erreur déjà traduite est reconnue selon son cas")
    func recognizesTranslatedError() {
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.screenRecordingDenied) == true)
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.noShareableWindows) == false)
        #expect(SlideCaptureError.isPermissionDenial(SlideCaptureError.captureFailed("x")) == false)
    }
}
