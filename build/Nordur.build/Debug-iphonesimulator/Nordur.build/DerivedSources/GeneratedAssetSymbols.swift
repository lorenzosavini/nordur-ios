import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "hero-aurora" asset catalog image resource.
    static let heroAurora = DeveloperToolsSupport.ImageResource(name: "hero-aurora", bundle: resourceBundle)

    /// The "hero-drive" asset catalog image resource.
    static let heroDrive = DeveloperToolsSupport.ImageResource(name: "hero-drive", bundle: resourceBundle)

    /// The "hero-map" asset catalog image resource.
    static let heroMap = DeveloperToolsSupport.ImageResource(name: "hero-map", bundle: resourceBundle)

    /// The "hero-roads" asset catalog image resource.
    static let heroRoads = DeveloperToolsSupport.ImageResource(name: "hero-roads", bundle: resourceBundle)

    /// The "hero-trip" asset catalog image resource.
    static let heroTrip = DeveloperToolsSupport.ImageResource(name: "hero-trip", bundle: resourceBundle)

    /// The "hero-volcano" asset catalog image resource.
    static let heroVolcano = DeveloperToolsSupport.ImageResource(name: "hero-volcano", bundle: resourceBundle)

    /// The "hero-weather" asset catalog image resource.
    static let heroWeather = DeveloperToolsSupport.ImageResource(name: "hero-weather", bundle: resourceBundle)

    /// The "kind-alcohol" asset catalog image resource.
    static let kindAlcohol = DeveloperToolsSupport.ImageResource(name: "kind-alcohol", bundle: resourceBundle)

    /// The "kind-bath" asset catalog image resource.
    static let kindBath = DeveloperToolsSupport.ImageResource(name: "kind-bath", bundle: resourceBundle)

    /// The "kind-beach" asset catalog image resource.
    static let kindBeach = DeveloperToolsSupport.ImageResource(name: "kind-beach", bundle: resourceBundle)

    /// The "kind-canyon" asset catalog image resource.
    static let kindCanyon = DeveloperToolsSupport.ImageResource(name: "kind-canyon", bundle: resourceBundle)

    /// The "kind-charger" asset catalog image resource.
    static let kindCharger = DeveloperToolsSupport.ImageResource(name: "kind-charger", bundle: resourceBundle)

    /// The "kind-convenience" asset catalog image resource.
    static let kindConvenience = DeveloperToolsSupport.ImageResource(name: "kind-convenience", bundle: resourceBundle)

    /// The "kind-fuel" asset catalog image resource.
    static let kindFuel = DeveloperToolsSupport.ImageResource(name: "kind-fuel", bundle: resourceBundle)

    /// The "kind-geothermal" asset catalog image resource.
    static let kindGeothermal = DeveloperToolsSupport.ImageResource(name: "kind-geothermal", bundle: resourceBundle)

    /// The "kind-glacier" asset catalog image resource.
    static let kindGlacier = DeveloperToolsSupport.ImageResource(name: "kind-glacier", bundle: resourceBundle)

    /// The "kind-landscape" asset catalog image resource.
    static let kindLandscape = DeveloperToolsSupport.ImageResource(name: "kind-landscape", bundle: resourceBundle)

    /// The "kind-mall" asset catalog image resource.
    static let kindMall = DeveloperToolsSupport.ImageResource(name: "kind-mall", bundle: resourceBundle)

    /// The "kind-shop" asset catalog image resource.
    static let kindShop = DeveloperToolsSupport.ImageResource(name: "kind-shop", bundle: resourceBundle)

    /// The "kind-supermarket" asset catalog image resource.
    static let kindSupermarket = DeveloperToolsSupport.ImageResource(name: "kind-supermarket", bundle: resourceBundle)

    /// The "kind-town" asset catalog image resource.
    static let kindTown = DeveloperToolsSupport.ImageResource(name: "kind-town", bundle: resourceBundle)

    /// The "kind-waterfall" asset catalog image resource.
    static let kindWaterfall = DeveloperToolsSupport.ImageResource(name: "kind-waterfall", bundle: resourceBundle)

    /// The "kind-wildlife" asset catalog image resource.
    static let kindWildlife = DeveloperToolsSupport.ImageResource(name: "kind-wildlife", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "AccentColor" asset catalog color.
    static var accent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .accent)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "AccentColor" asset catalog color.
    static var accent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .accent)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "hero-aurora" asset catalog image.
    static var heroAurora: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroAurora)
#else
        .init()
#endif
    }

    /// The "hero-drive" asset catalog image.
    static var heroDrive: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroDrive)
#else
        .init()
#endif
    }

    /// The "hero-map" asset catalog image.
    static var heroMap: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroMap)
#else
        .init()
#endif
    }

    /// The "hero-roads" asset catalog image.
    static var heroRoads: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroRoads)
#else
        .init()
#endif
    }

    /// The "hero-trip" asset catalog image.
    static var heroTrip: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroTrip)
#else
        .init()
#endif
    }

    /// The "hero-volcano" asset catalog image.
    static var heroVolcano: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroVolcano)
#else
        .init()
