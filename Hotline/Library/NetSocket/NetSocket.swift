// NetSocket.swift
// Dustin Mierau • @mierau
// MIT License

import Foundation
import Network

/// Byte order for multi-byte integer values in binary protocols
public enum Endian {
  /// Big-endian (network byte order, most significant byte first)
  case big
  /// Little-endian (least significant byte first)
  case little
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

/// An async TCP socket with automatic buffering
///
/// NetSocket provides:
/// - Async connection management
/// - Automatic receive buffering with memory compaction
/// - Type-safe reading/writing of integers, strings, and custom types
/// - File upload/download with progress tracking
///
/// Example usage:
/// ```swift
/// let socket = try await NetSocket.connect(host: "example.com", port: 80)
/// try await socket.write("Hello\n".data(using: .utf8)!)
/// let response = try await socket.read(until: .lineFeed)
/// ```
public actor NetSocket {
  /// Configuration options for the socket
  public struct Config: Sendable {
    /// Size of chunks to receive from network at once (default: 64 KB)
    public var receiveChunk: Int = 64 * 1024
    /// Maximum bytes to buffer before disconnecting (default: 8 MB)
    public var maxBufferBytes: Int = 8 * 1024 * 1024
    public init() {}
  }

  // Connection + state
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "NetSocket.NWConnection")
  private var ready = false
  private var isClosed = false
  private let connectionID: String  // For logging
  
  // Buffer with compaction
  private var buffer = Data()
  private var head = 0 // start of unread bytes
  private let config: Config
  
  // Waiters for data/ready
  private var dataWaiters: [CheckedContinuation<Void, Error>] = []
  private var readyWaiters: [CheckedContinuation<Void, Error>] = []
  
  // MARK: Init
  
  private init(connection: NWConnection, config: Config) {
    self.connection = connection
    self.config = config
    // Create a human-readable connection ID for logging
    if case .hostPort(host: let h, port: let p) = connection.endpoint {
      self.connectionID = "\(h):\(p)"
    } else {
      self.connectionID = "unknown"
    }
  }
  
  // MARK: Connect
  
  /// Connect to a remote host and return a ready socket
  ///
  /// This method establishes a TCP connection using Network framework types and waits until
  /// the connection is in `.ready` state.
  ///
  /// - Parameters:
  ///   - host: Network framework host (e.g., `.name("example.com", nil)` or `.ipv4(...)`)
  ///   - port: Network framework port
  ///   - config: Socket configuration (default: standard settings)
  ///   - tls: TLS policy (default: disabled)
  /// - Returns: A connected and ready `NetSocket`
  /// - Throws: Network errors or connection failures
  public static func connect(host: NWEndpoint.Host, port: NWEndpoint.Port, config: Config = .init(), tls: TLSPolicy = .disabled) async throws -> NetSocket {
    let parameters: NWParameters
    if tls.enabled {
      parameters = NWParameters(tls: Self.createTLSOptions(policy: tls))
    } else {
      parameters = .tcp
    }
    let conn = NWConnection(host: host, port: port, using: parameters)
    let socket = NetSocket(connection: conn, config: config)
    try await socket.start()
    return socket
  }

  /// Convenience wrapper to connect using string hostname and integer port
  public static func connect(host: String, port: UInt16, config: Config = .init(), tls: TLSPolicy = .disabled) async throws -> NetSocket {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw NetSocketError.invalidPort
    }

