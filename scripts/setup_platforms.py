"""Android/iOS platform klasörleri oluşturulduktan sonra (flutter create) izinleri ve
minimum sürümleri ayarlar. kurulum.ps1'in yaptığının aynısı; CI'da (GitHub Actions) kullanılır.

Kullanım: proje kökünde  python3 scripts/setup_platforms.py
"""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent

# --- Android izinleri
manifest = root / "android/app/src/main/AndroidManifest.xml"
xml = manifest.read_text(encoding="utf-8")
perms = ""
for perm in ("RECORD_AUDIO", "WAKE_LOCK", "INTERNET"):
    if f'android.permission.{perm}"' not in xml:
        perms += f'\n    <uses-permission android:name="android.permission.{perm}"/>'
if perms:
    xml = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + perms, xml, count=1)
    manifest.write_text(xml, encoding="utf-8")

# --- Android minSdk 24
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    f = root / name
    if f.exists():
        t = f.read_text(encoding="utf-8")
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
        f.write_text(t, encoding="utf-8")

# --- iOS izinleri
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    p = plist.read_text(encoding="utf-8")
    if "NSMicrophoneUsageDescription" not in p:
        add = (
            "\t<key>NSMicrophoneUsageDescription</key>\n"
            "\t<string>Toplantıyı kaydetmek ve katılımcıların sesini tanımak için mikrofon kullanılır.</string>\n"
            "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n"
            "\t<key>UIFileSharingEnabled</key>\n\t<true/>\n"
            "\t<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>\n"
        )
        i = p.rfind("</dict>")
        plist.write_text(p[:i] + add + p[i:], encoding="utf-8")

# --- iOS en az 13.0 (sherpa_onnx gereksinimi)
podfile = root / "ios/Podfile"
if podfile.exists():
    t = podfile.read_text(encoding="utf-8")
    t = re.sub(r"#\s*platform :ios, '[0-9.]+'", "platform :ios, '13.0'", t)
    podfile.write_text(t, encoding="utf-8")

print("Platform ayarları tamam.")
