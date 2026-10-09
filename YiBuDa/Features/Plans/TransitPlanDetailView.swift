import MapKit
import SwiftUI

/// 轉乘方案詳情：上方地圖示意、下方大字逐步說明。只供查看。
struct TransitPlanDetailView: View {
    let plan: TransitPlan
    let origin: Place
    let destination: Place
    let now: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PlanFormat.duration(plan.durationSeconds))
                            .font(.title.bold())
                        if let endAt = plan.endAt {
                            Text(TransitFormat.arrival(endAt))
                                .font(.title3)
                        }
                        Text(PlanFormat.summary(plan))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    map
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .accessibilityLabel("路線示意地圖")
                    Text("地圖上的線只是示意，實際依車輛行駛路線。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    steps
                    SafetyNote(text: "標「表定」的時間是時刻表，不是即時資訊，車可能提早或晚到。")
                        .card()
                }
                .padding(Theme.spacing)
            }
            .navigationTitle("轉乘方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SimulatedBadge()
                }
            }
        }
        .presentationBackground(Color(.systemBackground))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(Array(PlanSteps.make(plan, originName: origin.name, destinationName: destination.name, now: now).enumerated()),
                    id: \.element.id) { number, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number + 1)")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Label(step.title, systemImage: step.symbolName)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let tag = step.dataTag {
                            DataTagView(isRealtime: tag == .realtime)
                        }
                        Text(step.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var map: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(Array(plan.legs.enumerated()), id: \.offset) { _, leg in
                switch leg {
                case .walk(let walk):
                    MapPolyline(coordinates: [walk.from.coordinate.clCoordinate, walk.to.coordinate.clCoordinate])
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 8]))
                case .transit(let transit):
                    MapPolyline(coordinates: ([transit.from] + transit.stops + [transit.to]).map(\.coordinate.clCoordinate))
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    Marker(PlanFormat.place(transit.from, fallback: "上車"), systemImage: transit.mode.symbolName,
                           coordinate: transit.from.coordinate.clCoordinate)
                        .tint(Theme.accent)
                case .wait:
                    MapPolyline(coordinates: [])
                }
            }
            Marker("出發", systemImage: "figure.stand", coordinate: origin.coordinate.clCoordinate)
                .tint(Theme.accent)
            Marker(destination.name, systemImage: "flag.checkered", coordinate: destination.coordinate.clCoordinate)
                .tint(Theme.accent)
        }
        .mapControls { MapScaleView() }
    }
}
