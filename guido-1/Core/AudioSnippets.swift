//
//  AudioSnippets.swift
//  guido-1
//
//  Minimal helper to capture brief mono Float32 snippets without UI.
//

import Foundation
import AVFoundation

enum AudioSnippets {
	static func recordMonoFloat32(seconds: TimeInterval, sampleRate: Double = 16000) async -> [Float] {
		let engine = AVAudioEngine()
		let input = engine.inputNode
		// Use hardware/output format to avoid tap format mismatch; downmix to mono by reading channel 0
		let format = input.outputFormat(forBus: 0)
		
		var samples: [Float] = []
		input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
			guard let ch = buffer.floatChannelData else { return }
			let count = Int(buffer.frameLength)
			samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
		}
		
		do {
			// Leverage existing session config from the app; avoid flipping categories here.
			try engine.start()
			try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
		} catch {
			input.removeTap(onBus: 0)
			engine.stop()
			return []
		}
		
		input.removeTap(onBus: 0)
		engine.stop()
		return samples
	}
}


