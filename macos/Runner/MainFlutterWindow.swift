import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var bleBridge: BleBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Wire the CoreBluetooth bridge (Method + Event channels).
    bleBridge = BleBridge(messenger: flutterViewController.engine.binaryMessenger)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
