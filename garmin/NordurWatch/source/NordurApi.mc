import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;

// The request to nordur-api and the units, shared by the app, the glance and
// the background service.
(:background, :glance)
module NordurApi {
    const URL = "https://nordur-api.vercel.app/api/watch";

    function params(lat, lon) {
        var lang = System.getDeviceSettings().systemLanguage == System.LANGUAGE_ITA ? "it" : "en";
        return { "lat" => lat.format("%.4f"), "lon" => lon.format("%.4f"), "lang" => lang };
    }

    function options() {
        return {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // 0 = km/h (as in the iPhone app), 1 = m/s, 2 = knots; set in Garmin Connect.
    function unit() {
        var value = Application.Properties.getValue("units");
        return value instanceof Number ? value : 0;
    }

    function speed(ms) {
        if (ms == null) {
            return "--";
        }
        var u = unit();
        var v = u == 1 ? ms : (u == 2 ? ms * 1.94384 : ms * 3.6);
        return v.format("%.0f");
    }

    function unitLabel() {
        var u = unit();
        return u == 1 ? "m/s" : (u == 2 ? "kn" : "km/h");
    }

    // Same thresholds as the iPhone app: 15 m/s strong, 20 m/s dangerous.
    function gustColor(ms) {
        if (ms == null) {
            return 0xAAAAAA;
        } else if (ms >= 20) {
            return 0xFF3B30;
        } else if (ms >= 15) {
            return 0xFF9500;
        } else if (ms >= 10) {
            return 0xFFD60A;
        }
        return 0x2EC4A6;
    }
}
