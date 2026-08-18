import Foundation
import SwiftUI

/// Kind of memory occupied by one segment of the RAM breakdown bar (DW-3).
public enum MemorySegmentKind: Sendable {
    case app
    case cache
    case wired
    case compressed
}

/// One proportional segment of the memory bar.
public struct MemorySegment: Identifiable, Sendable {
    public let id: UUID
    public let kind: MemorySegmentKind
    public let bytes: UInt64

    public init(kind: MemorySegmentKind, bytes: UInt64) {
        self.id = UUID()
        self.kind = kind
        self.bytes = bytes
    }
}

/// Width fraction per segment (0...1). A zero total produces all-zero
/// fractions instead of dividing by zero (DW-3).
func memoryFractions(_ segments: [MemorySegment]) -> [Double] {
    let total = segments.reduce(UInt64(0)) { $0 + $1.bytes }
    guard total > 0 else { return segments.map { _ in 0 } }
    return segments.map { Double($0.bytes) / Double(total) }
}

/// Token color per segment kind (DW-6: AGColors only).
func memorySegmentColor(_ kind: MemorySegmentKind) -> Color {
    switch kind {
    case .app:
        return AGColors.accent
    case .cache:
        return AGColors.statusLive
    case .wired:
        return AGColors.statusPlaceholder
    case .compressed:
        return AGColors.statusDisabled
    }
}

/// Stacked RAM breakdown bar (app/cache/wired/compressed), spec DW-3.
/// Renders a full-width idle bar when there are no segments.
public struct AGMemoryBar: View {
    public let segments: [MemorySegment]
    public let tint: Color?

    public init(segments: [MemorySegment], tint: Color? = nil) {
        self.segments = segments
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let spacing = AGSpacing.xxSmall
            let count = segments.isEmpty ? 1 : segments.count
            let totalWidth = proxy.size.width - spacing * CGFloat(count - 1)
            let fractions = memoryFractions(segments)
            HStack(spacing: spacing) {
                if segments.isEmpty {
                    Capsule()
                        .fill(tint ?? AGColors.statusDisabled)
                        .frame(width: totalWidth)
                } else {
                    ForEach(Array(zip(segments, fractions)), id: \.0.id) { segment, fraction in
                        Capsule()
                            .fill(tint ?? memorySegmentColor(segment.kind))
                            .frame(width: totalWidth * fraction)
                    }
                }
            }
        }
        .frame(height: AGSpacing.small)
    }
}
