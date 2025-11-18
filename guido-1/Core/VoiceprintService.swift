//
//  VoiceprintService.swift
//  guido-1
//

import Foundation
import Accelerate

struct VoiceprintMetadata: Codable, Equatable {
    let version: String
    let sampleRate: Double
    let frameSize: Int
    let hopSize: Int
    let fftSize: Int
}

struct VoiceprintPayload: Codable, Equatable {
    let vector: [Double]
    let metadata: VoiceprintMetadata
    let createdAt: Date
}

struct VoiceprintQuietResult {
    let rms: Double
    let decibels: Double
    let isAcceptable: Bool
}

struct SpeechQualityResult {
    let duration: Double
    let rms: Double
    let voicedFraction: Double
    let isAcceptable: Bool
    let reason: String?
}

@MainActor
final class VoiceprintService: ObservableObject {
    static let shared = VoiceprintService()
    
    private let quietThresholdDB: Double = -42.0
    private let phraseDuration: TimeInterval = 3.0
    private let quietSampleDuration: TimeInterval = 2.0
    private let frameSize = 512
    private let hopSize = 256
    private var lastQuietRMS: Double?
    
    private init() {}
    
    func performQuietCheck() async -> VoiceprintQuietResult {
        print("[Voiceprint] 🔈 Quiet check starting…")
        let snippet = await AudioSnippets.recordMonoFloat32(seconds: quietSampleDuration)
        let result = evaluateQuiet(snippet: snippet)
        lastQuietRMS = result.rms
        print("[Voiceprint] 🔈 Quiet check: \(snippet.samples.count) samples @ \(Int(snippet.sampleRate)) Hz, \(String(format: "%.1f", result.decibels)) dB → \(result.isAcceptable ? "ACCEPTABLE" : "TOO NOISY")")
        return result
    }
    
    func recordPhrase() async -> AudioSnippet {
        print("[Voiceprint] 🎤 Starting phrase recording (~\(String(format: "%.1f", phraseDuration))s)…")
        let snippet = await AudioSnippets.recordMonoFloat32(seconds: phraseDuration)
        print("[Voiceprint] 🎤 Finished phrase recording: \(snippet.samples.count) samples")
        return snippet
    }
    
    func evaluateQuiet(snippet: AudioSnippet) -> VoiceprintQuietResult {
        let rmsValue = rootMeanSquare(samples: snippet.samples)
        let db = 20 * log10(max(rmsValue, 1e-7))
        return VoiceprintQuietResult(rms: rmsValue, decibels: db, isAcceptable: db <= quietThresholdDB)
    }
    
    func buildVoiceprint(from snippets: [AudioSnippet]) -> VoiceprintPayload? {
        guard let first = snippets.first, !first.samples.isEmpty else { return nil }
        var aggregate = [Float](repeating: 0, count: frameSize / 2)
        var contributions = 0
        
        for snippet in snippets where !snippet.samples.isEmpty {
            let vector = averagedSpectrum(from: snippet.samples)
            if vector.isEmpty { continue }
            vDSP_vadd(aggregate, 1, vector, 1, &aggregate, 1, vDSP_Length(vector.count))
            contributions += 1
        }
        
        guard contributions > 0 else { return nil }
        
        var scalar = 1.0 / Float(contributions)
        vDSP_vsmul(aggregate, 1, &scalar, &aggregate, 1, vDSP_Length(aggregate.count))
        
        let metadata = VoiceprintMetadata(
            version: "fft512_v1",
            sampleRate: first.sampleRate,
            frameSize: frameSize,
            hopSize: hopSize,
            fftSize: frameSize
        )
        let vector = aggregate.map { Double($0) }
        return VoiceprintPayload(vector: vector, metadata: metadata, createdAt: Date())
    }
    
