import SwiftUI
import CoreLocation

struct LocatedCity: Hashable, Sendable {
    let name: String
    let code: String
    let id: String
    static func resolve(address: APIValue, province: String?, city: String?, country: String?) -> LocatedCity? {
        guard country == "CN", let city else { return nil }
        func normalized(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "市", with: "") }
        let provinces = address["res"]["res"].values ?? []
        let matches = provinces.filter { province == nil || normalized($0["name"].text ?? "") == normalized(province!) }
            .flatMap { $0["cityList"].values ?? [] }
            .filter { normalized($0["name"].text ?? "") == normalized(city) }
        guard matches.count == 1, let item = matches.first, let name = item["name"].text,
              let code = item["code"].text, let id = item["id"].text else { return nil }
        return LocatedCity(name: name, code: code, id: id)
    }
}

extension LocationPermissionStore {
    func locate() {
        guard manualCity == nil, !usesAllRegions else { return }
        if ProcessInfo.processInfo.arguments.contains("--uitesting") && !ProcessInfo.processInfo.arguments.contains("--uitesting-live-location") {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-location") {
                region = LocatedCity(name: "上海市", code: "310000", id: "774")
            }
            return
        }
        refresh()
        guard !isLocating else { return }
        if region != nil, Date.now.timeIntervalSince(lastLocatedAt) < 300 { return }
        errorMessage = nil
        switch status {
        case .notDetermined: wantsLocation = true; request()
        case .authorizedAlways, .authorizedWhenInUse:
            wantsLocation = false; isLocating = true
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.requestLocation()
        default: region = nil
        }
    }
    func resolve(_ location: CLLocation) {
        Task { @MainActor in
            defer { isLocating = false }
            do {
                let places = try await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
                guard let place = places.first else { throw APIError.invalidResponse }
                let address = try await BusinessAPI().request("/address")
                guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
                guard let city = LocatedCity.resolve(address: address, province: place.administrativeArea,
                    city: place.locality ?? place.administrativeArea, country: place.isoCountryCode) else {
                    region = nil; errorMessage = "当前地区暂无城市数据，显示全部地区。"; return
                }
                region = city; lastLocatedAt = .now
            } catch {
                errorMessage = "暂时无法获取所在城市，可重试定位。"
            }
        }
    }
}

struct CityLocationBar: View {
    @Environment(LocationPermissionStore.self) private var location
    @State private var choosingCity = false
    var body: some View {
        HStack {
            Button { choosingCity = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: location.manualCity == nil && !location.usesAllRegions ? "location" : "mappin.and.ellipse")
                    Text(location.selectedRegion?.name ?? "全部地区")
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
            }.foregroundStyle(.primary).accessibilityIdentifier("city.choose")
            Spacer()
            if location.isLocating, location.manualCity == nil, !location.usesAllRegions { ProgressView() }
        }.font(.subheadline)
            .sheet(isPresented: $choosingCity) { CityPickerSheet() }
        if location.manualCity == nil, !location.usesAllRegions, let message = location.errorMessage {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CityPickerSheet: View {
    @Environment(LocationPermissionStore.self) private var location
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var search = ""
    @State private var cities: [LocatedCity] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    private var filtered: [LocatedCity] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? cities : cities.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if location.status == .denied {
                            location.manualCity = nil; location.usesAllRegions = false; location.wantsLocation = true
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        } else { location.useCurrentCity(); dismiss() }
                    } label: { Label("使用当前位置", systemImage: "location") }
                        .accessibilityIdentifier("city.current")
                    Button { location.selectAllRegions(); dismiss() } label: {
                        HStack { Text("全部地区"); Spacer(); if location.usesAllRegions { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("city.all")
                } footer: { Text("优先展示所选地区，仍可浏览其他地区。") }
                Section("城市") {
                    ForEach(filtered, id: \.code) { city in
                        Button { location.selectCity(city); dismiss() } label: {
                            HStack {
                                Text(city.name).foregroundStyle(.primary)
                                Spacer()
                                if location.selectedRegion?.code == city.code { Image(systemName: "checkmark") }
                            }
                        }.accessibilityIdentifier("city.option.\(city.code)")
                    }
                    if isLoading { ProgressView() }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                        Button("重试") { Task { await load() } }
                    } else if !isLoading, filtered.isEmpty {
                        Text("没有找到城市").foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("选择地区").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "搜索城市")
                .stableSearchToolbar()
                .toolbar { ToolbarItem(placement: .topBarLeading) { ModalCloseButton() } }
                .task { await load() }
        }
    }
    private func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await account.api.request("/address")
            guard let provinces = data["res"]["res"].values else { throw APIError.invalidResponse }
            var codes = Set<String>()
            cities = provinces.flatMap { $0["cityList"].values ?? [] }.compactMap { item in
                guard let name = item["name"].text, let code = item["code"].text,
                      let id = item["id"].text, codes.insert(code).inserted else { return nil }
                return LocatedCity(name: name, code: code, id: id)
            }
        } catch { errorMessage = "暂时无法加载城市，请重试。" }
    }
}

/// One scrolling/navigation structure for both activity browsers. Filters stay above the vertical results.
struct ActivityBrowseLayout<Filters: View, Rows: View>: View {
    let identity: AnyHashable
    let scrollIdentifier: String
    let itemCount: Int
    let canLoadMore: Bool
    let isLoading: Bool
    var refresh: () async -> Void
    var loadMore: () async -> Void
    var onScroll: () -> Void = {}
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var rows: () -> Rows
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) { filters() }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 8)
                .background(Design.canvas)
            ScrollView {
                LazyVStack(spacing: 13) { rows() }
                    .frame(maxWidth: .infinity).padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
            }.id(identity)
                .accessibilityIdentifier(scrollIdentifier)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) { onScroll() }
                })
                .refreshable { await refresh() }
                .automaticPagination(itemCount: itemCount, canLoadMore: canLoadMore, isLoading: isLoading) { await loadMore() }
        }.background(Design.canvas)
    }
}
