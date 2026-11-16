// FilesColumnResizeTests

import Testing
import CoreGraphics
@testable import Hotline

/// Making the files' columns wider or narrower by dragging the line after one: that column alone, or
/// with ⌥, all of them, with the line kept under the pointer as it's dragged.
struct FilesColumnResizeTests {
  @Test func oneColumnAlone() {
    let resized = FilesColumnView.resized(1, by: 40, all: false, from: (widths: [0: 300], standard: 230), rounded: true)
    #expect(resized.widths == [0: 300, 1: 270])
    #expect(resized.standard == 230)
  }

  @Test func allOfThemKeepTheLineUnderThePointer() {
    // The line after the second column, dragged 40 points: as far as the two up to it make up
    // between them, which all of them are as wide as, as the first was wider than the rest.
    let resized = FilesColumnView.resized(1, by: 40, all: true, from: (widths: [0: 300], standard: 230), rounded: false)
    #expect(resized.widths.isEmpty)
    let line: CGFloat = 300 + 230 + 40
    #expect(resized.standard * 2 == line)
    // The line after the fourth, dragged back 20 points.
    let back = FilesColumnView.resized(3, by: -20, all: true, from: (widths: [:], standard: 230), rounded: false)
    let fourth: CGFloat = 230 * 4 - 20
    #expect(back.standard * 4 == fourth)
  }

  @Test func asItWasWhenTheDragBegan() {
    // With ⌥ let go partway, the rest go back to how wide they were, and the one dragged is as wide
    // as it's been dragged.
    let start = (widths: [Int: CGFloat](), standard: CGFloat(230))
    _ = FilesColumnView.resized(2, by: 30, all: true, from: start, rounded: false)
    let letGo = FilesColumnView.resized(2, by: 30, all: false, from: start, rounded: true)
    #expect(letGo.widths == [2: 260])
    #expect(letGo.standard == 230)
  }

  @Test func noNarrowerOrWiderThanTheyCanBe() {
    let narrow = FilesColumnView.resized(0, by: -500, all: false, from: (widths: [:], standard: 230), rounded: true)
    #expect(narrow.widths[0] == FilesColumnView.narrowest)
    let wide = FilesColumnView.resized(0, by: 900, all: true, from: (widths: [:], standard: 230), rounded: true)
    #expect(wide.standard == FilesColumnView.widest)
  }
}
