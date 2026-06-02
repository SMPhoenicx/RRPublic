//
//  NotificationManager.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/29/26.
//


import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    //has the user been asked to enable before
    @AppStorage("notif.hasPrompted") private var hasPrompted: Bool = false
    @Published private(set) var apnsToken: String?
    // auth state of whether notif enabled
    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined
    //helps confirm notif enabled
    @Published private(set) var isRegistered: Bool = false
    
    private weak var repository: RegattaRepository?
    //used to set repo at root view
    func attachRepository(_ repo: RegattaRepository) {
        self.repository = repo
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthStatus() }
    }

    // Re-reads auth settings and asks to register if auth
    func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authStatus = settings.authorizationStatus
        
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    @discardableResult //(not used)
    func requestPermissionAndRegister() async -> Bool {
        hasPrompted = true
        let center = UNUserNotificationCenter.current()
        let preStatus = await center.notificationSettings().authorizationStatus

        switch preStatus {
            //alr auth
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            self.authStatus = preStatus
            return true

        case .denied:
            self.authStatus = .denied
            return false

            //first time, prompt them
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                self.authStatus = granted ? .authorized : .denied
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return granted
            } catch {
                print("[NotificationManager] permission request failed: \(error)")
                self.authStatus = .denied
                return false
            }

        @unknown default:
            return false
        }
    }

    // MARK: - Token delivery
    func didReceiveDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.apnsToken = hex
        Task { await registerWithBackend(token: hex) }
    }
    
    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("[NotificationManager] APNs registration failed: \(error)")
        // Surface this in development; in release we just log and move on.
        #if DEBUG
        print("\u{26a0}\u{fe0f}  Push registration failed. If this is a simulator on an")
        print("    older OS, that's expected. On a real device, double-check")
        print("    the Push Notifications capability in Signing & Capabilities.")
        #endif
    }

    // Send the token + detected environment to register_device_token.
    //self detects env and app data
    private func registerWithBackend(token: String) async {
        guard let repository else {
            print("[NotificationManager] no repository attached \u{2014} cannot register token")
            return
        }
        let environment = Self.detectAPNsEnvironment()
        let appVersion  = Self.currentAppVersion()

        do {
            try await repository.registerDeviceToken(
                token: token,
                environment: environment,
                appVersion: appVersion
            )
            self.isRegistered = true
            print("[NotificationManager] registered token (\(environment)) successfully")
        } catch {
            print("[NotificationManager] register_device_token RPC failed: \(error)")
            self.isRegistered = false
        }
    }

    static func detectAPNsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func currentAppVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Called when a notification arrives while the app is in the
    /// foreground. By default iOS suppresses these; we explicitly
    /// allow the banner + sound + badge so the user still sees them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Called when the user taps a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("[NotificationManager] tapped notification with userInfo: \(userInfo)")
        // TODO: when we add deep-linking, read event_id from userInfo
        // and route the app to that event's hub.
        completionHandler()
    }
}
