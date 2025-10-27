
//  NetSocketNew.swift
//  Created by Dustin Mierau • @mierau

import Foundation
import Network

// MARK: - Endianness and Framing

/// Byte order for multi-byte integer values in binary protocols
public enum Endian {
  /// Big-endian (network byte order, most significant byte first)
  case big
  /// Little-endian (least significant byte first)
  case little
}

/// Length prefix types for framing variable-length data (strings, arrays, binary blobs)
///
/// Used to encode the size of the following data as a fixed-width integer.
/// Each case can specify its own endianness.
public enum LengthPrefix {
  /// 1-byte length prefix (0-255)
  case u8
  /// 2-byte length prefix (0-65,535)
  case u16(Endian = .big)
  /// 4-byte length prefix (0-4,294,967,295)
  case u32(Endian = .big)
  /// 8-byte length prefix (0-2^64-1)
  case u64(Endian = .big)

  /// Number of bytes used by this length prefix
  var byteCount: Int {
    switch self {
    case .u8: return 1
    case .u16: return 2
    case .u32: return 4
    case .u64: return 8
    }
  }
}

/// Delimiter patterns for text-based protocols
public enum Delimiter {
  /// Custom single byte delimiter
  case byte(UInt8)
  /// Null terminator (0x00)
  case zeroByte
  /// Line feed (\n, 0x0A)
  case lineFeed
  /// Carriage return + line feed (\r\n, 0x0D 0x0A)
  case carriageReturnLineFeed

  /// Binary representation of this delimiter
  var data: Data {
    switch self {
    case .byte(let b): return Data([b])
    case .zeroByte: return Data([0x00])
    case .lineFeed: return Data([0x0A])
    case .carriageReturnLineFeed: return Data([0x0D, 0x0A])
    }
  }
}

/// TLS/SSL encryption policy for socket connections
public struct TLSPolicy: Sendable {
  /// Create a TLS-enabled policy with optional custom configuration
  /// - Parameter configure: Optional closure to customize TLS options
  public static func enabled(_ configure: (@Sendable (NWProtocolTLS.Options) -> Void)? = nil) -> TLSPolicy {
    TLSPolicy(enabled: true, configure: configure)
  }

  /// Create a policy with TLS disabled (plaintext connection)
  public static var disabled: TLSPolicy { TLSPolicy(enabled: false, configure: nil) }

  /// Whether TLS is enabled
  public let enabled: Bool
  /// Optional TLS configuration closure
  public let configure: (@Sendable (NWProtocolTLS.Options) -> Void)?
}

// MARK: - Errors

/// Errors that can occur during socket operations
public enum NetSocketError: Error, CustomStringConvertible, Sendable {
  /// Socket is not yet in ready state
  case notReady
  /// Connection has been closed
  case closed
  /// Invalid port number provided
  case invalidPort
  /// Network operation failed with underlying error
  case failed(underlying: Error)
  /// Not enough data available to fulfill read request
  case insufficientData(expected: Int, got: Int)
  /// Frame size exceeds configured maximum
  case framingExceeded(max: Int)
  /// Failed to decode data
  case decodeFailed(Error)
  /// Failed to encode data
  case encodeFailed(Error)

  public var description: String {
    switch self {
    case .notReady: return "Connection not ready."
    case .closed: return "Connection closed."
    case .invalidPort: return "Invalid port number."
    case .failed(let e): return "Network failure: \(e.localizedDescription)"
    case .insufficientData(let exp, let got): return "Insufficient data: need \(exp), have \(got)."
    case .framingExceeded(let max): return "Frame length exceeded maximum \(max)."
    case .decodeFailed(let e): return "Decoding failed: \(e)"
    case .encodeFailed(let e): return "Encoding failed: \(e)"
    }
  }
}

// MARK: - NetSocketNew

