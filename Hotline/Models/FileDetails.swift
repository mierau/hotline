import UniformTypeIdentifiers

struct FileDetails:Identifiable {
  let id = UUID()
  var name: String
  var path: [String]
  var size: Int
  var comment: String
  var type: String
  var creator: String
  var created: Date
  var modified: Date
}
