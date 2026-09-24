//
//  enum.swift
//  Feather
//
//  Created by samara on 3.05.2025.
//

import Foundation
import Combine
import UIKit.UIImpactFeedbackGenerator
import BackgroundTasks

class Download: Identifiable, @unchecked Sendable {
	@Published var progress: Double = 0.0
	@Published var bytesDownloaded: Int64 = 0
	@Published var totalBytes: Int64 = 0
	@Published var unpackageProgress: Double = 0.0
	
	var overallProgress: Double {
		onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
	var task: URLSessionDownloadTask?
	var resumeData: Data?
	
	let id: String
	let url: URL
	let fileName: String
	let onlyArchiving: Bool
	var sourceProvenance: SourceAppProvenance?
	/// AppMaster: sign with the default certificate and install right after the
	/// download/import finishes (see `OneTapInstaller`).
	var autoInstall: Bool = false
	/// Set by `AppFileHandler` once the IPA has been imported into the Library.
	var importedUUID: String?
	/// Consecutive automatic retries of a one-tap download (reset whenever bytes arrive).
	var retryCount: Int = 0
	
	init(
		id: String,
		url: URL,
		onlyArchiving: Bool = false,
		sourceProvenance: SourceAppProvenance? = nil
	) {
		self.id = id
		self.url = url
		self.onlyArchiving = onlyArchiving
		self.sourceProvenance = sourceProvenance
		self.fileName = url.lastPathComponent
	}
}

class DownloadManager: NSObject, ObservableObject {
	static let shared = DownloadManager()
	
	@Published var downloads: [Download] = []
	
	var manualDownloads: [Download] {
		downloads.filter { isManualDownload($0.id) }
	}
	
	private var _session: URLSession!
	/// Plain (foreground) session used by the one-tap install: real progress callbacks and a
	/// transfer that stalls times out and is retried instead of hanging on a dead spinner.
	private var _foregroundSession: URLSession!
	
	/// Set by AppDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)
	/// when iOS relaunches/wakes the app to report finished background downloads.
	/// Must be called (on the main thread) once every queued delegate callback has
	/// been processed, or the system keeps the app suspended in the background.
	var backgroundCompletionHandler: (() -> Void)?
	
	private static let backgroundSessionIdentifier = "com.appmaster.backgrounddownloads"
	
	#if !targetEnvironment(macCatalyst)
	private func _updateBackgroundAudioState() {
		if #unavailable(iOS 26.0){
			if !downloads.isEmpty {
				BackgroundAudioManager.shared.start()
			} else  {
				BackgroundAudioManager.shared.stop()
			}
		}
	}
	#endif
	
	override init() {
		super.init()
		// AppMaster: downloads must keep going (and be resumable) even if the
		// person leaves the app or the app gets suspended — previously this used
		// a plain .default session, which iOS pauses shortly after backgrounding,
		// forcing people to sit inside the app and wait for big IPAs to finish.
		// A background URLSession configuration hands the transfer to a system
		// daemon that keeps running independently of the app's own lifecycle.
		#if targetEnvironment(macCatalyst)
		let configuration = URLSessionConfiguration.default
		#else
		let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
		configuration.isDiscretionary = false
		configuration.sessionSendsLaunchEvents = true
		configuration.shouldUseExtendedBackgroundIdleMode = true
		#endif
		_session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
		
		let foreground = URLSessionConfiguration.default
		foreground.waitsForConnectivity = false
		foreground.timeoutIntervalForRequest = 30
		foreground.timeoutIntervalForResource = 60 * 60
		foreground.requestCachePolicy = .reloadIgnoringLocalCacheData
		foreground.urlCache = nil
		_foregroundSession = URLSession(configuration: foreground, delegate: self, delegateQueue: nil)
	}
	
	private func _urlSession(for download: Download) -> URLSession {
		download.autoInstall ? _foregroundSession : _session
	}
	
	func startDownload(
		from url: URL,
		id: String = UUID().uuidString,
		sourceProvenance: SourceAppProvenance? = nil,
		autoInstall: Bool = false
	) -> Download {
		let requestHasSourceProvenance = sourceProvenance != nil
		if let existingDownload = downloads.first(where: {
			$0.url == url && ($0.sourceProvenance != nil) == requestHasSourceProvenance
		}) {
			if autoInstall { existingDownload.autoInstall = true }
			resumeDownload(existingDownload)
			return existingDownload
		}
		
		let download = Download(id: id, url: url, sourceProvenance: sourceProvenance)
		download.autoInstall = autoInstall
		
		let task = _urlSession(for: download).downloadTask(with: url)
		download.task = task
		task.resume()
		
		downloads.append(download)
		
		#if !targetEnvironment(macCatalyst)
		if #available(iOS 26.0, *) {
			BackgroundTaskManager.shared.startTask(for: id, filename: url.lastPathComponent)
		} else {
			_updateBackgroundAudioState()
		}
		#endif
		
