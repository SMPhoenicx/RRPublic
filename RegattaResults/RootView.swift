//
//  RootView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/21/26.
//
import SwiftUI

struct RootView: View {
    @State private var didFinishLaunch = false
    @StateObject private var repository = RegattaRepository()
    @StateObject private var store = TrackedEventStore()
    @StateObject private var sailorStore = FavoriteSailorStore()
    @StateObject private var notif       = NotificationManager()
    
    var body: some View {
        ZStack {
            if didFinishLaunch {
                MainAppView()
                    .transition(.opacity)
            } else {
                LaunchView {
                    withAnimation(.easeOut(duration: 0.25)) {
                        didFinishLaunch = true
                    }
                }
                .transition(.opacity)
            }
        }
        .environmentObject(repository)
        .environmentObject(store)
        .environmentObject(sailorStore)
        .environmentObject(notif)
        .task {
            //sets the repository for notifmanager and gets auth
            notif.attachRepository(repository)
            NotificationBridge.shared.manager = notif
            await notif.refreshAuthStatus()
        }
    }
}
