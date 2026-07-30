import SwiftUI

/// Obsidian's faceted-gem mark, drawn as vector paths rather than a bitmap so it
/// stays crisp at any tile size and needs no asset catalog entry.
///
/// Like the Gmail and Calendar tiles this is a **styled placeholder** in the
/// shape and colors of the real mark. Obsidian's actual logo is a trademark;
/// before shipping, download the official asset from obsidian.md's brand page,
/// drop it into `Assets.xcassets`, and swap the body for an `Image("obsidian")`.
struct ObsidianMark: View {
    /// The three facets, in a 100×100 design space. Together they tile the whole
    /// silhouette, so the gem reads as one solid shape with a lit left face.
    private static let leftFacet: [CGPoint] = [
        CGPoint(x: 38, y: 2), CGPoint(x: 46, y: 44),
        CGPoint(x: 56, y: 98), CGPoint(x: 22, y: 82), CGPoint(x: 14, y: 38)
    ]
    private static let topFacet: [CGPoint] = [
        CGPoint(x: 38, y: 2), CGPoint(x: 76, y: 20),
        CGPoint(x: 86, y: 52), CGPoint(x: 46, y: 44)
    ]
    private static let rightFacet: [CGPoint] = [
        CGPoint(x: 46, y: 44), CGPoint(x: 86, y: 52), CGPoint(x: 56, y: 98)
    ]

    static let purple = Color(red: 0.48, green: 0.24, blue: 0.89)
    private static let highlight = Color(red: 0.68, green: 0.50, blue: 0.99)
    private static let shadow = Color(red: 0.29, green: 0.11, blue: 0.62)

    var body: some View {
        ZStack {
            Facet(points: Self.leftFacet)
                .fill(LinearGradient(colors: [Self.highlight, Self.purple],
                                     startPoint: .top, endPoint: .bottom))
            Facet(points: Self.topFacet)
                .fill(LinearGradient(colors: [Self.purple, Self.shadow],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Facet(points: Self.rightFacet)
                .fill(Self.shadow)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// One polygon of the gem, mapped from the 100×100 design space onto whatever
/// rect it's given.
private struct Facet: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        let scaleX = rect.width / 100, scaleY = rect.height / 100
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * scaleX, y: rect.minY + point.y * scaleY)
        }
        path.move(to: place(first))
        for point in points.dropFirst() { path.addLine(to: place(point)) }
        path.closeSubpath()
        return path
    }
}

/// Obsidian's tile for the Connections list, matching `ServiceIcon`'s geometry so
/// the rows line up.
struct ObsidianIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(ObsidianMark.purple.opacity(0.15))
            .frame(width: 38, height: 38)
            .overlay(ObsidianMark().frame(width: 21, height: 21))
    }
}

#Preview {
    HStack(spacing: 20) {
        ObsidianIcon()
        ObsidianMark().frame(width: 64, height: 64)
    }
    .padding()
}
