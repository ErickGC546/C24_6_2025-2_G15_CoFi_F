import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
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
  static const int _groqBitRate = 128000;
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
  String? _confirmationPrompt;
  Timer? _mainAutoStopTimer;

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
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
  }

  Future<void> _speakAndAwaitCompletion(String text) async {
    final ttsCompleter = Completer<void>();

    _flutterTts.setCompletionHandler(() {
      if (!ttsCompleter.isCompleted) {
        ttsCompleter.complete();
      }
    });

    try {
      await _speak(text);
      await Future.any([
        ttsCompleter.future,
        Future.delayed(const Duration(seconds: 10)),
      ]);
    } finally {
      _flutterTts.setCompletionHandler(() {});
    }
  }

  void _schedulePrimaryAutoStop() {
    _mainAutoStopTimer?.cancel();
    _mainAutoStopTimer = Timer(const Duration(seconds: 5), () {
      if (_isListening && !_isProcessing) {
        _stopListening();
      }
    });
  }

  void _cancelPrimaryAutoStop() {
    _mainAutoStopTimer?.cancel();
    _mainAutoStopTimer = null;
  }

  void _restartListeningFlow() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (!_isListening && !_isProcessing) {
        _startListening();
      }
    });
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
    if (_isProcessing) return;

    _cancelPrimaryAutoStop();

    setState(() {
      _isListening = true;
    });

    _pulseController.repeat();
    _scaleController.forward();

    Future<void> beginRecording() async {
      try {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _audioPath = '${directory.path}/recording_$timestamp.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: _groqBitRate,
            sampleRate: 44100,
          ),
          path: _audioPath!,
        );

        _schedulePrimaryAutoStop();

        debugPrint('🎤 Micrófono activado - Esperando transacción...');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.mic, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Habla ahora... Describe tu transacción'),
                  ),
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
        _cancelPrimaryAutoStop();
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

    final recordingTrigger = Completer<void>();

    void handlePromptFinished() {
      if (recordingTrigger.isCompleted) return;
      _flutterTts.setCompletionHandler(() {});
      recordingTrigger.complete();
      unawaited(beginRecording());
    }

    _flutterTts.setCompletionHandler(handlePromptFinished);

    await _speak(
      "Dime tu transacción. Por ejemplo: Gasté 50 soles en comida, o Recibí 100 soles de ingreso en salario",
    );

    handlePromptFinished();

    await recordingTrigger.future;
  }

  void _stopListening() async {
    if (!_isListening || _isProcessing) {
      return;
    }

    _cancelPrimaryAutoStop();

    setState(() {
      _isListening = false;
      _isProcessing = true;
    });

    // Detener animaciones
    _pulseController.stop();
    _pulseController.reset();
    _scaleController.reverse();

    try {
      // Detener grabación y validar inmediatamente el archivo resultante
      final path = await _audioRecorder.stop();
      final validatedFile = await _validateRecordedFile(path);
      final validatedPath = validatedFile.path;

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
      await _processTransaction(validatedPath);

      // Eliminar archivo temporal
      try {
        final file = File(validatedPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('⚠️ No se pudo eliminar archivo temporal: $e');
      }
    } catch (e) {
      debugPrint('❌ Error al procesar audio: $e');

      const fallbackVoiceError =
          'Lo siento, no pude entender la transacción. ¿Podrías repetirla?';
      final errorMessage = VoiceService.formatError(e);

      await _speak(fallbackVoiceError);

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

      _restartListeningFlow();
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<File> _validateRecordedFile(String? path) async {
    if (path == null || path.isEmpty) {
      throw Exception('No se guardó el audio');
    }

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

    return audioFile;
  }

  Future<void> _processTransaction(String audioPath) async {
    bool parseStepCompleted = false;
    bool backendError = false;

    try {
      debugPrint('📤 Enviando audio al backend (parse only)...');
      final result = await VoiceService.sendVoiceTransaction(
        audioPath,
        parseOnly: true,
      );

      if (result['success'] != true) {
        backendError = true;
        throw Exception('Error al procesar la transacción');
      }

      final data = (result['data'] ?? {}) as Map<String, dynamic>;
      final parsed = data['parsed'] as Map<String, dynamic>?;

      if (parsed == null) {
        backendError = true;
        throw Exception('No se pudo interpretar la transacción');
      }

      parseStepCompleted = true;

      final amountCandidate = parsed['amount'] ?? parsed['value'] ?? 0;
      final parsedAmount = double.tryParse(amountCandidate.toString()) ?? 0.0;
      final descriptionRaw = (parsed['description'] ?? '').toString().trim();
      final categoryName = (parsed['categoryName'] ?? '').toString().trim();
      final confirmationDescription = descriptionRaw.isNotEmpty
          ? descriptionRaw
          : (categoryName.isNotEmpty ? categoryName : 'esta transacción');
      final promptAmount = parsedAmount > 0
          ? parsedAmount.toStringAsFixed(2)
          : amountCandidate.toString();

      final userConfirmed = await _askConfirmation(
        confirmationDescription,
        promptAmount,
      );

      if (!userConfirmed) {
        await _speak('Gasto no guardado');

        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Gasto no guardado'),
              backgroundColor: Colors.orange.shade600,
            ),
          );
        }

        return;
      }

      final confirmationResult = await VoiceService.sendVoiceTransaction(
        audioPath,
        parseOnly: false,
      );

      if (confirmationResult['success'] != true) {
        backendError = true;
        throw Exception('Error al guardar la transacción');
      }

      final confirmationData =
          confirmationResult['data'] as Map<String, dynamic>?;

      await _speak('Transacción guardada exitosamente.');

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmationData != null
                  ? VoiceService.formatTransactionResult(confirmationData)
                  : 'Transacción guardada',
            ),
            backgroundColor: Colors.green.shade600,
          ),
        );

        widget.onTranscriptionComplete?.call();
      }
    } catch (e) {
      debugPrint('❌ Error al procesar transacción: $e');

      const fallbackVoiceError =
          'Lo siento, no pude entender la transacción. ¿Podrías repetirla?';
      String snackMessage = fallbackVoiceError;
      String voiceMessage = fallbackVoiceError;
      bool restartFlow = backendError || !parseStepCompleted;

      if (e.toString().contains('créditos')) {
        snackMessage = 'No tienes créditos de IA suficientes';
        voiceMessage = snackMessage;
        restartFlow = false;
      } else if (e.toString().contains('No autorizado')) {
        snackMessage = 'Necesitas iniciar sesión nuevamente';
        voiceMessage = snackMessage;
        restartFlow = false;
      }

      await _speak(voiceMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackMessage),
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
                if (!_isListening && !_isProcessing) {
                  _startListening();
                }
              },
            ),
          ),
        );
      }

      if (restartFlow) {
        _restartListeningFlow();
      }
    }
  }

  Future<bool> _askConfirmation(
    String confirmationDescription,
    String promptAmount,
  ) async {
    final promptMessage =
        '¿Guardar $confirmationDescription por S/ $promptAmount?';

    if (mounted) {
      setState(() {
        _confirmationPrompt = promptMessage;
      });
    }

    try {
      await _speakAndAwaitCompletion(promptMessage);
      return await _captureConfirmationResponse();
    } finally {
      if (mounted) {
        setState(() {
          _confirmationPrompt = null;
        });
      }
    }
  }

  Future<bool> _captureConfirmationResponse() async {
    final directory = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final confirmPath = '${directory.path}/confirm_$ts.m4a';

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Responde "sí" o "no"'),
          backgroundColor: Colors.blue.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: _groqBitRate,
          sampleRate: 44100,
        ),
        path: confirmPath,
      );

      await Future.delayed(const Duration(seconds: 5));

      final stopPath = await _audioRecorder.stop();
      final confirmAudioPath = (stopPath != null && stopPath.isNotEmpty)
          ? stopPath
          : confirmPath;

      if (confirmAudioPath.isEmpty) {
        throw Exception('No se pudo obtener la confirmación');
      }

      final confirmResult = await VoiceService.sendVoiceTransaction(
        confirmAudioPath,
        parseOnly: true,
      );
      final confirmData = confirmResult['data'] as Map<String, dynamic>?;
      final confirmTranscription =
          confirmData?['transcription']?.toString() ?? '';
      final normalizedAnswer = _normalizeConfirmationText(confirmTranscription);

      const positiveKeywords = [
        'si',
        'sí',
        'ya',
        'claro',
        'dale',
        'guarda',
        'guardalo',
        'guardame',
        'confirma',
        'confirmo',
      ];

      const negativeKeywords = ['no', 'espera', 'cancela', 'cancelalo'];

      if (_containsKeyword(normalizedAnswer, negativeKeywords)) {
        return false;
      }

      if (_containsKeyword(normalizedAnswer, positiveKeywords)) {
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error en confirmación por voz: $e');
      rethrow;
    } finally {
      try {
        final f = File(confirmPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  String _normalizeConfirmationText(String value) {
    var normalized = value.toLowerCase();
    const accentMap = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};

    accentMap.forEach((key, replacement) {
      normalized = normalized.replaceAll(key, replacement);
    });

    normalized = normalized
        .replaceAll(RegExp(r'[^a-zñ\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized;
  }

  bool _containsKeyword(String normalized, List<String> keywords) {
    return keywords.any(
      (keyword) =>
          normalized.contains(keyword) ||
          normalized.split(' ').contains(keyword),
    );
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
      clipBehavior: Clip.none,
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

        if (_confirmationPrompt != null)
          Positioned(
            bottom: -80,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _confirmationPrompt!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
    _mainAutoStopTimer?.cancel();
    super.dispose();
  }
}