/// An async/await TCP socket with automatic buffering and framing support
///
/// NetSocketNew provides:
/// - Async connection management
/// - Automatic receive buffering with memory compaction
/// - Length-prefixed framing for messages
/// - Type-safe reading/writing of integers, strings, and custom types
/// - File upload/download with progress tracking
/// - Flexible encoder/decoder support (JSON, binary, etc.)
///
/// Example usage:
/// ```swift
/// let socket = try await NetSocketNew.connect(host: "example.com", port: 80)
/// try await socket.write("Hello\n".data(using: .utf8)!)
/// let response = try await socket.readUntil(delimiter: .lineFeed)
/// ```
public actor NetSocketNew {
  /// Configuration options for the socket
  public struct Config: Sendable {
    /// Size of chunks to receive from network at once (default: 64 KB)
    public var receiveChunk: Int = 64 * 1024
    /// Maximum bytes to buffer before disconnecting (default: 8 MB)
    public var maxBufferBytes: Int = 8 * 1024 * 1024
    /// Maximum size for a single framed message (default: 4 MB)
    public var maxFrameBytes: Int = 4 * 1024 * 1024
    public init() {}
  }
  
  // Connection + state
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "NetSocket.NWConnection")
  private var ready = false
  private var isClosed = false
  
  // Buffer with compaction
  private var buffer = Data()
  private var head = 0 // start of unread bytes
  private let cfg: Config
  
  // Waiters for data/ready
  private var dataWaiters: [CheckedContinuation<Void, Error>] = []
  private var readyWaiters: [CheckedContinuation<Void, Error>] = []
  
  // Codable hooks - stored as closures for flexibility with any encoder/decoder
  private var encodeValue: @Sendable (any Encodable) throws -> Data = { value in
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }
  
  private var decodeValue: @Sendable (Data, any Decodable.Type) throws -> any Decodable = { data, type in
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
  }
  
  // MARK: Init/Connect
  
  private init(connection: NWConnection, config: Config) {
    self.connection = connection
    self.cfg = config
  }
  
  /// Connect to a remote host and return a ready socket
  ///
  /// This method establishes a TCP connection using Network framework types and waits until
  /// the connection is in `.ready` state.
  ///
  /// - Parameters:
  ///   - host: Network framework host (e.g., `.name("example.com", nil)` or `.ipv4(...)`)
  ///   - port: Network framework port
  ///   - tls: TLS policy (default: enabled with default settings)
  ///   - config: Socket configuration (default: standard settings)
  /// - Returns: A connected and ready `NetSocketNew`
  /// - Throws: Network errors or connection failures
  public static func connect(host: NWEndpoint.Host, port: NWEndpoint.Port, tls: TLSPolicy = .enabled(), config: Config = .init()) async throws -> NetSocketNew {
    let parameters = NWParameters.tcp
    if tls.enabled {
      let tlsOptions = NWProtocolTLS.Options()
      tls.configure?(tlsOptions)
      parameters.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
    }

    let conn = NWConnection(host: host, port: port, using: parameters)
    let socket = NetSocketNew(connection: conn, config: config)
    try await socket.start()
    return socket
  }

  /// Convenience wrapper to connect using string hostname and integer port
  public static func connect(host: String, port: UInt16, tls: TLSPolicy = .enabled(), config: Config = .init()) async throws -> NetSocketNew {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw NetSocketError.invalidPort
    }
    return try await connect(host: .name(host, nil), port: nwPort, tls: tls, config: config)
  }

  /// Inject custom encoding/decoding logic (supports any encoder/decoder: JSON, CBOR, MessagePack, etc.)
  ///
  /// Example with JSONEncoder:
  /// ```
  /// let encoder = JSONEncoder()
  /// socket.useCoders(
  ///   encode: { try encoder.encode($0) },
  ///   decode: { data, type in try decoder.decode(type, from: data) }
  /// )
  /// ```
  ///
  /// Example with other encoders (pseudocode):
  /// ```
  /// let cbor = CBOREncoder()
  /// socket.useCoders(
  ///   encode: { try cbor.encode($0) },
  ///   decode: { data, type in try CBORDecoder().decode(type, from: data) }
  /// )
  /// ```
  public func useCoders(
    encode: @escaping @Sendable (any Encodable) throws -> Data,
    decode: @escaping @Sendable (Data, any Decodable.Type) throws -> any Decodable
  ) {
    self.encodeValue = encode
    self.decodeValue = decode
  }
  
  /// Convenience method to configure JSON encoding/decoding
  ///
  /// Sets up the socket to use the provided JSON encoder/decoder for `send()` and `receive()` calls.
  ///
  /// - Parameters:
  ///   - encoder: A configured `JSONEncoder`
  ///   - decoder: A configured `JSONDecoder`
  public func useJSONCoders(encoder: JSONEncoder, decoder: JSONDecoder) {
    self.encodeValue = { try encoder.encode($0) }
    self.decodeValue = { data, type in try decoder.decode(type, from: data) }
  }
  
  private func start() async throws {
    self.connection.stateUpdateHandler = { state in
      Task { [weak self] in
        guard let self else { return }
        switch state {
        case .ready:
          await self.setReady()
          await self.resumeReadyWaiters(with: .success(()))
        case .failed(let error):
          await self.failAllWaiters(NetSocketError.failed(underlying: error))
          await self.setClosed()
        case .waiting(let error):
          // bubble as transient failure for awaiters; reconnect logic could live here
          await self.resumeReadyWaiters(with: .failure(NetSocketError.failed(underlying: error)))
        case .cancelled:
          await self.failAllWaiters(NetSocketError.closed)
          await self.setClosed()
        default:
          break
        }
      }
    }
    
    // Kick off receive loop after .start
    self.connection.start(queue: queue)
    try await self.waitUntilReady()
    self.startReceiveLoop()
  }
  
  private func waitUntilReady() async throws {
    guard !ready else { return }
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      readyWaiters.append(cont)
    }
  }
  
  private func resumeReadyWaiters(with result: Result<Void, Error>) {
    let waiters = readyWaiters
    readyWaiters.removeAll()
    for w in waiters {
      switch result {
      case .success: w.resume()
      case .failure(let e): w.resume(throwing: e)
      }
    }
  }
  
  private func failAllWaiters(_ error: Error) {
    resumeReadyWaiters(with: .failure(error))
    let waiters = dataWaiters
    dataWaiters.removeAll()
    for w in waiters { w.resume(throwing: error) }
  }
  
  private func setReady() {
    ready = true
  }
  
  private func setClosed() {
    isClosed = true
  }
  
  // MARK: Receive loop (runs on DispatchQueue, hops into actor)
  
  private nonisolated func startReceiveLoop() {
    func loop(_ connection: NWConnection, chunk: Int, owner: NetSocketNew) {
      print("NetSocketNew: Calling connection.receive() to request more data...")
      connection.receive(minimumIncompleteLength: 1, maximumLength: chunk) { data, _, isComplete, error in
        print("NetSocketNew: Receive callback - data: \(data?.count ?? 0) bytes, isComplete: \(isComplete), error: \(String(describing: error))")
        if let error {
          Task { await owner.handleReceiveError(error) }
          return
        }
        if let data, !data.isEmpty {
          Task { await owner.append(data) }
        }
        if isComplete {
          Task { await owner.handleEOF() }
          return
        }
        loop(connection, chunk: chunk, owner: owner)
      }
    }
    loop(connection, chunk: cfg.receiveChunk, owner: self)
  }
  
  private func handleReceiveError(_ error: Error) {
    isClosed = true
    failAllWaiters(NetSocketError.failed(underlying: error))
  }
  
  private func handleEOF() {
    isClosed = true
    let waiters = dataWaiters
    dataWaiters.removeAll()
    for w in waiters { w.resume() } // wake so readers can observe closure
  }
  
  private func append(_ data: Data) {
    print("NetSocketNew: Received \(data.count) bytes from network, buffer now has \(buffer.count - head + data.count) available")
    buffer.append(data)
    if buffer.count - head > cfg.maxBufferBytes {
      // Hard stop: drop connection rather than OOM'ing.
      isClosed = true
      connection.cancel()
      failAllWaiters(NetSocketError.framingExceeded(max: cfg.maxBufferBytes))
      return
    }
    resumeDataWaiters()
  }
  
  private func resumeDataWaiters() {
    let waiters = dataWaiters
    dataWaiters.removeAll()
    for w in waiters { w.resume() }
  }
  
  // MARK: Close

  /// Close the connection gracefully
  ///
  /// Performs a graceful shutdown of the underlying network connection (e.g., TCP FIN)
  /// and wakes all pending read/write operations with a `NetSocketError.closed` error.
  /// This method is idempotent - subsequent calls are ignored.
  ///
  /// Use `forceClose()` for immediate non-graceful termination (e.g., TCP RST).
  public func close() {
    guard !isClosed else { return }
    isClosed = true
    connection.cancel()
    resumeDataWaiters()
    resumeReadyWaiters(with: .failure(NetSocketError.closed))
  }

  /// Force close the connection immediately (non-graceful)
  ///
  /// Performs an immediate non-graceful shutdown of the underlying network connection
  /// (e.g., TCP RST). Use this when you need to terminate the connection immediately
  /// without waiting for graceful closure. For normal shutdown, use `close()` instead.
  ///
  /// This method is idempotent - subsequent calls are ignored.
  public func forceClose() {
    guard !isClosed else { return }
    isClosed = true
    connection.forceCancel()
    resumeDataWaiters()
    resumeReadyWaiters(with: .failure(NetSocketError.closed))
  }

  // MARK: Send (async)

  /// Write raw data to the socket
  ///
  /// Sends data and waits for confirmation that it has been processed by the network stack.
  ///
  /// - Parameter data: Raw bytes to send
  /// - Throws: `NetSocketError` if connection is not ready or send fails
  public func write(_ data: Data) async throws {
    try await ensureReady()
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error { cont.resume(throwing: NetSocketError.failed(underlying: error)) }
        else { cont.resume() }
      })
    }
  }

  /// Write a fixed-width integer to the socket
  ///
  /// - Parameters:
  ///   - value: The integer value to write
  ///   - endian: Byte order (default: big-endian)
  /// - Throws: `NetSocketError` if write fails
  public func write<T: FixedWidthInteger>(_ value: T, endian: Endian = .big) async throws {
    var v = value
    switch endian {
    case .big: v = T(bigEndian: value)
    case .little: v = T(littleEndian: value)
    }
    var copy = v
    let size = MemoryLayout<T>.size
    let bytes = withUnsafePointer(to: &copy) {
      Data(bytes: $0, count: size)
    }
    try await write(bytes)
  }
  
  /// Write a boolean as a single byte (0 or 1)
  /// - Parameter value: Boolean value
  public func write(_ value: Bool) async throws {
    try await write(value ? UInt8(0x01) : UInt8(0x00))
  }
  
  /// Write a Float as its IEEE 754 bit pattern
  /// - Parameters:
  ///   - value: Float value
  ///   - endian: Byte order (default: big-endian)
  public func write(_ value: Float, endian: Endian = .big) async throws {
    try await write(value.bitPattern, endian: endian)
  }
  
  /// Write a Double as its IEEE 754 bit pattern
  /// - Parameters:
  ///   - value: Double value
  ///   - endian: Byte order (default: big-endian)
  public func write(_ value: Double, endian: Endian = .big) async throws {
    try await write(value.bitPattern, endian: endian)
  }

  /// Write a string to the socket, optionally length-prefixed
  ///
  /// - Parameters:
  ///   - string: String to write
  ///   - prefix: Optional length prefix (if provided, string is sent as a framed message)
  ///   - encoding: Text encoding (default: UTF-8)
  /// - Throws: `NetSocketError` if encoding fails or write fails
  public func write(_ string: String, prefix: LengthPrefix? = nil, encoding: String.Encoding = .utf8) async throws {
    guard let data = string.data(using: encoding) else {
      throw NetSocketError.encodeFailed(NSError(domain: "StringEncoding", code: -1))
    }
    if let prefix { try await sendFrame(data, prefix: prefix) }
    else { try await write(data) }
  }

  // MARK: Frames & Codable

  /// Send a length-prefixed frame
  ///
  /// Writes the payload size as a fixed-width integer, followed by the payload bytes.
  ///
  /// - Parameters:
  ///   - payload: Data to send
  ///   - prefix: Length prefix type (default: u32 big-endian)
  /// - Throws: `NetSocketError.framingExceeded` if payload is too large for prefix type
  public func sendFrame(_ payload: Data, prefix: LengthPrefix = .u32()) async throws {
    // Ensure frame payload does not exceed max frame length.
    switch prefix {
    case .u8 where payload.count > Int(UInt8.max):
      throw NetSocketError.framingExceeded(max: Int(UInt8.max))
    case .u16 where payload.count > Int(UInt16.max):
      throw NetSocketError.framingExceeded(max: Int(UInt16.max))
    case .u32 where payload.count > Int(UInt32.max):
      throw NetSocketError.framingExceeded(max: Int(UInt32.max))
    default:
      break
    }
    
    if payload.count > cfg.maxFrameBytes { throw NetSocketError.framingExceeded(max: cfg.maxFrameBytes) }
    var header = Data()
    switch prefix {
    case .u8: header.append(UInt8(payload.count))
    case .u16(let e):
      try header.appendInteger(UInt16(payload.count), endian: e)
    case .u32(let e):
      try header.appendInteger(UInt32(payload.count), endian: e)
    case .u64(let e):
      try header.appendInteger(UInt64(payload.count), endian: e)
    }
    try await write(header + payload)
  }
  
  /// Receive a length-prefixed frame
  ///
  /// Reads a length prefix, then reads exactly that many bytes. Waits for data to arrive if needed.
  ///
  /// - Parameter prefix: Length prefix type (default: u32 big-endian)
  /// - Returns: The frame payload
  /// - Throws: `NetSocketError.framingExceeded` if frame size exceeds maximum
  public func receiveFrame(prefix: LengthPrefix = .u32()) async throws -> Data {
    let length: Int
    switch prefix {
    case .u8:
      let v: UInt8 = try await read(UInt8.self)
      length = Int(v)
    case .u16(let e):
      let v: UInt16 = try await read(UInt16.self, endian: e)
      length = Int(v)
    case .u32(let e):
      let v: UInt32 = try await read(UInt32.self, endian: e)
      length = Int(v)
    case .u64(let e):
      let v: UInt64 = try await read(UInt64.self, endian: e)
      if v > UInt64(cfg.maxFrameBytes) { throw NetSocketError.framingExceeded(max: cfg.maxFrameBytes) }
      length = Int(v)
    }
    if length > cfg.maxFrameBytes { throw NetSocketError.framingExceeded(max: cfg.maxFrameBytes) }
    return try await read(length)
  }

  /// Send an encodable value as a length-prefixed frame
  ///
  /// Uses the configured encoder (default: JSON) to serialize the value.
  ///
  /// - Parameters:
  ///   - value: Value to encode and send
  ///   - prefix: Length prefix type (default: u32 big-endian)
  /// - Throws: `NetSocketError.encodeFailed` if encoding fails
  public func send<T: Encodable>(_ value: T, prefix: LengthPrefix = .u32()) async throws {
    do {
      let data = try encodeValue(value)
      try await sendFrame(data, prefix: prefix)
    } catch {
      throw NetSocketError.encodeFailed(error)
    }
  }

  /// Receive and decode a length-prefixed value
  ///
  /// Uses the configured decoder (default: JSON) to deserialize the value.
  ///
  /// - Parameters:
  ///   - type: Type to decode
  ///   - prefix: Length prefix type (default: u32 big-endian)
  /// - Returns: Decoded value
  /// - Throws: `NetSocketError.decodeFailed` if decoding fails
  public func receive<T: Decodable>(_ type: T.Type, prefix: LengthPrefix = .u32()) async throws -> T {
    let data = try await receiveFrame(prefix: prefix)
    do {
      let decoded = try decodeValue(data, T.self)
      guard let result = decoded as? T else {
        throw NetSocketError.decodeFailed(NSError(
          domain: "NetSocketNew",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Type mismatch in decode"]
        ))
      }
      return result
    } catch {
      throw NetSocketError.decodeFailed(error)
    }
  }

  // MARK: Read typed & utilities

  /// Read a fixed-width integer from the socket
  ///
  /// - Parameters:
  ///   - type: Integer type to read
  ///   - endian: Byte order (default: big-endian)
  /// - Returns: The integer value
  /// - Throws: `NetSocketError` if insufficient data or connection closed
  public func read<T: FixedWidthInteger>(_ type: T.Type = T.self, endian: Endian = .big) async throws -> T {
    let size = MemoryLayout<T>.size
    let data = try await read(size)
    let value: T = data.withUnsafeBytes { raw in
      raw.load(as: T.self)
    }
    switch endian {
    case .big: return T(bigEndian: value)
    case .little: return T(littleEndian: value)
    }
  }

  /// Read a fixed-length string
  ///
  /// - Parameters:
  ///   - length: Number of bytes to read
  ///   - encoding: Text encoding (default: UTF-8)
  /// - Returns: Decoded string
  /// - Throws: `NetSocketError` if decoding fails or insufficient data
  public func read(_ length: Int, encoding: String.Encoding = .utf8) async throws -> String {
    let data = try await read(length)
    guard let s = String(data: data, encoding: encoding) else { throw NetSocketError.decodeFailed(NSError()) }
    return s
  }

  /// Read a string until a delimiter is found
  ///
  /// - Parameters:
  ///   - delimiter: Delimiter pattern to search for
  ///   - maxBytes: Maximum bytes to read before throwing (default: no limit)
  ///   - includeDelimiter: Whether to include delimiter in result (default: false)
  /// - Returns: String read from stream (delimiter consumed but not included unless specified)
  /// - Throws: `NetSocketError` if decoding fails, max bytes exceeded, or connection closed
  public func read(until delimiter: Delimiter, maxBytes: Int? = nil, includeDelimiter: Bool = false) async throws -> String {
    let bytes = try await read(past: delimiter.data, maxBytes: maxBytes, includeDelimiter: includeDelimiter)
    guard let s = String(data: bytes, encoding: .utf8) else { throw NetSocketError.decodeFailed(NSError()) }
    return s
  }

  /// Read a pascal string (1-byte length prefix followed by string data)
  ///
  /// This method reads a single byte for the length, then reads that many bytes and attempts
  /// to decode them as a string. It tries multiple encodings for compatibility with legacy
  /// protocols like Hotline: UTF-8, Shift-JIS, Windows-1251, and falls back to MacRoman.
  ///
  /// - Returns: The decoded string, or nil if length is 0
  /// - Throws: `NetSocketError` if reading fails or no encoding succeeds
  public func readPascalString() async throws -> String? {
    let length = try await read(UInt8.self)
    guard length > 0 else { return nil }

    let data = try await read(Int(length))

    // Try auto-detection with common encodings
    let allowedEncodings = [
      String.Encoding.utf8.rawValue,
      String.Encoding.shiftJIS.rawValue,
      String.Encoding.unicode.rawValue,
      String.Encoding.windowsCP1251.rawValue
    ]

    var decodedString: NSString?
    let detected = NSString.stringEncoding(
      for: data,
      encodingOptions: [.allowLossyKey: false],
      convertedString: &decodedString,
      usedLossyConversion: nil
    )

    if allowedEncodings.contains(detected), let str = decodedString as? String {
      return str
    }

    // Fallback to MacRoman for classic Mac compatibility
    guard let str = String(data: data, encoding: .macOSRoman) else {
      throw NetSocketError.decodeFailed(NSError(
        domain: "NetSocketNew",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to decode pascal string with any known encoding"]
      ))
    }
    return str
  }

  /// Read data until a delimiter is found
  ///
  /// Searches the buffer for the delimiter pattern and returns all data up to (and optionally including)
  /// the delimiter. The delimiter is always consumed from the stream.
  ///
  /// - Parameters:
  ///   - delimiter: Binary delimiter pattern to search for
  ///   - maxBytes: Maximum bytes to read before throwing (default: no limit)
  ///   - includeDelimiter: Whether to include delimiter in result (default: false)
  /// - Returns: Data read from stream
  /// - Throws: `NetSocketError.framingExceeded` if max bytes exceeded, or connection errors
  public func read(past delimiter: Data, maxBytes: Int? = nil, includeDelimiter: Bool = false) async throws -> Data {
    while true {
      try Task.checkCancellation()
      if let r = search(delimiter: delimiter) {
        let consumeLen = r.upperBound - head
        let data = try await read(consumeLen)
        return includeDelimiter ? data : data.dropLast(delimiter.count)
      }
      if let maxBytes, availableBytes >= maxBytes {
        throw NetSocketError.framingExceeded(max: maxBytes)
      }
      try await waitForData()
      guard !isClosed || availableBytes > 0 else { throw NetSocketError.closed }
    }
  }

  /// Read exactly N bytes from the socket
  ///
  /// Waits for data to arrive if buffer doesn't contain enough bytes yet. The internal buffer
  /// is automatically compacted after reading to prevent unbounded memory growth.
  ///
  /// - Parameter count: Number of bytes to read
  /// - Returns: Exactly `count` bytes
  /// - Throws: `NetSocketError.insufficientData` if connection closes before enough data arrives
  public func read(_ count: Int) async throws -> Data {
    try await ensureReadable(count)
    let start = head
    let end = head + count
    let slice = buffer[start..<end]
    head = end
    compactIfNeeded()
    return Data(slice)
  }
  
  /// Skip/discard exactly N bytes from the stream without allocating memory
  public func skip(_ count: Int) async throws {
    guard count > 0 else { return }
    try await ensureReadable(count)
    head += count
    compactIfNeeded()
  }
  
  /// Skip until delimiter is found (discards delimiter too)
  public func skip(past delimiter: Data) async throws {
    while true {
      try Task.checkCancellation()
      if let r = search(delimiter: delimiter) {
        head = r.upperBound  // Skip to end of delimiter
        compactIfNeeded()
        return
      }
      try await waitForData()
      guard !isClosed else { throw NetSocketError.closed }
    }
  }

  /// Read exactly N bytes with progress callbacks
  ///
  /// Like `read(_:)`, but reads in chunks and reports progress after each chunk.
  /// Useful for downloading large amounts of data where you want to update UI progress.
  ///
  /// Example:
  /// ```swift
  /// let data = try await socket.read(1_000_000) { current, total in
  ///   print("Progress: \(current)/\(total)")
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - count: Number of bytes to read
  ///   - chunkSize: Size of chunks to read at a time (default: 8192)
  ///   - progress: Optional callback with (bytesReceived, totalBytes)
  /// - Returns: Exactly `count` bytes
  /// - Throws: `NetSocketError` if connection closes before enough data arrives
  public func read(
    _ count: Int,
    chunkSize: Int = 8192,
    progress: (@Sendable (Int, Int) -> Void)? = nil
  ) async throws -> Data {
    var data = Data()
    data.reserveCapacity(count)
    var received = 0

    while received < count {
      try Task.checkCancellation()
      let toRead = min(chunkSize, count - received)
      let chunk = try await read(toRead)
      data.append(chunk)
      received += chunk.count
      progress?(received, count)
    }

    return data
  }

  func peek(_ count: Int) async throws -> Data {
    try await ensureReadable(count)
    let slice = buffer[head..<(head + count)]
    return Data(slice) // Don't advance head
  }
  
  // MARK: Internals
  
  private var availableBytes: Int { buffer.count - head }
  
  private func waitForData() async throws {
    try Task.checkCancellation()
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      if isClosed { cont.resume(); return }
      dataWaiters.append(cont)
    }
  }
  
  private func ensureReadable(_ count: Int) async throws {
    try await ensureReady()
    while availableBytes < count {
      try Task.checkCancellation()
      if isClosed { throw NetSocketError.insufficientData(expected: count, got: availableBytes) }
      try await waitForData()
    }
  }
  
  private func ensureReady() async throws {
    if isClosed { throw NetSocketError.closed }
    if !ready { try await waitUntilReady() }
  }
  
  private func compactIfNeeded() {
    // Avoid unbounded memory as head advances
    if head > 64 * 1024 && head > buffer.count / 2 {
      buffer.removeSubrange(0..<head)
      head = 0
    }
  }
  
  private func search(delimiter: Data) -> Range<Int>? {
    guard !delimiter.isEmpty, availableBytes >= delimiter.count else { return nil }
    let hay = buffer[head..<buffer.count]
    
    // Fast path for single-byte delimiters
    if delimiter.count == 1, let byte = delimiter.first {
      if let idx = hay.firstIndex(of: byte) {
        let pos = head + hay.distance(from: hay.startIndex, to: idx)
        return pos..<(pos + 1)
      }
      return nil
    }
    
    // General case
    if let r = hay.firstRange(of: delimiter) {
      let lower = head + hay.distance(from: hay.startIndex, to: r.lowerBound)
      let upper = head + hay.distance(from: hay.startIndex, to: r.upperBound)
      return lower..<upper
    }
    
    return nil
  }
}

