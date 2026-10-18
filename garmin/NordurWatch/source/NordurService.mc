import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;

// Every 15 minutes, also with the app closed: fetches the conditions at the
// last known position and hands them to the app (and the glance).
(:background)
class NordurService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var pos = Application.Storage.getValue("pos");
        if (!(pos instanceof Array) || pos.size() < 2) {
            Background.exit(null);
            return;
        }
        Communications.makeWebRequest(NordurApi.URL, NordurApi.params(pos[0], pos[1]), NordurApi.options(), method(:onData));
    }

    function onData(code as Number, data as Null or Dictionary or String or PersistedContent.Iterator) as Void {
        if (code == 200 && data instanceof Dictionary) {
            Background.exit(data);
        } else {
            Background.exit(null);
        }
    }
}
