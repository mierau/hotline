// PacketBytesTests

import Testing
import Foundation
@testable import Hotline

/// The exact bytes Hotline writes and reads for transactions, fields, users, file headers and
/// bookmark files, so the byte helpers underneath can change without changing what goes over the
/// wire or to disk.
struct PacketBytesTests {

  // MARK: - Writing

  @Test func transactionWithFields() {
    var transaction = HotlineTransaction(id: 0x01020304, type: .getUserNameList)
    transaction.setFieldUInt16(type: .userIconID, val: 0x0A0B)
    transaction.setFieldUInt32(type: .fileSize, val: 0x11223344)
    transaction.setFieldString(type: .userName, val: "Hi")

    #expect(transaction.encoded() == [
      0x00, 0x00, 0x01, 0x2C,                         // flags, reply, type 300
      0x01, 0x02, 0x03, 0x04,                         // id
      0x00, 0x00, 0x00, 0x00,                         // error code
      0x00, 0x00, 0x00, 0x16,                         // total size
      0x00, 0x00, 0x00, 0x16,                         // data size
      0x00, 0x03,                                     // field count
      0x00, 0x68, 0x00, 0x02, 0x0A, 0x0B,             // icon ID
      0x00, 0xCF, 0x00, 0x04, 0x11, 0x22, 0x33, 0x44, // file size
      0x00, 0x66, 0x00, 0x02, 0x48, 0x69,             // user name "Hi"
    ])
  }

  @Test func transactionWithoutFields() {
    let transaction = HotlineTransaction(id: 7, type: .getUserNameList)

    #expect(transaction.encoded() == [
      0x00, 0x00, 0x01, 0x2C,
      0x00, 0x00, 0x00, 0x07,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x02,
      0x00, 0x00, 0x00, 0x02,
      0x00, 0x00,
    ])
  }

  @Test func integerFields() {
    #expect(HotlineTransactionField(type: .userID, val: UInt16(0x0102)).data == [0x01, 0x02])
    #expect(HotlineTransactionField(type: .fileSize, val: UInt32(0x01020304)).data == [0x01, 0x02, 0x03, 0x04])

    let wide = HotlineTransactionField(type: .fileSize, val: UInt64(0x0102030405060708))
    #expect(wide.data == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
    #expect(wide.getUInt64() == 0x0102030405060708)
    #expect(wide.getInteger() == 0x0102030405060708)
  }

  @Test func pathField() {
    let field = HotlineTransactionField(type: .filePath, pathComponents: ["ab", "c"])

    #expect(field.dataSize == 11)
    #expect(field.data == [
      0x00, 0x02,                         // component count
      0x00, 0x00, 0x02, 0x61, 0x62,       // "ab"
      0x00, 0x00, 0x01, 0x63,             // "c"
    ])
  }

  @Test func user() {
    let user = HotlineUser(id: 0x0102, iconID: 0x0304, status: 0x0005, name: "Bo")

    #expect(user.encoded() == [0x01, 0x02, 0x03, 0x04, 0x00, 0x05, 0x00, 0x02, 0x42, 0x6F])
  }

  @Test func bookmarkFile() throws {
    let bookmark = Bookmark(type: .server, name: "Test", address: "example.com", port: 5501, login: "guest", password: "pw")
    let data = try #require(bookmark.bookmarkFileData())

    #expect(data.count == 4 + 2 + 128 + 2 + 32 + 2 + 32 + 2 + 256)
    #expect(Array(data.prefix(6)) == [0x48, 0x54, 0x73, 0x63, 0x00, 0x01]) // "HTsc", version 1
    #expect(Array(data[134..<141]) == [0x00, 0x05, 0x67, 0x75, 0x65, 0x73, 0x74]) // "guest"
    #expect(Array(data[168..<172]) == [0x00, 0x02, 0x70, 0x77]) // "pw"
    #expect(Array(data[202..<204]) == [0x00, 0x10]) // "example.com:5501"

    let read = try #require(Bookmark(fileData: data))
    #expect(read.address == "example.com")
    #expect(read.port == 5501)
    #expect(read.login == "guest")
    #expect(read.password == "pw")
  }

  // MARK: - Reading

  @Test func transactionHeader() throws {
    let transaction = try #require(HotlineTransaction(from: [
      0x01, 0x01, 0x00, 0x00,
      0x0A, 0x0B, 0x0C, 0x0D,
      0x00, 0x00, 0x00, 0x05,
      0x00, 0x00, 0x01, 0x00,
      0x00, 0x00, 0x00, 0xF0,
    ]))

    #expect(transaction.flags == 1)
    #expect(transaction.isReply == 1)
    #expect(transaction.id == 0x0A0B0C0D)
    #expect(transaction.errorCode == 5)
    #expect(transaction.totalSize == 256)
    #expect(transaction.dataSize == 240)

    // A header cut short isn't a transaction.
    #expect(HotlineTransaction(from: [0x00, 0x00, 0x00]) == nil)
  }

  @Test func userRoundTrip() {
    let user = HotlineUser(from: HotlineUser(id: 9, iconID: 128, status: 3, name: "Ann").encoded())

    #expect(user.id == 9)
    #expect(user.iconID == 128)
    #expect(user.status == 3)
    #expect(user.name == "Ann")
  }

  @Test func accountFields() {
    let account = HotlineAccount(from: [
      0x00, 0x02,                                     // field count
      0xFF, 0xFF, 0x00, 0x01, 0x00,                   // a field type Hotline doesn't know
      0x00, 0x66, 0x00, 0x03, 0x41, 0x6E, 0x6E,       // user name "Ann"
    ])

    #expect(account.name == "Ann")
  }

  @Test func fileHeaders() throws {
    var fileHeader = Data([0x46, 0x49, 0x4C, 0x50, 0x00, 0x01])
    fileHeader.append(Data(repeating: 0, count: 16))
    fileHeader.append(contentsOf: [0x00, 0x02])
    let file = try #require(HotlineFileHeader(from: fileHeader))
    #expect(file.format == 0x46494C50) // "FILP"
    #expect(file.version == 1)
    #expect(file.forkCount == 2)

    let forkHeader = Data([0x49, 0x4E, 0x46, 0x4F, 0, 0, 0, 0, 0, 0, 0, 0, 0x00, 0x00, 0x01, 0x00])
    let fork = try #require(HotlineFileForkHeader(from: forkHeader))
    #expect(fork.forkType == 0x494E464F) // "INFO"
    #expect(fork.compressionType == 0)
    #expect(fork.dataSize == 256)

    #expect(HotlineFileForkHeader(from: forkHeader.prefix(8)) == nil)
  }

  @Test func datesAndPascalStrings() {
    // 2000, 0 ms, a day of seconds into the year.
    let date: [UInt8] = [0x07, 0xD0, 0x00, 0x00, 0x00, 0x01, 0x51, 0x80]
    #expect(date.readDate(at: 0) == Date(timeIntervalSince1970: 946_771_200))
    #expect(Data([0xFF] + date).readDate(at: 1) == Date(timeIntervalSince1970: 946_771_200))
    #expect(date.readDate(at: 1) == nil)

    let short: [UInt8] = [0x03, 0x41, 0x62, 0x63, 0x00]
    for (text, length) in [short.readPString(at: 0), Data(short).readPString(at: 0)] {
      #expect(text == "Abc")
      #expect(length == 4)
    }

    let long: [UInt8] = [0x00, 0x02, 0x48, 0x69]
    for (text, length) in [long.readLongPString(at: 0), Data(long).readLongPString(at: 0)] {
      #expect(text == "Hi")
      #expect(length == 2)
    }
  }
}
