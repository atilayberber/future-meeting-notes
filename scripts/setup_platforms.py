"""Android/iOS platform klasörleri oluşturulduktan sonra (flutter create) izinleri ve
minimum sürümleri ayarlar. kurulum.ps1'in yaptığının aynısı; CI'da (GitHub Actions) kullanılır.

Kullanım: proje kökünde  python3 scripts/setup_platforms.py
"""
import os
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

# --- Android minSdk 24 (+ isteğe bağlı sabit NDK sürümü)
# ANDROID_NDK_VERSION verilirse (CI'da makinede kurulu olan sürüm) o kullanılır;
# böylece Gradle derleme sırasında NDK indirmeye çalışmaz.
ndk = os.environ.get("ANDROID_NDK_VERSION", "").strip()
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    f = root / name
    if f.exists():
        t = f.read_text(encoding="utf-8")
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
        # Release'te R8 küçültmeyi kapat: eklentilerin JNI ile çağrılan metotlarını
        # (ör. shared_preferences getAll) silip açılışta NoSuchMethodError'a yol açıyordu.
        if "isMinifyEnabled" not in t and name.endswith(".kts"):
            t = re.sub(
                r'(signingConfig\s*=\s*signingConfigs\.getByName\("debug"\))',
                r'\1\n            isMinifyEnabled = false\n            isShrinkResources = false',
                t,
            )
        elif "minifyEnabled" not in t and not name.endswith(".kts"):
            t = re.sub(
                r"(signingConfig\s+signingConfigs\.debug)",
                r"\1\n            minifyEnabled false\n            shrinkResources false",
                t,
            )
        if ndk:
            t = re.sub(r"ndkVersion\s*=\s*flutter\.ndkVersion", f'ndkVersion = "{ndk}"', t)
            t = re.sub(r"ndkVersion\s+flutter\.ndkVersion", f'ndkVersion "{ndk}"', t)
        f.write_text(t, encoding="utf-8")

# --- Sabit test imzası: her derleme aynı anahtarla imzalanır, böylece yeni APK
# eskisinin üzerine (silmeden) kurulabilir. Anahtar: signing/key.properties
kts = root / "android/app/build.gradle.kts"
if (root / "signing/key.properties").exists() and kts.exists():
    t = kts.read_text(encoding="utf-8")
    if 'create("fmnTest")' not in t:
        if "import java.util.Properties" not in t:
            t = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + t
        block = (
            "    signingConfigs {\n"
            '        create("fmnTest") {\n'
            '            val p = Properties().apply { load(FileInputStream(rootProject.file("../signing/key.properties"))) }\n'
            '            storeFile = rootProject.file("../signing/" + p.getProperty("storeFile"))\n'
            '            storePassword = p.getProperty("storePassword")\n'
            '            keyAlias = p.getProperty("keyAlias")\n'
            '            keyPassword = p.getProperty("keyPassword")\n'
            "        }\n"
            "    }\n\n"
        )
        t = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + block.rstrip("\n") + r"\1", t, count=1)
        t = t.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = signingConfigs.getByName("fmnTest")')
        kts.write_text(t, encoding="utf-8")

# --- Yedek önlem: küçültme ileride açılırsa eklenti sınıfları korunsun
(root / "android/app/proguard-rules.pro").write_text(
    "-keep class io.flutter.plugins.** { *; }\n"
    "-keep class com.github.dart_lang.jni.** { *; }\n"
    "-keep class dev.fluttercommunity.** { *; }\n"
    "-keep class com.llfbandit.record.** { *; }\n"
    "-keep class com.k2fsa.** { *; }\n"
    "-keepclassmembers class * { @androidx.annotation.Keep *; }\n",
    encoding="utf-8",
)

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
