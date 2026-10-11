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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBxrxu9dha-wFvUQtoh-mmoypjncywUFUQ',
    appId: '1:470110564561:android:ba57c88a17f6e5b73815f0',
    messagingSenderId: '470110564561',
    projectId: 'lotto-hotspot-finder',
    storageBucket: 'lotto-hotspot-finder.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBxrxu9dha-wFvUQtoh-mmoypjncywUFUQ',
    appId: '1:470110564561:ios:placeholder',
    messagingSenderId: '470110564561',
    projectId: 'lotto-hotspot-finder',
    storageBucket: 'lotto-hotspot-finder.firebasestorage.app',
    iosBundleId: 'com.luckylotto.finder',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBxrxu9dha-wFvUQtoh-mmoypjncywUFUQ',
    appId: '1:470110564561:web:8f79ce694837e6493815f0',
    messagingSenderId: '470110564561',
    projectId: 'lotto-hotspot-finder',
    storageBucket: 'lotto-hotspot-finder.firebasestorage.app',
    authDomain: 'lotto-hotspot-finder.firebaseapp.com',
  );
}
