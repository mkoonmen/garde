import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// Full-screen, big-text, hands-free cooking. Screen stays on, steps can be read aloud,
/// voice commands move through steps, and any step with a time gets a one-tap timer.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let title: String
    let steps: [String]
    let ingredients: [String]
    let servings: Int
    let usedItems: [PantryItem]
    let estimatedCost: Double?
    var onFinished: () -> Void

    @State private var index = 0
    @State private var voice = CookVoice()
    @AppStorage("cookTips") private var showTips = true
    @State private var readAloud = true
    @State private var showIngredients = false
    @State private var timers: [StepTimer] = []
    @State private var finishing = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct StepTimer: Identifiable { let id = UUID(); let step: Int; let label: String; let ends: Date }

    private var step: String { steps.indices.contains(index) ? steps[index] : "" }
    private var stepSeconds: Int? { CookVoice.duration(in: step) }

    @State private var mise = true
    @State private var gathered: Set<Int> = []

    var body: some View {
        if mise && !ingredients.isEmpty { miseView } else { cookBody }
    }

    /// Mise en place: get everything out before the first step.
    private var miseView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).font(.title2)
                Spacer()
                Text("Mise en place").font(.headline).fontDesign(.serif)
                Spacer()
                Button("Skip") { withAnimation { mise = false } }
            }.padding()
            List(Array(ingredients.enumerated()), id: \.offset) { i, line in
                Button {
                    if gathered.contains(i) { gathered.remove(i) } else { gathered.insert(i) }
                } label: {
                    HStack {
                        Image(systemName: gathered.contains(i) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(gathered.contains(i) ? .green : Theme.accent).font(.title2)
                        Text(line).font(.title3).strikethrough(gathered.contains(i))
                    }.contentShape(.rect)
                }.buttonStyle(.plain).listRowBackground(RowGlass())
            }
            .scrollContentBackground(.hidden)
            .sensoryFeedback(.selection, trigger: gathered.count)
            Button { withAnimation { mise = false } } label: {
                Text(gathered.count == ingredients.count ? "Everything's out. Start cooking" : "Start cooking (\(gathered.count)/\(ingredients.count) out)")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(GardeProminent()).controlSize(.large).padding()
        }
        .background { GardeBackground() }
    }

    private var cookBody: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).font(.title2)
                Spacer()
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                Button("Ingredients", systemImage: "list.bullet") { showIngredients = true }.labelStyle(.iconOnly).font(.title2)
            }.padding()

            ProgressView(value: Double(index + 1), total: Double(max(steps.count, 1))).tint(Theme.accent).padding(.horizontal)

            if !timers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(timers) { t in
                            TimerChip(step: t.step, ends: t.ends, now: now) {
                                timers.removeAll { $0.id == t.id }
                                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-\(t.id)"])
                            }
                        }
                    }.padding(.horizontal)
                }.padding(.top, 10)
            }

            Spacer()
            VStack(spacing: 18) {
                Text("STEP \(index + 1) OF \(steps.count)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(step).font(.system(size: 30, weight: .medium, design: .serif)).multilineTextAlignment(.center).minimumScaleFactor(0.5)
                    .id(index).transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                if showTips, let tip = ChefTips.tip(for: step) {
                    Label(tip, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).padding(10).background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
                if let secs = stepSeconds {
                    Button { startTimer(secs) } label: {
                        Label("Start \(secs >= 3600 ? "\(secs / 3600)h \(secs % 3600 / 60)m" : "\(secs / 60) min") timer", systemImage: "timer")
                    }.buttonStyle(.bordered).controlSize(.large)
                }
            }.padding(.horizontal, 24)
            Spacer()

            HStack(spacing: 16) {
                Button { go(-1) } label: { Image(systemName: "chevron.left").frame(maxWidth: .infinity, minHeight: 64) }
                    .buttonStyle(.bordered).disabled(index == 0).accessibilityLabel("Previous step")
                if index == steps.count - 1 {
                    Button { finishing = true } label: { Text("Done").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 64) }
                        .buttonStyle(GardeProminent())
                } else {
                    Button { go(1) } label: { Image(systemName: "chevron.right").frame(maxWidth: .infinity, minHeight: 64) }
                        .buttonStyle(GardeProminent()).accessibilityLabel("Next step")
                }
            }.font(.title2).padding(.horizontal)

            HStack {
                Toggle(isOn: $readAloud) { Label("Read aloud", systemImage: "speaker.wave.2") }.toggleStyle(.button)
                Spacer()
                Button {
                    if voice.isListening { voice.stop() } else { Task { await voice.start() } }
                } label: {
                    Label(voice.isListening ? "Listening" : "Voice", systemImage: voice.isListening ? "mic.fill" : "mic")
                }.buttonStyle(.bordered).tint(voice.isListening ? .red : .secondary)
            }.padding()
            if let p = voice.problem, !voice.isListening {
                HStack {
                    Text(p).font(.caption).foregroundStyle(.orange)
                    Button("Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }.font(.caption)
                }.padding(.horizontal)
            }
            if voice.isListening {
                Text("Say \"next\", \"back\", \"repeat\", \"start timer\" or \"how long\"").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        }
        .background { GardeBackground() }
        .gesture(DragGesture(minimumDistance: 40).onEnded { g in go(g.translation.width < 0 ? 1 : -1) })
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            voice.onCommand = handle
            if readAloud { voice.speak(step) }
            shareToTV()
        }
        .onChange(of: index) { _, _ in shareToTV() }
        .onChange(of: timers.count) { _, _ in shareToTV() }
        .onDisappear {
            KitchenFeed.setCooking(title: nil, context: context)
            CookActivity.end()
            UIApplication.shared.isIdleTimerDisabled = false
            voice.stop()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: timers.map { "timer-\($0.id)" })
        }
        .onReceive(tick) { t in
            let before = timers.filter { $0.ends > now }.count
            now = t
            if timers.filter({ $0.ends > now }).count < before {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                voice.speak("Timer done.")
            }
        }
        .sheet(isPresented: $showIngredients) {
            NavigationStack {
                List(ingredients, id: \.self) { line in Text(line).listRowBackground(RowGlass()) }
                    .gardePage()
                    .navigationTitle("Ingredients · serves \(servings)").navigationBarTitleDisplayMode(.inline)
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $finishing) {
            FinishCookingView(title: title, ingredients: ingredients, usedItems: usedItems, estimatedCost: estimatedCost) {
                onFinished(); finishing = false; dismiss()
            }
        }
    }

    /// Lets Koonmen OS show the current step on the kitchen TV.
    private func shareToTV() {
        let nextTimer = timers.filter { $0.ends > .now }.map(\.ends).min()
        KitchenFeed.setCooking(title: title, step: index, total: steps.count, text: step, timerEndsAt: nextTimer, context: context)
        CookActivity.update(title: title, step: index, total: steps.count, text: step, timerEnds: nextTimer)
    }

    private func go(_ delta: Int) {
        let n = index + delta
        guard steps.indices.contains(n) else { if delta > 0 && index == steps.count - 1 { finishing = true }; return }
        withAnimation(.snappy) { index = n }
        UISelectionFeedbackGenerator().selectionChanged()
        if readAloud { voice.speak(step) }
    }

    private func startTimer(_ secs: Int) {
        let timer = StepTimer(step: index, label: step, ends: .now.addingTimeInterval(TimeInterval(secs)))
        timers.append(timer)
        // Backup alert in case the phone gets locked.
        let content = UNMutableNotificationContent()
        content.title = "Timer done"; content.body = "Step \(index + 1): \(title)"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "timer-\(timer.id)", content: content,
                                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secs), repeats: false)))
    }

    private func handle(_ cmd: CookVoice.Command) {
        switch cmd {
        case .next: go(1)
        case .back: go(-1)
        case .repeatStep: voice.speak(step)
        case .startTimer:
            if let s = stepSeconds { startTimer(s); voice.speak("Timer started.") } else { voice.speak("This step doesn't have a time.") }
        case .timeLeft:
            if let t = timers.filter({ $0.ends > .now }).min(by: { $0.ends < $1.ends }) {
                let left = Int(t.ends.timeIntervalSinceNow)
                voice.speak(left >= 60 ? "\(left / 60) minutes \(left % 60) seconds left." : "\(left) seconds left.")
            } else { voice.speak("No timers running.") }
        case .stop: voice.stop()
        }
    }
}

