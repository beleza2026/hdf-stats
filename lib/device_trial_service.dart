import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Anti-abuso de trial: un dispositivo solo puede consumir el trial una vez,
/// aunque el usuario cree otra cuenta de Firebase.
///
/// Colección Firestore: [collectionName]. Documento = hash estable del dispositivo.
class DeviceTrialService {
  DeviceTrialService._();

  static const String collectionName = 'device_trials';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Clave cruda antes de hashear (para depuración; no persistir en claro).
  static Future<String?> _rawDeviceKey() async {
    if (kIsWeb) return null;
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      // device_info_plus no expone ANDROID_ID; fingerprint+marca+modelo es estable por build/ROM.
      return 'android|${a.fingerprint}|${a.brand}|${a.model}|${a.device}';
    }
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      final v = i.identifierForVendor;
      if (v != null && v.isNotEmpty) return 'ios|$v';
      return 'ios|unknown';
    }
    return null;
  }

  /// ID de documento Firestore (SHA-256 hex, sin caracteres problemáticos).
  static Future<String?> deviceDocumentId() async {
    final raw = await _rawDeviceKey();
    if (raw == null || raw.isEmpty) return null;
    final digest = sha256.convert(utf8.encode(raw));
    return digest.toString();
  }

  /// Antes de lanzar el checkout de RevenueCat: bloquea si otro UID ya usó trial aquí.
  static Future<DeviceTrialGateResult> verifyTrialAllowedForUser(User user) async {
    final docId = await deviceDocumentId();
    if (docId == null) {
      return DeviceTrialGateResult.allowed();
    }
    final snap = await _db.collection(collectionName).doc(docId).get();
    if (!snap.exists) return DeviceTrialGateResult.allowed();

    final data = snap.data()!;
    final prevUid = data['uid'] as String?;
    final hasUsed = data['hasUsedTrial'] == true;
    if (!hasUsed) return DeviceTrialGateResult.allowed();
    if (prevUid == user.uid) return DeviceTrialGateResult.allowed();

    return DeviceTrialGateResult.blocked(
      'Ya usaste el período de prueba gratuito en este dispositivo.',
    );
  }

  /// True si algún entitlement **activo** está en trial o precio introductorio.
  static bool customerInfoIsTrialOrIntro(CustomerInfo info) {
    for (final e in info.entitlements.active.values) {
      if (e.periodType == PeriodType.trial || e.periodType == PeriodType.intro) {
        return true;
      }
    }
    return false;
  }

  /// Tras compra exitosa: si entró en trial/intro, registra el dispositivo.
  static Future<void> registerTrialIfApplicable({
    required User user,
    required CustomerInfo customerInfo,
  }) async {
    if (!customerInfoIsTrialOrIntro(customerInfo)) return;
    final docId = await deviceDocumentId();
    if (docId == null) return;

    final email = user.email ?? '';
    await _db.collection(collectionName).doc(docId).set({
      'uid': user.uid,
      'email': email,
      'trialStartDate': FieldValue.serverTimestamp(),
      'hasUsedTrial': true,
    }, SetOptions(merge: true));
  }
}

class DeviceTrialGateResult {
  final bool allowed;
  final String? blockMessage;

  const DeviceTrialGateResult._({required this.allowed, this.blockMessage});

  factory DeviceTrialGateResult.allowed() =>
      const DeviceTrialGateResult._(allowed: true);

  factory DeviceTrialGateResult.blocked(String message) =>
      DeviceTrialGateResult._(allowed: false, blockMessage: message);
}
