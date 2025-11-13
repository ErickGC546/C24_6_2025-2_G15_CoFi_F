import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class AiService {
  static const String _backendUrl =
      "https://co-fi-web.vercel.app/api/ai/request";

  static Future<String> getAIResponse(
    String message, {
    bool concise = false,
  }) async {
    try {
      var trimmed = message.trim();
      if (trimmed.isEmpty) {
        print('⚠️ No se enviará petición a la IA: mensaje vacío');
        return '🤔 Escribe un mensaje antes de enviar.';
      }

      // Si el llamador pidió respuesta concisa, agregamos instrucción.
      final conciseInstruction = concise
          ? '\n\nPor favor responde en máximo 8 líneas.'
          : '';
      // No añadimos la instrucción aún si haremos fragmentado; la añadiremos
      // al último fragmento para intentar que la respuesta final sea concisa.

      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        print('⚠️ Token de Firebase nulo. Usuario no autenticado.');
        return "⚠️ No se pudo autenticar con Firebase.";
      }

      // El backend de Next.js espera 'userMessage' (según handler). Enviamos
      // userMessage y requestType por defecto.
      // Si el mensaje es muy largo, lo enviaremos en fragmentos (chunking).
      const int _maxMessageSize = 2000; // umbral para considerar fragmentado
      const int _chunkSize = 1500; // tamaño de cada fragmento en caracteres

      Future<http.Response> _postBody(String b) => http.post(
        Uri.parse(_backendUrl),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: b,
      );

      List<String> _chunks(String s) {
        final parts = <String>[];
        for (var i = 0; i < s.length; i += _chunkSize) {
          parts.add(s.substring(i, min(i + _chunkSize, s.length)));
        }
        return parts;
      }

      // Preparar fragments: si el mensaje es corto, se procesa como único fragmento.
      final List<String> parts = trimmed.length > _maxMessageSize
          ? _chunks(trimmed)
          : [trimmed];
      // Debug prints para diagnóstico (no imprimir token completo por seguridad)
      try {
        final shortToken = token.length > 10
            ? '${token.substring(0, 10)}...'
            : token;
        print('📤 Enviando petición IA a $_backendUrl');
        print('🔐 Authorization: Bearer $shortToken');
        print('📦 message length: ${trimmed.length}; parts: ${parts.length}');
      } catch (_) {}

      // Si tenemos múltiples partes, enviamos cada parte secuencialmente y
      // acumulamos las respuestas (mejor que fallar por payload demasiado grande).
      String accumulatedResponse = '';
      int successfulResponses = 0;

      // Helper para extraer texto de respuesta en distintas formas (map o string)
      String _extractResponseText(dynamic parsed) {
        try {
          if (parsed == null) return '';
          if (parsed is String) return parsed.trim();

          if (parsed is Map && parsed.containsKey('response')) {
            final r = parsed['response'];
            if (r is String) return r.trim();
            if (r is Map) {
              final raw = r['raw'] ?? r['result'] ?? r;
              if (raw is Map) {
                final choices =
                    raw['choices'] ?? raw['outputs'] ?? raw['result'];
                if (choices is List && choices.isNotEmpty) {
                  final first = choices[0];
                  if (first is Map) {
                    if (first.containsKey('message')) {
                      final msg = first['message'];
                      if (msg is Map && msg.containsKey('content')) {
                        return (msg['content'] ?? '').toString().trim();
                      }
                    }
                    if (first.containsKey('content')) {
                      return (first['content'] ?? '').toString().trim();
                    }
                    if (first.containsKey('text')) {
                      return (first['text'] ?? '').toString().trim();
                    }
                  }
                }
                if (raw.containsKey('message')) {
                  final msg = raw['message'];
                  if (msg is Map && msg.containsKey('content')) {
                    return (msg['content'] ?? '').toString().trim();
                  }
                }
              }
            }
          }

          if (parsed is Map && parsed.containsKey('choices')) {
            final choices = parsed['choices'];
            if (choices is List && choices.isNotEmpty) {
              final first = choices[0];
              if (first is Map) {
                if (first.containsKey('message')) {
                  final msg = first['message'];
                  if (msg is Map && msg.containsKey('content')) {
                    return (msg['content'] ?? '').toString().trim();
                  }
                }
                if (first.containsKey('text')) {
                  return (first['text'] ?? '').toString().trim();
                }
              }
            }
          }

          if (parsed is Map) {
            if (parsed.containsKey('text'))
              return (parsed['text'] ?? '').toString().trim();
            if (parsed.containsKey('message')) {
              final m = parsed['message'];
              if (m is String) return m.trim();
              if (m is Map && m.containsKey('content'))
                return (m['content'] ?? '').toString().trim();
            }
            if (parsed.containsKey('output'))
              return (parsed['output'] ?? '').toString().trim();
          }

          return '';
        } catch (_) {
          return '';
        }
      }

      for (var idx = 0; idx < parts.length; idx++) {
        final part = parts[idx];
        // Añadir instructivo conciso sólo al último fragmento (si aplica)
        final toSend = idx == parts.length - 1
            ? '$part$conciseInstruction'
            : part;

        final body = jsonEncode({
          "userMessage": toSend,
          "requestType": "advice",
          if (parts.length > 1) 'chunkIndex': idx,
          if (parts.length > 1) 'totalChunks': parts.length,
        });

        http.Response response;
        try {
          response = await _postBody(body);
        } catch (e) {
          print('💥 Error enviando chunk $idx: $e');
          continue;
        }

        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body);
            final respText = _extractResponseText(data);
            if (respText.isNotEmpty) {
              if (accumulatedResponse.isNotEmpty) {
                accumulatedResponse =
                    '$accumulatedResponse\n\n---\n\n$respText';
              } else {
                accumulatedResponse = respText;
              }
              successfulResponses++;
            }
          } catch (e) {
            print('⚠️ Error parseando JSON chunk $idx: $e');
          }
        } else {
          // Si el backend responde 403 indicando límite diario, no exponemos
          // el texto exacto (por ejemplo "Has alcanzado el límite diario de 5 consultas...")
          // y devolvemos un mensaje neutro para la UI.
          if (response.statusCode == 403) {
            try {
              final parsed = jsonDecode(response.body);
              final err = (parsed['error'] as String?)?.toLowerCase() ?? '';
              if (err.contains('límite') || err.contains('limite')) {
                print('❌ Chunk $idx falló: límite de uso backend (suprimido).');
                return '🤖 El servicio de IA no está disponible temporalmente. Intenta más tarde.';
              }
            } catch (_) {}
          }

          print(
            '❌ Chunk $idx falló (${response.statusCode}): ${response.body}',
          );
        }
      }

      // Si procesamos por partes y hubo al menos una respuesta válida, la usamos.
      http.Response? firstResponse;
      if (parts.length > 1 && successfulResponses > 0) {
        // Continuar con la limpieza y truncado sobre accumulatedResponse.
        try {
          String respText = accumulatedResponse;

          String _cleanFormatting(String s) {
            try {
              s = s.replaceAllMapped(
                RegExp(r"\*\*(.*?)\*\*"),
                (m) => m[1] ?? '',
              );
              s = s.replaceAllMapped(
                RegExp(r'(?m)^[ \t]*[\*\•][ \t]*'),
                (m) => '- ',
              );
              s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
              s = s
                  .split(RegExp(r"\r?\n"))
                  .map((l) => l.trimRight())
                  .join('\n');
              return s.trim();
            } catch (_) {
              return s;
            }
          }

          respText = _cleanFormatting(respText);

          String _truncateResponse(
            String s, {
            int maxLines = 8,
            int maxChars = 2000,
          }) {
            final lines = s.split(RegExp(r"\r?\n"));
            final taken = lines.take(maxLines).toList();
            var result = taken.join('\n');
            if (result.length > maxChars) {
              result = result.substring(0, maxChars) + '...';
            }
            return result;
          }

          return _truncateResponse(respText);
        } catch (e) {
          print('⚠️ Error limpiando respuesta acumulada: $e');
          return '🤖 Hubo un problema al procesar la respuesta de la IA.';
        }
      }

      // Si no era multipart o no hubo respuestas exitosas por partes, continuamos
      // con el flujo de una única petición normal (se intentará abajo).
      if (parts.length == 1) {
        final singleBody = jsonEncode({
          "userMessage": '${parts.first}$conciseInstruction',
          "requestType": "advice",
        });
        try {
          firstResponse = await _postBody(singleBody);
        } catch (e) {
          print('💥 Error en petición única: $e');
          throw e;
        }
      } else {
        // No se obtuvieron respuestas válidas de los chunks y no hay alternativa
        print('❌ No se obtuvieron respuestas válidas de los chunks');
        throw Exception('No se obtuvo respuesta de los fragments');
      }

      final response = firstResponse;

      if (response.statusCode == 200) {
        // Imprimir body completo del backend para depuración
        try {
          print('✅ Respuesta backend (status 200): ${response.body}');
          final data = jsonDecode(response.body);
          print('🔎 Parsed response JSON: $data');
          // Helper to extract text robustly from different backend shapes
          String _extractResponseText(dynamic parsed) {
            try {
              if (parsed == null) return '';

              // If it's already a string, return trimmed
              if (parsed is String) return parsed.trim();

              // If top-level has 'response' key either as String or Map
              if (parsed is Map && parsed.containsKey('response')) {
                final r = parsed['response'];
                if (r is String) return r.trim();
                // If 'response' is a map containing 'raw' with choice message
                if (r is Map) {
                  // Common shape: response.raw.choices[0].message.content
                  final raw = r['raw'] ?? r['result'] ?? r;
                  if (raw is Map) {
                    final choices =
                        raw['choices'] ?? raw['outputs'] ?? raw['result'];
                    if (choices is List && choices.isNotEmpty) {
                      final first = choices[0];
                      if (first is Map) {
                        // message -> content
                        if (first.containsKey('message')) {
                          final msg = first['message'];
                          if (msg is Map && msg.containsKey('content')) {
                            return (msg['content'] ?? '').toString().trim();
                          }
                        }
                        // content directly
                        if (first.containsKey('content')) {
                          return (first['content'] ?? '').toString().trim();
                        }
                        // text field
                        if (first.containsKey('text')) {
                          return (first['text'] ?? '').toString().trim();
                        }
                      }
                    }

                    // Fallback: check raw.message.content
                    if (raw.containsKey('message')) {
                      final msg = raw['message'];
                      if (msg is Map && msg.containsKey('content')) {
                        return (msg['content'] ?? '').toString().trim();
                      }
                    }
                  }
                }
              }

              // Some responses may include choices at top-level
              if (parsed is Map && parsed.containsKey('choices')) {
                final choices = parsed['choices'];
                if (choices is List && choices.isNotEmpty) {
                  final first = choices[0];
                  if (first is Map) {
                    if (first.containsKey('message')) {
                      final msg = first['message'];
                      if (msg is Map && msg.containsKey('content')) {
                        return (msg['content'] ?? '').toString().trim();
                      }
                    }
                    if (first.containsKey('text')) {
                      return (first['text'] ?? '').toString().trim();
                    }
                  }
                }
              }

              // Generic fallbacks
              if (parsed is Map) {
                if (parsed.containsKey('text'))
                  return (parsed['text'] ?? '').toString().trim();
                if (parsed.containsKey('message')) {
                  final m = parsed['message'];
                  if (m is String) return m.trim();
                  if (m is Map && m.containsKey('content'))
                    return (m['content'] ?? '').toString().trim();
                }
                if (parsed.containsKey('output'))
                  return (parsed['output'] ?? '').toString().trim();
              }

              return '';
            } catch (_) {
              return '';
            }
          }

          var respText = _extractResponseText(data);

          // Si el backend devuelve el placeholder que significa "sin respuesta" o está vacío,
          // hacemos un reintento con una instrucción explícita de respuesta corta.
          if (respText.isEmpty ||
              respText == 'No se recibió respuesta de la IA.' ||
              respText.toLowerCase().contains('no se reci')) {
            print(
              '⚠️ Backend no devolvió respuesta útil, intentando reintento conciso',
            );
            try {
              final retryBody = jsonEncode({
                "userMessage": '$trimmed$conciseInstruction',
                "requestType": "advice",
              });
              final r2 = await http.post(
                Uri.parse(_backendUrl),
                headers: {
                  "Authorization": "Bearer $token",
                  "Content-Type": "application/json",
                },
                body: retryBody,
              );
              if (r2.statusCode == 200) {
                final data2 = jsonDecode(r2.body);
                respText = _extractResponseText(data2);
                print('🔁 Reintento backend (200): $respText');
              } else {
                print('❌ Reintento fallido (${r2.statusCode}): ${r2.body}');
              }
            } catch (e) {
              print('💥 Error en reintento conciso: $e');
            }
          }

          if (respText.isEmpty) {
            return '🤖 Lo siento, no obtuve respuesta de la IA. Intenta reformular la pregunta o comprueba la conexión.';
          }

          final placeholder = 'No se recibió respuesta de la IA.';
          if (respText == placeholder) {
            return '🤖 No pude obtener una respuesta de la IA. Prueba de nuevo o revisa el servicio backend.';
          }

          // Limpieza de formato: quitar '**' (bold markdown) y convertir líneas que
          // comienzan con '*' o '•' en guiones '-' para que se vea mejor en la UI.
          String _cleanFormatting(String s) {
            try {
              // Remover bold Markdown **texto** -> texto
              s = s.replaceAllMapped(
                RegExp(r"\*\*(.*?)\*\*"),
                (m) => m[1] ?? '',
              );

              // Convertir bullets '*' o '•' al inicio de línea en '- '
              s = s.replaceAllMapped(
                RegExp(r'(?m)^[ \t]*[\*\•][ \t]*'),
                (m) => '- ',
              );

              // Normalizar espacios múltiples
              s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

              // Quitar espacios al final de cada línea
              s = s
                  .split(RegExp(r"\r?\n"))
                  .map((l) => l.trimRight())
                  .join('\n');

              return s.trim();
            } catch (_) {
              return s;
            }
          }

          // Aplicar limpieza antes de truncar
          respText = _cleanFormatting(respText);

          // Truncar respuestas demasiado largas a un tamaño razonable (máx 5 líneas o 600 chars)
          String _truncateResponse(
            String s, {
            int maxLines = 5,
            int maxChars = 600,
          }) {
            final lines = s.split(RegExp(r"\r?\n"));
            final taken = lines.take(maxLines).toList();
            var result = taken.join('\n');
            if (result.length > maxChars) {
              result = result.substring(0, maxChars) + '...';
            }
            return result;
          }

          return _truncateResponse(respText);
        } catch (e) {
          print('⚠️ Error al parsear JSON del backend: $e');
          // Si no se puede parsear, devolvemos mensaje por defecto
          return "🤔 No recibí respuesta de la IA, intenta nuevamente.";
        }
      }

      // Si el backend responde con 400 indicando que falta el mensaje,
      // intentamos algunos payloads alternativos comunes.
      if (response.statusCode == 400) {
        try {
          final respBody = response.body;
          final parsed = jsonDecode(respBody);
          if (parsed is Map &&
              parsed['error'] == 'Falta el mensaje del usuario') {
            print(
              '⚠️ Backend indica falta de campo message; reintentando con payload alternativos',
            );

            final altPayloads = [
              // incluir formato legacy 'message' por compatibilidad
              jsonEncode({'message': trimmed}),
              jsonEncode({'prompt': trimmed}),
              jsonEncode({'input': trimmed}),
              jsonEncode({
                'messages': [
                  {'role': 'user', 'content': trimmed},
                ],
              }),
            ];

            for (final p in altPayloads) {
              try {
                print('📤 Reintentando con payload: $p');
                final r2 = await http.post(
                  Uri.parse(_backendUrl),
                  headers: {
                    "Authorization": "Bearer $token",
                    "Content-Type": "application/json",
                  },
                  body: p,
                );
                if (r2.statusCode == 200) {
                  final data2 = jsonDecode(r2.body);
                  final extracted = _extractResponseText(data2);
                  return extracted.isNotEmpty
                      ? extracted
                      : '🤔 No recibí respuesta de la IA';
                } else {
                  print('❌ Reintento fallido (${r2.statusCode}): ${r2.body}');
                }
              } catch (e) {
                print('💥 Error en reintento con payload $p: $e');
              }
            }
          }
        } catch (e) {
          print('⚠️ No se pudo parsear body 400: ${response.body}');
        }
      }

      // Si el backend responde con 403 indicando límite diario, suprimimos
      // el detalle y devolvemos un mensaje neutro en lugar de propagar
      // el texto exacto que menciona "5 consultas".
      if (response.statusCode == 403) {
        try {
          final parsed = jsonDecode(response.body);
          final err = (parsed['error'] as String?)?.toLowerCase() ?? '';
          if (err.contains('límite') || err.contains('limite')) {
            print('❌ Backend limit detected (suppressed)');
            return '🤖 El servicio de IA no está disponible temporalmente. Intenta más tarde.';
          }
        } catch (_) {}
      }

      print("❌ Error IA: ${response.body}");
      throw Exception("Error ${response.statusCode}: ${response.body}");
    } catch (e) {
      print("💥 Error al consultar la IA: $e");
      return "❌ Ocurrió un error";
    }
  }
}
