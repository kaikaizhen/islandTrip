import SwiftUI

/// 推薦班次頁下方的「轉乘方案」區塊：只供查看，點了看步驟與地圖。
struct TransitPlansSection: View {
    let viewModel: TransitPlansViewModel
    @State private var detail: TransitPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("轉乘方案（含捷運、火車）")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("transitPlans")
            Label("可以先看怎麼走；轉乘的語音導航還沒有提供。", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .sheet(item: $detail) { plan in
            TransitPlanDetailView(plan: plan, origin: viewModel.origin, destination: viewModel.destination,
                                  now: viewModel.currentTime)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("正在找轉乘方案…（可能要半分鐘）")
                .frame(maxWidth: .infinity, minHeight: 80)
        case .failed(let message):
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded where viewModel.plans.isEmpty:
            Text("沒有找到轉乘方案。")
                .font(.body)
                .foregroundStyle(.secondary)
        case .loaded:
            let now = viewModel.currentTime
            ForEach(viewModel.plans) { plan in
                Button {
                    detail = plan
                } label: {
                    TransitPlanCard(plan: plan, now: now)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan-\(plan.id)")
            }
        }
    }
}
