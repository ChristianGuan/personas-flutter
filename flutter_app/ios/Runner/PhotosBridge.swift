import Flutter
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers
import CryptoKit

final class PhotosBridge: NSObject, FlutterPlugin, FlutterStreamHandler, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private let store = try? PhotoStore()
    private let worker = DispatchQueue(label: "personas.inference", qos: .userInitiated)
    private let previews: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .userInitiated; return q }()
    private let background = BackgroundAnalysis()
    private let session = AnalysisSession()
    private var openObserver: NSObjectProtocol?
    private var engine: NativeFaceEngine?
    private var sink: FlutterEventSink?
    private var pickerRequest: PhotoPreparation<[String]>?
    private var referenceRequest: PhotoPreparation<[String: Any]>?
    private weak var pickerController: UIViewController?
    private var pickerProgress: Progress?
    private var pendingSearch: FlutterResult?
    private var operation: PhotoOperation?
    private var incoming: [String] = []
    private var activeObserver: NSObjectProtocol?
    private var memoryObserver: NSObjectProtocol?
    private var finishing = false
    private var sharing = false
    // Per-photo diagnostics are accumulated on the serial worker and persisted in done.
    private var runDiagnostics: [String: Int] = [:]
    private let diagnosticsLock = NSLock()
    private func resetDiagnostics() { diagnosticsLock.lock(); defer { diagnosticsLock.unlock() }; runDiagnostics = [:] }
    private func addDiagnostics(_ values: [String: Int]) { diagnosticsLock.lock(); defer { diagnosticsLock.unlock() }; for (key, value) in values { runDiagnostics[key, default: 0] += value } }
    private func diagnosticsSnapshot() -> [String: Int] { diagnosticsLock.lock(); defer { diagnosticsLock.unlock() }; return runDiagnostics }
    private var pickerSingle = false
    private static let preparationTimeout: TimeInterval = 90
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PhotosBridge()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "co.local.personas/photos", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "co.local.personas/events", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
        instance.activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak instance] _ in instance?.consumeInbox(); instance?.openAnalysisIfNeeded() }
        instance.openObserver = NotificationCenter.default.addObserver(forName: Notification.Name("PersonasOpenAnalysis"), object: nil, queue: .main) { [weak instance] _ in instance?.openAnalysisIfNeeded() }
        instance.memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak instance] _ in
            guard let instance = instance, instance.operation == nil else { return }
            // Keep selected reference handles; normal cache eviction remains bounded.
            instance.worker.async { instance.engine?.clearAnalysisCache() }
        }
    }
    deinit { if let openObserver = openObserver { NotificationCenter.default.removeObserver(openObserver) }; if let activeObserver = activeObserver { NotificationCenter.default.removeObserver(activeObserver) }; if let memoryObserver = memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }; operation?.cancel() }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        DispatchQueue.main.async { self.openAnalysisIfNeeded() }
        if !incoming.isEmpty { events(["type": "incoming", "ids": incoming]); incoming = [] }
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
    private func reply(_ result: @escaping FlutterResult, _ value: Any?) { DispatchQueue.main.async { result(value) } }
    private func fail(_ result: @escaping FlutterResult, _ error: Error) { reply(result, FlutterError(code: "photo_error", message: error.localizedDescription, details: nil)) }
    private func emit(_ event: [String: Any]) { DispatchQueue.main.async {
        var event = event
        if event["type"] as? String == "photo" {
            guard self.session.value?["active"] as? Bool == true, !self.finishing else { return }
            if event["outcome"] as? String != "unreadable", let key = event["key"] as? String, let confirmed = self.session.feedback[key] {
                event["outcome"] = confirmed ? "confirmed" : "rejected"
            }
            self.session.photo(event)
            self.background.progress(self.session.processed)
        }
        self.sink?(event)
    }}
    private var presenter: UIViewController? {
        var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
        while let next = controller?.presentedViewController { controller = next }; return controller
    }
    private func getEngine() throws -> NativeFaceEngine {
        if let engine = engine { return engine }
        guard let path = Bundle.main.resourceURL?.appendingPathComponent("models").path else { throw photoError("No están disponibles los modelos de reconocimiento.") }
        let created = try NativeFaceEngine(models: path); engine = created; return created
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let store = store else { fail(result, photoError("No se pudo preparar el almacenamiento temporal. Libera espacio y vuelve a abrir la app.")); return }
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "initialize":
            consumeInbox()
            session.load { AnalysisNotifications.status { notifications in
                result(["platform": "ios", "access": store.access, "incoming": self.incoming,
                        "notifications": notifications, "backgroundMode": BackgroundAnalysis.capability,
                        "search": self.session.value as Any? ?? NSNull()])
                self.incoming = []
            }}
        case "searchSnapshot": session.load { result(self.session.value) }
        case "updateSearch": session.update(args); result(nil)
        case "notifications": AnalysisNotifications.status { result($0) }
        case "requestNotifications": AnalysisNotifications.request { result($0) }
        case "notificationSettings":
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }; result(nil)
        case "albums": worker.async { self.reply(result, store.catalog()) }
        case "managePhotoAccess":
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited, let controller = presenter else { result(nil); return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in result(nil) }
        case "requestAccess": PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in self.worker.async { self.reply(result, store.catalog()) } }
        case "albumPhotos":
            guard let id = args["id"] as? String else { fail(result, photoError("Álbum no válido.")); return }
            worker.async { do { self.reply(result, try store.albumPhotos(id)) } catch { self.fail(result, error) } }
        case "pick":
            guard pickerRequest == nil, operation == nil, let presenter = presenter,
                  !presenter.isBeingDismissed, !presenter.isBeingPresented else { fail(result, photoError("Termina la acción actual antes de abrir el selector.")); return }
            let request = PhotoPreparation<[String]>(requestID: args["requestId"] as? Int) { [weak self] request, value in
                guard let self = self else { return }
                if self.pickerRequest === request {
                    if request.operation.cancelled { self.pickerProgress?.cancel(); self.pickerController?.dismiss(animated: true) }
                    self.pickerRequest = nil; self.pickerController = nil; self.pickerProgress = nil
                }
                switch value { case .success(let ids): result(ids); case .failure(let error): self.fail(result, error) }
            }
            pickerRequest = request
            let kind = args["kind"] as? String ?? "photos"; pickerSingle = kind == "reference"
            if kind == "files" {
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: false)
                picker.allowsMultipleSelection = true; picker.delegate = self; pickerController = picker; presenter.present(picker, animated: true)
                picker.presentationController?.delegate = self
            } else {
                var configuration = PHPickerConfiguration(photoLibrary: .shared()); configuration.filter = .images
                configuration.selectionLimit = pickerSingle ? 1 : 0; configuration.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: configuration); picker.delegate = self; pickerController = picker; presenter.present(picker, animated: true)
                picker.presentationController?.delegate = self
            }
        case "reference":
            guard operation == nil, pickerRequest == nil, let id = args["id"] as? String else { fail(result, photoError("Elige una foto de referencia.")); return }
            let request = PhotoPreparation<[String: Any]>(requestID: args["requestId"] as? Int) { [weak self] request, value in
                guard let self = self else { return }
                if self.referenceRequest === request {
                    self.referenceRequest = nil
                    if self.operation === request.operation { self.operation = nil }
                }
                switch value { case .success(let reference): result(reference); case .failure(let error): self.fail(result, error) }
            }
            referenceRequest = request
            let operation = request.operation; self.operation = operation
            request.startTimeout(after: Self.preparationTimeout, error: photoError("La foto tardó demasiado en prepararse. Descárgala en Fotos y vuelve a elegirla, o prueba otra imagen."))
            worker.async { store.load(id, operation: operation) { data in self.worker.async {
                do {
                    guard !operation.cancelled else { throw photoError("Cambio de referencia cancelado.") }
                    let pixels = try PhotoStore.decode(data.get(), edge: 3200)
                    let engine = try self.getEngine()
                    var reference = try engine.referenceRGBA(pixels.data, width: Int32(pixels.width), height: Int32(pixels.height)) as! [String: Any]
                    if operation.cancelled { if let token = reference["token"] as? String { engine.releaseReference(token) }; throw photoError("Cambio de referencia cancelado.") }
                    reference["image"] = id
                    DispatchQueue.main.async {
                        if !request.finish(.success(reference)), let token = reference["token"] as? String {
                            self.worker.async { engine.releaseReference(token) }
                        }
                    }
                } catch { DispatchQueue.main.async { request.finish(.failure(error)) } }
            }}}
        case "releaseReference": if let token = args["token"] as? String { worker.async { self.engine?.releaseReference(token) } }; result(nil)
        case "image":
            guard let id = args["id"] as? String else { fail(result, photoError("Fotografía no válida.")); return }
            let edge = max(64, min(1600, args["edge"] as? Int ?? 512)), crop = args["crop"] as? [Double]
            previews.addOperation { store.load(id) { data in self.previews.addOperation {
                do { self.reply(result, FlutterStandardTypedData(bytes: try PhotoStore.preview(data.get(), edge: edge, crop: crop))) }
                catch { self.fail(result, error) }
            }}}
        case "search":
            guard operation == nil, let ids = args["ids"] as? [String], !ids.isEmpty,
                  let faces = args["faces"] as? [String], !faces.isEmpty, let run = args["runId"] as? Int else { fail(result, photoError("Elige una persona y las fotos donde buscar.")); return }
            let operation = PhotoOperation(); self.operation = operation; finishing = false
            session.begin(run: run, context: args["context"] as? [String: Any] ?? [:])
            pendingSearch = result
            background.start(total: ids.count, onMode: { mode in
                self.session.mode(mode)
                self.sink?(["type": "status", "runId": run, "backgroundMode": mode])
            }, onExpired: { [weak self, weak operation] in
                guard let self = self, let operation = operation else { return }
                operation.cancel()
                self.finish(run, operation: operation, error: "iOS detuvo el análisis en segundo plano. Revisa los resultados parciales y vuelve a buscar.")
            }, work: {
                self.worker.async {
                    do { self.resetDiagnostics(); _ = try self.getEngine().prepareFaces(faces); self.search(ids, index: 0, run: run, operation: operation) }
                    catch { self.finish(run, operation: operation, error: error.localizedDescription) }
                }
                self.pendingSearch?(["backgroundMode": self.session.value?["backgroundMode"] as Any? ?? BackgroundAnalysis.capability])
                self.pendingSearch = nil
            })
        case "cancelPreparation":
            let id = args["requestId"] as? Int
            if let request = pickerRequest, request.requestID == id { request.cancel(photoError("Carga cancelada. Puedes elegir otra foto.")) }
            if let request = referenceRequest, request.requestID == id { request.cancel(photoError("Carga cancelada. Puedes elegir otra foto.")) }
            result(nil)
        case "cancel":
            if let request = referenceRequest { request.cancel(photoError("Carga cancelada. Puedes elegir otra foto.")) }
            else { operation?.cancel() }
            result(nil)
        case "clear":
            guard operation == nil else { fail(result, photoError("Cancela el análisis antes de borrar la sesión.")); return }
            session.clear()
            worker.async { do { self.engine?.clear(); try store.clear(); self.reply(result, nil) } catch { self.fail(result, error) } }
        case "share":
            guard !sharing, let ids = args["ids"] as? [String], !ids.isEmpty else { fail(result, photoError("Selecciona las fotografías que quieres compartir.")); return }
            sharing = true; share(ids, index: 0, urls: [], result: result)
        case "settings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else { result(nil); return }; UIApplication.shared.open(url); result(nil)
        case "cloudSettings": fail(result, photoError("En iPhone usa Fotos para iCloud, Archivos para Google Drive o Compartir → Halladin desde Google Fotos."))
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func search(_ ids: [String], index: Int, run: Int, operation: PhotoOperation) {
        guard !operation.cancelled, index < ids.count else { finish(run, operation: operation); return }
        guard let store = store else { finish(run, operation: operation); return }
        let id = ids[index]
        let readStart = ProcessInfo.processInfo.systemUptime
        store.load(id, operation: operation) { data in self.worker.async { autoreleasepool {
            if operation.cancelled { self.finish(run, operation: operation); return }
            var diagnostics: [String: Int] = ["readMs": Int((ProcessInfo.processInfo.systemUptime-readStart)*1000), "decodeMs": 0]
            var event: [String: Any] = ["type": "photo", "runId": run, "id": id, "outcome": "unreadable"]
            do {
                let bytes = try data.get()
                let key = "ios/imageio-srgb-rgba8/opencv4.12/yunet+sface-v1/" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let engine = try self.getEngine()
                let matched: [String: Any]
                let cacheStart = ProcessInfo.processInfo.systemUptime
                if let cached = engine.cachedMatch(key) as? [String: Any] { matched = cached; diagnostics["cacheHits"] = 1; diagnostics["cacheMisses"] = 0; diagnostics["engineMs"] = Int((ProcessInfo.processInfo.systemUptime-cacheStart)*1000) }
                else {
                    let decodeStart = ProcessInfo.processInfo.systemUptime
                    let pixels = try PhotoStore.decode(bytes, edge: 3200)
                    diagnostics["decodeMs"] = Int((ProcessInfo.processInfo.systemUptime-decodeStart)*1000)
                    let engineStart = ProcessInfo.processInfo.systemUptime
                    matched = try engine.matchRGBA(pixels.data, width: Int32(pixels.width), height: Int32(pixels.height), key: key) as! [String: Any]
                    diagnostics["engineMs"] = Int((ProcessInfo.processInfo.systemUptime-engineStart)*1000)
                    diagnostics["cacheHits"] = 0; diagnostics["cacheMisses"] = 1
                }
                matched.forEach { event[$0.key] = $0.value }
            } catch { /* A read/inference failure stays unreadable, never a negative identity. */ }
            if operation.cancelled { self.finish(run, operation: operation); return }
            self.addDiagnostics(diagnostics)
            self.emit(event); self.search(ids, index: index + 1, run: run, operation: operation)
        }}}
    }
    private func finish(_ run: Int, operation: PhotoOperation, error: String? = nil) {
        let finish = {
            guard self.operation === operation, !self.finishing else { return }
            self.finishing = true
            self.pendingSearch?(["backgroundMode": self.session.value?["backgroundMode"] as Any? ?? BackgroundAnalysis.capability])
            self.pendingSearch = nil
            var event: [String: Any] = ["type": "done", "runId": run, "cancelled": operation.cancelled, "diagnostics": self.diagnosticsSnapshot()]
            if let error = error { event["error"] = error }
            self.session.finish(event) {
                let complete = {
                    guard self.operation === operation else { return }
                    self.background.finish(success: !operation.cancelled && error == nil)
                    self.operation = nil; self.finishing = false
                    self.sink?(event)
                }
                if !operation.cancelled || error != nil {
                    // Keep the task alive until the notification daemon accepts
                    // the request; releasing it first can suspend this process.
                    AnalysisNotifications.finished(matches: self.session.matches, processed: self.session.processed, interrupted: error != nil, run: run, completion: complete)
                } else { complete() }
            }
        }
        if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
    }
    private func openAnalysisIfNeeded() {
        guard let sink = sink, UserDefaults.standard.bool(forKey: "PersonasOpenAnalysis") else { return }
        UserDefaults.standard.removeObject(forKey: "PersonasOpenAnalysis")
        sink(["type": "openAnalysis"])
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard pickerController === picker, let request = pickerRequest else { return }
        pickerController = nil
        picker.dismiss(animated: true) {
            guard self.pickerRequest === request, request.pending else { return }
            self.importPicked(results, index: 0, ids: [], request: request)
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard pickerController === presentationController.presentedViewController, let request = pickerRequest else { return }
        request.finish(.success([]))
    }
    private func importPicked(_ items: [PHPickerResult], index: Int, ids: [String], request: PhotoPreparation<[String]>) {
        guard pickerRequest === request, request.pending else { return }
        guard index < items.count else { request.finish(.success(ids)); return }
        request.startTimeout(after: Self.preparationTimeout, error: photoError("No se pudo descargar la foto a tiempo. Revisa tu conexión o descárgala en Fotos y vuelve a elegirla."))
        let item = items[index]
        worker.async {
            guard !request.operation.cancelled else { return }
            if let id = item.assetIdentifier, self.store?.access != "none", PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count == 1 {
                DispatchQueue.main.async { self.importPicked(items, index: index + 1, ids: ids + ["ph:" + id], request: request) }
            } else {
                DispatchQueue.main.async { self.importProvider(items, index: index, ids: ids, request: request) }
            }
        }
    }
    private func importProvider(_ items: [PHPickerResult], index: Int, ids: [String], request: PhotoPreparation<[String]>) {
        guard pickerRequest === request, request.pending else { return }
        let item = items[index]
        guard let type = item.itemProvider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            request.finish(.failure(photoError("No se pudo descargar una de las imágenes. Vuelve a elegirla."))); return
        }
        let progress = item.itemProvider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            do {
                guard !request.operation.cancelled else { return }
                guard let url = url, let store = self.store else { throw error ?? photoError("No se pudo descargar la imagen. Revisa la conexión.") }
                let id = try store.copyOriginal(url)
                DispatchQueue.main.async { self.importPicked(items, index: index + 1, ids: ids + [id], request: request) }
            } catch { DispatchQueue.main.async { request.finish(.failure(error)) } }
        }
        pickerProgress = progress
        request.operation.onCancel { [weak progress] in progress?.cancel() }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard pickerController === controller, let request = pickerRequest else { return }
        request.finish(.success([]))
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard pickerController === controller, let request = pickerRequest else { return }
        pickerController = nil
        importDocuments(urls, index: 0, ids: [], request: request)
    }
    private func importDocuments(_ urls: [URL], index: Int, ids: [String], request: PhotoPreparation<[String]>) {
        guard pickerRequest === request, request.pending else { return }
        guard index < urls.count else { request.finish(.success(ids)); return }
        request.startTimeout(after: Self.preparationTimeout, error: photoError("No se pudo preparar el archivo a tiempo. Descárgalo en Archivos y vuelve a elegirlo."))
        worker.async {
            do {
                guard !request.operation.cancelled else { return }
                let url = urls[index]
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let store = self.store else { throw photoError("No se pudo preparar el archivo.") }
                let id = try store.copyOriginal(url)
                DispatchQueue.main.async { self.importDocuments(urls, index: index + 1, ids: ids + [id], request: request) }
            } catch { DispatchQueue.main.async { request.finish(.failure(error)) } }
        }
    }
    private func share(_ ids: [String], index: Int, urls: [URL], result: @escaping FlutterResult) {
        guard index < ids.count else {
            DispatchQueue.main.async {
                guard let presenter = self.presenter else { self.sharing = false; self.fail(result, photoError("No se pudo abrir Compartir.")); return }
                let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = presenter.view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 1, height: 1)
                sheet.completionWithItemsHandler = { _, _, _, _ in urls.forEach { try? FileManager.default.removeItem(at: $0) } }
                presenter.present(sheet, animated: true); self.sharing = false; result(nil)
            }; return
        }
        store?.load(ids[index]) { data in self.worker.async {
            do { guard let store = self.store else { throw photoError("No se pudo compartir la foto.") }; let url = try store.shareFile(data.get()); self.share(ids, index: index + 1, urls: urls + [url], result: result) }
            catch { urls.forEach { try? FileManager.default.removeItem(at: $0) }; DispatchQueue.main.async { self.sharing = false; self.fail(result, error) } }
        }}
    }
    private func consumeInbox() {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PersonasAppGroup") as? String, !group.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group), let store = store else { return }
        worker.async {
            let directory = container.appendingPathComponent("PersonasInbox", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            var ids: [String] = []
            for file in files where !file.lastPathComponent.hasPrefix(".") {
                if let id = try? store.copyOriginal(file) { ids.append(id); try? FileManager.default.removeItem(at: file) }
            }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async { if let sink = self.sink { sink(["type": "incoming", "ids": ids]) } else { self.incoming = ids } }
        }
    }
}
