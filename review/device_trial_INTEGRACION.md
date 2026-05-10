# Device trial anti-abuso — integración

## Archivos tocados en el repo

- `pubspec.yaml`: dependencias `device_info_plus` y `crypto` (directa).
- `lib/device_trial_service.dart`: **nuevo** — lógica Firestore + huella de dispositivo.
- `lib/paywall_screen.dart`: llamadas antes/después de `Purchases.purchasePackage`.

**No se modificó `main.dart`.** Si en el futuro usás `PremiumService.comprarPremium()` u otra ruta de compra, conviene llamar a los mismos métodos de `DeviceTrialService` allí.

## Identificador de dispositivo

- **iOS:** `identifierForVendor` vía `device_info_plus`.
- **Android:** `device_info_plus` no expone `ANDROID_ID`; se usa una huella `fingerprint + brand + model + device`, hasheada con SHA-256 para el ID de documento. Es estable para el mismo dispositivo/ROM; si necesitás `ANDROID_ID` estricto, habría que ampliar con otro plugin o un method channel.

## Reglas Firestore

Ver `review/device_trial_firestore_rules.txt`.

## Mensaje al usuario

Texto bloqueante: *"Ya usaste el período de prueba gratuito en este dispositivo."*

## RevenueCat

El registro en Firestore solo ocurre si, tras la compra, algún entitlement **activo** tiene `periodType` `trial` o `intro`. Suscripciones directas sin intro no marcan el dispositivo (otro usuario en el mismo equipo podría obtener trial según la tienda; si querés marcar cualquier primera suscripción, cambiá `customerInfoIsTrialOrIntro`).
