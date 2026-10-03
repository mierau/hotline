//
//  QuickTime.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 04.02.2024.
//

/// Utility code to handle QuickTime related data.
/// This basically implements two basic functionalities:
/// * Handling of QuickTime opcodes in QuickDraw images.
/// * Handling of QuickTime image files `QTIF`

/// https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/QuickTime.framework/Versions/A/Headers/ImageCompression.h
/// https://github.com/TheDiamondProject/Graphite/blob/aa6636a1fe09eb2439e4972c4501724b3282ac7c/libGraphite/quicktime/planar.cpp



/// DV Format
///  /// Spec if SMPTE314M
/// http://www.adamwilt.com/DV-FAQ-tech.html

/// Codecs handled by the backend.
/*
 (
 "public.jpeg",
 "public.png",
 "com.compuserve.gif",
 "com.canon.tif-raw-image",
 "com.adobe.raw-image",
 "com.dxo.raw-image",
 "com.canon.cr2-raw-image",
 "com.canon.cr3-raw-image",
 "com.leafamerica.raw-image",
 "com.hasselblad.fff-raw-image",
 "com.hasselblad.3fr-raw-image",
 "com.nikon.raw-image",
 "com.nikon.nrw-raw-image",
 "com.pentax.raw-image",
 "com.samsung.raw-image",
 "com.sony.raw-image",
 "com.sony.sr2-raw-image",
 "com.sony.arw-raw-image",
 "com.epson.raw-image",
 "com.kodak.raw-image",
 "public.tiff",
 "public.jpeg-2000",
 "com.apple.atx",
 "org.khronos.astc",
 "org.khronos.ktx",
 "public.avci",
 "public.heic",
 "public.heics",
 "public.heif",
 "com.canon.crw-raw-image",
 "com.fuji.raw-image",
 "com.panasonic.raw-image",
 "com.panasonic.rw2-raw-image",
 "com.leica.raw-image",
 "com.leica.rwl-raw-image",
 "com.konicaminolta.raw-image",
 "com.olympus.sr-raw-image",
 "com.olympus.or-raw-image",
 "com.olympus.raw-image",
 "com.phaseone.raw-image",
 "com.microsoft.ico",
 "com.microsoft.bmp",
 "com.apple.icns",
 "com.adobe.photoshop-image",
 "com.microsoft.cur",
 "com.truevision.tga-image",
 "com.ilm.openexr-image",
 "org.webmproject.webp",
 "com.sgi.sgi-image",
 "public.radiance",
 "public.pbm",
 "public.mpo-image",
 "public.pvr",
 "com.microsoft.dds",
 "com.apple.pict"
 )
 (
 "public.jpeg",
 "public.png",
 "com.compuserve.gif",
 "public.tiff",
 "public.jpeg-2000",
 "com.apple.atx",
 "org.khronos.ktx",
 "org.khronos.astc",
 "com.microsoft.dds",
 "public.heic",
 "public.heics",
 "com.microsoft.ico",
 "com.microsoft.bmp",
 "com.apple.icns",
 "com.adobe.photoshop-image",
 "com.adobe.pdf",
 "com.truevision.tga-image",
 "com.ilm.openexr-image",
 "public.pbm",
 "public.pvr"
 )
 
 
 */


import os
import Foundation

// MARK: - Errors
enum QuickTimeError: LocalizedError {
  case missingQuickTimePayload(quicktimeOpcode: QuickTimeOpcode);
  case missingQuickTimeData(quicktimeImage: QuickTimeIdsc);
  case corruptQuickTimeAtomLength(length: Int);
  case missingQuickTimePart(code: MacTypeCode);
  case missingClut(quicktimeImage: QuickTimeIdsc);
}

// MARK: - Representation of a converted image
struct ConvertedImageMeta : PixMapMetadata {
  let rowBytes: Int;
  let cmpSize: Int;
  let pixelSize: Int;
  let dimensions: QDDelta;
  let clut: QDColorTable?;
  var description: String {
    return describePixMap(self);
  }
}

enum QuickTimePictureDataStatus {
  case unchanged;
  case patched;
  case decoded(decodedMetaData: PixMapMetadata);
  case yuv420(data: YUV420Image);
}

