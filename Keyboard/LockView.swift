import UIKit

/// Covers the keys when the free trial hasn't started or has ended without a purchase.
/// The globe and hide buttons keep working so the user is never stuck in a locked keyboard.
final class LockView: UIView {
    let globeButton = UIButton(type: .system)
    let hideButton = UIButton(type: .system)
    private let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1)
        icon.tintColor = UIColor(red: 0.13, green: 0.70, blue: 0.59, alpha: 1)
        icon.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = .white
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = UIColor(white: 0.82, alpha: 1)
        for label in [titleLabel, bodyLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
        }
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        hideButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        for button in [globeButton, hideButton] {
            button.tintColor = .white
            button.backgroundColor = UIColor(white: 1, alpha: 0.12)
            button.layer.cornerRadius = 10
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 56).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let text = UIStackView(arrangedSubviews: [icon, titleLabel, bodyLabel])
        text.axis = .vertical
        text.spacing = 8
        text.alignment = .center
        let buttons = UIStackView(arrangedSubviews: [globeButton, UIView(), hideButton])
        buttons.axis = .horizontal
        buttons.semanticContentAttribute = .forceLeftToRight
        for v in [text, buttons] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            text.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(status: AccessStatus, arabic: Bool, showGlobe: Bool) {
        globeButton.isHidden = !showGlobe
        if status == .notStarted {
            titleLabel.text = arabic ? "ابدأ تجربتك المجانية" : "Start your free trial"
            bodyLabel.text = arabic ? "افتح تطبيق ضاد واضغط \"ابدأ التجربة المجانية\" عشان تستخدم الكيبورد 7 أيام ببلاش."
                                    : "Open the Daad app and tap \"Start free trial\" to use the keyboard free for 7 days."
        } else {
            titleLabel.text = arabic ? "انتهت التجربة المجانية" : "Your free trial has ended"
            bodyLabel.text = arabic ? "افتح تطبيق ضاد واشترِ الكيبورد مرة واحدة عشان تكمّل."
                                    : "Open the Daad app and buy the keyboard once to keep typing."
        }
    }
}
