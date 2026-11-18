// Configure les dossiers android/ et ios/ générés par `flutter create`
// (permission caméra, liens WhatsApp/appel, versions minimales).
//
// Usage, depuis la racine du projet :
//   flutter create --platforms=android,ios --project-name garde --org bj.mrl .
//   dart run tool/setup_platforms.dart
//
// Le script est idempotent : on peut le relancer sans risque.
import 'dart:io';

void main() {
  _patchAndroidManifest();
  _patchAndroidGradle();
  _installAndroidResources();
  _patchIosPlist();
  _patchIosPodfile();
  stdout.writeln('\nTerminé. Lancez maintenant : flutter pub get && flutter run');
}

/// Icône de l'appli + splash natif (remplace le logo Flutter par défaut).
/// Sources : tool/android_res (régénérables avec tool/gen_icons.py).
void _installAndroidResources() {
  final src = Directory('tool/android_res');
  const destRoot = 'android/app/src/main/res';
  if (!src.existsSync()) {
    stdout.writeln('• ignoré (introuvable) : tool/android_res');
    return;
  }
  if (!Directory(destRoot).existsSync()) {
    stdout.writeln('• ignoré (introuvable) : $destRoot');
    return;
  }
  var n = 0;
  for (final e in src.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = e.path.substring(src.path.length + 1);
    final out = File('$destRoot/$rel');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(e.readAsBytesSync());
    n++;
  }
  // Le modèle Flutter peut aussi fournir mipmap-*/ic_launcher.webp : il masquerait nos PNG.
  for (final f in Directory(destRoot).listSync(recursive: true)) {
    if (f is File && RegExp(r'ic_launcher(_round)?\.webp$').hasMatch(f.path)) f.deleteSync();
  }
  stdout.writeln('✓ icône et splash installés ($n fichiers) dans $destRoot');
}

String? _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('• ignoré (introuvable) : $path');
    return null;
  }
  return f.readAsStringSync();
}

void _write(String path, String content) {
  File(path).writeAsStringSync(content);
  stdout.writeln('✓ mis à jour : $path');
}

void _patchAndroidManifest() {
  const path = 'android/app/src/main/AndroidManifest.xml';
  var s = _read(path);
  if (s == null) return;
  final before = s;

  if (!s.contains('android.permission.CAMERA')) {
    const perms = '''    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>
''';
    s = s.replaceFirst(RegExp(r'[ \t]*<application'), '$perms    <application');
  }

  if (!s.contains('android:scheme="https"')) {
    const intents = '''        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
''';
    if (s.contains('<queries>')) {
      s = s.replaceFirst('<queries>', '<queries>\n$intents');
    } else {
      s = s.replaceFirst('</manifest>', '    <queries>\n$intents    </queries>\n</manifest>');
    }
  }

  s = s.replaceAll('android:label="garde"', 'android:label="Garde"');

  if (s != before) {
    _write(path, s);
  } else {
    stdout.writeln('• déjà configuré : $path');
  }
}

void _patchAndroidGradle() {
  for (final path in const ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final s = _read(path);
    if (s == null) continue;
    final out = s
        .replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 24')
        .replaceAll('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24');
    if (out != s) {
      _write(path, out);
    } else {
      stdout.writeln('• minSdk déjà configuré (ou format inconnu) : $path');
    }
  }
}

void _patchIosPlist() {
  const path = 'ios/Runner/Info.plist';
  final s = _read(path);
  if (s == null) return;
  if (s.contains('NSCameraUsageDescription')) {
    stdout.writeln('• déjà configuré : $path');
    return;
  }
  const entry = '''	<key>NSCameraUsageDescription</key>
	<string>La caméra sert à scanner les plaques et les QR codes des tickets.</string>
''';
  final i = s.lastIndexOf('</dict>');
  if (i < 0) {
    stdout.writeln('! format inattendu : $path (ajoutez NSCameraUsageDescription à la main)');
    return;
  }
  _write(path, s.replaceRange(i, i, entry));
}

void _patchIosPodfile() {
  const path = 'ios/Podfile';
  final s = _read(path);
  if (s == null) return;
  final re = RegExp(r"^\s*#?\s*platform :ios, '[\d.]+'", multiLine: true);
  if (!re.hasMatch(s)) {
    stdout.writeln("! ligne « platform :ios » introuvable : $path (mettez '15.5' à la main)");
    return;
  }
  final out = s.replaceFirst(re, "platform :ios, '15.5'");
  if (out != s) {
    _write(path, out);
  } else {
    stdout.writeln('• déjà configuré : $path');
  }
}
