# Future Meeting Notes - ilk kurulum (Windows PowerShell)
# Kullanım: proje klasöründe
#   powershell -ExecutionPolicy Bypass -File kurulum.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host '1/4 Android ve iOS platform klasörleri oluşturuluyor...'
# Mevcut dosyalar (lib/, pubspec.yaml) korunur; yalnızca eksikler oluşturulur.
flutter create --org com.bicen --project-name future_meeting_notes --platforms android,ios .
if (Test-Path 'test/widget_test.dart') { Remove-Item 'test/widget_test.dart' }

Write-Host '2/4 Android izinleri ekleniyor...'
$manifest = Join-Path $PSScriptRoot 'android/app/src/main/AndroidManifest.xml'
$xml = [IO.File]::ReadAllText($manifest)
$perms = ''
foreach ($perm in @('RECORD_AUDIO', 'WAKE_LOCK', 'INTERNET')) {
    if ($xml -notmatch "android.permission.$perm""") {
        $perms += "`n    <uses-permission android:name=""android.permission.$perm""/>"
    }
}
if ($perms -ne '') {
    $xml = [regex]::Replace($xml, '(<manifest[^>]*>)', '$1' + $perms, 1)
    [IO.File]::WriteAllText($manifest, $xml)
}

# Android minSdk 24
foreach ($g in @('android/app/build.gradle.kts', 'android/app/build.gradle')) {
    $path = Join-Path $PSScriptRoot $g
    if (Test-Path $path) {
        $t = [IO.File]::ReadAllText($path)
        $t = $t -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24'
        $t = $t -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24'
        [IO.File]::WriteAllText($path, $t)
    }
}

Write-Host '3/4 iOS izinleri ekleniyor...'
$plist = Join-Path $PSScriptRoot 'ios/Runner/Info.plist'
$p = [IO.File]::ReadAllText($plist)
if ($p -notmatch 'NSMicrophoneUsageDescription') {
    $add = @"
	<key>NSMicrophoneUsageDescription</key>
	<string>Toplantıyı kaydetmek ve katılımcıların sesini tanımak için mikrofon kullanılır.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
	<key>UIFileSharingEnabled</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>

"@
    $i = $p.LastIndexOf('</dict>')
    $p = $p.Substring(0, $i) + $add + $p.Substring($i)
    [IO.File]::WriteAllText($plist, $p)
}

# iOS en az 13.0 (sherpa_onnx gereksinimi)
$podfile = Join-Path $PSScriptRoot 'ios/Podfile'
if (Test-Path $podfile) {
    $pf = [IO.File]::ReadAllText($podfile)
    $pf = $pf -replace "#\s*platform :ios, '[0-9.]+'", "platform :ios, '13.0'"
    [IO.File]::WriteAllText($podfile, $pf)
}

Write-Host '4/4 Paketler indiriliyor ve testler çalıştırılıyor...'
flutter pub get
flutter test

Write-Host ''
Write-Host 'Kurulum tamam. Android telefonu USB ile bağlayıp: flutter run'