// MARK: - Small helpers

private extension Data {
  mutating func appendInteger<T: FixedWidthInteger>(_ value: T, endian: Endian) throws {
    var v = value
    switch endian {
    case .big: v = T(bigEndian: value)
    case .little: v = T(littleEndian: value)
    }
    var copy = v
    withUnsafePointer(to: &copy) { ptr in
      self.append(contentsOf: UnsafeRawBufferPointer(start: ptr, count: MemoryLayout<T>.size))
    }
  }
}

public extension NetSocketNew {
  /// Progress information for file uploads/downloads
  struct FileProgress: Sendable {
    /// Number of bytes sent/received so far
    public let sent: Int64
    /// Total file size (may be nil if unknown)
    public let total: Int64?
  }

  /// Upload a file to the socket without framing (raw byte stream)
  ///
  /// Reads and writes the file in chunks to limit memory usage. Each chunk waits for network
  /// backpressure via `.contentProcessed` before reading the next chunk.
  ///
  /// - Parameters:
  ///   - url: File URL to upload
  ///   - chunkSize: Chunk size for reading/writing (default: 256 KB)
  ///   - progress: Optional progress callback
  /// - Returns: Total bytes sent
  /// - Throws: File I/O or network errors
  @discardableResult
  func writeFile(
    from url: URL,
    chunkSize: Int = 256 * 1024,
    progress: (@Sendable (FileProgress) -> Void)? = nil
  ) async throws -> Int64 {
    try await ensureReady()
    let total = try? self.fileLength(at: url)
    
    let fh = try FileHandle(forReadingFrom: url)
    defer { try? fh.close() }
    
    var sent: Int64 = 0
    while true {
      try Task.checkCancellation()
      guard let chunk = try fh.read(upToCount: chunkSize), !chunk.isEmpty else { break }
      try await write(chunk) // uses .contentProcessed completion inside
      sent += Int64(chunk.count)
      progress?(.init(sent: sent, total: total))
    }
    return sent
  }
  
