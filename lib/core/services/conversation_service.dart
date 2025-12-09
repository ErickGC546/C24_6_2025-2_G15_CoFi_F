import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// 🗨️ Servicio para gestionar conversaciones con la IA
class ConversationService {
  static const String baseUrl =
      "https://co-fi-web.vercel.app/api/ai/conversations";

  /// Obtener token de autenticación del usuario actual
  static Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  /// 🟢 Obtener todas las conversaciones del usuario
  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception('Error al obtener conversaciones: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en getConversations: $e');
      rethrow;
    }
  }

  /// 🟣 Crear nueva conversación
  static Future<Map<String, dynamic>> createConversation({
    String? title,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'title': title ?? 'Nueva conversación'}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error al crear conversación: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en createConversation: $e');
      rethrow;
    }
  }

  /// 🟢 Obtener una conversación específica con todos sus mensajes
  static Future<Map<String, dynamic>> getConversationById(String id) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Conversación no encontrada');
      } else {
        throw Exception('Error al obtener conversación: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en getConversationById: $e');
      rethrow;
    }
  }

  /// 🔴 Eliminar conversación
  static Future<bool> deleteConversation(String id) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 404) {
        throw Exception('Conversación no encontrada');
      } else {
        throw Exception('Error al eliminar conversación: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en deleteConversation: $e');
      rethrow;
    }
  }

  /// 🟡 Actualizar título de conversación
  static Future<bool> updateConversationTitle(String id, String title) async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Usuario no autenticado');
      }

      final response = await http.patch(
        Uri.parse('$baseUrl/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'title': title}),
      );

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 404) {
        throw Exception('Conversación no encontrada');
      } else if (response.statusCode == 400) {
        throw Exception('Título inválido');
      } else {
        throw Exception('Error al actualizar título: ${response.body}');
      }
    } catch (e) {
      print('❌ Error en updateConversationTitle: $e');
      rethrow;
    }
  }
}
