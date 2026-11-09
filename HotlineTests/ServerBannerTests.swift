// ServerBannerTests

import Testing
import Foundation
@testable import Hotline

/// Where a server says its banner is, in a Server Banner message (122), or with its agreement (109).
struct ServerBannerTests {
  private func message(_ type: HotlineTransactionType = .serverBanner, _ fields: (inout HotlineTransaction) -> Void) -> HotlineTransaction {
    var transaction = HotlineTransaction(id: 1, type: type)
    fields(&transaction)
    return transaction
  }

  @Test func atAWebAddressByNumberOrLetters() {
    let byNumber = self.message { $0.setFieldUInt16(type: .serverBannerType, val: 1); $0.setFieldString(type: .serverBannerURL, val: "https://example.com/banner.gif") }
    #expect(HotlineServerBanner(from: byNumber) == .url(URL(string: "https://example.com/banner.gif")!))

    // A Server Banner message has the type as its four letters.
    let byLetters = self.message { $0.setFieldUInt32(type: .serverBannerType, val: "URL ".fourCharCode()); $0.setFieldString(type: .serverBannerURL, val: " https://example.com/b.jpg ") }
    #expect(HotlineServerBanner(from: byLetters) == .url(URL(string: "https://example.com/b.jpg")!))
  }

  @Test func anImageToAskFor() {
    let jpeg = self.message { $0.setFieldUInt32(type: .serverBannerType, val: "JPEG".fourCharCode()) }
    #expect(HotlineServerBanner(from: jpeg) == .download)

    let gif = self.message { $0.setFieldUInt16(type: .serverBannerType, val: 4) }
    #expect(HotlineServerBanner(from: gif) == .download)
  }

  @Test func sentWithTheAgreement() {
    let bytes = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
    let agreement = self.message(.showAgreement) {
      $0.setFieldString(type: .data, val: "Be nice.")
      $0.setFieldUInt16(type: .serverBannerType, val: 4)
      $0.setFieldData(type: .serverBanner, val: bytes)
    }
    #expect(HotlineServerBanner(from: agreement) == .data(bytes))
  }

  @Test func saysNothingUseful() {
    // An agreement without a banner.
    #expect(HotlineServerBanner(from: self.message(.showAgreement) { $0.setFieldString(type: .data, val: "Be nice.") }) == nil)
    // A web address that isn't one.
    let noAddress = self.message { $0.setFieldUInt16(type: .serverBannerType, val: 1); $0.setFieldString(type: .serverBannerURL, val: "banner.gif") }
    #expect(HotlineServerBanner(from: noAddress) == nil)
  }
}
