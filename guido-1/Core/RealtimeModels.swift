//
//  RealtimeModels.swift
//  guido-1
//
//  Created by Varun Jain on 7/30/25.
//

import Foundation
import SwiftUI

// MARK: - Shared Realtime Message Model
struct RealtimeMessage: Identifiable, Codable, Equatable {
    let id = UUID()
    let role: String
    var content: String
    let timestamp: Date
    var isStreaming: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case role, content, timestamp, isStreaming
    }
    
    static func == (lhs: RealtimeMessage, rhs: RealtimeMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Shared Message Bubble Component
struct MessageBubble: View {
    let message: RealtimeMessage
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == "user" ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .cornerRadius(16)
                    .opacity(message.isStreaming ? 0.7 : 1.0)
                
                Text(SharedDateFormatter.timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == "assistant" {
                Spacer()
            }
        }
    }
}

// MARK: - Shared Date Formatter
struct SharedDateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}