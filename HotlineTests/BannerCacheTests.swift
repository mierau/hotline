// BannerCacheTests

import Testing
import Foundation
@testable import Hotline

struct BannerCacheTests {

  /// A cache in a scratch folder of its own.
  private func makeCache() -> (cache: BannerCache, directory: URL) {
    let directory = URL.temporaryDirectory.appending(path: "BannerCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    return (BannerCache(directory: directory), directory)
  }

  /// Bytes that start like a PNG, different for each seed.
  private func banner(_ seed: Int, size: Int = 64) -> Data {
    var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    data.append(contentsOf: (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ seed) })
    return data
  }

  @Test func storedBannerIsFoundAgain() async throws {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(await cache.banner(forAddress: "example.com", port: 5500) == nil)
    let stored = try #require(await cache.store(self.banner(1), forAddress: "example.com", port: 5500))
    #expect(stored.pathExtension == "png")
    #expect(try Data(contentsOf: stored) == self.banner(1))
    #expect(await cache.banner(forAddress: "example.com", port: 5500) == stored)
  }

  @Test func unchangedBannerKeepsItsURL() async {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = await cache.store(self.banner(1), forAddress: "example.com", port: 5500)
    let second = await cache.store(self.banner(1), forAddress: "example.com", port: 5500)
    #expect(first != nil)
    #expect(first == second)
  }

  @Test func changedBannerReplacesTheOldOne() async throws {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    let old = try #require(await cache.store(self.banner(1), forAddress: "example.com", port: 5500))
    let new = try #require(await cache.store(self.banner(2), forAddress: "example.com", port: 5500))
    #expect(new != old)
    #expect(!FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
    #expect(await cache.banner(forAddress: "example.com", port: 5500) == new)
  }

  @Test func serversAreTheirAddressAndPort() async {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    let stored = await cache.store(self.banner(1), forAddress: "Example.com", port: 5500)
    #expect(await cache.banner(forAddress: " example.COM", port: 5500) == stored)
    #expect(await cache.banner(forAddress: "example.com", port: 5600) == nil)
  }

  @Test func removedBannerIsGone() async {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    await cache.store(self.banner(1), forAddress: "example.com", port: 5500)
    await cache.removeBanner(forAddress: "example.com", port: 5500)
    #expect(await cache.banner(forAddress: "example.com", port: 5500) == nil)
  }

  @Test func emptyAndHugeBannersArentKept() async {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(await cache.store(Data(), forAddress: "example.com", port: 5500) == nil)
    #expect(await cache.store(self.banner(1, size: 5 * 1024 * 1024), forAddress: "example.com", port: 5500) == nil)
  }

  @Test func leastRecentlyUsedServersGoFirst() async {
    let (cache, directory) = self.makeCache()
    defer { try? FileManager.default.removeItem(at: directory) }

    for index in 0..<100 {
      await cache.store(self.banner(index), forAddress: "server\(index).com", port: 5500)
    }
    // Looking a banner up counts as using it.
    _ = await cache.banner(forAddress: "server0.com", port: 5500)
    for index in 100..<105 {
      await cache.store(self.banner(index), forAddress: "server\(index).com", port: 5500)
    }

    #expect(await cache.banner(forAddress: "server0.com", port: 5500) != nil)
    #expect(await cache.banner(forAddress: "server1.com", port: 5500) == nil)
    #expect(await cache.banner(forAddress: "server104.com", port: 5500) != nil)
  }
}
