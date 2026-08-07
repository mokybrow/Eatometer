//
//  EatometerWidgetLiveActivity.swift
//  EatometerWidget
//
//  Created by Михаил Панин on 16/04/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct EatometerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String
    }

    var name: String
}

struct EatometerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EatometerWidgetAttributes.self) { context in
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension EatometerWidgetAttributes {
    fileprivate static var preview: EatometerWidgetAttributes {
        EatometerWidgetAttributes(name: "World")
    }
}

extension EatometerWidgetAttributes.ContentState {
    fileprivate static var smiley: EatometerWidgetAttributes.ContentState {
        EatometerWidgetAttributes.ContentState(emoji: "😀")
    }

    fileprivate static var starEyes: EatometerWidgetAttributes.ContentState {
        EatometerWidgetAttributes.ContentState(emoji: "🤩")
    }
}

#Preview("Notification", as: .content, using: EatometerWidgetAttributes.preview) {
    EatometerWidgetLiveActivity()
} contentStates: {
    EatometerWidgetAttributes.ContentState.smiley
    EatometerWidgetAttributes.ContentState.starEyes
}
