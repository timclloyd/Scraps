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

    private static func parseTimestamp(from filename: String) -> Date? {
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
                .font(.custom("RobotoMono-Medium", size: 18))
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

        for keyword in HighlightPatterns.keywords {
            keyword.regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range,
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

        HighlightPatterns.strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let font = UIFont(name: Theme.font, size: fontSize)
                ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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

@main
struct CacheWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestScrapWidget()
    }
}
