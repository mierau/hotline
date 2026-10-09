import SwiftUI
import UserNotifications

// MARK: - Files & Transfers

extension HotlineState {

  private func postTransferNotification(title: String, body: String, transfer: TransferInfo) {
    #if os(macOS)
    guard Prefs.shared.showTransferNotifications else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if let serverName = transfer.serverName {
      content.subtitle = serverName
    }
    content.sound = .default
    content.userInfo = ["type": "transfer"]

    let request = UNNotificationRequest(
      identifier: "transfer-\(transfer.id)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
    #endif
  }

  @discardableResult
  func getFileList(path: [String] = [], suppressErrors: Bool = false, preferCache: Bool = false) async throws -> [FileInfo]? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    // Check cache first if preferred
    if preferCache, let cached = self.cachedFileList(for: path, ttl: self.fileSearchConfig.cacheTTL, allowStale: false) {
      return cached.items
    }

    let hotlineFiles: [HotlineFile]
    do {
      hotlineFiles = try await client.getFileList(path: path)
    }
    catch let error as HotlineClientError {
      // Not for the folders a search goes through, some of which, like drop boxes, can't be
      // opened, and which it goes on without.
      if !suppressErrors {
        self.displayError(error, message: error.userMessage)
      }
      self.filesLoaded = true
      return nil
    }

    var newFiles = hotlineFiles.map { FileInfo(hotlineFile: $0) }

    // Update UI state
    if path.isEmpty {
      self.filesLoaded = true
      // Preserve existing folder nodes, and what's known of their children, so that deep-linked
      // folders loaded via ensureIntermediateFolders aren't destroyed when the root listing is
      // (re-)fetched.
      newFiles = Self.merged(newFiles, into: self.files)
      self.files = newFiles
    } else {
      // Ensure intermediate folder nodes exist so we can attach children
      self.ensureIntermediateFolders(for: path)

      // Update parent's children
      let parentFile = self.findFile(in: self.files, at: path)
      newFiles = Self.merged(newFiles, into: parentFile?.children)
      parentFile?.children = newFiles
      parentFile?.loaded = true
    }

    // Cache the result
    self.storeFileListInCache(newFiles, for: path)

    return newFiles
  }

  /// Lists folders again, as asked for, as the server has them now, each once, one after another, as
  /// gently on the server as it can be, and not one that's being listed again already, with what
  /// hasn't changed in each kept as it was.
  @MainActor
  func refreshFileLists(_ paths: [[String]]) async {
    var seen: Set<[String]> = []
    for path in paths where seen.insert(path).inserted && !self.refreshingFileLists.contains(path) {
      self.refreshingFileLists.insert(path)
      self.invalidateFileListCache(for: path)
      let _ = try? await self.getFileList(path: path)
      self.refreshingFileLists.remove(path)
    }
  }

  /// A folder's listing, with what hasn't changed since it was last listed kept as it was, so it's
  /// shown, selected and open as it was, rather than all of it shown anew, and only what's changed
  /// is new, though a folder that's changed keeps what's known of what's in it, and whether it's
  /// open.
  private static func merged(_ listed: [FileInfo], into existing: [FileInfo]?) -> [FileInfo] {
    guard let existing, !existing.isEmpty else {
      return listed
    }
    let byName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    return listed.map { file in
      guard let old = byName[file.name], old.isFolder == file.isFolder else {
        return file
      }
      if old.type == file.type, old.creator == file.creator, old.fileSize == file.fileSize, old.isUnavailable == file.isUnavailable {
        return old
      }
      if file.isFolder {
        file.children = old.children
        file.loaded = old.loaded
        file.expanded = old.expanded
      }
      return file
    }
  }