    return try await self.connect(host: NWEndpoint.Host(host), port: nwPort, config: config, tls: tls)
  }

  /// Create TLS options configured to allow self-signed certificates
  private static func createTLSOptions(policy: TLSPolicy) -> NWProtocolTLS.Options {
    let tlsOptions = NWProtocolTLS.Options()

    // Allow any custom configuration
    policy.configure?(tlsOptions)

    // Set minimum TLS version
    sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

    // Configure to accept self-signed certificates by setting a permissive verify block
    sec_protocol_options_set_verify_block(
      tlsOptions.securityProtocolOptions,
      { _, _, completion in
        // Accept all certificates (including self-signed)
        completion(true)
      },
      DispatchQueue.global()
    )

    return tlsOptions
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

  // MARK: Send Data

  /// Write raw data to the socket
  ///
  /// Sends data and waits for confirmation that it has been processed by the network stack.
  ///
  /// - Parameter data: Raw bytes to send
  /// - Throws: `NetSocketError` if connection is not ready or send fails
  @discardableResult
  public func write(_ data: Data) async throws -> Int {
    try await ensureReady()
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error { cont.resume(throwing: NetSocketError.failed(underlying: error)) }
        else { cont.resume(returning: data.count) }
      })
    }
  }

  /// Write a fixed-width integer to the socket
  ///
  /// - Parameters:
  ///   - value: The integer value to write
  ///   - endian: Byte order (default: big-endian)
  /// - Throws: `NetSocketError` if write fails
  @discardableResult
  public func write<T: FixedWidthInteger>(_ value: T, endian: Endian = .big) async throws -> Int {
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
    return bytes.count
  }
  
  /// Write a boolean as a single byte (0 or 1)
  /// - Parameter value: Boolean value
  @discardableResult
  public func write(_ value: Bool) async throws -> Int {
    return try await write(UInt8(value ? 0x01 : 0x00))
  }
  
  /// Write a Float as its IEEE 754 bit pattern
  /// - Parameters:
  ///   - value: Float value
  ///   - endian: Byte order (default: big-endian)
  @discardableResult
  public func write(_ value: Float, endian: Endian = .big) async throws -> Int {
    return try await write(value.bitPattern, endian: endian)
  }
  
  /// Write a Double as its IEEE 754 bit pattern
  /// - Parameters:
  ///   - value: Double value
  ///   - endian: Byte order (default: big-endian)
  @discardableResult
  public func write(_ value: Double, endian: Endian = .big) async throws -> Int {
    return try await write(value.bitPattern, endian: endian)
  }

  /// Write a string to the socket, optionally length-prefixed
  ///
  /// - Parameters:
  ///   - string: String to write
  ///   - encoding: Text encoding (default: UTF-8)
  ///   - allowLossyConversion: Allow lossy encoding if necessary (default: false)
  /// - Throws: `NetSocketError` if encoding fails or write fails
  @discardableResult
  public func write(_ string: String, encoding: String.Encoding = .utf8, allowLossyConversion: Bool = false) async throws -> Int {
    guard let data = string.data(using: encoding, allowLossyConversion: allowLossyConversion) else {
      throw NetSocketError.encodeFailed(NSError(domain: "StringEncoding", code: -1))
    }
    return try await write(data)
  }

  // MARK: Receive Data

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
    try await self.ensureReadable(count)
    let start = self.head
    let end = self.head + count
    let slice = self.buffer[start..<end]
    self.head = end
    self.compactIfNeeded()
    return Data(slice)
  }
  
  /// Read a fixed-width integer from the socket
  ///
  /// - Parameters:
  ///   - type: Integer type to read
  ///   - endian: Byte order (default: big-endian)
  /// - Returns: The integer value
  /// - Throws: `NetSocketError` if insufficient data or connection closed
  public func read<T: FixedWidthInteger>(_ type: T.Type = T.self, endian: Endian = .big) async throws -> T {
    let size = MemoryLayout<T>.size
    let data = try await self.read(size)
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
    let data = try await self.read(length)
    guard let s = String(data: data, encoding: encoding) else {
      throw NetSocketError.decodeFailed(NSError())
    }
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
  
  // MARK: Peek Data
  
  public var availableBytes: Int { self.buffer.count - self.head }

  public func peek(_ count: Int) -> Data? {
    guard self.availableBytes >= count else {
      return nil
    }
    
    let slice = self.buffer[self.head..<(self.head + count)]
    return Data(slice) // Don't advance head
  }
  
  public func peek(upto count: Int) -> Data {
    let amount = min(self.availableBytes, count)
    guard amount > 0 else {
      return Data()
    }
    
    let slice = self.buffer[self.head..<(self.head + amount)]
    return Data(slice)
  }
  
  public func peek(awaiting count: Int) async throws -> Data {
    try await self.ensureReadable(count)
    let slice = self.buffer[self.head..<(self.head + count)]
    return Data(slice) // Don't advance head
  }
  
  // MARK: Skip Data
  
  /// Skip/discard exactly N bytes from the stream without allocating memory
  public func skip(_ count: Int) async throws {
    guard count > 0 else { return }
    try await self.ensureReadable(count)
    self.head += count
    self.compactIfNeeded()
  }
  
  /// Skip until delimiter is found (discards delimiter too)
  public func skip(past delimiter: Data) async throws {
    while true {
      try Task.checkCancellation()
      if let r = self.search(delimiter: delimiter) {
        self.head = r.upperBound  // Skip to end of delimiter
        self.compactIfNeeded()
        return
      }
      try await self.waitForData()
      guard !self.isClosed else {
        throw NetSocketError.closed
      }
    }
  }
  
  // MARK: Files
  
  /// Upload a file from a URL, yielding progress as an AsyncSequence.
  ///
  /// Iterating this sequence drives the transfer. Each yielded value reports
  /// the total bytes sent so far and the known total. Cancel the consuming
  /// task to cancel the transfer.
  ///
  /// This method handles opening and closing the file handle automatically.
  ///
  /// - Parameters:
  ///   - url: File URL to upload.
  ///   - chunkSize: Size of each read chunk.
  /// - Returns: An `AsyncThrowingStream` of `FileProgress` updates.
  func writeFile(from url: URL, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    // This stream wrapper manages the FileHandle's lifetime.
    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
      // Capture self (the actor) to use in detached task
      let actor = self
      
      // Open file on a background thread (file I/O is blocking)
      let task = Task.detached {
        let fh: FileHandle
        let total: Int
        
        // 1. Open file and get length (blocking I/O, done off-actor)
        do {
          total = Int(try NetSocket.fileLength(at: url))
          fh = try FileHandle(forReadingFrom: url)
        } catch {
          continuation.finish(throwing: NetSocketError.failed(underlying: error))
          return
        }
        
        // 2. Now switch to the actor context to call the actor-isolated method
        let stream = await actor.writeFile(
          from: fh,
          length: total,
          chunkSize: chunkSize
        )
        
        // 3. Forward all elements from the underlying stream to our stream
        do {
          for try await progress in stream {
            try Task.checkCancellation() // Exit early if cancelled
            continuation.yield(progress)
          }
          try? fh.close()
          continuation.finish()
        } catch is CancellationError {
          try? fh.close()
          continuation.finish()
        } catch {
          try? fh.close()
          continuation.finish(throwing: error)
        }
      }
      
      // If the *consumer* cancels the stream, we cancel our managing task.
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
  
  /// Upload a file from an open FileHandle, yielding progress as an AsyncSequence.
  ///
  /// Iterating this sequence drives the transfer. Each yielded value reports
  /// the total bytes sent so far and the known total. Cancel the consuming
  /// task to cancel the transfer.
  ///
  /// **Note:** The caller is responsible for opening and closing the `fileHandle`.
  ///
  /// - Parameters:
  ///   - fileHandle: Open `FileHandle` for reading.
  ///   - length: Exact number of bytes to send (total file size).
  ///   - chunkSize: Size of each read chunk.
  /// - Returns: An `AsyncThrowingStream` of `FileProgress` updates.
  func writeFile(from fileHandle: FileHandle, length: Int, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    precondition(length >= 0, "length must be >= 0")
    
    if length == 0 {
      return AsyncThrowingStream { continuation in
        continuation.yield(.init(sent: 0, total: 0, bytesPerSecond: 0, estimatedTimeRemaining: 0))
        continuation.finish()
      }
    }
    
    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        
        var estimator = TransferRateEstimator(total: Int(length))
        
        do {
          try await self.ensureReady()
          
          while estimator.transferred < length {
            try Task.checkCancellation()
            
            let toRead = Int(min(chunkSize, length - estimator.transferred))
            
            // Read from disk
            guard let chunk = try fileHandle.read(upToCount: toRead), !chunk.isEmpty else {
              if estimator.transferred < length {
                throw NetSocketError.failed(underlying: NSError(
                  domain: "NetSocket", code: 9001,
                  userInfo: [NSLocalizedDescriptionKey: "File read ended prematurely. Expected \(length) bytes, got \(estimator.transferred)."]
                ))
              }
              break
            }
            
            // Write to network
            try await self.write(chunk)
            
            // Update estimator and yield progress
            let progress = estimator.update(bytes: chunk.count)
            continuation.yield(progress)
          }
          
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
  
  /// Receive a file of known length and yield progress updates as an AsyncSequence.
  ///
  /// Iterating this sequence drives the transfer. Each yielded value reports
  /// the total bytes written so far and the known total. Cancel the consuming
  /// task to cancel the transfer.
  ///
  /// - Parameters:
  ///   - fileHandle: Open `FileHandle` for writing (caller must close).
  ///   - length: Exact number of bytes expected.
  ///   - chunkSize: Size of each read chunk.
  /// - Returns: An `AsyncThrowingStream` of `FileProgress` updates.
  func receiveFile(to fileHandle: FileHandle, length: Int, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    precondition(length >= 0, "length must be >= 0")
    
    if length == 0 {
      return AsyncThrowingStream { continuation in
        continuation.yield(.init(sent: 0, total: 0, bytesPerSecond: 0, estimatedTimeRemaining: 0))
        continuation.finish()
      }
    }
    
    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
      let task = Task { [weak self] in
        guard let self else {
          continuation.finish()
          return
        }
        
        var estimator = TransferRateEstimator(total: length)
        
        do {
          var remaining: Int = length
          
          while remaining > 0 {
            try Task.checkCancellation()
            let n = min(chunkSize, remaining)
            
            let chunk = try await self.read(n)
            try fileHandle.write(contentsOf: chunk)
            
            let chunkSize = Int(chunk.count)
            remaining -= chunkSize
            let progress = estimator.update(bytes: chunkSize)
            continuation.yield(progress)
          }
          
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
  
  /// Download a file of known length and write it to disk in chunks
  ///
  /// This method does **not** read a length prefix. The caller must provide the expected
  /// file size (e.g., from protocol metadata). The file is streamed directly to disk to
  /// avoid loading it entirely into memory.
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
  /// try await socket.receiveFile(
  ///     to: destinationURL,
  ///     length: transaction.fileSize
  /// )
  /// ```
  @discardableResult
  func receiveFile(
    to url: URL,
    length: Int,
    chunkSize: Int = 256 * 1024,
    overwrite: Bool = true,
    atomic: Bool = true,
    progress: (@Sendable (FileProgress) -> Void)? = nil
  ) async throws -> Int {
    precondition(length >= 0, "length must be >= 0")
        
    // Fast path: nothing to do
    if length == 0 {
      if overwrite { try? FileManager.default.removeItem(at: url) }
      FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
      return 0
    }
    
    // Prepare destination (optionally atomic)
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    let tmp = atomic ? dir.appendingPathComponent(".\(url.lastPathComponent).part-\(UUID().uuidString)") : url
    
    if overwrite { try? fm.removeItem(at: tmp) }
    if overwrite, !atomic { try? fm.removeItem(at: url) }
    
    // Create and open the file for writing
    fm.createFile(atPath: tmp.path, contents: nil, attributes: nil)
    let fh = try FileHandle(forWritingTo: tmp)
    defer { try? fh.close() }
    
    var remaining: Int = length
    var written: Int = 0
    
    do {
      while remaining > 0 {
        try Task.checkCancellation()
        let n = Int(min(chunkSize, remaining))
        let chunk = try await self.read(n)
        try fh.write(contentsOf: chunk)
        remaining -= n
        written += Int(n)
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
  
  // MARK: Internals
  
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
  
  private func startReceiveLoop() {
    @Sendable func loop(_ connection: NWConnection, chunk: Int, owner: NetSocket, connID: String) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: chunk) { [weak owner] data, _, isComplete, error in
        Task {
          guard let o = owner else {
            return
          }
          
          if let error {
            await o.handleReceiveError(error)
            return
          }
          if let data, !data.isEmpty {
            await o.append(data, connID: connID)
          }
          if isComplete {
            await o.handleEOF()
            return
          }
          loop(connection, chunk: chunk, owner: o, connID: connID)
        }
      }
    }
    loop(connection, chunk: self.config.receiveChunk, owner: self, connID: connectionID)
  }
  
  private func handleReceiveError(_ error: Error) {
    self.isClosed = true
    self.failAllWaiters(NetSocketError.failed(underlying: error))
  }
  
  private func handleEOF() {
    self.isClosed = true
    let waiters = self.dataWaiters
    self.dataWaiters.removeAll()
    for w in waiters {
      w.resume()
    } // wake so readers can observe closure
  }
  
  private func setReady() {
    self.ready = true
  }
  
  private func setClosed() {
    self.isClosed = true
  }
  
  private func ensureReady() async throws {
    if self.isClosed {
      throw NetSocketError.closed
    }
    if !self.ready {
      try await self.waitUntilReady()
    }
  }
  
  private func ensureReadable(_ count: Int) async throws {
    try await self.ensureReady()
    while self.availableBytes < count {
      try Task.checkCancellation()
      if self.isClosed {
        throw NetSocketError.insufficientData(expected: count, got: self.availableBytes)
      }
      try await self.waitForData()
    }
  }
  
  private func waitForData() async throws {
    try Task.checkCancellation()
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      if self.isClosed {
        cont.resume()
        return
      }
      self.dataWaiters.append(cont)
    }
  }
  
  private func compactIfNeeded() {
    // Avoid unbounded memory as head advances
    if self.head > 64 * 1024 && self.head > self.buffer.count / 2 {
      self.buffer.removeSubrange(0..<self.head)
      self.head = 0
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
  
  private static func fileLength(at url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else {
      throw NetSocketError.failed(underlying: NSError(
        domain: "NetSocket", code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Not a regular file: \(url.path)"]
      ))
    }
    if let s = values.fileSize { return Int64(s) }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    if let n = attrs[.size] as? NSNumber {
      return n.int64Value
    }
    throw NetSocketError.failed(underlying: NSError(
      domain: "NetSocket", code: 1002,
      userInfo: [NSLocalizedDescriptionKey: "Unable to determine file size for \(url.lastPathComponent)"]
    ))
  }
  
  private func waitUntilReady() async throws {
    guard !self.ready else { return }
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      self.readyWaiters.append(cont)
    }
  }
  
  private func resumeReadyWaiters(with result: Result<Void, Error>) {
    let waiters = self.readyWaiters
    self.readyWaiters.removeAll()
    for w in waiters {
      switch result {
      case .success: w.resume()
      case .failure(let e): w.resume(throwing: e)
      }
    }
  }
  
  private func failAllWaiters(_ error: Error) {
    self.resumeReadyWaiters(with: .failure(error))
    let waiters = self.dataWaiters
    self.dataWaiters.removeAll()
    for w in waiters {
      w.resume(throwing: error)
    }
  }
  
  private func append(_ data: Data, connID: String) {
    buffer.append(data)
    if buffer.count - head > config.maxBufferBytes {
      // Hard stop: drop connection rather than OOM'ing.
      isClosed = true
      connection.cancel()
      failAllWaiters(NetSocketError.framingExceeded(max: config.maxBufferBytes))
      return
    }
    resumeDataWaiters()
  }
  
  private func resumeDataWaiters() {
    let waiters = dataWaiters
    dataWaiters.removeAll()
    for w in waiters { w.resume() }
  }
}

// MARK: - Utilities

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

// MARK: - NetSocketEncodable

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
///   init(from socket: NetSocket, endian: Endian) async throws {
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
  init(from socket: NetSocket, endian: Endian) async throws
}

public extension NetSocket {
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
    try await self.write(data)
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
  ///   init(from socket: NetSocket, endian: Endian) async throws {
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
