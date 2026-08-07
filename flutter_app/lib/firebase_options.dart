// ──────────────────────────────────────────────────────────────────────────
// 이 파일은 Firebase 설정 완료 후 flutterfire CLI가 자동 생성합니다.
// 터미널에서: dart pub global activate flutterfire_cli
//             flutterfire configure
// ──────────────────────────────────────────────────────────────────────────
// 또는 아래 값을 Firebase 콘솔에서 직접 복사해 채워주세요.
// ──────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Android (google-services.json 값을 여기에 복사) ──────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',           // ← Firebase 콘솔에서 복사
    appId: 'YOUR_ANDROID_APP_ID',             // ← Firebase 콘솔에서 복사
    messagingSenderId: 'YOUR_SENDER_ID',      // ← Firebase 콘솔에서 복사
    projectId: 'YOUR_PROJECT_ID',             // ← Firebase 콘솔에서 복사
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // ── iOS (GoogleService-Info.plist 값을 여기에 복사) ──────────────
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.luckylotto.finder',
  );

  // ── Web (필요시) ─────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
  );
}
