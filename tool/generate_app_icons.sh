#!/usr/bin/env bash
#
# Genera los iconos de lanzador de todas las plataformas a partir de los dos
# masters de assets/icon/. Se hace con ImageMagick en vez de con el paquete
# flutter_launcher_icons para no meter una dependencia nueva en pubspec.yaml
# (los archivos generados se commitean, así que esto solo se corre cuando
# cambia el logo).
#
#   assets/icon/icon.png             1024x1024 opaco  — escudo sobre el fondo
#                                     de marca; se usa tal cual en iOS/macOS/web
#                                     y como icono legacy de Android (<= API 25).
#   assets/icon/icon_foreground.png  1024x1024 con alfa — capa de primer plano
#                                     del icono adaptativo de Android (API 26+).
#                                     El escudo va más chico a propósito: la
#                                     máscara del launcher recorta hasta el 33%
#                                     exterior del lienzo.
#
# Ambos salieron de assets/icon/sosecure_logo.png (el logo completo con texto)
# recortando solo el escudo — el texto no se lee a 48px, así que el icono es
# únicamente la marca.
#
# Uso:  ./tool/generate_app_icons.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

ICON="assets/icon/icon.png"
FG="assets/icon/icon_foreground.png"
# Fondo de marca del logo original — también es la capa de fondo del icono
# adaptativo de Android (android/app/src/main/res/values/colors.xml).
BG="#F7F7F7"

command -v magick >/dev/null || { echo "Falta ImageMagick (magick)"; exit 1; }

# `-strip` quita metadatos; en iOS además hay que quitar el canal alfa o
# App Store Connect rechaza el binario.
res()  { magick "$ICON" -resize "${1}x${1}" -strip -depth 8 "$2"; }
resa() { magick "$ICON" -resize "${1}x${1}" -background "$BG" -alpha remove -alpha off -strip -depth 8 "$2"; }
resf() { magick "$FG"   -resize "${1}x${1}" -strip -depth 8 "$2"; }

echo "Android — icono legacy (mipmap-*/ic_launcher.png)"
A=android/app/src/main/res
res  48 "$A/mipmap-mdpi/ic_launcher.png"
res  72 "$A/mipmap-hdpi/ic_launcher.png"
res  96 "$A/mipmap-xhdpi/ic_launcher.png"
res 144 "$A/mipmap-xxhdpi/ic_launcher.png"
res 192 "$A/mipmap-xxxhdpi/ic_launcher.png"

echo "Android — primer plano del icono adaptativo (API 26+)"
resf 108 "$A/mipmap-mdpi/ic_launcher_foreground.png"
resf 162 "$A/mipmap-hdpi/ic_launcher_foreground.png"
resf 216 "$A/mipmap-xhdpi/ic_launcher_foreground.png"
resf 324 "$A/mipmap-xxhdpi/ic_launcher_foreground.png"
resf 432 "$A/mipmap-xxxhdpi/ic_launcher_foreground.png"

echo "iOS — AppIcon.appiconset"
I=ios/Runner/Assets.xcassets/AppIcon.appiconset
resa   20 "$I/Icon-App-20x20@1x.png"
resa   40 "$I/Icon-App-20x20@2x.png"
resa   60 "$I/Icon-App-20x20@3x.png"
resa   29 "$I/Icon-App-29x29@1x.png"
resa   58 "$I/Icon-App-29x29@2x.png"
resa   87 "$I/Icon-App-29x29@3x.png"
resa   40 "$I/Icon-App-40x40@1x.png"
resa   80 "$I/Icon-App-40x40@2x.png"
resa  120 "$I/Icon-App-40x40@3x.png"
resa  120 "$I/Icon-App-60x60@2x.png"
resa  180 "$I/Icon-App-60x60@3x.png"
resa   76 "$I/Icon-App-76x76@1x.png"
resa  152 "$I/Icon-App-76x76@2x.png"
resa  167 "$I/Icon-App-83.5x83.5@2x.png"
resa 1024 "$I/Icon-App-1024x1024@1x.png"

echo "macOS — AppIcon.appiconset"
M=macos/Runner/Assets.xcassets/AppIcon.appiconset
for s in 16 32 64 128 256 512 1024; do resa "$s" "$M/app_icon_${s}.png"; done

echo "Web — favicon + iconos PWA"
res  32 web/favicon.png
res 192 web/icons/Icon-192.png
res 512 web/icons/Icon-512.png
# Los iconos "maskable" se recortan hasta el 20% exterior, así que llevan el
# escudo del tamaño de la capa adaptativa sobre el fondo de marca.
magick -size 192x192 xc:"$BG" \( "$FG" -resize 192x192 \) -composite -strip -depth 8 web/icons/Icon-maskable-192.png
magick -size 512x512 xc:"$BG" \( "$FG" -resize 512x512 \) -composite -strip -depth 8 web/icons/Icon-maskable-512.png

echo "Windows — app_icon.ico"
magick "$ICON" -define icon:auto-resize=256,128,96,64,48,32,16 windows/runner/resources/app_icon.ico

echo "Listo."
