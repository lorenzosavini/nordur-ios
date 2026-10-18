import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The line in the glance list, without opening the app: the aurora first
// (level where you are and Kp), then the gusts.
(:glance)
class NordurGlance extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var data = Application.Storage.getValue("last");
        var w = dc.getWidth();
        var h = dc.getHeight();
        var title = "NORDUR";
        var aurora = "--";
        var auroraColor = Graphics.COLOR_WHITE;
        var gust = "";
        var gustColor = Graphics.COLOR_WHITE;
        if (data instanceof Dictionary) {
            if (data["place"] != null) {
                title = title + " · " + (data["place"] as String).toUpper();
            }
            var a = data["aurora"];
            var level = a instanceof Dictionary && a["level"] != null ? a["level"] : 0;
            var names = ["-", "debole", "possibile", "probabile", "FORTE"];
            aurora = "Aurora " + names[level > 4 ? 4 : level];
            if (a instanceof Dictionary && a["visible"] == true) {
                aurora = aurora + " ORA";
            }
            if (data["kp"] != null) {
                aurora = aurora + " · Kp " + data["kp"].format("%.1f");
            }
            auroraColor = level >= 4 ? 0xA06BFF : (level >= 2 ? 0x34E89E : 0x2EC4A6);
            gust = NordurApi.speed(data["gust"]) + " " + NordurApi.unitLabel();
            gustColor = NordurApi.gustColor(data["gust"]);
        }
        dc.setColor(0x8A8A8A, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.2, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(auroraColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.52, Graphics.FONT_TINY, aurora, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (!gust.equals("")) {
            dc.setColor(gustColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, h * 0.84, Graphics.FONT_XTINY, gust, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
