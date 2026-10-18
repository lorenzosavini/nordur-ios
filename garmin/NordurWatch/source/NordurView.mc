import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class NordurView extends WatchUi.View {
    var model;
    const ACCENT = 0x2EC4A6;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Graphics.FONT_XTINY, "NORDUR", Graphics.TEXT_JUSTIFY_CENTER);

        if (model.gust == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            // Wrapped to the round screen.
            var text = Graphics.fitTextToArea(message(), Graphics.FONT_SMALL, w * 0.78, h * 0.5, true);
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Gusts: the number that decides whether to drive, open a car door, walk on a ridge.
        dc.setColor(gustColor(model.gust), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.20, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Gusts), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.27, Graphics.FONT_NUMBER_HOT, model.gust.format("%.0f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.52, Graphics.FONT_XTINY, "m/s  " + gustLabel(model.gust), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (model.wind != null) {
            var windText = WatchUi.loadResource(Rez.Strings.Wind) + " " + model.wind.format("%.0f") + " m/s " + compass(model.dir);
            dc.drawText(cx, h * 0.62, Graphics.FONT_TINY, windText, Graphics.TEXT_JUSTIFY_CENTER);
        }

        var bottom = "";
        if (model.temp != null) {
            bottom = model.temp.format("%.0f") + "°C";
        }
        if (model.kp != null) {
            bottom = bottom + "   Kp " + model.kp.format("%.1f");
            if (model.kpMax != null) {
                bottom = bottom + " / " + model.kpMax.format("%.0f");
            }
        }
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.74, Graphics.FONT_TINY, bottom, Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom line: loading, or the time of the data when they are not fresh.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (model.status == :loading) {
            dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, "...", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (model.status != :ok && model.updated != null) {
            var clock = Gregorian.info(new Time.Moment(model.updated), Time.FORMAT_SHORT);
            var age = WatchUi.loadResource(Rez.Strings.DataFrom) + " " + clock.hour.format("%02d") + ":" + clock.min.format("%02d");
            dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, age, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function message() {
        if (model.status == :noGps) {
            return WatchUi.loadResource(Rez.Strings.NoGps);
        } else if (model.status == :timeout || model.status == :noPhone) {
            var text = WatchUi.loadResource(model.status == :timeout ? Rez.Strings.Unlock : Rez.Strings.NoPhone);
            if (model.errorCode != null) {
                text = text + " (" + model.errorCode + ")";
            }
            return text;
        } else if (model.status == :error) {
            var text = WatchUi.loadResource(Rez.Strings.Error);
            if (model.errorCode != null) {
                text = text + " (" + model.errorCode + ")";
            }
            return text;
        }
        return WatchUi.loadResource(Rez.Strings.Loading);
    }

    // Same thresholds as the iPhone app: 15 m/s strong, 20 m/s dangerous for cars.
    function gustColor(g) {
        if (g >= 20) {
            return Graphics.COLOR_RED;
        } else if (g >= 15) {
            return Graphics.COLOR_ORANGE;
        }
        return Graphics.COLOR_WHITE;
    }

    function gustLabel(g) {
        if (g >= 20) {
            return WatchUi.loadResource(Rez.Strings.Storm);
        } else if (g >= 15) {
            return WatchUi.loadResource(Rez.Strings.Strong);
        }
        return WatchUi.loadResource(Rez.Strings.Calm);
    }

    function compass(degrees) {
        if (degrees == null) {
            return "";
        }
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var index = ((degrees.toFloat() + 22.5) / 45).toNumber() % 8;
        return names[index];
    }
}
