// ABOUTME: Presents the live viewer and a small camera editor using native controls.
// ABOUTME: Keeps addresses in secure fields and all selection in CameraState.
import AppKit
import CameraBarCore
import SwiftUI

struct ViewerRoot: View {
  @ObservedObject var controller: AppController
  var body: some View {
    Group {
      if let state = controller.state {
        ViewerView(controller: controller, state: state)
      } else {
        Text(controller.error ?? "Camera Bar is unavailable").padding(24).frame(width: 400)
      }
    }.preferredColorScheme(.dark)
  }
}

struct ViewerView: View {
  @ObservedObject var controller: AppController
  @ObservedObject var state: CameraState
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "video.fill").foregroundStyle(.secondary)
        if state.cameras.isEmpty {
          Text("Camera Bar").font(.headline)
        } else {
          Picker(
            "Camera",
            selection: Binding(
              get: { state.selectedCamera?.id },
              set: { id in
                if let id { _ = controller.perform { try state.select(id: id) } }
              })
          ) {
            ForEach(state.cameras) { camera in Text(camera.name).tag(Optional(camera.id)) }
          }.labelsHidden().accessibilityLabel("Selected camera")
        }
        Spacer()
        Button(action: controller.showSettings) { Image(systemName: "gearshape") }
          .buttonStyle(.plain).help("Camera settings").accessibilityLabel("Camera settings")
      }.padding(16)
      ZStack {
        Color.black
        if state.selectedCamera != nil {
          VideoSurface(engine: controller.engine, isVisible: controller.viewerOpen)
          if !controller.isLive {
            VStack(spacing: 10) {
              Image(systemName: "video.slash").font(.system(size: 26)).foregroundStyle(.secondary)
              Text(controller.status).font(.callout)
              if controller.status != "Connecting…" { Button("Retry") { controller.restart() } }
            }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
        } else {
          VStack(spacing: 12) {
            Image(systemName: "video.badge.plus").font(.system(size: 32)).foregroundStyle(
              .secondary)
            Text("Your camera, one click away").font(.headline)
            Text("Add an RTSP camera to get started.").foregroundStyle(.secondary)
            Button("Add camera", action: controller.showSettings)
          }
        }
      }.frame(width: 480, height: 270)
      HStack {
        Circle().fill(controller.isLive ? Color.green : Color.secondary).frame(width: 6, height: 6)
        Text(controller.status).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption)
      }.padding(14)
      if let error = controller.error {
        Text(error).font(.caption).foregroundStyle(.orange).padding([.horizontal, .bottom])
      }
      if controller.widgetUnavailable {
        Text("Widget sharing is unavailable. See setup instructions.")
          .font(.caption).foregroundStyle(.secondary).padding([.horizontal, .bottom])
      }
    }.frame(width: 480, height: 430, alignment: .top)
  }
}

struct VideoSurface: NSViewRepresentable {
  let engine: PlaybackEngine
  let isVisible: Bool
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    if isVisible, engine.videoView.superview !== view {
      engine.videoView.removeFromSuperview()
      engine.videoView.frame = view.bounds
      engine.videoView.autoresizingMask = [.width, .height]
      view.addSubview(engine.videoView)
    } else if !isVisible, engine.videoView.superview === view {
      engine.parkVideo()
    }
  }
  func makeCoordinator() -> PlaybackEngine { engine }
  static func dismantleNSView(_ view: NSView, coordinator: PlaybackEngine) {
    coordinator.parkVideo()
  }
}

struct SettingsRoot: View {
  @ObservedObject var controller: AppController
  var body: some View {
    Group {
      if let state = controller.state {
        CameraSettings(controller: controller, state: state)
      } else {
        Text(controller.error ?? "Camera settings unavailable").padding()
      }
    }.preferredColorScheme(.dark)
  }
}

struct CameraSettings: View {
  @ObservedObject var controller: AppController
  @ObservedObject var state: CameraState
  @State private var editor: CameraEditorModel?
  @State private var removing: Camera?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Cameras").font(.title2.bold())
          Text("One selected camera powers the viewer and widget.").foregroundStyle(.secondary)
        }
        Spacer()
        Button("Add camera") { editor = CameraEditorModel() }
      }
      if state.cameras.isEmpty {
        ContentUnavailableView(
          "No cameras yet", systemImage: "video", description: Text("Add a named RTSP address."))
      } else {
        List(state.cameras) { camera in
          HStack(spacing: 12) {
            Image(
              systemName: camera.id == state.selectedCamera?.id ? "checkmark.circle.fill" : "video"
            )
            .foregroundStyle(
              camera.id == state.selectedCamera?.id ? Color.accentColor : Color.secondary)
            Text(camera.name)
            Spacer()
            if camera.id != state.selectedCamera?.id {
              Button("Select") { _ = controller.perform { try state.select(id: camera.id) } }
                .accessibilityLabel("Select \(camera.name)")
            }
            Button("Edit") {
              do {
                editor = CameraEditorModel(
                  camera: camera, address: try state.address(id: camera.id)?.rawValue ?? "")
              } catch {
                controller.error = "Could not read this address. Unlock Keychain and try again."
              }
            }.accessibilityLabel("Edit \(camera.name)")
            Button {
              removing = camera
            } label: {
              Image(systemName: "trash")
            }
            .accessibilityLabel("Remove \(camera.name)")
          }.padding(.vertical, 6)
        }.listStyle(.inset)
      }
      if let error = controller.error { Text(error).foregroundStyle(.orange).font(.callout) }
      HStack {
        Text("Addresses stay in Keychain. Keep Camera Bar running for widget updates.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Show viewer", action: controller.showViewer)
      }
    }.padding(24).frame(width: 580, height: 420)
      .sheet(item: $editor) { draft in
        CameraEditor(controller: controller, state: state, draft: draft)
      }
      .alert(
        "Remove camera?",
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
      ) {
        Button("Cancel", role: .cancel) { removing = nil }
        Button("Remove camera", role: .destructive) {
          if let camera = removing { _ = controller.perform { try state.remove(id: camera.id) } }
          removing = nil
        }
      } message: {
        Text("This removes the saved address from Keychain.")
      }
  }
}

struct CameraEditorModel: Identifiable {
  let id = UUID()
  var camera: Camera?
  var name: String
  var address: String
  init(camera: Camera? = nil, address: String = "") {
    self.camera = camera
    name = camera?.name ?? ""
    self.address = address
  }
}

struct CameraEditor: View {
  @ObservedObject var controller: AppController
  @ObservedObject var state: CameraState
  @State var draft: CameraEditorModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(draft.camera == nil ? "Add camera" : "Edit camera").font(.title2.bold())
      Form {
        TextField("Name", text: $draft.name).accessibilityLabel("Camera name")
        SecureField("RTSP address", text: $draft.address).accessibilityLabel("RTSP address")
          .help("rtsp://username:password@camera-host/path")
      }
      Text("Use the RTSP address provided by your camera. Credentials are saved in Keychain.")
        .font(.caption).foregroundStyle(.secondary)
      if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save camera") {
          let saved = controller.perform {
            if let camera = draft.camera {
              try state.edit(id: camera.id, name: draft.name, address: draft.address)
            } else {
              try state.add(name: draft.name, address: draft.address)
            }
          }
          if saved { dismiss() }
        }.keyboardShortcut(.defaultAction).disabled(
          draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.address.isEmpty)
      }
    }.padding(24).frame(width: 430)
  }
}
