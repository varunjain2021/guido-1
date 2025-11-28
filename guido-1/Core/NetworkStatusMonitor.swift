//
//  NetworkStatusMonitor.swift
//  guido-1
//
//  Lightweight monitor that exposes the current connection type for logging.
//

import Foundation
import Network

final class NetworkStatusMonitor {
    static let shared = NetworkStatusMonitor()
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.guido.network.monitor")
    private var currentType: String = "unknown"
    
    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status != .satisfied {
                currentType = "offline"
            } else if path.usesInterfaceType(.wifi) {
                currentType = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                currentType = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                currentType = "ethernet"
            } else if path.usesInterfaceType(.other) {
                currentType = "other"
            } else {
                currentType = "unknown"
            }
        }
        monitor.start(queue: queue)
    }
    
    func connectionType() -> String {
        currentType
    }
}

