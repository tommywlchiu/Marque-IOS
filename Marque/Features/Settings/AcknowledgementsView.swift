import SwiftUI

/// Credits for the 3D car models behind the Garage's studio renders. They're
/// Creative Commons Attribution, which requires naming each author, the
/// license and the source — read from the same `catalog.json` that decides
/// which cars have renders, so a car can never ship without its credit.
struct AcknowledgementsView: View {
    @State private var credits: [CarRenderLibrary.Credit] = CarRenderLibrary.cachedCatalog()?.credits ?? []

    var body: some View {
        List {
            Section {
                Text("Car images in the Garage are rendered from these 3D models. Each is used under its Creative Commons license; the renders are repainted and relit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(header: Text("3D Car Models")) {
                if credits.isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                ForEach(credits) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        if let url = URL(string: credit.url) {
                            Link(credit.title, destination: url)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("by \(credit.author)")
                            .font(.footnote)
                        if let license = URL(string: credit.licenseURL) {
                            Link(credit.license, destination: license)
                                .font(.caption)
                        } else {
                            Text(credit.license).font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let catalog = await CarRenderLibrary.catalog() { credits = catalog.credits }
        }
    }
}
