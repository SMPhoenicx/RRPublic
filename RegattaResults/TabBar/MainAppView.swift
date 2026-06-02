//
//  MainAppView.swift
//  RegattaResults
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var repository: RegattaRepository

    var body: some View {
        WithTabBar { selection, _ in
            switch selection {
            case .home:     HomePageView()
            case .events:   EventsView()
            case .tracked:  TrackedView()
            case .sailors: SailorsTabView()
            }
        }
    }
}



// MARK: - Settings Tab View
struct SettingsTabView: View {
    @AppStorage("userName") private var userName: String = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                HStack{
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.tellText)
                            .frame(width: 36, height: 36)
                            .glassCard(radius: 10)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                TellTopBar(subtitle: "Preferences", title: "Settings")

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        personalInfoCard
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
        }
    }

    private var personalInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR NAME")
                .font(.system(size: 10, weight: .black))
                .tracking(1.2)
                .foregroundColor(.tellTextMute)

            TextField("Enter your name", text: $userName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tellText)
                .tint(.tellAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassCard(radius: 10)
        }
        .padding(16)
        .glassCard(radius: 16)
        .padding(.horizontal, 16)
    }
}

