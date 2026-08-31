import SwiftUI

enum Brand {
    static let name = "Slate"
    static let symbol = "doc.text.fill"
}

enum Motion {
    static let snappy = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.9)
    static let pop = Animation.spring(response: 0.28, dampingFraction: 0.7)
}
