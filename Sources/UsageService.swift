import Foundation
import Combine
import Security
import LocalAuthentication
import JavaScriptCore
import SQLite3
import CryptoKit

struct UsageMeter: Codable { let label: String; let used: Double; let remaining: Double; let resetsAt: Double? }
struct UsageBalance: Codable { let currency: String; let amount: Double }
struct UsageValues: Codable { let meters: [UsageMeter]; let balances: [UsageBalance] }
struct UsageProvider: Identifiable {
    let id: String; let name: String; let kind: String; let endpoint: String; let guide: String
    static let all: [UsageProvider] = [
        .init(id: "codex", name: "Codex", kind: "Plan usage", endpoint: "https://chatgpt.com/backend-api/wham/usage", guide: "Sign in with Codex on this computer."),
        .init(id: "claude", name: "Claude", kind: "Plan usage", endpoint: "https://api.anthropic.com/api/oauth/usage", guide: "Sign in with Claude Code on this computer."),
        .init(id: "grok", name: "Grok", kind: "Plan usage", endpoint: "https://cli-chat-proxy.grok.com/v1/billing?format=credits", guide: "Sign in with Grok Build on this computer."),
        .init(id: "cursor", name: "Cursor", kind: "Plan usage", endpoint: "https://cursor.com/api/usage-summary", guide: "Sign in with Cursor or cursor-agent on this computer."),
        .init(id: "deepseek", name: "DeepSeek", kind: "API balance", endpoint: "https://api.deepseek.com/user/balance", guide: "Add a DeepSeek API key below."),
        .init(id: "openrouter", name: "OpenRouter", kind: "API balance", endpoint: "https://openrouter.ai/api/v1/credits", guide: "Add an OpenRouter key with credits access below.")
    ]
}
struct UsageRow: Identifiable {
    let provider: UsageProvider
    var id: String { provider.id }
    var status = "disconnected"
    var message: String
    var values = UsageValues(meters: [], balances: [])
    var updatedAt: Date?
    var retryAt: Date?
    var generation = 0
}

