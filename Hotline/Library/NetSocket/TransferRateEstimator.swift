// NetSocket: TransferRateEstimator
// Dustin Mierau • @mierau
// MIT License

import Foundation

/// Estimates transfer speed and time remaining with an exponential moving average
///
/// Speed and time remaining are only reported after `minElapsedTime` seconds or `minSamples`
/// updates, whichever comes first, since the first few samples are noisy.
///
/// ```swift
/// var estimator = TransferRateEstimator(total: fileSize)
/// for chunk in chunks {
///   let progress = estimator.update(bytes: chunk.count)
///   print(progress.formattedSpeed ?? "--")
/// }
/// ```
public struct TransferRateEstimator {
  /// Total bytes to transfer, if known
  public let total: Int?
  
  /// Moving average of the transfer rate, in bytes per second
  private var emaBytesPerSecond: Double = 0
  
  /// Smoothing factor in (0, 1]; higher follows recent changes more closely
  private let alpha: Double
  
  /// Rate samples taken so far
  private var sampleCount: Int = 0
  
  /// Time of the first update
  private var startTime: ContinuousClock.Instant?
  
  /// Time of the previous update
  private var lastUpdateTime: ContinuousClock.Instant?
  
  /// Seconds before estimates are reported
  private let minElapsedTime: TimeInterval
  
  /// Samples before estimates are reported
  private let minSamples: Int
  
  /// Bytes transferred so far
  public private(set) var transferred: Int = 0
  
  /// - Parameters:
  ///   - total: Total bytes to transfer, if known
  ///   - alpha: Smoothing factor in (0, 1] (default: 0.2)
  ///   - minElapsedTime: Seconds before estimates are reported (default: 2)
  ///   - minSamples: Updates before estimates are reported (default: 8)
  public init(
    total: Int? = nil,
    alpha: Double = 0.2,
    minElapsedTime: TimeInterval = 2.0,
    minSamples: Int = 8
  ) {
    precondition(alpha > 0 && alpha <= 1, "alpha must be in range (0, 1]")
    precondition(minSamples >= 0, "minSamples must be >= 0")
    
    self.total = total
    self.alpha = alpha
    self.minElapsedTime = minElapsedTime
    self.minSamples = minSamples
  }
  
  /// Record that the transfer has reached `total` bytes
  @discardableResult
  public mutating func update(total: Int) -> NetSocket.FileProgress {
    return self.update(bytes: max(0, total - self.transferred))
  }
  
  /// Record `bytes` more transferred since the last update
  ///
  /// - Returns: Progress so far, with speed and time remaining once enough samples are in
  @discardableResult
  public mutating func update(bytes: Int) -> NetSocket.FileProgress {
    let clock = ContinuousClock()
    let now = clock.now
    
    // Record start time on first sample
    if self.startTime == nil {
      self.startTime = now
    }
    
    // Calculate duration since last update
    let duration = self.lastUpdateTime.map { now - $0 } ?? .zero
    self.lastUpdateTime = now
    
    // Update transferred count
    self.transferred += bytes
    
    // Calculate instantaneous rate for this sample
    let seconds: Double = duration / .seconds(1.0)
    if seconds > 0 {
      let instantRate = Double(bytes) / seconds
      self.sampleCount += 1
      
      // Update EMA
      if self.emaBytesPerSecond == 0 {
        self.emaBytesPerSecond = instantRate
      } else {
        self.emaBytesPerSecond += self.alpha * (instantRate - self.emaBytesPerSecond)
      }
    }
    
    // Determine if we have enough data to trust the estimate
    let elapsed = self.startTime.map { now - $0 } ?? .zero
    let elapsedSeconds: Double = elapsed / .seconds(1.0)
    let haveEstimate = (elapsedSeconds >= self.minElapsedTime || self.sampleCount >= self.minSamples) && self.emaBytesPerSecond > 0
    
    // Calculate ETA if we have both an estimate and a known total
    let eta: TimeInterval?
    if haveEstimate, let total = self.total {
      let remaining = total - self.transferred
      eta = remaining > 0 ? TimeInterval(Double(remaining) / self.emaBytesPerSecond) : 0
    } else {
      eta = nil
    }
    
    return NetSocket.FileProgress(
      sent: self.transferred,
      total: self.total,
      now: bytes,
      bytesPerSecond: haveEstimate ? self.emaBytesPerSecond : nil,
      estimatedTimeRemaining: eta
    )
  }
}

