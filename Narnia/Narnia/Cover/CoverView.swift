//
//  CoverView.swift
//  Narnia
//
//  The cover (disguise) UI: an ordinary wardrobe / outerwear app. This layer is
//  fully self-contained — it knows nothing about what lies beyond the wardrobe
//  and references no types outside this file. Its only link to the rest of the
//  app is the `onHiddenDoor` closure, which the root wires up.
//

import SwiftUI

// MARK: - Cover

/// The ordinary-looking wardrobe app shown on launch.
struct CoverView: View {
    /// Invoked when the user long-presses the hidden back-panel at the end of the
    /// Outerwear tab. The root wires this to biometric auth + session unlock.
    let onHiddenDoor: () -> Void

    init(onHiddenDoor: @escaping () -> Void) {
        self.onHiddenDoor = onHiddenDoor
    }

    var body: some View {
        TabView {
            OuterwearTab(onHiddenDoor: onHiddenDoor)
                .tabItem {
                    Label("Outerwear", systemImage: "jacket")
                }

            ClosetPlaceholderTab(
                title: "Tops",
                systemImage: "tshirt",
                items: OutfitItem.tops
            )
            .tabItem {
                Label("Tops", systemImage: "tshirt")
            }

            ClosetPlaceholderTab(
                title: "Shoes",
                systemImage: "shoe",
                items: OutfitItem.shoes
            )
            .tabItem {
                Label("Shoes", systemImage: "shoe")
            }
        }
    }
}

// MARK: - Outerwear Tab

/// The Outerwear tab. A plain list of coats and jackets that ends, unremarkably,
/// with the back wall of the wardrobe.
private struct OuterwearTab: View {
    let onHiddenDoor: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(OutfitItem.outerwear) { item in
                        OutfitRow(item: item)
                    }
                }

                // The back of the wardrobe. Looks like the end of the closet.
                Section {
                    WardrobeBackPanel(onLongPress: onHiddenDoor)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Outerwear")
        }
    }
}

// MARK: - Placeholder Tab

/// A simple list-backed tab used for the other wardrobe sections.
private struct ClosetPlaceholderTab: View {
    let title: String
    let systemImage: String
    let items: [OutfitItem]

    var body: some View {
        NavigationStack {
            List(items) { item in
                OutfitRow(item: item)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
        }
    }
}

// MARK: - Rows

/// A single garment row.
private struct OutfitRow: View {
    let item: OutfitItem

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.swatch.gradient)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.white.opacity(0.85))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Wardrobe Back Panel

/// The wooden back wall of the wardrobe, rendered at the end of the Outerwear
/// list. Visually it reads as a piece of furniture — the back of a closet — so
/// it draws no attention. The long-press is the sole trigger handed up to the
/// root via the closure.
private struct WardrobeBackPanel: View {
    let onLongPress: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(woodGrain)
            .frame(height: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.black.opacity(0.18), lineWidth: 1)
            )
            .overlay(plankSeams)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onLongPressGesture(minimumDuration: 0.6) {
                onLongPress()
            }
            .accessibilityIdentifier("coverBackPanel")
    }

    /// A warm brown gradient evoking a stained-wood panel.
    private var woodGrain: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.45, green: 0.31, blue: 0.18),
                Color(red: 0.36, green: 0.24, blue: 0.13),
                Color(red: 0.41, green: 0.28, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Faint vertical seams suggesting wooden planks.
    private var plankSeams: some View {
        GeometryReader { proxy in
            let count = 4
            let spacing = proxy.size.width / CGFloat(count)
            Path { path in
                for index in 1..<count {
                    let x = spacing * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: 6))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height - 6))
                }
            }
            .stroke(.black.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - Placeholder Data

/// A plain garment shown in the cover lists. Local to the cover; carries no
/// meaning beyond the disguise.
private struct OutfitItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let symbol: String
    let swatch: Color
}

extension OutfitItem {
    static let outerwear: [OutfitItem] = [
        OutfitItem(name: "Wool Coat", detail: "Charcoal · Size M", symbol: "jacket", swatch: Color(red: 0.30, green: 0.32, blue: 0.36)),
        OutfitItem(name: "Rain Jacket", detail: "Forest green · Size L", symbol: "cloud.rain", swatch: Color(red: 0.18, green: 0.36, blue: 0.26)),
        OutfitItem(name: "Parka", detail: "Navy · Size M", symbol: "snowflake", swatch: Color(red: 0.16, green: 0.22, blue: 0.38)),
        OutfitItem(name: "Windbreaker", detail: "Slate blue · Size S", symbol: "wind", swatch: Color(red: 0.24, green: 0.40, blue: 0.52)),
        OutfitItem(name: "Denim Jacket", detail: "Washed indigo · Size M", symbol: "jacket", swatch: Color(red: 0.27, green: 0.34, blue: 0.49))
    ]

    static let tops: [OutfitItem] = [
        OutfitItem(name: "Cotton Tee", detail: "White · Size M", symbol: "tshirt", swatch: Color(red: 0.62, green: 0.64, blue: 0.66)),
        OutfitItem(name: "Flannel Shirt", detail: "Red plaid · Size L", symbol: "tshirt", swatch: Color(red: 0.55, green: 0.20, blue: 0.20)),
        OutfitItem(name: "Knit Sweater", detail: "Oatmeal · Size M", symbol: "tshirt", swatch: Color(red: 0.66, green: 0.58, blue: 0.46))
    ]

    static let shoes: [OutfitItem] = [
        OutfitItem(name: "Leather Boots", detail: "Brown · Size 42", symbol: "shoe", swatch: Color(red: 0.40, green: 0.26, blue: 0.16)),
        OutfitItem(name: "Running Shoes", detail: "Grey · Size 42", symbol: "shoe", swatch: Color(red: 0.45, green: 0.47, blue: 0.50)),
        OutfitItem(name: "Canvas Sneakers", detail: "White · Size 42", symbol: "shoe", swatch: Color(red: 0.70, green: 0.71, blue: 0.72))
    ]
}

// MARK: - Preview

#Preview {
    CoverView(onHiddenDoor: {})
}
