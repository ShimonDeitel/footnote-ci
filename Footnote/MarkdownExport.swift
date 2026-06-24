import Foundation

/// Renders notes to Markdown for the share sheet (single note free; bulk export is Pro).
enum MarkdownExport {
    static func note(_ rec: Recording) -> String {
        var lines: [String] = []
        lines.append("# \(rec.displayTitle)")
        lines.append("")
        lines.append("*\(rec.context.label) · \(rec.createdAt.formatted(date: .long, time: .shortened)) · \(rec.durationText)*")
        lines.append("")

        if let note = rec.note {
            if !note.oneLineSummary.isEmpty {
                lines.append(note.oneLineSummary)
                lines.append("")
            }
            if let promise = note.buriedPromise, !promise.isEmpty {
                lines.append("> **Buried Promise:** \(promise)")
                lines.append("")
            }
            if !note.decisions.isEmpty {
                lines.append("## Decisions")
                for d in note.decisions { lines.append("- \(d)") }
                lines.append("")
            }
            let items = note.orderedActionItems
            if !items.isEmpty {
                lines.append("## Action Items")
                for a in items {
                    var line = "- [\(a.isDone ? "x" : " ")] \(a.text)"
                    if let owner = a.ownerChip { line += " — _\(owner)_" }
                    if let due = TimeFmt.due(a.dueDate) { line += " (due \(due))" }
                    lines.append(line)
                }
                lines.append("")
            }
            if !note.openQuestions.isEmpty {
                lines.append("## Open Questions")
                for q in note.openQuestions { lines.append("- \(q)") }
                lines.append("")
            }
        } else if let err = rec.processingError {
            lines.append("_\(err)_")
            lines.append("")
        }

        if !rec.transcript.isEmpty {
            lines.append("## Transcript")
            lines.append(rec.transcript)
        }
        return lines.joined(separator: "\n")
    }

    /// Bulk export of the whole archive (Pro).
    static func archive(_ recordings: [Recording]) -> String {
        recordings.map { note($0) }.joined(separator: "\n\n---\n\n")
    }
}
