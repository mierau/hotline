// NetSocket FileProgress
// Dustin Mierau • @mierau
// MIT License

import Foundation

public extension NetSocket {
  
  /// Progress of a file transfer
  struct FileProgress: Sendable {
    /// Bytes sent or received so far
    public let sent: Int
    /// Total bytes, if known
    public let total: Int?
    /// Bytes in the most recent chunk
    ///
    /// Progress streams drop updates when the consumer falls behind, so use `sent` for totals.
    public let now: Int
    /// `sent / total` from 0 to 1, or 0 if the total isn't known
    public let progress: Double
    /// Smoothed transfer rate in bytes per second, once there are enough samples
    public let bytesPerSecond: Double?
    /// Estimated seconds remaining, once the rate is known
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(sent: Int, total: Int?, now: Int = 0, bytesPerSecond: Double? = nil, estimatedTimeRemaining: TimeInterval? = nil) {
      self.sent = sent
      self.total = total
      self.now = now
      
      if let t = total {
        self.progress = max(0.0, min(1.0, Double(sent) / Double(t)))
      }
      else {
        self.progress = 0.0
      }
      
      self.bytesPerSecond = bytesPerSecond
      self.estimatedTimeRemaining = estimatedTimeRemaining
    }
    
    /// The transfer rate as a short string like "45KB/sec" or "2.5MB/sec", or nil if it isn't known yet
    public var formattedSpeed: String? {
      guard let bytesPerSecond = bytesPerSecond, bytesPerSecond > 0 else { return nil }
      
      let kb = 1024.0
      let mb = kb * 1024.0
      let gb = mb * 1024.0
      
      if bytesPerSecond >= gb {
        return String(format: "%.1fGB/sec", bytesPerSecond / gb)
      } else if bytesPerSecond >= mb {
        return String(format: "%.1fMB/sec", bytesPerSecond / mb)
      } else if bytesPerSecond >= kb {
        return String(format: "%.0fKB/sec", bytesPerSecond / kb)
      } else {
        return String(format: "%.0fB/sec", bytesPerSecond)
      }
    }
  }
}
