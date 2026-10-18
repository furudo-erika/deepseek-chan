import AppKit
import SwiftUI
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published var engine = TimerEngine()
    @Published var now = Date()
    @Published var soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
    @Published var previewing = false
    @Published var totalBreaks = UserDefaults.standard.integer(forKey: "totalBreaks")
    let dialogue = DialogueService()
    @Published var speech = "Hey, you ♡"
    @Published var ambient = false
    @Published var settingsPresented = false { didSet { if settingsPresented { dismissBubble() } } }
    @Published var actionsPresented = false { didSet { if actionsPresented { dismissBubble() } } }
    @Published var dashboardVisible = true
    @Published var calmMode = UserDefaults.standard.bool(forKey: "calmMode") {
        didSet {
            UserDefaults.standard.set(calmMode, forKey: "calmMode")
            nextAction = Date().addingTimeInterval(calmMode ? 25 : 10)
        }
    }
    @Published var halloweenMode = UserDefaults.standard.bool(forKey: "halloweenMode") {
        didSet {
            guard halloweenMode != oldValue else { return }
            UserDefaults.standard.set(halloweenMode, forKey: "halloweenMode")
            // Changing clothes cancels old queued lines and in-flight AI replies.
            dismissBubble()
            personality = PetPersonality(); idleTurns = 0
            petAction = halloweenMode ? HalloweenTheme.index("hat_hello") : 0
            replay += 1
            speech = halloweenMode ? "New hat. Same tiny menace. ♡" : "Back to my everyday fluff. ♡"
            ambient = true; ambientUntil = Date().addingTimeInterval(7)
            nextAction = Date().addingTimeInterval(10)
            onChange?()
        }
    }
    @Published private(set) var replay = 0
    @Published var favoriteActions = Set(UserDefaults.standard.stringArray(forKey: "favoriteActions") ?? []) {
        didSet { UserDefaults.standard.set(Array(favoriteActions), forKey: "favoriteActions") }
    }
    @Published var favoritesOnly = UserDefaults.standard.bool(forKey: "favoritesOnly") {
        didSet { UserDefaults.standard.set(favoritesOnly, forKey: "favoritesOnly") }
    }
    private var actionShuffle = ActionShuffle()
    private var personality = PetPersonality()
    private var routine = RoutinePlayback()
    private var routineSpeaks = false
    private var routineUsesAI = false
    private var idleTurns = 0
    private var proactive = ProactiveDeck(remaining: UserDefaults.standard.stringArray(forKey: "chatterRemaining") ?? [], last: UserDefaults.standard.string(forKey: "chatterLastID"))
    private var halloweenChatter = ProactiveDeck(remaining: UserDefaults.standard.stringArray(forKey: "halloweenChatterRemaining") ?? [], last: UserDefaults.standard.string(forKey: "halloweenChatterLastID"))
    private var chatterSchedule = ProactiveSchedule()
    private var chatHasDraft = false
    private var routineIsProactive = false
    private var lastPetInteraction = Date()
    @Published var petAction = 0
    @Published var chatting = false
    @Published var petVisible = UserDefaults.standard.object(forKey: "petVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(petVisible, forKey: "petVisible") }
    }
    var onPetDrag: ((Bool) -> Void)?
    var onSettings: (() -> Void)?
    var onActions: (() -> Void)?
    @Published private(set) var isDragging = false
    private var dragBubbleSnapshot = false
    private var dragSizeSnapshot: NSSize?
    private var dragSpeechSnapshot = ""
    private var dragStarted: Date?
    private var nextAction = Date().addingTimeInterval(8)
    var bubbleVisible: Bool { isDragging ? dragBubbleSnapshot : previewing || ambient || chatting || engine.phase == .reminding || isResting }
    var displayedSpeech: String { isDragging ? dragSpeechSnapshot : speech }
    var panelSize: NSSize {
        if isDragging, let dragSizeSnapshot { return dragSizeSnapshot }
        let hasControls = previewing || engine.phase == .reminding || isResting
        return bubbleVisible ? NSSize(width: 320, height: chatting || hasControls ? 440 : 350) : NSSize(width: 240, height: 250)
    }
    func beginDragging() {
        guard !isDragging else { return }
        dragBubbleSnapshot = bubbleVisible; dragSizeSnapshot = panelSize; dragSpeechSnapshot = speech
        isDragging = true
        let started = Date(); dragStarted = started
        routine.pause(now: started)
    }
    func endDragging() {
        isDragging = false; dragSizeSnapshot = nil
        let ended = Date()
        routine.resume(now: ended)
        if let started = dragStarted, let until = ambientUntil { ambientUntil = until.addingTimeInterval(max(0, ended.timeIntervalSince(started))) }
        dragStarted = nil
        nextAction = Date().addingTimeInterval(3)
        onChange?()
    }
    @Published var littleHellos = UserDefaults.standard.object(forKey: "littleHellos") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(littleHellos, forKey: "littleHellos")
            chatterSchedule.schedule(now: Date())
            if !littleHellos && routineIsProactive { routine.cancel() }
        }
    }
    private var speechTask: Task<Void, Never>?
    private var speechGeneration = 0
    private var ambientUntil: Date?
    var onChange: (() -> Void)?
    var onPreview: (() -> Void)?
    private var timer: Timer?
    private var lastMouse = NSEvent.mouseLocation
    private var lastTick = Date()
    private var lastButtons = NSEvent.pressedMouseButtons
    private var lastObservedMouseActivity: Date?
    @Published private(set) var systemSuspended = false
    var minutes: Int { Int(engine.interval / 60) }
    var isResting: Bool { engine.phase == .resting }
    var clock: String {
        let n = Int(ceil(engine.remaining(now: now)))
        return String(format: "%02d:%02d", n / 60, n % 60)
    }
    var title: String {
        switch engine.phase {
        case .waiting: "Move your mouse and I’ll start the timer."
        case .focusing: "You focus. I’ll keep an eye on the time."
        case .reminding: "Knock knock. Your eyes deserve a break."
        case .resting: "Look into the distance. Take it easy."
        case .paused: "I’ll be here when you’re ready."
        }
    }
    var stateLabel: String {
        switch engine.phase {
        case .waiting: "Waiting for your mouse"
        case .focusing: "Focus time"
        case .reminding: "Time for a break"
        case .resting: "Taking a break"
        case .paused: "Reminders paused"
        }
    }
    init() {
        if halloweenMode { petAction = HalloweenTheme.index("hat_hello"); speech = "Your little witch is here. ♡" }
        let stored = UserDefaults.standard.integer(forKey: "intervalMinutes")
        if [15, 20, 25, 30, 45, 60].contains(stored) { engine.interval = Double(stored * 60) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            nc.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            }
        }
    }
    private func suspend() { systemSuspended = true; dismissBubble(); onChange?() }
    private func wake() {
        systemSuspended = false
        chatterSchedule.schedule(now: Date())
        let before = engine.completedBreaks
        engine.wake(now: Date())
        recordCompletions(since: before)
        lastMouse = NSEvent.mouseLocation; lastButtons = NSEvent.pressedMouseButtons; lastTick = Date()
        now = Date(); onChange?()
    }
    var shouldShowReminder: Bool { !systemSuspended && (petVisible || previewing || ambient || chatting || engine.phase == .reminding || engine.phase == .resting) }
    private func recordCompletions(since old: Int) {
        let difference = engine.completedBreaks - old
        if difference > 0 {
            totalBreaks += difference
            UserDefaults.standard.set(totalBreaks, forKey: "totalBreaks")
            showHello(.complete)
        }
    }
    private func tick() {
        guard !systemSuspended else { return }
        now = Date()
        let before = engine.completedBreaks
        if now.timeIntervalSince(lastTick) > 10 { engine.wake(now: now) }
        lastTick = now
        let mouse = NSEvent.mouseLocation
        let buttons = NSEvent.pressedMouseButtons
        let moved = mouse != lastMouse || buttons != lastButtons
        lastMouse = mouse; lastButtons = buttons
        if moved { lastObservedMouseActivity = now }
        let systemIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let idle = min(systemIdle, lastObservedMouseActivity.map { now.timeIntervalSince($0) } ?? systemIdle)
        if !isDragging && !isResting && !previewing && engine.phase != .reminding {
            let wasActive = routine.active
            if let beat = routine.advance(now: now) { applyBeat(beat) }
            if wasActive && !routine.active { nextAction = now.addingTimeInterval(calmMode ? 25 : 12) }
        }
        if !routine.active && (petVisible || dashboardVisible) && !isDragging && now >= nextAction && !isResting && !previewing && !actionsPresented && !settingsPresented && !chatting && engine.phase != .reminding {
            let sleepy = halloweenMode ? HalloweenTheme.sleepyIndices : ActionLibrary.indices(category: "Sleepy time") + [5]
            let choices = idle > 120 ? sleepy : idleActionChoices
            idleTurns += 1
            if idle < 120 && idleTurns % 4 == 0 && !favoritesOnly {
                startRoutine(personality.show(rememberReply: false, halloween: halloweenMode), speaks: false)
            } else { petAction = actionShuffle.next(in: choices, avoiding: petAction) }
            nextAction = now.addingTimeInterval(Double.random(in: calmMode ? 20...35 : 7...15))
        }
        let previous = engine.phase
        engine.tick(now: now, mouseMoved: moved, idle: idle)
        recordCompletions(since: before)
        if previous != .reminding && engine.phase == .reminding && soundEnabled { NSSound(named: "Pop")?.play() }
        if previous != .reminding && engine.phase == .reminding {
            routine.cancel()
            ambient = false; chatting = false; say(.reminder)
        }
        if !isDragging && ambient && !chatting, let until = ambientUntil, now >= until { dismissBubble(reschedule: false) }
        let chatterBlocked = !littleHellos || !petVisible || isDragging || actionsPresented || settingsPresented || previewing || isResting || engine.phase == .reminding || routine.active
        if chatterSchedule.shouldSpeak(now: now, chatOpen: chatting, ambientVisible: ambient, blocked: chatterBlocked, hasDraft: chatHasDraft, idle: min(idle, now.timeIntervalSince(lastPetInteraction))) {
            let story: PetRoutine?
            if halloweenMode {
                story = halloweenChatter.next(in: ProactiveLibrary.halloweenRoutines)
                UserDefaults.standard.set(halloweenChatter.remaining, forKey: "halloweenChatterRemaining")
                UserDefaults.standard.set(halloweenChatter.last, forKey: "halloweenChatterLastID")
            } else {
                story = proactive.next(in: ProactiveLibrary.routines)
                UserDefaults.standard.set(proactive.remaining, forKey: "chatterRemaining")
                UserDefaults.standard.set(proactive.last, forKey: "chatterLastID")
            }
            if let story {
                startRoutine(story, speaks: true, proactive: true)
            } else { chatterSchedule.schedule(now: now) }
        }
        onChange?()
    }
    func setMinutes(_ value: Int) {
        now = Date()
        engine.setInterval(Double(value * 60), now: now)
        UserDefaults.standard.set(value, forKey: "intervalMinutes")
        onChange?()
    }
    func say(_ context: BubbleContext, userMessage: String? = nil, fallback: String? = nil) {
        speechGeneration += 1
        let generation = speechGeneration
        speechTask?.cancel()
        speech = fallback ?? (halloweenMode ? halloweenLine(context) : nil) ?? LocalDialogue.line(for: context, avoiding: speech)
        let actionName = ActionLibrary.action(petAction).name
        speechTask = Task { [weak self] in
            guard let self else { return }
            let line = await dialogue.generate(context: context, userMessage: userMessage, actionName: actionName)
            guard !Task.isCancelled, generation == self.speechGeneration else { return }
            if let line { self.speech = line }
            else if self.routineUsesAI {
                self.routineUsesAI = false
                if let beat = self.routine.current { self.speech = beat.line }
            }
        }
    }
    private func halloweenLine(_ context: BubbleContext) -> String? {
        switch context {
        case .hello, .chat: ["Your little witch is here. ♡", "Trick, treat, or tiny chat?"].first { $0 != speech }
        case .reminder: "Eye-rest spell! Five minutes, please. ♡"
        case .resting: "Five quiet minutes. I'll guard the candy."
        case .complete: "Rest spell complete. Welcome back!"
        case .feed: "A tiny treat for a tiny witch?"
        default: nil
        }
    }
    func dismissBubble(reschedule: Bool = true) {
        routine.cancel(); chatHasDraft = false; routineIsProactive = false
        if reschedule { chatterSchedule.schedule(now: Date()) }
        previewing = false; ambient = false; chatting = false; ambientUntil = nil
        speechGeneration += 1; speechTask?.cancel()
        onChange?()
    }
    func showHello(_ context: BubbleContext = .hello) {
        routine.cancel()
        ambient = true; ambientUntil = Date().addingTimeInterval(9)
        chatterSchedule.schedule(now: Date())
        say(context); onChange?()
    }
    func interact(action: Int, context: BubbleContext) {
        guard !isDragging, !isResting, engine.phase != .reminding else { return }
        if context == .pat || context == .feed {
            previewing = false
            startRoutine(personality.touch(context == .pat ? "pat" : "feed", halloween: halloweenMode), speaks: true)
            onChange?(); return
        }
        routine.cancel()
        petAction = halloweenMode ? HalloweenTheme.wearingCostume(action) : action; replay += 1; nextAction = Date().addingTimeInterval(18)
        showHello(context)
    }
    var idleActionChoices: [Int] {
        HalloweenTheme.choices(enabled: halloweenMode, favorites: favoriteActions, favoritesOnly: favoritesOnly)
    }
    func toggleFavorite(_ id: String) {
        if favoriteActions.contains(id) { favoriteActions.remove(id) } else { favoriteActions.insert(id) }
        if favoriteActions.isEmpty { favoritesOnly = false }
    }
    func playAction(_ index: Int) {
        guard ActionLibrary.all.indices.contains(index), !isDragging, !isResting, engine.phase != .reminding else { return }
        halloweenMode = HalloweenTheme.isHalloween(ActionLibrary.all[index])
        previewing = false; chatting = false; petVisible = true
        routine.cancel()
        petAction = index; replay += 1; nextAction = Date().addingTimeInterval(24)
        speechGeneration += 1; speechTask?.cancel()
        speech = ActionLibrary.all[index].line
        ambient = true; ambientUntil = Date().addingTimeInterval(9)
        chatterSchedule.schedule(now: Date())
        onChange?()
    }
    func surpriseAction() { playAction(actionShuffle.next(in: idleActionChoices, avoiding: petAction)) }
    func openChat() {
        guard !isResting, engine.phase != .reminding else { return }
        routine.cancel(); previewing = false
        lastPetInteraction = Date(); chatterSchedule.schedule(now: Date())
        chatting = true; ambient = true; ambientUntil = nil; petVisible = true
        say(.chat); onChange?(); onPreview?()
    }
    func chatDraftChanged(_ text: String) {
        chatHasDraft = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard chatHasDraft else { return }
        lastPetInteraction = Date(); chatterSchedule.typed(now: Date())
        if routineIsProactive { routine.cancel(); routineIsProactive = false }
    }
    func sendChat(_ raw: String) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !text.isEmpty, !isDragging, !isResting, engine.phase != .reminding else { return }
        previewing = false; chatting = true; ambient = true; ambientUntil = nil; petVisible = true
        lastPetInteraction = Date()
        let reply = personality.reply(to: text, halloween: halloweenMode)
        startRoutine(reply, speaks: true)
        if dialogue.enabled && dialogue.hasKey && reply.name != "Quiet company" {
            routineUsesAI = true
            say(.chat, userMessage: text, fallback: reply.beats.first?.line)
        }
        onChange?()
    }
    private func applyBeat(_ beat: PetBeat) {
        guard let index = ActionLibrary.all.firstIndex(where: { $0.id == beat.action }) else { return }
        petAction = halloweenMode ? HalloweenTheme.wearingCostume(index) : index; replay += 1
        if routineSpeaks && !routineUsesAI { speech = beat.line }
    }
    private func startRoutine(_ show: PetRoutine, speaks: Bool, proactive: Bool = false) {
        routineIsProactive = proactive
        if speaks && !proactive { lastPetInteraction = Date() }
        speechGeneration += 1; speechTask?.cancel()
        routineSpeaks = speaks; routineUsesAI = false
        if let first = routine.start(show, now: Date()) { applyBeat(first) }
        if speaks {
            ambient = true
            ambientUntil = chatting ? nil : Date().addingTimeInterval(show.beats.reduce(0) { $0 + $1.duration } + 1)
            chatterSchedule.schedule(now: Date())
        }
        nextAction = Date().addingTimeInterval(25)
    }
    func tinyShow(rememberReply: Bool = true) {
        guard !isDragging, !isResting, engine.phase != .reminding else { return }
        previewing = false; petVisible = true
        let language = [PetPersonality.Language.english, .english, .chinese, .japanese].randomElement()!
        startRoutine(personality.show(language: language, rememberReply: rememberReply, halloween: halloweenMode), speaks: true); onChange?()
    }
    func togglePet() { petVisible.toggle(); dismissBubble() }
    func togglePause() { dismissBubble(); engine.togglePause(); onChange?() }
    func rest() {
        routine.cancel()
        previewing = false; ambient = false; chatting = false
        engine.startBreak(now: Date()); now = Date(); say(.resting); onChange?()
    }
    func snooze() {
        previewing = false; engine.snooze(now: Date()); now = Date(); showHello(.snooze)
    }
    func endRest() { engine.reset(); dismissBubble() }
    func preview() {
        routine.cancel()
        previewing = true; ambient = false; chatting = false
        say(isResting ? .resting : .reminder)
        onChange?(); onPreview?()
        if soundEnabled { NSSound(named: "Pop")?.play() }
    }
    func closePreview() { dismissBubble() }
    func acceptanceCountdown() {
        lastObservedMouseActivity = Date()
        engine.setInterval(10, now: Date())
        engine.tick(now: Date(), mouseMoved: true, idle: 0)
        onChange?()
    }
}

