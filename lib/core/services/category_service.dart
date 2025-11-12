import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Servicio para manejar operaciones con categorías
class CategoryService {
  static const String baseUrl = "https://co-fi-web.vercel.app/api";

  /// Obtiene todas las categorías del usuario
  static Future<List<Map<String, dynamic>>> getCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");

    final token = await user.getIdToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/categories'),
        headers: headers,
      );

      if (res.statusCode != 200) return [];

      final body = res.body.trim();
      if (body.isEmpty) return [];

      final decoded = json.decode(body);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (decoded is Map && decoded['data'] is List) {
        return (decoded['data'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching categories: $e');
      return [];
    }
  }

  /// Crea una nueva categoría
  /// [name] - Nombre de la categoría
  /// [type] - Tipo de categoría: 'income' o 'expense'
  /// [description] - Descripción opcional de la categoría
  static Future<Map<String, dynamic>?> createCategory({
    required String name,
    String type = 'expense',
    String? description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");

    final token = await user.getIdToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    try {
      final payload = {
        'name': name,
        'type': type,
        if (description != null && description.isNotEmpty)
          'description': description,
      };

      final res = await http.post(
        Uri.parse('$baseUrl/categories'),
        headers: headers,
        body: json.encode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = res.body.trim();
        if (body.isEmpty) return null;

        final decoded = json.decode(body);
        if (decoded is Map) {
          // Si la respuesta tiene un campo 'category', usarlo
          if (decoded['category'] is Map) {
            return Map<String, dynamic>.from(decoded['category']);
          }
          // Si no, retornar el objeto completo
          return Map<String, dynamic>.from(decoded);
        }
        return null;
      } else {
        print('Error creating category: ${res.statusCode} - ${res.body}');
        return null;
      }
    } catch (e) {
      print('Exception creating category: $e');
      return null;
    }
  }

  /// Actualiza una categoría existente
  static Future<bool> updateCategory({
    required String categoryId,
    String? name,
    String? type,
    String? description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");

    final token = await user.getIdToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    try {
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name;
      if (type != null) payload['type'] = type;
      if (description != null) payload['description'] = description;

      final res = await http.put(
        Uri.parse('$baseUrl/categories/$categoryId'),
        headers: headers,
        body: json.encode(payload),
      );

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('Exception updating category: $e');
      return false;
    }
  }

  /// Elimina una categoría
  static Future<bool> deleteCategory(String categoryId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");

    final token = await user.getIdToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/categories/$categoryId'),
        headers: headers,
      );

      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('Exception deleting category: $e');
      return false;
    }
  }
}
