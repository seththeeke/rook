import RookFeatures
import RookModels
import SwiftUI

/// Simplified profile: name, @username, and Member since.
struct ProfileView: View {
    let profile: UserProfile

    var body: some View {
        let summary = ProfileSummary(profile: profile)
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                VStack(spacing: Theme.Spacing.s) {
                    AvatarView(initials: summary.initials, photoURL: profile.profilePhoto, size: 96)
                        .overlay(Circle().strokeBorder(Theme.primary.opacity(0.6), lineWidth: 2))
                    Text(summary.displayName)
                        .font(.title.bold())
                        .accessibilityIdentifier("profile.name")
                    Text(summary.handle)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryLight)
                        .accessibilityIdentifier("profile.username")
                }
                .padding(.top, Theme.Spacing.l)

                if let memberSince = summary.memberSince {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(Theme.primaryLight)
                            .frame(width: 44, height: 44)
                            .background(Theme.primary.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Member since")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Text(memberSince)
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .rookCard()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profile.memberSince")
                }
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("profile.settings")
            }
        }
    }
}

/// Circular avatar: remote photo when available, otherwise initials on the brand color.
struct AvatarView: View {
    let initials: String
    var photoURL: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        ZStack {
            Theme.surfaceElevated
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .overlay(Circle().strokeBorder(Theme.border))
    }
}
