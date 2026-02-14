import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

/// Servicio para manejar transacciones por voz
class VoiceService {
  static const String _backendUrl =
      "https://co-fi-web.vercel.app/api/voice/transaction";

  /// Envía el archivo de audio al backend para procesar la transacción
  /// Retorna un Map con el resultado del procesamiento
  static Future<Map<String, dynamic>> sendVoiceTransaction(
    String audioPath, {
    bool parseOnly = false,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        throw Exception('No se pudo autenticar. Por favor inicia sesión.');
      }

      // Verificar que el archivo existe
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw Exception('El archivo de audio no existe');
      }

      // Validar tamaño del archivo
      final fileSize = await audioFile.length();
      print('📁 Tamaño del archivo: $fileSize bytes');

      if (fileSize == 0) {
        throw Exception('El archivo de audio está vacío');
      }

      if (fileSize < 1000) {
        throw Exception(
          'La grabación es muy corta. Habla más tiempo (mínimo 2-3 segundos)',
        );
      }

      if (fileSize > 4 * 1024 * 1024) {
        // 4MB
        throw Exception('El archivo es muy grande. Graba menos tiempo');
      }

      // Crear multipart request
      final url = parseOnly ? '$_backendUrl?parseOnly=true' : _backendUrl;
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Agregar headers
      request.headers['Authorization'] = 'Bearer $token';

      // Agregar archivo de audio
      final audioBytes = await audioFile.readAsBytes();

      // Determinar el tipo MIME compatible con el backend de voz
      final filename = p.basename(audioPath);
      final extension = p.extension(filename).toLowerCase();
      MediaType mediaType;

      switch (extension) {
        case '.mp3':
          mediaType = MediaType('audio', 'mp3');
          break;
        case '.m4a':
          mediaType = MediaType('audio', 'm4a');
          break;
        case '.aac':
          mediaType = MediaType('audio', 'aac');
          break;
        case '.flac':
          mediaType = MediaType('audio', 'flac');
          break;
        case '.ogg':
          mediaType = MediaType('audio', 'ogg');
          break;
        case '.aiff':
          mediaType = MediaType('audio', 'aiff');
          break;
        case '.wav':
        default:
          mediaType = MediaType('audio', 'wav');
          break;
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'audio',
        audioBytes,
        filename: filename,
        contentType: mediaType,
      );
      request.files.add(multipartFile);

      print('🎤 Enviando audio al backend...');
      print(
        '📎 Archivo: $filename, tipo: ${mediaType.type}/${mediaType.subtype}, tamaño: ${audioBytes.length} bytes',
      );

