#!/usr/bin/env python3
# generate-oled-srgb-profile.py
#
# Samsung ATNA40HQ02-0 OLED パネル (100% DCI-P3) 用の ICC プロファイルを生成する。
# EDID の色度座標から sRGB 色域にクランプする VCGT (Video Card Gamma Table) 付き
# ICC v2 プロファイルを作成する。
#
# VCGT は gnome-settings-daemon が読み取り、ディスプレイのガンマランプに適用する。
# これにより、カラーマネジメント非対応のアプリも含めて全画面が sRGB 相当に補正される。
#
# Usage:
#   python3 generate-oled-srgb-profile.py [output.icc]

import struct
import math
import sys
from datetime import datetime, timezone

# Samsung ATNA40HQ02-0 OLED パネルの EDID 色度座標
DISPLAY_PRIMARIES = {
    'r': (0.6826, 0.3164),
    'g': (0.2451, 0.7138),
    'b': (0.1396, 0.0439),
    'w': (0.3125, 0.3291),
}

# sRGB (IEC 61966-2-1) 色度座標
SRGB_PRIMARIES = {
    'r': (0.6400, 0.3300),
    'g': (0.3000, 0.6000),
    'b': (0.1500, 0.0600),
    'w': (0.3127, 0.3290),
}

# Bradford 色順応変換行列 (D65 → D50)
# ICC プロファイルは PCS として D50 を使うため必要
BRADFORD_D65_TO_D50 = [
    [ 1.0479298208405488,  0.0229468736674009, -0.0501922295431913],
    [ 0.0296278156881593,  0.9904344267538799, -0.0170738250293851],
    [-0.0092430581525912,  0.0150551448965779,  0.7518742899580008],
]

VCGT_SIZE = 256


def xy_to_XYZ(x, y):
    return [x / y, 1.0, (1 - x - y) / y]


def mat_mul(A, v):
    return [sum(A[i][j] * v[j] for j in range(3)) for i in range(3)]


def mat_inv(m):
    a, b, c = m[0]; d, e, f = m[1]; g, h, i = m[2]
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [
        [(e*i - f*h) / det, (c*h - b*i) / det, (b*f - c*e) / det],
        [(f*g - d*i) / det, (a*i - c*g) / det, (c*d - a*f) / det],
        [(d*h - e*g) / det, (b*g - a*h) / det, (a*e - b*d) / det],
    ]


