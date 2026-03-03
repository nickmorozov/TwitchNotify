import Cocoa

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var clientIdField: NSTextField!
    private var savedLabel: NSTextField!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Twitch Notifier Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let idLabel = NSTextField(labelWithString: "Client ID:")
        idLabel.font = .systemFont(ofSize: 12)
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(idLabel)

        let currentId = KeychainHelper.shared.retrieve(forKey: "twitch_client_id")
            ?? TwitchConstants.defaultClientId
        clientIdField = NSTextField()
        clientIdField.stringValue = currentId
        clientIdField.placeholderString = "Twitch Client ID"
        clientIdField.font = .systemFont(ofSize: 12)
        clientIdField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clientIdField)

        let saveButton = NSButton(title: "Save", target: self,
                                  action: #selector(saveClientId(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.font = .systemFont(ofSize: 12)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)

        savedLabel = NSTextField(labelWithString: "")
        savedLabel.font = .systemFont(ofSize: 10)
        savedLabel.textColor = .secondaryLabelColor
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(savedLabel)

        let helpLabel = NSTextField(labelWithString: "Register at dev.twitch.tv/console/apps\nRedirect URL: \(TwitchConstants.redirectURI)")
        helpLabel.font = .systemFont(ofSize: 10)
        helpLabel.textColor = .tertiaryLabelColor
        helpLabel.maximumNumberOfLines = 2
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(helpLabel)

        NSLayoutConstraint.activate([
            idLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            idLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            clientIdField.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 6),
            clientIdField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            clientIdField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            saveButton.topAnchor.constraint(equalTo: clientIdField.bottomAnchor, constant: 10),
            saveButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            savedLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            savedLabel.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 8),

            helpLabel.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 10),
            helpLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            helpLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])
    }

    @objc private func saveClientId(_ sender: NSButton) {
        let clientId = clientIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientId.isEmpty {
            KeychainHelper.shared.delete(forKey: "twitch_client_id")
            savedLabel.stringValue = "Cleared (using default)"
        } else {
            KeychainHelper.shared.save(clientId, forKey: "twitch_client_id")
            savedLabel.stringValue = "Saved"
        }
        savedLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
    }
}