  func getFileDetails(_ fileName: String, path: [String]) async throws -> FileDetails? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    return try await client.getFileInfo(name: fileName, path: fullPath)
  }

  @discardableResult
  func setFileInfo(fileName: String, path filePath: [String], fileNewName: String?, comment: String?) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    do {
      try await client.setFileInfo(name: fileName, path: filePath, newName: fileNewName, comment: comment)
      self.invalidateFileListCache(for: filePath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }

    return false
  }

  @discardableResult
  func newFolder(name: String, parentPath: [String]) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    do {
      try await client.newFolder(name: name, path: parentPath)
      self.invalidateFileListCache(for: parentPath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }

    return false
  }

  @discardableResult
  @MainActor
  func deleteFile(_ fileName: String, path: [String]) async throws -> Bool {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    do {
      try await client.deleteFile(name: fileName, path: fullPath)
      self.invalidateFileListCache(for: fullPath, includingAncestors: true)
      return true
    }
    catch let error as HotlineClientError {
      self.displayError(error, message: error.userMessage)
    }

    return false
  }

  /// Download a file from the server.
  ///
  /// - Parameters:
  ///   - fileName: Name of the file to download
  ///   - path: Path components to the file (includes the filename as last component)
  ///   - destination: Optional destination URL. If nil, downloads to Downloads folder.
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo and progress 0.0-1.0)
  ///   - callback: Optional completion callback (receives TransferInfo and final file URL)
  ///   - transfer: How it's been shown, waiting its turn, if it has, to start, rather than a new one
  ///   - failureCallback: Optional callback for when it doesn't download, once, with why
  @MainActor
  func downloadFile(_ fileName: String, path: [String], to destination: URL? = nil, transfer queued: TransferInfo? = nil, progress progressCallback: ((TransferInfo) -> Void)? = nil, complete callback: ((TransferInfo) -> Void)? = nil, failed failureCallback: ((Error) -> Void)? = nil) {
    // Shown failed, if it was shown waiting, and why, once.
    func fail(_ error: Error) {
      queued?.waiting = false
      queued?.failed = true
      failureCallback?(error)
    }

    guard let client = self.client else {
      fail(HotlineClientError.notConnected)
      return
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor [weak self] in
      guard let self else {
        fail(CancellationError())
        return
      }

      // Request download from server
      let result: (referenceNumber: UInt32, transferSize: Int, fileSize: Int, waitingCount: Int)?
      do {
        result = try await client.downloadFile(name: fileName, path: fullPath)
      }
      catch {
        self.displayError(error, message: (error as? HotlineClientError)?.userMessage)
        fail(error)
        return
      }

      guard let result,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        fail(HotlineClientError.invalidResponse)
        return
      }

      let referenceNumber = result.referenceNumber

      // Create transfer info for tracking (stored globally in AppState), or start the one shown
      // waiting for its turn.
      let transfer = queued ?? TransferInfo(
        reference: referenceNumber,
        title: fileName,
        size: UInt(result.transferSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.referenceNumber = referenceNumber
      transfer.size = UInt(result.transferSize)
      transfer.waiting = false
      transfer.isUpload = false
      transfer.downloadCallback = callback
      transfer.progressCallback = progressCallback
      if queued == nil {
        AppState.shared.addTransfer(transfer)
      }

      // Create download client
      let downloadClient = HotlineFileDownloadClient(
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        size: UInt32(result.transferSize)
      )

      // Create and store the download task
      let downloadTask = Task { @MainActor [weak self] in
        guard self != nil else {
          failureCallback?(CancellationError())
          return
        }

        do {
          // Download file with progress tracking
          let location: HotlineDownloadLocation = if let destination {
            .url(destination)
          } else {
            .url(Prefs.shared.resolvedDownloadFolder.generateUniqueFileURL(filename: fileName))
          }

          let fileURL: URL = try await downloadClient.download(to: location) { progress in
            switch progress {
            case .preparing: break
            case .unconnected, .connected, .connecting:
              transfer.progressCallback?(transfer)
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: let url):
              transfer.completed = true
              transfer.fileURL = url
            }
          }

          // Mark as completed
          transfer.progress = 1.0

          // Call completion callback
          transfer.downloadCallback?(transfer)
          fileURL.notifyDownloadFinished()

          self?.postTransferNotification(title: "Download Complete", body: fileName, transfer: transfer)
          if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
            SoundEffects.play(.transferComplete)
          }

          print("HotlineState: Download complete - \(fileURL.path)")

        } catch is CancellationError {
          // Download was cancelled, from the transfers list, or the Finder, and comes off the list,
          // as the list's own button takes it off.
          transfer.cancelled = true
          AppState.shared.cancelTransfer(id: transfer.id)
          failureCallback?(CancellationError())
          print("HotlineState: Download cancelled")

        } catch {
          // Mark as failed
          transfer.failed = true
          failureCallback?(error)
          self?.postTransferNotification(title: "Download Failed", body: fileName, transfer: transfer)
          print("HotlineState: Download failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the task in AppState so it can be cancelled later
      AppState.shared.registerTransferTask(downloadTask, transferID: transfer.id, client: downloadClient)
    }
  }

  /// Download a folder and its contents from the server.
  ///
  /// - Parameters:
  ///   - folderName: Name of the folder to download
  ///   - path: Path components to the folder (includes the foldername as last component)
  ///   - destination: Optional destination URL. If nil, downloads to Downloads folder.
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo)
  ///   - callback: Optional completion callback (receives TransferInfo and final folder URL)
  ///   - transfer: How it's been shown, waiting its turn, if it has, to start, rather than a new one
  ///   - failureCallback: Optional callback for when it doesn't download, once, with why
  @MainActor
  func downloadFolder(
    _ folderName: String,
    path: [String],
    to destination: URL? = nil,
    transfer queued: TransferInfo? = nil,
    progress progressCallback: ((TransferInfo) -> Void)? = nil,
//    itemProgress itemProgressCallback: ((TransferInfo, String, Int, Int) -> Void)? = nil,
    complete callback: ((TransferInfo) -> Void)? = nil,
    failed failureCallback: ((Error) -> Void)? = nil
  ) {
    // Shown failed, if it was shown waiting, and why, once.
    func fail(_ error: Error) {
      queued?.waiting = false
      queued?.failed = true
      failureCallback?(error)
    }

    guard let client = self.client else {
      fail(HotlineClientError.notConnected)
      return
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor [weak self] in
      guard let self else {
        fail(CancellationError())
        return
      }

      // Request folder download from server, saying why it won't, as for a file.
      let result: (referenceNumber: UInt32, transferSize: Int, itemCount: Int, waitingCount: Int)?
      do {
        result = try await client.downloadFolder(name: folderName, path: fullPath)
      }
      catch {
        self.displayError(error, message: (error as? HotlineClientError)?.userMessage)
        fail(error)
        return
      }

      guard let result,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        fail(HotlineClientError.invalidResponse)
        return
      }

      let referenceNumber = result.referenceNumber

      // Create transfer info for tracking (stored globally in AppState), or start the one shown
      // waiting for its turn.
      let transfer = queued ?? TransferInfo(
        reference: referenceNumber,
        title: folderName,
        size: UInt(result.transferSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.referenceNumber = referenceNumber
      transfer.size = UInt(result.transferSize)
      transfer.waiting = false
      transfer.isFolder = true
      transfer.folderName = folderName
      transfer.isUpload = false
      transfer.downloadCallback = callback
      transfer.progressCallback = progressCallback
      if queued == nil {
        AppState.shared.addTransfer(transfer)
      }

      // Create download client
      let downloadClient = HotlineFolderDownloadClient(
        address: address,
        port: UInt16(port),
        reference: referenceNumber,
        size: UInt32(result.transferSize),
        itemCount: result.itemCount
      )

      // Create and store the download task
      let downloadTask = Task { @MainActor [weak self] in
        guard self != nil else {
          failureCallback?(CancellationError())
          return
        }

        do {
          // Download folder with progress tracking
          let location: HotlineDownloadLocation = if let destination {
            .url(destination)
          } else {
            .url(Prefs.shared.resolvedDownloadFolder.generateUniqueFileURL(filename: folderName))
          }

          let folderURL = try await downloadClient.download(to: location, progress: { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              transfer.progressCallback?(transfer)
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: let url):
              transfer.completed = true
              transfer.fileURL = url
            }
          }, items: { item in
            transfer.title = item.fileName
            transfer.fileName = item.fileName
          })

          // Mark as completed
          transfer.progress = 1.0
          transfer.fileName = nil
          transfer.title = folderName // Reset title to folder name

          // Call completion callback
          transfer.downloadCallback?(transfer)

          folderURL.notifyDownloadFinished()

          self?.postTransferNotification(title: "Download Complete", body: folderName, transfer: transfer)
          if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
            SoundEffects.play(.transferComplete)
          }

          print("HotlineState: Folder download complete - \(folderURL.path)")

        } catch is CancellationError {
          // Download was cancelled, from the transfers list, or the Finder, and comes off the list,
          // as the list's own button takes it off.
          transfer.cancelled = true
          AppState.shared.cancelTransfer(id: transfer.id)
          failureCallback?(CancellationError())
          print("HotlineState: Folder download cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          failureCallback?(error)
          self?.postTransferNotification(title: "Download Failed", body: folderName, transfer: transfer)
          print("HotlineState: Folder download failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store transfer, with what downloads it, for stopping it to stop that, which the task
      // being cancelled doesn't, as it's waiting on one of the client's own.
      AppState.shared.registerTransferTask(downloadTask, transferID: transfer.id, client: downloadClient)
    }
  }

  /// Upload a folder to the server.
  ///
  /// - Parameters:
  ///   - folderURL: URL to the folder on disk to upload
  ///   - path: Destination path on the server where the folder should be uploaded
  ///   - progressCallback: Optional callback for progress updates (receives TransferInfo)
  ///   - itemProgressCallback: Optional callback for per-item updates (receives TransferInfo with current file info)
  ///   - callback: Optional completion callback (receives TransferInfo when upload is complete)
  ///   - transfer: How it's been shown, waiting its turn, if it has, to start, rather than a new one
  ///   - failureCallback: Optional callback for when it doesn't upload, once, with why
  @MainActor
  func uploadFolder(
    url folderURL: URL,
    path: [String],
    progress progressCallback: ((TransferInfo) -> Void)? = nil,
    itemProgress itemProgressCallback: ((TransferInfo, String, Int, Int) -> Void)? = nil,
    complete callback: ((TransferInfo) -> Void)? = nil,
    transfer queued: TransferInfo? = nil,
    failed failureCallback: ((Error) -> Void)? = nil
  ) {
    // Shown failed, if it was shown waiting, and why, once.
    func fail(_ error: Error) {
      queued?.waiting = false
      queued?.failed = true
      failureCallback?(error)
    }

    guard let client = self.client else {
      fail(HotlineClientError.notConnected)
      return
    }

    let folderName = folderURL.lastPathComponent

    guard folderURL.isFileURL, !folderName.isEmpty else {
      print("HotlineState: Not a valid folder URL")
      fail(CocoaError(.fileReadInvalidFileName))
      return
    }

    let folderPath = folderURL.path(percentEncoded: false)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDirectory),
          isDirectory.boolValue == true else {
      print("HotlineState: URL is not a folder")
      fail(CocoaError(.fileReadNoSuchFile))
      return
    }

    // Get the total size of the folder (all files)
    guard let (folderSize, fileCount) = FileManager.default.getFolderSize(folderURL) else {
      print("HotlineState: Could not determine folder size")
      fail(CocoaError(.fileReadUnknown))
      return
    }

    print("HotlineState: Requesting upload for folder '\(folderName)' - \(fileCount) items, \(folderSize) bytes total")

    Task { @MainActor [weak self] in
      guard let self else {
        fail(CancellationError())
        return
      }

      // Request folder upload from server.
      // The enumerator already omits the root folder, so report the full item count the server should expect.
      let reportedItemCount = fileCount
      print("HotlineState: Reporting \(reportedItemCount) items to server (enumerated count)")
      // Saying why the server won't take it, as for a file.
      let reference: UInt32?
      do {
        reference = try await client.uploadFolder(name: folderName, path: path, fileCount: reportedItemCount, totalSize: UInt32(folderSize))
      }
      catch {
        self.displayError(error, message: (error as? HotlineClientError)?.userMessage)
        fail(error)
        return
      }
      guard let referenceNumber = reference,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        print("HotlineState: Failed to get upload reference from server")
        fail(HotlineClientError.invalidResponse)
        return
      }

      // Invalidate cache for the upload destination
      self.invalidateFileListCache(for: path, includingAncestors: true)

      print("HotlineState: Got folder upload reference: \(referenceNumber)")

      // Create upload client
      guard let uploadClient = HotlineFolderUploadClient(
        folderURL: folderURL,
        address: address,
        port: UInt16(port),
        reference: referenceNumber
      ) else {
        print("HotlineState: Failed to create folder upload client")
        fail(HotlineTransferClientError.failedToTransfer)
        return
      }

      // Create transfer info for tracking (stored globally in AppState), or start the one shown
      // waiting for its turn.
      let transfer = queued ?? TransferInfo(
        reference: referenceNumber,
        title: folderName,
        size: UInt(folderSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.referenceNumber = referenceNumber
      transfer.size = UInt(folderSize)
      transfer.waiting = false
      transfer.isFolder = true
      transfer.isUpload = true
      transfer.uploadCallback = callback
      transfer.progressCallback = progressCallback
      if queued == nil {
        AppState.shared.addTransfer(transfer)
      }

      // Create and store the upload task
      let uploadTask = Task { @MainActor [weak self] in
        guard self != nil else {
          failureCallback?(CancellationError())
          return
        }

        do {
          // Upload folder with progress tracking
          try await uploadClient.upload(progress: { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              break
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
              transfer.progressCallback?(transfer)
            case .error(_):
              transfer.failed = true
            case .completed(url: _):
              transfer.completed = true
            }
          }, itemProgress: { itemInfo in
            // Update transfer title with current file being uploaded
            transfer.title = "\(itemInfo.fileName) (\(itemInfo.itemNumber)/\(itemInfo.totalItems))"
            itemProgressCallback?(transfer, itemInfo.fileName, itemInfo.itemNumber, itemInfo.totalItems)
          })

          // Mark as completed
          transfer.progress = 1.0
          transfer.title = folderName // Reset title to folder name

          // Call completion callback
          transfer.uploadCallback?(transfer)

          self?.postTransferNotification(title: "Upload Complete", body: folderName, transfer: transfer)
          if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
            SoundEffects.play(.transferComplete)
          }

          print("HotlineState: Folder upload complete - \(folderName)")

        } catch is CancellationError {
          // Upload was cancelled, from the transfers list, or the Finder, and comes off the list, as
          // the list's own button takes it off.
          transfer.cancelled = true
          AppState.shared.cancelTransfer(id: transfer.id)
          failureCallback?(CancellationError())
          print("HotlineState: Folder upload cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          failureCallback?(error)
          self?.postTransferNotification(title: "Upload Failed", body: folderName, transfer: transfer)
          print("HotlineState: Folder upload failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the task in AppState so it can be cancelled later, with what uploads it, for stopping it
      // to stop that, which the task being cancelled doesn't, as it's waiting on one of the client's
      // own.
      AppState.shared.registerTransferTask(uploadTask, transferID: transfer.id, client: uploadClient)
    }
  }

  /// Upload a file to the server.
  ///
  /// - Parameters:
  ///   - transfer: How it's been shown, waiting its turn, if it has, to start, rather than a new one
  ///   - failureCallback: Optional callback for when it doesn't upload, once, with why
  func uploadFile(url fileURL: URL, path: [String], transfer queued: TransferInfo? = nil, complete callback: ((TransferInfo) -> Void)? = nil, failed failureCallback: ((Error) -> Void)? = nil) {
    // Shown failed, if it was shown waiting, and why, once.
    func fail(_ error: Error) {
      queued?.waiting = false
      queued?.failed = true
      failureCallback?(error)
    }

    guard let client = self.client else {
      fail(HotlineClientError.notConnected)
      return
    }

    let fileName = fileURL.lastPathComponent

    print("UPLOAD FILE: \(fileName) \(fileURL)")

    guard fileURL.isFileURL, !fileName.isEmpty else {
      print("HotlineState: Not a valid file URL")
      fail(CocoaError(.fileReadInvalidFileName))
      return
    }

    let filePath = fileURL.path(percentEncoded: false)

    var fileIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: filePath, isDirectory: &fileIsDirectory),
          fileIsDirectory.boolValue == false else {
      print("HotlineState: File is a directory")
      fail(CocoaError(.fileReadNoSuchFile))
      return
    }

    // Get the flattened file size (includes all forks and headers)
    guard let payloadSize = FileManager.default.getFlattenedFileSize(fileURL) else {
      print("HotlineState: Could not determine file size")
      fail(CocoaError(.fileReadUnknown))
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        fail(CancellationError())
        return
      }

      let referenceNumber: UInt32?

      do {
        referenceNumber = try await client.uploadFile(name: fileName, path: path)
      }
      catch {
        self.displayError(error, message: (error as? HotlineClientError)?.userMessage)
        fail(error)
        return
      }


      // Request upload from server
      guard let referenceNumber,
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        print("HotlineState: Failed to get upload reference from server")
        fail(HotlineClientError.invalidResponse)
        return
      }

      // Invalidate cache for the upload destination
      self.invalidateFileListCache(for: path, includingAncestors: true)

      print("HotlineState: Got upload reference: \(referenceNumber)")

      // Create upload client
      guard let uploadClient = HotlineFileUploadClient(
        fileURL: fileURL,
        address: address,
        port: UInt16(port),
        reference: referenceNumber
      ) else {
        print("HotlineState: Failed to create upload client")
        fail(HotlineTransferClientError.failedToTransfer)
        return
      }

      // Create transfer info for tracking (stored globally in AppState), or start the one shown
      // waiting for its turn.
      let transfer = queued ?? TransferInfo(
        reference: referenceNumber,
        title: fileName,
        size: UInt(payloadSize),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.referenceNumber = referenceNumber
      transfer.size = UInt(payloadSize)
      transfer.waiting = false
      transfer.isUpload = true
      transfer.uploadCallback = callback
      if queued == nil {
        AppState.shared.addTransfer(transfer)
      }

      // Create and store the upload task
      let uploadTask = Task { @MainActor [weak self] in
        guard self != nil else {
          failureCallback?(CancellationError())
          return
        }

        do {
          // Upload file with progress tracking
          try await uploadClient.upload { progress in
            switch progress {
            case .preparing:
              break
            case .unconnected, .connected, .connecting:
              break
            case .transfer(name: _, size: _, total: _, progress: let progress, speed: let speed, estimate: let estimate):
              transfer.timeRemaining = estimate
              transfer.speed = speed
              transfer.progress = progress
            case .error(_):
              transfer.failed = true
            case .completed(url: _):
              transfer.completed = true
            }
          }

          // Mark as completed
          transfer.progress = 1.0

          // Call completion callback
          transfer.uploadCallback?(transfer)

          self?.postTransferNotification(title: "Upload Complete", body: fileName, transfer: transfer)
          if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
            SoundEffects.play(.transferComplete)
          }

          print("HotlineState: Upload complete - \(fileName)")

        } catch is CancellationError {
          // Upload was cancelled, from the transfers list, and comes off it, as the list's own button
          // takes it off.
          transfer.cancelled = true
          AppState.shared.cancelTransfer(id: transfer.id)
          failureCallback?(CancellationError())
          print("HotlineState: Upload cancelled")
        } catch {
          // Mark as failed
          transfer.failed = true
          failureCallback?(error)
          self?.postTransferNotification(title: "Upload Failed", body: fileName, transfer: transfer)
          print("HotlineState: Upload failed - \(error)")
        }

        AppState.shared.unregisterTransferTask(for: transfer.id)
      }

      // Store the transfer, with what uploads it, for stopping it to stop that
      AppState.shared.registerTransferTask(uploadTask, transferID: transfer.id, client: uploadClient)
    }
  }

  /// Uploads files and folders to a folder on the server, one after another, in turn, as some
  /// servers take only so many at once from each person, and turn away the rest. Each is in the
  /// transfers list from the start, waiting its turn, and the folder's listed again as each gets
  /// there.
  @MainActor
  func enqueueUploads(_ fileURLs: [URL], to path: [String]) {
    for fileURL in fileURLs {
      var isFolder: ObjCBool = false
      guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false), isDirectory: &isFolder) else {
        continue
      }
      let transfer = TransferInfo(
        reference: 0,
        title: fileURL.lastPathComponent,
        size: isFolder.boolValue ? 0 : UInt(FileManager.default.getFlattenedFileSize(fileURL) ?? 0),
        serverID: self.id,
        serverName: self.serverName ?? self.serverTitle
      )
      transfer.isUpload = true
      transfer.isFolder = isFolder.boolValue
      transfer.waiting = true
      AppState.shared.addTransfer(transfer)
      self.queuedUploads.append((fileURL, path, transfer))
    }

    guard self.uploadQueue == nil else {
      return
    }
    self.uploadQueue = Task { @MainActor [weak self] in
      while let self, !self.queuedUploads.isEmpty {
        let upload = self.queuedUploads.removeFirst()
        // Not one taken off the transfers list while it waited.
        guard AppState.shared.transfers.contains(where: { $0.id == upload.transfer.id }) else {
          continue
        }
        if await self.upload(upload.fileURL, to: upload.path, as: upload.transfer) {
          let _ = try? await self.getFileList(path: upload.path)
        }
      }
      self?.uploadQueue = nil
    }
  }

  /// A download waiting its turn: what it is, where it goes, how it's shown, and who's told once it's
  /// done.
  struct QueuedDownload {
    let name: String
    let path: [String]
    let isFolder: Bool
    let destination: URL?
    let transfer: TransferInfo
    let finished: ((Error?) -> Void)?
  }

  /// Downloads files and folders one after another, as uploads go, each in the transfers list from
  /// the start, waiting its turn, to where it's asked for, or the downloads folder, and says when
  /// each is there, or why it isn't, as for one dropped on the Finder, which waits to be told.
  @MainActor
  func enqueueDownload(_ file: FileInfo, to destination: URL? = nil, finished: ((Error?) -> Void)? = nil) {
    let transfer = TransferInfo(
      reference: 0,
      title: file.name,
      size: file.isFolder ? 0 : file.fileSize,
      serverID: self.id,
      serverName: self.serverName ?? self.serverTitle
    )
    transfer.isFolder = file.isFolder
    transfer.folderName = file.isFolder ? file.name : nil
    transfer.waiting = true
    AppState.shared.addTransfer(transfer)
    self.queuedDownloads.append(QueuedDownload(name: file.name, path: file.path, isFolder: file.isFolder, destination: destination, transfer: transfer, finished: finished))

    guard self.downloadQueue == nil else {
      return
    }
    self.downloadQueue = Task { @MainActor [weak self] in
      while let self, !self.queuedDownloads.isEmpty {
        let download = self.queuedDownloads.removeFirst()
        // Not one taken off the transfers list while it waited.
        guard AppState.shared.transfers.contains(where: { $0.id == download.transfer.id }) else {
          download.finished?(CancellationError())
          continue
        }
        download.finished?(await self.download(download))
      }
      self?.downloadQueue = nil
    }
  }

  /// Downloads one that's had its turn, and says, once it's done, why it didn't get there, if it
  /// didn't.
  @MainActor
  private func download(_ download: QueuedDownload) async -> Error? {
    await withCheckedContinuation { continuation in
      if download.isFolder {
        self.downloadFolder(download.name, path: download.path, to: download.destination, transfer: download.transfer, complete: { _ in continuation.resume(returning: nil) }, failed: { continuation.resume(returning: $0) })
      }
      else {
        self.downloadFile(download.name, path: download.path, to: download.destination, transfer: download.transfer, complete: { _ in continuation.resume(returning: nil) }, failed: { continuation.resume(returning: $0) })
      }
    }
  }

  /// Moves files and folders, by where they are, into a folder on the server, one after another,
  /// but not one into itself, or where it is already, and lists again where they were and where
  /// they've gone, and what those are in, whose counts of what's in them change.
  @MainActor
  func moveItems(at paths: [[String]], to folder: [String]) async {
    guard let client = self.client else {
      return
    }
    var changed: Set<[String]> = []
    var failure: Error?
    // Not what's in a folder that's moved too, which goes along with it.
    let paths = paths.filter { path in !paths.contains { $0.count < path.count && path.starts(with: $0) } }
    for path in paths {
      guard let name = path.last else {
        continue
      }
      let parent = Array(path.dropLast())
      guard parent != folder, !folder.starts(with: path) else {
        continue
      }
      do {
        try await client.moveFile(name: name, path: parent, to: folder)
        changed.formUnion([parent, folder])
      }
      catch {
        failure = failure ?? error
      }
    }
    // Why the first that couldn't be moved wasn't, once, and not for each.
    if let failure {
      self.displayError(failure, message: (failure as? HotlineClientError)?.userMessage)
    }
    for path in changed.union(changed.filter { !$0.isEmpty }.map { Array($0.dropLast()) }) {
      self.invalidateFileListCache(for: path)
      let _ = try? await self.getFileList(path: path)
    }
  }

  /// Uploads one that's had its turn, and says, once it's done, whether it got there.
  @MainActor
  private func upload(_ fileURL: URL, to path: [String], as transfer: TransferInfo) async -> Bool {
    await withCheckedContinuation { continuation in
      if transfer.isFolder {
        self.uploadFolder(url: fileURL, path: path, complete: { _ in continuation.resume(returning: true) }, transfer: transfer, failed: { _ in continuation.resume(returning: false) })
      }
      else {
        self.uploadFile(url: fileURL, path: path, transfer: transfer, complete: { _ in continuation.resume(returning: true) }, failed: { _ in continuation.resume(returning: false) })
      }
    }
  }

  @MainActor
  func previewFile(_ fileName: String, path: [String], complete callback: ((PreviewFileInfo?) -> Void)? = nil) {
    guard let client = self.client else {
      callback?(nil)
      return
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    Task { @MainActor in
      guard let result = try? await client.downloadFile(name: fileName, path: fullPath, preview: true),
            let server = self.server,
            let address = server.address as String?,
            let port = server.port as Int?
      else {
        callback?(nil)
        return
      }

      let info = PreviewFileInfo(
        id: result.referenceNumber,
        address: address,
        port: port,
        size: result.transferSize,
        name: fileName
      )

      callback?(info)
    }
  }

  /// Part of a file, without downloading all of it: up to `length` bytes of its data fork from
  /// `offset`, and the size the transfer gives the data fork, which is all of it from the start.
  /// From anywhere else, servers differ on what they give.
  @MainActor
  func readFile(_ fileName: String, path: [String], from offset: Int, length: Int) async throws -> (data: Data, size: Int) {
    guard let client = self.client, let server = self.server else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    print("HotlineState: Reading \(length) bytes of \(fileName) from \(offset)")
    guard let transfer = try await client.downloadFile(name: fileName, path: fullPath, dataOffset: offset) else {
      throw HotlineClientError.invalidResponse
    }
    print("HotlineState: Transfer \(transfer.referenceNumber) for \(fileName), transfer size \(transfer.transferSize), file size \(transfer.fileSize), waiting \(transfer.waitingCount)")
    let reader = HotlineFilePreviewClient(
      fileName: fileName,
      address: server.address,
      port: UInt16(server.port),
      reference: transfer.referenceNumber,
      size: UInt32(clamping: transfer.transferSize)
    )
    return try await reader.read(upTo: length)
  }

  /// A file's resource fork, up to `limit` bytes of it, without its data fork, which is
  /// `dataForkSize` long.
  @MainActor
  func readResourceFork(_ fileName: String, path: [String], dataForkSize: Int, limit: Int) async throws -> Data {
    guard let client = self.client, let server = self.server else {
      throw HotlineClientError.notConnected
    }

    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }

    print("HotlineState: Reading the resource fork of \(fileName), after its \(dataForkSize)-byte data fork")
    guard let transfer = try await client.downloadFile(name: fileName, path: fullPath, dataOffset: dataForkSize) else {
      throw HotlineClientError.invalidResponse
    }
    print("HotlineState: Transfer \(transfer.referenceNumber) for \(fileName), transfer size \(transfer.transferSize), file size \(transfer.fileSize), waiting \(transfer.waitingCount)")
    let reader = HotlineFilePreviewClient(
      fileName: fileName,
      address: server.address,
      port: UInt16(server.port),
      reference: transfer.referenceNumber,
      size: UInt32(clamping: transfer.transferSize)
    )
    return try await reader.readResourceFork(upTo: limit)
  }

  // MARK: - File Search

  @MainActor
  func startFileSearch(query: String, startPath: [String] = []) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      self.cancelFileSearch()
      return
    }

    self.fileSearchSession?.cancel()
    self.resetFileSearchState()
    self.fileSearchQuery = trimmed
    self.fileSearchStatus = .searching(processed: 0, pending: 0)
    self.fileSearchScannedFolders = 0
    self.fileSearchCurrentPath = []

    let session = HotlineStateFileSearchSession(hotlineState: self, query: trimmed, config: self.fileSearchConfig, startPath: startPath)
    self.fileSearchSession = session

    Task { await session.start() }
  }

  @MainActor
  func cancelFileSearch(clearResults: Bool = true) {
    guard let session = self.fileSearchSession else {
      if clearResults {
        self.resetFileSearchState()
      } else if !self.fileSearchResults.isEmpty {
        self.fileSearchStatus = .cancelled(processed: self.fileSearchScannedFolders)
        self.fileSearchCurrentPath = nil
      }
      return
    }

    session.cancel()
    self.fileSearchSession = nil
    self.fileSearchCurrentPath = nil

    if clearResults {
      self.resetFileSearchState()
    } else {
      self.fileSearchStatus = .cancelled(processed: self.fileSearchScannedFolders)
    }
  }

  @MainActor
  func clearFileListCache() {
    guard !self.fileListCache.isEmpty else {
      return
    }

    self.fileListCache.removeAll(keepingCapacity: false)
  }

  @MainActor
  fileprivate func searchSession(_ session: HotlineStateFileSearchSession, didEmit matches: [FileInfo], processed: Int, pending: Int) {
    guard self.fileSearchSession === session else {
      return
    }

    var appended: [FileInfo] = []
    for match in matches {
      let key = self.searchPathKey(for: match.path)
      if self.fileSearchResultKeys.insert(key).inserted {
        appended.append(match)
      }
    }

    if !appended.isEmpty {
      self.fileSearchResults.append(contentsOf: appended)
    }

    self.fileSearchScannedFolders = processed
    self.fileSearchStatus = .searching(processed: processed, pending: pending)
  }

  @MainActor
  fileprivate func searchSession(_ session: HotlineStateFileSearchSession, didFocusOn path: [String]) {
    guard self.fileSearchSession === session else {
      return
    }

    self.fileSearchCurrentPath = path
  }

  @MainActor
  fileprivate func searchSessionDidFinish(_ session: HotlineStateFileSearchSession, processed: Int, pending: Int, completed: Bool) {
    guard self.fileSearchSession === session else {
      return
    }

    self.fileSearchScannedFolders = processed
    self.fileSearchSession = nil
    self.fileSearchCurrentPath = nil

    if completed {
      self.fileSearchStatus = .completed(processed: processed)
    } else {
      self.fileSearchStatus = .cancelled(processed: processed)
    }
  }

  fileprivate func cachedListingForSearch(path: [String], ttl: TimeInterval) -> (items: [FileInfo], isFresh: Bool)? {
    self.cachedFileList(for: path, ttl: ttl, allowStale: true)
  }

  // MARK: - File Tree Helpers

  /// Ensures that each folder in `path` exists in the file tree,
  /// creating placeholder folder nodes where needed so that
  /// `findFile(in:at:)` can reach the deepest level.
  private func ensureIntermediateFolders(for path: [String]) {
    var currentFiles = self.files
    var currentList: (get: () -> [FileInfo], set: ([FileInfo]) -> Void) = (
      get: { self.files },
      set: { self.files = $0 }
    )

    for i in 0..<path.count {
      let name = path[i]
      if let existing = currentFiles.first(where: { $0.name == name && $0.isFolder }) {
        if existing.children == nil {
          existing.children = []
        }
        let parent = existing
        currentList = (
          get: { parent.children ?? [] },
          set: { parent.children = $0 }
        )
        currentFiles = existing.children ?? []
      } else {
        // Create a placeholder folder
        let folderPath = Array(path.prefix(i + 1))
        let placeholder = FileInfo(folderName: name, path: folderPath)
        var list = currentList.get()
        list.append(placeholder)
        currentList.set(list)
        let parent = placeholder
        currentList = (
          get: { parent.children ?? [] },
          set: { parent.children = $0 }
        )
        currentFiles = []
      }
    }
  }

  private func findFile(in filesToSearch: [FileInfo], at path: [String]) -> FileInfo? {
    guard !path.isEmpty, !filesToSearch.isEmpty else { return nil }

    let currentName = path[0]

    for file in filesToSearch {
      if file.name == currentName {
        if path.count == 1 {
          return file
        } else if let subfiles = file.children {
          let remainingPath = Array(path[1...])
          return self.findFile(in: subfiles, at: remainingPath)
        }
      }
    }

    return nil
  }

  // MARK: - File Search Helpers

  private func searchPathKey(for path: [String]) -> String {
    path.joined(separator: "\u{001F}")
  }

  func resetFileSearchState() {
    self.fileSearchResults = []
    self.fileSearchResultKeys.removeAll(keepingCapacity: true)
    self.fileSearchStatus = .idle
    self.fileSearchQuery = ""
    self.fileSearchScannedFolders = 0
    self.fileSearchCurrentPath = nil
  }

  // MARK: - File Cache Helpers

  private func shouldBypassFileCache(for path: [String]) -> Bool {
    guard let folderName = path.last else {
      return false
    }

    let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.range(of: "upload", options: [.caseInsensitive]) != nil {
      return true
    }

    if trimmed.range(of: "dropbox", options: [.caseInsensitive]) != nil {
      return true
    }

    if trimmed.range(of: "drop box", options: [.caseInsensitive]) != nil {
      return true
    }

    return false
  }

  private func cachedFileList(for path: [String], ttl: TimeInterval, allowStale: Bool) -> (items: [FileInfo], isFresh: Bool)? {
    guard ttl > 0 else {
      return nil
    }

    if self.shouldBypassFileCache(for: path) {
      return nil
    }

    let key = self.searchPathKey(for: path)
    guard let entry = self.fileListCache[key] else {
      return nil
    }

    let age = Date().timeIntervalSince(entry.timestamp)
    let isFresh = age <= ttl
    if !allowStale && !isFresh {
      return nil
    }

    return (entry.files, isFresh)
  }

  private func storeFileListInCache(_ files: [FileInfo], for path: [String]) {
    guard self.fileSearchConfig.cacheTTL > 0 else {
      return
    }

    if self.shouldBypassFileCache(for: path) {
      return
    }

    let key = self.searchPathKey(for: path)
    self.fileListCache[key] = FileListCacheEntry(files: files, timestamp: Date())
    self.pruneFileListCacheIfNeeded()
  }

  private func pruneFileListCacheIfNeeded() {
    let limit = self.fileSearchConfig.maxCachedFolders
    guard limit > 0, self.fileListCache.count > limit else {
      return
    }

    let excess = self.fileListCache.count - limit
    guard excess > 0 else { return }

    let sortedKeys = self.fileListCache.sorted { lhs, rhs in
      lhs.value.timestamp < rhs.value.timestamp
    }

    for index in 0..<excess {
      let key = sortedKeys[index].key
      self.fileListCache.removeValue(forKey: key)
    }
  }

  private func invalidateFileListCache(for path: [String], includingAncestors: Bool = false) {
    guard !self.fileListCache.isEmpty else {
      return
    }

    var currentPath = path
    while true {
      let key = self.searchPathKey(for: currentPath)
      self.fileListCache.removeValue(forKey: key)

      if !includingAncestors || currentPath.isEmpty {
        break
      }

      currentPath.removeLast()
      if currentPath.isEmpty {
        let rootKey = self.searchPathKey(for: currentPath)
        self.fileListCache.removeValue(forKey: rootKey)
        break
      }
    }
  }
}

