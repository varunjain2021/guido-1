//
//  SimpleSpeakerVerifier.swift
//  guido-1
//
//  Lightweight, in-memory speaker fingerprint for quick evaluation.
//

import Foundation
import Accelerate

struct SimpleSpeakerVerifier {
	private(set) var enrolled: [Float] = []
	
	mutating func enroll(from samples: [Float]) {
		enrolled = normalize(fingerprint(samples))
	}

	mutating func applyStoredVoiceprint(vector: [Double]) {
		enrolled = vector.map { Float($0) }
	}

	func exportVoiceprint() -> [Double]? {
		return enrolled.isEmpty ? nil : enrolled.map { Double($0) }
	}

	
	func isLikelySameSpeaker(samples: [Float], threshold: Float = 0.80) -> Bool {
		guard !enrolled.isEmpty else { return true } // pass-through if not enrolled
		let sim = similarity(samples: samples)
		return sim >= threshold
	}
	
	/// Returns cosine similarity between the enrolled fingerprint and the sample's fingerprint.
	func similarity(samples: [Float]) -> Float {
		guard !enrolled.isEmpty else { return 1.0 }
		let fp = normalize(fingerprint(samples))
		return cosine(enrolled, fp)
	}
	
	// MARK: - Fingerprint: averaged magnitude spectrum across short overlapping frames
	private func fingerprint(_ samples: [Float]) -> [Float] {
		guard !samples.isEmpty else { return [] }
		
		let frame = 512
		let hop = 256
		
		var idx = 0
		var accum: [Float] = []
		var nFrames = 0
		
		while idx + frame <= samples.count {
			let slice = Array(samples[idx ..< idx + frame])
			let mag = magnitudeSpectrum(slice)
			if accum.isEmpty {
				accum = mag
			} else {
				vDSP_vadd(accum, 1, mag, 1, &accum, 1, vDSP_Length(mag.count))
			}
			nFrames += 1
			idx += hop
		}
		
		guard nFrames > 0 else { return [] }
		var avg = accum
		var denom = Float(nFrames)
		vDSP_vsdiv(avg, 1, &denom, &avg, 1, vDSP_Length(avg.count))
		return avg
	}
	
	private func magnitudeSpectrum(_ x: [Float]) -> [Float] {
		let n = x.count
		guard n > 1, (n & (n - 1)) == 0 else { return [] } // power of two
		
		// Hann window
		var window = [Float](repeating: 0, count: n)
		vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
		var win = [Float](repeating: 0, count: n)
		vDSP_vmul(x, 1, window, 1, &win, 1, vDSP_Length(n))
		
		// Split-complex for real FFT
		let halfN = n / 2
		var real = [Float](repeating: 0, count: halfN)
		var imag = [Float](repeating: 0, count: halfN)
		var split = DSPSplitComplex(realp: &real, imagp: &imag)
		
		// Pack real input into split-complex (even -> real, odd -> imag)
		win.withUnsafeBufferPointer { ptr in
			ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
				vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
			}
		}
		
		let log2n = vDSP_Length(log2(Float(n)))
		guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
		defer { vDSP_destroy_fftsetup(setup) }
		
		vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
		
		// Magnitude for bins 0..(N/2-1)
		var mag = [Float](repeating: 0, count: halfN)
		vDSP_zvabs(&split, 1, &mag, 1, vDSP_Length(halfN))
		return mag
	}
	
	private func normalize(_ v: [Float]) -> [Float] {
		guard !v.isEmpty else { return v }
		var out = v
		var maxVal: Float = 1e-6
		vDSP_maxv(out, 1, &maxVal, vDSP_Length(out.count))
		var inv = 1.0 / max(maxVal, 1e-6)
		vDSP_vsmul(out, 1, &inv, &out, 1, vDSP_Length(out.count))
		return out
	}
	
	private func cosine(_ a: [Float], _ b: [Float]) -> Float {
		guard a.count == b.count, !a.isEmpty else { return 0 }
		var dot: Float = 0
		vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
		var na: Float = 0, nb: Float = 0
		vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
		vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
		return dot / (sqrt(max(na, 1e-6)) * sqrt(max(nb, 1e-6)))
	}
}


