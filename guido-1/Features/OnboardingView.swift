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
    @State private var isDismissing: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var gridContentHeight: CGFloat = 0
    
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
            .opacity(isDismissing ? 0 : 1)
            .scaleEffect(isDismissing ? 0.98 : 1)
            .offset(y: hasAppeared ? 0 : 24)
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            impactGenerator.prepare()
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = 0
            }
            if selectedCapability == nil {
                selectedCapability = capabilities.first
            }
            if UIAccessibility.isReduceMotionEnabled {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82).delay(0.05)) {
                    hasAppeared = true
                }
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
        Text("\(greeting), let's roam")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.top, 20)
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
                Button(action: { selection == totalPages - 1 ? complete() : nextOrComplete() }) {
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
    
    private var cardHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if screenHeight < 700 { return 420 }
        if screenHeight > 850 { return 460 }
        return 440
    }
    
    private var capabilityTileHeight: CGFloat { 52 }
    private var capabilityRowSpacing: CGFloat { 10 }
    private var gridRevealAmount: CGFloat { 18 }
    private var gridViewportHeight: CGFloat {
        // Show 2 full rows plus a partial third row to hint scroll
        (capabilityTileHeight * 2) + capabilityRowSpacing + gridRevealAmount
    }
    
    private var card1: some View {
        LiquidGlassCard(intensity: 0.75, cornerRadius: 24, shadowIntensity: 0.28, enableFloating: false, enableShimmer: true) {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingTitle(
                    iconName: "sparkles",
                    iconTint: .blue,
                    title: "Ready to explore?",
                    subtitle: "Pop in headphones—it's way better with audio.",
                    step: 1,
                    total: totalPages
                )
                VStack(spacing: 16) {
                    OnboardingRow(
                        iconName: "location.fill",
                        iconTint: .blue,
                        title: "Location",
                        subtitle: "Helps us guide you where you are.",
                        trailingIconName: isLocationAuthorized ? "checkmark.circle.fill" : nil,
                        trailingTint: isLocationAuthorized ? .green : .orange,
                        trailingText: isLocationAuthorized ? nil : locationStatusDescription
                    )
                    if shouldShowLocationAction {
                        permissionActionButton(title: locationActionTitle, systemImage: "location", action: requestLocationAuthorization)
                    }
                    OnboardingRow(
                        iconName: "bell.fill",
                        iconTint: .orange,
                        title: "Notifications",
                        subtitle: "Keep you in the loop, quietly.",
                        trailingIconName: isNotificationAuthorized ? "checkmark.circle.fill" : nil,
                        trailingTint: isNotificationAuthorized ? .green : .orange,
                        trailingText: isNotificationAuthorized ? nil : notificationStatusDescription
                    )
                    if shouldShowNotificationAction {
                        permissionActionButton(title: notificationActionTitle, systemImage: "bell.badge", action: requestNotificationAuthorization)
                    }
                }
                .padding(.bottom, 4)
                
                VStack(spacing: 12) {
                    OnboardingRow(
                        iconName: "wifi.slash",
                        iconTint: Color(.tertiaryLabel),
                        title: "Works offline for basic navigation",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                    OnboardingRow(
                        iconName: "lock.shield",
                        iconTint: Color(.tertiaryLabel),
                        title: "Your data stays private on your device",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                    OnboardingRow(
                        iconName: "gearshape",
                        iconTint: Color(.tertiaryLabel),
                        title: "Change permissions anytime in Settings",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                }
            }
            .padding(20)
            .frame(height: cardHeight)
        }
        .padding(.horizontal, 6)
                    .frame(maxWidth: 520)
    }
    
    private var card2: some View {
        LiquidGlassCard(intensity: 0.75, cornerRadius: 24, shadowIntensity: 0.28, enableFloating: false, enableShimmer: true) {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingTitle(
                    iconName: "waveform.circle.fill",
                    iconTint: .green,
                    title: "How it works",
                    subtitle: "Hands-free. Interrupt anytime.",
                    step: 2,
                    total: totalPages
                )
                VStack(spacing: 16) {
                    OnboardingRow(
                        iconName: "mic.fill",
                        iconTint: .blue,
                        title: "Tap begin and just speak.",
                        subtitle: nil
                    )
                    OnboardingRow(
                        iconName: "lock.iphone",
                        iconTint: .purple,
                        title: "Pocket your phone or multitask—Guido stays with you.",
                        subtitle: nil
                    )
                    OnboardingRow(
                        iconName: "gearshape.fill",
                        iconTint: .orange,
                        title: "Tweak language, theme, or sign out in settings.",
                        subtitle: nil
                    )
                            }
                            .padding(.bottom, 4)
                            
                VStack(spacing: 12) {
                    OnboardingRow(
                        iconName: "waveform.and.mic",
                        iconTint: Color(.tertiaryLabel),
                        title: "Speak naturally—interrupt anytime",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                    OnboardingRow(
                        iconName: "arrow.uturn.left.circle",
                        iconTint: Color(.tertiaryLabel),
                        title: "Ask follow-up questions as you go",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                    OnboardingRow(
                        iconName: "xmark.circle",
                        iconTint: Color(.tertiaryLabel),
                        title: "Tap end when you're done exploring",
                        subtitle: nil,
                        titleColor: .secondary
                    )
                }
            }
            .padding(20)
            .frame(height: cardHeight)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
    }
    
    private var card3: some View {
        VStack(spacing: 14) {
            LiquidGlassCard(intensity: 0.75, cornerRadius: 24, shadowIntensity: 0.28, enableFloating: false, enableShimmer: true) {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingTitle(
                        iconName: "sparkle.magnifyingglass",
                        iconTint: .purple,
                        title: "Explore what you can do",
                        subtitle: "Tap an icon to see examples.",
                        step: 3,
                        total: totalPages
                    )
                    
                    if let cap = selectedCapability {
                        VStack(alignment: .leading, spacing: 12) {
                            OnboardingRow(
                                iconName: cap.systemImage,
                                iconTint: cap.tint,
                                title: cap.title,
                                subtitle: cap.detail,
                                titleColor: .primary,
                                subtitleColor: .secondary
                            )
                            ForEach(Array(cap.examples.prefix(2)), id: \.self) { example in
                                OnboardingRow(
                                    iconName: "arrow.right.circle",
                                    iconTint: Color(.tertiaryLabel),
                                    title: example,
                                    subtitle: nil,
                                    titleColor: .secondary
                                )
                            }
                        }
                        .padding(.bottom, 4)
                    } else {
                        Text("Tap an icon below for examples")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(minHeight: 75, alignment: .leading)
                    }
                    
                    Divider().opacity(0.3).padding(.vertical, 12)
                    
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
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: GridContentHeightKey.self, value: geo.size.height)
                            }
                        )
                    }
                    .frame(height: gridViewportHeight)
                    .onPreferenceChange(GridContentHeightKey.self) { newHeight in
                        gridContentHeight = newHeight
                    }
                }
                .padding(20)
                .frame(height: cardHeight)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: 520)
        .animation(nil, value: selectedCapability?.title)
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
    
    private func capabilityIcon(_ capability: Capability, isSelected: Bool) -> some View {
        LiquidGlassCard(intensity: isSelected ? 0.65 : 0.5, cornerRadius: 14, shadowIntensity: isSelected ? 0.18 : 0.12, enableFloating: false, enableShimmer: false) {
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

    private var capabilities: [Capability] {
        [
            Capability(
                title: "Find places",
                systemImage: "mappin.and.ellipse",
                detail: "Discover cafés, parks, shops, and venues around you.",
                tint: .blue,
                examples: ["Find a quiet coffee shop nearby", "Best parks within 15 minutes", "Closest late‑night pharmacy"]
            ),
            Capability(
                title: "Get directions",
                systemImage: "map",
                detail: "Turn-by-turn directions with quick Maps handoff.",
                tint: .blue,
                examples: ["Walk to Central Park", "Fastest transit to JFK", "Bike route to the beach"]
            ),
            Capability(
                title: "On-the-way stops",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                detail: "Find the perfect place to stop without leaving your route.",
                tint: .teal,
                examples: ["Coffee on the way to work", "Quick lunch on the route", "EV charger along my drive"]
            ),
            Capability(
                title: "Menus & dietary",
                systemImage: "fork.knife",
                detail: "Scan menus for dietary tags, sections, and signatures.",
                tint: .orange,
                examples: ["Gluten‑free desserts at Levain", "Vegan options near me", "Kid‑friendly menu items"]
            ),
            Capability(
                title: "Price ranges",
                systemImage: "dollarsign.circle",
                detail: "Estimate price level from menus or catalogs.",
                tint: .orange,
                examples: ["Is this spot $$ or $$$?", "Great budget dinner nearby", "Average coffee price around here"]
            ),
            Capability(
                title: "Compare products",
                systemImage: "rectangle.and.text.magnifyingglass",
                detail: "Summaries to weigh retail products and services.",
                tint: .purple,
                examples: ["Compare two running shoes", "Best carry‑on under $200", "Light jackets for rainy days"]
            ),
            Capability(
                title: "Reviews insights",
                systemImage: "quote.bubble",
                detail: "See what people praise—or complain about.",
                tint: .green,
                examples: ["Common complaints at this café", "How’s the service here?", "Is it laptop‑friendly?"]
            ),
            Capability(
                title: "Vibe & photos",
                systemImage: "camera.on.rectangle",
                detail: "Understand ambiance, seating, and accessibility.",
                tint: .mint,
                examples: ["Is it quiet to read?", "Comfy seating & outlets?", "Clean and bright inside?"]
            ),
            Capability(
                title: "Look up policies",
                systemImage: "doc.plaintext",
                detail: "Return, dress-code, or age policies in a pinch.",
                tint: .indigo,
                examples: ["Return policy at Uniqlo", "Age policy for this venue", "Cancellation rules for tours"]
            ),
            Capability(
                title: "Read PDFs",
                systemImage: "doc.richtext",
                detail: "Extract highlights from menus or brochures.",
                tint: .indigo,
                examples: ["Brunch menu PDF", "Hotel spa services PDF", "Event brochure highlights"]
            ),
            Capability(
                title: "Live sports & scores",
                systemImage: "sportscourt",
                detail: "Grab fresh scores, fixtures, and match recaps.",
                tint: .pink,
                examples: ["Premier League scores now", "NBA results tonight", "When does my team play?"]
            ),
            Capability(
                title: "Local events",
                systemImage: "calendar",
                detail: "See what’s happening around you this week.",
                tint: .pink,
                examples: ["What’s on this weekend?", "Live music near me", "Family‑friendly events tonight"]
            ),
            Capability(
                title: "Weather",
                systemImage: "cloud.sun",
                detail: "Current conditions and short forecasts.",
                tint: .cyan,
                examples: ["Will it rain today?", "Best time for a walk", "Wind and temps this evening"]
            ),
            Capability(
                title: "Currency",
                systemImage: "coloncurrencysign.circle",
                detail: "Quick conversions with live exchange rates.",
                tint: .yellow,
                examples: ["20 EUR in USD", "Convert 5,000 JPY", "Is cash or card better here?"]
            ),
            Capability(
                title: "Translate",
                systemImage: "character.bubble",
                detail: "Translate phrases or signage instantly.",
                tint: .purple,
                examples: ["How to say thanks in Italian", "Translate this menu item", "What does this sign say?"]
            ),
            Capability(
                title: "Safety & emergency",
                systemImage: "cross.circle",
                detail: "Access advisories and emergency contacts on the go.",
                tint: .red,
                examples: ["Local emergency numbers", "Any current advisories?", "Nearest hospital or clinic"]
            )
        ]
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome"
        }
    }

    private var shouldShowScrollHint: Bool {
        if selection == 2 { return true }
        if gridContentHeight > 280 { return true }
        let columns = UIScreen.main.bounds.width > 360 ? 4 : 3
        let rows = ceil(Double(capabilities.count) / Double(columns))
        let estimatedHeight = rows * 62.0 // ~52 tile + ~10 spacing
        return estimatedHeight > 300
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.18)) {
            isDismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onboarding.dismissOnboarding(currentUserId: appState.currentUserId)
            isDismissing = false
            hasAppeared = false
        }
    }
}