struct QuickTimeBitDepth : OptionSet {
  let rawValue: UInt8;
  static let bit1 = QDGlyphState(rawValue: 1 << 0);
  static let bit2 = QDGlyphState(rawValue: 1 << 1);
  static let bit4 = QDGlyphState(rawValue: 1 << 2);
  static let bit8 = QDGlyphState(rawValue: 1 << 3);
  static let bit16 = QDGlyphState(rawValue: 1 << 4);
  static let bit32 = QDGlyphState(rawValue: 1 << 5);
}

// Quality value used by QuickTime
struct QuickTimeQuality : RawRepresentable, CustomStringConvertible {
  let rawValue: UInt32;
  
  var description: String {
    let quality = rawValue & ~QuickTimeQuality.kDepthMask;
    var result : String = QuickTimeQuality.qualityStr(quality);
    let rawDepth = UInt8(rawValue & QuickTimeQuality.kDepthMask);
    if rawDepth > 0 {
      let depth = QuickTimeBitDepth(rawValue: rawDepth);
      result += "\(depth)";
    }
    return result;
  }
  
  private static func qualityStr(_ quality : UInt32) -> String {
    if quality == 0x400 {
      return "Lossless";
    }
    let p = quality * 100 / 0x400 ;
    return "\(p)%";
  }
  
  private static let kDepthMask : UInt32 = 0b111111;
}

class QuickTimeIdsc : CustomStringConvertible, @unchecked Sendable {
  var description: String {
    var result = "'\(compressionName)' ";
    result += "codec: '\(codecType)' ";
    result += " version \(imageVersion).\(imageRevision)";
    result += " dimensions: \(dimensions), @ \(resolution)";
    if frameCount > 1 {
      result += " frameCount: \(frameCount)";
    }
    result += " depth: \(depth)";
    if let sQuality = spatialQuality {
      result += " quality: \(sQuality)";
    }
    if let id = clutId {
      result += " clutId: \(id)";
    }
    result += " data <size: \(dataSize) (\(compression * 100)%) idscSize: \(idscSize)";
    result += " status: \(dataStatus)";
    if let d = data {
      let subdata = d.subdata(in: 0..<16);
      result += " Magic: "
      result += subdata.map{ String(format:"%02x", $0) }.joined()
      result += " (\(d.count) bytes)"
    }
    result += ">";
    return result;
  }
  
  var compression : Float {
    let rawSize = dimensions.dh.rounded * dimensions.dv.rounded * depth / 8;
    let ratio = Float(dataSize) / Float(rawSize);
    return ratio;
  }
  
  var codecType : MacTypeCode = MacTypeCode.zero;
  var imageVersion : Int = 0;
  var imageRevision : Int = 0;
  var compressorDevelopper : MacTypeCode = MacTypeCode.zero;
  var temporalQuality : QuickTimeQuality?;
  var spatialQuality : QuickTimeQuality?;
  var dimensions : QDDelta = QDDelta.zero;
  var resolution : QDResolution = QDResolution.defaultResolution;
  var dataSize : Int = 0;
  var frameCount : Int = 0;
  var compressionName : String = "";
  var depth : Int = 0;
  var clutId : Int?;
  var idscSize : Int = 0;
  var data : Data?;
  var dataStatus : QuickTimePictureDataStatus = QuickTimePictureDataStatus.unchanged;
  
  var clut : QDColorTable? {
    if let id = self.clutId {
      return QDColorTable.forClutId(clutId: id);
    }
    return nil;
  }
}

/// Quicktime payload, typically stored within a QuickTime opcode.
class QuickTimePayload : CustomStringConvertible {
  public var description: String {
    var result = "[mode: \(mode)";
    if let mask = srcMask {
      result += " dstMask: \(mask)"
    }
    result += " transform: \(transform)";
    if let matte = self.matte {
      result += " matte: \(matte)"
    }
    result += " idsc: \(idsc)";
    if !metadata.isEmpty {
      result += " metadata: \(metadata)]";
    }
    return result;
  }
  
  // Geometrical transform matrix.
  var transform : [[FixedPoint]] = [];
  