def mat_mat(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def primaries_to_matrix(p):
    """色度座標から RGB→XYZ 変換行列を計算"""
    r, g, b, w = [xy_to_XYZ(*p[k]) for k in ('r', 'g', 'b', 'w')]
    M = [[r[0], g[0], b[0]], [r[1], g[1], b[1]], [r[2], g[2], b[2]]]
    S = mat_mul(mat_inv(M), w)
    return [[M[i][j] * S[j] for j in range(3)] for i in range(3)]


def srgb_eotf(x):
    """sRGB EOTF (エンコード値 → リニア)"""
    x = max(0.0, min(1.0, x))
    return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4


def srgb_oetf(x):
    """sRGB OETF (リニア → エンコード値)"""
    x = max(0.0, min(1.0, x))
    return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055


# --- ICC バイナリヘルパー ---

def s15f16(v):
    return struct.pack('>i', int(round(v * 65536)))


def u8f8(v):
    return struct.pack('>H', int(round(v * 256)))


def pad4(d):
    r = len(d) % 4
    return d + b'\x00' * (4 - r) if r else d


def make_xyz_tag(X, Y, Z):
    return b'XYZ \x00\x00\x00\x00' + s15f16(X) + s15f16(Y) + s15f16(Z)


def make_desc_tag(text):
    a = text.encode('ascii') + b'\x00'
    d = b'desc\x00\x00\x00\x00' + struct.pack('>I', len(a)) + a
    d += struct.pack('>II', 0, 0) + struct.pack('>HB', 0, 0) + b'\x00' * 67
    return pad4(d)


def make_text_tag(text):
    return pad4(b'text\x00\x00\x00\x00' + text.encode('ascii') + b'\x00')


def make_curv_tag(gamma):
    return pad4(b'curv\x00\x00\x00\x00' + struct.pack('>I', 1) + u8f8(gamma))


def make_vcgt_tag(lut_r, lut_g, lut_b):
    n = len(lut_r)
    d = b'vcgt\x00\x00\x00\x00' + struct.pack('>I', 0)
    d += struct.pack('>HHH', n, n, n) + struct.pack('>H', 2)
    for ch in (lut_r, lut_g, lut_b):
        for v in ch:
            d += struct.pack('>H', int(round(max(0, min(65535, v * 65535)))))
    return pad4(d)


def generate_profile(output_path):
    # sRGB→ディスプレイネイティブ変換行列を計算
    M_srgb = primaries_to_matrix(SRGB_PRIMARIES)
    M_disp = primaries_to_matrix(DISPLAY_PRIMARIES)
    M_s2d = mat_mat(mat_inv(M_disp), M_srgb)

    # D50 色順応を適用したディスプレイ XYZ 値
    M_disp_d50 = mat_mat(BRADFORD_D65_TO_D50, M_disp)
    rXYZ = [M_disp_d50[i][0] for i in range(3)]
    gXYZ = [M_disp_d50[i][1] for i in range(3)]
    bXYZ = [M_disp_d50[i][2] for i in range(3)]
    wXYZ = [sum(M_disp_d50[i][j] for j in range(3)) for i in range(3)]

    # VCGT LUT 生成 (1D per-channel: 対角要素でスケーリング)
    lut_r, lut_g, lut_b = [], [], []
    for i in range(VCGT_SIZE):
        v = i / (VCGT_SIZE - 1)
        lin = srgb_eotf(v)
        lut_r.append(srgb_oetf(max(0, min(1, M_s2d[0][0] * lin))))
        lut_g.append(srgb_oetf(max(0, min(1, M_s2d[1][1] * lin))))
        lut_b.append(srgb_oetf(max(0, min(1, M_s2d[2][2] * lin))))

    # タグを構築
    tags = {}
    tags[b'desc'] = make_desc_tag("Samsung ATNA40HQ02-0 sRGB Clamped")
    tags[b'dmnd'] = make_desc_tag("Samsung Display Corp.")
    tags[b'dmdd'] = make_desc_tag("ATNA40HQ02-0 OLED 2880x1800")
    tags[b'wtpt'] = make_xyz_tag(*wXYZ)
    tags[b'rXYZ'] = make_xyz_tag(*rXYZ)
    tags[b'gXYZ'] = make_xyz_tag(*gXYZ)
    tags[b'bXYZ'] = make_xyz_tag(*bXYZ)
    trc = make_curv_tag(2.2)
    tags[b'rTRC'] = trc
    tags[b'gTRC'] = trc
    tags[b'bTRC'] = trc
    tags[b'cprt'] = make_text_tag("No copyright")
    tags[b'vcgt'] = make_vcgt_tag(lut_r, lut_g, lut_b)

    # プロファイルを組み立て
    tag_count = len(tags)
    header_size = 128
    tag_table_size = 4 + tag_count * 12
    data_offset = header_size + tag_table_size
    if data_offset % 4:
        data_offset += 4 - (data_offset % 4)

    tag_entries = []
    tag_data = b''
    for sig, blob in tags.items():
        tag_entries.append((sig, data_offset + len(tag_data), len(blob)))
        tag_data += blob

    profile_size = data_offset + len(tag_data)

    now = datetime.now(timezone.utc)
    header = struct.pack('>I', profile_size) + b'lcms'
    header += struct.pack('>BBH', 2, 1, 0) + b'mntr' + b'RGB ' + b'XYZ '
    header += struct.pack('>HHH', now.year, now.month, now.day)
    header += struct.pack('>HHH', now.hour, now.minute, now.second)
    header += b'acsp' + b'APPL' + struct.pack('>I', 0)
    header += b'\x00' * 4 + b'\x00' * 4 + b'\x00' * 8
    header += struct.pack('>I', 0)
    header += s15f16(0.9642) + s15f16(1.0000) + s15f16(0.8249)
    header += b'\x00' * 4 + b'\x00' * 16 + b'\x00' * 28
    assert len(header) == 128

    tag_table = struct.pack('>I', tag_count)
    for sig, off, sz in tag_entries:
        tag_table += sig + struct.pack('>II', off, sz)

    profile = header + tag_table
    profile += b'\x00' * (data_offset - len(profile))
    profile += tag_data
    assert len(profile) == profile_size

    with open(output_path, 'wb') as f:
        f.write(profile)

    print(f"[OK] ICC プロファイルを生成: {output_path} ({profile_size} bytes)")
    print(f"     VCGT スケーリング: R={M_s2d[0][0]:.4f} G={M_s2d[1][1]:.4f} B={M_s2d[2][2]:.4f}")


if __name__ == '__main__':
    output = sys.argv[1] if len(sys.argv) > 1 else "samsung-oled-srgb-clamped.icc"
    generate_profile(output)
