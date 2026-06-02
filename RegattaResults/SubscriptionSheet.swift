//
//  SubscriptionSheet.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/29/26.
//

import SwiftUI

// MARK: - Hours options

/// Allowed subscription durations. Must match the whitelist on the
/// subscribe_to_event RPC; sending anything else throws.
enum SubscriptionHours: Int, CaseIterable, Identifiable {
    case h2  = 2
    case h4  = 4
    case h8  = 8
    case h12 = 12
    case h24 = 24

    var id: Int { rawValue }
    var label: String { "\(rawValue)h" }
}

// MARK: - Sheet

struct SubscribeSheet: View {
    let event: DBEvent
    /// Called after a successful subscribe with the new hot_until from
    /// the server. The parent updates its own state and closes the sheet.
    let onSubscribed: (Date) -> Void

    @EnvironmentObject var repository: RegattaRepository
    @EnvironmentObject var notif: NotificationManager
    @Environment(\.dismiss) private var dismiss

    /// Persisted choice — next time the user opens the sheet, the same
    /// duration is preselected.
    @AppStorage("subscribeSheet.selectedHours") private var storedHours: Int = 4
    @AppStorage("subscribeSheet.notificationsOn") private var notificationsOn: Bool = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var permissionDenied = false

    private var selected: SubscriptionHours {
        SubscriptionHours(rawValue: storedHours) ?? .h4
    }

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(alignment: .leading, spacing: 0) {
                header

                durationSection
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                notificationsSection
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Spacer(minLength: 24)

                subscribeButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subscribe")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.tellText)
                .tracking(-0.4)
            Text("Subscribe to get notifications of results for the regatta. Expect up to a 1 minute delay as we check for updates every minute.")
                .font(.system(size: 13))
                .foregroundColor(.tellTextDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: - Duration row

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Duration")
            HStack(spacing: 8) {
                ForEach(SubscriptionHours.allCases) { opt in
                    Button {
                        storedHours = opt.rawValue
                    } label: {
                        Text(opt.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(opt == selected ? .tellText : .tellTextMute)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(opt == selected
                                          ? Color.tellAccent.opacity(0.20)
                                          : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(opt == selected
                                                    ? Color.tellAccent.opacity(0.55)
                                                    : Color.glassBorder,
                                                    lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Notifications toggle

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Notifications")
            HStack(spacing: 12) {
                Image(systemName: notificationsOn ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(notificationsOn ? .tellAmber : .tellTextMute)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify on new results")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.tellText)
                    Text(notificationStatusLine)
                        .font(.system(size: 11.5))
                        .foregroundColor(permissionDenied ? .tellAccent : .tellTextMute)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { notificationsOn && !permissionDenied },
                    set: { newValue in
                        if newValue {
                            Task { await enableNotifications() }
                        } else {
                            notificationsOn = false
                        }
                    }
                ))
                .labelsHidden()
                .tint(.tellAccent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(radius: 12)
        }
    }
    
    private var notificationStatusLine: String {
        if permissionDenied {
            return "Permission denied — enable in Settings to receive alerts."
        }
        if notificationsOn {
            return "We'll alert you when scores post."
        }
        return "Off — no alerts will be sent."
    }

    // MARK: - Submit

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tellAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(isSubmitting
                         ? "Subscribing…"
                         : "Subscribe for \(selected.label)")
                        .font(.system(size: 15, weight: .black))
                        .tracking(-0.2)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tellAccent)
                        .shadow(color: .tellAccent.opacity(0.35), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.7 : 1.0)
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let token = notificationsOn ? notif.apnsToken : nil
            let hotUntil = try await repository.subscribe(
                eventId: event.id,
                hours: selected.rawValue,
                deviceToken: token,
                notifyOnResults: notificationsOn
            )
            onSubscribed(hotUntil)
            dismiss()
        } catch {
            errorMessage = "Couldn't subscribe. \(error.localizedDescription)"
        }
        isSubmitting = false
    }

    // MARK: - Helpers
    private func enableNotifications() async {
        let granted = await notif.requestPermissionAndRegister()
        if granted {
            notificationsOn = true
            permissionDenied = false
        } else {
            notificationsOn = false
            permissionDenied = true
        }
    }
    
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(1.1)
            .foregroundColor(.tellTextMute)
    }
}
