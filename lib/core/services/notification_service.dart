import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// Tipos de notificaciones
enum NotificationType {
  budgetExceeded,
  budgetWarning,
  goalAchieved,
  groupContribution,
  groupWithdrawal,
  memberJoined,
  memberLeft,
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  static const String baseUrl = 'https://cofi-backend.vercel.app/api';

  // Inicializar servicio de notificaciones
  static Future<void> initialize() async {
    try {
      // 1. Solicitar permisos
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Permisos de notificación concedidos');
      } else {
        print('⚠️ Permisos de notificación denegados');
      }

      // 2. Configurar notificaciones locales
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // 3. Configurar canal de notificaciones para Android
      const androidChannel = AndroidNotificationChannel(
        'cofi_notifications',
        'Notificaciones CoFi',
        description: 'Notificaciones de presupuesto, metas y grupos',
        importance: Importance.high,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidChannel);

      // 4. Obtener token FCM y guardarlo en el backend
      String? token = await _fcm.getToken();
      if (token != null) {
        print('📱 FCM Token: $token');
        await _saveFCMToken(token);
      }

      // 5. Escuchar actualizaciones del token
      _fcm.onTokenRefresh.listen(_saveFCMToken);

      // 6. Manejar mensajes en primer plano
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 7. Manejar tap en notificación cuando app está en background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

      print('✅ Servicio de notificaciones inicializado');
    } catch (e) {
      print('❌ Error inicializando notificaciones: $e');
    }
  }

  // Guardar token FCM en el backend
  static Future<void> _saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      final response = await http.post(
        Uri.parse('$baseUrl/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'action': 'save-token',
          'token': token,
          'platform': 'android', // o 'ios'
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Token FCM guardado en backend');
      }
    } catch (e) {
      print('❌ Error guardando token FCM: $e');
    }
  }

  // Manejar notificación cuando la app está en primer plano
  static void _handleForegroundMessage(RemoteMessage message) {
    print('📩 Mensaje recibido en primer plano');

    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _showLocalNotification(
        notification.title ?? 'CoFi',
        notification.body ?? '',
        message.data,
      );
    }
  }

  // Manejar tap en notificación desde background
  static void _handleBackgroundMessageTap(RemoteMessage message) {
    print('📲 Notificación tocada desde background');
    // Aquí puedes navegar a una pantalla específica
  }

  // Manejar tap en notificación local
  static void _onNotificationTap(NotificationResponse response) {
    print('📲 Notificación local tocada: ${response.payload}');
    // Aquí puedes navegar a una pantalla específica
  }

  // Mostrar notificación local
  static Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'cofi_notifications',
      'Notificaciones CoFi',
      channelDescription: 'Notificaciones de presupuesto, metas y grupos',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: jsonEncode(data),
    );
  }

  // Obtener lista de notificaciones del backend
  static Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 20,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('$baseUrl/notifications?limit=$limit'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['notifications']);
      }

      return [];
    } catch (e) {
      print('❌ Error obteniendo notificaciones: $e');
      return [];
    }
  }

  // Obtener contador de notificaciones no leídas
  static Future<int> getUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;

      final idToken = await user.getIdToken();

      final response = await http.get(
        Uri.parse('$baseUrl/notifications?action=unread-count'),
        headers: {'Authorization': 'Bearer $idToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }

      return 0;
    } catch (e) {
      print('❌ Error obteniendo contador: $e');
      return 0;
    }
  }

  // Marcar notificación como leída
  static Future<void> markAsRead(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      await http.patch(
        Uri.parse('$baseUrl/notifications/$notificationId'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (e) {
      print('❌ Error marcando como leída: $e');
    }
  }

  // Marcar todas como leídas
  static Future<void> markAllAsRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      await http.post(
        Uri.parse('$baseUrl/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'action': 'mark-all-read'}),
      );
    } catch (e) {
      print('❌ Error marcando todas como leídas: $e');
    }
  }

  // Eliminar notificación
  static Future<void> deleteNotification(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();

      await http.delete(
        Uri.parse('$baseUrl/notifications/$notificationId'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (e) {
      print('❌ Error eliminando notificación: $e');
    }
  }

  // Cancelar todas las notificaciones locales
  static Future<void> cancelAllLocalNotifications() async {
    await _notifications.cancelAll();
  }
}
