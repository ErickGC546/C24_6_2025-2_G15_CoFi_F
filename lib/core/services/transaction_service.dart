import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class TransactionService {
  static const String baseUrl = "https://co-fi-web.vercel.app/api";

  // ✅ Crear transacción
  static Future<Map<String, dynamic>> createTransaction({
    required double amount,
    required String type,
    required String note,
    String? categoryId,
    String? goalId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");
    final token = await user.getIdToken();

    final response = await http.post(
      Uri.parse("$baseUrl/transactions"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "amount": amount,
        "type": type,
        "note": note,
        if (categoryId != null) "categoryId": categoryId,
        if (goalId != null) "goalId": goalId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al crear transacción: ${response.body}");
    }
  }

  // ✅ Eliminar transacción
  static Future<Map<String, dynamic>> deleteTransaction(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");
    final token = await user.getIdToken();

    final response = await http.delete(
      Uri.parse("$baseUrl/transactions/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al eliminar transacción: ${response.body}");
    }
  }

  // ✅ Actualizar transacción
  static Future<Map<String, dynamic>> updateTransaction({
    required String id,
    required double amount,
    required String type,
    required String note,
    String? categoryId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");
    final token = await user.getIdToken();

    final response = await http.put(
      Uri.parse("$baseUrl/transactions/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "amount": amount,
        "type": type,
        "note": note,
        "categoryId": categoryId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al actualizar transacción: ${response.body}");
    }
  }
}