// MARK: - File Search Session

@MainActor
final class HotlineStateFileSearchSession {
  private struct FolderTask {
    let path: [String]
    let depth: Int
    let isHot: Bool
  }

  private weak var hotlineState: HotlineState?
  private let queryTokens: [String]
  private let config: FileSearchConfig
  private let startPath: [String]

  private var queue: [FolderTask] = []
  private var visited: Set<String> = []
  private var loopHistogram: [String: Int] = [:]

  private var processedCount: Int = 0
  private var currentDelay: TimeInterval
  private var isCancelled = false

  init(hotlineState: HotlineState, query: String, config: FileSearchConfig, startPath: [String] = []) {
    self.hotlineState = hotlineState
    self.queryTokens = query.lowercased().split(separator: " ").map(String.init)
    self.config = config
    self.startPath = startPath
    self.currentDelay = config.initialDelay
  }

  func start() async {
    guard let hotlineState else {
      return
    }

    await Task.yield()

    if !self.startPath.isEmpty {
      hotlineState.searchSession(self, didFocusOn: self.startPath)
      let startFiles = try? await hotlineState.getFileList(path: self.startPath, suppressErrors: true, preferCache: true)
      self.processedCount = max(self.processedCount, 1)
      self.processListing(startFiles ?? [], depth: 0, parentPath: self.startPath, parentIsHot: false)
    } else if !hotlineState.filesLoaded {
      hotlineState.searchSession(self, didFocusOn: [])
      let rootFiles = try? await hotlineState.getFileList(path: [], suppressErrors: true, preferCache: true)
      self.processedCount = max(self.processedCount, 1)
      self.processListing(rootFiles ?? [], depth: 0, parentPath: [], parentIsHot: false)
    } else {
      hotlineState.searchSession(self, didFocusOn: [])
      self.processedCount = max(self.processedCount, 1)
      self.processListing(hotlineState.files, depth: 0, parentPath: [], parentIsHot: false)
    }

    while !self.queue.isEmpty && !self.isCancelled {
      await Task.yield()

      guard let task = self.dequeueNextTask() else {
        continue
      }

      if self.shouldSkip(path: task.path, depth: task.depth) {
        hotlineState.searchSession(self, didEmit: [], processed: self.processedCount, pending: self.queue.count)
        continue
      }

      hotlineState.searchSession(self, didFocusOn: task.path)
      self.visited.insert(self.pathKey(for: task.path))

      if let cached = hotlineState.cachedListingForSearch(path: task.path, ttl: self.config.cacheTTL) {
        if cached.isFresh {
          self.processedCount += 1
          self.processListing(cached.items, depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)
          continue
        } else {
          self.processListing(cached.items, depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)
        }
      }

      let children = try? await hotlineState.getFileList(path: task.path, suppressErrors: true)
      self.processedCount += 1

      if self.isCancelled {
        break
      }

      self.processListing(children ?? [], depth: task.depth, parentPath: task.path, parentIsHot: task.isHot)

      await self.applyBackoff()
    }

    hotlineState.searchSessionDidFinish(self, processed: self.processedCount, pending: self.queue.count, completed: !self.isCancelled)
  }

