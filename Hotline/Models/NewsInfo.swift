import SwiftUI

enum NewsInfoType {
  case bundle
  case category
  case article
}

@Observable class NewsInfo: Identifiable, Hashable {
  let id: UUID = UUID()
  
  var name: String
  var count: UInt
  let type: NewsInfoType
  
  var categoryID: UUID?
  var articleID: UInt?
  var parentID: UInt?
  
  var path: [String]
  var expanded: Bool = false
  var children: [NewsInfo] = []
  
  var articleFlavors: [String]?
  var articleUsername: String?
  var articleDate: Date?
  var read: Bool = false
  
  var expandable: Bool {
    self.type == .bundle || self.type == .category || self.children.count > 0
  }
  
  var lookupPath: String? {
    switch self.type {
    case .bundle, .category:
      return "/\(self.path.joined(separator: "/"))"
    case .article:
      guard let aid = self.articleID else {
        return nil
      }
//      if let pid = self.parentID, pid != 0 {
//        return "/\(self.path.joined(separator: "/"))/\(pid)/\(aid)"
//      }
      return "/\(self.path.joined(separator: "/"))/\(aid)"
    }
  }
  
  var parentArticleLookupPath: String? {
    switch self.type {
    case .bundle, .category:
//      if self.path.count <= 1 {
//        return "/"
//      }
//      let parentPath = self.path[0..<self.path.count-1]
//      return "/\(parentPath.joined(separator: "/"))"
      return nil
    case .article:
      guard let pid = self.parentID, pid != 0 else {
        return nil
      }
      return "/\(self.path.joined(separator: "/"))/\(pid)"
    }
  }
  
  init(hotlineNewsCategory: HotlineNewsCategory) {
    self.categoryID = hotlineNewsCategory.id
    self.articleID = nil
    self.parentID = nil
    self.name = hotlineNewsCategory.name
    self.count = UInt(hotlineNewsCategory.count)
    self.path = hotlineNewsCategory.path
    
    if hotlineNewsCategory.type == 2 {
      self.type = .bundle
    }
    else {
      self.type = .category
    }
  }
  
  init(hotlineNewsArticle: HotlineNewsArticle) {
    self.articleID = UInt(hotlineNewsArticle.id)
    self.parentID = hotlineNewsArticle.parentID == 0 ? nil : UInt(hotlineNewsArticle.parentID)
    print(hotlineNewsArticle.parentID)
    self.categoryID = nil
    self.name = hotlineNewsArticle.title
    self.count = 0
//    self.count = UInt(hotlineNewsArticle.count)
    self.path = hotlineNewsArticle.path
    self.type = .article
    
    self.articleFlavors = hotlineNewsArticle.flavors.map { $0.0 }
    self.articleUsername = hotlineNewsArticle.username
    self.articleDate = hotlineNewsArticle.date
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  static func == (lhs: NewsInfo, rhs: NewsInfo) -> Bool {
    return lhs.id == rhs.id
  }
}
