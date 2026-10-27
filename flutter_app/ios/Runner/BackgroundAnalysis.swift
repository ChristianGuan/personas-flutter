import BackgroundTasks
import UIKit
import UserNotifications

/// CPU work only. The system can reject/expire continuation; never report that as completion.
final class BackgroundAnalysis {
    private var lease: UIBackgroundTaskIdentifier = .invalid
    private var token: String?
    private var task: AnyObject?
    private var identifier: String?
    private var started = false
    private var mayContinue = true
    private var total = 0
    private var processed = 0
    private var startWork: (() -> Void)?
    private var onExpired: (() -> Void)?
    private var onMode: ((String) -> Void)?
    static var capability: String { if #available(iOS 26.0, *) { return "iosContinued" }; return "iosLimited" }

    func start(total: Int, onMode: @escaping (String) -> Void, onExpired: @escaping () -> Void, work: @escaping () -> Void) {
        let token = UUID().uuidString
        self.token = token; self.total = total; self.processed = 0
        self.startWork = work; self.onExpired = onExpired; self.onMode = onMode
        self.started = false; self.mayContinue = true
        lease = UIApplication.shared.beginBackgroundTask(withName: "Análisis de tus fotos") { [weak self] in self?.expire(token) }
        if #available(iOS 26.0, *) {
            let id = (Bundle.main.bundleIdentifier ?? "co.local.personas") + ".analysis." + token
            identifier = id
            // Each exact identifier is registered once; the permitted prefix is in Info.plist.
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
                guard let self = self, self.token == token, self.mayContinue,
                      let continued = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                self.task = continued
                continued.progress.totalUnitCount = Int64(total)
                continued.progress.completedUnitCount = Int64(self.processed)
                continued.expirationHandler = { [weak self] in DispatchQueue.main.async { self?.expire(token) } }
                self.endLease()
                self.begin("iosContinued", token: token)
            }
            guard registered else { fallback(token); return }
            let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Buscando en tus fotos", subtitle: "Procesadas 0 de \(total) fotos")
            request.strategy = .fail
            // No GPU entitlement or alternative inference path is needed.
            DispatchQueue.global(qos: .userInitiated).async {
                if #available(iOS 27.0, *) {
                    BGTaskScheduler.shared.submitTaskRequest(request) { error in
                        if error != nil { DispatchQueue.main.async { self.fallback(token) } }
                    }
                } else {
                    do { try BGTaskScheduler.shared.submit(request) }
                    catch { DispatchQueue.main.async { self.fallback(token) } }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, self.token == token, !self.started else { return }
                self.fallback(token)
            }
        } else { fallback(token) }
    }
    private func begin(_ mode: String, token: String) {
        guard self.token == token else { return }
        onMode?(mode)
        guard !started else { return }
        started = true
        let work = startWork; startWork = nil; work?()
    }
    private func fallback(_ token: String) {
        guard self.token == token, task == nil else { return }
        mayContinue = false
        if let identifier = identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        begin("iosLimited", token: token)
    }
    func progress(_ processed: Int) {
        self.processed = processed
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64(processed)
            task.updateTitle("Buscando en tus fotos", subtitle: "Procesadas \(processed) de \(total) fotos")
        }
    }
    private func expire(_ token: String) {
        guard self.token == token else { return }
        onExpired?()
        finish(success: false)
    }
    func finish(success: Bool) {
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask { task.setTaskCompleted(success: success) }
        if let identifier = identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        task = nil; token = nil; identifier = nil
        startWork = nil; onExpired = nil; onMode = nil
        endLease()
    }
    private func endLease() {
        if lease != .invalid { UIApplication.shared.endBackgroundTask(lease); lease = .invalid }
    }
}

enum AnalysisNotifications {
    static func status(_ completion: @escaping ([String: Bool]) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let state = settings.authorizationStatus
            let enabled = state == .authorized || state == .provisional || state == .ephemeral
            UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
                let ours = delivered.contains { $0.request.identifier == "personas.analysis.finished" }
                DispatchQueue.main.async { completion([
                    "enabled": enabled, "asked": state != .notDetermined, "canAsk": state == .notDetermined,
                    "banners": settings.alertSetting == .enabled,
                    "notificationCenter": settings.notificationCenterSetting == .enabled,
                    "completionDelivered": ours,
                    "lastDeliveryFailed": UserDefaults.standard.bool(forKey: "PersonasAnalysisNotificationFailed")
                ]) }
            }
        }
    }
    static func request(_ completion: @escaping ([String: Bool]) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in status(completion) }
    }
    static func finished(matches: Int, processed: Int, interrupted: Bool, run: Int, completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = interrupted ? "Tu análisis necesita revisión" : "Tu análisis ha terminado"
        content.body = interrupted ? "El análisis se interrumpió. Abre Personas para revisar lo encontrado."
            : "\(matches) coincidencias · \(processed) fotos procesadas. Toca para revisarlas."
        content.sound = .default
        // One current completion, no person names, portraits, album titles or URIs.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "personas.analysis.finished", content: content, trigger: nil)) { error in
            DispatchQueue.main.async {
                UserDefaults.standard.set(error != nil, forKey: "PersonasAnalysisNotificationFailed")
                completion()
            }
        }
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: "PersonasAnalysisNotificationFailed")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["personas.analysis.finished"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["personas.analysis.finished"])
    }
}
