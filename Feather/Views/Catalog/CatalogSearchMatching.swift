//
//  CatalogSearchMatching.swift
//  AppMaster
//
//  Typo-tolerant, Arabic-aware matching for the company catalog search, in
//  the spirit of the App Store's own search: a query doesn't need to be
//  spelled exactly right, and common Arabic names for popular apps are
//  recognised even when the catalog's own name/description text is in
//  English (searching "انستا" finds "Instagram").
//

import Foundation

enum CatalogSearchMatching {

	// MARK: - Normalization

	/// Lowercases, strips Arabic diacritics/tatweel, unifies common letter
	/// variants (أ/إ/آ -> ا, ى/ئ -> ي, ة -> ه, ؤ -> و), and drops anything
	/// that isn't a letter/digit/space so punctuation and spacing
	/// differences never block a match.
	static func normalize(_ text: String) -> String {
		var result = text.lowercased()

		let diacritics: Set<Character> = [
			"\u{0617}", "\u{0618}", "\u{0619}", "\u{061A}",
			"\u{064B}", "\u{064C}", "\u{064D}", "\u{064E}", "\u{064F}", "\u{0650}",
			"\u{0651}", "\u{0652}", "\u{0653}", "\u{0654}", "\u{0655}", "\u{0656}",
			"\u{0640}"
		]
		result = String(result.filter { !diacritics.contains($0) })

		let letterMap: [Character: Character] = [
			"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
			"ى": "ي", "ئ": "ي",
			"ة": "ه",
			"ؤ": "و"
		]
		result = String(result.map { letterMap[$0] ?? $0 })

		let kept = result.unicodeScalars.filter {
			CharacterSet.alphanumerics.contains($0) || $0 == " "
		}
		result = String(String.UnicodeScalarView(kept))
		while result.contains("  ") {
			result = result.replacingOccurrences(of: "  ", with: " ")
		}
		return result.trimmingCharacters(in: .whitespaces)
	}

	// MARK: - Fuzzy distance

	private static func _editDistance(_ a: [Character], _ b: [Character]) -> Int {
		if a.isEmpty { return b.count }
		if b.isEmpty { return a.count }

		var previous = Array(0...b.count)
		var current = [Int](repeating: 0, count: b.count + 1)

		for i in 1...a.count {
			current[0] = i
			for j in 1...b.count {
				if a[i - 1] == b[j - 1] {
					current[j] = previous[j - 1]
				} else {
					current[j] = 1 + min(previous[j - 1], previous[j], current[j - 1])
				}
			}
			previous = current
		}
		return previous[b.count]
	}

	/// How many typos to tolerate for a query of this length. Short queries
	/// stay strict, or almost anything would match.
	private static func _tolerance(for length: Int) -> Int {
		switch length {
		case 0...2: return 0
		case 3...5: return 1
		default: return 2
		}
	}

	/// True if `query` (already normalized) fuzzy-matches anywhere in
	/// `target` (already normalized): a straight substring, a single word of
	/// `target` within typo distance of `query`, or a run of `target`'s
	/// letters (ignoring the spaces between its words) within typo distance —
	/// so "بيجي" still finds "ببجي" and "instagrm" still finds "instagram".
	static func fuzzyContains(query: String, in target: String) -> Bool {
		guard !query.isEmpty else { return true }
		guard !target.isEmpty else { return false }
		if target.contains(query) { return true }

		let tolerance = _tolerance(for: query.count)
		guard tolerance > 0 else { return false }

		let queryChars = Array(query)
		let words = target.split(separator: " ").map(String.init)

		for word in words where abs(word.count - query.count) <= tolerance {
			if _editDistance(queryChars, Array(word)) <= tolerance { return true }
		}

		let combined = Array(words.joined())
		guard combined.count >= queryChars.count else { return false }

		var start = 0
		while start + queryChars.count <= combined.count {
			let window = Array(combined[start..<(start + queryChars.count)])
			if _editDistance(queryChars, window) <= tolerance { return true }
			start += 1
		}
		return false
	}

	// MARK: - Synonyms

	/// Extra search keywords for well-known apps, so a search hit doesn't
	/// depend on the catalog's own name/description text containing the
	/// Arabic word someone typed. Add more entries any time — the key is the
	/// app's usual (English) name, matched fuzzily against the catalog
	/// entry's name; once that matches, every alias below it is also
	/// accepted as a hit for that same entry.
	private static let _synonyms: [String: [String]] = [
		"instagram": ["انستا", "انستغرام", "انستقرام", "insta"],
		"whatsapp": ["واتساب", "واتس اب", "واتس"],
		"snapchat": ["سناب شات", "سناب"],
		"tiktok": ["تيك توك", "تكتوك", "تيكتوك"],
		"youtube": ["يوتيوب"],
		"facebook": ["فيسبوك", "فيس بوك", "فيس"],
		"telegram": ["تليجرام", "تلغرام", "تيليجرام"],
		"twitter": ["تويتر", "اكس"],
		"pubg": ["ببجي", "بوبجي", "بب جي"],
		"canva": ["كانفا", "كانڤا"],
		"picsart": ["بيكس ارت", "بكسارت", "بيكسارت"],
		"netflix": ["نتفلكس", "نتفليكس"],
		"spotify": ["سبوتيفاي", "سبوتيفي"],
		"free fire": ["فري فاير"],
		"call of duty": ["كول اوف ديوتي", "كود موبايل", "كودم"],
		"minecraft": ["ماين كرافت", "ماينكرافت"],
		"roblox": ["روبلكس", "روبولوكس"]
	]

	/// True if `query` matches an alias registered for an app whose
	/// canonical (English) name fuzzy-matches `appName`.
	static func matchesSynonym(query: String, appName: String) -> Bool {
		let normalizedName = normalize(appName)

		for (canonical, aliases) in _synonyms {
			let normalizedCanonical = normalize(canonical)
			let nameMatchesCanonical =
				fuzzyContains(query: normalizedCanonical, in: normalizedName) ||
				fuzzyContains(query: normalizedName, in: normalizedCanonical)
			guard nameMatchesCanonical else { continue }

			if fuzzyContains(query: query, in: normalizedCanonical) { return true }
			if aliases.contains(where: { fuzzyContains(query: query, in: normalize($0)) }) {
				return true
			}
		}
		return false
	}
}