  /// Upload a file as a length-prefixed frame without buffering the entire file in memory
  ///
  /// Sends the file size as a length prefix, then streams the file content in chunks.
  /// Memory-efficient for large files.
  ///
  /// - Parameters:
  ///   - url: File URL to upload
  ///   - lengthPrefix: Length prefix type (default: u64 big-endian)
  ///   - chunkSize: Chunk size for reading/writing (default: 256 KB)
  ///   - progress: Optional progress callback
  /// - Returns: Total bytes sent (not including length header)
  /// - Throws: File I/O, framing, or network errors
  @discardableResult
  func sendFileFramed(
    _ url: URL,
    lengthPrefix: LengthPrefix = .u64(.big),
    chunkSize: Int = 256 * 1024,
    progress: (@Sendable (FileProgress) -> Void)? = nil
  ) async throws -> Int64 {
    let total = try fileLength(at: url)
    try ensure(total, fitsIn: lengthPrefix)
    
    // 1) Send the length header
    var header = Data()
    switch lengthPrefix {
    case .u8:
      header.append(UInt8(truncatingIfNeeded: total))
    case .u16(let e):
      try header.appendInteger(UInt16(truncatingIfNeeded: total), endian: e)
    case .u32(let e):
      try header.appendInteger(UInt32(truncatingIfNeeded: total), endian: e)
    case .u64(let e):
      try header.appendInteger(UInt64(total), endian: e)
    }
    try await write(header)
    
    // 2) Stream the file bytes (raw) right after the header
    let sent = try await writeFile(from: url, chunkSize: chunkSize) { prog in
      progress?(prog)
    }
    return sent
  }
  
