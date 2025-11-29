//
//  NavigationManager.swift
//  guido-1
//
//  Core service for managing turn-by-turn navigation sessions
//

import Foundation
import CoreLocation
import Combine
import GoogleMaps
import GoogleNavigation

// MARK: - Navigation Manager

/// Singleton service managing active turn-by-turn navigation
@MainActor
final class NavigationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NavigationManager()
    
    // MARK: - Published State
    
    @Published private(set) var isNavigating: Bool = false
    @Published private(set) var navState: NavigationState = .idle
    @Published private(set) var currentInstruction: String = ""
    @Published private(set) var nextInstruction: String = ""
    @Published private(set) var distanceToNextTurnMeters: Int = 0
    @Published private(set) var timeToNextTurnSeconds: Int = 0
    @Published private(set) var remainingDistanceMeters: Int = 0
    @Published private(set) var remainingTimeSeconds: Int = 0
    @Published private(set) var currentRoadName: String = ""
    @Published private(set) var currentManeuver: String = ""
    @Published private(set) var stepsRemaining: Int = 0
    
    // MARK: - Active Journey
    
    @Published private(set) var activeJourney: NavigationJourney?
    
    // MARK: - Event Publisher
    
    let navigationEventPublisher = PassthroughSubject<NavigationEvent, Never>()
    
    // MARK: - Private Properties
    
    private var mapView: GMSMapView?
    private var navigator: GMSNavigator?
    private var journeySink: JourneySink?
    
    // Track when navigation started to avoid immediate reroute noise
    private var navigationStartTime: Date?
    private var hasHandledInitialRouteChange = false
    private var lastRouteSnapshot: RouteSnapshot?
    private var pendingInitialInstructionAnnouncement = false
    private let stationarySpeedThreshold: CLLocationSpeed = 0.5
    
    // Breadcrumb batching
    private var pendingBreadcrumbs: [NavigationBreadcrumb] = []
    private var breadcrumbFlushTimer: Timer?
    private let breadcrumbBatchSize = 10
    private let breadcrumbFlushInterval: TimeInterval = 30
    
    // Announcement tracking
    private var lastAnnouncedStepIndex: Int = -1
    private var lastAnnouncementTime: Date = .distantPast
    private var lastAnnouncedStage: Int = 4 // 0=immediate, 1=near, 2=far, 3=distant, 4=none
    private let minimumAnnouncementInterval: TimeInterval = 5
    
    // Distance thresholds for announcements (in meters)
    private let farAnnouncementDistance = 800   // ~0.5 miles
    private let nearAnnouncementDistance = 150  // ~500 feet
    private let immediateAnnouncementDistance = 30 // ~100 feet
    private let rerouteDistanceThresholdMeters = 100
    private let rerouteTimeThresholdSeconds = 30
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        print("🗺️ [NavigationManager] Initialized")
    }
    
    // MARK: - Configuration
    
    func configure(journeySink: JourneySink) {
        self.journeySink = journeySink
        print("🗺️ [NavigationManager] Configured with journey sink")
    }
    
    // MARK: - Start Navigation
    
    func startNavigation(
        to destination: CLLocationCoordinate2D,
        destinationName: String?,
        destinationAddress: String,
        travelMode: TravelMode = .driving,
        from origin: CLLocationCoordinate2D,
        originAddress: String? = nil,
        userId: String? = nil,
        userEmail: String? = nil,
        sessionId: String? = nil,
        routeDistanceMetersOverride: Int? = nil,
        routeTimeSecondsOverride: Int? = nil,
        initialStepsCountOverride: Int? = nil
    ) async -> Result<NavigationJourney, NavigationError> {
        
        guard !isNavigating else {
            return .failure(.alreadyNavigating)
        }
        
        print("🗺️ [NavigationManager] Starting navigation to: \(destinationAddress)")
        
        navState = .calculating
        navigationStartTime = Date()
        hasHandledInitialRouteChange = false
        
        // Check terms acceptance
        let termsAccepted = await checkTermsAcceptance()
        guard termsAccepted else {
            navState = .error
            return .failure(.termsNotAccepted)
        }
        
        // Create map view and navigator
        let mapView = GMSMapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        mapView.isNavigationEnabled = true
        self.mapView = mapView
        
        guard let navigator = mapView.navigator else {
            navState = .error
            return .failure(.navigatorUnavailable)
        }
        
        self.navigator = navigator
        navigator.add(self)
        navigator.voiceGuidance = .silent // We handle voice via Guido
        
        // Create waypoint
        guard let waypoint = GMSNavigationWaypoint(location: destination, title: destinationName ?? "Destination") else {
            navState = .error
            return .failure(.invalidDestination)
        }
        
        // Calculate route
        let routeResult = await calculateRoute(navigator: navigator, waypoint: waypoint)
        
        guard case .success(let routeInfo) = routeResult else {
            navState = .error
            if case .failure(let error) = routeResult {
                return .failure(error)
            }
            return .failure(.routeCalculationFailed)
        }
        
        // Determine canonical route summary (allowing external overrides, e.g., Routes API with specific travel mode)
        let canonicalDistance = routeDistanceMetersOverride ?? routeInfo.distanceMeters
        let canonicalTime = routeTimeSecondsOverride ?? routeInfo.timeSeconds
        let canonicalSteps = initialStepsCountOverride ?? routeInfo.stepsCount
        
        // Create journey
        var journey = NavigationJourney(
            destinationAddress: destinationAddress,
            destinationLat: destination.latitude,
            destinationLng: destination.longitude,
            destinationName: destinationName,
            travelMode: travelMode,
            userId: userId,
            userEmail: userEmail,
            sessionId: sessionId
        )
        
        journey.setOrigin(address: originAddress, lat: origin.latitude, lng: origin.longitude)
        journey.setRouteSummary(
            distanceMeters: canonicalDistance,
            timeSeconds: canonicalTime,
            stepsCount: canonicalSteps
        )
        
        // Persist journey
        if let sink = journeySink {
            do {
                let createdJourney = try await sink.createJourney(journey)
                journey = createdJourney
            } catch {
                print("⚠️ [NavigationManager] Failed to persist journey: \(error)")
                // Continue anyway - navigation still works
            }
        }
        
        // Start guidance
        navigator.isGuidanceActive = true
        
        // Update state
        activeJourney = journey
        isNavigating = true
        navState = .enroute
        remainingDistanceMeters = canonicalDistance
        remainingTimeSeconds = canonicalTime
        stepsRemaining = canonicalSteps
        lastAnnouncedStepIndex = -1
        lastAnnouncedStage = 4
        navigationStartTime = Date()
        lastRouteSnapshot = RouteSnapshot(distanceMeters: canonicalDistance, timeSeconds: canonicalTime)
        pendingInitialInstructionAnnouncement = true
        
        // Start breadcrumb timer
        startBreadcrumbTimer()
        
        // Publish event
        navigationEventPublisher.send(.started(journey: journey))
        
        print("✅ [NavigationManager] Navigation started - \(journey.formattedDistance), \(journey.formattedTime)")
        
        return .success(journey)
    }
    
    // MARK: - Stop Navigation
    
    func stopNavigation(cancelled: Bool = true) async {
        guard isNavigating else { return }
        
        print("🗺️ [NavigationManager] Stopping navigation (cancelled: \(cancelled))")
        
        // Stop guidance
        navigator?.isGuidanceActive = false
        navigator?.clearDestinations()
        
        // Flush remaining breadcrumbs
        await flushBreadcrumbs()
        stopBreadcrumbTimer()
        
        // Update journey
        if var journey = activeJourney {
            if cancelled {
                journey.markCancelled()
                navigationEventPublisher.send(.cancelled(journey: journey))
            } else {
                journey.markCompleted()
                navigationEventPublisher.send(.arrived(journey: journey))
            }
            
            // Persist final state
            if let sink = journeySink {
                do {
                    try await sink.updateJourney(journey)
                } catch {
                    print("⚠️ [NavigationManager] Failed to update journey: \(error)")
                }
            }
        }
        
        // Clean up
        if let nav = navigator {
            nav.remove(self)
        }
        navigator = nil
        mapView = nil
        activeJourney = nil
        lastRouteSnapshot = nil
        
        // Reset state
        isNavigating = false
        navState = .idle
        currentInstruction = ""
        nextInstruction = ""
        distanceToNextTurnMeters = 0
        timeToNextTurnSeconds = 0
        remainingDistanceMeters = 0
        remainingTimeSeconds = 0
        currentRoadName = ""
        currentManeuver = ""
        stepsRemaining = 0
        lastAnnouncedStepIndex = -1
        lastAnnouncedStage = 4
        navigationStartTime = nil
        hasHandledInitialRouteChange = false
        pendingInitialInstructionAnnouncement = false
        
        print("✅ [NavigationManager] Navigation stopped")
    }
    
    // MARK: - Record Location
    
    func recordLocation(_ location: CLLocation) {
        guard isNavigating else { return }
        
        let breadcrumb = NavigationBreadcrumb(location: location)
        pendingBreadcrumbs.append(breadcrumb)
        
        // Batch flush if needed
        if pendingBreadcrumbs.count >= breadcrumbBatchSize {
            Task {
                await flushBreadcrumbs()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func checkTermsAcceptance() async -> Bool {
        return await withCheckedContinuation { continuation in
            let termsOptions = GMSNavigationTermsAndConditionsOptions(companyName: "Guido")
            GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with: termsOptions) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }
    
    // Safely convert Double-based distances/times to Int, avoiding crashes on NaN/inf or overflow
    private func safeInt(from value: Double) -> Int {
        guard value.isFinite else { return 0 }
        
        // Clamp to Int range to avoid overflow traps
        let maxIntDouble = Double(Int.max)
        let minIntDouble = Double(Int.min)
        
        if value > maxIntDouble {
            return Int.max
        } else if value < minIntDouble {
            return Int.min
        } else {
            return Int(value)
        }
    }
    
    private func calculateRoute(navigator: GMSNavigator, waypoint: GMSNavigationWaypoint) async -> Result<RouteInfo, NavigationError> {
        return await withCheckedContinuation { continuation in
            navigator.setDestinations([waypoint]) { routeStatus in
                Task { @MainActor in
                    switch routeStatus {
                    case .OK:
                        let distance = self.safeInt(from: navigator.distanceToNextDestination)
                        let time = self.safeInt(from: navigator.timeToNextDestination)
                        // Step count will be determined when we receive navInfo
                        let steps = 0
                        
                        let info = RouteInfo(distanceMeters: distance, timeSeconds: time, stepsCount: steps)
                        continuation.resume(returning: .success(info))
                        
                    case .noRouteFound:
                        continuation.resume(returning: .failure(.noRouteFound))
                    case .networkError:
                        continuation.resume(returning: .failure(.networkError))
                    case .quotaExceeded:
                        continuation.resume(returning: .failure(.quotaExceeded))
                    case .apiKeyNotAuthorized:
                        continuation.resume(returning: .failure(.apiKeyNotAuthorized))
                    case .locationUnavailable:
                        continuation.resume(returning: .failure(.locationUnavailable))
                    default:
                        continuation.resume(returning: .failure(.routeCalculationFailed))
                    }
                }
            }
        }
    }
    
    private func startBreadcrumbTimer() {
        breadcrumbFlushTimer = Timer.scheduledTimer(withTimeInterval: breadcrumbFlushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.flushBreadcrumbs()
            }
        }
    }
    
    private func stopBreadcrumbTimer() {
        breadcrumbFlushTimer?.invalidate()
        breadcrumbFlushTimer = nil
    }
    
    private func flushBreadcrumbs() async {
        guard !pendingBreadcrumbs.isEmpty, let journeyId = activeJourney?.id, let sink = journeySink else {
            return
        }
        
        let breadcrumbsToFlush = pendingBreadcrumbs
        pendingBreadcrumbs = []
        
        do {
            try await sink.appendBreadcrumbs(breadcrumbsToFlush, journeyId: journeyId)
        } catch {
            print("⚠️ [NavigationManager] Failed to flush breadcrumbs: \(error)")
            // Re-add failed breadcrumbs
            pendingBreadcrumbs = breadcrumbsToFlush + pendingBreadcrumbs
        }
    }
    
    private func getStage(for distance: Int) -> Int {
        if distance <= immediateAnnouncementDistance { return 0 }
        if distance <= nearAnnouncementDistance { return 1 }
        if distance <= farAnnouncementDistance { return 2 }
        return 3
    }

    private func shouldAnnounce(stepIndex: Int, distanceMeters: Int) -> Bool {
        let now = Date()
        
        // New step - always announce
        if stepIndex != lastAnnouncedStepIndex {
            return true
        }
        
        // If 5 minutes passed, remind (re-announce)
        if now.timeIntervalSince(lastAnnouncementTime) >= 300 {
            return true
        }
        
        // Don't announce too frequently (debounce)
        guard now.timeIntervalSince(lastAnnouncementTime) >= minimumAnnouncementInterval else {
            return false
        }
        
        // Check if we entered a new, closer stage
        let currentStage = getStage(for: distanceMeters)
        if currentStage < lastAnnouncedStage {
            return true
        }
        
        return false
    }
    
    private func recordCheckpoint(step: GMSNavigationStepInfo, stepIndex: Int) {
        guard var journey = activeJourney else { return }
        
        // Get current location from navigator or use step location
        let lat = mapView?.myLocation?.coordinate.latitude ?? 0
        let lng = mapView?.myLocation?.coordinate.longitude ?? 0
        
        let checkpoint = NavigationCheckpoint(
            stepIndex: stepIndex,
            instruction: step.fullInstructionText ?? "Continue",
            roadName: step.fullRoadName,
            maneuver: maneuverToString(step.maneuver),
            latitude: lat,
            longitude: lng,
            distanceFromPreviousMeters: safeInt(from: step.distanceFromPrevStepMeters)
        )
        
        journey.addCheckpoint(checkpoint)
        activeJourney = journey
        
        // Persist checkpoint
        if let sink = journeySink {
            Task {
                do {
                    try await sink.appendCheckpoint(checkpoint, journeyId: journey.id)
                } catch {
                    print("⚠️ [NavigationManager] Failed to persist checkpoint: \(error)")
                }
            }
        }
    }
    
    private func makeNavigationStep(from stepInfo: GMSNavigationStepInfo) -> NavigationStep {
        NavigationStep(
            stepIndex: stepInfo.stepNumber,
            instruction: stepInfo.fullInstructionText ?? maneuverToSpokenText(stepInfo.maneuver),
            roadName: stepInfo.fullRoadName ?? "",
            maneuver: maneuverToString(stepInfo.maneuver),
            distanceMeters: safeInt(from: stepInfo.distanceFromPrevStepMeters)
        )
    }
    
    private func maneuverToString(_ maneuver: GMSNavigationManeuver) -> String {
        switch maneuver {
        case .destination: return "destination"
        case .depart: return "depart"
        case .straight: return "straight"
        case .turnLeft: return "turn_left"
        case .turnRight: return "turn_right"
        case .turnSlightLeft: return "slight_left"
        case .turnSlightRight: return "slight_right"
        case .turnSharpLeft: return "sharp_left"
        case .turnSharpRight: return "sharp_right"
        case .turnKeepLeft: return "keep_left"
        case .turnKeepRight: return "keep_right"
        case .turnUTurnClockwise, .turnUTurnCounterClockwise: return "u_turn"
        case .mergeUnspecified, .mergeLeft, .mergeRight: return "merge"
        case .forkLeft: return "fork_left"
        case .forkRight: return "fork_right"
        case .roundaboutClockwise, .roundaboutCounterClockwise: return "roundabout"
        case .roundaboutExitClockwise, .roundaboutExitCounterClockwise: return "roundabout_exit"
        case .ferryBoat, .ferryTrain: return "ferry"
        case .nameChange: return "name_change"
        default: return "continue"
        }
    }
    
    private func maneuverToSpokenText(_ maneuver: GMSNavigationManeuver) -> String {
        switch maneuver {
        case .destination: return "Arrive at"
        case .depart: return "Head"
        case .straight: return "Continue straight"
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .turnSlightLeft: return "Slight left"
        case .turnSlightRight: return "Slight right"
        case .turnSharpLeft: return "Sharp left"
        case .turnSharpRight: return "Sharp right"
        case .turnKeepLeft: return "Keep left"
        case .turnKeepRight: return "Keep right"
        case .turnUTurnClockwise, .turnUTurnCounterClockwise: return "Make a U-turn"
        case .mergeUnspecified: return "Merge"
        case .mergeLeft: return "Merge left"
        case .mergeRight: return "Merge right"
        case .forkLeft: return "Keep left at fork"
        case .forkRight: return "Keep right at fork"
        case .roundaboutClockwise, .roundaboutCounterClockwise: return "Enter roundabout"
        case .roundaboutExitClockwise, .roundaboutExitCounterClockwise: return "Exit roundabout"
        case .ferryBoat, .ferryTrain: return "Take the ferry"
        case .nameChange: return "Continue on"
        default: return "Continue"
        }
    }
}

// MARK: - GMSNavigatorListener

extension NavigationManager: GMSNavigatorListener {
    
    nonisolated func navigator(_ navigator: GMSNavigator, didArriveAt waypoint: GMSNavigationWaypoint) {
        Task { @MainActor in
            print("🏁 [NavigationManager] Arrived at: \(waypoint.title ?? "destination")")
            
            navState = .arrived
            
            if let journey = activeJourney {
                navigationEventPublisher.send(.arrived(journey: journey))
            }
            
            // Auto-stop navigation
            await stopNavigation(cancelled: false)
        }
    }
    
    nonisolated func navigatorDidChangeRoute(_ navigator: GMSNavigator) {
        Task { @MainActor in
            guard isNavigating else { return }
            
            if !hasHandledInitialRouteChange {
                hasHandledInitialRouteChange = true
                print("🔄 [NavigationManager] Initial route established – suppressing reroute notice")
                navState = .enroute
                lastRouteSnapshot = RouteSnapshot(distanceMeters: safeInt(from: navigator.distanceToNextDestination),
                                                  timeSeconds: safeInt(from: navigator.timeToNextDestination))
                return
            }
            
            if let startTime = navigationStartTime, Date().timeIntervalSince(startTime) < 2.0 {
                print("🔄 [NavigationManager] Ignoring early route refinement (<2s)")
                return
            }

            let newDistance = safeInt(from: navigator.distanceToNextDestination)
            let newTime = safeInt(from: navigator.timeToNextDestination)
            let snapshot = RouteSnapshot(distanceMeters: newDistance, timeSeconds: newTime)
            
            if !shouldAnnounceReroute(for: snapshot) {
                print("🔄 [NavigationManager] Route change within tolerance – suppressing reroute notice")
                lastRouteSnapshot = snapshot
                return
            }
            
            if let currentSpeed = mapView?.myLocation?.speed, currentSpeed >= 0, currentSpeed < stationarySpeedThreshold {
                print("🔄 [NavigationManager] Route change ignored while stationary (speed \(String(format: "%.2f", currentSpeed)) m/s)")
                lastRouteSnapshot = snapshot
                return
            }
            
            lastRouteSnapshot = snapshot
            
            print("🔄 [NavigationManager] Route changed - rerouting")
            
            navState = .rerouting
            activeJourney?.recordReroute()
            
            navigationEventPublisher.send(.rerouting(reason: "Route recalculated"))
            
            // Update remaining distance/time
            remainingDistanceMeters = safeInt(from: navigator.distanceToNextDestination)
            remainingTimeSeconds = safeInt(from: navigator.timeToNextDestination)
            
            // Back to enroute after reroute
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self.navState == .rerouting {
                    self.navState = .enroute
                }
            }
        }
    }
    
    nonisolated func navigator(_ navigator: GMSNavigator, didUpdateRemainingTime time: TimeInterval) {
        Task { @MainActor in
            remainingTimeSeconds = safeInt(from: time)
        }
    }
    
    nonisolated func navigator(_ navigator: GMSNavigator, didUpdateRemainingDistance distance: CLLocationDistance) {
        Task { @MainActor in
            remainingDistanceMeters = safeInt(from: distance)
        }
    }
    
    nonisolated func navigator(_ navigator: GMSNavigator, didUpdate navInfo: GMSNavigationNavInfo) {
        Task { @MainActor in
            // Update nav state
            switch navInfo.navState {
            case .enroute:
                navState = .enroute
            case .rerouting:
                navState = .rerouting
            case .stopped:
                navState = .stopped
            @unknown default:
                break
            }
            
            // Update current step info
            if let currentStep = navInfo.currentStep {
                let instruction = currentStep.fullInstructionText ?? maneuverToSpokenText(currentStep.maneuver)
                currentInstruction = instruction
                currentRoadName = currentStep.fullRoadName ?? ""
                currentManeuver = maneuverToString(currentStep.maneuver)
            }
            
            // Update distance/time to next step
            distanceToNextTurnMeters = safeInt(from: navInfo.distanceToCurrentStepMeters)
            timeToNextTurnSeconds = safeInt(from: navInfo.timeToCurrentStepSeconds)
            
            // Update remaining steps
            stepsRemaining = navInfo.remainingSteps.count
            
            // Get next instruction
            if navInfo.remainingSteps.count > 0 {
                let nextStep = navInfo.remainingSteps[0]
                nextInstruction = nextStep.fullInstructionText ?? maneuverToSpokenText(nextStep.maneuver)
            } else {
                nextInstruction = ""
            }
            
            if pendingInitialInstructionAnnouncement, let currentStepInfo = navInfo.currentStep {
                let currentStep = makeNavigationStep(from: currentStepInfo)
                var upcomingStep: NavigationStep?
                if let nextStepInfo = navInfo.remainingSteps.first {
                    upcomingStep = makeNavigationStep(from: nextStepInfo)
                }
                
                navigationEventPublisher.send(.initialDirections(current: currentStep, next: upcomingStep))
                
                pendingInitialInstructionAnnouncement = false
                lastAnnouncedStepIndex = currentStepInfo.stepNumber
                lastAnnouncementTime = Date()
                lastAnnouncedStage = getStage(for: distanceToNextTurnMeters)
            }
            
            // Check if we should announce
            let stepIndex = navInfo.currentStep?.stepNumber ?? 0
            if shouldAnnounce(stepIndex: stepIndex, distanceMeters: distanceToNextTurnMeters) {
                
                // Create navigation step for event
                if let currentStep = navInfo.currentStep {
                    let step = NavigationStep(
                        stepIndex: stepIndex,
                        instruction: currentInstruction,
                        roadName: currentRoadName,
                        maneuver: currentManeuver,
                        distanceMeters: safeInt(from: currentStep.distanceFromPrevStepMeters)
                    )
                    
                    // Record checkpoint if this is a new step
                    if stepIndex != lastAnnouncedStepIndex {
                        recordCheckpoint(step: currentStep, stepIndex: stepIndex)
                    }
                    
                    // Publish approaching turn event
                    navigationEventPublisher.send(.approachingTurn(step: step, distanceMeters: distanceToNextTurnMeters))
                    
                    lastAnnouncedStepIndex = stepIndex
                    lastAnnouncementTime = Date()
                    lastAnnouncedStage = getStage(for: distanceToNextTurnMeters)
                }
            }
        }
    }
    
    private func shouldAnnounceReroute(for snapshot: RouteSnapshot) -> Bool {
        guard let previous = lastRouteSnapshot else {
            return true
        }
        let distanceDelta = abs(previous.distanceMeters - snapshot.distanceMeters)
        let timeDelta = abs(previous.timeSeconds - snapshot.timeSeconds)
        return distanceDelta >= rerouteDistanceThresholdMeters || timeDelta >= rerouteTimeThresholdSeconds
    }
}

// MARK: - Supporting Types

private struct RouteInfo {
    let distanceMeters: Int
    let timeSeconds: Int
    let stepsCount: Int
}

private struct RouteSnapshot {
    let distanceMeters: Int
    let timeSeconds: Int
}

enum NavigationError: Error, LocalizedError {
    case alreadyNavigating
    case termsNotAccepted
    case navigatorUnavailable
    case invalidDestination
    case noRouteFound
    case networkError
    case quotaExceeded
    case apiKeyNotAuthorized
    case locationUnavailable
    case routeCalculationFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyNavigating:
            return "Navigation is already in progress"
        case .termsNotAccepted:
            return "Navigation terms not accepted"
        case .navigatorUnavailable:
            return "Navigation service unavailable"
        case .invalidDestination:
            return "Invalid destination"
        case .noRouteFound:
            return "No route found to destination"
        case .networkError:
            return "Network error while calculating route"
        case .quotaExceeded:
            return "API quota exceeded"
        case .apiKeyNotAuthorized:
            return "API key not authorized for navigation"
        case .locationUnavailable:
            return "Current location unavailable"
        case .routeCalculationFailed:
            return "Failed to calculate route"
        }
    }
}


