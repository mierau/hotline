import Foundation

struct NewsArticle: Identifiable, Codable {
  var id: UUID = UUID()
  var parentID: UInt32?
  var path: [String]
  var title: String
  var body: String
}

extension NewsArticle: Equatable {
  static func == (lhs: NewsArticle, rhs: NewsArticle) -> Bool {
    return lhs.id == rhs.id && lhs.parentID == rhs.parentID
  }
}

extension NewsArticle: Hashable {
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
