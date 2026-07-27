import ActivityKit

struct LifeOSLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var scope: LiveActivityScope
        var remainingCount: Int
        var items: [LiveActivityItem]
    }
}

