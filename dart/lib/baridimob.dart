/// Unofficial Dart and Flutter SDK for BaridiMob (Algérie Poste).
///
/// Start with [BaridiMob]:
///
/// ```dart
/// import 'package:baridimob/baridimob.dart';
///
/// final bm = BaridiMob(storage: FileStorage('session.json'));
/// await bm.auth.login(login: 'login', password: 'password');
/// final balance = await bm.accounts.balance();
/// ```
library;

export 'src/client.dart'
    show
        AccountsModule,
        AuthModule,
        BaridiMob,
        DynamicPaymentsModule,
        PasswordHasher,
        PaymentsModule,
        ProfileModule,
        ReceiptsModule,
        TransfersModule;
export 'src/errors.dart' hide errorForResult, raiseForResult;
export 'src/keys.dart'
    show
        DeviceKeys,
        algorithmHash,
        deriveDevkey,
        devkeyAlgorithm,
        devkeyAlgorithmHash,
        generateDeviceKeys,
        sha256Hex;
export 'src/parse.dart' hide parseAccountResponse;
export 'src/result.dart' show resultNameFor;
export 'src/sign.dart' show initialStamp, signJsonBody, signParams;
export 'src/storage.dart';
export 'src/types.dart';
