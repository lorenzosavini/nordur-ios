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
struct TripStop: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var place: Place
    var date: Date
    var nights: Int = 1
    var transport: Transport = .car
    var notes: String = ""

    var endDate: Date {
        Calendar.current.date(byAdding: .day, value: max(nights, 0), to: date) ?? date
    }
}
