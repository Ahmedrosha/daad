import UIKit

enum EmojiData {
    static let categories: [(icon: String, emojis: [String])] = [
        ("😀", Array("😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😗😚😙😋😛😜🤪😝🤑🤗🤭🤫🤔🤐🤨😐😑😶😏😒🙄😬😮‍💨🤥😌😔😪🤤😴😷🤒🤕🤢🤮🥵🥶🥴😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈👿💀👻👽🤖💩").map(String.init)),
        ("👍", Array("👋🤚🖐✋🖖👌🤌🤏✌️🤞🤟🤘🤙👈👉👆👇☝️👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏✍️💪🦾🧠👀👁👄💋👶👦👧🧑👨👩🧓👴👵🧕👳👮👷💂🕵️👩‍⚕️👨‍⚕️👩‍🎓👨‍🎓👨‍🍳👩‍💻👨‍💻🤷🤦🙋🙆🙅💁🧏🙇👪💑").map(String.init)),
        ("❤️", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "♥️", "💯", "💢", "💥", "💫", "💦", "💨", "🔥", "✨", "⭐️", "🌟", "⚡️"]),
        ("🐶", Array("🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🐤🦆🦅🦉🐺🐗🐴🦄🐝🐛🦋🐌🐞🐢🐍🦎🐙🦑🦀🐠🐟🐬🐳🦈🐊🐅🐆🦓🐘🦒🐪🐫🐄🐎🐑🐐🐓🦃🕊🐇🐿🌵🌲🌳🌴🌱🌿☘️🍀🍃🍂🍁🌾🌷🌹🥀🌺🌸🌼🌻🌞🌝🌙⭐️🌍☀️⛅️🌧⛈❄️☃️🌈💧🌊").map(String.init)),
        ("🍔", Array("🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶🌽🥕🧄🧅🥔🍠🥐🍞🥖🧀🥚🍳🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🥪🌮🌯🥙🧆🥗🍝🍜🍲🍛🍣🍱🥟🍤🍚🍰🎂🧁🍮🍭🍬🍫🍿🍩🍪🥛☕️🍵🧃🥤🧋🍹🧉🧊").map(String.init)),
        ("⚽️", Array("⚽️🏀🏈⚾️🎾🏐🏉🎱🏓🏸🥊🥋⛳️🎣🤿🎽🛹⛸🏋️🤸⛹️🏊🚴🏆🥇🥈🥉🏅🎖🎗🎫🎪🎭🎨🎬🎤🎧🎼🎹🥁🎷🎺🎸🎻🎲♟🎯🎳🎮🕹🧩").map(String.init)),
        ("🚗", Array("🚗🚕🚙🚌🚎🏎🚓🚑🚒🚐🛻🚚🚛🚜🛵🏍🚲🛴🚨🚔🚍🚘🚖✈️🛫🛬🚀🛸🚁⛵️🚤🛳🚢⚓️⛽️🚧🚦🗺🗽🗼🏰🏯🏟🎡🎢🏖🏝🏜🌋⛰🏔🏕🏠🏡🏢🏬🏥🏦🏨🏪🏫🕌🕋⛪️🌃🌆🌇🌉").map(String.init)),
        ("💡", Array("⌚️📱💻⌨️🖥🖨🖱💾💿📷📸📹🎥📞☎️📺📻🎙⏰⏳📡🔋🔌💡🔦🕯💸💵💶💷💰💳💎⚖️🔧🔨🛠⚙️🔫💣🔪🛡🚬💊💉🩺🧬🔬🔭🧹🧺🧻🚽🛁🔑🗝🚪🛋🛏🎁🎈🎉🎊✉️📩📦📝📁📅📌📎✂️🔒🔓📚📖🔍").map(String.init)),
        ("✅", ["✅", "☑️", "✔️", "❌", "❎", "➕", "➖", "➗", "✖️", "❓", "❔", "❗️", "❕", "‼️", "⁉️", "⚠️", "🚫", "⛔️", "🔞", "♻️", "🆗", "🆕", "🆓", "🔝", "🔜", "🔙", "🔛", "🔚", "▶️", "⏸", "⏹", "⏺", "⏭", "⏮", "🔀", "🔁", "🔂", "⬆️", "⬇️", "⬅️", "➡️", "↩️", "↪️", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫️", "⚪️", "🟤", "🔺", "🔻", "💲", "©️", "®️", "™️", "🕐", "☪️", "🕋", "📿"]),
        ("🏳️", ["🇪🇬", "🇸🇦", "🇦🇪", "🇰🇼", "🇶🇦", "🇧🇭", "🇴🇲", "🇯🇴", "🇱🇧", "🇸🇾", "🇮🇶", "🇵🇸", "🇲🇦", "🇩🇿", "🇹🇳", "🇱🇾", "🇸🇩", "🇾🇪", "🇹🇷", "🇺🇸", "🇬🇧", "🇫🇷", "🇩🇪", "🇮🇹", "🇪🇸", "🇨🇦", "🇧🇷", "🇦🇷", "🇯🇵", "🇨🇳", "🇰🇷", "🇮🇳", "🇵🇰", "🇮🇩", "🇲🇾", "🏳️", "🏴", "🏁", "🚩"]),
    ]
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 30)
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }
}

/// Emoji picker that replaces the keys. Section 0 is "recently used".
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onClose: (() -> Void)?

    private var sections: [(icon: String, emojis: [String])] = []
    private let collection: UICollectionView
    private let bar = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let barHeight: CGFloat = 44

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        addSubview(collection)

        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let config = UIImage.SymbolConfiguration(pointSize: 18)
        backspaceButton.setImage(UIImage(systemName: "delete.left", withConfiguration: config), for: .normal)
        backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        bar.axis = .horizontal
        bar.distribution = .fillEqually
        addSubview(bar)
        addSubview(closeButton)
        addSubview(backspaceButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, recents: [String], closeTitle: String) {
        backgroundColor = theme.background
        closeButton.setTitle(closeTitle, for: .normal)
        closeButton.tintColor = theme.text
        backspaceButton.tintColor = theme.text
        sections = [(icon: "🕘", emojis: recents)] + EmojiData.categories
        bar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, section) in sections.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(section.icon, for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: 18)
            b.tag = i
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            bar.addArrangedSubview(b)
        }
        collection.reloadData()
        if !collection.bounds.isEmpty { collection.setContentOffset(.zero, animated: false) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        collection.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height - barHeight)
        let y = bounds.height - barHeight
        closeButton.frame = CGRect(x: 4, y: y, width: 52, height: barHeight)
        backspaceButton.frame = CGRect(x: w - 52, y: y, width: 48, height: barHeight)
        bar.frame = CGRect(x: 58, y: y, width: w - 116, height: barHeight)
        collection.collectionViewLayout.invalidateLayout()
    }

    // MARK: Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emojis[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let side = floor(collectionView.bounds.width / 8)
        return CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        sections[section].emojis.isEmpty ? .zero : UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onInsert?(sections[indexPath.section].emojis[indexPath.item])
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        let section = sender.tag
        guard sections.indices.contains(section), !sections[section].emojis.isEmpty else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .top, animated: false)
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func backspaceTapped() { onBackspace?() }
}
