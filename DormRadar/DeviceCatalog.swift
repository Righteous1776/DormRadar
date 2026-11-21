import Foundation

struct AdvertisedModel: Equatable, Sendable {
    let name: String
    let evidence: String
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

    func model(miBeaconPayload: Data?, broadcastName: String?,
               manufacturerData: Data? = nil) -> AdvertisedModel? {
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
        guard let name = broadcastName?.uppercased() else { return nil }
        let code: String
        if name.hasPrefix("GOVEE_") || name.hasPrefix("GOVEE ") {
            code = String(name.dropFirst(6).prefix(5))
        } else if name.hasPrefix("GV") {
            code = "H" + String(name.dropFirst(2).prefix(4))
        } else {
            return nil
        }
        guard govee.contains(code) else { return nil }
        return AdvertisedModel(name: "Govee \(code)", evidence: "Govee 广播名称中的型号")
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
