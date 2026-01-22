//
//  Item.swift
//  beemed
//
//  Created by Daniel Mackinlay on 22/1/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
