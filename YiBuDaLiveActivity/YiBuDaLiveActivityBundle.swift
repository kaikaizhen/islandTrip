import SwiftUI
import WidgetKit

/// 只包含 Live Activity，刻意不提供主畫面 Widget。
@main
struct YiBuDaLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        NavigationLiveActivity()
    }
}