#endif
    }

    /// The "hero-weather" asset catalog image.
    static var heroWeather: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .heroWeather)
#else
        .init()
#endif
    }

    /// The "kind-alcohol" asset catalog image.
    static var kindAlcohol: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindAlcohol)
#else
        .init()
#endif
    }

    /// The "kind-bath" asset catalog image.
    static var kindBath: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindBath)
#else
        .init()
#endif
    }

    /// The "kind-beach" asset catalog image.
    static var kindBeach: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindBeach)
#else
        .init()
#endif
    }

    /// The "kind-canyon" asset catalog image.
    static var kindCanyon: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindCanyon)
#else
        .init()
#endif
    }

    /// The "kind-charger" asset catalog image.
    static var kindCharger: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindCharger)
#else
        .init()
#endif
    }

    /// The "kind-convenience" asset catalog image.
    static var kindConvenience: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindConvenience)
#else
        .init()
#endif
    }

    /// The "kind-fuel" asset catalog image.
    static var kindFuel: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindFuel)
#else
        .init()
#endif
    }

    /// The "kind-geothermal" asset catalog image.
    static var kindGeothermal: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindGeothermal)
#else
        .init()
#endif
    }

    /// The "kind-glacier" asset catalog image.
    static var kindGlacier: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindGlacier)
#else
        .init()
#endif
    }

    /// The "kind-landscape" asset catalog image.
    static var kindLandscape: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindLandscape)
#else
        .init()
#endif
    }

    /// The "kind-mall" asset catalog image.
    static var kindMall: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindMall)
#else
        .init()
#endif
    }

    /// The "kind-shop" asset catalog image.
    static var kindShop: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindShop)
#else
        .init()
#endif
    }

    /// The "kind-supermarket" asset catalog image.
    static var kindSupermarket: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindSupermarket)
#else
        .init()
#endif
    }

    /// The "kind-town" asset catalog image.
    static var kindTown: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindTown)
#else
        .init()
#endif
    }

    /// The "kind-waterfall" asset catalog image.
    static var kindWaterfall: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindWaterfall)
#else
        .init()
#endif
    }

    /// The "kind-wildlife" asset catalog image.
    static var kindWildlife: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .kindWildlife)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "hero-aurora" asset catalog image.
    static var heroAurora: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroAurora)
#else
        .init()
#endif
    }

    /// The "hero-drive" asset catalog image.
    static var heroDrive: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroDrive)
#else
        .init()
#endif
    }

    /// The "hero-map" asset catalog image.
    static var heroMap: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroMap)
#else
        .init()
#endif
    }

    /// The "hero-roads" asset catalog image.
    static var heroRoads: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroRoads)
#else
        .init()
#endif
    }

    /// The "hero-trip" asset catalog image.
    static var heroTrip: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroTrip)
#else
        .init()
#endif
    }

    /// The "hero-volcano" asset catalog image.
    static var heroVolcano: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroVolcano)
#else
        .init()
#endif
    }

    /// The "hero-weather" asset catalog image.
    static var heroWeather: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .heroWeather)
#else
        .init()
#endif
    }

    /// The "kind-alcohol" asset catalog image.
    static var kindAlcohol: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindAlcohol)
#else
        .init()
#endif
    }

    /// The "kind-bath" asset catalog image.
    static var kindBath: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindBath)
#else
        .init()
#endif
    }

    /// The "kind-beach" asset catalog image.
    static var kindBeach: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindBeach)
#else
        .init()
#endif
    }

    /// The "kind-canyon" asset catalog image.
    static var kindCanyon: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindCanyon)
#else
        .init()
#endif
    }

    /// The "kind-charger" asset catalog image.
    static var kindCharger: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindCharger)
#else
        .init()
#endif
    }

    /// The "kind-convenience" asset catalog image.
    static var kindConvenience: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindConvenience)
#else
        .init()
#endif
    }

    /// The "kind-fuel" asset catalog image.
    static var kindFuel: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindFuel)
#else
        .init()
#endif
    }

    /// The "kind-geothermal" asset catalog image.
    static var kindGeothermal: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindGeothermal)
#else
        .init()
#endif
    }

    /// The "kind-glacier" asset catalog image.
    static var kindGlacier: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindGlacier)
#else
        .init()
#endif
    }

    /// The "kind-landscape" asset catalog image.
    static var kindLandscape: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindLandscape)
#else
        .init()
#endif
    }

    /// The "kind-mall" asset catalog image.
    static var kindMall: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindMall)
#else
        .init()
#endif
    }

    /// The "kind-shop" asset catalog image.
    static var kindShop: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindShop)
#else
        .init()
#endif
    }

    /// The "kind-supermarket" asset catalog image.
    static var kindSupermarket: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindSupermarket)
#else
        .init()
#endif
    }

    /// The "kind-town" asset catalog image.
    static var kindTown: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindTown)
#else
        .init()
#endif
    }

    /// The "kind-waterfall" asset catalog image.
    static var kindWaterfall: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindWaterfall)
#else
        .init()
#endif
    }

    /// The "kind-wildlife" asset catalog image.
    static var kindWildlife: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .kindWildlife)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

