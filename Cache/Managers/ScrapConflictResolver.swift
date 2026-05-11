import Foundation

@MainActor
final class ScrapConflictResolver {
    enum Resolution {
        case noOp
        case merged(String)
        case preserveVersions([ScrapConflictPlanner.Version])
        case failed
    }

    func resolution(
        for document: TextDocument,
        conflictVersions: [NSFileVersion]
    ) async -> Resolution {
        let descriptors = conflictVersions.map {
            ConflictVersionDescriptor(
                url: $0.url,
                localizedName: $0.localizedName,
                localizedNameOfSavingComputer: $0.localizedNameOfSavingComputer,
                modificationDate: $0.modificationDate
            )
        }

        let readableVersions = await Task.detached(priority: .userInitiated) {
            descriptors.compactMap { descriptor -> ScrapConflictPlanner.Version? in
                guard let text = Self.readText(from: descriptor) else { return nil }
                return ScrapConflictPlanner.Version(
                    text: text,
                    sourceDescription: Self.sourceDescription(for: descriptor),
                    modificationDate: descriptor.modificationDate
                )
            }
        }.value

        guard readableVersions.count == conflictVersions.count else {
            return .failed
        }

        let baseText = document.hasLocalEditsSinceMergeBase ? document.mergeBaseText : nil

        switch ScrapConflictPlanner.plan(
            baseText: baseText,
            currentText: document.text,
            conflictVersions: readableVersions
        ) {
        case .noOp:
            return .noOp
        case .merged(let text):
            return .merged(text)
        case .preserveVersions(let versions):
            return .preserveVersions(versions)
        }
    }

    private struct ConflictVersionDescriptor: Sendable {
        let url: URL
        let localizedName: String?
        let localizedNameOfSavingComputer: String?
        let modificationDate: Date?
    }

    nonisolated private static func readText(from descriptor: ConflictVersionDescriptor) -> String? {
        do {
            let data = try Data(contentsOf: descriptor.url)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error reading conflict version \(descriptor.localizedName ?? "unknown"): \(error)")
            return nil
        }
    }

    nonisolated private static func sourceDescription(for descriptor: ConflictVersionDescriptor) -> String {
        if let computer = descriptor.localizedNameOfSavingComputer, computer.isEmpty == false {
            return computer
        }
        if let name = descriptor.localizedName, name.isEmpty == false {
            return name
        }
        return "Unknown device"
    }
}
