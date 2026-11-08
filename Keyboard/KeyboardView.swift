import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTap action: KeyAction)
    func keyboardView(_ view: KeyboardView, insertAlternate text: String)
    func keyboardViewDeleteBackward(_ view: KeyboardView, word: Bool)
    func keyboardViewSwitchLanguage(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, moveCursorBy steps: Int)
    func keyboardView(_ view: KeyboardView, moveCursorLines lines: Int)
    func keyboardView(_ view: KeyboardView, moveCursorToLineEdge right: Bool)
    func keyboardViewCursorGesture(_ view: KeyboardView, began: Bool)
    func keyboardView(_ view: KeyboardView, feedbackFor action: KeyAction)
    func keyboardViewTickFeedback(_ view: KeyboardView)
    func keyboardView(_ view: KeyboardView, didGlide path: [CGPoint], keyCenters: [Character: CGPoint], keyWidth: CGFloat)
    var nextLanguageName: String { get }
    var popupsEnabled: Bool { get }
}

/// Lays out the keys and handles every touch itself, so fast typing and gestures stay smooth.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?
    var glideEnabled = false

    private let trail = CAShapeLayer()

    private var rows: [KeyRow] = []
    private var rowViews: [[KeyView]] = []
    private var maxUnits: CGFloat = 10
    private var theme = KeyboardTheme.make(dark: false)
    private var popup = KeyPopupView(theme: .make(dark: false))
    private var trackers: [ObjectIdentifier: TouchTracker] = [:]

    private let topPadding: CGFloat = 4
    private let bottomPadding: CGFloat = 2

    // Space-bar gesture tuning
    private let holdDelay: TimeInterval = 0.45
    private let cursorStartDistance: CGFloat = 6
    private let cursorStepWidth: CGFloat = 5
    private let flingSpeed: CGFloat = 1800
    private let cursorLineHeight: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        trail.fillColor = UIColor.clear.cgColor
        trail.lineWidth = 6
        trail.lineCap = .round
        trail.lineJoin = .round
        trail.zPosition = 10
        layer.addSublayer(trail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(rows: [KeyRow], maxUnits: CGFloat, theme: KeyboardTheme, look: KeyLook = KeyLook()) {
        cancelAllTouches()
        self.rows = rows
        self.maxUnits = maxUnits
        self.theme = theme
        backgroundColor = theme.background

        rowViews.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        popup.removeFromSuperview()

        rowViews = rows.map { row in
            row.keys.map { key in
                let v = KeyView(key: key, theme: theme, look: look)
                addSubview(v)
                return v
            }
        }
        popup = KeyPopupView(theme: theme)
        addSubview(popup)
        trail.strokeColor = theme.accent.withAlphaComponent(0.7).cgColor
        trail.path = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !rows.isEmpty, bounds.width > 0 else { return }
        let rowHeight = rowHeightValue
        let unit = bounds.width / maxUnits
        for (ri, row) in rows.enumerated() {
            let total = row.keys.reduce(CGFloat(0)) { $0 + $1.width }
            var x = (bounds.width - total * unit) / 2
            let y = topPadding + CGFloat(ri) * rowHeight
            let views = rowViews[ri]
            let order: [Int] = row.rightToLeft ? Array(views.indices.reversed()) : Array(views.indices)
            for i in order {
                let w = row.keys[i].width * unit
                views[i].frame = CGRect(x: x, y: y, width: w, height: rowHeight)
                x += w
            }
        }
    }

    private var rowHeightValue: CGFloat {
        (bounds.height - topPadding - bottomPadding) / CGFloat(max(rows.count, 1))
    }

    /// Finds the key under a point; gaps and edges go to the nearest key in that row.
    private func keyView(at p: CGPoint) -> KeyView? {
        guard !rows.isEmpty else { return nil }
        let rowIndex = min(max(0, Int((p.y - topPadding) / rowHeightValue)), rows.count - 1)
        return rowViews[rowIndex].min { a, b in
            distance(p.x, a.frame) < distance(p.x, b.frame)
        }
    }

    private func distance(_ x: CGFloat, _ r: CGRect) -> CGFloat {
        if x < r.minX { return r.minX - x }
        if x > r.maxX { return x - r.maxX }
        return 0
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            guard let kv = keyView(at: p) else { continue }

            // Fast typing: a new finger commits any letter still held by another finger.
            for (id, tracker) in Array(trackers) where tracker.keyView.key.action.isCharacter && tracker.alternates == nil && !tracker.gliding {
                trackers[id] = nil
                finish(tracker, cancelled: false)
            }

            let tracker = TouchTracker(keyView: kv, start: p)
            trackers[ObjectIdentifier(touch)] = tracker
            begin(tracker)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let tracker = trackers[ObjectIdentifier(touch)] else { continue }
            let p = touch.location(in: self)
            switch tracker.keyView.key.action {
            case .space:
                // After the hold that switches language, a clear move is needed, so a small wobble
                // doesn't cancel the switch.
                let needed = tracker.holdFired ? 22 : cursorStartDistance
                if !tracker.cursorMode && hypot(p.x - tracker.start.x, p.y - tracker.start.y) > needed {
                    tracker.invalidate()
                    tracker.cursorMode = true
                    tracker.holdFired = false
                    tracker.verticalAnchorX = p.x
                    delegate?.keyboardViewCursorGesture(self, began: true)
                    tracker.cursorAnchorX = p.x
                    tracker.cursorAnchorY = p.y
                    tracker.lastPoint = p
                    tracker.lastTime = touch.timestamp
                    tracker.keyView.resetLabel()
                    setCursorModeVisual(true)
                }
                if tracker.cursorMode {
                    // Like a trackpad: small moves are precise, faster moves cover much more ground,
                    // and a quick flick sends the cursor to that end of the line.
                    let dt = max(touch.timestamp - tracker.lastTime, 0.001)
                    let dx = p.x - tracker.lastPoint.x
                    let speed = abs(dx) / CGFloat(dt)                       // points per second
                    tracker.lastPoint = p
                    tracker.lastTime = touch.timestamp

                    if speed > flingSpeed && abs(dx) > 6 {
                        let direction = dx > 0 ? 1 : -1
                        if tracker.edgeReached != direction {
                            tracker.edgeReached = direction
                            delegate?.keyboardView(self, moveCursorToLineEdge: dx > 0)
                            delegate?.keyboardViewTickFeedback(self)
                        }
                        tracker.cursorAnchorX = p.x
                        tracker.cursorAnchorY = p.y
                        continue
                    }
                    if speed < 500 { tracker.edgeReached = 0 }

                    let boost = min(1 + pow(speed / 300, 1.4), 10)
                    tracker.cursorAnchorX -= dx * (boost - 1)               // fast moves count extra

                    let steps = Int((p.x - tracker.cursorAnchorX) / cursorStepWidth)
                    if steps != 0 {
                        delegate?.keyboardView(self, moveCursorBy: steps)
                        delegate?.keyboardViewTickFeedback(self)
                        tracker.cursorAnchorX += CGFloat(steps) * cursorStepWidth
                    }
                    // Up/down only when the finger moves mostly vertically.
                    if abs(p.x - tracker.verticalAnchorX) > 24 {
                        tracker.verticalAnchorX = p.x
                        tracker.cursorAnchorY = p.y
                    }
                    let lines = Int((p.y - tracker.cursorAnchorY) / cursorLineHeight)
                    if lines != 0 {
                        delegate?.keyboardView(self, moveCursorLines: lines)
                        delegate?.keyboardViewTickFeedback(self)
                        tracker.cursorAnchorY += CGFloat(lines) * cursorLineHeight
                    }
                }
            case .character:
                tracker.lastMovePoint = p
                if let alt = tracker.alternates {
                    alt.select(atX: p.x)
                } else if tracker.gliding {
                    if let last = tracker.path.last, hypot(p.x - last.x, p.y - last.y) >= 3 {
                        tracker.path.append(p)
                        drawTrail(tracker.path)
                    }
                } else if glideEnabled, trackers.count == 1,
                          hypot(p.x - tracker.start.x, p.y - tracker.start.y) > glideStartDistance(tracker, p) {
                    // Finger left the key: this is a swipe across letters (glide typing).
                    tracker.invalidate()
                    tracker.gliding = true
                    tracker.keyView.isHighlighted = false
                    popup.hide()
                    tracker.path = [tracker.start, p]
                    drawTrail(tracker.path)
                }
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let tracker = trackers[id] else { continue }
            trackers[id] = nil
            finish(tracker, cancelled: false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let tracker = trackers[id] else { continue }
            trackers[id] = nil
            finish(tracker, cancelled: true)
        }
    }

    private func cancelAllTouches() {
        for tracker in trackers.values {
            tracker.invalidate()
            tracker.alternates?.removeFromSuperview()
        }
        trackers.removeAll()
        setCursorModeVisual(false)
    }

    private func begin(_ tracker: TouchTracker) {
        let kv = tracker.keyView
        kv.isHighlighted = true
        delegate?.keyboardView(self, feedbackFor: kv.key.action)

        switch kv.key.action {
        case .character:
            if delegate?.popupsEnabled ?? true {
                popup.show(kv.key.label, over: kv.faceFrameInParent, in: bounds)
                bringSubviewToFront(popup)
            }
            if !kv.key.alternates.isEmpty {
                tracker.timer = schedule(0.4, repeats: false) { [weak self, weak tracker] _ in
                    guard let self, let tracker else { return }
                    self.showAlternates(for: tracker)
                }
            }

        case .backspace:
            delegate?.keyboardViewDeleteBackward(self, word: false)
            tracker.timer = schedule(0.45, repeats: false) { [weak self, weak tracker] _ in
                guard let self, let tracker else { return }
                tracker.timer = self.schedule(0.08, repeats: true) { [weak self, weak tracker] _ in
                    guard let self, let tracker else { return }
                    tracker.repeatCount += 1
                    if tracker.repeatCount > 15 {
                        // After a while, delete whole words (slower so it stays controllable).
                        if tracker.repeatCount % 3 == 0 { self.delegate?.keyboardViewDeleteBackward(self, word: true) }
                    } else {
                        self.delegate?.keyboardViewDeleteBackward(self, word: false)
                    }
                }
            }

        case .arrow:
            delegate?.keyboardView(self, didTap: kv.key.action)
            tracker.timer = schedule(0.4, repeats: false) { [weak self, weak tracker] _ in
                guard let self, let tracker else { return }
                tracker.timer = self.schedule(0.07, repeats: true) { [weak self, weak tracker] _ in
                    guard let self, let tracker else { return }
                    self.delegate?.keyboardView(self, didTap: tracker.keyView.key.action)
                }
            }

        case .space:
            tracker.timer = schedule(holdDelay, repeats: false) { [weak self, weak tracker] _ in
                guard let self, let tracker, !tracker.cursorMode else { return }
                tracker.holdFired = true
                tracker.keyView.setLabel("⇄  " + (self.delegate?.nextLanguageName ?? ""))
                self.delegate?.keyboardViewTickFeedback(self)
            }

        default:
            break
        }
    }

    /// Timers in .common mode keep firing while a finger is down.
    private func schedule(_ interval: TimeInterval, repeats: Bool, _ block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func showAlternates(for tracker: TouchTracker) {
        popup.hide()
        let alt = AlternatesView(items: [tracker.keyView.key.label] + tracker.keyView.key.alternates, theme: theme)
        addSubview(alt)
        alt.place(over: tracker.keyView.faceFrameInParent, in: bounds)
        tracker.alternates = alt
        delegate?.keyboardViewTickFeedback(self)
    }

    private func finish(_ tracker: TouchTracker, cancelled: Bool) {
        tracker.invalidate()
        let kv = tracker.keyView
        kv.isHighlighted = false
        popup.hide()

        if tracker.gliding {
            trail.path = nil
            if !cancelled {
                let (centers, width) = letterKeyCenters()
                delegate?.keyboardView(self, didGlide: tracker.path, keyCenters: centers, keyWidth: width)
            }
            return
        }

        if let alt = tracker.alternates {
            if !cancelled, let text = alt.selectedItem {
                delegate?.keyboardView(self, insertAlternate: text)
            }
            alt.removeFromSuperview()
            return
        }

        if !cancelled, let up = flickUpChar(tracker, end: tracker.lastMovePoint) {
            delegate?.keyboardView(self, insertAlternate: up)
            return
        }

        switch kv.key.action {
        case .space:
            if tracker.cursorMode {
                setCursorModeVisual(false)
                delegate?.keyboardViewCursorGesture(self, began: false)
            } else if tracker.holdFired {
                kv.resetLabel()
                if !cancelled { delegate?.keyboardViewSwitchLanguage(self) }
            } else if !cancelled {
                delegate?.keyboardView(self, didTap: .space)
            }
        case .backspace, .arrow:
            break
        default:
            if !cancelled { delegate?.keyboardView(self, didTap: kv.key.action) }
        }
    }

    /// A mostly-upward move on a key with a flick symbol needs to go further before it counts as glide typing.
    private func glideStartDistance(_ tracker: TouchTracker, _ p: CGPoint) -> CGFloat {
        let base = max(tracker.keyView.bounds.width * 0.75, 22)
        let dx = abs(p.x - tracker.start.x), dy = tracker.start.y - p.y
        if tracker.keyView.key.upChar != nil && dy > dx * 1.5 { return max(base, tracker.keyView.bounds.height * 1.2) }
        return base
    }

    /// The flick-up symbol, if the finger moved clearly upward and stayed near its key.
    private func flickUpChar(_ tracker: TouchTracker, end: CGPoint) -> String? {
        guard let up = tracker.keyView.key.upChar else { return nil }
        let dx = abs(end.x - tracker.start.x), dy = tracker.start.y - end.y
        return dy > 18 && dy > dx * 1.5 ? up : nil
    }

    private func drawTrail(_ points: [CGPoint]) {
        guard points.count > 1 else { trail.path = nil; return }
        let path = UIBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trail.path = path.cgPath
        CATransaction.commit()
    }

    /// Centers of the letter keys (not digits), used by glide typing.
    private func letterKeyCenters() -> ([Character: CGPoint], CGFloat) {
        var centers: [Character: CGPoint] = [:]
        var widths: [CGFloat] = []
        for v in rowViews.flatMap({ $0 }) {
            guard case .character(let text) = v.key.action, text.count == 1,
                  let ch = text.lowercased().first, ch.isLetter else { continue }
            let f = v.faceFrameInParent
            centers[ch] = CGPoint(x: f.midX, y: f.midY)
            widths.append(v.frame.width)
        }
        let width = widths.isEmpty ? 30 : widths.reduce(0, +) / CGFloat(widths.count)
        return (centers, width)
    }

    /// Like iOS: while moving the cursor, the key labels fade out.
    private func setCursorModeVisual(_ on: Bool) {
        for v in rowViews.flatMap({ $0 }) { v.setDimmed(on) }
    }
}

/// Lets UIDevice.playInputClick() work when Full Access is off.
extension KeyboardView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

private final class TouchTracker {
    let keyView: KeyView
    let start: CGPoint
    var timer: Timer?
    var repeatCount = 0
    var holdFired = false
    var cursorMode = false
    var cursorAnchorX: CGFloat = 0
    var cursorAnchorY: CGFloat = 0
    var lastPoint: CGPoint = .zero
    var lastTime: TimeInterval = 0
    var edgeReached = 0     // last flick direction: 1 right, -1 left
    var verticalAnchorX: CGFloat = 0
    lazy var lastMovePoint: CGPoint = start
    var alternates: AlternatesView?
    var gliding = false
    var path: [CGPoint] = []

    init(keyView: KeyView, start: CGPoint) {
        self.keyView = keyView
        self.start = start
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}
