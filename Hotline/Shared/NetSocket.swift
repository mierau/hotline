
// NetSocket.swift
// A simple delegate based buffered read/write TCP socket.
// Created by Dustin Mierau

import Foundation

protocol NetSocketDelegate: AnyObject {
  func netsocketConnected(socket: NetSocket)
  func netsocketDisconnected(socket: NetSocket, error: Error?)
  func netsocketReceived(socket: NetSocket, bytes: [UInt8])
  func netsocketSent(socket: NetSocket, count: Int)
}

extension NetSocketDelegate {
  func netsocketConnected(socket: NetSocket) {}
  func netsocketDisconnected(socket: NetSocket, error: Error?) {}
  func netsocketReceived(socket: NetSocket, bytes: [UInt8]) {}
  func netsocketSent(socket: NetSocket, count: Int) {}
}

enum NetSocketStatus {
  case disconnected
  case connecting
  case connected
}

final class NetSocket: NSObject, StreamDelegate {
  weak var delegate: NetSocketDelegate? = nil
  
  private var output: OutputStream? = nil
  private var input: InputStream? = nil
  
  private var outputBuffer: [UInt8] = []
  private var inputBuffer: [UInt8] = []
  
  private var readBuffer: [UInt8] = Array(repeating: 0, count: 4 * 1024)
  
  public func peek() -> [UInt8] { self.inputBuffer }
  public var available: Int { self.inputBuffer.count }
  
  private var status: NetSocketStatus = .disconnected
  
  override init() {}
  
  @MainActor public func connect(host: String, port: Int) {
    self.close()
    
    var outputStream: OutputStream? = nil
    var inputStream: InputStream? = nil
    
    self.status = .connecting
    
    Stream.getStreamsToHost(withName: host, port: port, inputStream: &inputStream, outputStream: &outputStream)
    
    self.input = inputStream
    self.output = outputStream
    
    inputStream?.delegate = self
    outputStream?.delegate = self
    
    inputStream?.schedule(in: .current, forMode: .common)
    outputStream?.schedule(in: .current, forMode: .common)
    
    inputStream?.open()
    outputStream?.open()
  }
  
  @MainActor public func close(_ err: Error? = nil) {
    let disconnected = (self.status != .disconnected)
    
    self.status = .disconnected
    
    self.input?.delegate = nil
    self.output?.delegate = nil
    self.input?.close()
    self.output?.close()
    self.input?.remove(from: .current, forMode: .common)
    self.output?.remove(from: .current, forMode: .common)
    self.input = nil
    self.output = nil
    self.inputBuffer = []
    self.outputBuffer = []
    
    if disconnected {
      self.delegate?.netsocketDisconnected(socket: self, error: err)
    }
    
    print("NetSocket: Closed")
  }
  
  @MainActor public func write(_ data: Data) {
    guard let output = self.output else {
      return
    }
    
    self.outputBuffer.append(contentsOf: data)
    
    if output.hasSpaceAvailable {
      self.writeBufferToStream()
    }
  }
  
  @MainActor public func write(_ data: [UInt8]) {
    guard let output = self.output else {
      return
    }
    
    self.outputBuffer.append(contentsOf: data)
    
    if output.hasSpaceAvailable {
      self.writeBufferToStream()
    }
  }
  
  @MainActor public func read(count: Int) -> [UInt8] {
    guard self.inputBuffer.count > 0, count > 0 else {
      return []
    }
    
    let amountToRead = min(count, self.inputBuffer.count)
    let dataRead: [UInt8] = Array(self.inputBuffer[0..<amountToRead])
    self.inputBuffer.removeFirst(amountToRead)
    
    return dataRead
  }
  
  @MainActor public func read(count: Int) -> Data {
    guard self.inputBuffer.count > 0, count > 0 else {
      return Data()
    }
    
    let amountToRead = min(count, self.inputBuffer.count)
    
    let dataRead: Data = Data(self.inputBuffer[0..<amountToRead])
    self.inputBuffer.removeFirst(amountToRead)
    
    return dataRead
  }
  
  @MainActor public func readAll() -> [UInt8] {
    guard self.inputBuffer.count > 0 else {
      return []
    }
    
    let dataRead: [UInt8] = Array(self.inputBuffer)
    self.inputBuffer = []
    
    return dataRead
  }
  
  @MainActor public func readAll() -> Data {
    guard self.inputBuffer.count > 0 else {
      return Data()
    }
    
    let dataRead: Data = Data(self.inputBuffer)
    self.inputBuffer = []
    
    return dataRead
  }
  
  @MainActor private func writeBufferToStream() {
    guard let output = self.output, self.outputBuffer.count > 0 else {
      return
    }
    
    let bytesWritten = output.write(self.outputBuffer, maxLength: self.outputBuffer.count)
    if bytesWritten > 0 {
      self.outputBuffer.removeFirst(bytesWritten)
      self.delegate?.netsocketSent(socket: self, count: bytesWritten)
    }
    else if bytesWritten == -1 {
      self.close(output.streamError)
    }
  }
  
  @MainActor private func readStreamToBuffer() {
    guard let input = self.input else {
      return
    }
    
    let bytesRead = input.read(&self.readBuffer, maxLength: self.readBuffer.capacity)
    if bytesRead > 0 {
      self.inputBuffer.append(contentsOf: readBuffer[0..<bytesRead])
      self.delegate?.netsocketReceived(socket: self, bytes: self.inputBuffer)
    }
    else if bytesRead == -1 {
      self.close(input.streamError)
    }
  }
  
  // MARK: -
    
  @MainActor func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    guard let input = self.input, let output = self.output else {
      return
    }
    
    switch eventCode {
    case .openCompleted:
      if input.streamStatus == .open && output.streamStatus == .open {
        if self.status == .connecting {
          print("NetSocket: Connected")
          self.status = .connected
          self.delegate?.netsocketConnected(socket: self)
        }
      }
      break
    case .hasBytesAvailable:
      print("NetSocket: Data available")
      self.readStreamToBuffer()
    case .hasSpaceAvailable:
      print("NetSocket: Space available")
      self.writeBufferToStream()
    case .endEncountered:
      print("NetSocket: End encounterd")
      self.close()
    case .errorOccurred:
      print("NetSocket: Error encounterd", input.streamError.debugDescription, output.streamError.debugDescription)
      let err = input.streamError ?? output.streamError
      self.close(err)
    default:
      break
    }
  }
}
