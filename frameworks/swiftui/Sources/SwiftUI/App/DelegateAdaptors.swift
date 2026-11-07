import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

#if canImport(ObjectiveC)
@MainActor
public protocol _ApplicationDelegateConstruction {}
#else
@MainActor
public protocol _ApplicationDelegateConstruction { init() }
#endif

@MainActor
private func makeDelegate<D: NSObject & _ApplicationDelegateConstruction>(_ type: D.Type) -> D {
    #if canImport(ObjectiveC)
    return type.init()
    #else
    return D()
    #endif
}

@MainActor
open class UIApplication {
    public enum State: Int, Sendable {
        case active
        case inactive
        case background
    }

    public struct LaunchOptionsKey: Hashable, RawRepresentable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
    }

    public struct OpenURLOptionsKey: Hashable, RawRepresentable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public static let shared = UIApplication()
    public internal(set) var applicationState: State = .background
    public weak var delegate: (any UIApplicationDelegate)?

    init() {}
}

@MainActor
public protocol UIApplicationDelegate: AnyObject, _ApplicationDelegateConstruction {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func applicationWillResignActive(_ application: UIApplication)
    func applicationDidEnterBackground(_ application: UIApplication)
    func applicationWillEnterForeground(_ application: UIApplication)
    func applicationWillTerminate(_ application: UIApplication)
}

extension UIApplicationDelegate {
    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }
    public func applicationDidBecomeActive(_ application: UIApplication) {}
    public func applicationWillResignActive(_ application: UIApplication) {}
    public func applicationDidEnterBackground(_ application: UIApplication) {}
    public func applicationWillEnterForeground(_ application: UIApplication) {}
    public func applicationWillTerminate(_ application: UIApplication) {}
}

@MainActor
open class NSApplication {
    public static let shared = NSApplication()
    public weak var delegate: (any NSApplicationDelegate)?
    public internal(set) var isActive = false
    init() {}
}

@MainActor
public protocol NSApplicationDelegate: AnyObject, _ApplicationDelegateConstruction {
    func applicationWillFinishLaunching(_ notification: Notification)
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationDidBecomeActive(_ notification: Notification)
    func applicationWillResignActive(_ notification: Notification)
    func applicationDidHide(_ notification: Notification)
    func applicationDidUnhide(_ notification: Notification)
    func applicationWillTerminate(_ notification: Notification)
    func application(_ application: NSApplication, open urls: [URL])
}

extension NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {}
    public func applicationDidFinishLaunching(_ notification: Notification) {}
    public func applicationDidBecomeActive(_ notification: Notification) {}
    public func applicationWillResignActive(_ notification: Notification) {}
    public func applicationDidHide(_ notification: Notification) {}
    public func applicationDidUnhide(_ notification: Notification) {}
    public func applicationWillTerminate(_ notification: Notification) {}
    public func application(_ application: NSApplication, open urls: [URL]) {}
}

package enum AppLifecycleEvent: Equatable {
    case didFinishLaunching
    case willEnterForeground
    case didBecomeActive
    case willResignActive
    case didEnterBackground
    case willTerminate
    case openURLs([URL])
}

@MainActor
package protocol AppDelegateAdaptorProtocol {
    func _deliver(_ event: AppLifecycleEvent)
}

package final class DelegateBox<D>: @unchecked Sendable {
    package let delegate: D
    init(_ d: D) { delegate = d }
}

@MainActor
@propertyWrapper
public struct UIApplicationDelegateAdaptor<DelegateType: NSObject & UIApplicationDelegate>: DynamicProperty {
    package let box: DelegateBox<DelegateType>

    public init(_ delegateType: DelegateType.Type = DelegateType.self) {
        box = DelegateBox(makeDelegate(delegateType))
    }

    public var wrappedValue: DelegateType { box.delegate }
}

extension UIApplicationDelegateAdaptor where DelegateType: ObservableObject {
    public var projectedValue: ObservedObject<DelegateType>.Wrapper { ObservedObject(wrappedValue: box.delegate).projectedValue }
}

extension UIApplicationDelegateAdaptor: AppDelegateAdaptorProtocol {
    package func _deliver(_ event: AppLifecycleEvent) {
        let d = box.delegate, app = UIApplication.shared
        app.delegate = d
        switch event {
        case .didFinishLaunching: _ = d.application(app, didFinishLaunchingWithOptions: nil)
        case .willEnterForeground: d.applicationWillEnterForeground(app)
        case .didBecomeActive: d.applicationDidBecomeActive(app)
        case .willResignActive: d.applicationWillResignActive(app)
        case .didEnterBackground: d.applicationDidEnterBackground(app)
        case .willTerminate: d.applicationWillTerminate(app)
        case .openURLs: break
        }
    }
}

@MainActor
@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType: NSObject & NSApplicationDelegate>: DynamicProperty {
    package let box: DelegateBox<DelegateType>

    public init(_ delegateType: DelegateType.Type = DelegateType.self) {
        box = DelegateBox(makeDelegate(delegateType))
    }

    public var wrappedValue: DelegateType { box.delegate }
}

extension NSApplicationDelegateAdaptor: AppDelegateAdaptorProtocol {
    package func _deliver(_ event: AppLifecycleEvent) {
        let d = box.delegate, app = NSApplication.shared
        app.delegate = d
        let n = Notification(name: Notification.Name("OpenViewsApplicationLifecycle"))
        switch event {
        case .didFinishLaunching:
            d.applicationWillFinishLaunching(n)
            d.applicationDidFinishLaunching(n)
        case .willEnterForeground: d.applicationDidUnhide(n)
        case .didBecomeActive:
            app.isActive = true
            d.applicationDidBecomeActive(n)
        case .willResignActive:
            app.isActive = false
            d.applicationWillResignActive(n)
        case .didEnterBackground: d.applicationDidHide(n)
        case .willTerminate: d.applicationWillTerminate(n)
        case .openURLs(let urls): d.application(app, open: urls)
        }
    }
}

extension UIApplication.State {
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        }
    }
}
