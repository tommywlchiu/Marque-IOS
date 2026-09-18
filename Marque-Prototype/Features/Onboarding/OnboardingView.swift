import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authService: AuthService
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "car.2.fill",
            accentColor: .blue,
            title: "Your Cars, Organized",
            subtitle: "Track every car you own. VIN decode, insurance, registration, and maintenance — all in one place."
        ),
        OnboardingPage(
            icon: "wrench.and.screwdriver.fill",
            accentColor: .orange,
            title: "Never Miss a Service",
            subtitle: "Log maintenance records and get notified before insurance or registration expires."
        ),
        OnboardingPage(
            icon: "person.2.fill",
            accentColor: .purple,
            title: "Connect With Car Fans",
            subtitle: "Share your builds, discover enthusiasts nearby, and follow the cars you love."
        ),
    ]

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            bottomControls
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            AnalyticsService.onboardingStepViewed(step: .valueFraming)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            pageIndicator

            MarquePrimaryButton(isLastPage ? "Get Started" : "Continue") {
                if isLastPage {
                    authService.completeOnboarding()
                } else {
                    withAnimation { currentPage += 1 }
                }
            }

            if isLastPage {
                Button("I already have an account") {
                    authService.completeOnboarding()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            } else {
                Button("Skip") {
                    authService.completeOnboarding()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
        .padding(.top, 8)
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color(.systemGray4))
                    .frame(width: index == currentPage ? 22 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: currentPage)
            }
        }
    }
}

// MARK: - Page Data

private struct OnboardingPage {
    let icon: String
    let accentColor: Color
    let title: String
    let subtitle: String
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.accentColor.opacity(0.12))
                    .frame(width: 180, height: 180)
                Image(systemName: page.icon)
                    .font(.system(size: 80))
                    .foregroundStyle(page.accentColor)
            }

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.largeTitle).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
