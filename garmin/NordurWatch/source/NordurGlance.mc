import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The line in the glance list: place, gusts and Kp, without opening the app.
(:glance)
class NordurGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var data = Application.Storage.getValue("last");
        var h = dc.getHeight();
        dc.setColor(0x2EC4A6, Graphics.COLOR_TRANSPARENT);
        var title = "NORDUR";
        if (data instanceof Dictionary && data["place"] != null) {
            title = title + " · " + (data["place"] as String).toUpper();
        }
        dc.drawText(0, h * 0.25, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var line = "--";
        if (data instanceof Dictionary) {
            dc.setColor(NordurApi.gustColor(data["gust"]), Graphics.COLOR_TRANSPARENT);
            line = NordurApi.speed(data["gust"]) + " " + NordurApi.unitLabel();
            if (data["kp"] != null) {
                line = line + "  ·  Kp " + data["kp"].format("%.1f");
            }
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(0, h * 0.72, Graphics.FONT_SMALL, line, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