enum UsageSecrets {
    static let service = "io.github.deepseek-chan.usage"
    static func read(service: String, account: String? = nil) -> String? {
        let auth = LAContext(); auth.interactionNotAllowed = true
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                                   kSecUseAuthenticationContext as String: auth]
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count <= 262144 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    // Client-owned items may grant access to Apple's security utility, rather than this app.
    // Bound the read; stdout is kept in memory and never sent to logs or the renderer.
    static func clientKeychain(_ service: String, account: String? = nil) -> String? {
        guard ["Claude Code-credentials", "cursor-access-token"].contains(service) else { return nil }
        let process = Process(), output = Pipe(), done = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service] + (account.map { ["-a", $0] } ?? []) + ["-w"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + 3) == .timedOut {
            if process.isRunning { process.terminate() }
            if done.wait(timeout: .now() + 0.3) == .timedOut, process.isRunning { kill(process.processIdentifier, SIGKILL); _ = done.wait(timeout: .now() + 0.3) }
            return nil
        }
        guard process.terminationStatus == 0, let data = try? output.fileHandleForReading.read(upToCount: 262145), data.count <= 262144 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func read(_ id: String) -> String? {
        read(service: service, account: id) ?? (id == "openrouter" ? read(service: "local.bill.eyewhale.openrouter", account: "api-key") : nil)
    }
    static func save(_ id: String, key: String) -> Bool {
        guard ["deepseek", "openrouter"].contains(id), validToken(key) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
        let data = Data(key.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func remove(_ id: String) -> Bool {
        guard ["deepseek", "openrouter"].contains(id) else { return false }
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id] as CFDictionary)
        let legacy = id != "openrouter" || CompanionKeychain.remove()
        return (result == errSecSuccess || result == errSecItemNotFound) && legacy
    }
    static func validToken(_ value: String) -> Bool { value.count >= 10 && value.count < 16384 && !value.contains(where: { $0.isWhitespace || $0.isNewline }) }
    static func json(_ path: String) -> [String: Any]? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat(); guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 262144 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 262145)
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count > 0, count <= 262144 else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(bytes.prefix(count)))) as? [String: Any]
    }
    static func object(_ value: String?) -> [String: Any]? {
        guard let value, let data = value.data(using: .utf8), data.count <= 262144 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func cursorCookie(_ raw: String?) -> String? {
        guard let raw, validToken(raw) else { return nil }
        let parts = raw.split(separator: "."); guard parts.count >= 2 else { return nil }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text), let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let subject = claims["sub"] as? String, !subject.isEmpty, subject.count <= 256,
              let escaped = subject.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return "WorkosCursorSessionToken=\(escaped)%3A%3A\(raw)"
    }
    static func cursorDesktopToken(home: String) -> String? {
        let file = home + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        var db: OpaquePointer?; guard sqlite3_open_v2(file, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; return nil }
        defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_bytes(statement, 0) < 16384, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }
    static func credentials(_ id: String) -> [String: String]? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path, env = ProcessInfo.processInfo.environment
        func bearer(_ value: String?) -> [String: String]? { guard let value, validToken(value) else { return nil }; return ["Authorization": "Bearer " + value] }
        switch id {
        case "codex":
            let data = json((env["CODEX_HOME"] ?? home + "/.codex") + "/auth.json")
            guard let tokens = data?["tokens"] as? [String: Any], var headers = bearer(tokens["access_token"] as? String) else { return nil }
            if let account = tokens["account_id"] as? String, validToken(account) { headers["ChatGPT-Account-Id"] = account }
            headers["User-Agent"] = "codex-cli"; headers["OpenAI-Beta"] = "codex-1"; return headers
        case "claude":
            let file = json((env["CLAUDE_CONFIG_DIR"] ?? home + "/.claude") + "/.credentials.json")
            let data = file ?? object(clientKeychain("Claude Code-credentials", account: NSUserName()))
            guard let oauth = data?["claudeAiOauth"] as? [String: Any], var headers = bearer(oauth["accessToken"] as? String) else { return nil }
            headers["anthropic-beta"] = "oauth-2025-04-20"; headers["User-Agent"] = "claude-code/2.1.0"; return headers
        case "grok":
            for (issuer, value) in json((env["GROK_HOME"] ?? home + "/.grok") + "/auth.json") ?? [:] {
                guard (issuer == "https://auth.x.ai" || issuer.hasPrefix("https://auth.x.ai::")), let entry = value as? [String: Any], var headers = bearer(entry["key"] as? String) else { continue }
                headers["X-XAI-Token-Auth"] = "xai-grok-cli"
                if let user = entry["user_id"] as? String, validToken(user) { headers["x-userid"] = user }; return headers
            }; return nil
        case "cursor":
            let cli = json(home + "/.cursor/auth.json")?["accessToken"] as? String
            guard let cookie = cursorCookie(clientKeychain("cursor-access-token")) ?? cursorCookie(cli) ?? cursorCookie(cursorDesktopToken(home: home)) else { return nil }
            return ["Cookie": cookie, "Origin": "https://cursor.com", "Referer": "https://cursor.com/dashboard"]
        case "deepseek", "openrouter": return bearer(read(id))
        default: return nil
        }
    }
}

