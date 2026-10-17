#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"it.lorenzosavini.nordur";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "hero-aurora" asset catalog image resource.
static NSString * const ACImageNameHeroAurora AC_SWIFT_PRIVATE = @"hero-aurora";

/// The "hero-drive" asset catalog image resource.
static NSString * const ACImageNameHeroDrive AC_SWIFT_PRIVATE = @"hero-drive";

/// The "hero-map" asset catalog image resource.
static NSString * const ACImageNameHeroMap AC_SWIFT_PRIVATE = @"hero-map";

/// The "hero-roads" asset catalog image resource.
static NSString * const ACImageNameHeroRoads AC_SWIFT_PRIVATE = @"hero-roads";

/// The "hero-trip" asset catalog image resource.
static NSString * const ACImageNameHeroTrip AC_SWIFT_PRIVATE = @"hero-trip";

/// The "hero-volcano" asset catalog image resource.
static NSString * const ACImageNameHeroVolcano AC_SWIFT_PRIVATE = @"hero-volcano";

/// The "hero-weather" asset catalog image resource.
static NSString * const ACImageNameHeroWeather AC_SWIFT_PRIVATE = @"hero-weather";

#undef AC_SWIFT_PRIVATE
