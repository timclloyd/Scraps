import SwiftUI
import WidgetKit

private struct LatestScrapEntry: TimelineEntry {
    let date: Date
    let scrap: WidgetScrap?
}

private struct WidgetScrap {
    let timestamp: Date
    let text: String
}

private struct WidgetHighlightKeyword {
    let regex: NSRegularExpression
    let band: ValenceBand
}

private struct WidgetHighlightSettings {
    let green: String
    let blue: String
    let red: String

    static let `default` = WidgetHighlightSettings(
        green: "idea",
        blue: "todo\nremember",
        red: "important"
    )

    var keywords: [WidgetHighlightKeyword] {
        makeKeywords(from: green, band: .positive)
            + makeKeywords(from: blue, band: .neutral)
            + makeKeywords(from: red, band: .negative)
    }

    init(green: String, blue: String, red: String) {
        self.green = green
        self.blue = blue
        self.red = red
    }

    init(serialized text: String) {
        var sections: [String: [String]] = [:]
        var currentSection: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
                sections[currentSection!, default: []] = []
            } else if let currentSection {
                sections[currentSection, default: []].append(line)
            }
        }

        self.green = Self.trimStoredSection(sections["green"]) ?? Self.default.green
        self.blue = Self.trimStoredSection(sections["blue"]) ?? Self.default.blue
        self.red = Self.trimStoredSection(sections["red"]) ?? Self.default.red
    }

    private static func trimStoredSection(_ lines: [String]?) -> String? {
        guard var lines else { return nil }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func makeKeywords(from text: String, band: ValenceBand) -> [WidgetHighlightKeyword] {
        text.components(separatedBy: .newlines).compactMap { rawTerm in
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = "\\b\(escaped)[a-zA-Z]*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return WidgetHighlightKeyword(regex: regex, band: band)
        }
    }
}

private struct LatestScrapProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestScrapEntry {
        LatestScrapEntry(
            date: Date(),
            scrap: WidgetScrap(
                timestamp: Date(),
                text: "Latest scrap appears here."
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestScrapEntry) -> Void) {
        completion(LatestScrapEntry(date: Date(), scrap: LatestScrapStore.loadLatestScrap()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestScrapEntry>) -> Void) {
        let entry = LatestScrapEntry(date: Date(), scrap: LatestScrapStore.loadLatestScrap())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private enum LatestScrapStore {
    private static let ubiquityContainerIdentifier = "iCloud.timlloyd.scraps"

    static func loadLatestScrap() -> WidgetScrap? {
        guard let documentsURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents") else {
            return nil
        }

        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return nil
        }

        let scraps = fileURLs.compactMap { url -> (url: URL, timestamp: Date)? in
            guard let timestamp = parseTimestamp(from: url.lastPathComponent) else { return nil }
            return (url, timestamp)
        }

        guard let latest = scraps.max(by: { $0.timestamp < $1.timestamp }) else { return nil }

        let text = (try? String(contentsOf: latest.url, encoding: .utf8)) ?? ""
        return WidgetScrap(timestamp: latest.timestamp, text: text)
    }

    static func loadHighlightSettings() -> WidgetHighlightSettings {
        guard let settingsURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("scraps-settings.txt"),
              let text = try? String(contentsOf: settingsURL, encoding: .utf8) else {
            return .default
        }

        return WidgetHighlightSettings(serialized: text)
    }

    static func parseTimestamp(from filename: String) -> Date? {
        guard filename.hasPrefix("scrap-"), filename.hasSuffix(".txt") else { return nil }

        let timestampString = filename
            .replacingOccurrences(of: "scrap-", with: "")
            .replacingOccurrences(of: ".txt", with: "")

        let isUTCEncoded = timestampString.hasSuffix("Z")
        let rawTimestampString = isUTCEncoded ? String(timestampString.dropLast()) : timestampString

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = isUTCEncoded ? TimeZone(secondsFromGMT: 0) : TimeZone.current
        return formatter.date(from: rawTimestampString)
    }
}

private struct LatestScrapWidgetView: View {
    let entry: LatestScrapEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                AccessoryCircularScrapView(scrap: entry.scrap)
            case .accessoryInline:
                Text(decoratedAccessoryLine)
                    .widgetAccentable()
            case .accessoryRectangular:
                AccessoryRectangularScrapView(scrap: entry.scrap, colorScheme: colorScheme, displayScale: displayScale)
            default:
                HomeScreenScrapView(scrap: entry.scrap, family: family, colorScheme: colorScheme, displayScale: displayScale)
            }
        }
        .widgetURL(URL(string: "scraps://latest"))
        .containerBackground(Theme.latestPanelBackground, for: .widget)
    }

    private var accessoryLine: String {
        let text = entry.scrap?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Scraps" : text
    }

    private var decoratedAccessoryLine: AttributedString {
        WidgetTextDecorator.attributedString(for: accessoryLine, colorScheme: colorScheme)
    }
}