      // Enviar request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 Respuesta del servidor: ${response.statusCode}');
      print(
        '📄 Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Transacción creada exitosamente');
        print('💾 Transcripción: ${data['transcription']}');
        if (data['parsed'] != null) {
          print('💰 Monto: ${data['parsed']['amount']}');
          print('📝 Descripción: ${data['parsed']['description']}');
          print(
            '🏷️ Categoría: ${data['parsed']['categoryName'] ?? 'Sin categoría'}',
          );
        }
        return {'success': true, 'data': data};
      } else if (response.statusCode == 401) {
        throw Exception('No autorizado. Por favor inicia sesión nuevamente.');
      } else if (response.statusCode == 402) {
        final error = json.decode(response.body);
        throw Exception(
          error['error'] ??
              'No tienes créditos de IA suficientes para procesar audio',
        );
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        final errorMsg = error['error'] ?? 'No se pudo procesar el audio';
        print('⚠️ Error 400: $errorMsg');

        // Mensajes mejorados según el backend
        if (errorMsg.contains('No se detectó voz clara')) {
          throw Exception(
            'No se detectó voz clara en el audio.\n\n'
            'Consejos:\n'
            '✓ Habla cerca del micrófono (5-10 cm)\n'
            '✓ Habla despacio y con claridad\n'
            '✓ Evita ruido de fondo\n'
            '✓ Mantén presionado el botón mientras hablas\n'
            '✓ Graba mínimo 2-3 segundos\n'
            '✓ Verifica los permisos de micrófono',
          );
        }
        throw Exception(errorMsg);
      } else if (response.statusCode == 500) {
        try {
          final error = json.decode(response.body);
          final errorMsg = error['error'] ?? 'Error del servidor';
          final details = error['details'] ?? '';
          print('❌ Error 500: $errorMsg');
          print('🔍 Detalles: $details');
          throw Exception(
            'Error al transcribir el audio. Verifica que el archivo sea válido.',
          );
        } catch (e) {
          print('❌ Error 500 sin detalles: ${response.body}');
          throw Exception('Error del servidor. Intenta de nuevo.');
        }
      } else {
        try {
          final error = json.decode(response.body);
          final errorMsg = error['error'] ?? 'Error desconocido';
          print('❌ Error ${response.statusCode}: $errorMsg');
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception(
            'Error al procesar la transacción (${response.statusCode})',
          );
        }
      }
    } catch (e) {
      print('❌ Error en VoiceService: $e');
      rethrow;
    }
  }

  /// Envío solo para parsear/transcribir sin intención de guardar.
  static Future<Map<String, dynamic>> sendVoiceParse(String audioPath) async {
    return await sendVoiceTransaction(audioPath, parseOnly: true);
  }

  /// Formatea el resultado de la transacción para mostrar al usuario
  static String formatTransactionResult(Map<String, dynamic> data) {
    try {
      final transcription = data['transcription'] as String? ?? '';
      final parsed = data['parsed'] as Map<String, dynamic>?;
      final transaction = data['transaction'] as Map<String, dynamic>?;
      final newBalance = data['newBalance'] as num?;
      final creditsRemaining = data['creditsRemaining'] as int?;

      if (parsed == null || transaction == null) {
        return 'Transacción registrada exitosamente';
      }

      final type = parsed['type'] as String? ?? 'expense';
      final amount = transaction['amount'] ?? 0.0;
      final description = parsed['description'] as String? ?? 'Sin descripción';
      final categoryName = parsed['categoryName'] as String? ?? '';
      final typeText = type == 'income' ? '💰 Ingreso' : '💸 Gasto';
      final typeEmoji = type == 'income' ? '✅' : '📤';

      String result =
          '''
$typeEmoji $typeText registrado
💵 Monto: S/ ${amount.toStringAsFixed(2)}
📝 Descripción: "$description"
''';

      if (categoryName.isNotEmpty) {
        result += '🏷️ Categoría: $categoryName\n';
      }

      result += '🎤 Dijiste: "$transcription"\n';

      if (newBalance != null) {
        result += '💳 Nuevo saldo: S/ ${newBalance.toStringAsFixed(2)}\n';
      }

      if (creditsRemaining != null) {
        result += '🪙 Créditos IA restantes: $creditsRemaining';
      }

      return result.trim();
    } catch (e) {
      return 'Transacción registrada exitosamente';
    }
  }

  /// Formatea mensajes de error para el usuario
  static String formatError(dynamic error) {
    final errorStr = error.toString();

    if (errorStr.contains('No autorizado')) {
      return '🔒 Por favor inicia sesión nuevamente';
    } else if (errorStr.contains('créditos')) {
      return '💳 No tienes créditos de IA suficientes para procesar audio';
    } else if (errorStr.contains('No se detectó voz clara')) {
      return errorStr.replaceAll('Exception:', '').trim();
    } else if (errorStr.contains('procesar')) {
      return '⚠️ No se pudo procesar el audio. Intenta de nuevo';
    } else if (errorStr.contains('Connection')) {
      return '📡 Error de conexión. Verifica tu internet';
    } else if (errorStr.contains('muy corta')) {
      return '⏱️ Grabación muy corta. Habla por al menos 5-10 segundos';
    } else {
      return '❌ Error: ${errorStr.replaceAll('Exception:', '').trim()}';
    }
  }
}