    // MARK: - Speech quality check for enrollment
    func evaluateSpeechQuality(snippet: AudioSnippet) -> SpeechQualityResult {
        let samples = snippet.samples
        let sr = snippet.sampleRate
        guard !samples.isEmpty, sr > 0 else {
            return SpeechQualityResult(duration: 0, rms: 0, voicedFraction: 0, isAcceptable: false, reason: "No audio captured")
        }
        let duration = Double(samples.count) / sr
        let overallRMS = rootMeanSquare(samples: samples)
        
        var voicedFrames = 0
        var totalFrames = 0
        var maxFrame: Float = 0
        var idx = 0
        // Dynamic threshold based on overall energy; enforce a sensible floor
        // Also adapt relative to quiet baseline if available
        let quietComponent = Float((lastQuietRMS ?? 0) * 3.0)
        let baseThreshold: Float = max(0.01, Float(overallRMS) * 0.5, quietComponent)
        while idx + frameSize <= samples.count {
            let frame = Array(samples[idx ..< idx + frameSize])
            let frm = frameRMS(frame)
            if frm > baseThreshold {
                voicedFrames += 1
            }
            if frm > maxFrame { maxFrame = frm }
            totalFrames += 1
            idx += hopSize
        }
        let vf = totalFrames > 0 ? Double(voicedFrames) / Double(totalFrames) : 0
        
        // Heuristics: require at least ~1.2s with >=30% voiced frames
        let minDuration = 1.2
        let minVoicedFraction = 0.30
        var ok = (duration >= minDuration) && (vf >= minVoicedFraction)
        // Allow strong peaks to pass even if voiced fraction is slightly low
        if !ok && vf >= 0.25 && maxFrame >= 0.05 {
            ok = true
        }
        print(String(format: "[Voiceprint] 🧪 Speech quality — dur: %.2fs, overallRMS: %.4f, threshold: %.4f, voiced: %.0f/%d (%.0f%%), maxFrame: %.4f → %@",
                     duration, overallRMS, baseThreshold, Double(voicedFrames), totalFrames, vf * 100, maxFrame, ok ? "OK" : "RETRY"))
        let reason = ok ? nil : "We didn’t catch enough of your voice. Try speaking a bit closer or louder."
        return SpeechQualityResult(duration: duration, rms: overallRMS, voicedFraction: vf, isAcceptable: ok, reason: reason)
    }
    
    // MARK: - DSP Helpers
    private func rootMeanSquare(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var value: Float = 0
        vDSP_measqv(samples, 1, &value, vDSP_Length(samples.count))
        return Double(sqrt(value))
    }
    
    private func frameRMS(_ frame: [Float]) -> Float {
        var value: Float = 0
        vDSP_measqv(frame, 1, &value, vDSP_Length(frame.count))
        return sqrtf(value)
    }
    
    private func averagedSpectrum(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var accumulator = [Float](repeating: 0, count: frameSize / 2)
        var frameCount = 0
        
        var index = 0
        while index + frameSize <= samples.count {
            let frame = Array(samples[index ..< index + frameSize])
            var spectrum = magnitudeSpectrum(frame)
            if !spectrum.isEmpty {
                vDSP_vadd(accumulator, 1, spectrum, 1, &accumulator, 1, vDSP_Length(spectrum.count))
                frameCount += 1
            }
            index += hopSize
        }
        
        guard frameCount > 0 else { return [] }
        var scalar = 1.0 / Float(frameCount)
        vDSP_vsmul(accumulator, 1, &scalar, &accumulator, 1, vDSP_Length(accumulator.count))
        return accumulator
    }
    
    private func magnitudeSpectrum(_ samples: [Float]) -> [Float] {
        guard samples.count == frameSize else { return [] }
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: frameSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))
        
        var real = [Float](repeating: 0, count: frameSize / 2)
        var imag = [Float](repeating: 0, count: frameSize / 2)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        windowed.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: frameSize / 2) { complex in
                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(frameSize / 2))
            }
        }
        
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(frameSize))), FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }
        
        vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Float(frameSize))), FFTDirection(FFT_FORWARD))
        var magnitudes = [Float](repeating: 0, count: frameSize / 2)
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(frameSize / 2))
        return magnitudes
    }
}

