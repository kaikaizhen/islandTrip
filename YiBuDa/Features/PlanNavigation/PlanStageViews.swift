import SwiftUI

/// 搭乘段的大標題：運具圖示＋路線＋往哪裡。方向是長輩最容易搭錯的地方，字要最大。
struct TransitHeader: View {
    let leg: TransitLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(PlanFormat.lineTitle(leg))
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: leg.mode.symbolName)
                    .foregroundStyle(Theme.accent)
            }
            if let headsign = PlanFormat.headsign(leg) {
                Text(headsign)
                    .font(.system(size: 40, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// 車站內步行：跟著站內指標走，不用 GPS（站內收不到）。
struct StationWalkView: View {
    let from: String?
    let to: String?
    let seconds: Int
    /// 走完後要搭的車（進站時）；出站時為 nil。
    let upcoming: TransitLeg?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("約 \(max(1, Int((Double(seconds) / 60).rounded(.up)))) 分鐘")
                        .font(.title2)
                }
                .card()
                .accessibilityElement(children: .combine)
                if let upcoming {
                    Label("跟著站內「\(PlanFormat.lineTitle(upcoming))」\(PlanFormat.headsign(upcoming).map { "、\($0)" } ?? "")的指標走。",
                          systemImage: "signpost.right.fill")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()
                } else {
                    Label("跟著站內「出口」指標走。", systemImage: "door.left.hand.open")
                        .font(.title3)
                        .card()
                }
                Label("車站內收不到定位，走到後請按下方按鈕。", systemImage: "location.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacing)
        }
    }

    private var title: String {
        if let to, !to.isEmpty { return "在站內走到 \(to)" }
        return upcoming == nil ? "走到出口" : "走到月台"
    }
}

/// 候車：搭什麼、往哪裡、在哪裡等、多久來（標示即時或表定）。
struct PlanWaitingView: View {
    let leg: TransitLeg
    let now: Date
    let notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let notice {
                    SafetyNote(text: notice).card()
                }
                TransitHeader(leg: leg)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        DataTagView(isRealtime: PlanFormat.isRealtime(leg))
                        Text(PlanFormat.boardingTimeWithoutTag(leg, now: now))
                            .font(.title.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("在 \(PlanFormat.place(leg.from, fallback: "這一站")) 上車")
                        .font(.title3)
                    if let updated = leg.realtime?.updatedAt {
                        Label(TransitFormat.updated(updated, isStale: now.timeIntervalSince(updated) > 120), systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("planWaitingTime")
                SafetyNote(text: hint)
                    .card()
            }
            .padding(Theme.spacing)
        }
    }

    private var hint: String {
        let direction = PlanFormat.headsign(leg).map { "「\($0)」" } ?? "正確方向"
        switch leg.mode {
        case .bus:
            return "車來時看清楚車頭的路線「\(leg.line)」再上車。"
        case .metro, .lightRail:
            return "請在寫著\(direction)的月台等車，上車前再看一次車門上方的方向。"
        case .tra, .thsr:
            return "請確認月台與車次，搭往\(direction)的車。表定時間可能因誤點改變，請注意月台廣播。"
        case .ferry, .other:
            return "上車前請確認方向是\(direction)。"
        }
    }
}

/// 搭乘中：在哪一站下車、剩幾站（GPS 可信時）、快到站時大字提醒。
struct PlanRidingView: View {
    let leg: TransitLeg
    let status: AlightReminder.Status
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if status.isApproaching {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 44))
                        Text("準備下車")
                            .font(.system(size: 40, weight: .bold))
                        Text("下一站：\(alightName)")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if status.source == .schedule {
                            Text("依表定時間提醒，請聽車上廣播確認站名")
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
                TransitHeader(leg: leg)
                VStack(alignment: .leading, spacing: 8) {
                    Text("在 \(alightName) 下車")
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let remaining = status.remainingStops, status.source == .gps {
                        Text(remaining == 0 ? "已到站" : "還有約 \(remaining) 站（依定位）")
                            .font(.title2)
                    }
                    if let arriveAt = leg.arriveAt {
                        Text("表定 \(TransitFormat.clock(arriveAt)) 到")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
                .accessibilityElement(children: .combine)
                if !status.isApproaching {
                    Label(reminderText, systemImage: "speaker.wave.2.fill")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()
                }
            }
            .padding(Theme.spacing)
        }
    }

    private var alightName: String { PlanFormat.place(leg.to, fallback: "下車站") }

    private var reminderText: String {
        switch status.source {
        case .gps: "快到站時會震動提醒您準備下車。"
        case .schedule: "沒有可靠的定位（例如在地下），會依表定時間提醒；請同時注意車上廣播。"
        case nil: "請聽車上廣播，看到站名再下車。"
        }
    }
}
