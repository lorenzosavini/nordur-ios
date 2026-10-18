import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Norður on the wrist: gusts, wind, temperature and aurora (Kp) where you are.
// Data: Open-Meteo for the weather at the watch's GPS position, nordur-api for
// the aurora. The watch goes online through the phone (Garmin Connect).
class NordurApp extends Application.AppBase {
    var model;

    function initialize() {
        AppBase.initialize();
        model = new NordurModel();
    }

    function onStart(state) {
        model.start();
    }

    function onStop(state) {
        model.stop();
    }

    function getInitialView() {
        return [new NordurView(model), new NordurDelegate(model)];
    }
}
