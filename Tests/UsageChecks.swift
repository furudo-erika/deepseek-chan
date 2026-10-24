import Foundation
import JavaScriptCore

@main struct UsageChecks {
    @MainActor static func main() throws {
        let context = JSContext()!
        context.evaluateScript(try String(contentsOfFile: "desktop/src/usage/core.js", encoding: .utf8))
        context.evaluateScript("function normalized(id, json) { return JSON.stringify(UsageCore.normalize(id, JSON.parse(json))); }")
        let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "Tests/usage-fixtures.json"))) as! [String: Any]
        for provider in UsageProvider.all {
            let input = String(data: try JSONSerialization.data(withJSONObject: fixtures[provider.id]!), encoding: .utf8)!
            let result = context.objectForKeyedSubscript("normalized")!.call(withArguments: [provider.id, input])!.toString()!
            precondition(context.exception == nil)
            let values = try JSONDecoder().decode(UsageValues.self, from: Data(result.utf8))
            precondition(!values.meters.isEmpty || !values.balances.isEmpty)
        }
        precondition(UsageSecrets.cursorCookie("bad token") == nil)
        precondition(!UsageSecrets.validToken("credential\nwith-newline"))
        let headers = UsageSecrets.openCodeHeaders(["type": "oauth", "access": "fixture-session", "metadata": ["server": "https://opencode.ai/console", "orgID": "org_fixture", "email": "PRIVATE"]])!
        precondition(headers["x-org-id"] == "org_fixture" && headers["Authorization"] == "Bearer fixture-session")
        precondition(!headers.values.contains("PRIVATE"))
        precondition(UsageSecrets.openCodeHeaders(["type": "oauth", "access": "fixture-session", "metadata": ["server": "https://untrusted.invalid"]]) == nil)
        print("PASS: native JavaScriptCore bridge decodes all five provider schemas; credential input validation passes")
    }
}
