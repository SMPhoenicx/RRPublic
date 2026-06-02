//
//  EventInfoView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/16/26.
//


//
//  EventInfoView.swift
//  RegattaResults
//
//  Detail page for an event the user hasn't tracked yet (or wants to
//  review before tracking). Opened as a sheet from EventsView and
//  HomePageView. Has a prominent "Track" button that:
//    1. Adds the event to TrackedEventStore
//    2. Sets a pending-hub request on the store so TrackedView opens
//       the hub when it appears
//    3. Switches to the Tracked tab
//

import SwiftUI

struct EventInfoView: View {
    let event: DBEvent

    @EnvironmentObject var store:       TrackedEventStore
    @EnvironmentObject var tabManager:  TabManager
    @EnvironmentObject var repository:  RegattaRepository

    @Environment(\.dismiss) private var dismiss

    @State private var boatClasses: [DBBoatClass] = []
    @State private var loadingClasses = true

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                // ── Handle bar ─────────────────────────────────────────
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                        infoSection
                        classesSection
                        Spacer().frame(height: 140)
                    }
                }
            }

            // ── Sticky Track button ─────────────────────────────────────
            VStack {
                Spacer()
                trackButtonBar
            }
        }
        .task {
            let classes = await repository.fetchBoatClasses(for: event.id)
            boatClasses = classes
            loadingClasses = false
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Photo or gradient
            Group {
                if let urlStr = event.imageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else { heroGradient }
                    }
                } else { heroGradient }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            // Dark tint so text is always readable over light/colourful photos
            .overlay(Color.black.opacity(0.35))

            // Gradient overlay (bottom)
            LinearGradient(
                colors: [.clear, Color.atmDeep.opacity(0.95)],
                startPoint: .center, endPoint: .bottom
            )

            // ── Top-right favorite star ───────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button {
                        store.toggleFavorite(event)
                    } label: {
                        Image(systemName: store.isFavorite(event) ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(store.isFavorite(event) ? .tellAmber : .white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.40))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
                Spacer()
            }

            // Event title block
            VStack(alignment: .leading, spacing: 6) {
                if let club = event.clubName {
                    Text(club.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.4)
                        .foregroundColor(.tellTextMute)
                }
                Text(event.displayName)
                    .font(.system(size: 26, weight: .black))
                    .tracking(-0.5)
                    .foregroundColor(.tellText)
                    .lineLimit(3)

                StatusPill(
                    text: statusLabel,
                    tone: statusTone,
                    showPulse: event.isLive
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Info rows

    private var infoSection: some View {
        VStack(spacing: 10) {
            if let start = event.startDate {
                infoRow(icon: "calendar", label: "Date", value: formattedDate(start, to: event.endDate))
            }
            if let loc = event.location {
                infoRow(icon: "location", label: "Location", value: loc)
            }
            infoRow(icon: "flag", label: "Source", value: event.sourceId.capitalized)

            // Register link — opens Clubspot registration in Safari
            if event.sourceId == "clubspot" {
                Button {
                    let urlStr = "https://theclubspot.com/register/regatta/\(event.sourceEventId)/class"
                    if let url = URL(string: urlStr) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tellGreen)
                            .frame(width: 22)
                        Text("Register")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.tellTextMute)
                            .frame(width: 64, alignment: .leading)
                        Text("Open in Safari")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.tellText)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.tellTextMute)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassCard(radius: 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tellCool)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.tellTextMute)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tellText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(radius: 10)
    }

    // MARK: - Boat classes

    @ViewBuilder
    private var classesSection: some View {
        if loadingClasses {
            ProgressView().tint(.tellCool).padding(.top, 24)
        } else if !boatClasses.isEmpty {
            VStack(spacing: 0) {
                TellSectionHeader(
                    title: "Classes",
                    subtitle: "\(boatClasses.count) division\(boatClasses.count == 1 ? "" : "s")"
                )
                FlowLayout(spacing: 8) {
                    ForEach(boatClasses) { cls in
                        Text(cls.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.tellTextDim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .overlay(Capsule().stroke(Color.glassBorder, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Track button bar

    private var trackButtonBar: some View {
        let alreadyTracked = store.isTracked(event)
        return HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tellTextDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .glassCard(radius: 14)
            }
            .buttonStyle(.plain)

            Button {
                trackAction()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag")
                        .font(.system(size: 14, weight: .bold))
                    Text("Open")
                        .font(.system(size: 15, weight: .black))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.tellAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .tellAccent.opacity(0.4), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .background(
            LinearGradient(
                colors: [Color.atmDeep.opacity(0), Color.atmDeep],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Track action

    /// Saves the event into the store, parks a "open hub" request on the
    /// store (TrackedView reads it on appearance via Combine), dismisses
    /// the sheet, and switches to the Tracked tab. The 0.35s delay lets the
    /// sheet finish dismissing before the tab swap so the transition reads
    /// as one motion rather than two competing animations.
    private func trackAction() {
        store.track(event)
        store.requestOpenHub(event)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            tabManager.switchTo(.tracked)
        }
    }

    // MARK: - Helpers

    private var heroGradient: some View {
        let seed = Double((event.sourceEventId.unicodeScalars.first?.value ?? 200) % 60)
        let hue  = seed / 360.0 + 0.55
        return LinearGradient(
            colors: [
                Color(hue: hue,       saturation: 0.50, brightness: 0.42),
                Color(hue: hue + 0.06, saturation: 0.40, brightness: 0.22),
                Color(hue: hue + 0.10, saturation: 0.30, brightness: 0.14),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var statusLabel: String {
        switch event.status {
        case "live":      return "LIVE NOW"
        case "upcoming":  return dateLabel
        case "completed": return "COMPLETED"
        default:          return "UPCOMING"
        }
    }

    private var statusTone: StatusTone {
        switch event.status {
        case "live":      return .red
        case "completed": return .ghost
        default:          return .amber
        }
    }

    private var dateLabel: String {
        guard let d = event.startDate else { return "TBD" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func formattedDate(_ start: Date, to end: Date?) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        guard let end, !Calendar.current.isDate(start, inSameDayAs: end) else {
            return f.string(from: start)
        }
        let f2 = DateFormatter(); f2.dateFormat = "MMM d"
        let f3 = DateFormatter(); f3.dateFormat = "MMM d"
        return "\(f3.string(from: start))–\(f2.string(from: end)), \(Calendar.current.component(.year, from: start))"
    }
}

// MARK: - Simple FlowLayout for class chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for view in row {
                let s = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += s.width + spacing
            }
            y += rowH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x + w > maxW && !rows.last!.isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows
    }
}
