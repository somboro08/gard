#!/usr/bin/env python3
"""Génère l'icône (adaptative + classique + monochrome) et le logo du splash Android.

Usage :  python3 tool/gen_icons.py          (nécessite Pillow ; police Poppins Bold)
Sortie : tool/android_res/…  (copié dans android/ par tool/setup_platforms.dart)
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'android_res')
GOLD = (245, 184, 0, 255)       # = AppPalette.gold
BLACK = (11, 11, 11, 255)       # = fond sombre de l'appli
SS = 4                           # sur-échantillonnage pour des bords nets
FONT_CANDIDATES = [
    '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
]


def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def shield(cx, cy, w, h):
    """Contour d'un écusson : épaules arrondies, pointe en bas."""
    x0, x1 = cx - w / 2, cx + w / 2
    top, bot = cy - h / 2, cy + h / 2
    r = w * 0.16
    pts = []
    pts += bezier((x0, top + r), (x0, top + r * 0.2), (x0 + r * 0.2, top), (x0 + r, top), 16)
    pts += bezier((x0 + r, top), (cx - w * 0.12, top - h * 0.02), (cx + w * 0.12, top - h * 0.02), (x1 - r, top), 24)
    pts += bezier((x1 - r, top), (x1 - r * 0.2, top), (x1, top + r * 0.2), (x1, top + r), 16)
    pts += bezier((x1, top + r), (x1, top + h * 0.58), (cx + w * 0.30, top + h * 0.84), (cx, bot), 60)
    pts += bezier((cx, bot), (cx - w * 0.30, top + h * 0.84), (x0, top + h * 0.58), (x0, top + r), 60)
    return pts


def font(size):
    for f in FONT_CANDIDATES:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    sys.exit('Aucune police trouvée.')


def draw_mark(size, shield_h_ratio, bg=None, fill=GOLD, letter=BLACK, cut_letter=False):
    """Écusson + « G » sur un canevas carré [size]. bg=None → transparent."""
    S = size * SS
    img = Image.new('RGBA', (S, S), bg or (0, 0, 0, 0))
    h = S * shield_h_ratio
    w = h * 0.84
    cx, cy = S / 2, S / 2 - h * 0.01
    d = ImageDraw.Draw(img)
    d.polygon(shield(cx, cy, w, h), fill=fill)
    f = font(int(h * 0.64))
    mask = Image.new('L', (S, S), 0)
    md = ImageDraw.Draw(mask)
    md.text((cx, cy - h * 0.07), 'G', font=f, fill=255, anchor='mm')
    if cut_letter:
        # lettre « évidée » (icône monochrome thématique) : on retire le G de l'alpha
        alpha = img.getchannel('A')
        alpha = Image.composite(Image.new('L', (S, S), 0), alpha, mask)
        img.putalpha(alpha)
    else:
        img.paste(Image.new('RGBA', (S, S), letter), (0, 0), mask)
    return img.resize((size, size), Image.LANCZOS)


def rounded_square(size, radius_ratio, color):
    S = size * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * radius_ratio), fill=color)
    return img.resize((size, size), Image.LANCZOS)


def save(img, rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


DENSITY = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

for name, k in DENSITY.items():
    # Icône classique (API < 26) : carré arrondi noir + écusson doré.
    legacy = int(48 * k)
    base = rounded_square(legacy, 0.22, BLACK)
    base.alpha_composite(draw_mark(legacy, 0.66))
    save(base, f'mipmap-{name}/ic_launcher.png')

    # Icône adaptative (API 26+) : calque 108 dp, zone sûre ≈ 66 dp.
    layer = int(108 * k)
    save(draw_mark(layer, 0.47), f'drawable-{name}/ic_launcher_foreground.png')
    # Monochrome (icônes thématiques Android 13+) : forme blanche, G évidé.
    save(draw_mark(layer, 0.47, fill=(255, 255, 255, 255), cut_letter=True),
         f'drawable-{name}/ic_launcher_monochrome.png')

# Logo du splash (≈ 144 dp en xxhdpi ; Android 12+ le centre dans un cercle).
save(draw_mark(432, 0.60), 'drawable-xxhdpi/splash_logo.png')

XML = {
    'mipmap-anydpi-v26/ic_launcher.xml': '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
''',
    'values/garde_colors.xml': '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0B0B0B</color>
    <color name="splash_background">#0B0B0B</color>
</resources>
''',
}
launch = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Splash natif Garde (fond noir + écusson doré) : remplace le logo Flutter par défaut. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_background"/>
    <item>
        <bitmap android:gravity="center" android:src="@drawable/splash_logo"/>
    </item>
</layer-list>
'''
XML['drawable/launch_background.xml'] = launch
XML['drawable-v21/launch_background.xml'] = launch


def styles(normal_parent):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Thème affiché pendant le démarrage natif. Les attributs windowSplashScreen*
         sont pris en compte à partir d'Android 12 et ignorés avant. -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/splash_background</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_logo</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Thème appliqué dès que Flutter a dessiné sa première image. -->
    <style name="NormalTheme" parent="{normal_parent}">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
'''


XML['values/styles.xml'] = styles('@android:style/Theme.Light.NoTitleBar')
XML['values-night/styles.xml'] = styles('@android:style/Theme.Black.NoTitleBar')

for rel, content in XML.items():
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# Aperçu (non copié dans l'appli) pour contrôle visuel.
prev = Image.new('RGBA', (1100, 560), (60, 60, 60, 255))
a = rounded_square(512, 0.22, BLACK)
a.alpha_composite(draw_mark(512, 0.66))
prev.alpha_composite(a, (20, 20))
circ = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
bgc = Image.new('RGBA', (512, 512), BLACK)
bgc.alpha_composite(draw_mark(512, 0.47 * 1.2))
m = Image.new('L', (512 * SS, 512 * SS), 0)
ImageDraw.Draw(m).ellipse((0, 0, 512 * SS - 1, 512 * SS - 1), fill=255)
circ.paste(bgc, (0, 0), m.resize((512, 512), Image.LANCZOS))
prev.alpha_composite(circ, (560, 20))
prev.save(os.path.join(os.path.dirname(OUT), 'icon_preview.png'))
print('OK ->', OUT)