  /// Download a length-prefixed file and write it to disk in chunks (bounded memory)
  ///
  /// Reads the file size from a length prefix, then streams the content directly to disk
  /// in chunks to avoid loading the entire file into memory.
  ///
  /// - Parameters:
  ///   - url: Destination file URL
  ///   - lengthPrefix: Length prefix type (default: u64 big-endian)
  ///   - chunkSize: Chunk size for reading/writing (default: 256 KB)
  ///   - overwrite: Whether to overwrite existing file (default: true)
  ///   - progress: Optional progress callback
  /// - Returns: Total bytes written
  /// - Throws: File I/O, framing, or network errors
  @discardableResult
  func receiveFile(
    to url: URL,
    lengthPrefix: LengthPrefix = .u64(.big),
    chunkSize: Int = 256 * 1024,
    overwrite: Bool = true,
    progress: (@Sendable (FileProgress) -> Void)? = nil
  ) async throws -> Int64 {
    // 1) Read length header
    let total64: Int64 = try await {
      switch lengthPrefix {
      case .u8:                return Int64(try await read(UInt8.self))
      case .u16(let e):        return Int64(try await read(UInt16.self, endian: e))
      case .u32(let e):        return Int64(try await read(UInt32.self, endian: e))
      case .u64(let e):
        let v: UInt64 = try await read(UInt64.self, endian: e)
        guard v <= UInt64(Int64.max) else {
          throw NetSocketError.framingExceeded(max: Int(Int64.max))
        }
        return Int64(v)
      }
    }()
    
    // 2) Prepare destination file
    if overwrite { try? FileManager.default.removeItem(at: url) }
    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
    let fh = try FileHandle(forWritingTo: url)
    defer { try? fh.close() }
    
    // 3) Stream chunks from the socket into the file
    var remaining = total64
    var written: Int64 = 0
    
    while remaining > 0 {
      try Task.checkCancellation()
      let n = Int(min(Int64(chunkSize), remaining))
      let chunk = try await read(n) // reuses your internal buffer, bounded by n
      fh.write(chunk)
      remaining -= Int64(n)
      written   += Int64(n)
      progress?(.init(sent: written, total: total64))
    }
    return written
  }