		return download
	}
	
	func startArchive(
		from url: URL,
		id: String = UUID().uuidString
	) -> Download {
		let download = Download(id: id, url: url, onlyArchiving: true)
		downloads.append(download)
		
		#if !targetEnvironment(macCatalyst)
		_updateBackgroundAudioState()
		#endif
		
		return download
	}
	
	func resumeDownload(_ download: Download) {
		if let resumeData = download.resumeData {
			let task = _urlSession(for: download).downloadTask(withResumeData: resumeData)
			download.task = task
			task.resume()
			
			#if !targetEnvironment(macCatalyst)
			_updateBackgroundAudioState()
			#endif
		} else if let url = download.task?.originalRequest?.url {
			let task = _urlSession(for: download).downloadTask(with: url)
			download.task = task
			task.resume()
			
			#if !targetEnvironment(macCatalyst)
			_updateBackgroundAudioState()
			#endif
		}
	}
	
	func cancelDownload(_ download: Download) {
		download.task?.cancel()
		if download.autoInstall { OneTapInstaller.shared.reset() }
		
		if let index = downloads.firstIndex(where: { $0.id == download.id }) {
			downloads.remove(at: index)
			
			#if !targetEnvironment(macCatalyst)
			_updateBackgroundAudioState()

			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.stopTask(for: download.id, success: false)
			}
			#endif
		}
	}
	
	func isManualDownload(_ string: String) -> Bool {
		return string.contains("FeatherManualDownload")
	}
	
	func getDownload(by id: String) -> Download? {
		return downloads.first(where: { $0.id == id })
	}
	
	func getDownloadIndex(by id: String) -> Int? {
		return downloads.firstIndex(where: { $0.id == id })
	}
	
	func getDownloadTask(by task: URLSessionDownloadTask) -> Download? {
		return downloads.first(where: { $0.task == task })
	}
}

extension DownloadManager: URLSessionDownloadDelegate {
	
	func handlePachageFile(url: URL, dl: Download) throws {
		FR.handlePackageFile(url, download: dl) { err in
			if err != nil {
				let generator = UINotificationFeedbackGenerator()
				generator.notificationOccurred(.error)
			}
			
			DispatchQueue.main.async {
				if let index = DownloadManager.shared.getDownloadIndex(by: dl.id) {
					DownloadManager.shared.downloads.remove(at: index)
					
					#if !targetEnvironment(macCatalyst)
					if #available(iOS 26.0, *) {
						BackgroundTaskManager.shared.updateProgress(for: dl.id, progress: 1.0)
					}
					
					self._updateBackgroundAudioState()
					#endif
				}
				
				// AppMaster: one-tap install (sign with the default certificate, then install)
				if dl.autoInstall {
					OneTapInstaller.shared.importFinished(download: dl, error: err)
				}
			}
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let download = getDownloadTask(by: downloadTask) else { return }
		
		if download.autoInstall {
			DispatchQueue.main.async { OneTapInstaller.shared.markPreparing() }
		}
		
		let tempDirectory = FileManager.default.temporaryDirectory
		let customTempDir = tempDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true)
		
		do {
			try FileManager.default.createDirectoryIfNeeded(at: customTempDir)
			
			// Use the server-suggested filename if available, otherwise fallback
			let suggestedFileName = downloadTask.response?.suggestedFilename ?? download.fileName
			let destinationURL = customTempDir.appendingPathComponent(suggestedFileName)
			
			try FileManager.default.removeFileIfNeeded(at: destinationURL)
			try FileManager.default.moveItem(at: location, to: destinationURL)
			
			try handlePachageFile(url: destinationURL, dl: download)
		} catch {
			print("Error handling downloaded file: \(error.localizedDescription)")
			if download.autoInstall { OneTapInstaller.shared.fail(error.localizedDescription) }
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard let download = getDownloadTask(by: downloadTask) else { return }
		
		DispatchQueue.main.async {
			download.progress = totalBytesExpectedToWrite > 0
			? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
			: 0
			if totalBytesWritten > download.bytesDownloaded { download.retryCount = 0 }
			download.bytesDownloaded = totalBytesWritten
			download.totalBytes = totalBytesExpectedToWrite
			
			if download.autoInstall {
				OneTapInstaller.shared.updateDownload(written: totalBytesWritten, total: totalBytesExpectedToWrite)
			}
			
			#if !targetEnvironment(macCatalyst)
			if #available(iOS 26.0, *) {
				BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
			}
			#endif
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard
			let error,
			let downloadTask = task as? URLSessionDownloadTask,
			let download = getDownloadTask(by: downloadTask)
		else {
			return
		}
		
		DispatchQueue.main.async {
			// One-tap downloads survive a flaky connection: a dropped or timed-out transfer is
			// retried automatically (resuming from what was already saved) instead of leaving
			// the person looking at a frozen spinner.
			let nsError = error as NSError
			let isCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
			
			if
				download.autoInstall,
				!isCancelled,
				download.retryCount < 4,
				self.getDownloadIndex(by: download.id) != nil
			{
				download.retryCount += 1
				download.resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
				
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
					// the person may have cancelled while we were waiting
					guard self.getDownloadIndex(by: download.id) != nil else { return }
					self.resumeDownload(download)
				}
				return
			}
			
			if let index = self.getDownloadIndex(by: download.id) {
				self.downloads.remove(at: index)
			}
			
			if download.autoInstall {
				let message: String = (nsError.domain == NSURLErrorDomain && !isCancelled)
					? String.localized("Download interrupted. Check your connection and try again.")
					: error.localizedDescription
				OneTapInstaller.shared.fail(message)
			}
		}
	}
	
	// Called once every queued delegate callback for the background session has
	// been delivered, after iOS relaunches/wakes the app to hand off a finished
	// background download. Must call the stored system completion handler (set
	// by AppDelegate) or the app stays frozen in the background needlessly.
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		DispatchQueue.main.async {
			self.backgroundCompletionHandler?()
			self.backgroundCompletionHandler = nil
		}
	}
}
