import SwiftUI

enum NewsCategoryType {
  case bundle
  case category
}

@Observable class NewsCategory: Identifiable, Hashable {
  let id: UUID = UUID()
  
  let name: String
  let count: UInt16
  let type: NewsCategoryType
  
  init(hotlineNewsCategory: HotlineNewsCategory) {
    self.name = hotlineNewsCategory.name
    self.count = hotlineNewsCategory.count
    
    if hotlineNewsCategory.type == 2 {
      self.type = .bundle
    }
    else {
      self.type = .category
    }
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  static func == (lhs: NewsCategory, rhs: NewsCategory) -> Bool {
    return lhs.id == rhs.id
  }
}