private struct HomeScreenScrapView: View {
    let scrap: WidgetScrap?
    let family: WidgetFamily
    let colorScheme: ColorScheme
    let displayScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RenderedWidgetText(
                text: displayText,
                fontSize: fontSize,
                colorScheme: colorScheme,
                displayScale: displayScale
            )
        }
        .padding(.top, topPadding)
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.bottom, Theme.textSize)
    }

    private var displayText: String {
        guard let text = scrap?.text, text.isEmpty == false else {
            return "No scraps yet."
        }
        return text
    }

    private var fontSize: CGFloat {
        switch family {
        case .systemSmall:
            return 13
        default:
            return Theme.textSize
        }
    }

    private var topPadding: CGFloat {
        family == .systemSmall ? 14 : 18
    }
}

private struct AccessoryRectangularScrapView: View {
    let scrap: WidgetScrap?
    let colorScheme: ColorScheme
    let displayScale: CGFloat

    var body: some View {
        RenderedWidgetText(
            text: displayText,
            fontSize: 12,
            colorScheme: colorScheme,
            displayScale: displayScale
        )
    }

    private var displayText: String {
        guard let text = scrap?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            return "No scraps yet."
        }
        return text
    }
}

private struct AccessoryCircularScrapView: View {
    let scrap: WidgetScrap?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(initials)
                .font(Theme.font(size: 18, weight: .medium))
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
    }

    private var initials: String {
        let text = scrap?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let first = text.first else { return "S" }
        return String(first).uppercased()
    }
}

private struct RenderedWidgetText: View {
    let text: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    let displayScale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width > 0, size.height > 0 {
                Image(uiImage: WidgetTextRenderer.image(
                    for: text,
                    size: size,
                    fontSize: fontSize,
                    colorScheme: colorScheme,
                    scale: displayScale
                ))
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private enum WidgetTextDecorator {
    static func attributedString(for text: String, colorScheme: ColorScheme) -> AttributedString {
        AttributedString(nsAttributedString(
            for: text,
            font: nil,
            colorScheme: colorScheme,
            includesLinkAttribute: true
        ))
    }

    static func nsAttributedString(
        for text: String,
        font: UIFont?,
        colorScheme: ColorScheme,
        includesLinkAttribute: Bool
    ) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributed = NSMutableAttributedString(string: text)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0

        var baseAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        if let font {
            baseAttributes[.font] = font
        }
        attributed.addAttributes(baseAttributes, range: fullRange)
        let strikeRanges = HighlightPatterns.strikeRanges(in: text, range: fullRange)

        for keyword in LatestScrapStore.loadHighlightSettings().keywords {
            keyword.regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range,
                      !HighlightPatterns.rangeIntersectsStrike(range, strikeRanges: strikeRanges),
                      let color = HighlightPatterns.highlightColor[keyword.band] else { return }
                attributed.addAttribute(
                    .backgroundColor,
                    value: color,
                    range: range
                )
            }
        }

        HighlightPatterns.urlDetector?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, let url = match.url else { return }
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: Theme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            if includesLinkAttribute {
                attributes[.link] = url
            }
            attributed.addAttributes(attributes, range: match.range)
        }

        for range in strikeRanges {
            attributed.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: Theme.linkColor
            ], range: range)
        }

        return attributed
    }
}

