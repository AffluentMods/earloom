// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import ActivityKit
import SwiftUI
import WidgetKit

// The widget extension: the Now Playing home and lock screen widget and the
// sleep timer Live Activity. It only reads what the app wrote to the App
// Group (lib/platform/widget_bridge.dart) and never calls a server.

private let appGroup = "group.com.affluentlabs.earloom"

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let hasBook: Bool
  let title: String
  let subtitle: String
  let progress: Double
  let playing: Bool
  let cover: UIImage?

  static let placeholder = NowPlayingEntry(
    date: Date(), hasBook: true, title: "Salt and Starlight", subtitle: "Chapter 4", progress: 0.4, playing: false,
    cover: nil)

  static func read() -> NowPlayingEntry {
    let store = UserDefaults(suiteName: appGroup)
    let coverPath = store?.string(forKey: "np.cover")
    return NowPlayingEntry(
      date: Date(),
      hasBook: store?.bool(forKey: "np.hasBook") ?? false,
      title: store?.string(forKey: "np.title") ?? "Earloom",
      subtitle: store?.string(forKey: "np.subtitle") ?? "",
      progress: Double(store?.integer(forKey: "np.progress") ?? 0) / 1000,
      playing: store?.bool(forKey: "np.playing") ?? false,
      cover: coverPath.flatMap { UIImage(contentsOfFile: $0) }
    )
  }
}

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(context.isPreview ? .placeholder : .read())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    // The app reloads the widget when something it shows changes.
    completion(Timeline(entries: [.read()], policy: .never))
  }
}

struct NowPlayingView: View {
  @Environment(\.widgetFamily) private var family
  let entry: NowPlayingEntry

  var body: some View {
    switch family {
    case .accessoryRectangular:
      VStack(alignment: .leading) {
        Text(entry.title).font(.headline).lineLimit(1)
        Text(entry.subtitle).font(.caption).lineLimit(1)
        ProgressView(value: entry.progress)
      }
    case .accessoryCircular:
      Gauge(value: entry.progress) { Image(systemName: "headphones") }
        .gaugeStyle(.accessoryCircularCapacity)
    default:
      HStack(spacing: 12) {
        cover.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.title).font(.headline).lineLimit(2)
          if !entry.subtitle.isEmpty {
            Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          if entry.hasBook { ProgressView(value: entry.progress).tint(.accentColor) }
        }
      }
      .widgetURL(URL(string: entry.hasBook ? "earloom://player" : "earloom://player?action=resume"))
    }
  }

  @ViewBuilder private var cover: some View {
    if let image = entry.cover {
      Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
    } else {
      ZStack {
        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
        Image(systemName: "headphones").font(.title2)
      }
    }
  }
}

struct NowPlayingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NowPlayingWidget", provider: NowPlayingProvider()) { entry in
      NowPlayingView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now playing")
    .description("What you are listening to.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
  }
}

/// The sleep timer on the lock screen and in the Dynamic Island.
struct SleepTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SleepTimerAttributes.self) { context in
      HStack {
        Image(systemName: "moon.zzz.fill")
        VStack(alignment: .leading) {
          Text(context.attributes.title).font(.headline).lineLimit(1)
          remaining(context.state)
        }
        Spacer()
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) { Image(systemName: "moon.zzz.fill") }
        DynamicIslandExpandedRegion(.center) { Text(context.attributes.title).lineLimit(1) }
        DynamicIslandExpandedRegion(.trailing) { remaining(context.state) }
      } compactLeading: {
        Image(systemName: "moon.zzz.fill")
      } compactTrailing: {
        remaining(context.state).frame(maxWidth: 56)
      } minimal: {
        Image(systemName: "moon.zzz.fill")
      }
    }
  }

  @ViewBuilder private func remaining(_ state: SleepTimerAttributes.ContentState) -> some View {
    if state.paused {
      Text(Duration.seconds(state.remainingSeconds), format: .time(pattern: .minuteSecond))
        .monospacedDigit()
    } else {
      Text(timerInterval: Date()...state.endsAt, countsDown: true).monospacedDigit()
    }
  }
}

@main
struct EarloomWidgets: WidgetBundle {
  var body: some Widget {
    NowPlayingWidget()
    SleepTimerLiveActivity()
  }
}
