import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// 📋 SISTEMA DE ROLES EN GRUPOS
///
/// Hay 3 roles en los grupos:
/// 1. **Owner (Líder/Creador)**: Máximos privilegios
///    - ✅ Puede crear, editar y eliminar metas del grupo
///    - ✅ Puede promover miembros a Admin u Owner
///    - ✅ Puede gestionar todos los aspectos del grupo
///
/// 2. **Admin (Administrador)**: Privilegios de administración
///    - ✅ Puede crear, editar y eliminar metas del grupo
///    - ❌ NO puede cambiar roles de otros usuarios
///
/// 3. **Member (Miembro)**: Privilegios básicos
///    - ✅ Puede ver las metas del grupo
///    - ✅ Puede participar en el grupo
///    - ❌ NO puede crear, editar o eliminar metas
///    - ❌ NO puede cambiar roles
///
/// Solo el Owner puede dar permisos de Admin u Owner a los miembros.

class GroupService {
  final String baseUrl = "https://co-fi-web.vercel.app/api/groups";
  // Separate base for savings endpoints (they live under /api/savings)
  final String savingsBase = "https://co-fi-web.vercel.app/api/savings";

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }
    return await user.getIdToken();
  }

  /// ✅ Verificar si el usuario puede gestionar metas (crear, editar, eliminar)
  /// Solo Owner y Admin pueden gestionar metas
  bool canManageGoals(String? userRole) {
    if (userRole == null) return false;
    return userRole == 'owner' || userRole == 'admin';
  }

  /// ✅ Verificar si el usuario puede cambiar roles de otros usuarios
  /// Solo Owner puede cambiar roles
  bool canChangeRoles(String? userRole) {
    if (userRole == null) return false;
    return userRole == 'owner';
  }

  /// ✅ Verificar si el usuario puede ver las metas
  /// Todos los miembros pueden ver las metas
  bool canViewGoals(String? userRole) {
    return true; // Todos pueden ver
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

  /// 💾 Crear meta (savings)
  /// Body: { title, targetAmount, targetDate?, groupId? }
  /// Requiere rol de Admin u Owner si es para un grupo
  Future<Map<String, dynamic>> createSaving({
    required String title,
    required num targetAmount,
    String? targetDate,
    String? groupId,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse(savingsBase),
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
      // Try to parse a friendly message from the response body
      try {
        final parsed = jsonDecode(response.body);
        final message = parsed is Map
            ? (parsed['error'] ??
                  parsed['message'] ??
                  parsed['detail'] ??
                  response.body)
            : response.body;
        if (response.statusCode == 403) {
          throw Exception(
            'No tienes permisos para crear metas. Solo Admin y Owner pueden crear metas.',
          );
        }
        throw Exception(
          'Error al crear meta: $message (status ${response.statusCode})',
        );
      } catch (e) {
        if (e.toString().contains('No tienes permisos')) rethrow;
        // Fallback if body is not JSON or parsing fails
        final bodyText = response.body.trim().isEmpty
            ? 'HTTP ${response.statusCode}'
            : response.body;
        throw Exception(
          'Error al crear meta: $bodyText (status ${response.statusCode})',
        );
      }
    }
  }

  /// 🟣 Listar metas (si groupId dado, devuelve metas del grupo)
  Future<List<dynamic>> getSavings({String? groupId}) async {
    final token = await _getToken();
    final uri = groupId != null
        ? Uri.parse("$savingsBase?groupId=$groupId")
        : Uri.parse(savingsBase);
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
      Uri.parse("$savingsBase/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Error al obtener meta: ${response.body}");
    }
  }

  /// Obtener movimientos de una meta (intenta varias rutas comunes)
  Future<List<dynamic>> getSavingMovements(
    String savingId, {
    String? groupId,
  }) async {
    final token = await _getToken();
    final headers = {"Authorization": "Bearer $token"};

    // Try a set of candidate URIs for movements retrieval
    final candidates = <Uri>[];
    // per-saving route
    candidates.add(Uri.parse("$savingsBase/$savingId/movements"));
    candidates.add(Uri.parse("$savingsBase/$savingId/transactions"));
    candidates.add(Uri.parse("$savingsBase/$savingId/contributions"));

    // global movements with query
    // global movements with query (try different query param names the backend may expect)
    candidates.add(
      Uri.parse("https://co-fi-web.vercel.app/api/movements?goalId=$savingId"),
    );
    candidates.add(
      Uri.parse(
        "https://co-fi-web.vercel.app/api/movements?savingsGoalId=$savingId",
      ),
    );
    candidates.add(
      Uri.parse(
        "https://co-fi-web.vercel.app/api/movements?savingId=$savingId",
      ),
    );

    candidates.add(
      Uri.parse(
        "https://co-fi-web.vercel.app/api/contributions?goalId=$savingId",
      ),
    );
    candidates.add(
      Uri.parse(
        "https://co-fi-web.vercel.app/api/contributions?savingsGoalId=$savingId",
      ),
    );
    candidates.add(
      Uri.parse(
        "https://co-fi-web.vercel.app/api/contributions?savingId=$savingId",
      ),
    );

    candidates.add(Uri.parse("$savingsBase/movements?goalId=$savingId"));
    candidates.add(Uri.parse("$savingsBase/movements?savingsGoalId=$savingId"));
    candidates.add(Uri.parse("$savingsBase/movements?savingId=$savingId"));

    // if groupId provided, try group-scoped routes
    if (groupId != null && groupId.trim().isNotEmpty) {
      candidates.insert(
        0,
        Uri.parse("$baseUrl/$groupId/savings/$savingId/movements"),
      );
      candidates.insert(
        1,
        Uri.parse("$baseUrl/$groupId/savings/$savingId/transactions"),
      );
      candidates.insert(
        2,
        Uri.parse("$baseUrl/$groupId/savings/$savingId/contributions"),
      );
    }

    for (final u in candidates) {
      try {
        final resp = await http.get(u, headers: headers);
        if (resp.statusCode == 200) {
          final parsed = jsonDecode(resp.body);
          if (parsed is List) return parsed;
          if (parsed is Map && parsed['data'] is List) return parsed['data'];
          // some endpoints may return object with 'movements' key
          if (parsed is Map && parsed['movements'] is List)
            return parsed['movements'];
        }
      } catch (_) {}
    }
    return [];
  }

  /// 🟠 Actualizar meta
  /// Requiere rol de Admin u Owner si es para un grupo
  Future<Map<String, dynamic>> updateSaving({
    required String id,
    required Map<String, dynamic> body,
  }) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse("$savingsBase/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      // Check for permission errors
      if (response.statusCode == 403) {
        throw Exception(
          'No tienes permisos para editar metas. Solo Admin y Owner pueden editar metas.',
        );
      }
      throw Exception("Error al actualizar meta: ${response.body}");
    }
  }

  /// 🔴 Eliminar meta
  /// Requiere rol de Admin u Owner si es para un grupo
  Future<void> deleteSaving(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse("$savingsBase/$id"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode != 200) {
      // Check for permission errors
      if (response.statusCode == 403) {
        throw Exception(
          'No tienes permisos para eliminar metas. Solo Admin y Owner pueden eliminar metas.',
        );
      }
      throw Exception("Error al eliminar meta: ${response.body}");
    }
  }

  /// 🟣 Agregar movimiento/ingreso a una meta
  /// NOTE: backend path for movements is inferred. If your backend uses a different
  /// endpoint, update this method accordingly.
  Future<Map<String, dynamic>> createSavingMovement({
    required String savingId,
    required num amount,
    String type = 'deposit', // 'deposit' or 'withdraw'
    String? note,
    String? transactionId,
    String? groupId,
  }) async {
    final token = await _getToken();
    // Prepare common headers and body
    final headers = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    };
    // canonical body using backend's expected field names
    final canonicalBody = {
      "goalId": savingId,
      "amount": amount,
      "type": type,
      if (note != null) "note": note,
      if (transactionId != null) "transactionId": transactionId,
      if (groupId != null) "groupId": groupId,
    };
    final body = jsonEncode(canonicalBody);

    // Try a list of candidate endpoints/approaches until one succeeds.
    // If this saving belongs to a group, try group-scoped endpoints first.
    // We also keep a list of attempted URIs to report back in case of failure.
    final candidates = <Future<http.Response> Function()>[];
    final attemptedUris = <String>[];

    if (groupId != null && groupId.trim().isNotEmpty) {
      candidates.add(() async {
        final u = "$baseUrl/$groupId/savings/$savingId/movements";
        attemptedUris.add(u);
        // try canonical body
        return await http.post(Uri.parse(u), headers: headers, body: body);
      });
      candidates.add(() async {
        final u = "$baseUrl/$groupId/savings/$savingId/transactions";
        attemptedUris.add(u);
        return await http.post(Uri.parse(u), headers: headers, body: body);
      });
      candidates.add(() async {
        final u = "$baseUrl/$groupId/savings/$savingId/contributions";
        attemptedUris.add(u);
        return await http.post(Uri.parse(u), headers: headers, body: body);
      });
    }

    // Most likely: /api/savings/{id}/movements
    candidates.add(() async {
      final u = "$savingsBase/$savingId/movements";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    // Alternative: global movements endpoint with savingId in payload
    // global movements endpoint (send canonical 'goalId' as well)
    candidates.add(() async {
      final u = "$savingsBase/movements";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    // Other common alternatives
    candidates.add(() async {
      final u = "$savingsBase/$savingId/transactions";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });
    candidates.add(() async {
      final u = "$savingsBase/$savingId/contributions";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    // As a last attempt, try PUT to the per-saving path (some APIs use PUT for idempotent updates)
    candidates.add(() async {
      final u = "$savingsBase/$savingId/movements";
      attemptedUris.add(u + " (PUT)");
      return await http.put(Uri.parse(u), headers: headers, body: body);
    });

    // Additional diagnostic candidates:
    // - Group-scoped generic movements endpoint with savingId in body
    if (groupId != null && groupId.trim().isNotEmpty) {
      candidates.add(() async {
        final u = "$baseUrl/$groupId/movements";
        attemptedUris.add(u);
        return await http.post(Uri.parse(u), headers: headers, body: body);
      });

      // Try group-level movements root
      candidates.add(() async {
        final u = "$baseUrl/movements";
        attemptedUris.add(u);
        return await http.post(Uri.parse(u), headers: headers, body: body);
      });
    }

    // Try common global endpoints
    candidates.add(() async {
      final u = "$baseUrl/movements";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    candidates.add(() async {
      final u = "https://co-fi-web.vercel.app/api/movements";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    candidates.add(() async {
      final u = "https://co-fi-web.vercel.app/api/contributions";
      attemptedUris.add(u);
      return await http.post(Uri.parse(u), headers: headers, body: body);
    });

    // Try PATCH to per-saving movements path (some APIs use PATCH)
    candidates.add(() async {
      final u = "$savingsBase/$savingId/movements";
      attemptedUris.add(u + " (PATCH)");
      return await http.patch(Uri.parse(u), headers: headers, body: body);
    });

    http.Response? lastResponse;
    for (final attempt in candidates) {
      try {
        final resp = await attempt();
        lastResponse = resp;
        if (resp.statusCode == 200 ||
            resp.statusCode == 201 ||
            resp.statusCode == 204) {
          if (resp.body.trim().isEmpty) return {};
          try {
            return jsonDecode(resp.body);
          } catch (_) {
            return {"message": resp.body};
          }
        }

        // If we got 405 Method Not Allowed or 404 Not Found, try next candidate
        if (resp.statusCode == 405 || resp.statusCode == 404) continue;

        // For other non-success statuses, try to parse a helpful message and throw
        try {
          final parsed = jsonDecode(resp.body);
          final message = parsed is Map
              ? (parsed['error'] ??
                    parsed['message'] ??
                    parsed['detail'] ??
                    resp.body)
              : resp.body;
          throw Exception(
            'Error al crear movimiento: $message (status ${resp.statusCode})',
          );
        } catch (_) {
          final bodyText = resp.body.trim().isEmpty
              ? 'HTTP ${resp.statusCode}'
              : resp.body;
          throw Exception(
            'Error al crear movimiento: $bodyText (status ${resp.statusCode})',
          );
        }
      } catch (e) {
        // If the exception was thrown by the http client itself, record and try next
        // but if it's our parsed Exception, rethrow so UI shows helpful detail.
        if (e is Exception &&
            e.toString().contains('Error al crear movimiento:'))
          rethrow;
        // otherwise continue to next candidate
      }
    }

    // If we exhausted candidates, provide the last response status/body if available
    if (lastResponse != null) {
      final resp = lastResponse;
      final bodyText = resp.body.trim().isEmpty
          ? 'HTTP ${resp.statusCode}'
          : resp.body;
      final attemptedText = attemptedUris.isEmpty
          ? 'N/A'
          : attemptedUris.join(' | ');
      throw Exception(
        'Error al crear movimiento: $bodyText (status ${resp.statusCode}). Endpoints intentados: $attemptedText',
      );
    }

    // Unknown failure
    throw Exception('Error al crear movimiento: falla desconocida');
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
  /// Solo el Owner puede cambiar roles de otros usuarios
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
      // Check for permission errors
      if (response.statusCode == 403) {
        throw Exception(
          'No tienes permisos para cambiar roles. Solo el Owner puede cambiar roles.',
        );
      }
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
