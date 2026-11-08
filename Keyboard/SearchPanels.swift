import UIKit
import Contacts
#if canImport(Translation)
import Translation
#endif

/// Panel shown above the keys while the user types into the keyboard itself
/// (contact search, text to translate). Results appear above the typed text.
final class SearchPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    struct Row {
        let title: String
        let detail: String
        let insertText: String
        var group: String? = nil      // rows with the same group show under one heading (a contact's name)
        var symbol: String? = nil     // e.g. "phone", "envelope"
    }

    var onClose: (() -> Void)?
    var onInsert: ((String) -> Void)?

    private let header = PanelHeader()
    private let queryLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .plain)
    private let resultLabel = UILabel()
    private let messageLabel = UILabel()
    private var rows: [Row] = []
    private var sections: [(title: String?, rows: [Row])] = []
    private var resultText: String?
    private var theme = KeyboardTheme.make(dark: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        header.actionButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        addSubview(header)

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = 40
        table.sectionHeaderTopPadding = 0
        table.register(UITableViewCell.self, forCellReuseIdentifier: "r")
        addSubview(table)

        resultLabel.numberOfLines = 0
        resultLabel.font = UIFont.systemFont(ofSize: 17)
        addSubview(resultLabel)

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 14)
        addSubview(messageLabel)

        queryLabel.font = UIFont.systemFont(ofSize: 17)
        queryLabel.layer.cornerRadius = 8
        queryLabel.layer.masksToBounds = true
        addSubview(queryLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, title: String, insertTitle: String?) {
        self.theme = theme
        backgroundColor = theme.background
        header.apply(theme: theme, title: title)
        header.actionButton.setTitle(insertTitle, for: .normal)
        header.actionButton.isHidden = true
        queryLabel.backgroundColor = theme.key
        resultLabel.textColor = theme.text
        messageLabel.textColor = theme.secondaryText
        rows = []
        resultText = nil
        table.reloadData()
        update()
    }

    func setQuery(_ query: String, placeholder: String) {
        let text = NSMutableAttributedString()
        if query.isEmpty {
            text.append(NSAttributedString(string: "  " + placeholder, attributes: [.foregroundColor: theme.secondaryText]))
        } else {
            text.append(NSAttributedString(string: "  " + query, attributes: [.foregroundColor: theme.text]))
            text.append(NSAttributedString(string: "|", attributes: [.foregroundColor: theme.accent]))
        }
        queryLabel.attributedText = text
        queryLabel.textAlignment = query.contains(where: TextHelpers.isArabic) || (query.isEmpty && placeholder.contains(where: TextHelpers.isArabic)) ? .right : .left
    }

    func show(rows: [Row]) {
        self.rows = rows
        sections = []
        for row in rows {
            if let last = sections.last, last.title == row.group, row.group != nil {
                sections[sections.count - 1].rows.append(row)
            } else {
                sections.append((row.group, [row]))
            }
        }
        resultText = nil
        messageLabel.text = nil
        table.reloadData()
        update()
    }

    func show(result: String?) {
        resultText = result
        rows = []
        messageLabel.text = nil
        resultLabel.text = result
        resultLabel.textAlignment = (result ?? "").contains(where: TextHelpers.isArabic) ? .right : .left
        update()
    }

    func show(message: String?) {
        messageLabel.text = message
        rows = []
        resultText = nil
        table.reloadData()
        update()
    }

    private func update() {
        table.isHidden = rows.isEmpty
        resultLabel.isHidden = resultText == nil
        messageLabel.isHidden = messageLabel.text == nil
        header.actionButton.isHidden = resultText == nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        header.frame = CGRect(x: 0, y: 0, width: w, height: 36)
        let queryHeight: CGFloat = 36
        queryLabel.frame = CGRect(x: 8, y: bounds.height - queryHeight - 4, width: w - 16, height: queryHeight)
        let area = CGRect(x: 0, y: 36, width: w, height: queryLabel.frame.minY - 40)
        table.frame = area
        resultLabel.frame = area.insetBy(dx: 14, dy: 4)
        messageLabel.frame = area.insetBy(dx: 20, dy: 4)
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sections[section].title else { return nil }
        let label = UILabel()
        label.text = "   " + title
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = theme.text
        label.backgroundColor = theme.background
        return label
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].title == nil ? 0 : 28
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "r", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = row.title
        content.secondaryText = row.detail
        content.textProperties.color = theme.secondaryText
        content.textProperties.font = UIFont.systemFont(ofSize: 14)
        content.secondaryTextProperties.color = theme.text
        content.secondaryTextProperties.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        if let symbol = row.symbol {
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = theme.accent
        }
        cell.contentConfiguration = content
        cell.backgroundColor = theme.key.withAlphaComponent(0.25)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onInsert?(sections[indexPath.section].rows[indexPath.row].insertText)
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func insertTapped() { if let r = resultText { onInsert?(r) } }
}

// MARK: - Contacts

enum ContactsSearcher {
    static var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited { return true }
        return status == .authorized
    }

    static func search(_ query: String, completion: @escaping ([SearchPanelView.Row]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let store = CNContactStore()
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                        CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let predicate = CNContact.predicateForContacts(matchingName: query)
            let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
            var rows: [SearchPanelView.Row] = []
            // One heading per contact; each number/email shows its label (mobile, home, work…).
            for c in contacts.prefix(20) {
                let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for phone in c.phoneNumbers {
                    let number = phone.value.stringValue
                    let label = phone.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "📞"
                    rows.append(.init(title: label, detail: number, insertText: "\(name): \(number)",
                                      group: name, symbol: "phone"))
                }
                for email in c.emailAddresses {
                    let address = String(email.value)
                    let label = email.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "✉️"
                    rows.append(.init(title: label, detail: address, insertText: "\(name): \(address)",
                                      group: name, symbol: "envelope"))
                }
            }
            DispatchQueue.main.async { completion(rows) }
        }
    }
}

// MARK: - Translation (Apple, on device)

enum Translator {
    enum Failure { case unsupportedSystem, notInstalled, failed(String) }

    /// Arabic text goes to English, anything else to Arabic.
    static func translate(_ text: String, completion: @escaping (String?, Failure?) -> Void) {
        let toEnglish = text.contains(where: TextHelpers.isArabic)
        #if canImport(Translation)
        if #available(iOS 26.0, *) {
            let source = Locale.Language(identifier: toEnglish ? "ar" : "en")
            let target = Locale.Language(identifier: toEnglish ? "en" : "ar")
            Task { @MainActor in
                let status = await LanguageAvailability().status(from: source, to: target)
                guard status == .installed else {
                    completion(nil, .notInstalled)
                    return
                }
                do {
                    let session = TranslationSession(installedSource: source, target: target)
                    let response = try await session.translate(text)
                    completion(response.targetText, nil)
                } catch {
                    completion(nil, .failed(error.localizedDescription))
                }
            }
            return
        }
        #endif
        completion(nil, .unsupportedSystem)
    }
}