  func cancel() {
    self.isCancelled = true
  }

  private func processListing(_ items: [FileInfo], depth: Int, parentPath: [String], parentIsHot: Bool) {
    guard let hotlineState else {
      return
    }

    var matches: [FileInfo] = []
    var folderEntries: [(file: FileInfo, isHot: Bool)] = []
    var hasFileMatch = false

    for file in items {
      let matchesName = self.nameMatchesQuery(file.name)

      if matchesName {
        matches.append(file)
        if !file.isFolder {
          hasFileMatch = true
        }
      }

      if file.isFolder && !file.isAppBundle {
        folderEntries.append((file, matchesName))
      }
    }

    var remainingBurst = 0
    if self.config.hotBurstLimit > 0 && (parentIsHot || hasFileMatch) {
      remainingBurst = self.config.hotBurstLimit
    }

    if remainingBurst > 0 {
      var candidateIndices: [Int] = []
      for index in folderEntries.indices where !folderEntries[index].isHot {
        candidateIndices.append(index)
      }

      if !candidateIndices.isEmpty {
        candidateIndices.shuffle()
        for index in candidateIndices {
          folderEntries[index].isHot = true
          remainingBurst -= 1
          if remainingBurst == 0 {
            break
          }
        }
      }
    }

    for entry in folderEntries {
      self.enqueueFolder(entry.file, depth: depth + 1, markHot: entry.isHot)
    }

    hotlineState.searchSession(self, didEmit: matches, processed: self.processedCount, pending: self.queue.count)
  }

