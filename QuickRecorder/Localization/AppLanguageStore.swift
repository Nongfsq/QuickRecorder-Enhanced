import Foundation
import Combine
import SwiftUI

struct AppLocalizedRoot<Content: View>: View {
    @ObservedObject private var store: AppLanguageStore
    private let content: Content

    init(_ content: Content, store: AppLanguageStore = .shared) {
        self.content = content
        self.store = store
    }

    var body: some View {
        content
            .environmentObject(store)
            .environment(\.locale, store.locale)
    }
}

final class AppLanguageStore: ObservableObject {
    struct Language: Identifiable, Equatable {
        let id: String
        let displayName: String
    }

    static let shared = AppLanguageStore()
    static let preferenceKey = "quickRecorder.appLanguage"
    static let systemIdentifier = "system"

    @Published private(set) var selectedIdentifier: String
    @Published private(set) var locale: Locale
    @Published private(set) var selectedBundle: Bundle
    @Published private(set) var restartRecommended = false

    let availableLanguages: [Language]

    private let bundle: Bundle
    private let defaults: UserDefaults
    private let supportedIdentifiers: Set<String>

    private struct LocaleManifest: Decodable {
        struct Entry: Decodable {
            let identifier: String
            let complete: Bool
        }

        let locales: [Entry]
    }

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.defaults = defaults

        let declared = Self.loadDeclaredLocales(from: bundle)
        let embedded = Set(bundle.localizations.map(Self.canonicalIdentifier))
        let availableIdentifiers = declared.filter {
            embedded.contains($0) && bundle.path(forResource: $0, ofType: "lproj") != nil
        }
        supportedIdentifiers = Set(availableIdentifiers)
        availableLanguages = availableIdentifiers.map { identifier in
            let nativeLocale = Locale(identifier: identifier)
            let name = nativeLocale.localizedString(forIdentifier: identifier) ?? identifier
            return Language(id: identifier, displayName: name.capitalized(with: nativeLocale))
        }

        let stored = defaults.string(forKey: Self.preferenceKey) ?? Self.systemIdentifier
        let normalized = Self.canonicalIdentifier(stored)
        let initialIdentifier = supportedIdentifiers.contains(normalized) ? normalized : Self.systemIdentifier
        selectedIdentifier = initialIdentifier
        locale = initialIdentifier == Self.systemIdentifier ? .autoupdatingCurrent : Locale(identifier: initialIdentifier)
        selectedBundle = Self.localizationBundle(for: initialIdentifier, in: bundle) ?? bundle

        if stored != initialIdentifier {
            defaults.set(initialIdentifier, forKey: Self.preferenceKey)
        }
    }

    func select(_ identifier: String) {
        let canonical = Self.canonicalIdentifier(identifier)
        let next = supportedIdentifiers.contains(canonical) ? canonical : Self.systemIdentifier
        guard next != selectedIdentifier else { return }

        selectedIdentifier = next
        locale = next == Self.systemIdentifier ? .autoupdatingCurrent : Locale(identifier: next)
        selectedBundle = Self.localizationBundle(for: next, in: bundle) ?? bundle
        defaults.set(next, forKey: Self.preferenceKey)
        restartRecommended = true
    }

    private static func loadDeclaredLocales(from bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "supported-locales", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LocaleManifest.self, from: data) else {
            return []
        }

        return manifest.locales.compactMap { entry in
            guard entry.complete else { return nil }
            return canonicalIdentifier(entry.identifier)
        }
    }

    private static func localizationBundle(for identifier: String, in bundle: Bundle) -> Bundle? {
        guard identifier != systemIdentifier,
              let path = bundle.path(forResource: identifier, ofType: "lproj") else {
            return identifier == systemIdentifier ? bundle : nil
        }
        return Bundle(path: path)
    }

    private static func canonicalIdentifier(_ identifier: String) -> String {
        guard identifier.caseInsensitiveCompare(systemIdentifier) != .orderedSame else {
            return systemIdentifier
        }
        return Locale(identifier: identifier).identifier.replacingOccurrences(of: "_", with: "-")
    }
}
