import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'home_service.dart';

// utilities
String _shortMonthLabel(int monthIndex) {
  const months = [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];
  return months[(monthIndex - 1) % 12];
}

class ReportService {
  // 🔹 Cambia esta URL por tu dominio del backend
  final String baseUrl = "https://co-fi-web.vercel.app/api/reports";

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  /// 🟢 Obtener resumen general de reportes (saldo, ingresos, egresos, ahorro)
  Future<Map<String, dynamic>> getGeneralReport() async {
    final token = await _getToken();
    final url = Uri.parse(baseUrl);

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      // Fallback: calcular totales a partir de transacciones locales
      try {
        final home = await HomeService.getHomeData();
        final transactions = (home['transactions'] as List<dynamic>?) ?? [];
        double income = 0.0;
        double expenses = 0.0;
        for (final t in transactions) {
          try {
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            final type = (t['type'] ?? '')?.toString().toLowerCase();
            if (type == 'income' || amount > 0) income += amount.abs();
            if (type == 'expense' || amount < 0) expenses += amount.abs();
          } catch (_) {}
        }
        final balance = income - expenses;
        return {'income': income, 'expenses': expenses, 'balance': balance};
      } catch (e) {
        throw Exception(
          'Error al obtener reporte general: ${response.statusCode} - ${response.body}',
        );
      }
    }
  }

  /// 🟣 Obtener reporte por categoría
  Future<List<Map<String, dynamic>>> getCategoryReport() async {
    final token = await _getToken();
    final url = Uri.parse("$baseUrl/category");

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      // Fallback: intentar construir reporte por categoría desde las
      // transacciones locales (obtenidas a través de HomeService). Esto
      // evita que la UI muestre un error cuando el endpoint backend falla.
      try {
        final home = await HomeService.getHomeData();
        final transactions = (home['transactions'] as List<dynamic>?) ?? [];
        final categories = (home['categories'] as List<dynamic>?) ?? [];

        // map categoryId -> name
        final Map<String, String> catNames = {};
        for (final c in categories) {
          try {
            final id = (c['id'] ?? c['_id'] ?? c['categoryId'])?.toString();
            final name = (c['name'] ?? c['title'])?.toString() ?? 'Sin nombre';
            if (id != null) catNames[id] = name;
          } catch (_) {}
        }

        // sum expenses per category id or name
        final Map<String, double> sums = {};
        double total = 0;
        for (final t in transactions) {
          try {
            final type = (t['type'] ?? '')?.toString().toLowerCase();
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            final isExpense = type == 'expense' || amount < 0;
            if (!isExpense) continue;
            final absAmount = amount.abs();
            // Prefer categoryId if available, otherwise try category name field
            final catIdRaw =
                t['categoryId'] ??
                t['category'] ??
                t['categoryName'] ??
                t['categoria'];
            final catId = catIdRaw?.toString() ?? '';
            sums[catId] = (sums[catId] ?? 0) + absAmount;
            total += absAmount;
          } catch (_) {}
        }
        // If total==0 we still want to return available categories (with 0)
        final List<Map<String, dynamic>> out = [];
        // First, ensure we include known categories from catNames even if sums has no entry
        final allKeys = <String>{}
          ..addAll(sums.keys)
          ..addAll(catNames.keys);
        for (final catId in allKeys) {
          final value = sums[catId] ?? 0.0;
          final pct = (total > 0) ? (value / total) * 100 : 0.0;
          out.add({
            'name': catNames[catId] ?? (catId.isNotEmpty ? catId : 'Otros'),
            'amount': value,
            'percentage': double.parse(pct.toStringAsFixed(1)),
          });
        }
        // If still empty (no categories, no transactions), return empty
        return out;
      } catch (e) {
        // Como último recurso, devolver lista vacía para que la UI muestre
        // el placeholder en lugar de fallar con excepción.
        return [];
      }
    }
  }

  /// 🟠 Obtener evolución mensual (ingresos/gastos agrupados por mes)
  Future<List<Map<String, dynamic>>> getMonthlyReport() async {
    final token = await _getToken();
    final url = Uri.parse("$baseUrl/monthly");

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      // Fallback: computar a partir de transacciones locales
      try {
        final home = await HomeService.getHomeData();
        final transactions = (home['transactions'] as List<dynamic>?) ?? [];

        // Agrupar por mes (últimos 12 meses)
        final now = DateTime.now();
        final Map<String, double> sums = {};
        for (int i = 0; i < 12; i++) {
          final m = DateTime(now.year, now.month - (11 - i));
          sums['${m.year}-${m.month}'] = 0.0;
        }

        for (final t in transactions) {
          try {
            final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            DateTime dt;
            if (rawDate is DateTime)
              dt = rawDate;
            else if (rawDate is int)
              dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else
              dt =
                  DateTime.tryParse(rawDate?.toString() ?? '') ??
                  DateTime.now();

            final key = '${dt.year}-${dt.month}';
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            final isExpense =
                (t['type'] ?? '')?.toString().toLowerCase() == 'expense' ||
                amount < 0;
            if (!isExpense) continue;
            sums[key] = (sums[key] ?? 0) + amount.abs();
          } catch (_) {}
        }

        final out = <Map<String, dynamic>>[];
        sums.forEach((k, v) {
          final parts = k.split('-');
          final y = int.tryParse(parts[0]) ?? now.year;
          final m = int.tryParse(parts[1]) ?? now.month;
          out.add({'month': _shortMonthLabel(m), 'year': y, 'expenses': v});
        });
        return out;
      } catch (_) {
        return [];
      }
    }
  }

  /// 🟡 Obtener evolución semanal (ingresos/gastos agrupados por semana)
  /// Nota: asume que el backend expone `/weekly`. Si no existe, el consumidor
  /// debe manejar la excepción y caer en un fallback.
  Future<List<Map<String, dynamic>>> getWeeklyReport() async {
    final token = await _getToken();
    final url = Uri.parse("$baseUrl/weekly");

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      // Fallback: construir últimos 7 días a partir de transacciones
      try {
        final home = await HomeService.getHomeData();
        final transactions = (home['transactions'] as List<dynamic>?) ?? [];
        final now = DateTime.now();
        final Map<String, double> sums = {};
        for (int i = 6; i >= 0; i--) {
          final d = now.subtract(Duration(days: i));
          final label = '${d.day}/${d.month}';
          sums[label] = 0.0;
        }

        for (final t in transactions) {
          try {
            final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            DateTime dt;
            if (rawDate is DateTime)
              dt = rawDate;
            else if (rawDate is int)
              dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else
              dt =
                  DateTime.tryParse(rawDate?.toString() ?? '') ??
                  DateTime.now();

            final label = '${dt.day}/${dt.month}';
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            final isExpense =
                (t['type'] ?? '')?.toString().toLowerCase() == 'expense' ||
                amount < 0;
            if (!isExpense) continue;
            if (sums.containsKey(label))
              sums[label] = (sums[label] ?? 0) + amount.abs();
          } catch (_) {}
        }

        final out = <Map<String, dynamic>>[];
        sums.forEach((k, v) => out.add({'label': k, 'expenses': v}));
        return out;
      } catch (_) {
        return [];
      }
    }
  }

  /// 🔵 Obtener evolución anual (ingresos/gastos agrupados por año)
  /// Nota: asume que el backend expone `/yearly`.
  Future<List<Map<String, dynamic>>> getYearlyReport() async {
    final token = await _getToken();
    final url = Uri.parse("$baseUrl/yearly");

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      // Fallback: sumar por año (últimos 5 años)
      try {
        final home = await HomeService.getHomeData();
        final transactions = (home['transactions'] as List<dynamic>?) ?? [];
        final now = DateTime.now();
        final Map<int, double> sums = {};
        for (int i = 4; i >= 0; i--) {
          sums[now.year - i] = 0.0;
        }

        for (final t in transactions) {
          try {
            final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            DateTime dt;
            if (rawDate is DateTime)
              dt = rawDate;
            else if (rawDate is int)
              dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else
              dt =
                  DateTime.tryParse(rawDate?.toString() ?? '') ??
                  DateTime.now();

            final year = dt.year;
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            final isExpense =
                (t['type'] ?? '')?.toString().toLowerCase() == 'expense' ||
                amount < 0;
            if (!isExpense) continue;
            if (sums.containsKey(year))
              sums[year] = (sums[year] ?? 0) + amount.abs();
          } catch (_) {}
        }

        final out = <Map<String, dynamic>>[];
        sums.forEach((k, v) => out.add({'year': k, 'expenses': v}));
        return out;
      } catch (_) {
        return [];
      }
    }
  }
}