  /// Download a file of known length and write it to disk in chunks
  ///
  /// Unlike `receiveFile()`, this method does **not** read a length prefix. The caller must
  /// provide the expected file size (e.g., from protocol metadata). The file is streamed
  /// directly to disk to avoid loading it entirely into memory.
  ///
  /// Supports atomic writes: when enabled, data is written to a temporary `.part` file and
  /// renamed on success. If an error occurs, the temporary file is automatically cleaned up.
  ///
  /// - Parameters:
  ///   - url: Destination file URL
  ///   - length: Exact number of bytes to read (must match what's on the wire)
  ///   - chunkSize: Chunk size for reading/writing (default: 256 KB)
  ///   - overwrite: Whether to overwrite existing file (default: true)
  ///   - atomic: Write to temporary file and rename on success (default: true)
  ///   - progress: Optional progress callback
  /// - Returns: Total bytes written (equals `length` on success)
  /// - Throws: File I/O or network errors. On atomic writes, partial files are cleaned up.
  ///
  /// Example:
  /// ```swift
  /// // Hotline protocol: file size comes from transaction header
  /// let transaction = try await socket.receive(HotlineTransaction.self)
  /// try await socket.receiveFileKnownLength(
  ///     to: destinationURL,
  ///     length: transaction.fileSize
  /// )
  /// ```
  @discardableResult
  func receiveFileKnownLength(
    to url: URL,
    length: Int64,
    chunkSize: Int = 256 * 1024,
    overwrite: Bool = true,
    atomic: Bool = true,
    progress: (@Sendable (FileProgress) -> Void)? = nil
  ) async throws -> Int64 {
    precondition(length >= 0, "length must be >= 0")

    // Validate length doesn't exceed configured maximum
    guard length <= cfg.maxFrameBytes else {
      throw NetSocketError.framingExceeded(max: cfg.maxFrameBytes)
    }

    // Fast path: nothing to do
    if length == 0 {
      if overwrite { try? FileManager.default.removeItem(at: url) }
      FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
      return 0
    }

    // Prepare destination (optionally atomic)
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    let tmp = atomic
      ? dir.appendingPathComponent(".\(url.lastPathComponent).part-\(UUID().uuidString)")
      : url

    if overwrite { try? fm.removeItem(at: tmp) }
    if overwrite, !atomic { try? fm.removeItem(at: url) }

    // Create and open the file for writing
    fm.createFile(atPath: tmp.path, contents: nil, attributes: nil)
    let fh = try FileHandle(forWritingTo: tmp)
    defer { try? fh.close() }

    var remaining = length
    var written: Int64 = 0

    do {
      while remaining > 0 {
        try Task.checkCancellation()
        let n = Int(min(Int64(chunkSize), remaining))
        let chunk = try await read(n)
        fh.write(chunk)
        remaining -= Int64(n)
        written += Int64(n)
        progress?(.init(sent: written, total: length))
      }
    } catch {
      // Cleanup partial file on failure if we were writing atomically
      if atomic { try? fm.removeItem(at: tmp) }
      throw error
    }

    // Atomically move into place if requested
    if atomic {
      if overwrite { try? fm.removeItem(at: url) }
      try fm.moveItem(at: tmp, to: url)
    }

    return written
  }
}