/// Rate it (teaches Garde your taste), mark ingredients used, save leftovers.
struct FinishCookingView: View {
    @Environment(\.modelContext) private var context
    let title: String
    let ingredients: [String]
    let usedItems: [PantryItem]
    let estimatedCost: Double?
    var onDone: () -> Void
    @State private var rating = 0
    @State private var change = ""
    @State private var neverAgain = false
    @State private var selected: Set<Int> = []
    @State private var finished: Set<UUID> = []
    @State private var requirements: [IngredientRequirement] = []
    @State private var saveLeftovers = false
    @State private var leftoverServings = 1
    @State private var operationID = UUID()
    @State private var saved = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("How was it?") {
                    Picker("Rating", selection: $rating) {
                        Text("Unrated").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) }
                    }
                    TextField("What would you change next time?", text: $change, axis: .vertical)
                    Toggle("Never suggest this again", isOn: $neverAgain)
                }
                Section {
                    ForEach(requirements.filter { !$0.allocations.isEmpty }) { need in
                        Toggle(isOn: Binding(get: { selected.contains(need.id) }, set: { if $0 { selected.insert(need.id) } else { selected.remove(need.id) } })) {
                            VStack(alignment: .leading) {
                                Text(need.line)
                                Text(need.allocations.map { $0.amount.label + " from " + $0.item.name }.joined(separator: "; "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(requirements.filter { $0.needsCheck && !$0.isBasic }) { need in
                        Text("Check manually: " + need.line).font(.caption).foregroundStyle(.orange)
                    }
                } header: { Text("Amounts used") } footer: {
                    Text("Selected amounts are deducted from the recorded packages. Unknown amounts need a quick check in the Kitchen.")
                }
                Section("Packages completely finished") {
                    ForEach(usedItems) { item in
                        Toggle(item.name, isOn: Binding(get: { finished.contains(item.id) }, set: { if $0 { finished.insert(item.id) } else { finished.remove(item.id) } }))
                    }
                }
                Section {
                    Toggle("Save leftovers", isOn: $saveLeftovers)
                    if saveLeftovers { Stepper("\(leftoverServings) servings", value: $leftoverServings, in: 1...12) }
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .gardePage().navigationTitle("Nice work")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saved) } }
            .onAppear {
                requirements = KitchenStock.plan(ingredients, items: usedItems)
                selected = Set(requirements.filter { !$0.allocations.isEmpty }.map(\.id))
            }
        }
    }

    private func save() {
        guard !saved else { return }
        do {
            if try context.fetch(FetchDescriptor<CookLog>()).contains(where: { $0.id == operationID }) {
                saved = true; onDone(); return
            }
            try KitchenStock.consume(requirements, selected: selected, operationID: operationID, context: context)
            for item in usedItems where finished.contains(item.id) { item.markUsed() }
            let log = CookLog(title: title, rating: rating, wouldChange: change, neverAgain: neverAgain, cost: estimatedCost)
            log.id = operationID
            context.insert(log)
            var leftover: PantryItem?
            if saveLeftovers {
                let item = PantryItem(name: "\(title) (leftovers)", category: .other, location: .fridge,
                                      quantity: Double(leftoverServings), unit: "serving",
                                      expirationDate: Calendar.current.date(byAdding: .day, value: 4, to: .now))
                item.isLeftover = true
                KitchenStock.register(item, context: context)
                leftover = item
            }
            try context.save()
            if let leftover { Notifier.leftoverLunch(title: title, itemID: leftover.id) }
            saved = true
            onDone()
        } catch {
            context.rollback()
            problem = error.localizedDescription
            requirements = KitchenStock.plan(ingredients, items: usedItems)
        }
    }
}


/// One running cook-mode timer.
struct TimerChip: View {
    let step: Int
    let ends: Date
    let now: Date
    var onDismiss: () -> Void

    private var left: Int { max(0, Int(ends.timeIntervalSince(now))) }
    private var clock: String { String(format: "%d:%02d", left / 60, left % 60) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: left == 0 ? "bell.fill" : "timer")
            Text("Step \(step + 1)  \(clock)").monospacedDigit()
            Button("Dismiss", systemImage: "xmark.circle.fill", action: onDismiss).labelStyle(.iconOnly)
        }
        .font(.headline)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(left == 0 ? Color.red : Theme.copper, lineWidth: 1))
    }
}
