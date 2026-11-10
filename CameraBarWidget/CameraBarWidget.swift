// ABOUTME: Shows the selected camera's last captured frame in a native desktop widget.
// ABOUTME: Preserves capture time and opens the menu bar viewer when clicked.
import SwiftUI
import WidgetKit

struct CameraEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
}

struct CameraProvider: TimelineProvider {
  func placeholder(in context: Context) -> CameraEntry { CameraEntry(date: Date(), snapshot: nil) }
  func getSnapshot(in context: Context, completion: @escaping (CameraEntry) -> Void) {
    completion(entry())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<CameraEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(300))))
  }
  private func entry() -> CameraEntry {
    CameraEntry(
      date: Date(),
      snapshot: SharedContainer.snapshotStore().flatMap { WidgetSnapshot.load(from: $0) })
  }
}

struct CameraWidgetView: View {
  let entry: CameraEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    CameraWidgetContent(entry: entry, family: family)
      .containerBackground(MonitorTheme.housing, for: .widget)
      .widgetURL(URL(string: "camerabar://viewer"))
  }
}

struct CameraWidgetContent: View {
  let entry: CameraEntry
  let family: WidgetFamily

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 5) {
        Image(systemName: "display").accessibilityHidden(true)
        Text("SNAPSHOT").tracking(1.3)
        Spacer(minLength: 0)
      }.font(.system(size: 9, weight: .semibold)).foregroundStyle(MonitorTheme.secondary)
      if let snapshot = entry.snapshot {
        if family == .systemMedium {
          HStack(spacing: 12) {
            display(snapshot)
            caption(snapshot).frame(width: 100, alignment: .leading)
          }
        } else {
          display(snapshot)
          caption(snapshot)
        }
      } else {
        VStack(spacing: 7) {
          Image(systemName: "display")
            .font(.system(size: family == .systemSmall ? 23 : 28, weight: .light))
            .foregroundStyle(MonitorTheme.secondary).accessibilityHidden(true)
          Text("No snapshot yet").font(.system(size: 12, weight: .semibold))
          Text("Open Camera Bar to choose a camera.")
            .font(.system(size: 10)).foregroundStyle(MonitorTheme.secondary)
            .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
          .background(MonitorTheme.display, in: RoundedRectangle(cornerRadius: 6))
      }
    }.padding(12).foregroundStyle(MonitorTheme.text)
  }

  private func display(_ snapshot: WidgetSnapshot) -> some View {
    GeometryReader { geometry in
      Image(nsImage: snapshot.image).resizable().scaledToFit()
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .background(MonitorTheme.display)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6).strokeBorder(MonitorTheme.edge, lineWidth: 1)
    }
    .accessibilityLabel("Snapshot of \(snapshot.cameraName)")
  }

  private func caption(_ snapshot: WidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: family == .systemMedium ? 6 : 2) {
      Text(snapshot.cameraName).font(.system(size: 12, weight: .semibold))
        .lineLimit(family == .systemMedium ? 3 : 1)
      Text(snapshot.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
        .font(.system(size: 10).monospacedDigit()).foregroundStyle(MonitorTheme.secondary)
        .lineLimit(family == .systemMedium ? 2 : 1).minimumScaleFactor(0.85)
        .accessibilityLabel("Captured \(snapshot.capturedAt.formatted())")
    }
  }
}

@main
struct CameraBarWidget: Widget {
  let kind = "CameraBarSnapshot"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CameraProvider()) { CameraWidgetView(entry: $0) }
      .configurationDisplayName("Camera Bar")
      .description(
        "The latest snapshot from your selected camera. Keep Camera Bar running for updates."
      )
      .supportedFamilies([.systemSmall, .systemMedium])
      .contentMarginsDisabled()
  }
}
