#!/usr/bin/env python3
"""
日の出・日没に基づいて GNOME のダークモード/ライトモードを自動切替するスクリプト。

外部依存なし (Python 標準ライブラリのみ使用)。
緯度経度は ~/.config/auto-darkmode/location.conf から読み込む。
"""

import math
import datetime
import subprocess
import sys
import os
import configparser

CONFIG_DIR = os.path.expanduser("~/.config/auto-darkmode")
CONFIG_FILE = os.path.join(CONFIG_DIR, "location.conf")


def load_config():
    if not os.path.exists(CONFIG_FILE):
        print(f"[ERROR] 設定ファイルが見つかりません: {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    lat = config.getfloat("location", "latitude")
    lon = config.getfloat("location", "longitude")
    return lat, lon


def calc_sunrise_sunset(lat, lon, date):
    """
    NOAA のアルゴリズムに基づいて日の出・日没時刻を UTC 時間で計算する。
    返り値: (sunrise_utc_hours, sunset_utc_hours) — 24時間制の浮動小数点数
    極夜/白夜の場合は None を返す。
    """
    day_of_year = date.timetuple().tm_yday
    lng_hour = lon / 15.0

    def sun_time(is_rise):
        if is_rise:
            t = day_of_year + ((6 - lng_hour) / 24)
        else:
            t = day_of_year + ((18 - lng_hour) / 24)

        # 太陽の平均近点角
        M = (0.9856 * t) - 3.289

        # 太陽の黄経
        L = M + (1.916 * math.sin(math.radians(M))) \
              + (0.020 * math.sin(math.radians(2 * M))) + 282.634
        L = L % 360

        # 赤経
        RA = math.degrees(math.atan(0.91764 * math.tan(math.radians(L))))
        RA = RA % 360
        L_quad = (L // 90) * 90
        RA_quad = (RA // 90) * 90
        RA = (RA + (L_quad - RA_quad)) / 15  # 時間に変換

        # 赤緯
        sin_dec = 0.39782 * math.sin(math.radians(L))
        cos_dec = math.cos(math.asin(sin_dec))

        # 時角
        zenith = 90.833
        cos_H = (math.cos(math.radians(zenith))
                 - (sin_dec * math.sin(math.radians(lat)))) \
                / (cos_dec * math.cos(math.radians(lat)))

        if cos_H > 1:
            return None  # 太陽が昇らない (極夜)
        if cos_H < -1:
            return None  # 太陽が沈まない (白夜)

        if is_rise:
            H = (360 - math.degrees(math.acos(cos_H))) / 15
        else:
            H = math.degrees(math.acos(cos_H)) / 15

        # 地方平均時
        T = H + RA - (0.06571 * t) - 6.622
        # UTC
        UT = (T - lng_hour) % 24
        return UT

    return sun_time(True), sun_time(False)


def utc_hours_to_local_time(utc_hours):
    """UTC 時間 (浮動小数点) をローカルの時・分に変換"""
    # UTC オフセットを加算してローカル時刻を得る
    local_offset_hours = datetime.datetime.now().astimezone().utcoffset().total_seconds() / 3600
    local_hours = (utc_hours + local_offset_hours) % 24
    h = int(local_hours)
    m = int((local_hours - h) * 60)
    return h, m


def get_current_scheme():
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
        capture_output=True, text=True
    )
    return result.stdout.strip().strip("'")


def set_scheme(dark):
    scheme = "prefer-dark" if dark else "default"
    subprocess.run(
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme],
        check=True
    )
    return scheme


def main():
    lat, lon = load_config()
    today = datetime.date.today()
    sunrise_utc, sunset_utc = calc_sunrise_sunset(lat, lon, today)

    if sunrise_utc is None or sunset_utc is None:
        print("[WARN] 日の出/日没を計算できません (極地域)")
        return

    sr_h, sr_m = utc_hours_to_local_time(sunrise_utc)
    ss_h, ss_m = utc_hours_to_local_time(sunset_utc)
    now = datetime.datetime.now()
    now_minutes = now.hour * 60 + now.minute
    sunrise_minutes = sr_h * 60 + sr_m
    sunset_minutes = ss_h * 60 + ss_m

    is_daytime = sunrise_minutes <= now_minutes <= sunset_minutes
    should_be_dark = not is_daytime

    current = get_current_scheme()
    current_is_dark = (current == "prefer-dark")

    sunrise_str = f"{sr_h:02d}:{sr_m:02d}"
    sunset_str = f"{ss_h:02d}:{ss_m:02d}"
    now_str = now.strftime("%H:%M")

    if should_be_dark == current_is_dark:
        mode = "dark" if current_is_dark else "light"
        print(f"[SKIP] 既に {mode} モード (日の出 {sunrise_str} / 日没 {sunset_str} / 現在 {now_str})")
    else:
        set_scheme(should_be_dark)
        mode = "dark" if should_be_dark else "light"
        print(f"[OK] {mode} モードに切替 (日の出 {sunrise_str} / 日没 {sunset_str} / 現在 {now_str})")


if __name__ == "__main__":
    main()
