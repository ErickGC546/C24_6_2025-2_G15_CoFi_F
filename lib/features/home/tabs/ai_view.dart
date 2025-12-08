import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cofi/core/services/ai_service.dart';
import 'package:cofi/core/services/conversation_service.dart';

class AiView extends StatefulWidget {
  const AiView({super.key});

  @override
  State<AiView> createState() => _AiViewState();
}

class _AiViewState extends State<AiView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _concise = true;
  String _lastSent = '';
  DateTime? _lastSentAt;
  bool _isSending = false; // 🆕 Bandera para evitar envíos concurrentes

  // 🆕 Variables para el sistema de conversaciones
  String? _currentConversationId;
  bool _isFirstMessage = true;
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoadingConversations = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    // Mostrar mensaje de bienvenida inicial (sin conversación)
    _messages.add(
      ChatMessage(
        text:
            '👋 ¡Hola! Soy tu asistente financiero inteligente. '
            'Puedo analizar tus hábitos de gasto, ayudarte con presupuestos y darte recomendaciones personalizadas. '
            '¿En qué puedo ayudarte hoy?',
        isUser: false,
        time: _getCurrentTime(),
      ),
    );
  }

  /// 🆕 Cargar lista de conversaciones
  Future<void> _loadConversations() async {
    setState(() {
      _isLoadingConversations = true;
    });

    try {
      final conversations = await ConversationService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
        });
      }
    } catch (e) {
      print('Error cargando conversaciones: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConversations = false;
        });
      }
    }
  }

  /// 🆕 Crear nueva conversación (botón en AppBar)
  Future<void> _createNewConversation() async {
    setState(() {
      _currentConversationId = null;
      _isFirstMessage = true;
      _messages.clear();
      _messages.add(
        ChatMessage(
          text:
              '👋 ¡Nueva conversación iniciada!\n\n'
              '💬 ¿En qué puedo ayudarte?',
          isUser: false,
          time: _getCurrentTime(),
        ),
      );
    });
  }

  /// 🆕 Generar título automático del primer mensaje (primeras 5 palabras)
  String _generateTitle(String firstMessage) {
    final words = firstMessage.trim().split(' ');
    if (words.length <= 5) {
      return firstMessage;
    }
    return '${words.take(5).join(' ')}...';
  }

  /// 🆕 Cargar conversación específica
  Future<void> _loadConversation(String conversationId) async {
    try {
      final conversation = await ConversationService.getConversationById(
        conversationId,
      );
      if (!mounted) return;

      setState(() {
        _currentConversationId = conversationId;
        _isFirstMessage = false;
        _messages.clear();
      });

      // Cargar mensajes de la conversación
      final recommendations = conversation['aiRecommendations'] as List;

      // Agrupar recomendaciones para evitar duplicación
      // Cada recomendación debería contener tanto la pregunta (inputJson) como la respuesta (recFull)
      for (var rec in recommendations) {
        String? userMessage;
        String? aiResponse;

        // Extraer mensaje del usuario del inputJson
        if (rec['inputJson'] != null) {
          try {
            dynamic input = rec['inputJson'];
            if (input is String) {
              input = jsonDecode(input);
            }

            // Buscar userQuestion dentro de context
            if (input['context'] != null && input['context'] is Map) {
              userMessage = input['context']['userQuestion']?.toString();
            }

            // Si no está en context, buscar directamente
            userMessage ??= input['userQuestion']?.toString();

            // Limpiar la instrucción de "Por favor responde en máximo X líneas"
            if (userMessage != null) {
              userMessage = userMessage
                  .replaceAll(
                    RegExp(r'\n\nPor favor responde en máximo \d+ líneas\.'),
                    '',
                  )
                  .trim();
            }
          } catch (e) {
            print('❌ Error parseando inputJson: $e');
          }
        }

        // Extraer respuesta de la IA
        if (rec['recFull'] != null && rec['recFull'].toString().isNotEmpty) {
          aiResponse = rec['recFull'].toString();
          // 🆕 Aplicar la misma limpieza que en respuestas en tiempo real
          aiResponse = _cleanFormatting(aiResponse);
          aiResponse = _replaceCurrencySymbols(aiResponse);
        }

        // Solo agregar si tenemos AMBOS: pregunta Y respuesta
        // Esto evita duplicación cuando el backend envía registros separados
        if (userMessage != null &&
            userMessage.isNotEmpty &&
            aiResponse != null &&
            aiResponse.isNotEmpty) {
          // Agregar mensaje del usuario
          _messages.add(
            ChatMessage(
              text: userMessage,
              isUser: true,
              time: _formatTimestamp(rec['generatedAt']),
            ),
          );

          // Agregar respuesta de la IA
          _messages.add(
            ChatMessage(
              text: aiResponse,
              isUser: false,
              time: _formatTimestamp(rec['generatedAt']),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    } catch (e) {
      print('Error cargando conversación: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar conversación'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Formatea el timestamp para mostrarlo en el chat
  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp == null) return _getCurrentTime();

      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        dateTime = timestamp;
      } else {
        return _getCurrentTime();
      }

      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return _getCurrentTime();
    }
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _sendMessage({String? predefinedMessage}) async {
    final text = predefinedMessage ?? _messageController.text.trim();
    if (text.isEmpty) return;

    // 🔒 PROTECCIÓN: Evitar envíos concurrentes
    if (_isSending) {
      print('⚠️ Ya hay un mensaje enviándose, ignorando duplicado');
      return;
    }

    // Evitar envíos repetidos idénticos consecutivos
    final now = DateTime.now();
    if (_lastSent.isNotEmpty && _lastSent == text && _lastSentAt != null) {
      final diff = now.difference(_lastSentAt!).inMilliseconds;
      if (diff < 1500) return;
    }
    _lastSent = text;
    _lastSentAt = now;

    // 🔒 Bloquear nuevos envíos
    setState(() {
      _isSending = true;
    });

    try {
      // 🆕 Si es el primer mensaje y no hay conversación, crearla automáticamente
      if (_currentConversationId == null || _isFirstMessage) {
        try {
          final newConv = await ConversationService.createConversation(
            title: _generateTitle(text),
          );
          setState(() {
            _currentConversationId = newConv['id'];
            _isFirstMessage = false;
            // Limpiar mensaje de bienvenida
            _messages.clear();
          });
          await _loadConversations();
        } catch (e) {
          print('Error creando conversación: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error al crear conversación'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Agregar mensaje del usuario
      final userMessage = ChatMessage(
        text: text,
        isUser: true,
        time: _getCurrentTime(),
      );
      if (!mounted) return;
      setState(() {
        _messages.add(userMessage);
        _isTyping = true;
      });

      _messageController.clear();
      _scrollToBottom();

      // Obtener respuesta de la IA con conversationId
      final aiReply = await AiService.getAIResponse(
        text,
        concise: _concise,
        conversationId: _currentConversationId,
      );

      if (mounted) {
        // Limpiar formato de la respuesta (remover asteriscos **)
        String cleanedResponse = aiReply;
        cleanedResponse = cleanedResponse.replaceAll(
          RegExp(r'\*\*(.*?)\*\*'),
          r'$1',
        );
        cleanedResponse = cleanedResponse.replaceAll(
          RegExp(r'\*(.*?)\*'),
          r'$1',
        );
        // 🇵🇪 Reemplazar símbolos de dólar por soles peruanos
        cleanedResponse = _replaceCurrencySymbols(cleanedResponse);

        final aiMessage = ChatMessage(
          text: cleanedResponse,
          isUser: false,
          time: _getCurrentTime(),
        );
        setState(() {
          _messages.add(aiMessage);
          _isTyping = false;
        });
        _scrollToBottom();

        // 🆕 Actualizar lista de conversaciones para reflejar el nuevo contador
        _loadConversations();
      }
    } catch (e) {
      print('❌ Error al enviar mensaje: $e');
      if (mounted) {
        setState(() {
          _isTyping = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar mensaje: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 🔓 Desbloquear envíos
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🆕 Drawer para lista de conversaciones
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.blue.shade50),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                    const SizedBox(width: 12),
                    const Text(
                      'Conversaciones',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      color: Colors.blue,
                      onPressed: () {
                        Navigator.pop(context);
                        _createNewConversation();
                      },
                      tooltip: 'Nueva',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoadingConversations
                    ? const Center(child: CircularProgressIndicator())
                    : _conversations.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            '📝 No hay conversaciones\n\nEscribe un mensaje para comenzar',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conv = _conversations[index];
                          final isActive = conv['id'] == _currentConversationId;
                          return ListTile(
                            leading: Icon(
                              Icons.chat_bubble,
                              color: isActive ? Colors.blue : Colors.grey,
                            ),
                            title: Text(
                              conv['title'] ?? 'Sin título',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${((conv['_count']?['aiRecommendations'] ?? 0) / 2).ceil()} mensajes',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isActive,
                            selectedTileColor: Colors.blue.shade50,
                            onTap: () {
                              Navigator.pop(context);
                              _loadConversation(conv['id']);
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: Colors.red.shade300,
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Eliminar conversación'),
                                    content: Text(
                                      '¿Eliminar "${conv['title'] ?? 'Sin título'}"?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text(
                                          'Eliminar',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await ConversationService.deleteConversation(
                                    conv['id'],
                                  );
                                  await _loadConversations();

                                  if (conv['id'] == _currentConversationId) {
                                    _createNewConversation();
                                  }
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Header con gradiente
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade400,
                  Colors.blue.shade600,
                  Colors.purple.shade500,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Análisis de IA',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'Asistente financiero inteligente',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sugerencias rápidas
          Container(
            height: 56,
            color: Colors.grey.shade50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildSuggestionChip(
                  '💰 Consejos de ahorro',
                  '¿Cómo puedo ahorrar más?',
                ),
                _buildSuggestionChip(
                  '📊 Análisis mensual',
                  'Analiza mis gastos del mes',
                ),
                _buildSuggestionChip(
                  '📝 Crear presupuesto',
                  '¿Cómo crear un presupuesto?',
                ),
              ],
            ),
          ),

          // Chat mensajes
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == _messages.length) {
                    return _buildTypingIndicator();
                  }
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
          ),

          // Input
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Pregúntame sobre tus finanzas...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade400,
                            Colors.purple.shade400,
                          ],
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                        ),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String label, String message) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.blue.shade200),
        ),
        onPressed: () => _sendMessage(predefinedMessage: message),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.purple.shade400],
                ),
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: message.isUser
                        ? LinearGradient(
                            colors: [
                              Colors.blue.shade400,
                              Colors.purple.shade400,
                            ],
                          )
                        : null,
                    color: message.isUser ? null : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                      bottomRight: Radius.circular(message.isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: message.isUser ? Colors.white : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.time,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.purple.shade400],
              ),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text("Escribiendo..."),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 🆕 Helper para limpiar formato markdown (igual que en ai_service.dart)
  String _cleanFormatting(String text) {
    // Remover ** bold markdown
    text = text.replaceAllMapped(RegExp(r"\*\*(.*?)\*\*"), (m) => m[1] ?? '');
    // Remover * italic markdown
    text = text.replaceAllMapped(RegExp(r"\*(.*?)\*"), (m) => m[1] ?? '');
    // Normalizar bullets
    text = text.replaceAllMapped(
      RegExp(r'^[ \t]*[\*\•][ \t]*', multiLine: true),
      (m) => '- ',
    );
    return text.trim();
  }

  // 🇵🇪 Helper para reemplazar símbolos de dólar y euro por soles peruanos
  String _replaceCurrencySymbols(String text) {
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

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;

  ChatMessage({required this.text, required this.isUser, required this.time});
}
