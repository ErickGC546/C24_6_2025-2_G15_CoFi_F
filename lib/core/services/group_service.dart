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
    String privacy = "invite_only",
  }) async {
    final token = await _getToken();
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
      "Accept": "application/json",
    };

    // Build body without null fields to avoid sending "description": null
    final Map<String, dynamic> body = {"name": name, "privacy": privacy};
    if (description != null && description.trim().isNotEmpty) {
      body['description'] = description.trim();
    }

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      // Try to parse error body to give a clearer message
      try {
        final parsed = jsonDecode(response.body);
        final message = parsed is Map
            ? (parsed['error'] ?? parsed['message'] ?? response.body)
            : response.body;
        throw Exception(
          'Error al crear grupo: $message (status ${response.statusCode})',
        );
      } catch (_) {
        throw Exception(
          'Error al crear grupo: ${response.body} (status ${response.statusCode})',
        );
      }
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

  /// 🟠 Actualizar grupo
  Future<Map<String, dynamic>> updateGroup({
    required String id,
    required String name,
    String? description,
    String? privacy,
  }) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse("$baseUrl/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "name": name,
        "description": description,
        "privacy": privacy,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al actualizar grupo: ${response.body}");
    }
  }

  /// 🔴 Eliminar grupo
  Future<void> deleteGroup(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse("$baseUrl/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Error al eliminar grupo: ${response.body}");
    }
  }

  /// 🟣 Invitar miembro
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

  /// 🟢 Unirse a grupo por código
  Future<Map<String, dynamic>> joinGroup(String joinCode) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/join"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"joinCode": joinCode}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al unirse al grupo: ${response.body}");
    }
  }

  /// 🟡 Salir de un grupo
  Future<Map<String, dynamic>> leaveGroup(String groupId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/members/leave"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"groupId": groupId}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Some responses may not include a body. Return an empty map in that case.
      if (response.body.trim().isEmpty) return {};
      return jsonDecode(response.body);
    } else {
      // Try to parse the body to extract a friendly message
      try {
        final parsed = jsonDecode(response.body);
        final message = parsed is Map
            ? (parsed['error'] ?? parsed['message'] ?? response.body)
            : response.body;
        if (response.statusCode == 403) {
          throw Exception('No autorizado: $message');
        } else if (response.statusCode == 404) {
          throw Exception('Grupo no encontrado: $message');
        }
        throw Exception(
          'Error al salir del grupo: $message (status ${response.statusCode})',
        );
      } catch (_) {
        // If response body isn't valid JSON or is empty, fall back to a generic message
        final bodyText = response.body.trim().isEmpty
            ? 'HTTP ${response.statusCode}'
            : response.body;
        throw Exception('Error al salir del grupo: $bodyText');
      }
    }
  }

  /// � Crear meta (savings)
  /// Body: { title, targetAmount, targetDate?, groupId? }
  Future<Map<String, dynamic>> createSaving({
    required String title,
    required num targetAmount,
    String? targetDate,
    String? groupId,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/savings"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "title": title,
        "targetAmount": targetAmount,
        if (targetDate != null) "targetDate": targetDate,
        if (groupId != null) "groupId": groupId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al crear meta: ${response.body}");
    }
  }

  /// 🟣 Listar metas (si groupId dado, devuelve metas del grupo)
  Future<List<dynamic>> getSavings({String? groupId}) async {
    final token = await _getToken();
    final uri = groupId != null
        ? Uri.parse("$baseUrl/savings?groupId=$groupId")
        : Uri.parse("$baseUrl/savings");
    final response = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener metas: ${response.body}");
    }
  }

  /// 🟡 Obtener meta por id
  Future<Map<String, dynamic>> getSavingById(String id) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/savings/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener meta: ${response.body}");
    }
  }

  /// 🟠 Actualizar meta
  Future<Map<String, dynamic>> updateSaving({
    required String id,
    required Map<String, dynamic> body,
  }) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse("$baseUrl/savings/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al actualizar meta: ${response.body}");
    }
  }

  /// 🔴 Eliminar meta
  Future<void> deleteSaving(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse("$baseUrl/savings/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      throw Exception("Error al eliminar meta: ${response.body}");
    }
  }

  /// 🟣 Agregar movimiento/ingreso a una meta
  /// NOTE: backend path for movements is inferred. If your backend uses a different
  /// endpoint, update this method accordingly.
  Future<Map<String, dynamic>> createSavingMovement({
    required String savingId,
    required num amount,
    String? note,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/savings/$savingId/movements"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"amount": amount, if (note != null) "note": note}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al crear movimiento: ${response.body}");
    }
  }

  /// �🟣 Listar miembros de un grupo
  Future<List<dynamic>> getGroupMembers(String groupId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/members?groupId=$groupId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener miembros: ${response.body}");
    }
  }

  /// Obtener joinCode (solo para owner/admins según backend)
  Future<String?> getJoinCode(String groupId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse("$baseUrl/$groupId/joincode"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      return parsed is Map ? parsed['joinCode'] as String? : null;
    } else if (response.statusCode == 403) {
      // No autorizado para ver el código
      return null;
    } else if (response.statusCode == 404) {
      throw Exception('Grupo no encontrado');
    } else {
      throw Exception('Error al obtener joinCode: ${response.body}');
    }
  }

  /// Regenerar joinCode (solo owner/admins)
  Future<String> regenerateJoinCode(String groupId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse("$baseUrl/$groupId/joincode"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed['joinCode'] != null)
        return parsed['joinCode'] as String;
      throw Exception('Respuesta inesperada al regenerar código');
    } else if (response.statusCode == 403) {
      throw Exception('No autorizado para regenerar el código');
    } else {
      throw Exception('Error al regenerar código: ${response.body}');
    }
  }

  /// 🟠 Actualizar rol de miembro
  Future<Map<String, dynamic>> updateMemberRole({
    required String memberId,
    required String newRole,
  }) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse("$baseUrl/members"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"memberId": memberId, "newRole": newRole}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al actualizar rol: ${response.body}");
    }
  }

  /// 🔴 Eliminar miembro
  Future<void> deleteMember(String memberId) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse("$baseUrl/members"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"memberId": memberId}),
    );

    if (response.statusCode != 200) {
      throw Exception("Error al eliminar miembro: ${response.body}");
    }
  }
}
