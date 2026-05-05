//
//  ScreenshotCategory.swift
//  ScreenShotAtoZ
//

import Foundation

enum ScreenshotCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    static let orderedForDisplay: [ScreenshotCategory] = [
        .today, .yesterday, .thisWeek, .thisMonth, .older,
    ]

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .older: "Older"
        }
    }
}
