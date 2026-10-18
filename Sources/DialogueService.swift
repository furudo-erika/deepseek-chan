import Foundation
import Security
import Combine

enum BubbleContext: String { case hello, reminder, resting, complete, snooze, feed, pat, chat }

enum LocalDialogue {
    static func line(for context: BubbleContext, avoiding previous: String = "") -> String {
        let lines: [String]
        switch context {
        case .hello: lines = ["偷偷冒个泡 (｡･ω･｡)", "You’ve got this, tiny human ♡", "えへへ、見つかっちゃった", "记得眨眨眼呀 ✨", "Just checking on my favorite human.", "今日もおつかれさま ♡"]
        case .reminder: lines = ["叩叩！眼睛借我休息一下嘛 ♡", "ちょっと休憩しよ？", "Tiny break? Pretty please ♡", "再盯屏幕，我要敲敲你啦！", "おめめ、おやすみ〜", "Five minutes. I’ll guard your desk!"]
        case .resting: lines = ["乖乖看远处，我替你数时间 ♡", "Look far away. I’m right here.", "のんびりしよ〜", "眼睛放假，小鱼值班！", "Your eyes get a tiny vacation ♡"]
        case .complete: lines = ["满血复活！小鱼给你盖个章 ♡", "おかえり〜 ♡", "Welcome back, bright eyes!", "休息任务完成！摸摸头～"]
        case .snooze: lines = ["好叭，五分钟后再来抓你 ♡", "あと5分だけだよ？", "Five more minutes. Pinky promise?", "小鱼记在小本本上了！"]
        case .feed: lines = ["白米饭！小鱼的快乐回来啦！", "もぐもぐ…おいしい ♡", "Rice acquired. Happiness restored!", "啊——再来一口嘛 ♡"]
        case .pat: lines = ["嘿嘿，再摸摸嘛 ♡", "なでなで、すき〜", "Head pats! My only weakness ♡", "已被摸成一条快乐小鱼！"]
        case .chat: lines = ["我在呀，耳朵竖起来啦 ♡", "うんうん、聞いてるよ ♡", "I’m here, little human ♡"]
        }
        return lines.filter { $0 != previous }.randomElement() ?? lines[0]
    }
}

enum DialogueValidation {
    static func clean(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard !text.isEmpty, text.count <= 84,
              text.split(whereSeparator: { $0.isNewline }).count <= 2,
              !text.contains("<"), !text.contains(">"), !text.contains("http"),
              text.split(whereSeparator: { $0.isWhitespace }).count <= 17 else { return nil }
        return text
    }
    static func parse(_ data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = body["choices"] as? [[String: Any]],
              let choice = choices.first, choice["finish_reason"] as? String != "length",
              let message = choice["message"] as? [String: Any],
              let text = message["content"] as? String else { return nil }
        return clean(text)
    }
}

enum CompanionKeychain {
    private static let service = "local.bill.eyewhale.openrouter"
    private static let account = "api-key"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 20, !value.contains(where: { $0.isWhitespace }) else { return false }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func remove() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class DialogueService: ObservableObject {
    static let model = "deepseek/deepseek-v4.1-flash"
    @Published var enabled = UserDefaults.standard.bool(forKey: "aiDialogueEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "aiDialogueEnabled") }
    }
    @Published private(set) var hasKey = false
    @Published private(set) var status = "Local phrases"
    private let session: URLSession
    private let defaults: UserDefaults
    init(session: URLSession? = nil, defaults: UserDefaults = .standard, inspectKeychain: Bool = true) {
        self.defaults = defaults
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 15
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            self.session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        }
        if inspectKeychain { hasKey = CompanionKeychain.read() != nil }
        status = hasKey ? "Ready for DeepSeek" : "Add an OpenRouter key to connect"
    }
    func saveKey(_ key: String) -> Bool {
        guard CompanionKeychain.save(key) else { status = "Couldn’t save key. Please try again."; return false }
        hasKey = true; enabled = true; status = "Key saved in Keychain"
        return true
    }
    func removeKey() {
        guard CompanionKeychain.remove() else { status = "Couldn’t remove key"; return }
        hasKey = false; enabled = false; status = "Local phrases"
    }
    static func request(context: BubbleContext, language: String, key: String, userMessage: String? = nil, actionName: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepSeek-chan", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": 120, "temperature": 0.95,
            "reasoning": ["enabled": false], "stream": false,
            "messages": [
                ["role": "system", "content": "You are DeepSeek-chan, a tiny cute blue-haired whale-maid desktop companion. Write ONE short speech bubble, no explanations or quotes. Warm, playful, a little cheeky, never guilt-tripping. At most 12 English words or 26 Chinese/Japanese characters, at most one cute kaomoji or heart. No medical claims, links, commands, or reasoning. Resting means the human should look away from the screen. Reminders are for a 5-minute eye break. Snooze means return in 5 minutes. Use only the requested language."],
                ["role": "user", "content": userMessage.map { "Your current visible pose is \(actionName ?? "relaxing"). Respond to the actual message, not a generic greeting. For jokes, give a tiny punchline. For comfort, be gentle. Reply in their language: \(String($0.prefix(300)))" } ?? "Occasion: \(context.rawValue). Language: \(language). Give a fresh, adorable little line."]
            ]
        ])
        return request
    }
    func generate(context: BubbleContext, testKey: String? = nil, now: Date = Date(), userMessage: String? = nil, actionName: String? = nil) async -> String? {
        guard enabled || testKey != nil else { return nil }
        guard let key = testKey ?? CompanionKeychain.read(), !key.isEmpty else { status = "Add an OpenRouter key to connect"; return nil }
        let window = Int(now.timeIntervalSince1970 / 3600)
        let manual = userMessage != nil
        let prefix = manual ? "chat" : "dialogue"
        let storedWindow = defaults.integer(forKey: prefix + "RateWindow")
        let count = storedWindow == window ? defaults.integer(forKey: prefix + "RateCount") : 0
        let last = defaults.double(forKey: prefix + "LastRequest")
        guard now.timeIntervalSince1970 - last >= (manual ? 3 : 90), count < (manual ? 60 : 12) else { status = "Local phrase · AI cooldown"; return nil }
        defaults.set(window, forKey: prefix + "RateWindow")
        defaults.set(count + 1, forKey: prefix + "RateCount")
        defaults.set(now.timeIntervalSince1970, forKey: prefix + "LastRequest")
        let language = ["English", "English", "Chinese", "Japanese"].randomElement()!
        status = "Thinking of something cute…"
        do {
            let request = try Self.request(context: context, language: language, key: key, userMessage: userMessage, actionName: actionName)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                status = code == 401 ? "Key rejected · check your key" : code == 402 ? "OpenRouter credit needed" : "AI unavailable · local phrase used"
                return nil
            }
            guard data.count < 64_000, let text = DialogueValidation.parse(data) else { status = "Local phrase used"; return nil }
            status = "Connected · DeepSeek V4.1 Flash"
            return text
        } catch {
            if !(error is CancellationError) { status = "Offline · local phrase used" }
            return nil
        }
    }
}
