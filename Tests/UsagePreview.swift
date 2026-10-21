import Foundation
import SwiftUI
import AppKit
import JavaScriptCore
@main struct UsagePreview {
 @MainActor static func main() throws {
  let core=URL(fileURLWithPath:"desktop/src/usage/core.js"), service=UsageService(coreURL:core), context=JSContext()!
  context.evaluateScript(try String(contentsOf:core,encoding:.utf8))
  context.evaluateScript("function parse(id,json){return JSON.stringify(UsageCore.normalize(id,JSON.parse(json)));}")
  let fixtures=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"Tests/usage-fixtures.json"))) as! [String:Any]
  for i in service.rows.indices {let id=service.rows[i].id;let input=String(data:try JSONSerialization.data(withJSONObject:fixtures[id]!),encoding:.utf8)!;let output=context.objectForKeyedSubscript("parse")!.call(withArguments:[id,input])!.toString()!;service.rows[i].values=try JSONDecoder().decode(UsageValues.self,from:Data(output.utf8));service.rows[i].status="ok";service.rows[i].message="";service.rows[i].updatedAt=Date(timeIntervalSince1970:1893450000)}
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let host = NSHostingView(rootView: UsageView(service:service,done:{},refreshOnAppear:false))
  host.frame = NSRect(x:0,y:0,width:510,height:620)
  let window = NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
  window.contentView=host
  host.layoutSubtreeIfNeeded()
  RunLoop.current.run(until:Date().addingTimeInterval(0.2))
  guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {fatalError("Render failed")}
  host.cacheDisplay(in:host.bounds,to:bitmap)
  let png=bitmap.representation(using:.png,properties:[:])!
  try png.write(to:URL(fileURLWithPath:".build/usage-mac-preview.png"))
  print("PASS: native usage preview rendered with synthetic fixtures only")
 }
}