  private func enqueueFolder(_ folder: FileInfo, depth: Int, markHot: Bool) {
    guard !self.isCancelled else { return }
    guard depth <= self.config.maxDepth else { return }

    let path = folder.path
    let key = self.pathKey(for: path)
    guard !self.visited.contains(key) else { return }

    if self.exceedsLoopThreshold(for: path) {
      return
    }

    self.queue.append(FolderTask(path: path, depth: depth, isHot: markHot))
  }

  private func dequeueNextTask() -> FolderTask? {
    guard !self.queue.isEmpty else {
      return nil
    }

    if self.queue.count == 1 {
      return self.queue.removeFirst()
    }

    let currentDepth = self.queue[0].depth
    var lastSameDepthIndex = 0
    var hotIndices: [Int] = []

    for index in 0..<self.queue.count {
      let candidate = self.queue[index]
      if candidate.depth == currentDepth {
        lastSameDepthIndex = index
        if candidate.isHot {
          hotIndices.append(index)
        }
      } else {
        break
      }
    }

    let selectionPool: [Int]
    if !hotIndices.isEmpty {
      selectionPool = hotIndices
    } else {
      selectionPool = Array(0...lastSameDepthIndex)
    }

    let randomIndex = selectionPool.randomElement() ?? 0
    return self.queue.remove(at: randomIndex)
  }

