import Foundation

final class MockRouter: URLProtocol, @unchecked Sendable {
    static var calls = 0
    static var statusCode = 200
    static var responseText = "Tiny break? Pretty please ♡"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": Self.responseText]]]])
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct DialogueChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label)
        print("PASS: \(label)")
    }
    @MainActor static func main() async throws {
        check(DialogueValidation.clean("休息一下嘛 ♡") == "休息一下嘛 ♡", "Short Unicode phrases are preserved")
        check(DialogueValidation.clean(String(repeating: "x", count: 85)) == nil, "Long answers are rejected")
        check(DialogueValidation.clean("<think>reasoning</think>") == nil, "Reasoning or markup cannot enter a bubble")
        check(DialogueValidation.parse(Data("{}".utf8)) == nil, "Malformed response falls back")
        let request = try DialogueService.request(context: .reminder, language: "Japanese", key: "fake-test-key")
        check(request.url?.host == "openrouter.ai" && request.httpMethod == "POST", "Request uses only the intended API")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        check(body["max_tokens"] as? Int == 120 && body["model"] as? String == DialogueService.model, "Output budget and model are pinned")
        let chatRequest = try DialogueService.request(context: .chat, language: "English", key: "fake-test-key", userMessage: "讲个笑话", actionName: "Thinking")
        let chatBody = try JSONSerialization.jsonObject(with: chatRequest.httpBody!) as! [String: Any]
        let messages = chatBody["messages"] as! [[String: String]]
        check(messages.count == 2 && messages[1]["content"]!.contains("讲个笑话") && messages[1]["content"]!.contains("Thinking"), "Chat sends the actual message and visible pose without transcript history")
        let name = "EyeWhaleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRouter.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = DialogueService(session: session, defaults: defaults, inspectKeychain: false)
        let now = Date(timeIntervalSince1970: 3600 * 100 + 1)
        let success = await service.generate(context: .reminder, testKey: "fake-test-key", now: now)
        check(success == MockRouter.responseText && MockRouter.calls == 1, "Mock API success returns a short bubble")
        let cooldown = await service.generate(context: .hello, testKey: "fake-test-key", now: now.addingTimeInterval(1))
        check(cooldown == nil && MockRouter.calls == 1, "Rapid clicks do not send more requests")
        MockRouter.statusCode = 401
        let rejected = await service.generate(context: .hello, testKey: "fake-test-key", now: now.addingTimeInterval(100))
        check(rejected == nil && service.status.contains("Key rejected"), "Authentication failure stays local with a useful status")
        MockRouter.statusCode = 200
        MockRouter.responseText = String(repeating: "Too much text ", count: 30)
        let long = await service.generate(context: .hello, testKey: "fake-test-key", now: now.addingTimeInterval(200))
        check(long == nil, "Oversized remote dialogue falls back")
        defaults.set(12, forKey: "dialogueRateCount")
        let limited = await service.generate(context: .hello, testKey: "fake-test-key", now: now.addingTimeInterval(300))
        check(limited == nil && MockRouter.calls == 3, "Hourly request cap stops outbound calls")
        for context in [BubbleContext.hello, .reminder, .resting, .complete, .snooze] {
            check(!LocalDialogue.line(for: context).isEmpty, "Offline dialogue exists for \(context.rawValue)")
        }
        print("All dialogue checks passed. Mock requests only; no paid API calls.")
    }
}
