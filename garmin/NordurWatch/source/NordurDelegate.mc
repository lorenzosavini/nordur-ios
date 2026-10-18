import Toybox.Lang;
import Toybox.WatchUi;

// START (or a tap on touch watches) refreshes; BACK closes the app.
class NordurDelegate extends WatchUi.BehaviorDelegate {
    var model;

    function initialize(m) {
        BehaviorDelegate.initialize();
        model = m;
    }

    function onSelect() {
        model.refresh();
        return true;
    }
}
