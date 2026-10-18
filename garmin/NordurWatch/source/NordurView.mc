import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// One screen: the place on top, the gusts in the middle inside a gauge ring
// (0–30 m/s, coloured like the app's thresholds), then wind, sky, temperature
// and aurora, and at the bottom the time and source of the data.
class NordurView extends WatchUi.View {
    var model;
    const ACCENT = 0x2EC4A6;
    const DIM = 0x8A8A8A;
    const TRACK = 0x2A2A2A;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() {
        model.start();
    }

    function onHide() {
        model.stop();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var data = model.data;
        var hasData = data instanceof Dictionary;
        var gust = hasData ? data["gust"] : null;

        // Gauge ring, open at the bottom (270°), filled up to the gusts.
        var radius = (w < h ? w : h) / 2 - 6;
        var pen = w / 28;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setPenWidth(pen);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, 315);
        if (gust != null && gust > 0) {
            var fraction = gust / 30.0;
            if (fraction > 1) {
                fraction = 1;
            }
            var end = 225 - 270 * fraction;
            if (end < 0) {
                end += 360;
            }
            dc.setColor(NordurApi.gustColor(gust), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, end.toNumber());
        }
        dc.setPenWidth(1);

        // Place.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var place = hasData && data["place"] != null ? (data["place"] as String).toUpper() : "NORDUR";
        dc.drawText(cx, h * 0.14, Graphics.FONT_XTINY, place, Graphics.TEXT_JUSTIFY_CENTER);

        if (!hasData) {
            var text = Graphics.fitTextToArea(message(), Graphics.FONT_SMALL, w * 0.7, h * 0.4, true);
            dc.drawText(cx, cy, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Gusts.
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.25, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Gusts), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(NordurApi.gustColor(gust), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.43, Graphics.FONT_NUMBER_HOT, NordurApi.speed(gust), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, h * 0.555, Graphics.FONT_XTINY, NordurApi.unitLabel() + " · " + gustLabel(gust), Graphics.TEXT_JUSTIFY_CENTER);

        // Wind and direction (where it blows from).
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var wind = WatchUi.loadResource(Rez.Strings.Wind) + " " + NordurApi.speed(data["wind"]) + " " + NordurApi.unitLabel();
        if (data["dir"] != null) {
            wind = wind + " " + WatchUi.loadResource(Rez.Strings.From) + " " + compass(data["dir"]);
        }
        dc.drawText(cx, h * 0.645, Graphics.FONT_TINY, wind, Graphics.TEXT_JUSTIFY_CENTER);

        // Temperature, sky, aurora.
        var line = "";
        if (data["temp"] != null) {
            line = data["temp"].format("%.0f") + "°";
        }
        var sky = skyLabel(data["sky"]);
        if (sky != null) {
            line = line + " " + sky;
        }
        dc.drawText(cx, h * 0.73, Graphics.FONT_TINY, line, Graphics.TEXT_JUSTIFY_CENTER);
        // Aurora, the three signals kept apart: Kp (3 h), Hp30 (30 min), Bz now
        // (south = negative: aurora likely in 30–60 minutes, shown in green).
        var aurora = "";
        if (data["kp"] != null) {
            aurora = "Kp " + data["kp"].format("%.1f");
        }
        if (data["hp30"] != null) {
            aurora = aurora + "  Hp30 " + data["hp30"].format("%.1f");
        }
        if (data["bz"] != null) {
            aurora = aurora + "  Bz " + (data["bz"] > 0 ? "+" : "") + data["bz"].format("%.0f");
        }
        if (!aurora.equals("")) {
            var bz = data["bz"];
            var magLevel = data["mag"];
            var likely = (bz != null && bz <= -5) || (magLevel != null && magLevel >= 2);
            dc.setColor(likely ? 0x34C759 : ACCENT, Graphics.COLOR_TRANSPARENT);
            var fitted = Graphics.fitTextToArea(aurora, Graphics.FONT_XTINY, w * 0.8, h * 0.08, true);
            dc.drawText(cx, h * 0.81, Graphics.FONT_XTINY, fitted, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Time of the data (and why they are old, when they are).
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        var footer = "...";
        if (model.status != :loading && data["t"] != null) {
            var clock = Gregorian.info(new Time.Moment(data["t"] as Number), Time.FORMAT_SHORT);
            footer = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
            if (model.status != :ok) {
                footer = WatchUi.loadResource(Rez.Strings.DataFrom) + " " + footer;
            }
        }
        dc.drawText(cx, h * 0.885, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function message() {
        var text = WatchUi.loadResource(Rez.Strings.Loading);
        if (model.status == :noGps) {
            text = WatchUi.loadResource(Rez.Strings.NoGps);
        } else if (model.status == :noPhone) {
            text = WatchUi.loadResource(Rez.Strings.NoPhone);
        } else if (model.status == :timeout) {
            text = WatchUi.loadResource(Rez.Strings.Unlock);
        } else if (model.status == :error) {
            text = WatchUi.loadResource(Rez.Strings.Error);
        }
        if (model.errorCode != null) {
            text = text + " (" + model.errorCode + ")";
        }
        return text;
    }

    function gustLabel(g) {
        if (g == null) {
            return "";
        } else if (g >= 20) {
            return WatchUi.loadResource(Rez.Strings.Storm);
        } else if (g >= 15) {
            return WatchUi.loadResource(Rez.Strings.Strong);
        }
        return WatchUi.loadResource(Rez.Strings.Calm);
    }

    function skyLabel(sky) {
        if (sky == null) {
            return null;
        }
        var ids = {
            "clear" => Rez.Strings.SkyClear, "partly" => Rez.Strings.SkyPartly, "cloudy" => Rez.Strings.SkyCloudy,
            "rain" => Rez.Strings.SkyRain, "snow" => Rez.Strings.SkySnow, "fog" => Rez.Strings.SkyFog, "storm" => Rez.Strings.SkyStorm
        };
        var id = ids[sky];
        return id == null ? null : WatchUi.loadResource(id);
    }

    function compass(degrees) {
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var index = ((degrees.toFloat() + 22.5) / 45).toNumber() % 8;
        return names[index];
    }
}
