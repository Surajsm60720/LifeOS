import ActivityKit

struct LifeOSLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var itemCount: Int
        var items: [LiveActivityItem]
    }
}

