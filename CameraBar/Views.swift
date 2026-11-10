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
      HStack(spacing: 12) {
        Image(systemName: "display")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(MonitorTheme.secondary)
          .accessibilityHidden(true)
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
        Spacer(minLength: 12)
        Button(action: controller.showSettings) { Image(systemName: "gearshape") }
          .buttonStyle(.borderless).controlSize(.large)
          .help("Camera settings").accessibilityLabel("Camera settings")
      }.padding(.horizontal, 20).frame(height: 62)
      ZStack {
        MonitorTheme.display
        if state.selectedCamera != nil {
          VideoSurface(engine: controller.engine, isVisible: controller.viewerOpen)
          if !controller.isLive {
            MonitorTheme.display
            VStack(spacing: 12) {
              Image(systemName: controller.status == "Connecting…" ? "display" : "wifi.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(MonitorTheme.secondary)
                .accessibilityHidden(true)
              Text(controller.status).font(.headline)
              if controller.status == "Connecting…" {
                Text("Waiting for the camera’s video.")
                  .font(.callout).foregroundStyle(MonitorTheme.secondary)
              } else {
                Text("Check the camera’s connection or saved address.")
                  .font(.callout).foregroundStyle(MonitorTheme.secondary)
                Button("Retry") { controller.restart() }.controlSize(.large)
              }
            }.padding(24).multilineTextAlignment(.center)
          }
        } else {
          VStack(spacing: 12) {
            Image(systemName: "display")
              .font(.system(size: 36, weight: .ultraLight))
              .foregroundStyle(MonitorTheme.secondary).accessibilityHidden(true)
            Text("Your camera, one click away").font(.headline)
            Text("Add an RTSP camera to get started.")
              .font(.callout).foregroundStyle(MonitorTheme.secondary)
            Button("Add camera", action: controller.showSettings).controlSize(.large)
          }.padding(24)
        }
      }.frame(width: 464, height: 261)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10).strokeBorder(MonitorTheme.edge, lineWidth: 1)
        }
        .padding(.horizontal, 16)
      HStack(spacing: 8) {
        Circle().fill(controller.isLive ? MonitorTheme.live : MonitorTheme.secondary.opacity(0.5))
          .frame(width: 6, height: 6).accessibilityHidden(true)
        Text(controller.status).font(.caption).foregroundStyle(MonitorTheme.secondary)
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
          .buttonStyle(.borderless).font(.caption).foregroundStyle(MonitorTheme.secondary)
      }.padding(.horizontal, 20).frame(height: 42)
      if let error = controller.error {
        Text(error).font(.caption).foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(
            .bottom, 8)
      }
      if controller.widgetUnavailable {
        HStack(alignment: .top, spacing: 7) {
          Image(systemName: "info.circle").accessibilityHidden(true)
          Text("Widget sharing is unavailable. See setup instructions.")
        }.font(.caption).foregroundStyle(MonitorTheme.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20).padding(.bottom, 14)
      }
    }.frame(width: 496).fixedSize(horizontal: false, vertical: true)
      .foregroundStyle(MonitorTheme.text).background(MonitorTheme.housing)
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
          Text("Cameras").font(.system(size: 24, weight: .semibold))
          Text("One camera for your viewer and widget.")
            .font(.callout).foregroundStyle(MonitorTheme.secondary)
        }
        Spacer()
        Button("Add camera") { editor = CameraEditorModel() }.controlSize(.large)
      }
      if state.cameras.isEmpty {
        ContentUnavailableView(
          "No cameras yet", systemImage: "display", description: Text("Add a named RTSP address.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(state.cameras) { camera in
          HStack(spacing: 12) {
            Image(
              systemName: camera.id == state.selectedCamera?.id
                ? "checkmark.circle.fill" : "display"
            )
            .foregroundStyle(
              camera.id == state.selectedCamera?.id ? MonitorTheme.text : MonitorTheme.secondary)
            VStack(alignment: .leading, spacing: 3) {
              Text(camera.name).font(.body.weight(.medium)).lineLimit(1)
              if camera.id == state.selectedCamera?.id {
                Text("Selected for viewer & widget").font(.caption)
                  .foregroundStyle(MonitorTheme.secondary)
              }
            }
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
          }.padding(.vertical, 10)
        }.listStyle(.inset).scrollContentBackground(.hidden)
          .background(MonitorTheme.display, in: RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(MonitorTheme.edge, lineWidth: 1)
              .allowsHitTesting(false)
          }
      }
      if let error = controller.error { Text(error).foregroundStyle(.orange).font(.callout) }
      HStack {
        Text("Addresses stay in Keychain.\nKeep Camera Bar running for widget updates.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Show viewer", action: controller.showViewer)
      }
    }.padding(24).frame(width: 600, height: 440)
      .foregroundStyle(MonitorTheme.text).background(MonitorTheme.housing)
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
      Text(draft.camera == nil ? "Add camera" : "Edit camera")
        .font(.system(size: 24, weight: .semibold))
      Form {
        TextField("Name", text: $draft.name).accessibilityLabel("Camera name")
        SecureField("RTSP address", text: $draft.address).accessibilityLabel("RTSP address")
          .help("rtsp://username:password@camera-host/path")
      }
      Label(
        "Use your camera’s RTSP address. Credentials are saved in Keychain.", systemImage: "lock"
      )
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
    }.padding(28).frame(width: 460)
      .foregroundStyle(MonitorTheme.text).background(MonitorTheme.housing)
  }
}
