import Cocoa
import FlutterMacOS
import desktop_multi_window

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var windowControlChannel: FlutterMethodChannel?
  private let minimumWindowSize = NSSize(width: 1600, height: 900)

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    mainFlutterWindow?.delegate = self
    mainFlutterWindow?.minSize = minimumWindowSize

    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }

    windowControlChannel = FlutterMethodChannel(
      name: "croploo/window_controls",
      binaryMessenger: controller.engine.binaryMessenger)

    windowControlChannel?.setMethodCallHandler { [weak self] call, result in
      guard let window = self?.mainFlutterWindow else {
        result(FlutterError(code: "NO_WINDOW", message: "Main window not found", details: nil))
        return
      }
      Self.handleWindowControlCall(call, result: result, window: window)
    }

    // Register the same handler for every secondary window created by
    // desktop_multi_window, so custom window controls work there too.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Register all Flutter plugins with the new engine so platform plugins
      // (e.g., url_launcher) work in secondary windows. This project's
      // GeneratedPluginRegistrant.swift uses the function-based API, not
      // the newer GeneratedPluginRegistrant.register(with:) class API.
      RegisterGeneratedPlugins(registry: controller)

      // Keep secondary windows (e.g., the login window) above the same minimum
      // size so the Flutter layout never gets crushed below its usable bounds.
      let secondaryWindow = controller.view.window
      secondaryWindow?.minSize = self.minimumWindowSize
      secondaryWindow?.delegate = self

      let channel = FlutterMethodChannel(
        name: "croploo/window_controls",
        binaryMessenger: controller.engine.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard let window = controller.view.window else {
          result(FlutterError(code: "NO_WINDOW", message: "Window not found", details: nil))
          return
        }
        Self.handleWindowControlCall(call, result: result, window: window)
      }
    }
  }

  // `NSWindow.zoom(_:)` computes its target frame from the title bar's
  // standard-button geometry, which doesn't exist on this borderless
  // (`.titled` removed) window — that mismatch can hang AppKit's zoom
  // animation. Track maximize state and animate the frame manually instead.
  private static var previousFrames: [ObjectIdentifier: NSRect] = [:]
  private static var maximizedWindows: Set<ObjectIdentifier> = []
  private static var miniaturizingWindows: Set<ObjectIdentifier> = []

  private static func handleWindowControlCall(_ call: FlutterMethodCall, result: @escaping FlutterResult, window: NSWindow) {
    let id = ObjectIdentifier(window)
    switch call.method {
    case "close":
      window.close()
      result(nil)
    case "minimize":
      window.miniaturize(nil)
      result(nil)
    case "maximize":
      if !maximizedWindows.contains(id) {
        previousFrames[id] = window.frame
        if let screenFrame = window.screen?.visibleFrame {
          window.setFrame(screenFrame, display: true, animate: true)
        }
        maximizedWindows.insert(id)
      }
      result(nil)
    case "unmaximize":
      if maximizedWindows.contains(id) {
        if let frame = previousFrames[id] {
          window.setFrame(frame, display: true, animate: true)
        }
        maximizedWindows.remove(id)
      }
      result(nil)
    case "isMaximized":
      result(maximizedWindows.contains(id))
    case "startDrag":
      // Simulate a mouse down event to start window dragging
      let currentEvent = NSApp.currentEvent!
      window.performDrag(with: currentEvent)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - NSWindowDelegate

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    return NSSize(
      width: max(frameSize.width, minimumWindowSize.width),
      height: max(frameSize.height, minimumWindowSize.height)
    )
  }

  func windowWillMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    Self.miniaturizingWindows.insert(ObjectIdentifier(window))
  }

  func windowDidMiniaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    Self.miniaturizingWindows.remove(ObjectIdentifier(window))
  }

  func windowDidDeminiaturize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    Self.miniaturizingWindows.remove(ObjectIdentifier(window))
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    let id = ObjectIdentifier(window)
    // During the minimize animation AppKit shrinks the window to the Dock;
    // enforcing the minimum size here fights that animation and can hang the UI.
    if window.isMiniaturized || Self.miniaturizingWindows.contains(id) {
      return
    }
    let currentFrame = window.frame
    let minFrame = NSRect(
      x: currentFrame.origin.x,
      y: currentFrame.origin.y,
      width: max(currentFrame.width, minimumWindowSize.width),
      height: max(currentFrame.height, minimumWindowSize.height)
    )
    if currentFrame.width < minimumWindowSize.width || currentFrame.height < minimumWindowSize.height {
      window.setFrame(minFrame, display: true, animate: false)
    }
  }
}
