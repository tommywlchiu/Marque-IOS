import SwiftUI

struct PublicCarDetailView: View {
    let publicCar: PublicCar

    @EnvironmentObject var exploreStore: ExploreStore
    @EnvironmentObject var blockStore: BlockStore
    @State private var showingOwnerProfile = false
    @State private var showingReport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                photoHeader
                ownerRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
                specsSection
                serviceHistorySection
            }
        }
        .navigationTitle(publicCar.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingReport = true } label: {
                    Image(systemName: "flag")
                }
            }
        }
        .sheet(isPresented: $showingOwnerProfile) {
            NavigationStack {
                PublicProfileView(ownerUID: publicCar.ownerUID, ownerUsername: publicCar.ownerUsername)
                    .environmentObject(exploreStore)
                    .environmentObject(blockStore)
            }
        }
        .sheet(isPresented: $showingReport) {
            ReportView(title: "Report Car", reportedUID: publicCar.ownerUID, contentId: publicCar.carId)
                .environmentObject(blockStore)
        }
    }

    // MARK: - Photo Header

    private var photoHeader: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            if let url = publicCar.primaryPhotoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                            .offset(y: publicCar.photoOffsetY)
                    default:
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipped()
    }

    private var placeholderIcon: some View {
        Image(systemName: "car.fill")
            .font(.system(size: 72))
            .foregroundColor(.accentColor.opacity(0.3))
    }

    // MARK: - Owner Row

    private var ownerRow: some View {
        Button { showingOwnerProfile = true } label: {
            HStack(spacing: 10) {
                OwnerAvatar(avatarURL: publicCar.ownerAvatarURL, username: publicCar.ownerUsername, size: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(publicCar.ownerUsername)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Specs

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Specs")
                .font(.headline).fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ForEach(Array(publicCar.specRows.enumerated()), id: \.offset) { i, spec in
                HStack {
                    Text(spec.label).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(spec.value).font(.subheadline).fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if i < publicCar.specRows.count - 1 {
                    Divider().padding(.horizontal, 16)
                }
            }

            if !publicCar.notes.isEmpty {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(.subheadline).foregroundColor(.secondary)
                    Text(publicCar.notes).font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Service History (no costs)

    @ViewBuilder
    private var serviceHistorySection: some View {
        if !publicCar.serviceHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                HStack {
                    Text("Service History")
                        .font(.headline).fontWeight(.semibold)
                    Spacer()
                    Text("\(publicCar.serviceHistory.count) records")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ForEach(publicCar.serviceHistory.sorted { $0.date > $1.date }.prefix(5)) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.serviceType)
                                .font(.subheadline).fontWeight(.medium)
                            Text(record.date, style: .date)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .padding(.bottom, 24)
        }
    }
}

