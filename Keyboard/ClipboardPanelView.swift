import UIKit

/// Keeps the last things the user copied. Needs Full Access to read the pasteboard.
final class ClipboardStore {
    private static let itemsKey = "clipboardHistory"
    private static let changeKey = "clipboardChangeCount"
    private static let limit = 30

    private var store: UserDefaults = .standard
    private(set) var items: [String] = []

    func configure(store: UserDefaults) {
        self.store = store
        items = store.stringArray(forKey: ClipboardStore.itemsKey) ?? []
    }

    /// Reads the pasteboard only when its content changed, so iOS doesn't show the paste banner every time.
    func captureIfChanged() {
        let board = UIPasteboard.general
        let change = board.changeCount
        guard change != store.integer(forKey: ClipboardStore.changeKey) else { return }
        store.set(change, forKey: ClipboardStore.changeKey)
        guard board.hasStrings, let text = board.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > ClipboardStore.limit { items.removeLast(items.count - ClipboardStore.limit) }
        save()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() { store.set(items, forKey: ClipboardStore.itemsKey) }
}

final class ClipboardPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onInsert: ((String) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?

    private var items: [String] = []
    private let header = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let table = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()
    private var theme = KeyboardTheme.make(dark: false)
    private let headerHeight: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        header.addSubview(titleLabel)
        header.addSubview(closeButton)
        header.addSubview(clearButton)
        addSubview(header)

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 52
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        addSubview(table)

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = UIFont.systemFont(ofSize: 15)
        addSubview(messageLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, items: [String], arabic: Bool, fullAccess: Bool) {
        self.theme = theme
        self.items = items
        backgroundColor = theme.background
        titleLabel.textColor = theme.text
        titleLabel.text = arabic ? "الحافظة" : "Clipboard"
        closeButton.setTitle(arabic ? "رجوع" : "Back", for: .normal)
        clearButton.setTitle(arabic ? "مسح الكل" : "Clear", for: .normal)
        closeButton.tintColor = theme.accent
        clearButton.tintColor = theme.accent
        clearButton.isHidden = items.isEmpty || !fullAccess
        messageLabel.textColor = theme.secondaryText
        if !fullAccess {
            messageLabel.text = arabic
                ? "فعّل Allow Full Access من إعدادات الكيبورد عشان الحافظة تشتغل"
                : "Turn on Allow Full Access in keyboard settings to use the clipboard"
        } else if items.isEmpty {
            messageLabel.text = arabic ? "انسخ أي نص وهيظهر هنا" : "Copied text will appear here"
        } else {
            messageLabel.text = nil
        }
        messageLabel.isHidden = messageLabel.text == nil
        table.isHidden = !messageLabel.isHidden
        table.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        closeButton.frame = CGRect(x: 8, y: 0, width: 80, height: headerHeight)
        clearButton.frame = CGRect(x: bounds.width - 88, y: 0, width: 80, height: headerHeight)
        titleLabel.frame = CGRect(x: 90, y: 0, width: bounds.width - 180, height: headerHeight)
        table.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: bounds.height - headerHeight)
        messageLabel.frame = table.frame.insetBy(dx: 24, dy: 12)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = items[indexPath.row]
        content.textProperties.numberOfLines = 2
        content.textProperties.color = theme.text
        cell.contentConfiguration = content
        cell.backgroundColor = theme.key
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onInsert?(items[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, done in
            guard let self else { return done(false) }
            self.onDelete?(indexPath.row)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func clearTapped() { onClear?() }
}
