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
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let snapshot = entry.snapshot {
        GeometryReader { geometry in
          Image(nsImage: snapshot.image).resizable().scaledToFit()
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        LinearGradient(
          colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 3) {
          Text(snapshot.cameraName).font(.headline).lineLimit(1)
          Text(snapshot.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
            .font(.caption2).foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Captured \(snapshot.capturedAt.formatted())")
        }.padding(12)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "video").font(.title2)
          Text("No snapshot yet").font(.headline)
          Text("Open Camera Bar to choose a camera.").font(.caption).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
      }
    }.foregroundStyle(.white)
      .containerBackground(.black, for: .widget)
      .widgetURL(URL(string: "camerabar://viewer"))
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