  var matte : QDRect? = nil;
  var mode : QuickDrawMode = QuickDrawMode.defaultMode;
  var srcMask : QDRegion?;
  var accuracy : Int = 0;
  var idsc : QuickTimeIdsc = QuickTimeIdsc();
  var metadata : Dictionary<String, String> = [:];
  
  static let identityTransform = [
    [FixedPoint.one, FixedPoint.zero, FixedPoint.zero],
    [FixedPoint.zero, FixedPoint.one, FixedPoint.zero],
    [FixedPoint.zero, FixedPoint.zero, FixedPoint(16384)]];
}


/// Patch a BMP file embedded inside a QuickTime image.
/// For some reason, a part of the header is omitted,
/// so we need to add it back so that downstream system understand it as valid BMP file.
/// - Parameter quicktimeImage: the QuickTime image description object to patch
/// - Throws: an error if there is no data attached to the QuickTime image.
func patchQuickTimeBMP(quicktimeImage : inout QuickTimeIdsc) throws {
  guard let data = quicktimeImage.data else {
    throw QuickTimeError.missingQuickTimeData(quicktimeImage: quicktimeImage);
  }
  var patched = Data();
  patched.append(contentsOf: [0x42, 0x4D]);
  let bmpHeaderSize : Int32 = 14;
  let dibHeaderSize : Int32 = 12;
  let headerSize = bmpHeaderSize + dibHeaderSize;
  let totalSize = headerSize + Int32(data.count);
  patched.append(contentsOf: byteArrayLE(from: totalSize));
  patched.append(contentsOf: [0x00, 0x00, 0x00, 0x00]);
  patched.append(contentsOf: byteArrayLE(from: headerSize));
  patched.append(contentsOf: byteArrayLE(from: dibHeaderSize));
  let width = Int16(quicktimeImage.dimensions.dh.rounded);
  let height = Int16(quicktimeImage.dimensions.dv.rounded);
  patched.append(contentsOf: byteArrayLE(from: width));
  patched.append(contentsOf: byteArrayLE(from: height));
  let planes = Int16(1);
  patched.append(contentsOf: byteArrayLE(from: planes));
  let depth = Int16(quicktimeImage.depth);
  patched.append(contentsOf: byteArrayLE(from: depth));
  assert(patched.count == headerSize);
  patched.append(data);
  quicktimeImage.data = patched;
  quicktimeImage.dataStatus = .patched;
}

// QuickTime strips the 512 bytes header of SGI files.
// So this function reconstructs it.
// Information about the SGI format: https://paulbourke.net/dataformats/sgirgb/sgiversion.html
func patchQuickTimeSGI(quicktimeImage : inout QuickTimeIdsc) throws {
  guard let data = quicktimeImage.data else {
    throw QuickTimeError.missingQuickTimeData(quicktimeImage: quicktimeImage);
  }
  var patched = Data();
  patched.append(contentsOf: [0x01, 0xDA]);  // SGI header
  let (channels, componentSize) = try expandDepth(quicktimeImage.depth);
  let componentBytes = UInt8(componentSize / 8);
  patched.append(contentsOf: [0x01, componentBytes]);
  let numberChannels = UInt16(channels);
  // Number of dimensions ~number of channels
  patched.append(contentsOf: byteArrayBE(from: numberChannels));
  let height = UInt16(quicktimeImage.dimensions.dv.rounded);
  let width = UInt16(quicktimeImage.dimensions.dh.rounded);
  patched.append(contentsOf: byteArrayBE(from: width));
  patched.append(contentsOf: byteArrayBE(from: height));
  // Dimensions ~number of channels
  patched.append(contentsOf: byteArrayBE(from: numberChannels));
  let minPixel = UInt32(0);
  let maxPixel = UInt32(0xff);
  patched.append(contentsOf: byteArrayBE(from: minPixel));
  patched.append(contentsOf: byteArrayBE(from: maxPixel));
  patched.append(contentsOf: [0x00, 0x00, 0x00, 0x00]);
  let imageName = [UInt8].init(repeating: 0, count: 80);
  patched.append(contentsOf: imageName);
  // Default color-map value
  patched.append(contentsOf: [0x00, 0x00, 0x00, 0x00]);
  let dummy = [UInt8].init(repeating: 0, count: 404);
  patched.append(contentsOf: dummy);
  assert(patched.count == 512);
  patched.append(contentsOf: data);
  quicktimeImage.data = patched;
  quicktimeImage.dataStatus = .patched;
}

