//
//  BackgroundSyncScheduler.swift
//  beemed
//

#if os(iOS)
import Foundation
import BackgroundTasks

@MainActor
final class BackgroundSyncScheduler {
    static let refreshTaskId = "name.danmackinlay.beemed.sync.refresh"
    static let processingTaskId = "name.danmackinlay.beemed.sync.processing"

    private let queueManager: QueueManager
    private let backgroundUploader: BackgroundUploader

    init(queueManager: QueueManager, backgroundUploader: BackgroundUploader) {
        self.queueManager = queueManager
        self.backgroundUploader = backgroundUploader
    }

    // Call from App.init() BEFORE app finishes launching
    nonisolated static func registerTasks(handler: @escaping @Sendable (BGTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil, launchHandler: handler)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskId, using: nil, launchHandler: handler)
    }

    func scheduleRefreshTask() {
        guard queueManager.totalPendingCount > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule refresh task: \(error)")
        }
    }

    func scheduleProcessingTask() {
        guard queueManager.totalPendingCount > 0 else { return }

        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 min

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule processing task: \(error)")
        }
    }

    func handleTask(_ task: BGTask) {
        // IMPORTANT: Schedule next task FIRST (before any async work)
        scheduleRefreshTask()

        task.expirationHandler = {
            // Time's up - uploads continue via background URLSession
            task.setTaskCompleted(success: true)
        }

        // Submit pending items to background URLSession
        Task { @MainActor in
            await backgroundUploader.submitPendingUploads()
            task.setTaskCompleted(success: true)
        }
    }

    func cancelAllTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
}
#endif
