import SwiftUI
import WidgetKit

/// Entry point for the widget extension.
@main
struct VercelticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeployStatusWidget()
        DeployLiveActivity()
    }
}
