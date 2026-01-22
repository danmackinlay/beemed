//
//  BackgroundUploader.swift
//  beemed
//

import Foundation

@MainActor
final class BackgroundUploader: NSObject {
    static let sessionIdentifier = "name.danmackinlay.beemed.background-upload"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false // Upload ASAP when network available
        config.sessionSendsLaunchEvents = true // Wake app on completion
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let queueManager: QueueManager
    private var pendingTaskIds: [Int: UUID] = [:] // URLSession task ID -> QueuedDatapoint ID
    private var responseData: [Int: Data] = [:] // Collect response body for error analysis

    init(queueManager: QueueManager) {
        self.queueManager = queueManager
        super.init()
    }

    func submitPendingUploads() async {
        guard let token = KeychainHelper.loadToken() else { return }

        // Clean up stale items before processing
        queueManager.cleanupStaleItems()

        for datapoint in queueManager.itemsReadyToRetry() {
            // Skip if already being uploaded
            guard !pendingTaskIds.values.contains(datapoint.id) else { continue }

            guard let request = buildRequest(for: datapoint, token: token) else { continue }

            let task = session.dataTask(with: request)
            pendingTaskIds[task.taskIdentifier] = datapoint.id
            task.resume()
        }
    }

    private func buildRequest(for datapoint: QueuedDatapoint, token: String) -> URLRequest? {
        let urlString = "https://www.beeminder.com/api/v1/users/me/goals/\(datapoint.goalSlug)/datapoints.json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "value": datapoint.value,
            "timestamp": Int(datapoint.timestamp.timeIntervalSince1970),
            "requestid": datapoint.id.uuidString
        ]
        if let comment = datapoint.comment {
            body["comment"] = comment
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    // Called by app when background URLSession completes all tasks
    func handleBackgroundSessionCompletion() {
        // Session delegate methods handle individual completions
    }

    private func handleTaskCompletion(taskIdentifier: Int, response: URLResponse?, error: Error?) {
        guard let datapointId = pendingTaskIds.removeValue(forKey: taskIdentifier) else { return }
        let data = responseData.removeValue(forKey: taskIdentifier)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch statusCode {
        case 200...299:
            // Explicit success
            queueManager.dequeue(id: datapointId)

        case 409:
            // Duplicate - treat as success (requestid already processed)
            queueManager.dequeue(id: datapointId)

        case 401:
            // Auth expired - remove item, user must re-auth
            queueManager.markAuthFailure(id: datapointId)

        case 422:
            // Validation error - check if "already exists" (duplicate)
            if responseContainsDuplicateMessage(data) {
                queueManager.dequeue(id: datapointId)
            } else {
                queueManager.markAttempt(id: datapointId, error: "Validation error (HTTP 422)")
            }

        default:
            // Transient failure - apply backoff
            let errorMsg = error?.localizedDescription ?? "HTTP \(statusCode)"
            queueManager.markAttempt(id: datapointId, error: errorMsg)
        }
    }

    private func responseContainsDuplicateMessage(_ data: Data?) -> Bool {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = json["errors"] as? [String: Any] else {
            return false
        }
        // Beeminder returns errors about duplicate requestid
        let errorString = String(describing: errors).lowercased()
        return errorString.contains("requestid") || errorString.contains("duplicate") || errorString.contains("already")
    }
}

extension BackgroundUploader: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            // Accumulate response data for error analysis
            if var existing = responseData[dataTask.taskIdentifier] {
                existing.append(data)
                responseData[dataTask.taskIdentifier] = existing
            } else {
                responseData[dataTask.taskIdentifier] = data
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            handleTaskCompletion(taskIdentifier: task.taskIdentifier, response: task.response, error: error)
        }
    }
}
