//
//  TidepoolClient.swift
//  Blipper
//
//  Minimal Tidepool API client, mirroring tidepool_pull.py:
//  Basic-auth login returns a session token, then /data/{userid} is queried for cbg records.
//

import Foundation
import OSLog

nonisolated enum TidepoolError: LocalizedError {
    case invalidCredentials
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Login failed. Check the email and password."
        case .http(let code): "Tidepool request failed (\(code))."
        case .badResponse: "Unexpected response from Tidepool."
        }
    }
}

nonisolated struct TidepoolSession: Sendable {
    let token: String
    let userID: String
}

nonisolated struct TidepoolClient: Sendable {
    static let base = URL(string: "https://api.tidepool.org")!
    private static let mmolToMgdl = 18.01559

    var urlSession: URLSession = .shared

    // MARK: Login

    func login(email: String, password: String) async throws -> TidepoolSession {
        let auth = Data("\(email):\(password)".utf8).base64EncodedString()
        var request = URLRequest(url: Self.base.appending(path: "auth/login"))
        request.httpMethod = "POST"
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TidepoolError.badResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw TidepoolError.invalidCredentials
        default: throw TidepoolError.http(http.statusCode)
        }
        guard let token = http.value(forHTTPHeaderField: "X-Tidepool-Session-Token"),
              let body = try? JSONDecoder().decode(LoginBody.self, from: data) else {
            throw TidepoolError.badResponse
        }
        return TidepoolSession(token: token, userID: body.userid)
    }

    // MARK: Data

    /// CGM (`cbg`) readings in `interval`, converted to mg/dL and sorted ascending.
    func cgmReadings(session: TidepoolSession, in interval: DateInterval) async throws -> [GlucoseReading] {
        var components = URLComponents(
            url: Self.base.appending(path: "data/\(session.userID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "type", value: "cbg"),
            URLQueryItem(name: "startDate", value: Self.queryFormatter.string(from: interval.start)),
            URLQueryItem(name: "endDate", value: Self.queryFormatter.string(from: interval.end)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(session.token, forHTTPHeaderField: "X-Tidepool-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TidepoolError.badResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw TidepoolError.invalidCredentials
        default: throw TidepoolError.http(http.statusCode)
        }
        let records = try JSONDecoder().decode([Record].self, from: data)
        return records
            .compactMap { record -> GlucoseReading? in
                guard record.type == "cbg", let value = record.value,
                      let timestamp = Self.parseTime(record.time) else { return nil }
                let mgdl = (record.units ?? "").lowercased().hasPrefix("mmol")
                    ? (value * Self.mmolToMgdl).rounded()
                    : value.rounded()
                return GlucoseReading(timestamp: timestamp, value: mgdl)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: Devices

    /// Devices from `pumpSettings` and `cgmSettings` records since `since`, joined to their
    /// `upload` (data set) records, which are fetched without a date floor because an uploader
    /// like Loop creates its data set once and keeps appending to it for months.
    func devices(session: TidepoolSession, since: Date) async throws -> [DeviceInfo] {
        async let settingsData = fetchData(session: session, types: "pumpSettings,cgmSettings", since: since)
        async let uploadsData = fetchData(session: session, types: "upload", since: nil)
        let payloads = try await [settingsData, uploadsData]

        var records: [DeviceRecord] = []
        for data in payloads {
            do {
                let lenient = try JSONDecoder().decode([LenientRecord<DeviceRecord>].self, from: data)
                records += lenient.compactMap(\.record)
                let skipped = lenient.filter { $0.record == nil }
                if !skipped.isEmpty {
                    Self.log.notice("devices: skipped \(skipped.count) records: \(skipped.compactMap(\.failure).joined(separator: "; "), privacy: .public)")
                }
            } catch {
                Self.log.error("devices: decode failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        }
        let counts = Dictionary(grouping: records, by: \.type).mapValues(\.count)
        let devices = Self.mergeDevices(records, since: since)
        // Counts only; never log record contents.
        Self.log.notice("devices: \(records.count) records \(counts.description, privacy: .public) → \(devices.count) devices, \(devices.filter { $0.pumpSettings != nil }.count) with pump settings, \(devices.filter { $0.cgmSettings != nil }.count) with CGM settings")
        return devices
    }

    // MARK: Therapy

    /// Boluses, basal, carbs, and fingersticks in `interval`. The query starts a day early so a
    /// basal segment that began before the interval but runs into it is not missed.
    func therapy(session: TidepoolSession, in interval: DateInterval) async throws -> TherapyData {
        let query = DateInterval(start: interval.start.addingTimeInterval(-86_400), end: interval.end)
        let data = try await fetchData(session: session, types: "bolus,basal,wizard,food,smbg", in: query)
        let records = try Self.decodeLenient(TherapyRecord.self, from: data, what: "therapy")
        let result = Self.therapyData(from: records).clipped(to: interval)
        // Counts by category only; never record contents.
        let bolusKinds = Dictionary(grouping: records.filter { $0.type == "bolus" }) { $0.subType ?? "none" }.mapValues(\.count)
        let basalKinds = Dictionary(grouping: records.filter { $0.type == "basal" }) { $0.deliveryType ?? "none" }.mapValues(\.count)
        Self.log.notice("therapy: \(records.count) records → \(result.boluses.count) boluses \(bolusKinds.description, privacy: .public), \(result.basal.count) basal segments \(basalKinds.description, privacy: .public), \(result.carbs.count) carb entries, \(result.fingersticks.count) fingersticks")
        return result
    }

    /// Fingerstick (`smbg`) readings in `interval`, converted to mg/dL and sorted ascending.
    func fingersticks(session: TidepoolSession, in interval: DateInterval) async throws -> [BGMReading] {
        let data = try await fetchData(session: session, types: "smbg", in: interval)
        let records = try Self.decodeLenient(TherapyRecord.self, from: data, what: "smbg")
        let readings = Self.therapyData(from: records).fingersticks.filter { interval.contains($0.timestamp) }
        Self.log.notice("smbg: \(records.count) records → \(readings.count) fingersticks")
        return readings
    }

    private static func therapyData(from records: [TherapyRecord]) -> TherapyData {
        var data = TherapyData()
        var wizardCarbTimes: [Date] = []
        for record in records {
            guard let time = parseTime(record.time) else { continue }
            let scale = (record.units ?? "").lowercased().hasPrefix("mmol") ? mmolToMgdl : 1
            switch record.type {
            case "bolus":
                let normal = record.normal ?? 0
                let extended = record.extended ?? 0
                guard normal + extended > 0 else { continue }
                data.boluses.append(InsulinBolus(
                    timestamp: time, normal: normal, extended: extended,
                    duration: TimeInterval(record.duration ?? 0) / 1000,
                    automated: record.subType == "automated"
                ))
            case "basal":
                guard let duration = record.duration, duration > 0 else { continue }
                let kind: BasalSegment.Kind
                switch record.deliveryType {
                case "temp": kind = .temp
                case "automated": kind = .automated
                case "suspend": kind = .suspend
                default: kind = .scheduled
                }
                data.basal.append(BasalSegment(
                    start: time, duration: TimeInterval(duration) / 1000,
                    rate: kind == .suspend ? 0 : (record.rate ?? 0), kind: kind
                ))
            case "wizard":
                if let grams = record.carbInput, grams > 0 {
                    data.carbs.append(CarbEntry(timestamp: time, grams: grams))
                    wizardCarbTimes.append(time)
                }
            case "food":
                if let grams = record.nutrition?.carbohydrate?.net, grams > 0 {
                    data.carbs.append(CarbEntry(timestamp: time, grams: grams))
                }
            case "smbg":
                guard let value = record.value else { continue }
                let source: BGMReading.Source = record.subType == "manual" ? .manual : .meter
                data.fingersticks.append(BGMReading(timestamp: time, value: (value * scale).rounded(), source: source))
            default:
                continue
            }
        }
        // A pump's wizard entry and a logged food entry for the same meal would double count.
        if !wizardCarbTimes.isEmpty {
            data.carbs.removeAll { entry in
                !wizardCarbTimes.contains(entry.timestamp)
                    && wizardCarbTimes.contains { abs($0.timeIntervalSince(entry.timestamp)) < 120 }
            }
        }
        data.boluses.sort { $0.timestamp < $1.timestamp }
        data.basal.sort { $0.start < $1.start }
        data.carbs.sort { $0.timestamp < $1.timestamp }
        data.fingersticks.sort { $0.timestamp < $1.timestamp }
        return data
    }

    private static let log = Logger(subsystem: "com.PickleTron.Blipper", category: "tidepool")

    /// Decodes a record list, dropping (and counting) records that don't fit `R`.
    private static func decodeLenient<R: Decodable>(_ type: R.Type, from data: Data, what: String) throws -> [R] {
        do {
            let lenient = try JSONDecoder().decode([LenientRecord<R>].self, from: data)
            let skipped = lenient.filter { $0.record == nil }
            if !skipped.isEmpty {
                log.notice("\(what, privacy: .public): skipped \(skipped.count) records: \(skipped.compactMap(\.failure).joined(separator: "; "), privacy: .public)")
            }
            return lenient.compactMap(\.record)
        } catch {
            log.error("\(what, privacy: .public): decode failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// GET /data/{userid} for the given comma-separated `types`, optionally from `since` to now.
    private func fetchData(session: TidepoolSession, types: String, since: Date?) async throws -> Data {
        try await fetchData(session: session, types: types, in: since.map { DateInterval(start: $0, end: Date()) })
    }

    private func fetchData(session: TidepoolSession, types: String, in interval: DateInterval?) async throws -> Data {
        var components = URLComponents(
            url: Self.base.appending(path: "data/\(session.userID)"),
            resolvingAgainstBaseURL: false
        )!
        var items = [URLQueryItem(name: "type", value: types)]
        if let interval {
            items.append(URLQueryItem(name: "startDate", value: Self.queryFormatter.string(from: interval.start)))
            items.append(URLQueryItem(name: "endDate", value: Self.queryFormatter.string(from: interval.end)))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(session.token, forHTTPHeaderField: "X-Tidepool-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TidepoolError.badResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw TidepoolError.invalidCredentials
        default: throw TidepoolError.http(http.statusCode)
        }
    }

    /// Upload records older than `since` only serve to resolve settings records to a device;
    /// they are not listed on their own.
    private static func mergeDevices(_ records: [DeviceRecord], since: Date) -> [DeviceInfo] {
        struct Partial {
            var upload: DeviceRecord?
            var pump: DeviceRecord?
            var cgm: DeviceRecord?
        }
        // Settings records carry no deviceId; they reference their upload (data set) by uploadId,
        // which matches the upload record's `uploadId` on older data sets and its `id` on newer ones.
        var uploadByDataSet: [String: DeviceRecord] = [:]
        for record in records where record.type == "upload" {
            for key in [record.uploadId, record.id].compactMap({ $0 }) {
                uploadByDataSet[key] = record
            }
        }
        func deviceKey(_ record: DeviceRecord) -> String? {
            if let deviceID = record.deviceId { return deviceID }
            if let uploadID = record.uploadId, let upload = uploadByDataSet[uploadID] {
                return upload.deviceId ?? upload.deviceSerialNumber ?? uploadID
            }
            // No upload record for this data set (Loop's, for one). Key by device kind so a
            // pod or sensor swap doesn't list as a new device; the newest record wins.
            let kind = [record.manufacturers?.first, record.model ?? record.name].compactMap { $0 }
            return kind.isEmpty ? (record.serialNumber ?? record.uploadId) : kind.joined(separator: " ")
        }

        var partials: [String: Partial] = [:]
        for record in records {
            guard let id = deviceKey(record), let time = parseTime(record.time) else { continue }
            if record.type == "upload" && time < since { continue }
            var partial = partials[id] ?? Partial()
            func newer(_ existing: DeviceRecord?) -> Bool {
                guard let existing, let existingTime = parseTime(existing.time) else { return true }
                return time > existingTime
            }
            switch record.type {
            case "upload": if newer(partial.upload) { partial.upload = record }
            case "pumpSettings": if newer(partial.pump) { partial.pump = record }
            case "cgmSettings": if newer(partial.cgm) { partial.cgm = record }
            default: continue
            }
            partials[id] = partial
        }

        return partials.map { id, partial in
            let upload = partial.upload, pump = partial.pump, cgm = partial.cgm
            let lastUpload: Date? = [upload, pump, cgm]
                .compactMap { $0.flatMap { parseTime($0.time) } }
                .max()
            let manufacturer: String? = upload?.deviceManufacturers?.first
                ?? pump?.manufacturers?.first
                ?? cgm?.manufacturers?.first
            let model: String? = upload?.deviceModel ?? pump?.model ?? cgm?.model ?? pump?.name ?? cgm?.name
            let serial: String? = upload?.deviceSerialNumber ?? pump?.serialNumber ?? cgm?.serialNumber
            return DeviceInfo(
                id: id,
                manufacturer: manufacturer,
                model: model,
                serialNumber: serial,
                lastUpload: lastUpload,
                tags: upload?.deviceTags ?? [],
                pumpSettings: pump.flatMap(pumpSettings(from:)),
                cgmSettings: cgm.flatMap(cgmSettings(from:))
            )
        }
        .sorted { ($0.lastUpload ?? .distantPast) > ($1.lastUpload ?? .distantPast) }
    }

    private static func pumpSettings(from record: DeviceRecord) -> PumpSettings? {
        guard let updated = parseTime(record.time) else { return nil }
        let bgInMmol = (record.units?.bg ?? "").lowercased().hasPrefix("mmol")
        let bgScale = bgInMmol ? mmolToMgdl : 1

        func entries(_ list: [WireScheduleEntry]?) -> [ScheduleEntry] {
            (list ?? []).compactMap { entry in
                entry.amount.map { ScheduleEntry(start: TimeInterval(entry.start ?? 0) / 1000, value: $0) }
            }
            .sorted { $0.start < $1.start }
        }
        func rates(_ list: [WireScheduleEntry]?) -> [ScheduleEntry] {
            (list ?? []).compactMap { entry in
                entry.rate.map { ScheduleEntry(start: TimeInterval(entry.start ?? 0) / 1000, value: $0) }
            }
            .sorted { $0.start < $1.start }
        }
        /// Some pumps key these by schedule name; pick the active one, else the first.
        func pick(_ flat: [WireScheduleEntry]?, _ keyed: [String: [WireScheduleEntry]]?) -> [WireScheduleEntry]? {
            if let flat { return flat }
            guard let keyed else { return nil }
            if let active = record.activeSchedule, let match = keyed[active] { return match }
            return keyed.sorted { $0.key < $1.key }.first?.value
        }

        let basal = (record.basalSchedules ?? [:]).mapValues(rates)
        let sensitivities = entries(pick(record.insulinSensitivity, record.insulinSensitivities))
            .map { ScheduleEntry(start: $0.start, value: ($0.value * bgScale).rounded()) }
        let targets = (pick(record.bgTarget, record.bgTargets) ?? []).map { entry in
            TargetEntry(
                start: TimeInterval(entry.start ?? 0) / 1000,
                low: entry.low.map { ($0 * bgScale).rounded() },
                high: entry.high.map { ($0 * bgScale).rounded() },
                target: entry.target.map { ($0 * bgScale).rounded() }
            )
        }
        .sorted { $0.start < $1.start }

        return PumpSettings(
            updated: updated,
            activeSchedule: record.activeSchedule,
            basalSchedules: basal,
            carbRatios: entries(pick(record.carbRatio, record.carbRatios)),
            insulinSensitivities: sensitivities,
            targets: targets
        )
    }

    private static func cgmSettings(from record: DeviceRecord) -> CGMSettings? {
        guard let updated = parseTime(record.time) else { return nil }
        let inMmol = (record.units?.bg ?? record.unitsString ?? "").lowercased().hasPrefix("mmol")
        let scale = inMmol ? mmolToMgdl : 1
        func level(_ alert: WireAlert?) -> Double? {
            guard let alert, alert.enabled ?? true, let level = alert.level else { return nil }
            return (level * scale).rounded()
        }
        return CGMSettings(
            updated: updated,
            transmitterID: record.transmitterId,
            lowAlert: level(record.lowAlerts),
            highAlert: level(record.highAlerts)
        )
    }

    // MARK: Wire formats

    private struct LoginBody: Decodable {
        let userid: String
    }

    /// Decodes one record, or notes why it couldn't be, so one odd record doesn't sink the list.
    private struct LenientRecord<R: Decodable>: Decodable {
        let record: R?
        /// Key path of the problem, never a value.
        let failure: String?

        init(from decoder: Decoder) throws {
            do {
                record = try R(from: decoder)
                failure = nil
            } catch let error as DecodingError {
                record = nil
                switch error {
                case .keyNotFound(let key, _): failure = "missing \(key.stringValue)"
                case .valueNotFound(_, let context): failure = "null \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                case .typeMismatch(_, let context): failure = "type \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                case .dataCorrupted(let context): failure = "corrupt \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                @unknown default: failure = "unknown"
                }
            }
        }
    }

    /// Superset of the fields on upload, pumpSettings and cgmSettings records; everything optional.
    private struct DeviceRecord: Decodable {
        let type: String
        let time: String
        let id: String?
        let deviceId: String?
        let uploadId: String?
        let name: String?
        // upload
        let deviceManufacturers: [String]?
        let deviceModel: String?
        let deviceSerialNumber: String?
        let deviceTags: [String]?
        // pumpSettings / cgmSettings
        let manufacturers: [String]?
        let model: String?
        let serialNumber: String?
        let activeSchedule: String?
        let units: WireUnits?
        let basalSchedules: [String: [WireScheduleEntry]]?
        let carbRatio: [WireScheduleEntry]?
        let carbRatios: [String: [WireScheduleEntry]]?
        let insulinSensitivity: [WireScheduleEntry]?
        let insulinSensitivities: [String: [WireScheduleEntry]]?
        let bgTarget: [WireScheduleEntry]?
        let bgTargets: [String: [WireScheduleEntry]]?
        let transmitterId: String?
        let lowAlerts: WireAlert?
        let highAlerts: WireAlert?

        /// cgmSettings sometimes carries `units` as a plain string rather than an object.
        var unitsString: String? { units?.raw }

        private enum CodingKeys: String, CodingKey {
            case type, time, id, deviceId, uploadId, name
            case deviceManufacturers, deviceModel, deviceSerialNumber, deviceTags
            case manufacturers, model, serialNumber, activeSchedule, units, basalSchedules
            case carbRatio, carbRatios, insulinSensitivity, insulinSensitivities, bgTarget, bgTargets
            case transmitterId, lowAlerts, highAlerts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            time = try c.decode(String.self, forKey: .time)
            id = try? c.decode(String.self, forKey: .id)
            deviceId = try? c.decode(String.self, forKey: .deviceId)
            uploadId = try? c.decode(String.self, forKey: .uploadId)
            name = try? c.decode(String.self, forKey: .name)
            deviceManufacturers = try? c.decode([String].self, forKey: .deviceManufacturers)
            deviceModel = try? c.decode(String.self, forKey: .deviceModel)
            deviceSerialNumber = try? c.decode(String.self, forKey: .deviceSerialNumber)
            deviceTags = try? c.decode([String].self, forKey: .deviceTags)
            manufacturers = try? c.decode([String].self, forKey: .manufacturers)
            model = try? c.decode(String.self, forKey: .model)
            serialNumber = try? c.decode(String.self, forKey: .serialNumber)
            activeSchedule = try? c.decode(String.self, forKey: .activeSchedule)
            units = try? c.decode(WireUnits.self, forKey: .units)
            basalSchedules = try? c.decode([String: [WireScheduleEntry]].self, forKey: .basalSchedules)
            carbRatio = try? c.decode([WireScheduleEntry].self, forKey: .carbRatio)
            carbRatios = try? c.decode([String: [WireScheduleEntry]].self, forKey: .carbRatios)
            insulinSensitivity = try? c.decode([WireScheduleEntry].self, forKey: .insulinSensitivity)
            insulinSensitivities = try? c.decode([String: [WireScheduleEntry]].self, forKey: .insulinSensitivities)
            bgTarget = try? c.decode([WireScheduleEntry].self, forKey: .bgTarget)
            bgTargets = try? c.decode([String: [WireScheduleEntry]].self, forKey: .bgTargets)
            transmitterId = try? c.decode(String.self, forKey: .transmitterId)
            lowAlerts = try? c.decode(WireAlert.self, forKey: .lowAlerts)
            highAlerts = try? c.decode(WireAlert.self, forKey: .highAlerts)
        }
    }

    private struct WireUnits: Decodable {
        let bg: String?
        let carb: String?
        let raw: String?

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer().decode(String.self) {
                bg = single
                carb = nil
                raw = single
                return
            }
            struct Object: Decodable {
                let bg: String?
                let carb: String?
            }
            let object = try Object(from: decoder)
            bg = object.bg
            carb = object.carb
            raw = nil
        }
    }

    private struct WireScheduleEntry: Decodable {
        /// Milliseconds after midnight.
        let start: Int?
        let rate: Double?
        let amount: Double?
        let low: Double?
        let high: Double?
        let target: Double?
    }

    private struct WireAlert: Decodable {
        let enabled: Bool?
        let level: Double?
    }

    private struct Record: Decodable {
        let type: String
        let time: String
        let value: Double?
        let units: String?
    }

    /// Superset of the fields on bolus, basal, wizard, food and smbg records.
    private struct TherapyRecord: Decodable {
        let type: String
        let time: String
        let subType: String?
        // bolus
        let normal: Double?
        let extended: Double?
        /// Milliseconds.
        let duration: Int?
        // basal
        let deliveryType: String?
        let rate: Double?
        // wizard
        let carbInput: Double?
        // food
        let nutrition: Nutrition?
        // smbg
        let value: Double?
        let units: String?

        struct Nutrition: Decodable {
            let carbohydrate: Carbohydrate?
            struct Carbohydrate: Decodable {
                let net: Double?
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type, time, subType, normal, extended, duration, deliveryType, rate
            case carbInput, nutrition, value, units
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            time = try c.decode(String.self, forKey: .time)
            subType = try? c.decode(String.self, forKey: .subType)
            normal = try? c.decode(Double.self, forKey: .normal)
            extended = try? c.decode(Double.self, forKey: .extended)
            duration = try? c.decode(Int.self, forKey: .duration)
            deliveryType = try? c.decode(String.self, forKey: .deliveryType)
            rate = try? c.decode(Double.self, forKey: .rate)
            carbInput = try? c.decode(Double.self, forKey: .carbInput)
            nutrition = try? c.decode(Nutrition.self, forKey: .nutrition)
            value = try? c.decode(Double.self, forKey: .value)
            // smbg carries a plain string; other types may carry an object. Only the string matters here.
            units = try? c.decode(String.self, forKey: .units)
        }
    }

    /// Matches the script's "%Y-%m-%dT%H:%M:%S.000Z".
    private static let queryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()

    private static let fractionalParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let wholeSecondParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseTime(_ string: String) -> Date? {
        fractionalParser.date(from: string) ?? wholeSecondParser.date(from: string)
    }
}