func patchQuickTimeRaw(quicktimeImage : inout QuickTimeIdsc) throws {
  let (_, componentSize) = try expandDepth(quicktimeImage.depth);
  let metadata = ConvertedImageMeta(
    rowBytes: quicktimeImage.dimensions.dh.rounded * 4,
    cmpSize: componentSize,
    pixelSize: 32,
    dimensions: quicktimeImage.dimensions,
    clut: nil);
  quicktimeImage.dataStatus = .decoded(decodedMetaData: metadata)
}


/// Prepare the data in a QuickTime image for downstream processing.
/// * If the codec of the image can be handled by the system dowstream (core-image).
///   The data is just passed along, except in the case of Windows BMP where the headers need to be
///   reconstructed.
/// * If the codec of the image cannot be handled, this function will try to decode the image.
///   and replace the `data` field with the raw, decoded image.
/// The `dataStatus` field of the image describe in which case we are.
/// If the data was decoded, a header for rendering is populated within dataStatus.
/// If the data was in the `raw ` codec, the code sets the header as if were decoded, but the
/// raw data is left in place (it is technically already decoded).
/// - Parameter quicktimeImage: QuickTime image description object
/// - Throws: description
func patchQuickTimeImage(quicktimeImage : inout QuickTimeIdsc) throws {
  guard let data = quicktimeImage.data else {
    throw QuickTimeError.missingQuickTimeData(quicktimeImage: quicktimeImage);
  }
  switch quicktimeImage.codecType.description {
    case "WRLE":
      try patchQuickTimeBMP(quicktimeImage: &quicktimeImage);
    case ".SGI":
      try patchQuickTimeSGI(quicktimeImage: &quicktimeImage);
      break
    case "raw ":
      try patchQuickTimeRaw(quicktimeImage: &quicktimeImage);
    case "rpza":
      let rpza = RoadPizzaImage(dimensions: quicktimeImage.dimensions);
      try rpza.load(data: data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: rpza);
      quicktimeImage.data = Data(rpza.pixmap);
    case "yuv2":
      let rgb = convertYuv2Data(data: data);
      let metadata = ConvertedImageMeta(
        rowBytes: quicktimeImage.dimensions.dh.rounded * 3,
        cmpSize: 8,
        pixelSize: 24,
        dimensions: quicktimeImage.dimensions,
        clut: nil);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: metadata);
      quicktimeImage.data = Data(rgb);
    case "8BPS":
      let planar = try PlanarImage(dimensions: quicktimeImage.dimensions, depth: quicktimeImage.depth, clut: quicktimeImage.clut);
      try planar.load(data: data);
      let rgb = planar.pixmap;
      quicktimeImage.dataStatus = .decoded(decodedMetaData: planar);
      quicktimeImage.data = Data(rgb);
      break;
    case "mjp2":
      // JPEG-2000 is a QuickTime node so we skip size + type.
      let skipped = data.subdata(in: 8..<data.count);
      quicktimeImage.dataStatus = .patched;
      quicktimeImage.data = skipped;
    case "PNTG":
      let macPaintImage = MacPaintImage();
      try macPaintImage.load(data:data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: macPaintImage);
      quicktimeImage.data = Data(macPaintImage.bitmap);
    case "rle ":
      let animation = try AnimationImage(dimensions: quicktimeImage.dimensions, depth: quicktimeImage.depth, clut: quicktimeImage.clut);
      try animation.load(data: data);
      let data = animation.pixmap;
      quicktimeImage.dataStatus = .decoded(decodedMetaData: animation);
      quicktimeImage.data = Data(data);
    case "smc ":
      guard let clut = quicktimeImage.clut else {
        throw QuickTimeError.missingClut(quicktimeImage: quicktimeImage);
      }
      let graphics = QuickTimeGraphicsImage(dimensions: quicktimeImage.dimensions, clut: clut);
      try graphics.load(data: data);
      let data = graphics.pixmap;
      quicktimeImage.dataStatus = .decoded(decodedMetaData: graphics);
      quicktimeImage.data = Data(data);
    case "tga ":
      let targa = TargaImage(dimensions: quicktimeImage.dimensions, clut: quicktimeImage.clut);
      try targa.load(data: data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: targa);
      quicktimeImage.data = Data(targa.pixmap);
    case "YVU9":
      let intel = IntelRawImage(dimensions: quicktimeImage.dimensions);
      try intel.load(data: data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: intel);
      quicktimeImage.data = Data(intel.pixmap);
    case "cvid":
      let cinepak = Cinepak(dimensions: quicktimeImage.dimensions, clut: quicktimeImage.clut);
      try cinepak.load(data: data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: cinepak);
      quicktimeImage.data = Data(cinepak.pixmap)
    case "qktk":
      let yuv = try decodeQTKND(dimensions: quicktimeImage.dimensions, data: data);
      quicktimeImage.dataStatus = .yuv420(data: yuv);
    case let c where c.hasPrefix("dv") || c == "h263":
      let dvimage = try DVImage(codec: quicktimeImage.codecType, dimensions: quicktimeImage.dimensions);
      try dvimage.load(data: data);
      quicktimeImage.dataStatus = .decoded(decodedMetaData: dvimage);
      quicktimeImage.data = Data(dvimage.pixmap);
    default:
      break;
  }
}

