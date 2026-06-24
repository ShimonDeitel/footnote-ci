import SwiftUI

// MARK: - Section header

/// A small uppercase section label used inside note detail and other forms.
struct FootnoteSectionHeader: View {
    let title: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.footnoteAccent)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Live waveform

/// A flat Apple-blue bar waveform driven by the recorder's rolling levels.
struct WaveformView: View {
    let levels: [CGFloat]
    var active: Bool = true

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(active ? Color.footnoteAccent : Color.secondary)
                        .frame(width: barWidth,
                               height: max(3, levels[i] * geo.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Context chip / picker

struct ContextChip: View {
    let context: RecordingContext
    let selected: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.symbol).font(.footnote.weight(.semibold))
            Text(context.label).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .foregroundStyle(selected ? Color.white : .primary)
        .background(selected ? Color.footnoteAccent : Color.footnoteCard, in: Capsule())
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Due-date / owner chips

struct MetaChip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2.weight(.semibold))
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.footnoteField, in: Capsule())
    }
}

// MARK: - Buried promise banner

struct BuriedPromiseBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.headline)
                .foregroundStyle(Color.footnoteAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Buried Promise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.footnoteAccent)
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.footnoteAccent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Pro lock row

struct ProLockRow: View {
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.headline)
                .foregroundStyle(Color.footnoteAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.footnoteCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
