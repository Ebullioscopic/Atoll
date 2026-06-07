@MainActor
protocol AudioProcessMonitoring: AnyObject {
    var activeApps: [AudioApp] { get }
    var onAppsChanged: (([AudioApp]) -> Void)? { get set }

    func start()
    func stop()
}
