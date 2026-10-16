import Foundation

enum Transport: String, Codable, CaseIterable, Identifiable {
    case car, plane, ferry, bus, walk, boat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .car: return "Auto"
        case .plane: return "Aereo"
        case .ferry: return "Traghetto"
        case .bus: return "Bus"
        case .walk: return "A piedi / trekking"
        case .boat: return "Escursione in barca"
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
