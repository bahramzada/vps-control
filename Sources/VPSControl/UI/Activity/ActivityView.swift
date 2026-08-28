import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "Fəaliyyət",
                subtitle: "Yalnız tətbiqin yaratdığı redaktə olunmuş hadisələr",
                systemImage: "waveform.path.ecg"
            )

            if appState.activities.isEmpty {
                ContentUnavailableView(
                    "Fəaliyyət yoxdur",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Terminal məzmunu və parollar heç vaxt bu jurnala yazılmır.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                }
                .glassCard(padding: 12)
            }
        }
        .padding(26)
        .background(VPSTheme.canvas)
    }
}

struct ActivityRow: View {
    let activity: ActivityEntry

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: activity.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(activity.tint)
                .frame(width: 26, height: 26)
                .background(activity.tint.opacity(0.11))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VPSTheme.primaryText)
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(VPSTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(activity.date, format: .dateTime.hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(VPSTheme.secondaryText)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VPSTheme.subtleBorder)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
