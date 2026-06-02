//
//  SupabaseManager.swift
//  RegattaResults
//

import Foundation
import Supabase


private enum PGDate {
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let pgSpaceFrac: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        return f
    }()
    static let pgSpace: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return f
    }()
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

private let supabaseDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)

        if let date = PGDate.isoFrac.date(from: s)
            ?? PGDate.isoPlain.date(from: s)
            ?? PGDate.pgSpaceFrac.date(from: s)
            ?? PGDate.pgSpace.date(from: s)
            ?? PGDate.dateOnly.date(from: s) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date format: \(s)"
        )
    }
    return d
}()

// MARK: - Client

let supabase = SupabaseClient(
    supabaseURL: URL(string: "")!,
    supabaseKey: "",
    options: SupabaseClientOptions(
        db: .init(decoder: supabaseDecoder),
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)