  private func shouldSkip(path: [String], depth: Int) -> Bool {
    if self.isCancelled {
      return true
    }

    if depth > self.config.maxDepth {
      return true
    }

    let key = self.pathKey(for: path)
    if self.visited.contains(key) {
      return true
    }

    return false
  }

  private func nameMatchesQuery(_ name: String) -> Bool {
    guard !self.queryTokens.isEmpty else { return false }
    let lowercased = name.lowercased()
    return self.queryTokens.allSatisfy { lowercased.contains($0) }
  }

  private func exceedsLoopThreshold(for path: [String]) -> Bool {
    guard self.config.loopRepetitionLimit > 0 else { return false }
    guard let last = path.last else { return false }
    let parent = path.dropLast()

    guard let previousIndex = parent.lastIndex(of: last) else {
      return false
    }

    let suffix = Array(path[previousIndex...])
    let key = suffix.joined(separator: "\u{001F}")
    let count = (self.loopHistogram[key] ?? 0) + 1
    self.loopHistogram[key] = count
    return count > self.config.loopRepetitionLimit
  }

  private func pathKey(for path: [String]) -> String {
    path.joined(separator: "\u{001F}")
  }

  private func applyBackoff() async {
    guard !self.isCancelled else { return }

    if self.processedCount > self.config.initialBurstCount {
      self.currentDelay = min(self.config.maxDelay, max(self.config.initialDelay, self.currentDelay * self.config.backoffMultiplier))
    }

    guard self.currentDelay > 0 else {
      return
    }

    let nanoseconds = UInt64(self.currentDelay * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanoseconds)
  }
}
