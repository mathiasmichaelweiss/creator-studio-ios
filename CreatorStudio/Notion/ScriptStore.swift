import Foundation

/// Сценарии из Notion с копией на телефоне: без интернета показываются последние скачанные.
@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var scripts: [Script] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let cache: ScriptCache

    init(cache: ScriptCache = ScriptCache()) {
        self.cache = cache
        if let saved = cache.load() {
            scripts = saved.scripts
            lastSync = saved.date
        }
    }

    var hasKey: Bool { NotionKeychain.hasKey }

    func refresh() async {
        guard !isLoading else { return }
        guard let client = NotionClient() else { error = NotionError.noKey.errorDescription; return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fresh = try await Self.download(client: client)
            scripts = fresh
            lastSync = Date()
            cache.save(CachedScripts(date: lastSync!, scripts: fresh))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Нет связи с Notion. Показываю сохранённые сценарии."
        }
    }

    /// Строки обеих баз, затем текст каждой страницы (по одной, чтобы не упереться в лимит Notion).
    static func download(client: NotionClient) async throws -> [Script] {
        let scriptPages = try await client.queryAll(dataSource: NotionConfig.scriptsDataSource)
        let variantPages = try await client.queryAll(dataSource: NotionConfig.variantsDataSource)
        let forecastPages = try await client.queryAll(dataSource: NotionConfig.forecastsDataSource)

        var scripts = scriptPages.compactMap(NotionParser.script(page:))
        var variants = variantPages.compactMap(NotionParser.variant(page:))

        for i in scripts.indices {
            scripts[i].body.sections = NotionParser.sections(blocks: try await client.blocks(of: scripts[i].id))
        }
        for i in variants.indices {
            variants[i].variant.body.sections =
                NotionParser.sections(blocks: try await client.blocks(of: variants[i].variant.id))
        }
        var forecasts: [(scriptId: String, forecast: Forecast)] = []
        for page in forecastPages {
            guard let id = page["id"] as? String else { continue }
            let blocks = try await client.blocks(of: id)
            if let f = ForecastParser.forecast(page: page, blocks: blocks) { forecasts.append(f) }
        }
        return merge(scripts: scripts, variants: variants, forecasts: forecasts)
    }

    /// Привязка вариаций к сценариям и порядок списка.
    static func merge(scripts: [Script], variants: [(scriptId: String, variant: ScriptVariant)],
                      forecasts: [(scriptId: String, forecast: Forecast)] = []) -> [Script] {
        var result = scripts
        for f in forecasts {
            let key = normalize(f.scriptId)
            if let i = result.firstIndex(where: { normalize($0.id) == key }) { result[i].forecast = f.forecast }
        }
        for v in variants {
            let key = normalize(v.scriptId)
            if let i = result.firstIndex(where: { normalize($0.id) == key }) {
                result[i].variants.append(v.variant)
            }
        }
        return result.sorted {
            let a = ScriptStatus.rank($0.status), b = ScriptStatus.rank($1.status)
            return a != b ? a < b : $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }

    /// Notion отдаёт id то с дефисами, то без.
    static func normalize(_ id: String) -> String { id.replacingOccurrences(of: "-", with: "").lowercased() }
}

struct CachedScripts: Codable, Equatable {
    var date: Date
    var scripts: [Script]
}

/// Копия сценариев в файле приложения.
struct ScriptCache {
    var url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scripts.json")
    }()

    func load() -> CachedScripts? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CachedScripts.self, from: data)
    }

    func save(_ value: CachedScripts) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
