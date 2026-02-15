import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class AiService {
  static const String _backendUrl =
      "https://co-fi-web.vercel.app/api/ai/recommendations";

  /// Carga el historial de recomendaciones del usuario
  static Future<List<Map<String, dynamic>>> loadRecommendations() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        print('⚠️ No se pudo cargar recomendaciones: usuario no autenticado');
        return [];
      }

      final response = await http.get(
        Uri.parse(_backendUrl),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is List) {
          print('✅ Cargadas ${data.length} recomendaciones del historial');
          return data.map((item) => item as Map<String, dynamic>).toList();
        } else if (data is Map && data.containsKey('recommendations')) {
          final recs = data['recommendations'] as List;
          print('✅ Cargadas ${recs.length} recomendaciones del historial');
          return recs.map((item) => item as Map<String, dynamic>).toList();
        }

        return [];
      } else {
        print('❌ Error cargando recomendaciones: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('💥 Error al cargar recomendaciones: $e');
      return [];
    }
  }

  /// Elimina todas las recomendaciones del usuario
  static Future<bool> clearRecommendations() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        print('⚠️ No se pudo limpiar recomendaciones: usuario no autenticado');
        return false;
      }

      final response = await http.delete(
        Uri.parse(_backendUrl),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('✅ Recomendaciones eliminadas correctamente');
        return true;
      } else {
        print('❌ Error eliminando recomendaciones: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('💥 Error al eliminar recomendaciones: $e');
      return false;
    }
  }

  /// 🔥 MODIFICADO: Solo hace UNA llamada al backend con respuestas cortas
  static Future<String> getAIResponse(
    String message, {
    bool concise = true, // 🆕 Por defecto siempre conciso (8 líneas máx)
    String? conversationId,
  }) async {
    try {
      var trimmed = message.trim();
      if (trimmed.isEmpty) {
        return "Por favor escribe algo para que pueda ayudarte.";
      }

      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        return "⚠️ Debes iniciar sesión para usar esta función.";
      }

      print('📤 Enviando mensaje a IA (conversationId: $conversationId)');
      print(
        '📝 Mensaje: ${trimmed.substring(0, trimmed.length > 50 ? 50 : trimmed.length)}...',
      );

      // 🆕 Instrucción explícita para respuestas cortas
      final conciseInstruction =
          "\n\nResponde de forma concisa y directa en máximo dos párrafos breves."
          "Usa soles (S/) para montos de dinero. Evita el uso de negritas (**) y listas extensas.";

      // 🆕 Preparar el payload completo en UNA SOLA LLAMADA
      final requestBody = jsonEncode({
        "recType": "chat",
        "recSummary": trimmed, // ✅ Solo la pregunta original
        "recFull": "", // Se llenará con la respuesta del backend
        "score": 5,
        "conversationId": conversationId,
        "context": {
          "userQuestion":
              trimmed + conciseInstruction, // ✅ Pregunta + instrucción
          "requestedConcise": true,
          "maxLines": 4, // 🆕 Límite explícito de 4 líneas
          "currency": "PEN", // 🇵🇪 Moneda peruana
          "currencySymbol": "S/", // 🇵🇪 Símbolo de Soles
        },
      });

      // 🚀 UNA SOLA LLAMADA HTTP
      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: requestBody,
      );

      print('📥 Respuesta recibida: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String aiResponse =
            data['recFull']?.toString() ??
            data['response']?.toString() ??
            "Lo siento, no pude generar una respuesta.";

        // 🆕 Limpiar formato antes de devolver
        aiResponse = _cleanFormatting(aiResponse);

        // 🇵🇪 Reemplazar símbolos de dólar por soles peruanos
        aiResponse = _replaceCurrencySymbols(aiResponse);

        print('✅ Respuesta procesada (${aiResponse.length} caracteres)');
        return aiResponse;
      }

      // Manejar errores específicos
      if (response.statusCode == 400) {
        print('❌ Error 400: ${response.body}');
        return "⚠️ Error en la solicitud. Por favor intenta de nuevo.";
      }

      if (response.statusCode == 403) {
        print('❌ Error 403: Límite alcanzado');
        return "⚠️ Has alcanzado el límite de consultas diarias. Intenta mañana.";
      }

      print("❌ Error IA: ${response.statusCode} - ${response.body}");
      throw Exception("Error ${response.statusCode}: ${response.body}");
    } catch (e) {
      print("💥 Error al consultar la IA: $e");
      return "❌ Ocurrió un error al conectar con el servicio de IA. "
          "Por favor verifica tu conexión e intenta de nuevo.";
    }
  }

  // 🆕 Helper para limpiar formato markdown
  static String _cleanFormatting(String text) {
    // Remover ** bold markdown
    text = text.replaceAllMapped(RegExp(r"\*\*(.*?)\*\*"), (m) => m[1] ?? '');
    // Remover * italic markdown
    text = text.replaceAllMapped(RegExp(r"\*(.*?)\*"), (m) => m[1] ?? '');
    // Normalizar bullets (usar multiLine en lugar de (?m))
    text = text.replaceAllMapped(
      RegExp(r'^[ \t]*[\*\•][ \t]*', multiLine: true),
      (m) => '- ',
    );
    return text.trim();
  }

  // 🇵🇪 Helper para reemplazar símbolos de dólar y euro por soles peruanos
  static String _replaceCurrencySymbols(String text) {
    // Reemplazar €X por S/ X (EURO)
    text = text.replaceAllMapped(
      RegExp(r'€\s*(\d+(?:[.,]\d+)?)'),
      (m) => 'S/ ${m[1]}',
    );
    // Reemplazar $X por S/ X (DÓLAR)
    text = text.replaceAllMapped(
      RegExp(r'\$\s*(\d+(?:[.,]\d+)?)'),
      (m) => 'S/ ${m[1]}',
    );
    // Reemplazar "euros" o "EUR" por "soles" o "PEN"
    text = text.replaceAll(
      RegExp(r'\beuros?\b', caseSensitive: false),
      'soles',
    );
    text = text.replaceAll(RegExp(r'\bEUR\b'), 'PEN');
    // Reemplazar "dólares" o "USD" por "soles" o "PEN"
    text = text.replaceAll(
      RegExp(r'\bdólares?\b', caseSensitive: false),
      'soles',
    );
    text = text.replaceAll(RegExp(r'\bUSD\b'), 'PEN');
    return text;
  }
}