@MainActor final class UsageService: ObservableObject {
    @Published var rows = UsageProvider.all.map { UsageRow(provider: $0, message: $0.guide) }
    @Published var busy = false
    @Published var keyStatus = ""
    private var lastAttempt = Date.distantPast
    private var timer: Timer?
    private var fingerprints: [String: String] = [:]
    private var pendingRefresh = false
    private let context: JSContext?
    private let session: URLSession
    init(coreURL: URL? = Bundle.main.url(forResource: "usage-core", withExtension: "js")) {
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        context = JSContext()
        if let url = coreURL, let source = try? String(contentsOf: url, encoding: .utf8) {
            context?.evaluateScript(source)
            context?.evaluateScript("function parseUsage(id, json) { return JSON.stringify(UsageCore.normalize(id, JSON.parse(json))); }")
        }
    }
    func start() {
        refresh()
        if timer == nil { timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    }
    func refresh() {
        guard !busy, Date().timeIntervalSince(lastAttempt) >= 30 else { return }
        lastAttempt = Date(); busy = true
        Task {
            await withTaskGroup(of: Void.self) { group in
                for index in rows.indices { group.addTask { await self.fetch(index) } }
            }
            busy = false
            if pendingRefresh { pendingRefresh = false; lastAttempt = .distantPast; refresh() }
        }
    }
    private func fingerprint(_ headers: [String: String]?) -> String? {
        guard let headers, let data = try? JSONSerialization.data(withJSONObject: headers, options: .sortedKeys) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func sameAccount(_ index: Int, headers: [String: String], generation: Int) async -> Bool {
        guard rows[index].generation == generation else { return false }
        let id = rows[index].id
        let current = await Task.detached(priority: .utility) { UsageSecrets.credentials(id) }.value
        guard rows[index].generation == generation else { return false }
        guard fingerprint(current) != fingerprint(headers) else { return true }
        clear(id); rows[index].message = "Account changed. Refreshing…"; return false
    }
    private func fetch(_ index: Int) async {
        let row = rows[index], generation = row.generation
        let headers = await Task.detached(priority: .utility) { UsageSecrets.credentials(row.id) }.value
        guard rows[index].generation == generation else { return }
        guard let headers else {
            fingerprints.removeValue(forKey: row.id)
            rows[index].status = "disconnected"; rows[index].message = row.provider.guide
            rows[index].retryAt = nil; rows[index].updatedAt = nil; rows[index].values = .init(meters: [], balances: []); return
        }
        let identity = fingerprint(headers)
        if fingerprints[row.id] != identity { rows[index].values = .init(meters: [], balances: []); rows[index].updatedAt = nil; rows[index].retryAt = nil; fingerprints[row.id] = identity }
        if let retry = rows[index].retryAt, retry > Date() { return }
        do {
            var request = URLRequest(url: URL(string: row.provider.endpoint)!); request.httpMethod = "GET"
            request.allHTTPHeaderFields = headers; request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard await sameAccount(index, headers: headers, generation: generation) else { bytes.task.cancel(); return }
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 401 || http.statusCode == 403 {
                bytes.task.cancel(); rows[index].status = "expired"; rows[index].message = "Sign-in expired or access denied. Reconnect in the provider app."; return
            }
            if http.statusCode == 429 {
                bytes.task.cancel(); rows[index].status = "limited"; rows[index].message = "Provider is rate limiting requests. Retrying later."
                rows[index].retryAt = Date().addingTimeInterval(min(3600, max(300, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300))); return
            }
            guard http.statusCode == 200 else { bytes.task.cancel(); throw URLError(.badServerResponse) }
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count > 262144 { bytes.task.cancel(); throw URLError(.dataLengthExceedsMaximum) } }
            guard rows[index].generation == generation else { return }
            guard let json = String(data: data, encoding: .utf8) else { throw URLError(.cannotParseResponse) }
            context?.exception = nil
            guard let normalized = context?.objectForKeyedSubscript("parseUsage")?.call(withArguments: [row.id, json])?.toString(), context?.exception == nil,
                  let clean = normalized.data(using: .utf8), let result = try? JSONDecoder().decode(UsageValues.self, from: clean) else { throw URLError(.cannotParseResponse) }
            guard await sameAccount(index, headers: headers, generation: generation) else { return }
            rows[index].values = result; rows[index].updatedAt = Date(); rows[index].status = "ok"; rows[index].message = ""; rows[index].retryAt = nil
        } catch {
            guard await sameAccount(index, headers: headers, generation: generation) else { return }
            rows[index].status = "error"; rows[index].message = "Could not refresh. Try again later."
        }
    }
    func save(id: String, key: String) {
        guard UsageSecrets.save(id, key: key) else { keyStatus = "Could not save this key in Keychain."; return }
        clear(id); keyStatus = "Saved in macOS Keychain."; refresh()
    }
    func remove(id: String) {
        guard UsageSecrets.remove(id) else { keyStatus = "Could not remove this key."; return }
        clear(id); keyStatus = "Key removed."
    }
    private func clear(_ id: String) {
        if busy { pendingRefresh = true }
        fingerprints.removeValue(forKey: id)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let generation = rows[index].generation + 1
        rows[index] = UsageRow(provider: rows[index].provider, message: rows[index].provider.guide, generation: generation)
        lastAttempt = .distantPast
    }
}
