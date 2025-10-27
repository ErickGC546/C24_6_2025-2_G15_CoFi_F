// group_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class GroupService {
  final String baseUrl = "https://co-fi-web.vercel.app/api/groups";

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }
    return await user.getIdToken();
  }

  /// 🟢 Crear grupo
  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? description,
    required double savingGoal,
    String privacy = "invite_only",
  }) async {
    final token = await _getToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };

    final Map<String, dynamic> body = {
      "name": name,
      "privacy": privacy,
      "savingGoal": savingGoal,
    };
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al crear grupo: ${response.body}');
    }
  }

  /// 🟣 Listar grupos del usuario
  Future<List<dynamic>> getUserGroups() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener grupos: ${response.body}");
    }
  }

  /// 🟡 Obtener detalle de un grupo
  Future<Map<String, dynamic>> getGroupDetail(String id) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener detalle del grupo: ${response.body}");
    }
  }

  /// 🟣 Invitar miembro por email
  Future<Map<String, dynamic>> inviteMember({
    required String groupId,
    required String inviteeEmail,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/invites"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"groupId": groupId, "inviteeEmail": inviteeEmail}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al enviar invitación: ${response.body}");
    }
  }

  /// 💰 Añadir una transacción (ahorro o retiro)
  Future<Map<String, dynamic>> addTransaction({
    required String groupId,
    required double amount,
    required String type,
    String? description,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/$groupId/transactions"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "amount": amount,
        "type": type,
        "description": description,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al agregar transacción: ${response.body}");
    }
  }

  /// 📜 Obtener historial de transacciones de un grupo
  Future<List<dynamic>> getTransactions(String groupId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/$groupId/transactions"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      if (response.statusCode == 404) {
        return [];
      }
      throw Exception("Error al obtener transacciones: ${response.body}");
    }
  }
  
  /// 🔗 Generar un link de invitación
  Future<String> generateInviteLink(String groupId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/$groupId/generate-invite"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['inviteLink'];
    } else {
      throw Exception("Error al generar el link de invitación: ${response.body}");
    }
  }
}