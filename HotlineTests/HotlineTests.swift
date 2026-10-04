// HotlineTests

import Testing
@testable import Hotline

struct HotlineTests {
}

struct ServerAddressTests {
  private func parsed(_ address: String) -> String {
    let server = Server.parseServerAddress(address)
    return "\(server.host) \(server.port) \(server.login ?? "-") \(server.password ?? "-")"
  }

  @Test func addressesAndPorts() {
    #expect(self.parsed("Hotline.Example.com") == "hotline.example.com 5500 - -")
    #expect(self.parsed(" hotline.example.com:5600 ") == "hotline.example.com 5600 - -")
    #expect(self.parsed("192.168.1.5:5500") == "192.168.1.5 5500 - -")
  }

  @Test func loginsAndPasswordsTypedWithTheAddress() {
    #expect(self.parsed("mars@hotline.example.com") == "hotline.example.com 5500 mars -")
    #expect(self.parsed("mars:secret@hotline.example.com:5600") == "hotline.example.com 5600 mars secret")
    #expect(self.parsed("mars:p@ss@hotline.example.com") == "hotline.example.com 5500 mars p@ss")
    #expect(self.parsed("@hotline.example.com") == "hotline.example.com 5500 - -")
  }

  @Test func links() {
    #expect(self.parsed("hotline://mars:secret@hotline.example.com:5501/files/Maps") == "hotline.example.com 5501 mars secret")
  }

  @Test func ipv6() {
    #expect(self.parsed("[fe80::1]:5600") == "fe80::1 5600 - -")
    #expect(self.parsed("fe80::1") == "fe80::1 5500 - -")
    #expect(self.parsed("mars:secret@[fe80::1]:5600") == "fe80::1 5600 mars secret")
  }

  @Test func addressAndPortLeavesTheLoginOut() {
    let (host, port) = Server.parseServerAddressAndPort("mars:secret@hotline.example.com:5600")
    #expect(host == "hotline.example.com" && port == 5600)
  }
}
