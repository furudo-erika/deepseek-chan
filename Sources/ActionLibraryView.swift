import SwiftUI

struct ActionLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var category = "All"
    @State private var showFavorites = false
    private var visible: [Int] {
        ActionLibrary.all.indices.filter { i in
            let a = ActionLibrary.all[i]
            return (category == "All" || a.category == category)
                && (!showFavorites || model.favoriteActions.contains(a.id))
                && a.matches(search)
        }
    }
    private var current: PetAction { ActionLibrary.action(model.petAction) }
    private var unavailable: Bool { model.isResting || model.engine.phase == .reminding }
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Her little world").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("\(ActionLibrary.all.count) little things she can do.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { model.actionsPresented = false }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.ocean)
                TextField("Find an action…", text: $search).textFieldStyle(.plain).accessibilityLabel("Find an action")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                Toggle("Favorites", isOn: $showFavorites).toggleStyle(.button).controlSize(.small)
            }.padding(11).background(.white, in: RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    Picker("Collection", selection: $category) {
                        Text("All collections").tag("All")
                        ForEach(ActionLibrary.categories, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().accessibilityLabel("Collection")
                    ScrollView {
                        if visible.isEmpty {
                            ContentUnavailableView(showFavorites ? "No favorites here yet" : "No matching actions", systemImage: "heart", description: Text("Try another collection or a shorter search."))
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(visible, id: \.self) { index in
                                    actionCard(index)
                                }
                            }.padding(3)
                        }
                    }.id(category + String(showFavorites) + search)
                    Text("\(visible.count) \(visible.count == 1 ? "action" : "actions")").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(width: 410)
                VStack(spacing: 13) {
                    CompanionView(still: model.systemSuspended || !model.dashboardVisible, action: model.petAction, replay: model.replay, calm: model.calmMode, halloween: model.halloweenMode).frame(width: 230, height: 230)
                    Text(current.name).font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(current.line).font(.system(size: 15, weight: .medium, design: .rounded)).multilineTextAlignment(.center).frame(height: 42)
                    HStack {
                        Button { model.toggleFavorite(current.id) } label: {
                            Label(model.favoriteActions.contains(current.id) ? "Loved" : "Love this", systemImage: model.favoriteActions.contains(current.id) ? "heart.fill" : "heart")
                        }
                        Button("Play again") { model.playAction(model.petAction) }.disabled(unavailable)
                    }.controlSize(.small)
                    Button { model.surpriseAction() } label: { Label("Surprise me", systemImage: "shuffle") }.disabled(unavailable)
                    Divider().padding(.vertical, 3)
                    Toggle("Only favorites when awake", isOn: $model.favoritesOnly)
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                        .disabled(model.favoriteActions.isEmpty)
                        .help("Favorites play within her current outfit. If none match, she uses that outfit’s full collection.")
                    Text(unavailable ? "She'll play after your eye break." : "Cards also switch her outfit.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(width: 250)
            }
        }.padding(26).frame(width: 732, height: 650)
            .foregroundStyle(Color.ink).background(Color.mist).preferredColorScheme(.light)
    }
    private func actionCard(_ index: Int) -> some View {
        let action = ActionLibrary.all[index]
        return ZStack(alignment: .topTrailing) {
        Button { model.playAction(index) } label: {
            VStack(spacing: 5) {
                // The grid uses still thumbnails; only the selected preview animates.
                CompanionSprite(frame: action.frame, side: 100, artwork: action.atlas)
                Text(action.name).font(.system(size: 11, weight: .medium)).lineLimit(2).frame(height: 28)
            }.padding(7).frame(maxWidth: .infinity)
                .background(.white.opacity(index == model.petAction ? 1 : 0.65), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(index == model.petAction ? Color.ocean : .clear, lineWidth: 2))
        }.buttonStyle(.plain).disabled(unavailable)
            .accessibilityLabel("Play \(action.name)")
        Button { model.toggleFavorite(action.id) } label: {
            Image(systemName: model.favoriteActions.contains(action.id) ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(model.favoriteActions.contains(action.id) ? .pink : Color.ocean.opacity(0.6))
                .frame(width: 27, height: 27).background(.white.opacity(0.9), in: Circle())
        }.buttonStyle(.plain).padding(4)
            .accessibilityLabel("\(model.favoriteActions.contains(action.id) ? "Unfavorite" : "Favorite") \(action.name)")
        }
    }
}
