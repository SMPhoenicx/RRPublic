//
//  Resume.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 11/5/25.
//
import SwiftUI
import FirebaseCore
import FirebaseFirestoreInternal
import FirebaseFirestore

struct Profile: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var bio: String?
    var homeClub: String?
    var createdAt: Date
    var updatedAt: Date?
    var profileImageURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bio
        case homeClub
        case createdAt
        case updatedAt
        case profileImageURL
    }
    
}

struct RegattaStructure: Codable, Identifiable {
    @DocumentID var id: String?
    var userID: String
    var date: Date?
    var boat: String?
    var regattaName: String?
    var place: Int?
    var placeAmount: Int?
    var fleetPlace: Int?
    var organizer: String?
    var coach: String?
    var resultsLink: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case date
        case boat
        case regattaName
        case place
        case placeAmount
        case fleetPlace
        case organizer
        case coach
        case resultsLink
    }
}

struct SailorStats {
    let userId: String
    let totalRegattas: Int
    let averagePlace: Double?
    let podiumFinishes: Int
    let topTenFinishes: Int
}
