//
//  ElevenLabsService.swift
//  guido-1
//
//  Created by Varun Jain on 7/27/25.
//

import Foundation

class ElevenLabsService {
    private let apiKey: String
    private let session = URLSession.shared

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Text to Speech

    func textToSpeech(text: String, voiceID: String = "JBFqnCBsd6RMkjVDRZzb") async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🔊 Requesting TTS with mp3_22050_32 format...")

        let requestBody: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "output_format": "mp3_22050_32",
            "voice_settings": [
                "stability": 0.4,
                "similarity_boost": 0.8,
                "style": 0.2,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid TTS response"])
        }
        
        print("🌐 ElevenLabs TTS response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ ElevenLabs TTS error: \(errorBody)")
            throw NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to convert text to speech. Status: \(httpResponse.statusCode), Response: \(errorBody)"])
        }

        print("✅ ElevenLabs TTS success: \(data.count) bytes received")
        return data
    }

    // MARK: - Speech to Text

    func speechToText(audioData: Data) async throws -> String {
        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        
        // Add audio file data - using WAV format for PCM16 data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        // Create WAV header for PCM16 data at 24kHz mono
        let wavData = createWAVData(from: audioData)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("scribe_v1".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        
        print("🌐 Sending \(wavData.count) bytes of WAV data to ElevenLabs STT")
        
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        print("🌐 ElevenLabs STT response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ ElevenLabs STT error: \(errorBody)")
            throw NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to convert speech to text. Status: \(httpResponse.statusCode), Response: \(errorBody)"])
        }

        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        print("✅ ElevenLabs STT success: \(transcriptionResponse.text)")
        return transcriptionResponse.text
    }
    
    // MARK: - Helper Methods
    
    private func createWAVData(from pcmData: Data) -> Data {
        var wavData = Data()
        
        // WAV header for PCM16, 48kHz, mono (matching iOS native recording rate)
        let sampleRate: UInt32 = 48000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })  // PCM format
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(pcmData)
        
        print("🎵 Created WAV file: \(wavData.count) bytes (header: 44 bytes, data: \(pcmData.count) bytes, 48kHz PCM16)")
        return wavData
    }
}

// MARK: - Data Models
// TranscriptionResponse is defined in OpenAIChatService.swift 