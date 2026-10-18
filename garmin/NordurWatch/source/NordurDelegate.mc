import Toybox.Lang;
import Toybox.WatchUi;

// UP/DOWN or swipe: change page. START (or a tap): refresh. BACK: close.
class NordurDelegate extends WatchUi.BehaviorDelegate {
    var model;
    var view;

    function initialize(m, v) {
        BehaviorDelegate.initialize();
        model = m;
        view = v;
    }

    function onNextPage() {
        view.turn(1);
        return true;
    }

    function onPreviousPage() {
        view.turn(-1);
        return true;
    }

    function onSelect() {
        model.refresh();
        return true;
    }
}