private struct OnboardingTitle: View {
    let iconName: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let step: Int
    let total: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconTint)
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                Spacer()
                OnboardingProgress(current: step, total: total)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Divider().opacity(0.3)
        }
    }
}

private struct OnboardingRow: View {
    let iconName: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    let titleColor: Color
    let subtitleColor: Color
    let trailingIconName: String?
    let trailingTint: Color?
    let trailingText: String?
    
    init(
        iconName: String,
        iconTint: Color,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = .primary,
        subtitleColor: Color = .secondary,
        trailingIconName: String? = nil,
        trailingTint: Color? = nil,
        trailingText: String? = nil
    ) {
        self.iconName = iconName
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.trailingIconName = trailingIconName
        self.trailingTint = trailingTint
        self.trailingText = trailingText
    }
    
    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(iconTint)
                .frame(width: 24, height: 24)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if trailingIconName != nil || trailingText != nil {
                HStack(spacing: 6) {
                    if let trailingText {
                        Text(trailingText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(trailingTint ?? .secondary)
                    }
                    if let trailingIconName {
                        Image(systemName: trailingIconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(trailingTint ?? .secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityLabelText: String {
        if let subtitle, !subtitle.isEmpty {
            return "\(title). \(subtitle)"
        }
        return title
    }
    
    private var accessibilityValueText: String {
        if let trailingText {
            return trailingText
        }
        if trailingIconName == "checkmark.circle.fill" {
            return "Allowed"
        }
        return ""
    }
}

private struct OnboardingProgress: View {
    let current: Int
    let total: Int
    
    var body: some View {
        Text("Step \(current) of \(total)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
    }
}

private struct Capability: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let detail: String
    let tint: Color
    let examples: [String]
}


private struct GridContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