private enum WidgetTextRenderer {
    static func image(
        for text: String,
        size: CGSize,
        fontSize: CGFloat,
        colorScheme: ColorScheme,
        scale: CGFloat
    ) -> UIImage {
        let traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            traitCollection.performAsCurrent {
                let font = Theme.uiFont(size: fontSize)
                let attributed = WidgetTextDecorator.nsAttributedString(
                    for: text,
                    font: font,
                    colorScheme: colorScheme,
                    includesLinkAttribute: false
                )
                let textStorage = NSTextStorage(attributedString: attributed)
                let layoutManager = NSLayoutManager()
                let textContainer = NSTextContainer(size: size)

                textContainer.lineFragmentPadding = 0
                textContainer.maximumNumberOfLines = 0
                textContainer.lineBreakMode = .byWordWrapping

                layoutManager.usesFontLeading = false
                layoutManager.addTextContainer(textContainer)
                textStorage.addLayoutManager(layoutManager)

                let glyphRange = layoutManager.glyphRange(for: textContainer)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
            }
        }
    }
}

struct LatestScrapWidget: Widget {
    let kind = "LatestScrapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestScrapProvider()) { entry in
            LatestScrapWidgetView(entry: entry)
        }
        .configurationDisplayName("Latest Scrap")
        .description("Shows the latest scrap.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Highlight Sentiment Widget

private struct SentimentEntry: TimelineEntry {
    let date: Date
    let positive: Int
    let neutral: Int
    let negative: Int
}

private struct SentimentProvider: TimelineProvider {
    func placeholder(in context: Context) -> SentimentEntry {
        SentimentEntry(date: Date(), positive: 5, neutral: 3, negative: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (SentimentEntry) -> Void) {
        completion(SentimentStore.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SentimentEntry>) -> Void) {
        let entry = SentimentStore.load()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private enum SentimentStore {
    private static let ubiquityContainerIdentifier = "iCloud.timlloyd.scraps"

    static func load() -> SentimentEntry {
        var counts: [ValenceBand: Int] = [.positive: 0, .neutral: 0, .negative: 0]

        guard let documentsURL = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier)?
            .appendingPathComponent("Documents") else {
            return SentimentEntry(date: Date(), positive: 0, neutral: 0, negative: 0)
        }

        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let keywords = LatestScrapStore.loadHighlightSettings().keywords

        for url in fileURLs where LatestScrapStore.parseTimestamp(from: url.lastPathComponent) != nil {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(location: 0, length: (text as NSString).length)
            let strikeRanges = HighlightPatterns.strikeRanges(in: text, range: range)
            for keyword in keywords {
                keyword.regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    guard let match,
                          !HighlightPatterns.rangeIntersectsStrike(match.range, strikeRanges: strikeRanges) else { return }
                    counts[keyword.band, default: 0] += 1
                }
            }
        }

        return SentimentEntry(
            date: Date(),
            positive: counts[.positive, default: 0],
            neutral: counts[.neutral, default: 0],
            negative: counts[.negative, default: 0]
        )
    }
}

private struct SentimentWidgetView: View {
    let entry: SentimentEntry

    let innerCornerRadius: CGFloat = 14

    var body: some View {
        SentimentBar(
            positive: entry.positive,
            neutral: entry.neutral,
            negative: entry.negative,
            cornerRadius: innerCornerRadius
        )
        .widgetURL(URL(string: "scraps://latest"))
        .containerBackground(Theme.latestPanelBackground, for: .widget)
    }
}

private struct SentimentBar: View {
    let positive: Int
    let neutral: Int
    let negative: Int
    let cornerRadius: CGFloat

    var body: some View {
        let total = positive + neutral + negative
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { proxy in
            if total == 0 {
                shape.fill(Color(.systemGray5))
            } else {
                HStack(spacing: 0) {
                    if positive > 0 {
                        Theme.minimapColor(for: .positive)
                            .frame(width: proxy.size.width * CGFloat(positive) / CGFloat(total))
                    }
                    if neutral > 0 {
                        Theme.minimapColor(for: .neutral)
                            .frame(width: proxy.size.width * CGFloat(neutral) / CGFloat(total))
                    }
                    if negative > 0 {
                        Theme.minimapColor(for: .negative)
                            .frame(width: proxy.size.width * CGFloat(negative) / CGFloat(total))
                    }
                }
                .clipShape(shape)
                .opacity(0.667)
            }
        }
    }
}

struct HighlightSentimentWidget: Widget {
    let kind = "HighlightSentimentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SentimentProvider()) { entry in
            SentimentWidgetView(entry: entry)
        }
        .configurationDisplayName("Highlight Sentiment")
        .description("Shows the balance of positive, neutral, and negative highlights across all scraps.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CacheWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestScrapWidget()
        HighlightSentimentWidget()
    }
}