struct PillButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 19).frame(height: 42)
            .foregroundStyle(primary ? Color.white : Color.ocean)
            .background(primary ? Color.ocean : Color.white.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(primary ? Color.clear : Color.ocean.opacity(0.12)))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    var window: NSWindow!
    var panel: NSPanel!
    var status: NSStatusItem!
    var stateItem: NSMenuItem!
    var pauseItem: NSMenuItem!
    var panelCentral = false
    private var screenDrag: ScreenDrag?
    private var homeAnchor: CGPoint?
    private var centralScreen: CGRect?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DeepSeek-chan", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "Open DeepSeek-chan", action: #selector(showWindow), keyEquivalent: "0")
        appMenu.addItem(withTitle: "Action library…", action: #selector(actions), keyEquivalent: "l")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit DeepSeek-chan", action: #selector(quit), keyEquivalent: "q")
        let root = NSMenuItem(); root.submenu = appMenu; mainMenu.addItem(root); NSApp.mainMenu = mainMenu
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; mainMenu.addItem(editItem)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "DeepSeek-chan"
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: Dashboard(model: model))
        window.center()
        panel = ReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.title = "DeepSeek-chan Companion"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1); panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Only our screen-coordinate drag controller moves the panel.
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: ReminderView(model: model))
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "DeepSeek-chan")
        status.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Waiting for your mouse", action: nil, keyEquivalent: ""); menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open DeepSeek-chan", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Chat", action: #selector(chat), keyEquivalent: "")
        menu.addItem(withTitle: "Action library…", action: #selector(actions), keyEquivalent: "")
        menu.addItem(withTitle: "Show / hide companion", action: #selector(togglePet), keyEquivalent: "")
        menu.addItem(withTitle: "Say hi", action: #selector(hello), keyEquivalent: "")
        menu.addItem(withTitle: "AI Settings…", action: #selector(settings), keyEquivalent: "")
        menu.addItem(withTitle: "Preview reminder", action: #selector(preview), keyEquivalent: "")
        menu.addItem(withTitle: "Take a 5-minute break", action: #selector(rest), keyEquivalent: "")
        pauseItem = NSMenuItem(title: "Pause reminders", action: #selector(pause), keyEquivalent: ""); menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeepSeek-chan", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        model.onChange = { [weak self] in self?.refresh() }
        model.onPreview = { [weak self] in self?.panel.makeKeyAndOrderFront(nil) }
        model.onSettings = { [weak self] in self?.settings() }
        model.onActions = { [weak self] in self?.actions() }
        model.onPetDrag = { [weak self] ended in
            guard let self else { return }
            if ended && screenDrag == nil { return }
            let pointer = NSEvent.mouseLocation
            if screenDrag == nil {
                screenDrag = ScreenDrag(pointerStart: pointer, windowStart: panel.frame.origin)
                model.beginDragging()
            }
            if let screenDrag { panel.setFrameOrigin(screenDrag.position(pointer: pointer)) }
            if ended {
                let anchor = PetPlacement.anchor(in: panel.frame.size)
                let absolute = CGPoint(x: panel.frame.minX + anchor.x, y: panel.frame.minY + anchor.y)
                if let frame = PetPlacement.screen(for: absolute, frames: NSScreen.screens.map(\.visibleFrame)) {
                    panel.setFrameOrigin(PetPlacement.clamped(origin: panel.frame.origin, size: panel.frame.size, to: frame))
                    if panelCentral { centralScreen = frame }
                }
                if !panelCentral {
                    homeAnchor = CGPoint(x: panel.frame.minX + anchor.x, y: panel.frame.minY + anchor.y)
                    saveHomeAnchor()
                }
                screenDrag = nil
                model.endDragging()
            }
        }
        refresh(); showWindow()
        if CommandLine.arguments.contains("--preview") { model.preview() }
        #if DEBUG
        if CommandLine.arguments.contains("--acceptance-countdown") {
            model.acceptanceCountdown()
        }
        #endif
    }
    private func saveHomeAnchor() {
        guard let homeAnchor else { return }
        UserDefaults.standard.set(homeAnchor.x, forKey: "petAnchorX")
        UserDefaults.standard.set(homeAnchor.y, forKey: "petAnchorY")
    }
    func positionPanel(central: Bool, animate: Bool) {
        let mouse = NSEvent.mouseLocation
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard let active = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame else { return }
        let defaults = UserDefaults.standard
        if homeAnchor == nil {
            if let x = defaults.object(forKey: "petAnchorX") as? Double, let y = defaults.object(forKey: "petAnchorY") as? Double {
                homeAnchor = CGPoint(x: x, y: y)
            } else {
                let x = defaults.object(forKey: "petOriginX") as? Double ?? (active.maxX - 258)
                let y = defaults.object(forKey: "petOriginY") as? Double ?? (active.minY + 16)
                homeAnchor = CGPoint(x: x + 120, y: y + 125)
            }
        }
        let homeScreen = PetPlacement.screen(for: homeAnchor!, frames: frames) ?? active
        let corner = PetPlacement.clamped(origin: PetPlacement.origin(anchor: homeAnchor!, size: panel.frame.size), size: panel.frame.size, to: homeScreen)
        if central && (!panelCentral || centralScreen == nil || !frames.contains(centralScreen!)) { centralScreen = active }
        let frame = centralScreen ?? active
        let target = central ? NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2) : corner
        panelCentral = central
        if central && animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrameOrigin(corner)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.65
                panel.animator().setFrameOrigin(target)
            }
        } else { panel.setFrameOrigin(target) }
    }
    func refresh() {
        status.button?.title = model.engine.phase == .focusing || model.isResting ? " \(model.clock)" : ""
        status.button?.toolTip = "DeepSeek-chan · \(model.stateLabel)"
        stateItem.title = model.stateLabel
        pauseItem.title = model.engine.phase == .paused ? "Resume reminders" : "Pause reminders"
        guard screenDrag == nil else { return }
        if model.shouldShowReminder {
            let sizeChanged = panel.frame.size != model.panelSize
            if sizeChanged { panel.setContentSize(model.panelSize) }
            let central = model.previewing || model.engine.phase == .reminding || model.isResting
            let disconnected = !NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
            if !panel.isVisible || panelCentral != central || sizeChanged || disconnected {
                positionPanel(central: central, animate: central && !model.isResting && !panelCentral)
                panel.orderFrontRegardless()
            }
        } else { panel.orderOut(nil) }
    }
    @objc func showWindow() { model.dashboardVisible = true; NSApp.activate(ignoringOtherApps: true); window.deminiaturize(nil); window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) {
        model.dashboardVisible = false; model.actionsPresented = false; model.settingsPresented = false
    }
    func windowDidMiniaturize(_ notification: Notification) { model.dashboardVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.dashboardVisible = true }
    @objc func closeWindow() {
        if model.actionsPresented { model.actionsPresented = false }
        else if model.settingsPresented { model.settingsPresented = false }
        else { window.close() }
    }
    @objc func chat() { model.openChat() }
    @objc func togglePet() { model.togglePet() }
    @objc func hello() { model.showHello() }
    @objc func settings() { showWindow(); model.settingsPresented = true }
    @objc func actions() { showWindow(); model.actionsPresented = true }
    @objc func preview() { model.preview() }
    @objc func rest() { model.rest() }
    @objc func pause() { model.togglePause() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "DeepSeek-chan", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development", .credits: NSAttributedString(string: "Your DeepSeek-chan desktop companion.\n\(ActionLibrary.all.count) illustrated actions, little bubbles and gentle eye breaks.\nFan-made; not affiliated with DeepSeek.")])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
