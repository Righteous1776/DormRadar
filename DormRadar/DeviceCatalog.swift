import Foundation

struct AdvertisedModel: Equatable, Sendable {
    let name: String
    let evidence: String
    let strength: Strength

    enum Strength: Int, Sendable {
        case systemName, broadcastName, productCode
    }

    init(name: String, evidence: String, strength: Strength = .productCode) {
        self.name = name
        self.evidence = evidence
        self.strength = strength
    }
}

struct DeviceCatalog: Decodable, Sendable {
    private struct Model: Decodable, Sendable {
        let name: String
        let code: String
        let brand: String
    }

    private let companies: [String: String]
    private let services: [String: String]
    private let miBeacon: [String: Model]
    private let govee: Set<String>
    private let appleHeadphones: [String: String]

    private struct AdditionalCodes: Decodable, Sendable {
        let android: [String: String]
        let apple: [String: String]
        let switchbot: [String: String]
        let shelly: [String: String]

        static let bundled: AdditionalCodes = {
            if let url = Bundle.main.url(forResource: "AdditionalModelCodes", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let codes = try? JSONDecoder().decode(AdditionalCodes.self, from: data) {
                return codes
            }
            return AdditionalCodes(android: [:], apple: [:], switchbot: [:], shelly: [:])
        }()
    }

    static let bundled: DeviceCatalog = {
        if let url = Bundle.main.url(forResource: "DeviceCatalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(DeviceCatalog.self, from: data) {
            return catalog
        }
        return DeviceCatalog(companies: [:], services: [:], miBeacon: [:], govee: [], appleHeadphones: [:])
    }()

    func companyName(_ id: UInt16) -> String? {
        switch id {
        case 0x004C: return "Apple"
        case 0x0006: return "Microsoft"
        case 0x0075: return "Samsung"
        case 0x00E0: return "Google"
        case 0x0059: return "Nordic Semiconductor"
        default: return companies[String(id)]
        }
    }

    func serviceName(_ uuid: String) -> String? { services[Self.shortUUID(uuid)] }

    func model(miBeaconPayload: Data?, broadcastName: String?, manufacturerData: Data? = nil,
               switchBotPayload: Data? = nil, hasBTHome: Bool = false,
               systemName: String? = nil) -> AdvertisedModel? {
        if let data = manufacturerData, data.count == 29 {
            let header = Array(data.prefix(7))
            if header.prefix(5).elementsEqual([0x4C, 0x00, 0x07, 0x19, 0x01]) {
                let id = UInt16(header[5]) | (UInt16(header[6]) << 8)
                if let name = appleHeadphones[String(id)] {
                    return AdvertisedModel(name: name, evidence: "Apple 配件广播型号代码")
                }
            }
        }
        if let data = miBeaconPayload, data.count >= 5 {
            let header = Array(data.prefix(5))
            let control = UInt16(header[0]) | (UInt16(header[1]) << 8)
            let id = UInt16(header[2]) | (UInt16(header[3]) << 8)
            let minimumLength = 5 + ((control & 0x0010) != 0 ? 6 : 0)
                                   + ((control & 0x0020) != 0 ? 1 : 0)
            if control >> 12 >= 2, control & 0x0080 == 0, data.count >= minimumLength,
               let model = miBeacon[String(id)] {
                return AdvertisedModel(name: "\(model.brand) \(model.name) · \(model.code)",
                                       evidence: "MiBeacon 广播产品编号")
            }
        }
        if let payload = switchBotPayload, let name = switchBotName(payload) {
            return AdvertisedModel(name: name, evidence: "SwitchBot 服务数据中的产品代码")
        }
        if let broadcastName {
            let name = broadcastName.uppercased()
            if hasBTHome, let model = AdditionalCodes.bundled.shelly[name] {
                return AdvertisedModel(name: model, evidence: "BTHome 服务与 Shelly 广播型号",
                                       strength: .broadcastName)
            }
            if let model = namedHardwareModel(name) {
                return AdvertisedModel(name: model, evidence: "广播名称中的厂商型号代码",
                                       strength: .broadcastName)
            }
            if let model = goveeModel(name) {
                return AdvertisedModel(name: model, evidence: "Govee 广播名称中的型号",
                                       strength: .broadcastName)
            }
        } else if let systemName, let model = namedHardwareModel(systemName.uppercased()) {
            return AdvertisedModel(name: model, evidence: "iOS 设备名称中的厂商型号代码",
                                   strength: .systemName)
        }
        return nil
    }

    private func namedHardwareModel(_ name: String) -> String? {
        let codes = AdditionalCodes.bundled
        if let model = codes.apple[name] ?? codes.android[name] { return model }
        if name.hasPrefix("SAMSUNG-SM-") {
            return codes.android[String(name.dropFirst("SAMSUNG-".count))]
        }
        return nil
    }

    private func switchBotName(_ payload: Data) -> String? {
        guard payload.count >= 2, let first = payload.first else { return nil }
        let codes = AdditionalCodes.bundled.switchbot
        if let name = codes[String(format: "%02x", first & 0x7F)] { return name }
        guard payload.count >= 6 else { return nil }
        for offset in [0, 1] {
            let code = payload.dropLast(offset).suffix(4).map { String(format: "%02x", $0) }.joined()
            if let name = codes[code] { return name }
        }
        return nil
    }

    private func goveeModel(_ name: String) -> String? {
        let code: String
        if name.hasPrefix("GOVEE_") || name.hasPrefix("GOVEE ") {
            code = String(name.dropFirst(6).prefix(5))
        } else if name.hasPrefix("GV") {
            code = "H" + String(name.dropFirst(2).prefix(4))
        } else {
            return nil
        }
        guard govee.contains(code) else { return nil }
        return "Govee \(code)"
    }

    static func shortUUID(_ raw: String) -> String {
        let uuid = raw.uppercased()
        if uuid.count == 36, uuid.hasPrefix("0000"),
           uuid.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            return String(uuid.dropFirst(4).prefix(4))
        }
        return uuid
    }
}
