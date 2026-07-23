//
//  FlutterWindow.swift
//  flutter_multi_window
//
//  Created by Bin Yang on 2022/1/10.
//
import Cocoa
import FlutterMacOS
import Foundation

class BaseFlutterWindow: NSObject {
  private let window: NSWindow
  let windowChannel: WindowChannel

  init(window: NSWindow, channel: WindowChannel) {
    self.window = window
    self.windowChannel = channel
    super.init()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func hide() {
    window.orderOut(nil)
  }

  func center() {
    window.center()
  }

  func setFrame(frame: NSRect) {
    window.setFrame(frame, display: false, animate: true)
  }

  func setTitle(title: String) {
    window.title = title
  }

  func resizable(resizable: Bool) {
    if (resizable) {
      window.styleMask.insert(.resizable)
    } else {
      window.styleMask.remove(.resizable)
    }
  }

  func close() {
    window.close()
  }

  func setFrameAutosaveName(name: String) {
    window.setFrameAutosaveName(name)
  }
}

// Plain `NSWindow` (no `.titled`) never reliably becomes the key
// window on macOS — and a window that isn't key never routes keyboard
// events to its content, so no text field inside it can ever receive
// input. This is the exact same issue fixed in the app's own
// MainFlutterWindow.swift for the primary (login) window; this
// secondary-window class needs the same fix, since every dashboard
// window (created via DesktopMultiWindow.createWindow) is built here.
class CroplooMultiFlutterWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

class FlutterWindow: BaseFlutterWindow {
  let windowId: Int64

  let window: NSWindow

  weak var delegate: WindowManagerDelegate?

  init(id: Int64, arguments: String) {
    windowId = id
    window = CroplooMultiFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
      styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["multi_window", "\(windowId)", arguments]
    let flutterViewController = FlutterViewController(project: project)
    window.contentViewController = flutterViewController

    let plugin = flutterViewController.registrar(forPlugin: "FlutterMultiWindowPlugin")
    FlutterMultiWindowPlugin.registerInternal(with: plugin)
    let windowChannel = WindowChannel.register(with: plugin, windowId: id)
    // Give app a chance to register plugin.
    FlutterMultiWindowPlugin.onWindowCreatedCallback?(flutterViewController)

    super.init(window: window, channel: windowChannel)

    window.delegate = self
    window.isReleasedWhenClosed = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    // Hide native traffic lights; custom controls are rendered in Flutter.
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
  }

  deinit {
    debugPrint("release window resource")
    window.delegate = nil
    // Do not shut down the engine synchronously here. Flutter may still send
    // lifecycle/platform messages briefly after the window closes; tearing
    // down the engine immediately causes 'Invalid engine handle' errors.
    // The engine is released when the window/controller are deallocated.
    window.contentViewController = nil
    window.windowController = nil
  }
}

extension FlutterWindow: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    delegate?.onClose(windowId: windowId)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    delegate?.onClose(windowId: windowId)
    return true
  }
}
