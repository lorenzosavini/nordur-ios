import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Position and conditions while the app is open. The last data and position
// are kept on the watch: without the phone the app shows them with their time.
class NordurModel {
    var data = null;          // the last answer of nordur-api (Dictionary)
    var lat = null;
    var lon = null;
    var status = :loading;    // :loading, :noGps, :noPhone, :timeout, :error, :ok
    var errorCode = null;
    var timer = null;

    function initialize() {
        data = Application.Storage.getValue("last");
        var pos = Application.Storage.getValue("pos");
        if (pos instanceof Array && pos.size() >= 2) {
            lat = pos[0];
            lon = pos[1];
        }
    }

    function start() {
        var info = Position.getInfo();
        if (info != null && info.position != null && info.accuracy != Position.QUALITY_NOT_AVAILABLE) {
            onPosition(info);
        } else if (lat != null) {
            refresh();
        } else {
            status = :noGps;
        }
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
        timer = new Timer.Timer();
        timer.start(method(:onTick), 60000, true);
        // Background refresh for the glance, also with the app closed.
        if (Toybox has :Background) {
            Background.registerForTemporalEvent(new Time.Duration(15 * 60));
        }
    }

    function stop() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (timer != null) {
            timer.stop();
        }
    }

    function age() {
        if (data instanceof Dictionary && data["t"] != null) {
            return Time.now().value() - (data["t"] as Number);
        }
        return null;
    }

    function onTick() as Void {
        // Every minute: retry after a failure; otherwise refresh every 5 minutes.
        var a = age();
        if (status != :ok || a == null || a > 300) {
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
        Application.Storage.setValue("pos", [lat, lon]);
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
        Communications.makeWebRequest(NordurApi.URL, NordurApi.params(lat, lon), NordurApi.options(), method(:onData));
    }

    function onData(code as Number, answer as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (code == 200 && answer instanceof Dictionary) {
            data = answer;
            Application.Storage.setValue("last", answer);
            status = :ok;
            errorCode = null;
        } else {
            errorCode = code;
            // -104: phone not reachable; -2/-3/-300: no answer (phone locked, Garmin
            // Connect closed); anything else: the service answered badly.
            if (code == -104) {
                status = :noPhone;
            } else if (code == -2 || code == -3 || code == -300) {
                status = :timeout;
            } else {
                status = :error;
            }
        }
        WatchUi.requestUpdate();
    }
}
