//
//  WiFiMonitor.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 6/1/26.
//


import Network
import Foundation


final class WiFiMonitor {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "WiFiMonitorQueue")
    
    var onWiFiStatusChanged: ((Bool) -> Void)?
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let hasWiFi = (path.status == .satisfied)
            
            DispatchQueue.main.async {
                self?.onWiFiStatusChanged?(hasWiFi)
            }
        }
    }
    
    func start() {
        monitor.start(queue: queue)
    }
    
    func stop() {
        monitor.cancel()
    }
}
