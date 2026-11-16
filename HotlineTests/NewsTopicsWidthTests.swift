// NewsTopicsWidthTests

import Testing
import CoreGraphics
@testable import Hotline

/// How wide the news's topics are drawn beside the articles: as wide as they were left, in whole
/// points, but never narrower than shows their names, nor so wide the articles have less than their
/// share of the width, which comes first.
struct NewsTopicsWidthTests {
  @Test func asWideAsTheyWereLeft() {
    #expect(NewsTopicsWidth.clamped(200, in: 520) == 200)
    #expect(NewsTopicsWidth.clamped(200, in: 1400) == 200)
    #expect(NewsTopicsWidth.clamped(312.4, in: 1000) == 312)
  }

  @Test func neverNarrowerThanTheirNames() {
    #expect(NewsTopicsWidth.clamped(90, in: 800) == NewsTopicsWidth.narrowest)
  }

  @Test func theArticlesKeepTheirShare() {
    // 60% of 800.
    #expect(NewsTopicsWidth.clamped(700, in: 800) == 480)
  }

  @Test func inANarrowWindowTheArticlesComeFirst() {
    // 60% of 250 is narrower than the topics would otherwise be.
    #expect(NewsTopicsWidth.clamped(200, in: 250) == 150)
    #expect(NewsTopicsWidth.clamped(200, in: 0) == 0)
  }
}
