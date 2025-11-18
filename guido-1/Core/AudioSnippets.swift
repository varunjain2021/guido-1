//
//  AudioSnippets.swift
//  guido-1
//
//  Minimal helper to capture brief mono Float32 snippets without UI.
//

import Foundation
import AVFoundation

struct AudioSnippet {
    let samples: [Float]
    let sampleRate: Double
}

enum AudioSnippets {
    static func recordMonoFloat32(seconds: TimeInterval, sampleRate: Double = 16000) async -> AudioSnippet {
        let session = AVAudioSession.sharedInstance()
        let permString: String = {
            switch session.recordPermission {
            case .granted: return "granted"
            case .denied: return "denied"
            case .undetermined: return "undetermined"
            @unknown default: return "unknown"
            }
        }()
        print("[VoiceprintAudio] 🎙️ Starting capture for \(String(format: "%.1f", seconds))s (permission: \(permString))")
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Use hardware/output format to avoid tap format mismatch; downmix to mono by reading channel 0
        let format = input.outputFormat(forBus: 0)
        print("[VoiceprintAudio] ⚙️ Input format: \(format.sampleRate) Hz, \(format.channelCount) ch")
        
        var samples: [Float] = []
        var bufferCount: Int = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let ch = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
            bufferCount += 1
            if bufferCount == 1 || bufferCount % 20 == 0 {
                print("[VoiceprintAudio] 🎧 Tap buffers: \(bufferCount), last \(count) frames, total \(samples.count)")
            }
        }
        
        do {
            // Leverage existing session config from the app; avoid flipping categories here.
            try engine.start()
            print("[VoiceprintAudio] ✅ Engine started")
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            print("[VoiceprintAudio] ❌ Engine start/record failed: \(error.localizedDescription)")
            return AudioSnippet(samples: [], sampleRate: format.sampleRate)
        }
        
        input.removeTap(onBus: 0)
        engine.stop()
        
        if samples.isEmpty {
            print("[VoiceprintAudio] ⚠️ No samples captured")
        } else {
            // Quick RMS/DB snapshot for debugging
            var sumSq: Double = 0
            for s in samples { sumSq += Double(s) * Double(s) }
            let rms = samples.isEmpty ? 0 : sqrt(sumSq / Double(samples.count))
            let db = 20 * log10(max(rms, 1e-12))
            let duration = Double(samples.count) / format.sampleRate
            print("[VoiceprintAudio] 📦 Captured \(samples.count) samples (~\(String(format: "%.2f", duration))s @ \(Int(format.sampleRate)) Hz), RMS \(String(format: "%.4f", rms)) (\(String(format: "%.1f", db)) dB)")
        }
        
        return AudioSnippet(samples: samples, sampleRate: format.sampleRate)
    }
}


