import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Three pages, UP/DOWN (or swipe) to move, START to refresh:
//   0  Aurora where you are: level, probability overhead and to the north,
//      darkness and clouds; an animated curtain when it can be seen now.
//   1  Space weather: Kp now and for the next 24 h, Bz, solar wind, Hp30,
//      ground magnetometer, each signal on its own.
//   2  Wind and weather: gusts in a gauge ring, wind, temperature, sky.
class NordurView extends WatchUi.View {
    var model;
    var page = 0;
    var phase = 0;
    var anim = null;

    const ACCENT = 0x2EC4A6;
    const DIM = 0x8A8A8A;
    const TRACK = 0x262626;
    const GREEN = 0x34E89E;
    const DEEP = 0x1B7F55;
    const VIOLET = 0xA06BFF;

    function initialize(m) {
        View.initialize();
        model = m;
    }

    function onShow() {
        model.start();
    }

    function onHide() {
        model.stop();
        setAnimation(false);
    }

    function turn(step) {
        page = (page + step + 3) % 3;
        WatchUi.requestUpdate();
    }

    // MARK: Drawing

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var data = model.data;
        if (!(data instanceof Dictionary)) {
            setAnimation(false);
            title(dc, w, h, "NORDUR");
            var text = Graphics.fitTextToArea(message(), Graphics.FONT_SMALL, w * 0.7, h * 0.4, true);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        if (page == 0) {
            drawAurora(dc, w, h, data);
        } else if (page == 1) {
            setAnimation(false);
            drawSpace(dc, w, h, data);
        } else {
            setAnimation(false);
            drawWeather(dc, w, h, data);
        }
        dots(dc, w, h);
    }

    // Page 0 ------------------------------------------------------------

