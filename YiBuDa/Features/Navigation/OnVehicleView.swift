import SwiftUI

/// 搭乘中（草圖 D）：路線、要下車的站、剩餘站數（資料可信時）、「準備下車」大字提醒。
struct OnVehicleView: View {
    let bus: BusLeg
    let remainingStops: Int?
    let isApproaching: Bool
    /// 「準備下車」的依據；依預估時間時要提醒使用者聽廣播確認。
    var alightSource: AlightReminder.Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                // 快到站時「準備下車」放最上面，字體放大也不會被底部按鈕擋住。
                if isApproaching {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 44))
                        Text("準備下車")
                            .font(.system(size: 40, weight: .bold))
                        Text("下一站：\(bus.alightingStop.name)")
                            .font(.title2.weight(.semibold))
                        if alightSource == .schedule {
                            Text("依預估時間提醒，請聽車上廣播確認站名")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.spacing * 1.5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("approachingAlight")
                }

                VStack(alignment: .leading, spacing: 6) {
                    RouteBadge(routeName: bus.option.routeName, size: .system(size: 56))
                    Text(bus.option.direction)
                        .font(.title2.weight(.semibold))
                }
                .card()
                .accessibilityElement(children: .combine)

                progress

                if !isApproaching {
                    Label("快到站時會提醒您準備下車", systemImage: "speaker.wave.2.fill")
                        .font(.title3)
                        .card()
                }
            }
            .padding(Theme.spacing)
        }
    }

    @ViewBuilder
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("在 \(bus.alightingStop.name) 下車")
                .font(.title.bold())
            if let remainingStops {
                Text("還有 \(remainingStops) 站（模擬）")
                    .font(.title2)
                    .accessibilityIdentifier("remainingStops")
            } else {
                Text("請聽車上廣播，看到站名再下車。")
                    .font(.title3)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// 已抵達。
struct ArrivedView: View {
    let destinationName: String

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(Theme.accent)
            Text("已抵達")
                .font(.largeTitle.bold())
            Text(destinationName)
                .font(.title.weight(.semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacing)
        .accessibilityElement(children: .combine)
    }
}
