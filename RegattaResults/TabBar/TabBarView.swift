//
//  TabBarView.swift
//  RegattaResults
//

import SwiftUI
import Foundation

// MARK: - Tab Selection Manager

class TabManager: ObservableObject {
    @Published var selection: Tabs = .home

    func switchTo(_ tab: Tabs) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            selection = tab
        }
    }
}

struct WithTabBar<Content>: View where Content: View {
    @StateObject private var tabManager = TabManager()
    @ViewBuilder var content: (Tabs, TabManager) -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content(tabManager.selection, tabManager)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .bottom) {
                GlassmorphicTabBar(selection: $tabManager.selection)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .environmentObject(tabManager)
        .ignoresSafeArea(.all)
    }
}

// MARK: - Tab Bar

struct GlassmorphicTabBar: View {
    @Binding var selection: Tabs
    @State private var animationTrigger: Bool = false
    @Namespace private var tabItemNameSpace

    func changeTabTo(_ tab: Tabs) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            selection = tab
        }
        animationTrigger.toggle()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tabs.allCases, id: \.self) { tab in
                Button(action: { changeTabTo(tab) }) {
                    GlassmorphicTabItem(
                        tab: tab,
                        isSelected: tab == selection,
                        animationTrigger: animationTrigger
                    )
                }
                .buttonStyle(GlassmorphicButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(glassmorphicBackground)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var glassmorphicBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.1), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.2), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1.5)
                )
        }
    }
}

// MARK: - Tab Item

struct GlassmorphicTabItem: View {
    let tab: Tabs
    let isSelected: Bool
    let animationTrigger: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Ellipse()
                    .fill(Color.white.opacity(0.15)).blur(radius: 20)
                    .frame(width: 130, height: 100)
                Ellipse()
                    .fill(Color.white.opacity(0.2)).blur(radius: 12)
                    .frame(width: 100, height: 80)
                Ellipse()
                    .fill(Color.white.opacity(0.1)).blur(radius: 6)
                    .frame(width: 70, height: 50)
            }

            VStack(spacing: 6) {
                Image(systemName: tab.item.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                    .animation(.easeInOut(duration: 0.3), value: isSelected)

                Text(tab.item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary.opacity(0.7))
                    .animation(.easeInOut(duration: 0.3), value: isSelected)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }
}

// MARK: - Tabs Enum

enum Tabs: CaseIterable {
    case home, events, tracked, sailors

    var item: TabItem {
        switch self {
        case .home:     .init(title: "Home",    systemImage: "house.fill",       color: .blue)
        case .events:   .init(title: "Events",  systemImage: "calendar",         color: .tellAmber)
        case .tracked:  .init(title: "Tracked", systemImage: "flag.fill",        color: .tellAccent)
        case .sailors: .init(title: "Sailors", systemImage: "person.3.fill",            color: .orange)
        }
    }
}

struct TabItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let systemImage: String
    let color: Color
}

// MARK: - Button Style

struct GlassmorphicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension Material {
    static let glassmorphic = Material.ultraThinMaterial
}