    function drawAurora(dc, w, h, data) {
        var cx = w / 2;
        var a = data["aurora"];
        var level = 0;
        var visible = false;
        if (a instanceof Dictionary) {
            level = a["level"] == null ? 0 : a["level"];
            visible = a["visible"] == true;
        }
        var demo = Application.Properties.getValue("demoAurora") == true;
        if (demo) {
            level = 3;
            visible = true;
        }

        // The curtain: moving when the aurora can be seen now, still and faint
        // when there is activity but it is day or cloudy.
        if (level >= 2 || demo) {
            curtain(dc, w, h, level, visible);
        }
        setAnimation(visible);

        ring(dc, w, h, level / 4.0, levelColor(level));
        var place = data["place"] != null ? (data["place"] as String).toUpper() : "";
        title(dc, w, h, WatchUi.loadResource(Rez.Strings.AuroraTitle) + (place.equals("") ? "" : " · " + place));

        dc.setColor(levelColor(level), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.47, Graphics.FONT_LARGE, levelName(level), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Why: visible now, or what stops it.
        var why = "";
        if (a instanceof Dictionary) {
            if (visible) {
                why = WatchUi.loadResource(Rez.Strings.VisibleNow);
            } else if (level >= 1 && a["dark"] != true) {
                why = WatchUi.loadResource(Rez.Strings.Daylight);
            } else if (level >= 1 && a["clouds"] != null && a["clouds"] >= 75) {
                why = WatchUi.loadResource(Rez.Strings.Cloudy);
            } else if (level == 0) {
                why = WatchUi.loadResource(Rez.Strings.NoneHere);
            }
        }
        dc.setColor(visible ? GREEN : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        line(dc, w, h * 0.565, Graphics.FONT_XTINY, why);

        // Probability overhead and toward the north (OVATION).
        if (a instanceof Dictionary) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            line(dc, w, h * 0.645, Graphics.FONT_TINY,
                WatchUi.loadResource(Rez.Strings.Overhead) + " " + a["overhead"] + "%  ·  "
                + WatchUi.loadResource(Rez.Strings.North) + " " + a["horizon"] + "%");
            var sky = (a["dark"] == true ? WatchUi.loadResource(Rez.Strings.Dark) : WatchUi.loadResource(Rez.Strings.Day)) as String;
            if (a["clouds"] != null) {
                sky = sky + "  ·  " + WatchUi.loadResource(Rez.Strings.Clouds) + " " + a["clouds"] + "%";
            }
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            line(dc, w, h * 0.725, Graphics.FONT_XTINY, sky);
        }

        // The three space signals, short.
        var signals = "";
        if (data["kp"] != null) {
            signals = "Kp " + data["kp"].format("%.1f");
        }
        if (data["bz"] != null) {
            signals = signals + "  Bz " + signed(data["bz"]);
        }
        if (data["hp30"] != null) {
            signals = signals + "  Hp30 " + data["hp30"].format("%.1f");
        }
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        line(dc, w, h * 0.795, Graphics.FONT_XTINY, signals);
        footer(dc, w, h, data);
    }

    function curtain(dc, w, h, level, moving) {
        var n = 30;
        var colW = w / n.toFloat();
        dc.setPenWidth(colW.toNumber() + 1);
        var strength = 0.55 + 0.45 * (level / 4.0);
        for (var i = 0; i < n; i++) {
            var x = (i * colW + colW / 2).toNumber();
            var t = moving ? phase : 0;
            var wave = 0.5 * Math.sin(t * 0.16 + i * 0.42) + 0.5 * Math.sin(t * 0.07 - i * 0.19);
            var top = h * (0.13 + 0.05 * wave);
            var len = h * 0.24 * strength * (0.75 + 0.25 * Math.sin(t * 0.23 + i * 0.9));
            if (!moving) {
                len = len * 0.6;
            }
            // Violet fringe on top when strong, bright green core, deeper green at the base.
            if (level >= 3) {
                dc.setColor(VIOLET, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x, top.toNumber(), x, (top + len * 0.18).toNumber());
            }
            dc.setColor(moving ? GREEN : DEEP, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, (top + len * 0.18).toNumber(), x, (top + len * 0.55).toNumber());
            dc.setColor(DEEP, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, (top + len * 0.55).toNumber(), x, (top + len).toNumber());
        }
        dc.setPenWidth(1);
    }

    function setAnimation(on) {
        if (on && anim == null) {
            anim = new Timer.Timer();
            anim.start(method(:onFrame), 100, true);
        } else if (!on && anim != null) {
            anim.stop();
            anim = null;
        }
    }

    function onFrame() as Void {
        phase += 1;
        WatchUi.requestUpdate();
    }

    // Page 1 ------------------------------------------------------------

    function drawSpace(dc, w, h, data) {
        var cx = w / 2;
        title(dc, w, h, WatchUi.loadResource(Rez.Strings.SpaceTitle));
        var kp = data["kp"];
        dc.setColor(kpColor(kp), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.27, Graphics.FONT_NUMBER_MEDIUM, kp == null ? "--" : kp.format("%.1f"), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        var sub = WatchUi.loadResource(Rez.Strings.KpNow) as String;
        if (data["kpMax"] != null) {
            sub = sub + "  ·  " + WatchUi.loadResource(Rez.Strings.Max24) + " " + data["kpMax"].format("%.0f");
        }
        line(dc, w, h * 0.375, Graphics.FONT_XTINY, sub);

        // Kp for the next 24 h, one bar per 3-hour block, scale 0–9, line at 5 (storm).
        var series = data["kp24"];
        if (series instanceof Array && series.size() > 0) {
            var left = w * 0.2;
            var width = w * 0.6;
            var base = h * 0.6;
            var height = h * 0.17;
            var n = series.size();
            var gap = 3;
            var barW = (width - gap * (n - 1)) / n;
            dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(left.toNumber(), (base - height * 5 / 9).toNumber(), (left + width).toNumber(), (base - height * 5 / 9).toNumber());
            for (var i = 0; i < n; i++) {
                var v = series[i];
                if (v == null) {
                    continue;
                }
                var bh = height * (v > 9 ? 9 : v) / 9.0;
                if (bh < 2) {
                    bh = 2;
                }
                dc.setColor(kpColor(v), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle((left + i * (barW + gap)).toNumber(), (base - bh).toNumber(), barW.toNumber(), bh.toNumber());
            }
            if (data["kpStart"] != null) {
                dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
                dc.drawText(left.toNumber(), base.toNumber() + 2, Graphics.FONT_XTINY, clock(data["kpStart"]), Graphics.TEXT_JUSTIFY_LEFT);
                dc.drawText((left + width).toNumber(), base.toNumber() + 2, Graphics.FONT_XTINY, "+24h", Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var wind = "";
        if (data["bz"] != null) {
            wind = "Bz " + signed(data["bz"]) + " nT";
        }
        if (data["speed"] != null) {
            wind = wind + "  ·  " + data["speed"].format("%.0f") + " km/s";
        }
        var bz = data["bz"];
        dc.setColor(bz != null && bz <= -5 ? GREEN : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        line(dc, w, h * 0.705, Graphics.FONT_TINY, wind);

        var ground = "";
        if (data["hp30"] != null) {
            ground = "Hp30 " + data["hp30"].format("%.1f");
        }
        if (data["mag"] != null) {
            ground = ground + "  ·  " + fieldName(data["mag"]);
        }
        dc.setColor(data["mag"] != null && data["mag"] >= 2 ? GREEN : ACCENT, Graphics.COLOR_TRANSPARENT);
        line(dc, w, h * 0.785, Graphics.FONT_XTINY, ground);

        if (data["arrival"] != null) {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            line(dc, w, h * 0.855, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Arrives) + " " + data["arrival"].format("%.0f") + " min");
        }
    }

    // Page 2 ------------------------------------------------------------

    function drawWeather(dc, w, h, data) {
        var cx = w / 2;
        var gust = data["gust"];
        var fraction = gust == null ? 0 : gust / 30.0;
        ring(dc, w, h, fraction > 1 ? 1 : fraction, NordurApi.gustColor(gust));
        var place = data["place"] != null ? (data["place"] as String).toUpper() : "NORDUR";
        title(dc, w, h, place);

        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.23, Graphics.FONT_XTINY, WatchUi.loadResource(Rez.Strings.Gusts), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(NordurApi.gustColor(gust), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.41, Graphics.FONT_NUMBER_HOT, NordurApi.speed(gust), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        line(dc, w, h * 0.545, Graphics.FONT_XTINY, NordurApi.unitLabel() + " · " + gustLabel(gust));

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var wind = WatchUi.loadResource(Rez.Strings.Wind) + " " + NordurApi.speed(data["wind"]) + " " + NordurApi.unitLabel();
        if (data["dir"] != null) {
            wind = wind + " " + WatchUi.loadResource(Rez.Strings.From) + " " + compass(data["dir"]);
        }
        line(dc, w, h * 0.635, Graphics.FONT_TINY, wind);

        var weather = "";
        if (data["temp"] != null) {
            weather = data["temp"].format("%.0f") + "°";
        }
        var sky = skyLabel(data["sky"]);
        if (sky != null) {
            weather = weather + "  " + sky;
        }
        line(dc, w, h * 0.72, Graphics.FONT_TINY, weather);
        footer(dc, w, h, data);
    }

    // MARK: Pieces

    function title(dc, w, h, text) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        line(dc, w, h * 0.10, Graphics.FONT_XTINY, text);
    }

    // One centred line, shrunk to the width of the round screen at that height.
    function line(dc, w, y, font, text) {
        if (text == null || text.equals("")) {
            return;
        }
        var fitted = Graphics.fitTextToArea(text, font, w * 0.78, dc.getFontHeight(font) + 2, true);
        dc.drawText(w / 2, y, font, fitted, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function ring(dc, w, h, fraction, color) {
        var radius = (w < h ? w : h) / 2 - 6;
        dc.setPenWidth(w / 30);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(w / 2, h / 2, radius, Graphics.ARC_CLOCKWISE, 225, 315);
        if (fraction > 0.01) {
            var end = 225 - 270 * fraction;
            if (end < 0) {
                end += 360;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(w / 2, h / 2, radius, Graphics.ARC_CLOCKWISE, 225, end.toNumber());
        }
        dc.setPenWidth(1);
    }

    // Page indicator on the right edge.
    function dots(dc, w, h) {
        for (var i = 0; i < 3; i++) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : 0x555555, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w - w / 18, h / 2 + (i - 1) * (h / 22), i == page ? 4 : 3);
        }
    }

    function footer(dc, w, h, data) {
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        var text = "...";
        if (model.status != :loading && data["t"] != null) {
            text = clock(data["t"]);
            if (model.status != :ok) {
                text = WatchUi.loadResource(Rez.Strings.DataFrom) + " " + text;
            }
        }
        line(dc, w, h * 0.875, Graphics.FONT_XTINY, text);
    }

    function clock(seconds) {
        var info = Gregorian.info(new Time.Moment(seconds as Number), Time.FORMAT_SHORT);
        return info.hour.format("%02d") + ":" + info.min.format("%02d");
    }

    function signed(v) {
        return (v > 0 ? "+" : "") + v.format("%.1f");
    }

    function levelColor(level) {
        if (level >= 4) {
            return VIOLET;
        } else if (level >= 2) {
            return GREEN;
        } else if (level == 1) {
            return 0x7FBFA0;
        }
        return DIM;
    }

    function levelName(level) {
        var names = [Rez.Strings.Lvl0, Rez.Strings.Lvl1, Rez.Strings.Lvl2, Rez.Strings.Lvl3, Rez.Strings.Lvl4];
        return WatchUi.loadResource(names[level < 0 ? 0 : (level > 4 ? 4 : level)]);
    }

    function fieldName(level) {
        var names = [Rez.Strings.Field0, Rez.Strings.Field1, Rez.Strings.Field2, Rez.Strings.Field3];
        return WatchUi.loadResource(names[level < 0 ? 0 : (level > 3 ? 3 : level)]);
    }

    function kpColor(kp) {
        if (kp == null) {
            return DIM;
        } else if (kp >= 7) {
            return 0xFF3B30;
        } else if (kp >= 5) {
            return VIOLET;
        } else if (kp >= 4) {
            return GREEN;
        }
        return ACCENT;
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
