import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Servicio unificado para manejar budgets (limpio, sin duplicación).
///
/// Incluye helpers privados para:
/// - obtener encabezados autorizados
/// - extraer items desde respuestas variadas (lista, { data: [...] }, objeto único)
class BudgetService {
  static const String baseUrl = "https://co-fi-web.vercel.app/api";

  /// Último mensaje de error (útil para la UI)
  String? lastErrorMessage;

  Future<Map<String, String>> _getAuthHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  List<Map<String, dynamic>> _extractItems(dynamic decoded) {
    final List<Map<String, dynamic>> items = [];
    if (decoded == null) return items;

    if (decoded is List) {
      for (final v in decoded) {
        if (v is Map) items.add(Map<String, dynamic>.from(v));
      }
    } else if (decoded is Map) {
      if (decoded['data'] is List) {
        for (final v in decoded['data']) {
          if (v is Map) items.add(Map<String, dynamic>.from(v));
        }
      } else {
        // Single object response
        items.add(Map<String, dynamic>.from(decoded));
      }
    }

    return items;
  }

  /// Busca y retorna el presupuesto mensual del backend. Retorna null si no existe o en error.
  Future<Map<String, dynamic>?> getMonthlyBudget() async {
    try {
      final headers = await _getAuthHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/budgets'),
        headers: headers,
      );
      if (res.statusCode != 200) return null;

      final body = res.body.trim();
      if (body.isEmpty) return null;

      final decoded = json.decode(body);
      final items = _extractItems(decoded);
      if (items.isEmpty) return null;

      // prefer monthly/frecuencia mensual
      for (final it in items) {
        final period = (it['period'] ?? it['type'] ?? it['frequency'])
            ?.toString()
            .toLowerCase();
        if (period == 'monthly' || period == 'mensual') return it;
      }

      // fallback: primero disponible
      return items.first;
    } catch (e) {
      // guardamos mensaje para UI si es necesario
      lastErrorMessage = e.toString();
      return null;
    }
  }

  /// Guarda (crea o actualiza) el presupuesto mensual.
  /// Retorna true si la operación fue exitosa.
  Future<bool> saveMonthlyBudget(double amount, {String? categoryId}) async {
    lastErrorMessage = null;

    try {
      final headers = await _getAuthHeaders();

      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      String? finalCategoryId = categoryId;
      if (finalCategoryId == null || finalCategoryId.isEmpty) {
        // intentar obtener la primera categoría disponible
        try {
          final catRes = await http.get(
            Uri.parse('$baseUrl/categories'),
            headers: headers,
          );
          if (catRes.statusCode == 200) {
            final body = catRes.body.trim();
            if (body.isNotEmpty) {
              final decoded = json.decode(body);
              final items = _extractItems(decoded);
              if (items.isNotEmpty) {
                final first = items.first;
                finalCategoryId =
                    (first['id'] ?? first['_id'] ?? first['categoryId'])
                        ?.toString();
              }
            }
          }
        } catch (_) {
          // no hacer nada: fallará más abajo si no hay categoría
        }
      }

      if (finalCategoryId == null || finalCategoryId.isEmpty) {
        lastErrorMessage =
            'No hay categorías disponibles en tu cuenta. Crea una categoría antes de establecer un presupuesto.';
        return false;
      }

      final payload = json.encode({
        'budget': amount,
        'amount': amount,
        'value': amount,
        'period': 'monthly',
        'month': monthStr,
        'categoryId': finalCategoryId,
      });

      // si existe, actualizamos (PUT), si no, creamos (POST)
      final existing = await getMonthlyBudget();
      if (existing != null) {
        final id = (existing['id'] ?? existing['_id'] ?? existing['budgetId'])
            ?.toString();
        if (id != null && id.isNotEmpty) {
          final res = await http.put(
            Uri.parse('$baseUrl/budgets/$id'),
            headers: headers,
            body: payload,
          );
          if (!(res.statusCode >= 200 && res.statusCode < 300)) {
            lastErrorMessage = 'PUT ${res.statusCode}: ${res.body}';
            print('BudgetService PUT failed: $lastErrorMessage');
          }
          return res.statusCode >= 200 && res.statusCode < 300;
        }
      }

      final res = await http.post(
        Uri.parse('$baseUrl/budgets'),
        headers: headers,
        body: payload,
      );
      if (!(res.statusCode >= 200 && res.statusCode < 300)) {
        lastErrorMessage = 'POST ${res.statusCode}: ${res.body}';
        print('BudgetService POST failed: $lastErrorMessage');
      }
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      lastErrorMessage = e.toString();
      print('BudgetService exception: $lastErrorMessage');
      return false;
    }
  }

  /// Elimina el presupuesto mensual del backend.
  /// Retorna true si la operación fue exitosa.
  Future<bool> deleteMonthlyBudget() async {
    lastErrorMessage = null;

    try {
      final headers = await _getAuthHeaders();

      // Primero obtener el presupuesto mensual para conseguir su ID
      final existing = await getMonthlyBudget();
      if (existing == null) {
        // No existe presupuesto mensual, considerar como éxito
        return true;
      }

      final id = (existing['id'] ?? existing['_id'] ?? existing['budgetId'])
          ?.toString();

      if (id == null || id.isEmpty) {
        lastErrorMessage = 'No se pudo obtener el ID del presupuesto';
        return false;
      }

      // Eliminar el presupuesto usando DELETE
      final res = await http.delete(
        Uri.parse('$baseUrl/budgets/$id'),
        headers: headers,
      );

      if (!(res.statusCode >= 200 && res.statusCode < 300)) {
        lastErrorMessage = 'DELETE ${res.statusCode}: ${res.body}';
        print('BudgetService DELETE failed: $lastErrorMessage');
        return false;
      }

      return true;
    } catch (e) {
      lastErrorMessage = e.toString();
      print('BudgetService delete exception: $lastErrorMessage');
      return false;
    }
  }
}