// MARK: - Small helpers (private)
fileprivate extension NetSocketNew {
  func fileLength(at url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else {
      throw NetSocketError.failed(underlying: NSError(
        domain: "NetSocket", code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Not a regular file: \(url.path)"]
      ))
    }
    if let s = values.fileSize { return Int64(s) }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    if let n = attrs[.size] as? NSNumber { return n.int64Value }
    throw NetSocketError.failed(underlying: NSError(
      domain: "NetSocket", code: 1002,
      userInfo: [NSLocalizedDescriptionKey: "Unable to determine file size for \(url.lastPathComponent)"]
    ))
  }
  
  func ensure(_ length: Int64, fitsIn prefix: LengthPrefix) throws {
    let max: Int64 = {
      switch prefix {
      case .u8:  return Int64(UInt8.max)
      case .u16: return Int64(UInt16.max)
      case .u32: return Int64(UInt32.max)
      case .u64: return Int64.max
      }
    }()
    if length > max {
      throw NetSocketError.framingExceeded(max: Int(max))
    }
  }
}

// MARK: - Stream-based Encoding/Decoding

/// Protocol for types that can encode themselves to binary data
///
/// Types conforming to `NetSocketEncodable` produce binary data that can be sent over
/// a socket. Unlike writing field-by-field to the socket, encodable types build complete
/// binary messages that are sent in a single write operation for efficiency.
///
/// Example:
/// ```swift
/// struct MyMessage: NetSocketEncodable {
///   let id: UInt32
///   let name: String
///
///   func encode(endian: Endian) throws -> Data {
///     var data = Data()
///     // Encode fields to data...
///     return data
///   }
/// }
///
/// try await socket.send(message)
/// ```
public protocol NetSocketEncodable: Sendable {
  /// Encode this value to binary data
  ///
  /// Implementations should build a complete binary message and return it as Data.
  /// The data will be sent to the socket in a single write operation.
  ///
  /// - Parameter endian: Byte order for multi-byte values
  /// - Returns: Encoded binary data ready to send
  /// - Throws: Encoding errors
  func encode(endian: Endian) throws -> Data
}

