import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Norður on the wrist: gusts, wind, temperature, sky and aurora (Kp) where you
// are, computed by nordur-api exactly as the iPhone app does (MET Norway +
// Open-Meteo), with the place name. A background service refreshes the data
// every 15 minutes for the glance; the watch goes online through the phone.
(:background, :glance)
class NordurApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var model = new NordurModel();
        var view = new NordurView(model);
        return [view, new NordurDelegate(model, view)];
    }

    (:glance)
    function getGlanceView() {
        return [new NordurGlance()];
    }

    function getServiceDelegate() {
        return [new NordurService()];
    }

    // Data fetched by the background service.
    function onBackgroundData(data) {
        if (data instanceof Dictionary) {
            Application.Storage.setValue("last", data);
            WatchUi.requestUpdate();
        }
    }
}
