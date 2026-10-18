import SwiftUI

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: rect.width * 0.65, y: rect.height), control: CGPoint(x: rect.width * 0.25, y: rect.height * 0.8))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width * 0.6, y: rect.height * 0.3))
        p.closeSubpath()
        return p
    }
}

struct SpeechBubble: View {
    let text: String
    var onDismiss: (() -> Void)? = nil
    @State private var hovering = false
    private let tint = Color(red: 0.94, green: 0.97, blue: 1)
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text).font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.9)).multilineTextAlignment(.center)
                .lineSpacing(3).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.ocean.opacity(hovering ? 0.75 : 0.35))
                        .frame(width: 16, height: 18).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Dismiss bubble")
            }
        }
        .padding(.leading, 16).padding(.trailing, onDismiss == nil ? 16 : 10).padding(.vertical, 12)
        .frame(maxWidth: 252)
        .background(tint.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1))
        .overlay(alignment: .bottom) {
            BubbleTail().fill(tint).frame(width: 12, height: 8).offset(x: 23, y: 7)
        }
        .shadow(color: .ocean.opacity(0.09), radius: 9, y: 4)
        .onHover { hovering = $0 }
    }
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("DeepSeek-chan").font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Picker("Outfit", selection: $model.halloweenMode) {
                    Text("Classic").tag(false)
                    Text("Halloween 🎃").tag(true)
                }.frame(width: 185).controlSize(.small)
                    .help("A little witch outfit, seasonal stories and a moonstep dance.")
                Button { model.settingsPresented = true } label: { Image(systemName: "gearshape").font(.system(size: 18)) }
                    .buttonStyle(.plain).accessibilityLabel("AI Settings")
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 15) {
                    Text(model.isResting ? "Resting ♡" : "Your little companion").font(.system(size: 15, weight: .medium, design: .rounded))
                    Text(model.engine.phase == .reminding ? "Now ♡" : model.clock)
                        .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Color.ocean)
                    Text(model.stateLabel).font(.system(size: 11)).foregroundStyle(Color.ink.opacity(0.55))
                    HStack(spacing: 8) {
                        PillButton(title: "Chat", icon: "bubble", primary: true) { model.openChat() }
                            .disabled(model.isResting || model.engine.phase == .reminding)
                        Button("Dance ♡") { model.preview() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.ocean)
                    }
                    Button(model.isResting ? "End break" : "Rest now") { if model.isResting { model.endRest() } else { model.rest() } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.ocean)
                    Button("Tiny show ✧") { model.tinyShow() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.ocean)
                    Button { model.actionsPresented = true } label: {
                        Label("Actions · \(ActionLibrary.all.count)", systemImage: "sparkles")
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ocean)
                }.frame(width: 210, alignment: .leading)
                VStack(spacing: 12) {
                    SpeechBubble(text: model.speech).frame(width: 265)
                    CompanionView(sleeping: model.isResting, still: !model.dashboardVisible || model.actionsPresented || model.settingsPresented || model.systemSuspended, action: model.petAction, replay: model.replay, calm: model.calmMode, halloween: model.halloweenMode).frame(width: 220, height: 220)
                        .onTapGesture { model.interact(action: 8, context: .pat) }.accessibilityAddTraits(.isButton)
                        .accessibilityHint("Give her a head pat")
                }
            }.frame(height: 315)
            HStack {
                Text("Eye rest").font(.system(size: 12)).foregroundStyle(Color.ink.opacity(0.6))
                ForEach([15, 20, 25, 30, 45, 60], id: \.self) { value in
                    Button { model.setMinutes(value) } label: {
                        Text("\(value)").font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(model.minutes == value ? Color.ocean : .white, in: Capsule())
                            .foregroundStyle(model.minutes == value ? .white : Color.ocean)
                    }.buttonStyle(.plain).accessibilityLabel("Every \(value) minutes")
                }
                Text("min").font(.system(size: 12)).foregroundStyle(Color.ink.opacity(0.6))
            }
            HStack(spacing: 16) {
                Toggle("Sound", isOn: $model.soundEnabled).toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: model.soundEnabled) { _, value in UserDefaults.standard.set(value, forKey: "soundEnabled") }
                Toggle("Little hellos", isOn: $model.littleHellos).toggleStyle(.switch).controlSize(.mini)
                    .help("A little story every 2–3 minutes, including quiet chats. She waits while you type.")
                Toggle("Calm mode", isOn: $model.calmMode).toggleStyle(.switch).controlSize(.mini)
                    .help("Gentler movement and longer pauses between everyday actions. Eye-break reminders stay visible.")
                Spacer()
                Button(model.engine.phase == .paused ? "Resume" : "Pause") { model.togglePause() }.buttonStyle(.plain).foregroundStyle(Color.ocean)
            }.font(.system(size: 11))
        }
        .padding(30).frame(width: 640, height: 560)
        .foregroundStyle(Color.ink)
        .background(LinearGradient(colors: [Color(red: 0.94, green: 0.97, blue: 1), Color(red: 0.93, green: 0.94, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.settingsPresented) { AISettingsView(model: model, service: model.dialogue) }
        .sheet(isPresented: $model.actionsPresented) { ActionLibraryView(model: model) }
    }
}

struct ReminderView: View {
    @ObservedObject var model: AppModel
    @State private var input = ""
    @GestureState private var dragging = false
    var body: some View {
        let centerY = model.panelSize.height - PetPlacement.anchor(in: model.panelSize).y
        ZStack(alignment: .topLeading) {
            if model.bubbleVisible {
            SpeechBubble(text: model.displayedSpeech, onDismiss: model.previewing || model.ambient || model.chatting ? { model.dismissBubble() } : nil)
                .frame(width: 272, height: 86)
                .position(x: model.panelSize.width / 2, y: centerY - 151)
            }
            CompanionView(knocking: isDancing, sleeping: model.isResting, still: model.isDragging || !model.shouldShowReminder || model.systemSuspended, dancing: isDancing, action: model.petAction, replay: model.replay, calm: model.calmMode, halloween: model.halloweenMode)
                .frame(width: 210, height: 210)
                .onTapGesture { model.interact(action: 8, context: .pat) }
                .gesture(DragGesture(minimumDistance: 5)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { _ in model.onPetDrag?(false) }
                    .onEnded { _ in model.onPetDrag?(true) })
                .onChange(of: dragging) { _, active in if !active { model.onPetDrag?(true) } }
                .contextMenu {
                    Button("Chat ♡") { model.openChat() }
                        .disabled(model.isResting || model.engine.phase == .reminding)
                    Button("Head pats") { model.interact(action: 8, context: .pat) }
                    Button(model.halloweenMode ? "Give a treat" : "Feed rice") { model.interact(action: 4, context: .feed) }
                    Button("Wave") { model.interact(action: 1, context: .hello) }
                    Button("Nap") { model.interact(action: 5, context: .resting) }
                    Button("Dance") { model.preview() }
                    Button("Surprise me") { model.surpriseAction() }
                    Button("Tiny show ✧") { model.tinyShow() }
                    Toggle("Halloween outfit 🎃", isOn: $model.halloweenMode)
                    Toggle("Calm mode", isOn: $model.calmMode)
                    Button("Action library…") { model.onActions?() }
                    Menu("More actions") {
                        ForEach(ActionLibrary.categories, id: \.self) { category in
                            Menu(category) {
                                ForEach(ActionLibrary.indices(category: category), id: \.self) { index in
                                    Button(ActionLibrary.all[index].name) { model.playAction(index) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Hide companion") { model.togglePet() }
                    Button("Settings") { model.onSettings?() }
                }
                .position(x: model.panelSize.width / 2, y: centerY)
            if model.isResting {
                HStack(spacing: 14) {
                    Text(model.clock).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    Button("End") { model.endRest() }.buttonStyle(.plain).font(.system(size: 11))
                }.foregroundStyle(Color.ocean).padding(.horizontal, 20).padding(.vertical, 9).background(.white, in: Capsule())
                    .position(x: model.panelSize.width / 2, y: model.panelSize.height - 37)
            } else if isDancing {
                HStack(spacing: 12) {
                    PillButton(title: "Rest 5 min ♡", primary: true) { model.rest() }
                    if !model.previewing {
                        Button("Later") { model.snooze() }.buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ocean)
                            .padding(12).background(.white, in: Capsule())
                    }
                }
                .position(x: model.panelSize.width / 2, y: model.panelSize.height - 37)
            }
            if model.chatting {
                HStack(spacing: 8) {
                    Menu {
                        if model.halloweenMode { Button("Trick or treat 🎃") { model.sendChat("Trick or treat") } }
                        Button("Tell a joke") { model.sendChat("Tell a joke") }
                        Button("Magic trick") { model.sendChat("Magic trick") }
                        Button("Snack time") { model.sendChat("Snack time") }
                        Button("Tiny dance") { model.sendChat("Dance") }
                        Button("One more!") { model.sendChat("Again") }
                    } label: {
                        Image(systemName: "sparkles").font(.system(size: 13))
                            .foregroundStyle(Color.ocean.opacity(0.6)).frame(width: 20, height: 26)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Little things to try").help("Jokes, snacks and tiny shows")
                    TextField("Talk to me…", text: $input).textFieldStyle(.plain)
                        .font(.system(size: 13, design: .rounded))
                        .onSubmit(send)
                        .onChange(of: input) { _, value in
                            if value.count > 300 { input = String(value.prefix(300)) }
                            model.chatDraftChanged(input)
                        }
                        .onDisappear { input = ""; model.chatDraftChanged("") }
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 27, height: 27)
                            .background(Color.ocean.opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.25 : 0.85), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Send message")
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
                .frame(width: 270).foregroundStyle(Color.ink)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .ocean.opacity(0.06), radius: 7, y: 3)
                .position(x: model.panelSize.width / 2, y: model.panelSize.height - 36)
            }
        }.frame(width: model.panelSize.width, height: model.panelSize.height)
            .preferredColorScheme(.light)
    }
    private var isDancing: Bool { !model.isResting && (model.previewing || model.engine.phase == .reminding) }
    private func send() { model.sendChat(input); input = "" }
}

struct AISettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var service: DialogueService
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Her little voice").font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { model.settingsPresented = false }
            }
            Toggle("AI bubbles · DeepSeek", isOn: $service.enabled)
                .onChange(of: service.enabled) { _, value in if !value { model.say(.hello) } }
            Text("English, 中文, 日本語 — a little of each.").font(.system(size: 12)).foregroundStyle(.secondary)
            SecureField(service.hasKey ? "Replace OpenRouter API key" : "OpenRouter API key", text: $key)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save key") { if service.saveKey(key) { key = "" } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Try a line") { model.showHello() }.disabled(!service.enabled || !service.hasKey)
                Spacer()
                if service.hasKey { Button("Remove key") { service.removeKey(); model.say(.hello) } }
            }
            Text(service.status).font(.system(size: 12)).foregroundStyle(Color.ocean)
            Text("Key stays in macOS Keychain. AI sends short prompts and messages you type to OpenRouter. Offline? She uses local phrases.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("DeepSeek V4.1 Flash · 12 automatic + 60 chat requests/hour max").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 460).preferredColorScheme(.light)
    }
}
