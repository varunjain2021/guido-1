//
//  OnboardingView.swift
//  guido-1
//

import CoreLocation
import SwiftUI
import UIKit

struct OnboardingCardsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var onboarding: OnboardingController
    @ObservedObject private var locationManager: LocationManager
    @ObservedObject private var notificationService: NotificationService
    
    @State private var selection: Int = 0
    @State private var selectedCapability: Capability?
    @State private var locationStatus: CLAuthorizationStatus
    @State private var notificationStatus: UNAuthorizationStatus
    @State private var toastMessage: String?
    
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init(
        onboarding: OnboardingController,
        locationManager: LocationManager,
        notificationService: NotificationService = .shared
    ) {
        self._onboarding = ObservedObject(initialValue: onboarding)
        self._locationManager = ObservedObject(initialValue: locationManager)
        self._notificationService = ObservedObject(initialValue: notificationService)
        _locationStatus = State(initialValue: locationManager.authorizationStatus)
        _notificationStatus = State(initialValue: notificationService.authorizationStatus)
    }
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                cards
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .overlay(toastView, alignment: .bottom)
        .onAppear {
            impactGenerator.prepare()
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = 0
            }
            if selectedCapability == nil {
                selectedCapability = capabilities.first
            }
        }
        .task {
            await updatePermissionStates()
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            locationStatus = status
        }
        .onReceive(notificationService.$authorizationStatus) { status in
            notificationStatus = status
        }
    }
    
    private var header: some View {
        LiquidGlassCard(intensity: 0.85, cornerRadius: 24, shadowIntensity: 0.3, enableFloating: true) {
            VStack(spacing: 6) {
                Text("Guido")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.top, 28)
        .frame(maxWidth: 520)
    }
    
    private var cards: some View {
        TabView(selection: $selection) {
            card1.tag(0)
            card2.tag(1)
            card3.tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .padding(.horizontal, 18)
        .animation(.easeInOut(duration: 0.25), value: selection)
    }
    
    private var controls: some View {
        HStack(spacing: 12) {
            LiquidGlassCard(intensity: 0.6, cornerRadius: 14, shadowIntensity: 0.14) {
                Button(action: nextOrComplete) {
                    HStack(spacing: 8) {
                        Text(selection == totalPages - 1 ? "done" : "next")
                        Image(systemName: selection == totalPages - 1 ? "checkmark.circle" : "chevron.right.circle")
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selection == totalPages - 1 ? "Finish onboarding" : "Next onboarding card")
            }
            LiquidGlassCard(intensity: 0.6, cornerRadius: 14, shadowIntensity: 0.14) {
                Button(action: skip) {
                    HStack(spacing: 8) {
                        Text("skip")
                        Image(systemName: "xmark.circle")
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip onboarding")
            }
        }
    }
    
    private var card1: some View {
        LiquidGlassCard(intensity: 0.7, cornerRadius: 24, shadowIntensity: 0.25) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.blue)
                    cardTitle("Ready to explore?")
                }
                
                HStack(spacing: 10) {
                    Image(systemName: "headphones")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.purple)
                    Text("Pop in headphones—it's way better with audio.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Divider().opacity(0.2)
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 6) {
                        permissionStatusRow(
                            title: "Location",
                            message: "Helps us guide you where you are.",
                            statusText: locationStatusDescription,
                            isActive: isLocationAuthorized
                        )
                        if shouldShowLocationAction { permissionActionButton(title: locationActionTitle, systemImage: "location", action: requestLocationAuthorization) }
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        permissionStatusRow(
                            title: "Notifications",
                            message: "Keep you in the loop, quietly.",
                            statusText: notificationStatusDescription,
                            isActive: isNotificationAuthorized
                        )
                        if shouldShowNotificationAction { permissionActionButton(title: notificationActionTitle, systemImage: "bell.badge", action: requestNotificationAuthorization) }
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
    }
    
    private var card2: some View {
        LiquidGlassCard(intensity: 0.7, cornerRadius: 24, shadowIntensity: 0.25) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.green)
                    cardTitle("How it works")
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                    Text("Tap begin and just speak.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.iphone")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.purple)
                    Text("Pocket your phone or multitask—Guido stays with you.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                    Text("Tweak language, theme, or sign out in settings.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
    }
    
    private var card3: some View {
        LiquidGlassCard(intensity: 0.7, cornerRadius: 24, shadowIntensity: 0.25) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Explore what you can do")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
 
                 // Top preview area driven by selected capability
                 if let cap = selectedCapability {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cap.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(cap.examples.prefix(2)), id: \.self) { ex in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(.tertiaryLabel))
                                    Text(ex)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 70, maxHeight: 90, alignment: .topLeading)
                 } else {
                     Text("Tap an icon below for examples")
                         .font(.system(size: 12, weight: .medium, design: .rounded))
                         .foregroundColor(.secondary)
                         .frame(minHeight: 70, maxHeight: 90, alignment: .center)
                 }
 
                 Divider().opacity(0.2)
 
                 // Icons-only grid at the bottom
                 ScrollView(.vertical, showsIndicators: false) {
                     LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                         ForEach(capabilities) { cap in
                             Button {
                                 impactGenerator.impactOccurred()
                                 selectedCapability = cap
                             } label: {
                                 capabilityIcon(cap, isSelected: cap.title == selectedCapability?.title)
                             }
                             .buttonStyle(.plain)
                             .accessibilityLabel("Select capability: \(cap.title)")
                         }
                     }
                     .padding(.top, 2)
                 }
                 .frame(maxHeight: 360)
             }
            .padding(12)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
        .animation(nil, value: selectedCapability?.title)
    }
    
    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(Color(.secondaryLabel))
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.thinMaterial)
            .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 12)
    }
    
    private var toastView: some View {
        Group {
            if let message = toastMessage {
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(18)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func permissionStatusRow(title: String, message: String, statusText: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(isActive ? .green : .orange)
            }
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
    
    private func permissionActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        LiquidGlassCard(intensity: 0.5, cornerRadius: 14, shadowIntensity: 0.12) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    Text(title.lowercased())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundColor(Color(.secondaryLabel))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func capabilityTile(_ capability: Capability) -> some View {
        LiquidGlassCard(intensity: 0.5, cornerRadius: 16, shadowIntensity: 0.12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: capability.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(capability.tint)
                    .frame(width: 22, height: 22)
                Text(capability.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Color(.secondaryLabel))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
    
    private func handlePromptTap(_ prompt: String) {
        UIPasteboard.general.string = prompt
        impactGenerator.impactOccurred()
        let message = "Copied “\(prompt)”"
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if toastMessage == message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }
    
    private func updatePermissionStates() async {
        let locationResult = await locationManager.requestAuthorization()
        await notificationService.refreshAuthorizationStatus()
        await MainActor.run {
            locationStatus = locationResult
            notificationStatus = notificationService.authorizationStatus
        }
    }
    
    private func requestLocationAuthorization() {
        switch locationStatus {
        case .denied, .restricted:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
        default:
            Task {
                let status = await locationManager.requestAuthorization()
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        locationStatus = status
                    }
                }
            }
        }
    }
    
    private func requestNotificationAuthorization() {
        if notificationStatus == .denied {
            notificationService.openSystemSettings()
            return
        }
        Task {
            let status = await notificationService.requestAuthorization()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    notificationStatus = status
                }
            }
        }
    }
    
    private func nextOrComplete() {
        if selection < totalPages - 1 {
            withAnimation(.easeInOut(duration: 0.25)) {
                selection += 1
            }
        } else {
            complete()
        }
    }
    
    private func skip() {
        complete()
    }
    
    private func complete() {
        impactGenerator.impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            onboarding.dismissOnboarding(currentUserId: appState.currentUserId)
        }
    }
    
    private var primaryMessage: String {
        onboarding.mode == .help
            ? "Here’s a refresher on Guido. For the best experience, connect headphones and keep permissions up to date."
            : "For the best experience, connect your headphones and allow access so Guido can guide you wherever you are."
    }
    
    private var headerSubtitle: String {
        onboarding.mode == .help
            ? "Here’s a refresher on how Guido keeps you oriented and inspired."
            : "Let’s set up a few essentials so Guido can be your everywhere guide."
    }
    
    private var locationStatusDescription: String {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Allowed"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            return "Allow Access"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var notificationStatusDescription: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Open Settings"
        case .notDetermined:
            return "Allow Access"
        @unknown default:
            return "Unknown"
        }
    }
    
    private var shouldShowLocationAction: Bool {
        switch locationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return onboarding.mode == .firstRun && !isLocationAuthorized
        case .notDetermined, .denied, .restricted:
            return true
        @unknown default:
            return false
        }
    }
    
    private var locationActionTitle: String {
        switch locationStatus {
        case .denied, .restricted:
            return "Open Settings"
        default:
            return "Enable Location"
        }
    }
    
    private var shouldShowNotificationAction: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return onboarding.mode == .firstRun && !isNotificationAuthorized
        case .denied, .notDetermined:
            return true
        @unknown default:
            return false
        }
    }
    
    private var notificationActionTitle: String {
        notificationStatus == .denied ? "Open Settings" : "Enable Notifications"
    }
    
    private var isLocationAuthorized: Bool {
        locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse
    }
    
    private var isNotificationAuthorized: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
    
    private var starterPrompts: [String] { [] }
    
    private var capabilities: [Capability] {
        [
            Capability(
                title: "Find places",
                systemImage: "mappin.and.ellipse",
                detail: "Discover cafés, parks, shops, and venues around you.",
                tint: .blue,
                examples: ["Find a quiet coffee shop nearby","Best parks within 15 minutes","Closest late‑night pharmacy"]
            ),
            Capability(
                title: "Get directions",
                systemImage: "map",
                detail: "Turn-by-turn directions with quick Maps handoff.",
                tint: .blue,
                examples: ["Walk to Central Park","Fastest transit to JFK","Bike route to the beach"]
            ),
            Capability(
                title: "On-the-way stops",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                detail: "Find the perfect place to stop without leaving your route.",
                tint: .teal,
                examples: ["Coffee on the way to work","Quick lunch on the route","EV charger along my drive"]
            ),
            Capability(
                title: "Menus & dietary",
                systemImage: "fork.knife",
                detail: "Scan menus for dietary tags, sections, and signatures.",
                tint: .orange,
                examples: ["Gluten‑free desserts at Levain","Vegan options near me","Kid‑friendly menu items"]
            ),
            Capability(
                title: "Price ranges",
                systemImage: "dollarsign.circle",
                detail: "Estimate price level from menus or catalogs.",
                tint: .orange,
                examples: ["Is this spot $$ or $$$?","Great budget dinner nearby","Average coffee price around here"]
            ),
            Capability(
                title: "Compare products",
                systemImage: "rectangle.and.text.magnifyingglass",
                detail: "Summaries to weigh retail products and services.",
                tint: .purple,
                examples: ["Compare two running shoes","Best carry‑on under $200","Light jackets for rainy days"]
            ),
            Capability(
                title: "Reviews insights",
                systemImage: "quote.bubble",
                detail: "See what people praise—or complain about.",
                tint: .green,
                examples: ["Common complaints at this café","How’s the service here?","Is it laptop‑friendly?"]
            ),
            Capability(
                title: "Vibe & photos",
                systemImage: "camera.on.rectangle",
                detail: "Understand ambiance, seating, and accessibility.",
                tint: .mint,
                examples: ["Is it quiet to read?","Comfy seating & outlets?","Clean and bright inside?"]
            ),
            Capability(
                title: "Look up policies",
                systemImage: "doc.plaintext",
                detail: "Return, dress-code, or age policies in a pinch.",
                tint: .indigo,
                examples: ["Return policy at Uniqlo","Age policy for this venue","Cancellation rules for tours"]
            ),
            Capability(
                title: "Read PDFs",
                systemImage: "doc.richtext",
                detail: "Extract highlights from menus or brochures.",
                tint: .indigo,
                examples: ["Brunch menu PDF","Hotel spa services PDF","Event brochure highlights"]
            ),
            Capability(
                title: "Live sports & scores",
                systemImage: "sportscourt",
                detail: "Grab fresh scores, fixtures, and match recaps.",
                tint: .pink,
                examples: ["Premier League scores now","NBA results tonight","When does my team play?"]
            ),
            Capability(
                title: "Local events",
                systemImage: "calendar",
                detail: "See what’s happening around you this week.",
                tint: .pink,
                examples: ["What’s on this weekend?","Live music near me","Family‑friendly events tonight"]
            ),
            Capability(
                title: "Weather",
                systemImage: "cloud.sun",
                detail: "Current conditions and short forecasts.",
                tint: .cyan,
                examples: ["Will it rain today?","Best time for a walk","Wind and temps this evening"]
            ),
            Capability(
                title: "Currency",
                systemImage: "coloncurrencysign.circle",
                detail: "Quick conversions with live exchange rates.",
                tint: .yellow,
                examples: ["20 EUR in USD","Convert 5,000 JPY","Is cash or card better here?"]
            ),
            Capability(
                title: "Translate",
                systemImage: "character.bubble",
                detail: "Translate phrases or signage instantly.",
                tint: .purple,
                examples: ["How to say thanks in Italian","Translate this menu item","What does this sign say?"]
            ),
            Capability(
                title: "Safety & emergency",
                systemImage: "cross.circle",
                detail: "Access advisories and emergency contacts on the go.",
                tint: .red,
                examples: ["Local emergency numbers","Any current advisories?","Nearest hospital or clinic"]
            )
        ]
    }
    
    private func capabilityIcon(_ capability: Capability, isSelected: Bool) -> some View {
        LiquidGlassCard(intensity: 0.5, cornerRadius: 14, shadowIntensity: 0.12) {
            Image(systemName: capability.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(capability.tint)
                .frame(width: 40, height: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? capability.tint.opacity(0.5) : Color.clear, lineWidth: 2)
                )
                .padding(6)
        }
        .frame(height: 52)
    }
    
    private let totalPages = 3
}

private struct Capability: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let detail: String
    let tint: Color
    let examples: [String]
}

private struct CapabilityDetailSheet: View {
    let capability: Capability
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What it does")) {
                    Text(capability.detail)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                }
                
                if !capability.examples.isEmpty {
                    Section(header: Text("Try asking")) {
                        ForEach(capability.examples, id: \.self) { example in
                            Text(example)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(capability.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

private struct FlexiblePromptGrid: View {
    let prompts: [String]
    let onTap: (String) -> Void
    
    private let columns = [
        GridItem(.flexible(minimum: 120), spacing: 12),
        GridItem(.flexible(minimum: 120), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    onTap(prompt)
                } label: {
                    Text(prompt)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground).opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy prompt: \(prompt)")
            }
        }
    }
}


