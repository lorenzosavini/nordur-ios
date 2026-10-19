import Foundation

enum Transport: String, Codable, CaseIterable, Identifiable {
    case car, plane, ferry, bus, walk, boat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .car: return String(localized: "Auto")
        case .plane: return String(localized: "Aereo")
        case .ferry: return String(localized: "Traghetto")
        case .bus: return String(localized: "Bus")
        case .walk: return String(localized: "A piedi / trekking")
        case .boat: return String(localized: "Escursione in barca")
        }
    }

    var symbol: String {
        switch self {
        case .car: return "car.fill"
        case .plane: return "airplane"
        case .ferry: return "ferry.fill"
        case .bus: return "bus.fill"
        case .walk: return "figure.hiking"
        case .boat: return "sailboat.fill"
        }
    }

    /// Which hazards matter most for this way of travelling.
    var caresAboutSea: Bool { self == .ferry || self == .boat }
}

/// One stop of the itinerary: the transport is how you *arrive* there.
/// The attractions to see on the way there and during the stay are its visits.
struct TripStop: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var place: Place
    var date: Date
    var nights: Int = 1
    var transport: Transport = .car
    var notes: String = ""
    var visits: [TripVisit] = []

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: max(nights, 0), to: date) ?? date
    }

    /// Visits in time order.
    var sortedVisits: [TripVisit] { visits.sorted { $0.date < $1.date } }

    /// Each day of the stop, from the day you arrive to the day you leave (Iceland time).
    var days: [Date] {
        let calendar = Calendar.iceland
        let start = calendar.startOfDay(for: date)
        return (0...max(nights, 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func includes(day: Date) -> Bool {
        days.contains { Calendar.iceland.isDate($0, inSameDayAs: day) }
    }
}

extension TripStop {
    // Trips saved before visits existed have no "visits" key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        place = try c.decode(Place.self, forKey: .place)
        date = try c.decode(Date.self, forKey: .date)
        nights = try c.decodeIfPresent(Int.self, forKey: .nights) ?? 1
        transport = try c.decodeIfPresent(Transport.self, forKey: .transport) ?? .car
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        visits = try c.decodeIfPresent([TripVisit].self, forKey: .visits) ?? []
    }
}

/// An attraction to see (a waterfall, a beach, a glacier lagoon…), with the day
/// and time of arrival and how long you stay.
struct TripVisit: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var place: Place
    var date: Date
    var minutes: Int = 60
    var kind: AttractionKind?
    var notes: String = ""

    var end: Date { date.addingTimeInterval(Double(minutes) * 60) }

    /// The same visit at the same time of day on another day.
    func moved(to day: Date) -> TripVisit {
        let calendar = Calendar.iceland
        let time = calendar.dateComponents([.hour, .minute], from: date)
        var visit = self
        visit.date = calendar.date(bySettingHour: time.hour ?? 10, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return visit
    }

    func shifted(days: Int) -> TripVisit {
        var visit = self
        visit.date = Calendar.iceland.date(byAdding: .day, value: days, to: date) ?? date
        return visit
    }
}
