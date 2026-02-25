## CoFi — Asistente de productividad con IA (Flutter + Firebase)

[![Flutter](https://img.shields.io/badge/Flutter-Framework-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-Language-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com/)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-4B5563)](#)

CoFi es una aplicación de **Gestión de finanzas colaborativas** desarrollada en **Flutter** que integra **autenticación con Firebase**, **notificaciones** (Firebase Messaging + Local Notifications) y funcionalidades basadas en IA para gestionar **conversaciones y recomendaciones** mediante una API externa.

---

## Tecnologías

- **Flutter / Dart**
- **Firebase**
  - `firebase_core`
  - `firebase_auth`
  - `firebase_messaging`
- **Notificaciones**
  - `flutter_local_notifications`
  - `permission_handler`
- **Auth social**
  - `google_sign_in`
- **Networking**
  - `http`
- **Utilidades**
  - `intl`, `path_provider`, `record`, `flutter_tts`, `fl_chart`, `flutter_slidable`

---

## Características 

- **Gestión de finanzas colaborativas**
  - Crea y administra espacios/grupos para organizar gastos con amigos, pareja o equipos.
  - Comparte la visibilidad del presupuesto y movimientos con los miembros del grupo.

- **Registro y control de gastos e ingresos**
  - Añade movimientos con monto, categoría y fecha.
  - Historial de transacciones para seguimiento y auditoría rápida.

- **Presupuestos y seguimiento**
  - Define presupuestos por categoría o por periodo y monitorea el avance.
  - Visualización del estado financiero para tomar decisiones informadas.

- **Balance y reparto de gastos**
  - Calcula balances entre miembros (quién debe a quién) para simplificar cierres.
  - Facilita la conciliación de cuentas al final de un periodo o evento.

- **Notificaciones**
  - Alertas sobre actividad relevante (p. ej., nuevos gastos, recordatorios o eventos del grupo), integrando notificaciones locales y push.

- **Onboarding y experiencia guiada**
  - Flujo de bienvenida para comprender rápidamente la app y su propuesta de valor.

- **Autenticación y seguridad**
  - Inicio de sesión con Firebase Authentication (con base para proveedor social como Google).
  - Consumo de servicios protegido con token (ID token) del usuario.

- **Asistente con IA (conversaciones)**
  - Gestión de conversaciones con IA mediante API externa, para apoyo en consultas, resúmenes o insights (según la configuración del backend).

---

## Pre-requisitos

Antes de comenzar, asegúrate de tener instalado:

- **Git**
- **Flutter SDK** (compatible con el proyecto; ver `environment: sdk` en `pubspec.yaml`)
- **Dart SDK** (incluido con Flutter)
- Para Android:
  - **Android Studio** + Android SDK + un emulador o dispositivo físico
- Para iOS (solo macOS):
  - **Xcode** + CocoaPods (`sudo gem install cocoapods`)
- (Recomendado) **FlutterFire CLI** si necesitas reconfigurar Firebase:
  - `dart pub global activate flutterfire_cli`

> Importante: el proyecto ya incluye `lib/firebase_options.dart`, por lo que normalmente **no necesitas** regenerarlo para ejecutar en local, a menos que cambies de proyecto Firebase.

---

## Instalación y Configuración (5 minutos)

### 1) Clonar el repositorio
```bash
git clone https://github.com/ErickGC546/C24_6_2025-2_G15_CoFi_F.git
cd C24_6_2025-2_G15_CoFi_F
```

### 2) Instalar dependencias
```bash
flutter pub get
```

### 3) (Opcional) Verificar entorno
```bash
flutter doctor
```

### 4) Configuración Firebase (si fuese necesaria)
El arranque inicializa Firebase aquí:

- `lib/main.dart` (usa `Firebase.initializeApp(...)`)
- `lib/firebase_options.dart` (opciones por plataforma)

Si necesitas apuntar a **otro** proyecto Firebase:
```bash
flutterfire configure
```
y luego vuelve a ejecutar:
```bash
flutter pub get
```

---

## Uso

### Ejecutar en local (modo debug)

**Android:**
```bash
flutter run
```

**Chrome (Web):**
```bash
flutter run -d chrome
```

**iOS (macOS):**
```bash
cd ios
pod install
cd ..
flutter run
```

### Comandos útiles
```bash
flutter clean
flutter pub get
flutter test
```
