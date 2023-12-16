import SwiftUI

enum NewsInfoType {
  case bundle
  case category
  case article
}

@Observable class NewsInfo: Identifiable, Hashable {
  let id: UUID = UUID()
  
  let name: String
  let count: UInt
  let type: NewsInfoType
  
  let categoryID: UUID?
  let articleID: UInt?
  
  let path: [String]
  var children: [NewsInfo] = []
  
  var articleFlavors: [String]?
  
  init(hotlineNewsCategory: HotlineNewsCategory) {
    self.categoryID = hotlineNewsCategory.id
    self.articleID = nil
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
    self.categoryID = nil
    self.name = hotlineNewsArticle.title
    self.count = 0
//    self.count = UInt(hotlineNewsArticle.count)
    self.path = hotlineNewsArticle.path
    self.type = .article
    
    self.articleFlavors = hotlineNewsArticle.flavors.map { $0.0 }
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  static func == (lhs: NewsInfo, rhs: NewsInfo) -> Bool {
    return lhs.id == rhs.id
  }
}
