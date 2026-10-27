import Foundation

/// Last result/context in private cache; native reference vectors remain memory-only.
final class AnalysisSession {
    private let io = DispatchQueue(label: "personas.analysis.state")
    private let url: URL
    private var metadata: [String: Any]?
    private var events: [[String: Any]] = []
    private var revision = 0
    var value: [String: Any]? { metadata.map { $0.merging(["events": events]) { _, new in new } } }
    init() {
        url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PersonasLastAnalysis.json")
    }
    func load(_ completion: @escaping () -> Void) {
        guard value == nil else { completion(); return }
        let revision = self.revision
        io.async {
            var disk = (try? Data(contentsOf: self.url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            disk?["referencesAvailable"] = false
            if disk?["active"] as? Bool == true {
                let run = disk?["runId"] ?? 0
                disk?["active"] = false
                disk?["done"] = ["type": "done", "runId": run, "cancelled": true,
                                 "error": "iOS interrumpió el análisis. Revisa los resultados parciales y elige de nuevo tu referencia."]
            }
            DispatchQueue.main.async { if self.metadata == nil && self.revision == revision {
                self.events = disk?.removeValue(forKey: "events") as? [[String: Any]] ?? []
                self.metadata = disk
            }; completion() }
        }
    }
    func begin(run: Int, context: [String: Any]) {
        revision += 1
        events = []
        metadata = ["runId": run, "context": context, "active": true,
                 "referencesAvailable": true, "backgroundMode": BackgroundAnalysis.capability]
        AnalysisNotifications.clear()
        save()
    }
    func mode(_ mode: String) { metadata?["backgroundMode"] = mode }
    func photo(_ event: [String: Any]) {
        guard metadata?["active"] as? Bool == true, metadata?["runId"] as? Int == event["runId"] as? Int else { return }
        events.append(event)
        if events.count % 25 == 0 { save() }
    }
    var processed: Int { events.count }
    var matches: Int { events.filter { ["match", "confirmed"].contains($0["outcome"] as? String ?? "") }.count }
    var feedback: [String: Bool] { (value?["context"] as? [String: Any])?["feedback"] as? [String: Bool] ?? [:] }
    func finish(_ event: [String: Any], completion: @escaping () -> Void) {
        guard var final = value else { completion(); return }
        final["active"] = false; final["done"] = event
        io.async {
            if let data = try? JSONSerialization.data(withJSONObject: final) { try? data.write(to: self.url, options: .atomic) }
            DispatchQueue.main.async {
                self.metadata?["active"] = false; self.metadata?["done"] = event
                completion()
            }
        }
    }
    func update(_ context: [String: Any]) {
        guard value?["active"] as? Bool != true, context["runId"] as? Int == value?["runId"] as? Int else { return }
        metadata?["context"] = context; save()
    }
    private func save() {
        guard let value = value else { return }
        io.async { if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: self.url, options: .atomic) } }
    }
    func clear() { revision += 1; metadata = nil; events = []; io.async { try? FileManager.default.removeItem(at: self.url) }; AnalysisNotifications.clear() }
}
