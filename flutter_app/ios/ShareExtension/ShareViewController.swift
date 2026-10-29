import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var started = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); guard !started else { return }; started = true
        let text = UILabel(); text.text = "Preparando fotos para Halladin…"; text.numberOfLines = 0; text.textAlignment = .center
        text.translatesAutoresizingMaskIntoConstraints = false; view.backgroundColor = .systemBackground; view.addSubview(text)
        NSLayoutConstraint.activate([text.centerXAnchor.constraint(equalTo: view.centerXAnchor), text.centerYAnchor.constraint(equalTo: view.centerYAnchor), text.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)])
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PersonasAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group), !providers.isEmpty else {
            text.text = "No se pudo recibir la imagen. Revisa la configuración de la extensión."; return
        }
        let inbox = container.appendingPathComponent("PersonasInbox", isDirectory: true)
        do { try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true); var values = URLResourceValues(); values.isExcludedFromBackup = true; var url = inbox; try url.setResourceValues(values) }
        catch { text.text = "No hay espacio para recibir las fotos."; return }
        copy(providers, index: 0, inbox: inbox, text: text)
    }
    private func copy(_ providers: [NSItemProvider], index: Int, inbox: URL, text: UILabel) {
        guard index < providers.count else { DispatchQueue.main.async { text.text = "Fotos recibidas. Abre Halladin para añadirlas a tu búsqueda."; self.extensionContext?.completeRequest(returningItems: nil) }; return }
        let provider = providers[index]
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { fail(text); return }
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            do {
                guard let url = url, (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else { self.fail(text); return }
                let destination = inbox.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
                let temporary = inbox.appendingPathComponent("." + UUID().uuidString)
                try FileManager.default.copyItem(at: url, to: temporary); try FileManager.default.moveItem(at: temporary, to: destination)
                self.copy(providers, index: index + 1, inbox: inbox, text: text)
            } catch { self.fail(text) }
        }
    }
    private func fail(_ text: UILabel) { DispatchQueue.main.async { text.text = "No se pudieron recibir todas las fotos. Vuelve a intentarlo con una selección más pequeña." } }
}
