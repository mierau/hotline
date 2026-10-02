// NetSocket.swift
// Dustin Mierau • @mierau
// MIT License

import Foundation
import Network

/// Byte order for multi-byte integers
public enum Endian {
  /// Most significant byte first (network byte order)
  case big
  /// Least significant byte first
  case little
}

/// Bytes that end a record in line- or null-terminated protocols
public enum Delimiter {
  /// Any single byte
  case byte(UInt8)
  /// 0x00
  case zeroByte
  /// `\n` (0x0A)
  case lineFeed
  /// `\r\n` (0x0D 0x0A)
  case carriageReturnLineFeed

  /// The delimiter's bytes
  var data: Data {
    switch self {
    case .byte(let b): return Data([b])
    case .zeroByte: return Data([0x00])
    case .lineFeed: return Data([0x0A])
    case .carriageReturnLineFeed: return Data([0x0D, 0x0A])
    }
  }
}

/// Whether a connection uses TLS, and how it's set up
public struct TLSPolicy: Sendable {
  /// Use TLS, optionally adjusting its options before connecting
  public static func enabled(_ configure: (@Sendable (NWProtocolTLS.Options) -> Void)? = nil) -> TLSPolicy {
    TLSPolicy(enabled: true, configure: configure)
  }

  /// Plain TCP
  public static var disabled: TLSPolicy { TLSPolicy(enabled: false, configure: nil) }

  /// Whether TLS is on
  public let enabled: Bool
  /// Adjusts the TLS options before connecting
  public let configure: (@Sendable (NWProtocolTLS.Options) -> Void)?
}

// MARK: - Errors

/// Errors thrown by `NetSocket`
public enum NetSocketError: Error, CustomStringConvertible, Sendable {
  /// The connection isn't ready yet
  case notReady
  /// The connection is closed, by us or the peer
  case closed
  /// The port number is out of range
  case invalidPort
  /// The underlying connection failed
  case failed(underlying: Error)
  /// The connection closed partway through a read of `expected` bytes
  case insufficientData(expected: Int, got: Int)
  /// `max` bytes arrived without a delimiter, or without being read
  case framingExceeded(max: Int)
  /// Received data couldn't be decoded
  case decodeFailed(Error)
  /// Data couldn't be encoded for sending
  case encodeFailed(Error)
  /// A string can't be represented in the requested encoding
  case stringEncodingFailed(String.Encoding)
  /// Received bytes aren't valid in the requested encoding
  case stringDecodingFailed(String.Encoding)
  /// The file to send isn't a regular file, or its size can't be read
  case invalidFile(URL)
  /// The file being sent ended before the expected length
  case fileEndedEarly(expected: Int, got: Int)

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
    case .stringEncodingFailed(let encoding): return "Can't encode string as \(encoding)."
    case .stringDecodingFailed(let encoding): return "Received bytes aren't valid \(encoding)."
    case .invalidFile(let url): return "Not a readable file: \(url.path(percentEncoded: false))."
    case .fileEndedEarly(let exp, let got): return "File ended after \(got) of \(exp) bytes."
    }
  }
}

