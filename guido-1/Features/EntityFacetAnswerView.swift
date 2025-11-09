import SwiftUI

struct EntityFacetAnswerView: View {
    struct Citation: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let source: String
        let url: URL?
        let timestamp: Date?
        
        init(title: String, source: String, url: URL?, timestamp: Date?) {
            self.title = title
            self.source = source
            self.url = url
            self.timestamp = timestamp
        }
        
        init(title: String, source: String, urlString: String?, timestampISO: String?) {
            self.title = title
            self.source = source
            if let urlString,
               let value = URL(string: urlString) {
                self.url = value
            } else {
                self.url = nil
            }
            if let timestampISO,
               let value = ISO8601DateFormatter().date(from: timestampISO) {
                self.timestamp = value
            } else {
                self.timestamp = nil
            }
        }
    }
    
    struct Model {
        let facet: String
        let answer: String
        let rationale: String?
        let confidence: Double?
        let citations: [Citation]
        let followUps: [String]
        
        init(
            facet: String,
            answer: String,
            rationale: String? = nil,
            confidence: Double? = nil,
            citations: [Citation] = [],
            followUps: [String] = []
        ) {
            self.facet = facet
            self.answer = answer
            self.rationale = rationale
            self.confidence = confidence
            self.citations = citations
            self.followUps = followUps
        }
    }
    
    let model: Model
    
    private var facetTitle: String {
        model.facet.isEmpty ? "Discovery" : model.facet.capitalized
    }
    
    private var confidenceDisplay: String? {
        guard let value = model.confidence else { return nil }
        let percent = Int(round(value * 100))
        return "\(percent)% confidence"
    }
    
    private var confidenceValue: Double {
        guard let value = model.confidence else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(model.answer)
                .font(.body)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            if let rationale = model.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if model.confidence != nil {
                confidenceRow
            }
            
            if !model.citations.isEmpty {
                Divider().padding(.top, 4)
                citationsSection
            }
            
            if !model.followUps.isEmpty {
                Divider().padding(.top, 4)
                followUpsSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3))
        )
    }
    
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: iconName(for: model.facet))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor(for: model.facet))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(iconColor(for: model.facet).opacity(0.12))
                )
            
            Text(facetTitle)
                .font(.headline)
                .foregroundStyle(Color.primary)
            
            Spacer()
        }
    }
    
    private var confidenceRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let display = confidenceDisplay {
                Text(display)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            ProgressView(value: confidenceValue)
                .progressViewStyle(.linear)
        }
    }
    
    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Citations")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            ForEach(model.citations) { citation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        if let url = citation.url {
                            Link(destination: url) {
                                Text(citation.title.isEmpty ? url.host ?? url.absoluteString : citation.title)
                                    .font(.callout)
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                        } else {
                            Text(citation.title)
                                .font(.callout)
                                .foregroundStyle(Color.secondary)
                        }
                        Text(metadata(for: citation))
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }
    
    private var followUpsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested follow-ups")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(model.followUps, id: \.self) { followUp in
                    Text(followUp)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemFill))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
            }
        }
    }
    
    private func iconName(for facet: String) -> String {
        switch facet.lowercased() {
        case "reviews":
            return "quote.bubble"
        case "vibe":
            return "sparkles"
        case "menu", "offerings":
            return "list.bullet.rectangle"
        case "policy":
            return "doc.text.magnifyingglass"
        case "search":
            return "magnifyingglass"
        default:
            return "info.circle"
        }
    }
    
    private func iconColor(for facet: String) -> Color {
        switch facet.lowercased() {
        case "reviews":
            return Color.orange
        case "vibe":
            return Color.purple
        case "menu", "offerings":
            return Color.green
        case "policy":
            return Color.blue
        case "search":
            return Color.indigo
        default:
            return Color.accentColor
        }
    }
    
    private func metadata(for citation: Citation) -> String {
        var parts: [String] = []
        if !citation.source.isEmpty {
            parts.append(citation.source.capitalized)
        }
        if let timestamp = citation.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            parts.append(formatter.string(from: timestamp))
        }
        return parts.joined(separator: " • ")
    }
}

#Preview("Facet Answer") {
    EntityFacetAnswerView(
        model: .init(
            facet: "reviews",
            answer: "Guests consistently praise the house-made pastries, but mornings can get busy—arrive before 10am if you need a quiet spot.",
            rationale: "Based on three recent Google reviews from the last month, all highlighting pastries and morning crowds.",
            confidence: 0.82,
            citations: [
                .init(
                    title: "Google review by Alex P.",
                    source: "places",
                    urlString: "https://maps.google.com/?cid=123456",
                    timestampISO: "2025-10-29T17:24:00Z"
                ),
                .init(
                    title: "Google review by Priya K.",
                    source: "places",
                    urlString: nil,
                    timestampISO: "2025-10-21T11:05:00Z"
                )
            ],
            followUps: ["Check their menu", "See if it’s laptop friendly"]
        )
    )
    .padding()
    .previewLayout(.sizeThatFits)
    .background(Color(.systemBackground))
}

