import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // 保持强引用，防止触发对象被释放导致系统撤销授权请求
  private static var permissionBrowser: NWBrowser?
  private static var permissionConnection: NWConnection?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Self.triggerLocalNetworkPermission()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 主动触发 iOS“本地网络”授权弹窗。
  ///
  /// 背景：Dart 的 RawDatagramSocket 走 BSD socket，在部分 iOS 版本
  /// （特别是 16.0.x）上不会被系统注册为“局域网访问尝试”——
  /// 系统既不弹授权框，也不会把 App 列入 设置>隐私>本地网络，
  /// 同时静默拦截 App 的出站局域网流量（表现为只能收不能发）。
  ///
  /// Network framework 的 Bonjour 浏览是 Apple 官方推荐的触发方式，
  /// 调用后系统立即弹窗，并在设置中生成对应的开关。
  private static func triggerLocalNetworkPermission() {
    // 1) Bonjour 浏览（需要 Info.plist 的 NSBonjourServices 声明）
    let descriptor = NWBrowser.Descriptor.bonjour(type: "_lanfile._tcp", domain: nil)
    let browser = NWBrowser(for: descriptor, using: NWParameters())
    browser.stateUpdateHandler = { _ in }
    browser.browseResultsChangedHandler = { _, _ in }
    browser.start(queue: .global(qos: .utility))
    permissionBrowser = browser

    // 2) 双保险：建立一个指向广播地址的 UDP 连接
    let connection = NWConnection(host: "255.255.255.255", port: 9, using: .udp)
    connection.stateUpdateHandler = { _ in }
    connection.start(queue: .global(qos: .utility))
    permissionConnection = connection
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
