// URLHighlightingTests

import Testing
import Foundation
@testable import Hotline

struct URLHighlightingTests {

  // MARK: - Helper: extract matched URLs from relaxedLink

  private func matchedURLs(in text: String) -> [String] {
    text.ranges(of: RegularExpressions.relaxedLink).map { String(text[$0]) }
  }

  // MARK: - Basic URL Detection

  @Test func simpleHTTPSURL() {
    let urls = matchedURLs(in: "Visit https://example.com today")
    #expect(urls == ["https://example.com"])
  }

  @Test func simpleHTTPURL() {
    let urls = matchedURLs(in: "Visit http://example.com today")
    #expect(urls == ["http://example.com"])
  }

  @Test func hotlineSchemeURL() {
    let urls = matchedURLs(in: "Connect to hotline://server.example.com")
    #expect(urls == ["hotline://server.example.com"])
  }

  @Test func schemelessURL() {
    let urls = matchedURLs(in: "Visit example.com for more")
    #expect(urls == ["example.com"])
  }

  @Test func urlWithPath() {
    let urls = matchedURLs(in: "See https://example.com/path/to/page for info")
    #expect(urls == ["https://example.com/path/to/page"])
  }

  @Test func urlWithQueryString() {
    let urls = matchedURLs(in: "Go to https://example.com/search?q=hello&page=2 now")
    #expect(urls == ["https://example.com/search?q=hello&page=2"])
  }

  @Test func urlWithPort() {
    let urls = matchedURLs(in: "Connect to server.example.com:5500")
    #expect(urls == ["server.example.com:5500"])
  }

  @Test func hotlineURLWithPort() {
    let urls = matchedURLs(in: "Try hotline://myserver.com:5500")
    #expect(urls == ["hotline://myserver.com:5500"])
  }

  @Test func urlWithFragment() {
    let urls = matchedURLs(in: "See https://example.com/page#section for details")
    #expect(urls == ["https://example.com/page#section"])
  }

  @Test func urlWithTildeInPath() {
    let urls = matchedURLs(in: "Visit https://example.com/~user/page")
    #expect(urls == ["https://example.com/~user/page"])
  }

  @Test func urlWithPlusInQuery() {
    let urls = matchedURLs(in: "Search https://example.com/search?q=hello+world for results")
    #expect(urls == ["https://example.com/search?q=hello+world"])
  }

  @Test func urlWithAtSignInPath() {
    let urls = matchedURLs(in: "Check out https://www.youtube.com/@dmug for videos")
    #expect(urls == ["https://www.youtube.com/@dmug"])
  }

  // MARK: - Balanced Parentheses

  @Test func urlInParenthesesNotIncluded() {
    let urls = matchedURLs(in: "Check out (tracked.mainecyber.com)")
    #expect(urls == ["tracked.mainecyber.com"])
  }

  @Test func trailingParenNotIncluded() {
    let urls = matchedURLs(in: "tracked.mainecyber.com)")
    #expect(urls == ["tracked.mainecyber.com"])
  }

  @Test func wikipediaStyleBalancedParens() {
    let urls = matchedURLs(in: "See https://en.wikipedia.org/wiki/Hotline_(protocol) for info")
    #expect(urls == ["https://en.wikipedia.org/wiki/Hotline_(protocol)"])
  }

  @Test func urlInBracketsNotIncluded() {
    let urls = matchedURLs(in: "Link: [example.com]")
    #expect(urls == ["example.com"])
  }

  // MARK: - URL as Query Parameter

  @Test func urlAsQueryParameter() {
    let urls = matchedURLs(in: "Go to https://example.com/redirect?url=https://other.com/page")
    #expect(urls == ["https://example.com/redirect?url=https://other.com/page"])
  }

  // MARK: - TLD Handling

  @Test func schemelessKnownTLD() {
    let urls = matchedURLs(in: "Visit example.org for more")
    #expect(urls == ["example.org"])
  }

  @Test func schemelessUnknownTLDNotMatched() {
    // Without a scheme, unknown TLDs should not match to avoid false positives
    let urls = matchedURLs(in: "Open file.txt now")
    #expect(urls.isEmpty)
  }

  @Test func schemeWithAnyTLD() {
    // With an explicit scheme, any TLD should be accepted
    let urls = matchedURLs(in: "Visit https://example.pizza/menu")
    #expect(urls == ["https://example.pizza/menu"])
  }

  @Test func schemeWithUncommonTLD() {
    let urls = matchedURLs(in: "See https://my.restaurant for the menu")
    #expect(urls == ["https://my.restaurant"])
  }

