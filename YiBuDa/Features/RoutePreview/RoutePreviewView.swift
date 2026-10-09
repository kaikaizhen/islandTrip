import MapKit
import SwiftUI

/// 在地圖上確認方案：上方地圖、下方用大字逐段說明。地圖只是輔助，不要求看懂地圖。
struct RoutePreviewView: View {
    @Bindable var viewModel: RoutePreviewViewModel
    let onChoose: () -> Void

    enum Focus: Hashable {
        case boardingArea
        case wholeRoute
    }

    @Environment(\.dismiss) private var dismiss
    @State private var focus: Focus = .boardingArea
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    // 預設放大上車站附近：全程縮放時，兩側站牌只差幾十公尺會疊在一起，看不出哪一側。
                    Picker("地圖範圍", selection: $focus) {
                        Text("上車站附近").tag(Focus.boardingArea)
                        Text("全程").tag(Focus.wholeRoute)
                    }
                    .pickerStyle(.segmented)
                    map
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .accessibilityLabel("路線地圖")
                    if let bus = viewModel.bus {
                        legend(bus)
                    }
                }
                .padding(Theme.spacing)
            }
            .navigationTitle("在地圖上確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SimulatedBadge()
                }
            }
            .bottomAction(chooseTitle, systemImage: "checkmark") {
                onChoose()
                dismiss()
            }
        }
        .task {
            await viewModel.load()
            updateCamera()
        }
        .onChange(of: focus) { updateCamera() }
    }

    private func updateCamera() {
        withAnimation {
            switch focus {
            case .wholeRoute:
                camera = .automatic
            case .boardingArea:
                camera = Self.region(fitting: viewModel.boardingAreaCoordinates).map(MapCameraPosition.region) ?? .automatic
            }
        }
    }

    /// 能同時看到所有點的範圍，至少約 200 公尺見方，才分得出馬路兩側。
    private static func region(fitting coordinates: [Coordinate]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let minimumSpan = 0.002
        let center = CLLocationCoordinate2D(latitude: ((lats.min() ?? first.latitude) + (lats.max() ?? first.latitude)) / 2,
                                            longitude: ((lons.min() ?? first.longitude) + (lons.max() ?? first.longitude)) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(minimumSpan, ((lats.max() ?? 0) - (lats.min() ?? 0)) * 1.6),
                                    longitudeDelta: max(minimumSpan, ((lons.max() ?? 0) - (lons.min() ?? 0)) * 1.6))
        return MKCoordinateRegion(center: center, span: span)
    }

    private var chooseTitle: String {
        viewModel.bus.map { "選這個方案（搭 \($0.option.routeName)）" } ?? "選這個方案"
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(viewModel.segments) { segment in
                MapPolyline(coordinates: segment.coordinates.map(\.clCoordinate))
                    .stroke(segment.kind == .bus ? Color.secondary : Theme.accent,
                            style: StrokeStyle(lineWidth: segment.kind == .bus ? 4 : 6, lineCap: .round,
                                               dash: segment.isApproximate ? [8, 8] : []))
            }
            ForEach(viewModel.markers) { marker in
                Marker(marker.title, systemImage: marker.symbolName, coordinate: marker.coordinate.clCoordinate)
                    .tint(marker.tint)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private func legend(_ bus: BusLeg) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            legendRow(number: 1, title: "走到 \(bus.boardingStop.name)",
                      detail: "\(bus.boardingStop.directionDescription)\n\(viewModel.walkSummary(viewModel.walkToStop))")
            if viewModel.oppositeStop != nil {
                SafetyNote(text: "對面也有同名站牌，但方向相反（地圖上灰色「不是這個」），不要在那裡搭。")
            }
            legendRow(number: 2, title: "搭 \(bus.option.routeName)（\(bus.option.direction)）",
                      detail: "在 \(bus.alightingStop.name) 下車\n地圖上的公車虛線只是示意，實際依公車行駛路線")
            legendRow(number: 3, title: "走到 \(viewModel.ranked.journey.destination.name)",
                      detail: viewModel.walkSummary(viewModel.walkToDestination))
        }
        .card()
    }

    private func legendRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension RouteMarker {
    var symbolName: String {
        switch kind {
        case .origin: "figure.stand"
        case .boardingStop: "bus.fill"
        case .wrongDirectionStop: "xmark"
        case .alightingStop: "bell.fill"
        case .destination: "flag.checkered"
        }
    }

    var tint: Color {
        switch kind {
        case .wrongDirectionStop: .gray
        default: Theme.accent
        }
    }
}
