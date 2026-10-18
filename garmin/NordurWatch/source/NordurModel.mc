import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Position, weather and aurora; asks the view to redraw when something arrives.
// The last data and position are kept on the watch: without the phone the app
// shows them with their time, and it retries every minute while open.
class NordurModel {
    var lat = null;
    var lon = null;
    var temp = null;
    var wind = null;
    var gust = null;
    var dir = null;
    var kp = null;
    var kpMax = null;
    // Time.now().value() of the weather shown.
    var updated = null;
    // :loading, :noGps, :noPhone, :timeout, :error, :ok
    var status = :loading;
    var errorCode = null;
    var timer = null;

    function initialize() {
        var saved = Application.Storage.getValue("last");
        if (saved instanceof Dictionary) {
            lat = saved["lat"];
            lon = saved["lon"];
            temp = saved["temp"];
            wind = saved["wind"];
            gust = saved["gust"];
            dir = saved["dir"];
            kp = saved["kp"];
            kpMax = saved["kpMax"];
            updated = saved["t"];
        }
    }

    function start() {
        var info = Position.getInfo();
        if (info != null && info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            onPosition(info);
        } else if (lat != null) {
            // Last known position while the GPS gets a fix.
            refresh();
        } else {
            status = :noGps;
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        timer = new Timer.Timer();
        timer.start(method(:onTick), 60000, true);
    }

    function stop() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (timer != null) {
            timer.stop();
        }
    }

    function onTick() as Void {
        // Every minute: retry after a failure, otherwise refresh every 10 minutes.
        if (status != :ok || updated == null || Time.now().value() - updated > 600) {
            refresh();
        }
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
            updated = Time.now().value();
            status = :ok;
            errorCode = null;
            save();
        } else {
            errorCode = code;
            // -104: phone not reachable; -2/-300: no answer (often the phone is locked
            // or Garmin Connect is closed); anything else: the service answered badly.
            if (code == -104 || code == -2) {
                status = :noPhone;
            } else if (code == -300 || code == -3) {
                status = :timeout;
            } else {
                status = :error;
            }
        }
        WatchUi.requestUpdate();
    }

    function onAurora(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (code == 200 && data instanceof Dictionary) {
            kp = data["kp"];
            kpMax = data["kpMax24"];
            save();
        }
        WatchUi.requestUpdate();
    }

    function save() {
        Application.Storage.setValue("last", {
            "lat" => lat, "lon" => lon, "temp" => temp, "wind" => wind, "gust" => gust,
            "dir" => dir, "kp" => kp, "kpMax" => kpMax, "t" => updated
        });
    }
}
