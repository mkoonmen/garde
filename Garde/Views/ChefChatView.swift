import SwiftUI
import SwiftData
import FoundationModels
import Speech
import AVFoundation

/// Talk to the chef. Fully offline: Apple's on-device model, on-device speech recognition.
/// "I've got chicken thighs and want something spicy" → it answers, you push back, it adjusts.
/// Any recipe it writes can be saved or cooked. Every recipe passes the allergen check before you see it.
@MainActor
@Observable
final class ChefConversation {
    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        var text: String
        var recipe: RecipeIdea?
        var blockedForAllergen: [String] = []
    }

    var messages: [Message] = []
    var thinking = false
    private var session: ChefSession?
    private var instructions: String?
    private var allergies: [String] = []

    func start(items: [PantryItem], spices: [Spice], profile: KitchenProfile, logs: [CookLog]) {
        guard session == nil else { return }   // coming back from a recipe keeps the conversation
        allergies = profile.allergies
        let chef = ChefAI()
        let active = items.filter { !$0.isUsedUp }.sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
        let instructions = chef.baseInstructions(profile: profile, logs: logs) + """

        You are chatting with the cook. Be warm, brief and practical, like a chef friend texting back.
        When they want a dish, write one complete recipe. When they're just asking a question (substitutions, technique,
        timing, what goes with what), answer in a few sentences and set the recipe to have an empty title.
        They may ask for anything; ingredients don't have to come from the kitchen, but prefer what's there and what expires soon.

        Their kitchen right now (soonest-expiring first):
        \(chef.inventoryText(active, limit: 30).ifEmpty("(empty)"))
        Spices: \(spices.filter { $0.level != .empty }.map(\.name).joined(separator: ", ").ifEmpty("basic only"))
        """
        self.instructions = instructions
        createSession(instructions: instructions)
        if messages.isEmpty {
            messages.append(Message(fromUser: false, text: "What are we making? Tell me what you're craving, what you've got, or how much time you have."))
        }
    }

    private func createSession(instructions: String) {
        session = ChefEngine.shared.session(instructions: instructions)
    }

    func reset() { session = nil; instructions = nil; messages = [] }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let instructions, session == nil || session?.brain != (ChefEngine.shared.usingLocal ? .local8B : .apple) {
            createSession(instructions: instructions)
        }
        guard !trimmed.isEmpty, let session else { return }
        messages.append(Message(fromUser: true, text: trimmed))
        thinking = true
        defer { thinking = false }
        do {
            let reply = try await session.reply(to: trimmed, generating: ChefReply.self, limit: 120)
            var msg = Message(fromUser: false, text: reply.message)
            if let r = reply.recipe, !r.title.isEmpty, !r.steps.isEmpty {
                let hits = AllergenGuard.violations(in: [r.title] + r.ingredients + r.steps, allergies: allergies)
                if hits.isEmpty { msg.recipe = r } else {
                    msg.blockedForAllergen = hits
                    msg.text = "I came up with something, but it used \(hits.joined(separator: ", ")), which you're allergic to, so I tossed it. Want me to try again another way?"
                }
            }
            messages.append(msg)
        } catch let error as LocalModelInterrupted {
            self.session = nil
            messages.append(Message(fromUser: false, text: error.localizedDescription))
        } catch let error as AITimeoutError {
            self.session = nil
            messages.append(Message(fromUser: false, text: error.localizedDescription))
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                messages.append(Message(fromUser: false, text: "We've been talking a while, so I'm starting a fresh page. Ask me again?"))
                self.session = nil
            } else {
                messages.append(Message(fromUser: false, text: "I couldn't answer that one. Try rephrasing?"))
            }
        } catch {
            messages.append(Message(fromUser: false, text: "I couldn't answer that one. Try rephrasing?"))
        }
    }
}

@Generable
struct ChefReply {
    @Guide(description: "What you say back, 1–4 sentences")
    var message: String
    @Guide(description: "A full recipe if they asked for a dish; otherwise leave the title empty")
    var recipe: RecipeIdea?
}

