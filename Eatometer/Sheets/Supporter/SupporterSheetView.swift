import StoreKit
import SwiftUI

struct SupporterSheetView: View {
    @EnvironmentObject private var supporterService: SupporterService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            pageBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    heroHeader

                    if supporterService.isLoadingProducts && supporterService.products.isEmpty {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else if supporterService.products.isEmpty {
                        emptyStateView
                    } else {
                        tiersList
                    }

                    if let activeTier = supporterService.activeTier {
                        activeStatusCard(tier: activeTier)
                    }

                    helperButtons

                    if let error = supporterService.lastErrorMessage, !error.isEmpty, !supporterService.products.isEmpty {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(Text(NSLocalizedString("supporter.title", comment: "Support the project")))
        .navigationBarTitleDisplayMode(.inline)
        .platformToolbarBackgroundVisibleForNavigationBar()
        .platformToolbarBackgroundColorForNavigationBar(pageBackground)
        .task {
            if supporterService.products.isEmpty {
                await supporterService.loadProducts()
            }
            await supporterService.refreshEntitlements(reportToBackend: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await supporterService.refreshEntitlements(reportToBackend: true)
            }
        }
    }

    // MARK: - Sections

    private var heroHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.pink)

            Text(NSLocalizedString("supporter.hero.title", comment: "Support Eatometer"))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("supporter.hero.subtitle", comment: "Help us keep developing the app. Cancel anytime."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private var tiersList: some View {
        VStack(spacing: 12) {
            ForEach(supporterService.products, id: \.id) { product in
                tierCard(for: product)
            }
        }
    }

    private func tierCard(for product: Product) -> some View {
        let isActive = supporterService.purchasedProductIDs.contains(product.id)
        let tier = SupporterService.tier(for: product.id)
        return Button {
            Task { await supporterService.purchase(product) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isActive ? "checkmark.seal.fill" : "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isActive ? .green : .pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName.isEmpty ? (tier?.fallbackTitle ?? product.id) : product.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("supporter.per_month", comment: "/month"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(supporterService.purchaseInProgress)
    }

    private func activeStatusCard(tier: SupporterService.Tier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text(NSLocalizedString("supporter.active.title", comment: "Active subscription"))
                    .font(.subheadline.weight(.semibold))
            }
            Text(tier.fallbackTitle)
                .font(.body)
                .foregroundStyle(.primary)
            if let expires = supporterService.activeExpiresAt {
                Text(String(
                    format: NSLocalizedString("supporter.renews_on %@", comment: "Renews on"),
                    expires.formatted(date: .long, time: .omitted)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var helperButtons: some View {
        VStack(spacing: 8) {
            Button {
                Task { await supporterService.restorePurchases() }
            } label: {
                Text(NSLocalizedString("supporter.restore", comment: "Restore purchases"))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .disabled(supporterService.purchaseInProgress)

            if supporterService.activeTier != nil {
                Button {
                    Task { await supporterService.manageSubscriptions() }
                } label: {
                    Text(NSLocalizedString("supporter.manage", comment: "Manage subscription"))
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.top, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("supporter.empty.title", comment: "Subscriptions unavailable"))
                .font(.headline)
            Text(NSLocalizedString("supporter.empty.subtitle", comment: "Please try again later."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = supporterService.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Button {
                Task { await supporterService.loadProducts() }
            } label: {
                Text(NSLocalizedString("supporter.retry", comment: "Retry"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 32)
    }

    private var pageBackground: Color {
        Color.platformSystemGroupedBackground
    }

    private var cardBackground: Color {
        colorScheme == .light ? Color.white : Color.platformSecondarySystemBackground
    }
}
