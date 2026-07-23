import Cocoa
import FlutterMacOS

class CroplooFlutterViewController: FlutterViewController {
  override var acceptsFirstResponder: Bool { true }
}

class MainFlutterWindow: NSWindow {
  // Without `.titled`, AppKit defaults a borderless window to never
  // becoming key — which means none of its text fields could ever
  // receive keyboard focus/input.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
    let result = super.makeFirstResponder(responder)
    // Ensure the Flutter view controller can become first responder
    if let flutterVC = contentViewController as? CroplooFlutterViewController {
      _ = flutterVC.acceptsFirstResponder
    }
    return result
  }

  override func awakeFromNib() {
    let flutterViewController = CroplooFlutterViewController()
    let windowFrame = self.frame

    // Hide the *appearance* of the native title bar and traffic lights —
    // custom window controls are rendered in Flutter instead — without
    // actually removing `.titled` from the style mask. Confirmed by
    // testing: removing `.titled` (making the window fully borderless)
    // breaks keyboard input app-wide, because AppKit only grants key-window
    // status to non-titled windows if the app also implements full
    // NSTextInputClient plumbing itself; Flutter's text fields rely on
    // AppKit's normal key-window/first-responder chain, which a titled
    // window gets for free. `fullSizeContentView` + transparent/hidden
    // title bar + hidden buttons already gives a fully custom, chrome-less
    // look while keeping the window titled under the hood.
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Minimum size: the sidebar with all nav items needs at least this much
    // vertical space; the dashboard also becomes cramped below 1600x900.
    self.minSize = NSSize(width: 1600, height: 900)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    
    // Ensure the window becomes key and accepts keyboard input
    DispatchQueue.main.async {
      self.makeKeyAndOrderFront(nil)
      self.becomeKey()
    }
  }
}
