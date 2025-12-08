import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Servicio para manejar transacciones por voz
class VoiceService {
  static const String _backendUrl =
      "https://co-fi-web.vercel.app/api/voice/transaction";

  /// Envía el archivo de audio al backend para procesar la transacción
  /// Retorna un Map con el resultado del procesamiento
  static Future<Map<String, dynamic>> sendVoiceTransaction(
    String audioPath,
  ) async {
    try {
      // Obtener token de Firebase
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
        throw Exception('La grabación es muy corta. Habla más tiempo');
      }

      if (fileSize > 10 * 1024 * 1024) {
        // 10MB
        throw Exception('El archivo es muy grande. Graba menos tiempo');
      }

      // Crear multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));

      // Agregar headers
      request.headers['Authorization'] = 'Bearer $token';

      // Agregar archivo de audio
      final audioBytes = await audioFile.readAsBytes();

      // Determinar el tipo MIME correcto basado en la extensión
      String filename = 'recording.m4a';
      String contentType = 'audio/m4a';

      if (audioPath.endsWith('.webm')) {
        filename = 'recording.webm';
        contentType = 'audio/webm';
      } else if (audioPath.endsWith('.mp3')) {
        filename = 'recording.mp3';
        contentType = 'audio/mp3';
      } else if (audioPath.endsWith('.wav')) {
        filename = 'recording.wav';
        contentType = 'audio/wav';
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'audio',
        audioBytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      );
      request.files.add(multipartFile);

      print('🎤 Enviando audio al backend...');
      print(
        '📎 Archivo: $filename, tipo: $contentType, tamaño: ${audioBytes.length} bytes',
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
        return {'success': true, 'data': data};
      } else if (response.statusCode == 401) {
        throw Exception('No autorizado. Por favor inicia sesión nuevamente.');
      } else if (response.statusCode == 402) {
        final error = json.decode(response.body);
        throw Exception(
          error['error'] ?? 'No tienes créditos de IA suficientes',
        );
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        final errorMsg = error['error'] ?? 'No se pudo procesar el audio';
        print('⚠️ Error 400: $errorMsg');
        throw Exception(errorMsg);
      } else if (response.statusCode == 500) {
        try {
          final error = json.decode(response.body);
          final errorMsg = error['error'] ?? 'Error del servidor';
          final details = error['details'] ?? '';
          print('❌ Error 500: $errorMsg');
          print('🔍 Detalles: $details');
          throw Exception('Error al transcribir el audio. Intenta de nuevo.');
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

  /// Formatea el resultado de la transacción para mostrar al usuario
  static String formatTransactionResult(Map<String, dynamic> data) {
    try {
      final transcription = data['transcription'] as String? ?? '';
      final parsed = data['parsed'] as Map<String, dynamic>?;
      final transaction = data['transaction'] as Map<String, dynamic>?;

      if (parsed == null || transaction == null) {
        return 'Transacción registrada exitosamente';
      }

      final type = parsed['type'] as String? ?? 'expense';
      final amount = transaction['amount'] ?? 0.0;
      final description = parsed['description'] as String? ?? 'Sin descripción';
      final typeText = type == 'income' ? 'Ingreso' : 'Gasto';

      return '''
✅ $typeText registrado
💰 Monto: S/ ${amount.toStringAsFixed(2)}
📝 "${description}"
🎤 "${transcription}"
'''
          .trim();
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
      return '💳 No tienes créditos de IA suficientes';
    } else if (errorStr.contains('No se pudo detectar audio')) {
      return '🎤 No se detectó audio. Habla más claro y cerca del micrófono';
    } else if (errorStr.contains('procesar')) {
      return '⚠️ No se pudo procesar el audio. Intenta de nuevo';
    } else if (errorStr.contains('Connection')) {
      return '📡 Error de conexión. Verifica tu internet';
    } else {
      return '❌ Error: ${errorStr.replaceAll('Exception:', '').trim()}';
    }
  }
}