/// Convert the `codec` name of a QuickTime image into a type description.
/// Not strictly needed, as core-image seems to be able to guess types fines, but we have the data so.
/// Despite the fact that Preview can handle Targa files, Core Image cannot.
/// - Parameter qtImage: image whose codec will be translated.
/// - Returns: a type description as used on OS X.
func codecToContentType(qtImage : QuickTimeIdsc) -> String {
  switch qtImage.codecType.description {
    case "tga ":
      return "com.truevision.tga-image";
    case "mjp2":
      return "public.jpeg-2000";
    case "WRLE":
      return "com.microsoft.bmp";
    case "PNTG":
      return "com.apple.macpaint-image";
    case "gif ":
      return "com.compuserve.gif";
    case ".SGI":
      return "com.sgi.sgi-image";
    case "mjpa":
      return "com.jpeg";
    default:
      return "public." + qtImage.codecType.description.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct QuickTimeOpcode : OpCode, @unchecked Sendable {
  mutating func load(reader: QuickDrawDataReader) throws {
    let dataSize = Int(try reader.readInt32());
    let subReader = try reader.subReader(bytes: dataSize);
    opcodeVersion = try subReader.readInt16();
    for _ in 0..<3 {
      var line : [FixedPoint] = [];
      for _ in 0..<3 {
        line.append(try subReader.readFixed());
      }
      quicktimePayload.transform.append(line);
    }
    let matteSize = Int(try subReader.readInt32());
    let rawMatte = try subReader.readRect();
    if rawMatte != QDRect.empty {
      quicktimePayload.matte = rawMatte;
    }
    quicktimePayload.mode = QuickDrawMode(rawValue: try subReader.readUInt16());
    let srcRect = try subReader.readRect();
    quicktimePayload.accuracy = Int(try subReader.readUInt32());
    let maskSize = Int(try subReader.readUInt32());
    // variable length parts
    reader.skip(bytes: matteSize);
    let maskData = try subReader.readUInt16(bytes: maskSize);
    let (rects, bitlines) = try DecodeRegionData(boundingBox: srcRect, data: maskData);
    quicktimePayload.srcMask = QDRegion(boundingBox: srcRect, rects: rects, bitlines: bitlines);
    quicktimePayload.idsc = try subReader.readQuickTimeIdsc();
    do {
      let atomReader = try subReader.subReader(bytes: quicktimePayload.idsc.idscSize - 86);
      try atomReader.parseQuickTimeStream(quicktimePayload: &quicktimePayload);
    } catch {
      print("Failed atom parsing: \(error)");
    }
    
    quicktimePayload.idsc.data = try subReader.readData(bytes: subReader.remaining);
    try patchQuickTimeImage(quicktimeImage: &quicktimePayload.idsc);
  }
  
  var opcodeVersion : Int16 = 0;
  var quicktimePayload : QuickTimePayload = QuickTimePayload();
}

extension QuickDrawDataReader {
  /// Parse a QuickTime image into a QuickDraw picture.
  /// This will fail if the QuickTime image does not have an `idsc` (image description) atom.
  /// Note that the resulting file is enough for this program, a valid QuickDraw file would require some
  /// header operations.
  /// - Throws: if data is corrupt / unreadable
  /// - Returns: a _fake_ QuickDraw image with a single QuickTime opcode.
  func readQuickTimeImage() throws -> QDPicture {
    let fileSize = self.remaining;
    var payload = QuickTimePayload();
    payload.transform = QuickTimePayload.identityTransform;
    try parseQuickTimeStream(quicktimePayload: &payload);
    try patchQuickTimeImage(quicktimeImage: &payload.idsc);
    let frame = QDRect(topLeft: QDPoint.zero, dimension: payload.idsc.dimensions);
    let destination = QDRegion.forRect(rect: frame);
    payload.srcMask = destination;
    let picture = QDPicture(size: fileSize, frame: frame, filename: self.filename);
    picture.version = 0xff;
    var opcode = QuickTimeOpcode();
    opcode.quicktimePayload = payload;
    picture.opcodes.append(opcode);
    return picture;
  }
  
  func parseQuickTimeStream(quicktimePayload: inout QuickTimePayload) throws  {
    var quickTimeIdsc : QuickTimeIdsc?;
    var quickTimeIdat : Data?;
    
    while self.remaining > 8 {
      let length = Int(try readInt32()) - 8;
      guard length >= 0 else {
        throw QuickTimeError.corruptQuickTimeAtomLength(length: length);
      }
      let type = try readType();
      let data = try readData(bytes: length);
      // "iicc" would be ICC profile
      // See https://exiftool.org/TagNames/QuickTime.html
      switch type.description {
        case "idsc":
          let subReader = try QuickDrawDataReader(data: data, position: 0);
          quickTimeIdsc = try subReader.readQuickTimeIdsc();
        case "idat":
          quickTimeIdat = data
        case "meta":
          let subReader = try QuickDrawDataReader(data: data, position: 0);
          quicktimePayload.metadata = try subReader.readQuickTimeMeta();
        default:
          print("Ignoring QuickTime atom \(type): \(length) bytes");
          break;
      }
    }
    if let idsc = quickTimeIdsc {
      quicktimePayload.idsc = idsc;
    }
    if let idat = quickTimeIdat {
      quicktimePayload.idsc.data = idat;
    }
  }
  
  func readQuickTimeQuality() throws -> QuickTimeQuality? {
    let rawQuality = try readUInt32(); // 4
    if rawQuality > 0 {
      return QuickTimeQuality(rawValue: rawQuality);
    }
    return nil;
  }
  
  func readQuickTimeIdsc() throws -> QuickTimeIdsc {
    let idsc = QuickTimeIdsc();
    idsc.idscSize = Int(try readUInt32());
    idsc.codecType = try readType();
    skip(bytes: 8);
    idsc.imageVersion = Int(try readUInt16());
    idsc.imageRevision = Int(try readUInt16());
    idsc.compressorDevelopper = try readType();
    idsc.temporalQuality  = try readQuickTimeQuality();
    idsc.spatialQuality = try readQuickTimeQuality();
    idsc.dimensions = try readDelta();
    idsc.resolution = try readResolution();
    idsc.dataSize = Int(try readInt32());
    idsc.frameCount = Int(try readInt16());
    idsc.compressionName = try readStr31();
    idsc.depth = Int(try readInt16());
    let rawClutId = Int(try readInt16());
    if rawClutId >= 0 {
      idsc.clutId = rawClutId;
    }
    return idsc;
  }
  
  func readQuickTimeMeta() throws -> Dictionary<String, String> {
    var metadata = Dictionary<String, String>()
    let size = Int(try readUInt32());
    guard size >= 0 else {
      throw QuickTimeError.corruptQuickTimeAtomLength(length: size);
    }
    while self.remaining > 8 {
      let subAtom = try self.readType();
      let subSize = Int(try readUInt16());
      // See https://exiftool.org/TagNames/QuickTime.html
      switch subAtom.description {
        case "©cpy":
          skip(bytes: 2);
          metadata["copyright"] = try readString(bytes: subSize);
        default:
          print("Ignoring copyright atom \(subAtom)");
      }
    }
    return metadata;
  }
}
