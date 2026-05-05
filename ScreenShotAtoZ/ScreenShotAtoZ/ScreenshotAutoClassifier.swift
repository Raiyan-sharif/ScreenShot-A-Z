//
//  ScreenshotAutoClassifier.swift
//  ScreenShotAtoZ
//

import Foundation
import Photos

enum ScreenshotAutoClassifier {
    static func autoCategory(for asset: PHAsset, relativeTo now: Date = Date()) -> ScreenshotCategory {
        guard let date = asset.creationDate else { return .older }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let wNow = cal.component(.weekOfYear, from: now)
        let yNow = cal.component(.yearForWeekOfYear, from: now)
        let wDate = cal.component(.weekOfYear, from: date)
        let yDate = cal.component(.yearForWeekOfYear, from: date)
        if wDate == wNow, yDate == yNow { return .thisWeek }
        let monthComponents = cal.dateComponents([.year, .month], from: now)
        let assetComponents = cal.dateComponents([.year, .month], from: date)
        if monthComponents.year == assetComponents.year, monthComponents.month == assetComponents.month {
            return .thisMonth
        }
        return .older
    }
}