  @Test func variousKnownTLDs() {
    #expect(matchedURLs(in: "test.com") == ["test.com"])
    #expect(matchedURLs(in: "test.net") == ["test.net"])
    #expect(matchedURLs(in: "test.org") == ["test.org"])
    #expect(matchedURLs(in: "test.io") == ["test.io"])
    #expect(matchedURLs(in: "test.dev") == ["test.dev"])
    #expect(matchedURLs(in: "test.ai") == ["test.ai"])
    #expect(matchedURLs(in: "test.app") == ["test.app"])
    #expect(matchedURLs(in: "test.gg") == ["test.gg"])
    #expect(matchedURLs(in: "test.xyz") == ["test.xyz"])
  }

  // MARK: - Email Address Exclusion
  //
  // The raw regex does match domain portions of emails (e.g. mac.com from bobkiwi@mac.com)
  // because @ creates a word boundary. The conversion functions (convertingLinksToMarkdown,
  // convertToAttributedStringWithLinks) filter these out by detecting email overlap.
  // These raw-regex tests verify what the regex produces; the conversion function tests
  // (markdownConversion*, realWorld*) verify the correct end-to-end behavior.

  @Test func emailDomainMatchedByRawRegex() {
    // Raw regex matches the domain portion — conversion functions will filter this
    let urls = matchedURLs(in: "Email me at bobkiwi@mac.com for info")
    #expect(urls == ["mac.com"])
  }

  @Test func emailAndURLInSameText() {
    // Raw regex matches both the email domain and the standalone URL
    let urls = matchedURLs(in: "Email bob@example.com or visit example.org")
    #expect(urls == ["example.com", "example.org"])
  }

  // MARK: - False Positives

  @Test func ellipsisNotMatchedAsURL() {
    // "is...not" should NOT be detected as a URL (was matching is..no as domain.tld)
    let urls = matchedURLs(in: "my placeholder art is...not good :|")
    #expect(urls.isEmpty)
  }

  @Test func consecutiveDotsNotMatchedAsURL() {
    #expect(matchedURLs(in: "wait..what").isEmpty)
    #expect(matchedURLs(in: "no...way").isEmpty)
    #expect(matchedURLs(in: "test....com").isEmpty)
  }

  // MARK: - Trailing Punctuation

  @Test func trailingPeriodNotIncluded() {
    let urls = matchedURLs(in: "Visit example.com.")
    #expect(urls == ["example.com"])
  }

  // MARK: - Multiple URLs in Text

  @Test func multipleURLs() {
    let urls = matchedURLs(in: "Visit example.com and https://other.org/page for info")
    #expect(urls == ["example.com", "https://other.org/page"])
  }

  // MARK: - Case Insensitivity

  @Test func caseInsensitiveScheme() {
    let urls = matchedURLs(in: "Go to HTTPS://EXAMPLE.COM/PATH")
    #expect(urls == ["HTTPS://EXAMPLE.COM/PATH"])
  }

  @Test func caseInsensitiveTLD() {
    let urls = matchedURLs(in: "Visit Example.Com today")
    #expect(urls == ["Example.Com"])
  }

  // MARK: - Subdomain Handling

  @Test func subdomainURL() {
    let urls = matchedURLs(in: "Visit www.example.com for info")
    #expect(urls == ["www.example.com"])
  }

  @Test func deepSubdomainURL() {
    let urls = matchedURLs(in: "See sub.domain.example.com/page")
    #expect(urls == ["sub.domain.example.com/page"])
  }

  // MARK: - convertingLinksToMarkdown

  @Test func markdownConversionAddsScheme() {
    let result = "Visit example.com for info".convertingLinksToMarkdown()
    #expect(result == "Visit [example.com](https://example.com) for info")
  }

  @Test func markdownConversionPreservesScheme() {
    let result = "Visit https://example.com for info".convertingLinksToMarkdown()
    #expect(result == "Visit [https://example.com](https://example.com) for info")
  }

  @Test func markdownConversionPreservesHotlineScheme() {
    let result = "Connect to hotline://server.com:5500".convertingLinksToMarkdown()
    #expect(result == "Connect to [hotline://server.com:5500](hotline://server.com:5500)")
  }

  @Test func markdownConversionHandlesEmailAddress() {
    let result = "Email bob@example.com for info".convertingLinksToMarkdown()
    #expect(result == "Email [bob@example.com](mailto:bob@example.com) for info")
  }

  @Test func markdownConversionEmailAndURL() {
    let result = "Email bob@example.com or visit example.org".convertingLinksToMarkdown()
    #expect(result == "Email [bob@example.com](mailto:bob@example.com) or visit [example.org](https://example.org)")
  }

