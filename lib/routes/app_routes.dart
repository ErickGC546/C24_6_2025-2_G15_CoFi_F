// Definición de rutas de la app
import 'package:flutter/material.dart';
import '../features/splash/splash_view.dart';
import '../features/onboarding/onboarding1_view.dart';
import '../features/onboarding/onboarding2_view.dart';
import '../features/onboarding/onboarding3_view.dart';
import '../features/auth/login_view.dart';
import '../features/home/home_view.dart';
import '../features/home/notifications_view.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding1 = '/onboarding1';
  static const String onboarding2 = '/onboarding2';
  static const String onboarding3 = '/onboarding3';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String notifications = '/notifications';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const SplashView(),
      onboarding1: (context) => const Onboarding1View(),
      onboarding2: (context) => const Onboarding2View(),
      onboarding3: (context) => const Onboarding3View(),
      login: (context) => const LoginView(),

      home: (context) => const HomeView(),
      notifications: (context) => NotificationsView(),
    };
  }
}
