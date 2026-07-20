//
//  Item.swift
//  Varq
//
//  Created by Pratik Rai on 21/07/26.
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
