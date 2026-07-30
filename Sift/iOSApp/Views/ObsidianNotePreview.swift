import SwiftUI
import SiftCore

/// The Obsidian confirmation sheet.
///
/// Two very different jobs, matching the two modes:
/// - **Creating** a note: edit the name and body, then see the literal file that
///   will be written, frontmatter and all.
/// - **Appending** to a note you already keep: see the *real tail of the real
///   file* with the new line highlighted in place. That's the whole point — the
///   riskiest thing Sift does should also be the easiest to eyeball.
///
/// The rendered text comes from `MarkdownNoteDraft` itself, so this preview
/// can't drift from what the vault actually writes.
struct ObsidianNotePreview: View {
    @Binding var draft: MarkdownNoteDraft

    /// The last few lines of the target note, loaded from the vault.
    @State private var tail: String?
    @State private var loadingTail = true

    var body: some View {
        Form {
            header

            switch draft.mode {
            case .createNote:  createFields
            case .appendToNote(let heading): appendFields(heading: heading)
            }
        }
        .task {
            guard draft.mode.isAppend else {
                loadingTail = false
                return
            }
            tail = await ObsidianVault.shared.tail(ofNote: draft.noteName)
            loadingTail = false
        }
    }

    // MARK: Header

    private var header: some View {
        Section {
            HStack(spacing: 10) {
                ObsidianMark().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.mode.isAppend ? draft.fileName : draft.vaultPath)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(draft.mode.isAppend ? "Adding to an existing note" : "New note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Create

    @ViewBuilder
    private var createFields: some View {
        Section("Note name") {
            TextField("Note name", text: Binding(
                get: { draft.noteName },
                // Sanitize as they type: a "/" in a name silently becomes a
                // folder, which is a confusing way to lose a note.
                set: { draft.noteName = MarkdownNoteDraft.sanitizedNoteName($0) }
            ))
            .font(.body.weight(.medium))
        }

        Section("Body") {
            TextEditor(text: $draft.body)
                .frame(minHeight: 140)
                .font(.body)
        }

        if !draft.tags.isEmpty || !draft.links.isEmpty {
            Section {
                if !draft.tags.isEmpty {
                    ChipRow(label: "Tags", items: draft.tags.map { "#\($0)" },
                            tint: ObsidianMark.purple)
                }
                if !draft.links.isEmpty {
                    ChipRow(label: "Links", items: draft.links.map { "[[\($0)]]" },
                            tint: .accentColor)
                }
            } footer: {
                if !draft.links.isEmpty {
                    Text("Links point at notes that already exist in your vault — Sift won't invent a page you don't have.")
                }
            }
        }

        Section("File preview") {
            MarkdownBlock(text: draft.renderedNote)
        }
    }

    // MARK: Append

    @ViewBuilder
    private func appendFields(heading: String) -> some View {
        Section {
            TextField("What to remember", text: $draft.body, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("The fact")
        } footer: {
            Text("Goes under “## \(heading)” in \(draft.fileName).")
        }

        Section("Where it lands") {
            if loadingTail {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading \(draft.fileName)…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let tail {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(draft.renderedAppendix)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ObsidianMark.purple)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(ObsidianMark.purple.opacity(0.12))
                        )
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Couldn't read that note — it may have been renamed or moved.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Label("Sift is editing a file you wrote. Nothing else in the note changes.",
                  systemImage: "hand.raised")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pieces

/// A block of Markdown shown as-is, monospaced, scrollable when it's long —
/// the literal bytes headed for disk.
private struct MarkdownBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 260)
    }
}

private struct ChipRow: View {
    let label: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            // Wraps rather than scrolls, so nothing is hidden off-screen.
            FlowRow(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Minimal wrapping row. `Layout` rather than a stack of `HStack`s so chips of
/// any width flow onto the next line instead of being clipped.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, totalHeight: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth,
                      height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