  @Test func markdownConversionEmailDomainNotLinkedAsURL() {
    let result = "Contact bobkiwi@mac.com for help".convertingLinksToMarkdown()
    // mac.com should NOT be separately linked as a URL
    #expect(result == "Contact [bobkiwi@mac.com](mailto:bobkiwi@mac.com) for help")
  }

  @Test func markdownConversionParensNotIncluded() {
    let result = "Check out (example.com) for more".convertingLinksToMarkdown()
    #expect(result == "Check out ([example.com](https://example.com)) for more")
  }

  @Test func markdownConversionNoLinksUnchanged() {
    let result = "Just some plain text here".convertingLinksToMarkdown()
    #expect(result == "Just some plain text here")
  }

  // MARK: - Email Address Detection

  @Test func emailWholeMatch() {
    #expect("bob@example.com".isEmailAddress())
    #expect("user.name@domain.org".isEmailAddress())
    #expect("test-user@sub.domain.com".isEmailAddress())
  }

  @Test func nonEmailDoesNotMatch() {
    #expect(!"example.com".isEmailAddress())
    #expect(!"not an email".isEmailAddress())
    #expect(!"@example.com".isEmailAddress())
  }

  // MARK: - Real-world Chat Messages

  @Test func realWorldChatWithEmail() {
    // Raw regex matches the email domain; conversion functions filter it out.
    // The trailing period after mac.com. should NOT be included.
    let text = "I'm almost always away from keyboard (AFK), but feel free to email me at bobkiwi@mac.com. If you are looking for classic Mac OS Software, check out the Macintosh Garden website."
    let urls = matchedURLs(in: text)
    #expect(urls == ["mac.com"])
  }

  @Test func realWorldChatWithEmailMarkdown() {
    // End-to-end: conversion functions correctly handle the email and don't link mac.com separately
    let text = "I'm almost always away from keyboard (AFK), but feel free to email me at bobkiwi@mac.com. If you are looking for classic Mac OS Software, check out the Macintosh Garden website."
    let result = text.convertingLinksToMarkdown()
    #expect(result.contains("[bobkiwi@mac.com](mailto:bobkiwi@mac.com)"))
    #expect(!result.contains("[mac.com]"))
  }

  @Test func realWorldChatWithEmailAndMarkdown() {
    let text = "I'm almost always AFK, but email me at bobkiwi@mac.com. Check out macintoshgarden.org for software."
    let result = text.convertingLinksToMarkdown()
    #expect(result.contains("[bobkiwi@mac.com](mailto:bobkiwi@mac.com)"))
    #expect(result.contains("[macintoshgarden.org](https://macintoshgarden.org)"))
    // mac.com should NOT appear as a separate link
    #expect(!result.contains("[mac.com]"))
  }

  @Test func realWorldURLInParens() {
    let text = "The tracker is back up (tracked.mainecyber.com)"
    let urls = matchedURLs(in: text)
    #expect(urls == ["tracked.mainecyber.com"])
  }

  // MARK: - Detected Links

  @Test func serverAndPortLinksToHotline() {
    let result = "server is hotline.example.org:5500".convertingLinksToMarkdown()
    #expect(result == "server is [hotline.example.org:5500](hotline://hotline.example.org:5500)")
  }

  @Test func ipAddressAndPortLinksToHotline() {
    let result = "connect to 192.168.1.5:5500 now".convertingLinksToMarkdown()
    #expect(result == "connect to [192.168.1.5:5500](hotline://192.168.1.5:5500) now")
  }

  @Test func bareIPAddressIsNotALink() {
    #expect("version 10.0.0.2 is out".convertingLinksToMarkdown() == "version 10.0.0.2 is out")
  }

  @Test func fileNamesAreNotLinks() {
    #expect("the file is notes.txt and readme.md".convertingLinksToMarkdown() == "the file is notes.txt and readme.md")
  }

  @Test func otherSchemesAreNotLinks() {
    #expect("open file:///etc/hosts".convertingLinksToMarkdown() == "open file:///etc/hosts")
  }

  @Test func markdownLinksAreLeftAlone() {
    #expect("read [the plan](https://example.com/plan) first".convertingLinksToMarkdown() == "read [the plan](https://example.com/plan) first")
  }

  @Test func linkTextIsEscaped() {
    // So *b* in a link isn't read as italics.
    #expect("see example.com/a*b* now".convertingLinksToMarkdown() == "see [example.com/a\\*b\\*](https://example.com/a*b*) now")
  }

  @Test func linkInParenthesesKeepsItsOwn() {
    let links = "(https://en.wikipedia.org/wiki/Hotline_(software)) is it".detectedLinks()
    #expect(links.map(\.url.absoluteString) == ["https://en.wikipedia.org/wiki/Hotline_(software)"])
  }
}
