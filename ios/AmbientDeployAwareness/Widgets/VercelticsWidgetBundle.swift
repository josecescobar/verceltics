import SwiftUI
import WidgetKit

/// Entry point for the widget extension. Replaces the stub Xcode generates with the target.
@main
struct VercelticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeployStatusWidget()
        DeployLiveActivity()
    }
}
