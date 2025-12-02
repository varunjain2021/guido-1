//
//  HeatmapView.swift
//  guido-1
//
//  Created by GPT-5.1 Codex on 11/29/25.
//

import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct HeatmapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HeatmapViewModel()
    @State private var cameraPosition: MapCameraPosition = .region(HeatmapViewModel.defaultRegion())
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    filterSelector
                    Spacer()
                    legend
                }
                .padding()
                
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding()
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(radius: 10)
                }
            }
            .navigationTitle("Activity Heatmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.headline)
                }
            }
            .task {
                await viewModel.loadInitial()
                // Update camera to show fetched data
                cameraPosition = .region(viewModel.region)
                print("🗺️ [Heatmap] Initial load complete - \(viewModel.overlays.count) overlays, region: \(viewModel.region.center.latitude), \(viewModel.region.center.longitude)")
            }
            .onChange(of: viewModel.selectedRange) { _ in
                Task {
                    await viewModel.refresh()
                    cameraPosition = .region(viewModel.region)
                    print("🗺️ [Heatmap] Range changed - \(viewModel.overlays.count) overlays, region: \(viewModel.region.center.latitude), \(viewModel.region.center.longitude)")
                }
            }
        }
    }
    
    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.overlays) { overlay in
                let polygon = MKPolygon(coordinates: overlay.coordinates, count: overlay.coordinates.count)
                MapPolygon(polygon)
                    .stroke(.clear)
                    .foregroundStyle(fillColor(for: overlay.intensity))
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let latDelta = context.region.span.latitudeDelta
            viewModel.updateForZoom(latitudeDelta: latDelta)
        }
    }
    
    private var filterSelector: some View {
        HStack(spacing: 8) {
            ForEach(HeatmapRange.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        viewModel.selectedRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .foregroundColor(range == viewModel.selectedRange ? .black : .white)
                        .background(range == viewModel.selectedRange ? Color.white : Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private var legend: some View {
        HStack(spacing: 10) {
            Text("Passing through")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.4),
                    Color(red: 1.0, green: 0.6, blue: 0.2),
                    Color(red: 0.85, green: 0.1, blue: 0.1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .cornerRadius(4)
            Text("Frequent spot")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func fillColor(for intensity: Double) -> Color {
        let clamped = max(0, min(1, intensity))
        switch clamped {
        case 0..<0.33:
            return Color(red: 1.0, green: 0.9, blue: 0.4).opacity(0.4 + clamped * 0.4)
        case 0.33..<0.66:
            return Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.5 + clamped * 0.3)
        default:
            return Color(red: 0.85, green: 0.1, blue: 0.1).opacity(0.65 + clamped * 0.25)
        }
    }
}

