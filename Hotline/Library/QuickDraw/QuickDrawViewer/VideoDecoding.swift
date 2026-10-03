//
//  VideoDecoding.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 14.10.2025.
//

import VideoToolbox
import CoreGraphics
import CoreVideo

/// Make a CMFormatDescription
/// - Parameters:
///   - codec: source codec, as a MacTypeCode
///   - dimensions: size of the media
/// - Throws: Initialisation error
/// - Returns: an initialised Core Media Format Description
func makeCMFormatDescription(codec: MacTypeCode, dimensions : QDDelta) throws -> CMFormatDescription {
  var formatDescription : CMFormatDescription?;
  let status = CMVideoFormatDescriptionCreate(
    allocator: nil, codecType: codec.rawValue,
    width: Int32(dimensions.dh.rounded), height: Int32(dimensions.dv.rounded),
    extensions: nil, formatDescriptionOut: &formatDescription);
  guard status == 0 else {
    throw NSError(domain: "CMVideoFormatDescriptionCreate", code: Int(status), userInfo: nil);
  }
  return formatDescription!;
}

/// Creates a decoding session, a bit cumbersome when we are only decoding a single frame, mais c'est la vie.
/// - Parameters:
///   - formatDescription: description of the source data,.
///   - toFormat: target format, typically `kCVPixelFormatType_24RGB`.
/// - Throws: in case of initialisation failure.
/// - Returns: A initialised Video-Toolbox session
func makeVTDecodingSession(formatDescription: CMFormatDescription, toFormat: OSType) throws ->  VTDecompressionSession {
  var session : VTDecompressionSession?;
  let decoderSpec : [NSString: NSObject]  = [:];
  let imageSpec = [kCVPixelBufferPixelFormatTypeKey : toFormat];
  let sessionStatus = VTDecompressionSessionCreate(
    allocator: nil, formatDescription: formatDescription,
    decoderSpecification: decoderSpec as CFDictionary,
    imageBufferAttributes: imageSpec as CFDictionary,
    outputCallback: nil, decompressionSessionOut: &session);
  guard sessionStatus == 0 else {
    throw NSError(domain: "VTDecompressionSessionCreate", code: Int(sessionStatus), userInfo: nil);
  }
  return session!;
}

/// Creates a core-media sample buffer for raw-bytes.
/// - Parameters:
///   - formatDescription: description of the source data,.
///   - data: raw bytes to convert.
/// - Throws: Initialisation failure.
/// - Returns: A core media sample buffer.
func makeCMSampleBuffer(formatDescription: CMFormatDescription, data: Data) throws -> CMSampleBuffer {
  let sampleSizeArray = [data.count]
  let blockBuffer = try createCMBlockBuffer(from: data);
  var sampleBuffer: CMSampleBuffer?;
  let bufferStatus = CMSampleBufferCreateReady(
    allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
    formatDescription: formatDescription, sampleCount: 1,
    sampleTimingEntryCount: 0, sampleTimingArray: nil,
    sampleSizeEntryCount: 1, sampleSizeArray: sampleSizeArray, sampleBufferOut: &sampleBuffer)
  guard bufferStatus == 0 else {
    throw NSError(domain: "CMSampleBufferCreateReady", code: Int(bufferStatus), userInfo: nil);
  }
  return sampleBuffer!;
}

/// Creates a block buffer from bytes
/// - Parameter data: raw bytes
/// - Throws: initialisation failure.
/// - Returns: An initialised buffer
func createCMBlockBuffer(from data: Data) throws -> CMBlockBuffer  {
  var blockBuffer: CMBlockBuffer?

  // Convert Data to a byte pointer
  let dataPointer = UnsafeMutableRawPointer(mutating: (data as NSData).bytes)
  let dataLength = data.count

  // Create a CMBlockBuffer
  let status = CMBlockBufferCreateWithMemoryBlock(
    allocator: kCFAllocatorDefault,
    memoryBlock: dataPointer,
    blockLength: dataLength,
    blockAllocator: kCFAllocatorNull,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: dataLength,
    flags: 0,
    blockBufferOut: &blockBuffer
  )

  guard status == kCMBlockBufferNoErr else {
    throw NSError(domain: "CMBlockBufferCreateWithMemoryBlock", code: Int(status), userInfo: nil);
  }
  return blockBuffer!
}

func decodeBuffer(session: VTDecompressionSession, sampleBuffer : CMSampleBuffer) throws -> (rowBytes : Int, pixmap : [UInt8]){
  let decodeFlags = VTDecodeFrameFlags();
  var decodeInfoFlags = VTDecodeInfoFlags();
  var rowBytes : Int = 0;
  var pixmap : [UInt8] = [];
  let outputHandler : VTDecompressionOutputHandler = {_, _, buffer, _ , _ in
    guard let b = buffer else {
      return;
    }
    let pixelBuffer = b as CVPixelBuffer;
    rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer);
    let lockFlags = CVPixelBufferLockFlags(rawValue: 0);
    CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags);
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    let size = CVPixelBufferGetDataSize(pixelBuffer);
    let bufferPtr = baseAddress!.bindMemory(to: UInt8.self, capacity: size);
    let buffer = UnsafeBufferPointer(start: bufferPtr, count: size);
    pixmap = Array(buffer);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags);
  }
  let decodeStatus = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags:decodeFlags, infoFlagsOut: &decodeInfoFlags, outputHandler: outputHandler);
  guard decodeStatus == 0 else {
    throw NSError(domain: "VTDecompressionSessionDecodeFrame", code: Int(decodeStatus), userInfo: nil);
  }
  return (rowBytes: rowBytes, pixmap: pixmap);
}

// MARK: - Yuv image to CG Image logic
extension YUV420Image {
  func toCGImage() -> CGImage? {
    // Create CVPixelBuffer from YUV planes
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8Planar,
      nil,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    // Copy Y plane
    let yDest = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
    let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    yPlane.withUnsafeBytes { yPtr in
      for row in 0..<height {
        let srcOffset = row * width
        let dstOffset = row * yBytesPerRow
        memcpy(yDest!.advanced(by: dstOffset), yPtr.baseAddress!.advanced(by: srcOffset), width)
      }
    }

    // Copy U plane
    let uDest = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
    let uBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
    uPlane.withUnsafeBytes { uPtr in
      for row in 0..<(height / 2) {
        let srcOffset = row * (width / 2)
        let dstOffset = row * uBytesPerRow
        memcpy(uDest!.advanced(by: dstOffset), uPtr.baseAddress!.advanced(by: srcOffset), width / 2)
      }
    }

    // Copy V plane
    let vDest = CVPixelBufferGetBaseAddressOfPlane(buffer, 2)
    let vBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 2)
    vPlane.withUnsafeBytes { vPtr in
      for row in 0..<(height / 2) {
        let srcOffset = row * (width / 2)
        let dstOffset = row * vBytesPerRow
        memcpy(vDest!.advanced(by: dstOffset), vPtr.baseAddress!.advanced(by: srcOffset), width / 2)
      }
    }

    // Convert CVPixelBuffer to CGImage
    var cgImage: CGImage?
    VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage)

    return cgImage
  }
}
