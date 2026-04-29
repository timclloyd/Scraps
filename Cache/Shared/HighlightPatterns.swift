import UIKit

enum ValenceBand {
    case positive
    case negative
    case neutral
}

struct HighlightKeyword {
    let pattern: String
    let regex: NSRegularExpression
    let band: ValenceBand
}

enum HighlightPatterns {
    // Keywords to highlight for quick visual scanning. Patterns use word boundaries (\b)
    // to avoid partial matches. Compiled once at load.
    //
    // Valence bands:
    //   positive, negative, and neutral all contribute to the archive minimap;
    //   Theme.minimapColor(for:) maps each band to its strip colour.
    static let keywords: [HighlightKeyword] = {
        let specs: [(String, ValenceBand)] = [
//            ("\\bfun\\b",        .positive),
//            ("\\bgreat\\b",      .positive),
//            ("\\bgrateful\\b",   .positive),
//            ("\\blove\\b",       .positive),
//            ("\\bhappy\\b",      .positive),
//            ("\\bexcited\\b",    .positive),
            ("\\bidea[a-zA-Z]*", .positive),

//            ("\\bsad\\b",        .negative),
//            ("\\banxious\\b",    .negative),
//            ("\\banxiety\\b",    .negative),
//            ("\\bangry\\b",      .negative),
//            ("\\bstress(ed)?\\b",   .negative),
//            ("\\bfuck(ing)?\\b", .negative),

            ("\\bimportant\\b",  .negative),

            ("\\btodo\\b",       .neutral),
            ("\\bremember\\b",   .neutral),
        ]
        return specs.compactMap { pattern, band in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return HighlightKeyword(pattern: pattern, regex: regex, band: band)
        }
    }()

    // Per-band dynamic UIColors. Created once; UIKit resolves the trait closure
    // against the real text-view/widget environment at draw time.
    static let highlightColor: [ValenceBand: UIColor] = [
        .positive: UIColor { traits in
            UIColor.systemGreen.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.4 : 0.22)
        },
        .negative: UIColor { traits in
            UIColor.systemRed.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.4 : 0.22)
        },
        .neutral: UIColor { traits in
            UIColor.systemBlue.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.4 : 0.22)
        },
    ]

    static let strikeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "~~.+?~~")
    }()

    static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
}