/// A TCP connection with buffered async reads and writes
///
/// Reads wait until enough data has arrived, so binary protocols can be parsed one field at a
/// time. There are reads and writes for integers, strings, delimited records,
/// `NetSocketDecodable`/`NetSocketEncodable` types, and whole files.
///
/// ```swift
/// let socket = try await NetSocket.connect(host: "example.com", port: 80)
/// try await socket.write("GET / HTTP/1.0\r\n\r\n")
/// let status = try await socket.read(until: .carriageReturnLineFeed)
/// ```
public actor NetSocket {
  /// Socket options
  public struct Config: Sendable {
    /// Most bytes to take from the network per receive (default: 64 KB)
    public var receiveChunk: Int = 64 * 1024
    /// Stop receiving once this many unread bytes are buffered (default: 1 MB)
    ///
    /// Receiving resumes when reads drain the buffer below half of this, or when a read needs
    /// more than is buffered. While paused, TCP flow control slows the sender.
    public var receiveHighWaterMark: Int = 1024 * 1024
    /// Disconnect if more than this many unread bytes are buffered (default: 8 MB)
    ///
    /// Backpressure keeps the buffer near `receiveHighWaterMark`, so this only happens for a
    /// single read larger than the limit, or a delimiter that never arrives.
    public var maxBufferBytes: Int = 8 * 1024 * 1024
    /// Turn on TCP keepalive to detect dead connections (default: false)
    public var enableKeepAlive: Bool = false
    /// Seconds of idle time before the first keepalive probe (default: 60)
    public var keepAliveIdleTime: Int = 60
    public init() {}
  }

  // Connection + state
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "NetSocket.NWConnection")
  private var ready = false
  private var isClosed = false  // Set once by shutdown(); the connection has been cancelled
  private let connectionID: String  // For logging
  
  // Buffer with compaction
  private var buffer = Data()
  private var head = 0 // start of unread bytes
  private let config: Config
  private var receivePaused = false // no receive outstanding because the buffer is full
  
  // Waiters for data/ready, keyed by ID so a cancelled task can remove its own
  private var dataWaiters: [Int: CheckedContinuation<Void, Error>] = [:]
  private var readyWaiters: [Int: CheckedContinuation<Void, Error>] = [:]
  private var nextWaiterID = 0

  // Serialized state update stream
  private var stateContinuation: AsyncStream<NWConnection.State>.Continuation?
  private var stateTask: Task<Void, Never>?

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

  deinit {
    // Safety net for owners that drop the socket without closing it.
    self.stateContinuation?.finish()
    self.connection.cancel()
  }

  // MARK: Connect
  
  /// Connect to a host and wait until the connection is ready
  ///
  /// - Parameters:
  ///   - host: For example `.name("example.com", nil)` or an IP address
  ///   - parameters: Plain TCP by default. Keepalive settings from `config` are applied to it.
  /// - Throws: `NetSocketError.failed` if the connection is refused or fails, or
  ///   `CancellationError` if the task is cancelled first
  public static func connect(host: NWEndpoint.Host, port: NWEndpoint.Port, config: Config = .init(), parameters: NWParameters = .tcp) async throws -> NetSocket {
    if config.enableKeepAlive {
      if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = config.keepAliveIdleTime
      }
    }
    let conn = NWConnection(host: host, port: port, using: parameters)
    let socket = NetSocket(connection: conn, config: config)
    do {
      try await socket.start()
    } catch {
      // Network keeps a refused (.waiting) connection alive and retries it, so cancel it here.
      await socket.close()
      throw error
    }
    return socket
  }

  /// Connect using a host name or IP address string
  public static func connect(host: String, port: UInt16, config: Config = .init()) async throws -> NetSocket {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      throw NetSocketError.invalidPort
    }

    return try await self.connect(host: NWEndpoint.Host(host), port: nwPort, config: config)
  }
  
  // MARK: Close

  /// Close the connection
  ///
  /// Pending reads and writes fail with `NetSocketError.closed`, and unread data is discarded.
  /// Calling it again does nothing. See `forceClose()` to skip waiting for unsent data.
  public func close() {
    self.shutdown(.closed)
    self.discardBuffer()
  }

  /// Close the connection immediately, without waiting for unsent data
  ///
  /// Otherwise the same as `close()`.
  public func forceClose() {
    self.shutdown(.closed, force: true)
    self.discardBuffer()
  }

  // MARK: Send Data

  /// Send bytes, returning once the network stack has taken them
  ///
  /// - Returns: The number of bytes sent
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

  /// Send a fixed-width integer in the given byte order
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
  
  /// Send a Bool as one byte, 1 or 0
  @discardableResult
  public func write(_ value: Bool) async throws -> Int {
    return try await write(UInt8(value ? 0x01 : 0x00))
  }
  
  /// Send a Float's IEEE 754 bit pattern
  @discardableResult
  public func write(_ value: Float, endian: Endian = .big) async throws -> Int {
    return try await write(value.bitPattern, endian: endian)
  }
  
  /// Send a Double's IEEE 754 bit pattern
  @discardableResult
  public func write(_ value: Double, endian: Endian = .big) async throws -> Int {
    return try await write(value.bitPattern, endian: endian)
  }

  /// Send a string's bytes in the given encoding, with no length prefix or terminator
  ///
  /// - Throws: `NetSocketError.stringEncodingFailed` if the string can't be represented in
  ///   `encoding` and `allowLossyConversion` is false
  @discardableResult
  public func write(_ string: String, encoding: String.Encoding = .utf8, allowLossyConversion: Bool = false) async throws -> Int {
    guard let data = string.data(using: encoding, allowLossyConversion: allowLossyConversion) else {
      throw NetSocketError.stringEncodingFailed(encoding)
    }
    return try await write(data)
  }

  // MARK: Receive Data

  /// Read up to the next occurrence of `delimiter`
  ///
  /// The delimiter is always consumed, but only included in the result if `includeDelimiter` is true.
  ///
  /// - Parameter maxBytes: Throw `NetSocketError.framingExceeded` if this many bytes arrive
  ///   without a delimiter
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
      // Throws once the connection has closed and no more data can arrive.
      try await waitForData()
    }
  }

  /// Read exactly `count` bytes, waiting for them to arrive if needed
  ///
  /// - Throws: `NetSocketError.closed` or `NetSocketError.insufficientData` if the connection
  ///   closes before `count` bytes are available
  public func read(_ count: Int) async throws -> Data {
    try await self.ensureReadable(count)
    let start = self.head
    let end = self.head + count
    let slice = self.buffer[start..<end]
    self.head = end
    self.didConsume()
    return Data(slice)
  }
  
  /// Read a fixed-width integer in the given byte order
  public func read<T: FixedWidthInteger>(_ type: T.Type = T.self, endian: Endian = .big) async throws -> T {
    let size = MemoryLayout<T>.size
    let data = try await self.read(size)
    let value: T = data.withUnsafeBytes { raw in
      raw.loadUnaligned(as: T.self)
    }
    switch endian {
    case .big: return T(bigEndian: value)
    case .little: return T(littleEndian: value)
    }
  }

  /// Read `length` bytes and decode them as a string
  ///
  /// - Throws: `NetSocketError.stringDecodingFailed` if the bytes aren't valid in `encoding`
  public func read(_ length: Int, encoding: String.Encoding = .utf8) async throws -> String {
    let data = try await self.read(length)
    guard let s = String(data: data, encoding: encoding) else {
      throw NetSocketError.stringDecodingFailed(encoding)
    }
    return s
  }

  /// Read a UTF-8 string up to the next `delimiter`
  ///
  /// The delimiter and `maxBytes` work the same as in `read(past:maxBytes:includeDelimiter:)`.
  ///
  /// - Throws: `NetSocketError.stringDecodingFailed` if the bytes aren't valid UTF-8
  public func read(until delimiter: Delimiter, maxBytes: Int? = nil, includeDelimiter: Bool = false) async throws -> String {
    let bytes = try await read(past: delimiter.data, maxBytes: maxBytes, includeDelimiter: includeDelimiter)
    guard let s = String(data: bytes, encoding: .utf8) else { throw NetSocketError.stringDecodingFailed(.utf8) }
    return s
  }

  /// Read exactly `count` bytes in chunks, calling `progress` with (bytes so far, total) after each one
  ///
  /// ```swift
  /// let data = try await socket.read(1_000_000) { received, total in
  ///   print("\(received) of \(total)")
  /// }
  /// ```
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
  
  /// Bytes received but not read yet
  public var availableBytes: Int { self.buffer.count - self.head }

  /// The next `count` bytes without consuming them, or nil if fewer are buffered
  public func peek(_ count: Int) -> Data? {
    guard self.availableBytes >= count else {
      return nil
    }
    
    let slice = self.buffer[self.head..<(self.head + count)]
    return Data(slice) // Don't advance head
  }
  
  /// Up to `count` buffered bytes, without consuming them
  public func peek(upto count: Int) -> Data {
    let amount = min(self.availableBytes, count)
    guard amount > 0 else {
      return Data()
    }
    
    let slice = self.buffer[self.head..<(self.head + amount)]
    return Data(slice)
  }
  
  /// The next `count` bytes without consuming them, waiting for them to arrive if needed
  public func peek(awaiting count: Int) async throws -> Data {
    try await self.ensureReadable(count)
    let slice = self.buffer[self.head..<(self.head + count)]
    return Data(slice) // Don't advance head
  }
  
  // MARK: Skip Data
  
  /// Discard exactly `count` bytes
  ///
  /// Bytes are dropped as they arrive, so `count` can be larger than `maxBufferBytes`.
  ///
  /// - Throws: `NetSocketError.closed` if the connection closes before `count` bytes arrive
  public func skip(_ count: Int) async throws {
    var skipped = 0
    while skipped < count {
      try await self.ensureReadable(1)
      // Only advance over bytes that are already buffered, same as read.
      let n = min(count - skipped, self.availableBytes)
      self.head += n
      skipped += n
      self.didConsume()
    }
  }
  
  /// Discard everything up to and including the next occurrence of `delimiter`
  public func skip(past delimiter: Data) async throws {
    while true {
      try Task.checkCancellation()
      if let r = self.search(delimiter: delimiter) {
        self.head = r.upperBound  // Skip to end of delimiter
        self.didConsume()
        return
      }
      // Throws once the connection has closed and no more data can arrive.
      try await self.waitForData()
    }
  }
  
  // MARK: Files
  
  /// Send a file's contents, reporting progress as it goes
  ///
  /// Opens and closes the file itself. The progress stream works the same as in
  /// `writeFile(from:length:chunkSize:)`.
  func writeFile(from url: URL, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    // This stream wrapper manages the FileHandle's lifetime.
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      // Capture self (the actor) to use in detached task
      let actor = self
      
      // Open file on a background thread (file I/O is blocking)
      let task = Task.detached {
        let fh: FileHandle
        let total: Int
        
        // 1. Open file and get length (blocking I/O, done off-actor)
        do {
          total = try NetSocket.fileLength(at: url)
          fh = try FileHandle(forReadingFrom: url)
        } catch {
          continuation.finish(throwing: error)
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
  
  /// Send `length` bytes from an open file, reporting progress as it goes
  ///
  /// The transfer starts when the stream is created, not when it's iterated. Each value carries
  /// the running total. A consumer that falls behind gets the latest value, and always the last
  /// one. Cancel the consuming task to stop the transfer. The caller opens and closes `fileHandle`.
  ///
  /// The stream throws `NetSocketError.fileEndedEarly` if the file is shorter than `length`.
  func writeFile(from fileHandle: FileHandle, length: Int, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    precondition(length >= 0, "length must be >= 0")
    
    if length == 0 {
      return AsyncThrowingStream { continuation in
        continuation.yield(.init(sent: 0, total: 0, bytesPerSecond: 0, estimatedTimeRemaining: 0))
        continuation.finish()
      }
    }
    
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
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
                throw NetSocketError.fileEndedEarly(expected: length, got: estimator.transferred)
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
  
  /// Receive `length` bytes into an open file, reporting progress as it goes
  ///
  /// The progress stream and cancellation work the same as in `writeFile(from:length:chunkSize:)`.
  /// The caller opens and closes `fileHandle`.
  func receiveFile(to fileHandle: FileHandle, length: Int, chunkSize: Int = 256 * 1024) -> AsyncThrowingStream<FileProgress, Error> {
    precondition(length >= 0, "length must be >= 0")
    
    if length == 0 {
      return AsyncThrowingStream { continuation in
        continuation.yield(.init(sent: 0, total: 0, bytesPerSecond: 0, estimatedTimeRemaining: 0))
        continuation.finish()
      }
    }
    
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
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
  
  /// Receive `length` bytes into a file at `url`, without holding the whole file in memory
  ///
  /// `length` has to come from the protocol; nothing is read from the socket to find it. With
  /// `atomic`, data goes to a temporary `.part` file next to `url`, which is renamed into place
  /// when complete and deleted if the transfer fails.
  ///
  /// - Parameters:
  ///   - overwrite: Replace an existing file at `url`
  ///   - progress: Called after each chunk is written
  /// - Returns: The number of bytes written, which is `length` on success
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
        let n = min(chunkSize, remaining)
        let chunk = try await self.read(n)
        try fh.write(contentsOf: chunk)
        remaining -= chunk.count
        written += chunk.count
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
    let (stream, continuation) = AsyncStream.makeStream(of: NWConnection.State.self)
    self.stateContinuation = continuation

    self.connection.stateUpdateHandler = { state in
      continuation.yield(state)
    }

    self.stateTask = Task { [weak self] in
      for await state in stream {
        // Bind self per update so this task never keeps the socket alive between updates.
        guard let self else { return }
        await self.handleStateUpdate(state)
      }
    }

    // Kick off receive loop after .start
    self.connection.start(queue: queue)
    try await self.waitUntilReady()
    self.receiveNext()
  }

  /// Ask the connection for the next chunk. Only one receive is ever outstanding.
  private func receiveNext() {
    guard !self.isClosed else { return }
    self.connection.receive(minimumIncompleteLength: 1, maximumLength: self.config.receiveChunk) { [weak self] data, _, isComplete, error in
      Task {
        await self?.handleReceive(data: data, isComplete: isComplete, error: error)
      }
    }
  }

  private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
    // Buffer data before handling an error or EOF so it can still be read.
    if let data, !data.isEmpty {
      self.append(data, connID: self.connectionID)
    }
    if let error {
      self.shutdown(.failed(underlying: error))
      return
    }
    if isComplete {
      self.shutdown(.closed)
      return
    }

    // Backpressure: stop pulling from the network while the reader catches up.
    if self.availableBytes >= self.config.receiveHighWaterMark {
      self.receivePaused = true
    } else {
      self.receiveNext()
    }
  }

  /// Resume receiving after a pause. `force` is for a read that needs more than is buffered.
  private func resumeReceivingIfNeeded(force: Bool = false) {
    guard self.receivePaused else { return }
    guard force || self.availableBytes < self.config.receiveHighWaterMark / 2 else { return }
    self.receivePaused = false
    self.receiveNext()
  }
  
  private func handleStateUpdate(_ state: NWConnection.State) {
    switch state {
    case .ready:
      self.ready = true
      self.resumeReadyWaiters(with: .success(()))
    case .failed(let error):
      self.shutdown(.failed(underlying: error))
    case .waiting(let error):
      // Fails a pending connect(), which then closes the socket.
      self.resumeReadyWaiters(with: .failure(NetSocketError.failed(underlying: error)))
    case .cancelled:
      self.shutdown(.closed)
    default:
      break
    }
  }

  /// End the connection: cancel it, stop state updates, and fail anything waiting on it
  ///
  /// Every way a connection ends goes through here: close(), the peer closing, a receive error,
  /// a failed state, or a buffer overflow. Later calls do nothing.
  private func shutdown(_ error: NetSocketError, force: Bool = false) {
    guard !self.isClosed else { return }
    self.isClosed = true
    self.stateContinuation?.finish()
    self.stateContinuation = nil
    self.stateTask?.cancel()
    self.stateTask = nil
    if force {
      self.connection.forceCancel()
    } else {
      self.connection.cancel()
    }
    self.failAllWaiters(error)
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
    // Check the buffer before the connection state: bytes the peer sent before closing stay readable.
    while self.availableBytes < count {
      try Task.checkCancellation()
      if self.isClosed {
        // Closed with nothing buffered is a clean end of stream; anything less than `count` was cut short.
        if self.availableBytes == 0 {
          throw NetSocketError.closed
        }
        throw NetSocketError.insufficientData(expected: count, got: self.availableBytes)
      }
      try await self.ensureReady()
      try await self.waitForData()
    }
  }
  
  private func waitForData() async throws {
    // A read needs more than is buffered, so make sure data is flowing even above the high-water mark.
    self.resumeReceivingIfNeeded(force: true)
    try await self.suspend(.data)
  }
  
  /// Call after advancing `head`.
  private func didConsume() {
    self.compactIfNeeded()
    self.resumeReceivingIfNeeded()
  }

  private func compactIfNeeded() {
    // Avoid unbounded memory as head advances
    if self.head > 64 * 1024 && self.head > self.buffer.count / 2 {
      self.buffer.removeSubrange(0..<self.head)
      self.head = 0
    }
  }

  /// Drop unread data so nothing more can be read after our own close().
  private func discardBuffer() {
    self.buffer = Data()
    self.head = 0
  }
  
  private func search(delimiter: Data) -> Range<Int>? {
    guard !delimiter.isEmpty, availableBytes >= delimiter.count else { return nil }
    let hay = buffer[head..<buffer.count]

    // Fast path for single-byte delimiters
    if delimiter.count == 1, let byte = delimiter.first {
      if let idx = hay.firstIndex(of: byte) {
        return idx..<(idx + 1)
      }
      return nil
    }

    // General case
    if let r = hay.firstRange(of: delimiter) {
      return r.lowerBound..<r.upperBound
    }
    
    return nil
  }
  
  private static func fileLength(at url: URL) throws -> Int {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else {
      throw NetSocketError.invalidFile(url)
    }
    if let size = values.fileSize {
      return size
    }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    if let size = attrs[.size] as? NSNumber {
      return size.intValue
    }
    throw NetSocketError.invalidFile(url)
  }
  
  private func waitUntilReady() async throws {
    guard !self.ready else { return }
    try await self.suspend(.ready)
  }

  private enum WaitReason {
    case data
    case ready
  }

  /// Suspend until data arrives or the connection becomes ready.
  ///
  /// Throws `CancellationError` as soon as the calling task is cancelled, and
  /// `NetSocketError.closed` if the connection has already closed.
  private func suspend(_ reason: WaitReason) async throws {
    let id = self.nextWaiterID
    self.nextWaiterID += 1

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          cont.resume(throwing: CancellationError())
        } else if self.isClosed {
          cont.resume(throwing: NetSocketError.closed)
        } else {
          switch reason {
          case .data: self.dataWaiters[id] = cont
          case .ready: self.readyWaiters[id] = cont
          }
        }
      }
    } onCancel: {
      // Runs off the actor, so hop back on. A no-op if the waiter was already resumed.
      Task { await self.cancelWaiter(id) }
    }
  }

  private func cancelWaiter(_ id: Int) {
    let waiter = self.dataWaiters.removeValue(forKey: id) ?? self.readyWaiters.removeValue(forKey: id)
    waiter?.resume(throwing: CancellationError())
  }

  private func resumeReadyWaiters(with result: Result<Void, Error>) {
    let waiters = self.readyWaiters.values
    self.readyWaiters.removeAll()
    for w in waiters {
      w.resume(with: result)
    }
  }

  private func failAllWaiters(_ error: Error) {
    self.resumeReadyWaiters(with: .failure(error))
    let waiters = self.dataWaiters.values
    self.dataWaiters.removeAll()
    for w in waiters {
      w.resume(throwing: error)
    }
  }
  
  private func append(_ data: Data, connID: String) {
    buffer.append(data)
    if buffer.count - head > config.maxBufferBytes {
      // Hard stop: drop connection rather than OOM'ing.
      shutdown(.framingExceeded(max: config.maxBufferBytes))
      return
    }
    resumeDataWaiters()
  }
  
  private func resumeDataWaiters() {
    let waiters = dataWaiters.values
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

/// A message that encodes itself into bytes, sent in one write by `NetSocket.send(_:endian:)`
///
/// ```swift
/// struct Ping: NetSocketEncodable {
///   let id: UInt32
///
///   func encode(endian: Endian) throws -> Data {
///     let value = endian == .big ? id.bigEndian : id.littleEndian
///     return withUnsafeBytes(of: value) { Data($0) }
///   }
/// }
///
/// try await socket.send(Ping(id: 1))
/// ```
public protocol NetSocketEncodable: Sendable {
  /// The whole message as bytes, with multi-byte values in `endian` order
  func encode(endian: Endian) throws -> Data
}

/// A message that decodes itself by reading its fields straight from the socket
///
/// Reads wait for data to arrive, so a message can be parsed one field at a time without
/// knowing its size up front. If decoding throws partway through, the bytes it already read
/// are gone and the stream is out of sync, so the connection should usually be closed.
///
/// ```swift
/// struct Greeting: NetSocketDecodable {
///   let id: UInt32
///   let name: String
///
///   init(from socket: NetSocket, endian: Endian) async throws {
///     self.id = try await socket.read(UInt32.self, endian: endian)
///     let nameLength = try await socket.read(UInt16.self, endian: endian)
///     self.name = try await socket.read(Int(nameLength), encoding: .utf8)
///   }
/// }
///
/// let greeting = try await socket.receive(Greeting.self)
/// ```
public protocol NetSocketDecodable: Sendable {
  /// Read this value's fields from `socket`, with multi-byte values in `endian` order
  init(from socket: NetSocket, endian: Endian) async throws
}

public extension NetSocket {
  /// Encode `value` and send it in one write
  func send<T: NetSocketEncodable>(_ value: T, endian: Endian = .big) async throws {
    let data = try value.encode(endian: endian)
    try await self.write(data)
  }

  /// Read a `T` by letting it decode its own fields from the socket
  func receive<T: NetSocketDecodable>(_ type: T.Type, endian: Endian = .big) async throws -> T {
    return try await T(from: self, endian: endian)
  }
}
