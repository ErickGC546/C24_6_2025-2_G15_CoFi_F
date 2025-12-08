import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:cofi/core/services/voice_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Widget modular del botón de micrófono con animaciones
class MicrophoneButton extends StatefulWidget {
  final VoidCallback? onTranscriptionComplete;

  const MicrophoneButton({super.key, this.onTranscriptionComplete});

  @override
  State<MicrophoneButton> createState() => _MicrophoneButtonState();
}

class _MicrophoneButtonState extends State<MicrophoneButton>
    with TickerProviderStateMixin {
  bool _isListening = false;
  bool _hasPermission = false;
  bool _isProcessing = false;
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts _flutterTts = FlutterTts();
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _setupAnimations();
    _setupTts();
  }

  void _setupAnimations() {
    // Animación de pulso (ondas)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.8,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    // Animación de escala del ícono
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  Future<void> _setupTts() async {
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.status;
    setState(() {
      _hasPermission = status.isGranted;
    });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.microphone.request();

    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
      });
      _startListening();
    } else if (status.isDenied) {
      _showPermissionDialog(
        'Permiso denegado',
        'Necesitamos acceso al micrófono para esta función.',
      );
    } else if (status.isPermanentlyDenied) {
      _showPermissionDialog(
        'Permiso bloqueado',
        'Por favor, habilita el permiso del micrófono en la configuración de la app.',
      );
    }
  }

  void _showPermissionDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Configuración'),
          ),
        ],
      ),
    );
  }

  void _startListening() async {
    setState(() {
      _isListening = true;
    });

    // Iniciar animaciones
    _pulseController.repeat();
    _scaleController.forward();

    // Hablar el prompt
    await _speak(
      "Dime tu transacción. Por ejemplo: Gasté 50 soles en comida, o Recibí 100 soles de ingreso en salario",
    );

    try {
      // Obtener directorio temporal para guardar el audio
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioPath = '${directory.path}/recording_$timestamp.m4a';

      // Iniciar grabación
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _audioPath!,
      );

      debugPrint('🎤 Micrófono activado - Esperando transacción...');

      // Mostrar feedback visual
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.mic, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Habla ahora... Describe tu transacción')),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error al iniciar grabación: $e');
      setState(() {
        _isListening = false;
      });
      _pulseController.stop();
      _scaleController.reverse();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar grabación: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _stopListening() async {
    setState(() {
      _isListening = false;
      _isProcessing = true;
    });

    // Detener animaciones
    _pulseController.stop();
    _pulseController.reset();
    _scaleController.reverse();

    try {
      // Detener grabación
      final path = await _audioRecorder.stop();

      if (path == null || path.isEmpty) {
        throw Exception('No se guardó el audio');
      }

      // Validar que el archivo existe y tiene contenido
      final audioFile = File(path);

      if (!await audioFile.exists()) {
        throw Exception('El archivo de audio no existe');
      }

      final fileSize = await audioFile.length();
      debugPrint('🎤 Grabación finalizada: $path');
      debugPrint('📁 Tamaño del archivo: $fileSize bytes');

      if (fileSize == 0) {
        throw Exception('El archivo de audio está vacío');
      }

      if (fileSize < 1000) {
        throw Exception('La grabación es muy corta. Habla más tiempo');
      }

      // Mostrar feedback de procesamiento
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Procesando tu transacción...'),
              ],
            ),
            backgroundColor: Colors.blue.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }

      // Procesar la transacción
      await _processTransaction(path);

      // Eliminar archivo temporal
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('⚠️ No se pudo eliminar archivo temporal: $e');
      }
    } catch (e) {
      debugPrint('❌ Error al procesar audio: $e');

      final errorMessage = VoiceService.formatError(e);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _processTransaction(String audioPath) async {
    try {
      debugPrint('📤 Enviando audio al backend...');

      // Enviar el audio al backend para procesar la transacción completa
      final result = await VoiceService.sendVoiceTransaction(audioPath);

      if (result['success'] != true) {
        throw Exception('Error al procesar la transacción');
      }

      debugPrint('✅ Respuesta del backend recibida');

      // Obtener datos de la transacción
      final data = result['data'];
      final transcription =
          data['transcription']?.toString().trim() ?? 'Audio procesado';
      final transaction = data['transaction'] as Map<String, dynamic>?;
      final parsed = data['parsed'] as Map<String, dynamic>?;

      if (transaction == null) {
        throw Exception('No se pudo crear la transacción');
      }

      // Extraer información de la transacción
      final amount = transaction['amount']?.toString() ?? '0';
      final type = (parsed?['type'] ?? 'expense').toString();
      final typeText = type == 'income' ? 'Ingreso' : 'Gasto';
      final description = parsed?['description']?.toString() ?? transcription;

      debugPrint('💾 Transacción guardada: $typeText de S/ $amount');

      // Mostrar confirmación con voz
      await _speak(
        "Transacción guardada exitosamente. $typeText de $amount soles",
      );

      // Mostrar feedback visual de éxito
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      '¡Transacción guardada!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('💰 $typeText: S/ $amount'),
                if (description.isNotEmpty && description != amount)
                  Text('📝 $description'),
                const SizedBox(height: 4),
                Text(
                  '🎤 "$transcription"',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 4),
          ),
        );

        // Notificar al padre para recargar datos (actualizar movimientos recientes)
        await Future.delayed(const Duration(milliseconds: 500));
        widget.onTranscriptionComplete?.call();
      }
    } catch (e) {
      debugPrint('❌ Error al procesar transacción: $e');

      // Manejar error de forma más amigable
      String errorMsg = 'No pude procesar tu transacción';

      if (e.toString().contains('créditos')) {
        errorMsg = 'No tienes créditos de IA suficientes';
      } else if (e.toString().contains('No se pudo detectar audio') ||
          e.toString().contains('No se detectó')) {
        errorMsg = 'No te escuché bien. Habla más claro y cerca del micrófono';
      } else if (e.toString().contains('No autorizado')) {
        errorMsg = 'Necesitas iniciar sesión nuevamente';
      }

      await _speak(errorMsg);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Reintentar',
              textColor: Colors.white,
              onPressed: () {
                // Permitir reintentar
                if (!_isListening && !_isProcessing) {
                  _startListening();
                }
              },
            ),
          ),
        );
      }

      rethrow;
    }
  }

  void _toggleListening() {
    if (!_hasPermission) {
      _requestPermission();
      return;
    }

    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Ondas de pulso (solo cuando está activo)
        if (_isListening) ...[
          _buildPulseWave(0.0, Colors.blue.withOpacity(0.4)),
          _buildPulseWave(0.3, Colors.blue.withOpacity(0.3)),
          _buildPulseWave(0.6, Colors.blue.withOpacity(0.2)),
        ],

        // Botón principal
        ScaleTransition(
          scale: _scaleAnimation,
          child: GestureDetector(
            onTap: _isProcessing ? null : _toggleListening,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isProcessing
                      ? [Colors.orange.shade400, Colors.orange.shade600]
                      : _isListening
                      ? [Colors.red.shade400, Colors.red.shade600]
                      : [Colors.blue.shade400, Colors.blue.shade600],
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_isProcessing
                                ? Colors.orange
                                : _isListening
                                ? Colors.red
                                : Colors.blue)
                            .withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: _isProcessing
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
            ),
          ),
        ),

        // Indicador de estado
        if (_isProcessing)
          Positioned(
            bottom: -30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Procesando...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPulseWave(double delay, Color color) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final delayedValue = (_pulseAnimation.value - delay).clamp(0.0, 1.0);

        return Container(
          width: 70 * delayedValue * 1.5,
          height: 70 * delayedValue * 1.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(1.0 - delayedValue),
              width: 3,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}
