//
//  ParallelDownloader.swift
//  AppMaster
//
//  Downloads one file with several simultaneous connections (HTTP Range requests)
//  and joins the parts. Used by the one-tap install so a host that limits the speed
//  of a single connection no longer slows the download down.
//  If the host can't do ranges (or anything goes wrong) `onFallback` is called and
//  the normal single-connection download takes over.
//

import Foundation

final class ParallelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
	private static let minTotal: Int64 = 8 * 1024 * 1024
	private static let minSegment: Int64 = 4 * 1024 * 1024
	private static let maxSegments: Int64 = 6

	private let url: URL
	private let lock = NSLock()
	private let workDir: URL

	private var session: URLSession?
	private var ranges: [ClosedRange<Int64>] = []
	private var tasks: [Int: URLSessionDownloadTask] = [:]
	private var written: [Int: Int64] = [:]
	private var segmentFiles: [Int: URL] = [:]
	private var retries: [Int: Int] = [:]
	private var total: Int64 = 0
	private var finished = 0
	private var done = false
	private var suggestedName: String?
	private var lastReport = Date.distantPast

	/// (bytes written so far, total bytes)
	var onProgress: ((Int64, Int64) -> Void)?
	/// The joined file, ready to be imported.
	var onFinish: ((URL) -> Void)?
	/// Not supported by the host or failed: use the normal download instead.
	var onFallback: (() -> Void)?

	init(url: URL) {
		self.url = url
		self.workDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherParts-\(UUID().uuidString)", isDirectory: true)
		super.init()
	}

	// MARK: Start
	func start() {
		var probe = DownloadManager.browserRequest(url)
		probe.httpMethod = "HEAD"
		probe.timeoutInterval = 20

		URLSession.shared.dataTask(with: probe) { [weak self] _, response, error in
			guard let self else { return }
			guard
				error == nil,
				let http = response as? HTTPURLResponse,
				(200..<300).contains(http.statusCode),
				http.expectedContentLength >= Self.minTotal,
				(http.value(forHTTPHeaderField: "Accept-Ranges") ?? "bytes").lowercased() != "none"
			else {
				self.fallback()
				return
			}
			self.suggestedName = http.suggestedFilename
			self.begin(total: http.expectedContentLength)
		}.resume()
	}

	private func begin(total: Int64) {
		let count = Int(min(Self.maxSegments, max(2, total / Self.minSegment)))
		let size = (total + Int64(count) - 1) / Int64(count)
		var list: [ClosedRange<Int64>] = []
		var start: Int64 = 0
		while start < total {
			let end = min(start + size - 1, total - 1)
			list.append(start...end)
			start = end + 1
		}

		lock.lock()
		if done { lock.unlock(); return }
		self.total = total
		self.ranges = list
		lock.unlock()

		try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 30
		config.timeoutIntervalForResource = 60 * 60
		config.httpMaximumConnectionsPerHost = list.count
		config.urlCache = nil
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = 1
		let newSession = URLSession(configuration: config, delegate: self, delegateQueue: queue)

		lock.lock()
		if done { lock.unlock(); newSession.invalidateAndCancel(); return }
		session = newSession
		lock.unlock()

		for index in 0..<list.count { startSegment(index) }
	}

	private func startSegment(_ index: Int) {
		lock.lock()
		guard !done, let current = session else { lock.unlock(); return }
		let range = ranges[index]
		written[index] = 0
		lock.unlock()

		var request = DownloadManager.browserRequest(url)
		request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
		let task = current.downloadTask(with: request)
		task.taskDescription = String(index)

		lock.lock()
		tasks[index] = task
		lock.unlock()
		task.resume()
	}

	// MARK: Stop
	func cancel() {
		lock.lock()
		if done { lock.unlock(); return }
		done = true
		let running = Array(tasks.values)
		let current = session
		lock.unlock()

		running.forEach { $0.cancel() }
		current?.invalidateAndCancel()
		_cleanup()
		onProgress = nil
		onFinish = nil
		onFallback = nil
	}

	private func fallback() {
		lock.lock()
		if done { lock.unlock(); return }
		done = true
		let running = Array(tasks.values)
		let current = session
		lock.unlock()

		running.forEach { $0.cancel() }
		current?.invalidateAndCancel()
		_cleanup()
		onFallback?()
	}

	private func _cleanup() {
		try? FileManager.default.removeItem(at: workDir)
	}

	// MARK: Join
	private func assemble() {
		lock.lock()
		let count = ranges.count
		let parts = segmentFiles
		let expectedTotal = total
		let name = suggestedName
		lock.unlock()

		DispatchQueue.global(qos: .userInitiated).async { [self] in
			do {
				let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true)
				try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
				let fileName = (name?.isEmpty == false) ? name! : url.lastPathComponent
				let destination = folder.appendingPathComponent(fileName)
				try? FileManager.default.removeItem(at: destination)
				FileManager.default.createFile(atPath: destination.path, contents: nil)

				let output = try FileHandle(forWritingTo: destination)
				var length: Int64 = 0
				for index in 0..<count {
					guard let part = parts[index] else { throw URLError(.cannotParseResponse) }
					let input = try FileHandle(forReadingFrom: part)
					while true {
						let chunk: Data = autoreleasepool { input.readData(ofLength: 4 * 1024 * 1024) }
						if chunk.isEmpty { break }
						try output.write(contentsOf: chunk)
						length += Int64(chunk.count)
					}
					try? input.close()
					try? FileManager.default.removeItem(at: part)
				}
				try output.close()

				if length != expectedTotal { throw URLError(.cannotParseResponse) }

				session?.finishTasksAndInvalidate()
				_cleanup()
				onFinish?(destination)
			} catch {
				session?.invalidateAndCancel()
				_cleanup()
				onFallback?()
			}
		}
	}

	// MARK: URLSessionDownloadDelegate
	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite: Int64
	) {
		guard let index = Int(downloadTask.taskDescription ?? "") else { return }

		lock.lock()
		if done { lock.unlock(); return }
		written[index] = totalBytesWritten
		let sum = written.values.reduce(0, +)
		let all = total
		let now = Date()
		let shouldReport = now.timeIntervalSince(lastReport) > 0.2
		if shouldReport { lastReport = now }
		lock.unlock()

		if shouldReport { onProgress?(min(sum, all), all) }
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let index = Int(downloadTask.taskDescription ?? "") else { return }

		lock.lock()
		let isDone = done
		let range = index < ranges.count ? ranges[index] : nil
		lock.unlock()
		guard !isDone, let range else { return }

		let expected = range.upperBound - range.lowerBound + 1
		let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
		let attributes = try? FileManager.default.attributesOfItem(atPath: location.path)
		let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
		guard status == 206, size == expected else { return }

		let destination = workDir.appendingPathComponent("part-\(index)")
		try? FileManager.default.removeItem(at: destination)
		do {
			try FileManager.default.moveItem(at: location, to: destination)
		} catch {
			return
		}

		lock.lock()
		segmentFiles[index] = destination
		lock.unlock()
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let index = Int(task.taskDescription ?? "") else { return }

		lock.lock()
		if done { lock.unlock(); return }

		if error == nil, segmentFiles[index] != nil {
			finished += 1
			let allFinished = finished == ranges.count
			if allFinished { done = true }
			lock.unlock()
			if allFinished { assemble() }
			return
		}

		if let nsError = error as NSError?, nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
			lock.unlock()
			return
		}

		let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
		let attempts = retries[index, default: 0]
		if status == 200 || attempts >= 3 {
			lock.unlock()
			fallback()
			return
		}
		retries[index] = attempts + 1
		lock.unlock()

		DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.startSegment(index)
		}
	}
}
