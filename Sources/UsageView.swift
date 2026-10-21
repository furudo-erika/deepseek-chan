import SwiftUI

struct QuotaBubble: View {
    @ObservedObject var service: UsageService
    let details: () -> Void
    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Remaining ♡").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button("Details ›", action: details).buttonStyle(.plain).font(.system(size: 10))
            }.foregroundStyle(Color.ocean)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(service.rows) { row in
                    let meter = row.values.meters.min { $0.remaining < $1.remaining }
                    let old = row.status != "ok" || row.updatedAt.map { Date().timeIntervalSince($0) > 600 } != false
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Text(row.provider.name).fontWeight(.semibold)
                            Spacer(minLength: 1)
                            if let meter { Text("\(Int(meter.remaining.rounded()))%").monospacedDigit() }
                        }.font(.system(size: 10))
                        if let meter {
                            GeometryReader { box in
                                Capsule().fill(Color.ocean.opacity(0.1))
                                Capsule().fill(old ? Color.gray : meter.remaining <= 10 ? Color.orange : Color.ocean)
                                    .frame(width: box.size.width * max(0, min(100, meter.remaining)) / 100)
                            }.frame(height: 5)
                                .accessibilityLabel("\(row.provider.name) \(meter.label): \(Int(meter.remaining.rounded()))% remaining\(old ? ", last known" : "")")
                            Text("\(meter.label)\(old ? " · old" : "")").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        } else if let balance = row.values.balances.first {
                            Text("\(balance.currency) \(balance.amount, specifier: "%.2f")\(old ? " · old" : "")").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.ocean).lineLimit(1)
                            Text("API credits").font(.system(size: 8)).foregroundStyle(.secondary)
                        } else {
                            Text(service.busy ? "Checking…" : row.status == "disconnected" ? "Not connected" : "Unavailable")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                            Color.clear.frame(height: 5)
                        }
                    }.frame(height: 35, alignment: .top)
                }
            }
        }.padding(13).background(Color(red: 0.95, green: 0.98, blue: 1).opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ocean.opacity(0.15), lineWidth: 1))
            .overlay(alignment: .top) { BubbleTail().fill(Color(red: 0.95, green: 0.98, blue: 1)).frame(width: 12, height: 8).rotationEffect(.degrees(180)).offset(y: -7) }
            .foregroundStyle(Color.ink)
    }
}

struct UsageView: View {
    @ObservedObject var service: UsageService
    let done: () -> Void
    var refreshOnAppear = true
    @State private var key = ""
    @State private var provider = "deepseek"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coding Plan").font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("Your quota, a little closer. ♡").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(service.busy ? "Refreshing…" : "Refresh") { service.refresh() }.disabled(service.busy)
                Button("Done", action: done)
            }
            Text("Remaining quota · refreshes every 5 minutes").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(service.rows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(row.provider.name).font(.system(size: 15, weight: .semibold)); Spacer(); Text(row.provider.kind).font(.system(size: 10)).foregroundStyle(.secondary) }
                            ForEach(Array(row.values.meters.enumerated()), id: \.offset) { _, meter in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(meter.label); Spacer(); Text("\(Int(meter.remaining.rounded()))% left").bold().monospacedDigit() }.font(.system(size: 12))
                                    ProgressView(value: meter.remaining, total: 100).tint(meter.remaining <= 10 ? .orange : Color.ocean)
                                    if let reset = meter.resetsAt { Text("Resets \(Date(timeIntervalSince1970: reset / 1000).formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary) }
                                }
                            }
                            ForEach(Array(row.values.balances.enumerated()), id: \.offset) { _, balance in
                                Text("\(balance.currency) \(balance.amount, specifier: "%.2f")").font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Color.ocean)
                            }
                            if !row.message.isEmpty { Text(row.message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            if let updated = row.updatedAt {
                                Text("\(row.status != "ok" || Date().timeIntervalSince(updated) > 600 ? "Last known · " : "Updated ")\(updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(row.status == "ok" ? Color.secondary : Color.orange)
                            }
                        }.padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.frame(maxHeight: 330)
            DisclosureGroup("Connect API balance") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Provider", selection: $provider) { Text("DeepSeek").tag("deepseek"); Text("OpenRouter").tag("openrouter") }.onChange(of: provider) { _, _ in key = "" }
                    SecureField("API key", text: $key).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save key") { service.save(id: provider, key: key); key = "" }.disabled(key.isEmpty)
                        Button("Remove key") { key = ""; service.remove(id: provider) }
                        Text(service.keyStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(.top, 6)
            }.font(.system(size: 12))
            Text("Uses local client sign-ins and read-only provider endpoints. Keys stay on this computer. No prompts or chat history are read. Accounts and emails are not displayed.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 510).foregroundStyle(Color.ink)
            .background(Color(red: 0.94, green: 0.97, blue: 1)).preferredColorScheme(.light)
            .onAppear { if refreshOnAppear { service.start() } }
    }
}
