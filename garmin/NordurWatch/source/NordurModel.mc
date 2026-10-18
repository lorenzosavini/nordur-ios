import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Position, weather and aurora; asks the view to redraw when something arrives.
class NordurModel {
    var lat = null;
    var lon = null;
    var temp = null;
    var wind = null;
    var gust = null;
    var dir = null;
    var kp = null;
    var kpMax = null;
    var updated = null;
    // :loading, :noGps, :noPhone, :error, :ok
    var status = :loading;

    function initialize() {
    }

    function start() {
        var info = Position.getInfo();
        if (info != null && info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            onPosition(info);
        } else {
            status = :noGps;
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
    }

    function stop() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info.position == null) {
            return;
        }
        var degrees = (info.position as Position.Location).toDegrees() as Array<Double>;
        lat = degrees[0];
        lon = degrees[1];
        refresh();
    }

    function refresh() {
        if (!System.getDeviceSettings().phoneConnected) {
            status = :noPhone;
            WatchUi.requestUpdate();
            return;
        }
        if (lat == null) {
            status = :noGps;
            WatchUi.requestUpdate();
            return;
        }
        status = :loading;
        WatchUi.requestUpdate();
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        var params = {
            "latitude" => lat.format("%.3f"),
            "longitude" => lon.format("%.3f"),
            "current" => "temperature_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m",
            "wind_speed_unit" => "ms"
        };
        Communications.makeWebRequest("https://api.open-meteo.com/v1/forecast", params, options, method(:onWeather));
        Communications.makeWebRequest("https://nordur-api.vercel.app/api/aurora", { "compact" => "1" }, options, method(:onAurora));
    }

    function onWeather(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (code == 200 && data instanceof Dictionary && data["current"] != null) {
            var current = data["current"] as Dictionary;
            temp = current["temperature_2m"];
            wind = current["wind_speed_10m"];
            gust = current["wind_gusts_10m"];
            dir = current["wind_direction_10m"];
            updated = Time.now();
            status = :ok;
        } else {
            status = :error;
        }
        WatchUi.requestUpdate();
    }

    function onAurora(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (code == 200 && data instanceof Dictionary) {
            kp = data["kp"];
            kpMax = data["kpMax24"];
        }
        WatchUi.requestUpdate();
    }
}
