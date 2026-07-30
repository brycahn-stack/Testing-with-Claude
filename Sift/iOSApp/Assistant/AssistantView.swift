import SwiftUI
import SiftCore

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    var citedEntryIDs: [UUID] = []
}

/// The Assistant tab: ask questions about everything you've journaled.
///
/// It reads the whole journal (via `JournalContext`) but can't act on its own —
/// anything it wants to do becomes a card in the Review queue, same as every
/// other proposal.
struct AssistantView: View {
    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var proposals: ProposalStore

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    private let responder: AssistantResponder = LocalQueryResponder()

    private let starters = [
        "What business ideas have I had?",
        "Summarize my week",
        "What workouts did I log?",
        "What's waiting on me?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { message in
                                MessageBubble(message: message, store: store)
                                    .id(message.id)
                            }
                            if isThinking {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Reading your journal…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages) { _, _ in
                        if let last = messages.last {
                            withAnimation { scroll.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                composer
            }
            .navigationTitle("Assistant")
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { messages.removeAll() }
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Ask about your journal")
                .font(.title3.weight(.semibold))
            Text("I can read every entry you've recorded — \(store.entries.count) so far — and answer questions about them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        send(starter)
                    } label: {
                        Text(starter)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask about your journal…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .focused($inputFocused)
                .onSubmit { send(input) }

            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, text: question))
        input = ""
        inputFocused = false
        isThinking = true

        Task {
            let context = JournalContext(
                entries: store.entries,
                pendingProposals: proposals.pending
            )
            let reply = await responder.respond(to: question, context: context)
            messages.append(ChatMessage(role: .assistant, text: reply.text,
                                        citedEntryIDs: reply.citedEntryIDs))
            // Anything the assistant wants to do goes to the Review queue.
            proposals.add(contentsOf: reply.proposedActions)
            isThinking = false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let store: JournalStore

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        message.role == .user ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .textSelection(.enabled)

                if !message.citedEntryIDs.isEmpty {
                    Text("Based on \(message.citedEntryIDs.count) journal entr\(message.citedEntryIDs.count == 1 ? "y" : "ies")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
