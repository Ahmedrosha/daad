import Foundation

/// Emoji offered next to word suggestions, and words kept out of suggestions.
enum WordExtras {
    /// Keys are normalized (see Lexicon.normalize).
    static let emoji: [String: String] = {
        let pairs: [(String, String)] = [
            // English
            ("love", "❤️"), ("heart", "❤️"), ("happy", "😊"), ("smile", "😊"), ("laugh", "😂"), ("lol", "😂"),
            ("haha", "😂"), ("sad", "😢"), ("cry", "😭"), ("angry", "😠"), ("cool", "😎"), ("kiss", "😘"),
            ("ok", "👌"), ("okay", "👌"), ("yes", "👍"), ("good", "👍"), ("great", "👏"), ("thanks", "🙏"),
            ("thank", "🙏"), ("please", "🙏"), ("party", "🎉"), ("congrats", "🎉"), ("birthday", "🎂"),
            ("fire", "🔥"), ("hot", "🔥"), ("cold", "🥶"), ("sun", "☀️"), ("rain", "🌧️"), ("coffee", "☕️"),
            ("tea", "🍵"), ("pizza", "🍕"), ("food", "🍽️"), ("car", "🚗"), ("home", "🏠"), ("work", "💼"),
            ("money", "💰"), ("phone", "📱"), ("sleep", "😴"), ("tired", "😩"), ("sick", "🤒"), ("wow", "😮"),
            ("think", "🤔"), ("hello", "👋"), ("hi", "👋"), ("bye", "👋"), ("star", "⭐️"), ("music", "🎵"),
            ("football", "⚽️"), ("gift", "🎁"), ("flower", "🌹"), ("cat", "🐱"), ("dog", "🐶"), ("time", "⏰"),
            ("strong", "💪"), ("pray", "🤲"), ("moon", "🌙"), ("eid", "🌙"),
            // Arabic / Egyptian
            ("حب", "❤️"), ("بحبك", "❤️"), ("قلبي", "❤️"), ("حبيبي", "❤️"), ("حبيبتي", "❤️"), ("فرحان", "😊"),
            ("مبسوط", "😊"), ("ههههه", "😂"), ("هههه", "😂"), ("ههه", "😂"), ("زعلان", "😢"), ("حزين", "😢"),
            ("بعيط", "😭"), ("متضايق", "😞"), ("غضبان", "😠"), ("حلو", "😍"), ("جميل", "😍"), ("تمام", "👌"),
            ("ماشي", "👍"), ("اوك", "👌"), ("شكرا", "🙏"), ("متشكر", "🙏"), ("مبروك", "🎉"), ("عيد", "🌙"),
            ("رمضان", "🌙"), ("كريم", "🌙"), ("نار", "🔥"), ("جامد", "🔥"), ("برد", "🥶"), ("شمس", "☀️"),
            ("مطر", "🌧️"), ("قهوه", "☕️"), ("شاي", "🍵"), ("اكل", "🍽️"), ("بيتزا", "🍕"), ("عربيه", "🚗"),
            ("البيت", "🏠"), ("شغل", "💼"), ("فلوس", "💰"), ("نايم", "😴"), ("تعبان", "😩"), ("عيان", "🤒"),
            ("واو", "😮"), ("بفكر", "🤔"), ("اهلا", "👋"), ("سلام", "👋"), ("ورده", "🌹"), ("هديه", "🎁"),
            ("كوره", "⚽️"), ("الحمدلله", "🤲"), ("يارب", "🤲"), ("دعاء", "🤲"), ("ماشاءالله", "😍"),
            ("قطه", "🐱"), ("كلب", "🐶"), ("صباح", "☀️"), ("تصبح", "🌙"), ("وحشتني", "🥺"), ("ميلاد", "🎂"),
        ]
        var map: [String: String] = [:]
        for (word, e) in pairs { map[Lexicon.normalize(word)] = e }
        return map
    }()

    /// Never suggested, completed or glided to (the user can still type them).
    static let blocked: Set<String> = {
        let words = [
            "fuck", "fucking", "fucked", "fucker", "motherfucker", "shit", "shitty", "bitch", "bitches",
            "asshole", "bastard", "dick", "pussy", "cunt", "whore", "slut", "cock", "wanker", "bollocks",
            "retard", "nigger", "nigga", "faggot", "fag", "twat", "prick", "dickhead",
            "شرموطه", "شرموط", "شراميط", "متناك", "متناكه", "منيك", "منيوك", "معرص", "عرص", "خول",
            "كس", "كسم", "كسمك", "كسمها", "طيز", "زب", "زبي", "احا", "لبوه", "قحبه", "عاهره", "خرا",
            "يلعن", "وسخه", "نيك", "نيكه", "انيك", "تنيك",
        ]
        return Set(words.map(Lexicon.normalize))
    }()

    static func isBlocked(_ word: String) -> Bool {
        blocked.contains(Lexicon.normalize(word))
    }
}