struct ChefChatView: View {
    @Query(filter: #Predicate<PantryItem> { !$0.isUsedUp }) private var items: [PantryItem]
    @Query private var spices: [Spice]
    @Query private var profiles: [KitchenProfile]
    @Query private var logs: [CookLog]
    @State private var convo = ChefConversation()
    @State private var draft = ""
    @State private var dictation = Dictation()
    @State private var chef = ChefAI()
    @FocusState private var typing: Bool

    private let starters = ["Something spicy with what I have", "Fancy date-night dinner", "20-minute weeknight meal", "Use up whatever's expiring"]

    var body: some View {
        VStack(spacing: 0) {
            if case .unavailable(let why) = chef.state {
                ContentUnavailableView("Chef is offline", systemImage: "brain", description: Text(why))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(convo.messages) { m in bubble(m).id(m.id) }
                            if convo.thinking {
                                HStack(spacing: 6) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }.padding(.leading, 4).id("thinking")
                            }
                            if convo.messages.count <= 1 {
                                ForEach(starters, id: \.self) { s in
                                    Button(s) { Task { await convo.send(s) } }.buttonStyle(.bordered).tint(Theme.accent)
                                }
                            }
                        }.padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: convo.messages.count) { _, _ in withAnimation { proxy.scrollTo(convo.messages.last?.id, anchor: .bottom) } }
                    .onChange(of: convo.thinking) { _, t in if t { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } } }
                }
                inputBar
            }
        }
        .gardePage()
        .navigationTitle("Ask the chef")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("New chat", systemImage: "square.and.pencil") { convo.reset(); startIfReady() } }
        .onAppear(perform: startIfReady)
        .onDisappear { dictation.stop() }
    }

    private func startIfReady() {
        guard let p = profiles.first, chef.state == .available else { return }
        convo.start(items: items, spices: spices, profile: p, logs: logs)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if dictation.isListening { dictation.stop() } else { Task { await dictation.start { draft = $0 } } }
            } label: {
                Image(systemName: dictation.isListening ? "mic.fill" : "mic").font(.title3)
                    .foregroundStyle(dictation.isListening ? .red : Theme.accent).frame(width: 36, height: 36)
                    .symbolEffect(.pulse, isActive: dictation.isListening)
            }
            TextField("Tell the chef…", text: $draft, axis: .vertical)
                .lineLimit(1...5).focused($typing)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card, in: .rect(cornerRadius: 18))
            Button {
                dictation.stop()
                let t = draft; draft = ""
                Task { await convo.send(t) }
            } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)) }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || convo.thinking)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private func bubble(_ m: ChefConversation.Message) -> some View {
        VStack(alignment: m.fromUser ? .trailing : .leading, spacing: 8) {
            Text(m.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(m.fromUser ? Theme.cream : .primary)
                .background(m.fromUser ? AnyShapeStyle(Theme.navy) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 18))
            if let r = m.recipe {
                NavigationLink {
                    RecipeDetailView(title: r.title, summary: r.summary, minutes: r.minutes, servings: r.servings,
                                     ingredients: r.ingredients, steps: r.steps, idea: r)
                } label: { RecipeRow(title: r.title, summary: r.summary, minutes: r.minutes).gardeCard() }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
        .padding(m.fromUser ? .leading : .trailing, 40)
    }
}

/// Push-to-talk dictation, recognized on the iPhone.
@MainActor
@Observable
final class Dictation {
    var isListening = false
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func start(onText: @escaping (String) -> Void) async {
        let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard ok, await AVAudioApplication.requestRecordPermission(), let recognizer, recognizer.isAvailable else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak req] buf, _ in req?.append(buf) }
            engine.prepare(); try engine.start()
            isListening = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    if let t = result?.bestTranscription.formattedString { onText(t) }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch { stop() }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
