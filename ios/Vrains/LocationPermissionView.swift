import SwiftUI
import CoreLocation
import Observation

@Observable @MainActor
final class LocationPermissionStore: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    let geocoder = CLGeocoder()
    var region: LocatedCity?
    var manualCity: LocatedCity?
    var usesAllRegions = false
    var selectedRegion: LocatedCity? { usesAllRegions ? nil : (manualCity ?? region) }
    func selectCity(_ city: LocatedCity) { manualCity = city; usesAllRegions = false }
    func selectAllRegions() { manualCity = nil; usesAllRegions = true }
    func useCurrentCity() { manualCity = nil; usesAllRegions = false; lastLocatedAt = .distantPast; locate() }
    var isLocating = false
    var errorMessage: String?
    var lastLocatedAt = Date.distantPast
    var wantsLocation = false
    private(set) var status: CLAuthorizationStatus = .notDetermined
    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
    }
    var title: String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: "已允许使用位置"
        case .denied: "位置权限已关闭"
        case .restricted: "位置权限受系统限制"
        default: "允许使用位置"
        }
    }
    func request() { manager.requestWhenInUseAuthorization() }
    func refresh() { status = manager.authorizationStatus }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.status = status
            if status == .denied || status == .restricted { self.region = nil; self.wantsLocation = false; self.isLocating = false }
            else if self.wantsLocation { self.locate() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in self?.resolve(location) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isLocating = false
            self?.errorMessage = "暂时无法获取所在城市，可重试定位。"
        }
    }
}

struct LocationPermissionView: View {
    @Environment(LocationPermissionStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            switch store.status {
            case .notDetermined:
                Button { store.request() } label: { permissionRow("未设置") }
                    .accessibilityIdentifier("location.request")
            case .denied:
                Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: { permissionRow("未允许") }
                    .accessibilityLabel("前往设置开启位置权限")
            case .restricted:
                permissionRow("受限")
            default:
                Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: { permissionRow("已允许") }
            }
        }.onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
    }
    private func permissionRow(_ value: String) -> some View {
        HStack {
            Text("位置权限").foregroundStyle(Design.ink)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
