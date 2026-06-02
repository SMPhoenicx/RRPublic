//
//  RegattaResultsApp.swift
//  RegattaResults
//
//  Entry point. Injects the new RegattaRepository for Supabase-backed
//  views (Home, Events) alongside the legacy environment objects that
//  the existing Scanner flow (ScannerTabView, QRScanView,
//  RegattaResultsView, SailorsView) still depends on. We will retire
//  RegattaSocketManager / APIRetrievalService when the scanner is
//  migrated to the repository.
//

import SwiftUI
import UIKit

@main
struct RegattaResultsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    
//    // legacy
//    @StateObject private var socketManager = RegattaSocketManager()
//    @StateObject private var retriever     = APIRetrievalService()
 
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return true
    }

    /// Apple delivered an APNs device token. Hand it to the manager.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationBridge.shared.manager?.didReceiveDeviceToken(deviceToken)
        }
    }

    /// Apple couldn't issue a token (or we hit a transient failure).
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationBridge.shared.manager?
                .didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}

@MainActor
final class NotificationBridge {
    static let shared = NotificationBridge()
    var manager: NotificationManager?
    private init() {}
}
