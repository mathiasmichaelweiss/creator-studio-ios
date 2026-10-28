import Foundation

/// Notion: строки баз, блоки страниц и смена одного поля-выбора (статус).
struct NotionClient {
    typealias JSON = [String: Any]

    let key: String
    var session: URLSession = .shared

    init?(key: String? = NotionKeychain.read()) {
        guard let key, !key.isEmpty else { return nil }
        self.key = key
    }

    /// Все строки источника данных (по 100 за запрос).
    func queryAll(dataSource: String) async throws -> [JSON] {
        var all: [JSON] = []
        var cursor: String?
        repeat {
            var body: JSON = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let data = try await send("data_sources/\(dataSource)/query", method: "POST", body: body)
            let page = try NotionParser.list(data)
            all += page.results
            cursor = page.nextCursor
        } while cursor != nil
        return all
    }

    /// Блоки страницы верхнего уровня.
    func blocks(of pageId: String) async throws -> [JSON] {
        var all: [JSON] = []
        var cursor: String?
        repeat {
            var path = "blocks/\(pageId)/children?page_size=100"
            if let cursor { path += "&start_cursor=\(cursor)" }
            let data = try await send(path, method: "GET", body: nil)
            let page = try NotionParser.list(data)
            all += page.results
            cursor = page.nextCursor
        } while cursor != nil
        return all
    }

    /// Меняет поле-выбор на странице, например «Статус» = «Снято».
    func setSelect(pageId: String, property: String, value: String) async throws {
        _ = try await send("pages/\(pageId)", method: "PATCH",
                           body: NotionWrite.selectBody(property: property, value: value))
    }

    /// Проверка ключа и доступа: один запрос к базе «Сценарии».
    func check() async throws {
        let data = try await send("data_sources/\(NotionConfig.scriptsDataSource)/query",
                                  method: "POST", body: ["page_size": 1])
        _ = try NotionParser.list(data)
    }

    private func send(_ path: String, method: String, body: JSON?, attempt: Int = 0) async throws -> Data {
        guard let url = URL(string: path, relativeTo: NotionConfig.baseURL) else { throw NotionError.badResponse }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(NotionConfig.apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Лимит Notion: 3 запроса в секунду. Подождать и повторить до трёх раз.
        if status == 429, attempt < 3 {
            try await Task.sleep(for: .seconds(1 + attempt))
            return try await send(path, method: method, body: body, attempt: attempt + 1)
        }
        if (200..<300).contains(status) { return data }
        // Тело ошибки Notion содержит понятный код (unauthorized, object_not_found…).
        if let obj = try? JSONSerialization.jsonObject(with: data) as? JSON, obj["object"] as? String == "error" {
            throw NotionError.api(code: obj["code"] as? String ?? "", message: obj["message"] as? String ?? "")
        }
        throw NotionError.http(status)
    }
}