/// Protocol for types that can decode themselves directly from a socket stream
///
/// Types conforming to `NetSocketDecodable` read field-by-field directly from the socket
/// using async reads. This enables true streaming without buffering entire messages.
///
/// **Important**: If decoding throws after consuming some bytes (e.g., validation fails),
/// the socket will be left with those bytes consumed. In practice, this usually means the
/// connection should be closed. For most protocols this is acceptable since decode errors
/// indicate corrupt data or protocol violations.
///
/// Example:
/// ```swift
/// struct MyMessage: NetSocketDecodable {
///   let id: UInt32
///   let name: String
///
///   init(from socket: NetSocketNew, endian: Endian) async throws {
///     self.id = try await socket.read(UInt32.self, endian: endian)
///     let nameLen = try await socket.read(UInt16.self, endian: endian)
///     let nameData = try await socket.readExactly(Int(nameLen))
///     guard let name = String(data: nameData, encoding: .utf8) else {
///       throw NetSocketError.decodeFailed(NSError())
///     }
///     self.name = name
///   }
/// }
///
/// let message = try await socket.receive(MyMessage.self)
/// ```
public protocol NetSocketDecodable: Sendable {
  /// Decode a value by reading directly from the socket stream
  ///
  /// This initializer should read all necessary fields from the socket using
  /// methods like `read(_:endian:)`, `readExactly(_:)`, `readString(length:)`, etc.
  ///
  /// The socket handles waiting for data to arrive, so you can read field by field
  /// without worrying about buffering.
  ///
  /// - Parameters:
  ///   - socket: Socket to read from
  ///   - endian: Byte order for multi-byte values
  /// - Throws: Network errors, insufficient data, or custom decoding errors
  init(from socket: NetSocketNew, endian: Endian) async throws
}

public extension NetSocketNew {
  /// Send an encodable value to the socket
  ///
  /// The type encodes itself to binary data, which is then sent in a single write operation.
  ///
  /// Example:
  /// ```swift
  /// struct MyMessage: NetSocketEncodable {
  ///   let id: UInt32
  ///   let name: String
  ///
  ///   func encode(endian: Endian) throws -> Data {
  ///     var data = Data()
  ///     // Build binary message...
  ///     return data
  ///   }
  /// }
  ///
  /// try await socket.send(message)
  /// ```
  ///
  /// - Parameters:
  ///   - value: Value conforming to NetSocketEncodable
  ///   - endian: Byte order (default: big-endian)
  /// - Throws: Encoding or network errors
  func send<T: NetSocketEncodable>(_ value: T, endian: Endian = .big) async throws {
    let data = try value.encode(endian: endian)
    try await write(data)
  }

  /// Receive and decode a value directly from the socket stream (no length prefix)
  ///
  /// The type reads field-by-field from the socket as needed, enabling true streaming
  /// without buffering entire messages. Useful for protocols where message size isn't
  /// known upfront or for progressive decoding.
  ///
  /// Example:
  /// ```swift
  /// struct ServerEntry: NetSocketDecodable {
  ///   let id: UInt32
  ///   let name: String
  ///
  ///   init(from socket: NetSocketNew, endian: Endian) async throws {
  ///     self.id = try await socket.read(UInt32.self, endian: endian)
  ///     // Read variable-length string...
  ///   }
  /// }
  ///
  /// let entry = try await socket.receive(ServerEntry.self)
  /// ```
  ///
  /// - Parameters:
  ///   - type: Type conforming to NetSocketDecodable
  ///   - endian: Byte order (default: big-endian)
  /// - Returns: Decoded value
  /// - Throws: Decoding or network errors
  func receive<T: NetSocketDecodable>(_ type: T.Type, endian: Endian = .big) async throws -> T {
    return try await T(from: self, endian: endian)
  }
}
