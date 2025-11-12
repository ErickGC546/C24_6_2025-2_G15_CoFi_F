import 'package:flutter/material.dart';
import '../../../core/services/group_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class GroupDetailPage extends StatefulWidget {
  final String? groupId;
  final Map<String, dynamic>? groupData;

  const GroupDetailPage({super.key, required this.groupId, this.groupData});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final GroupService _groupService = GroupService();
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _savings = [];
  final Map<String, bool> _savingLoading = {};
  Map<String, dynamic>? _groupDetail;
  String? _joinCode;
  bool _isAdminOrOwner = false;
  String? _myRole;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (widget.groupId == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _groupService.getGroupDetail(widget.groupId!);
      final members = await _groupService.getGroupMembers(widget.groupId!);
      final parsed = <Map<String, dynamic>>[];
      for (final m in members) {
        if (m is Map<String, dynamic>)
          parsed.add(m);
        else if (m is Map)
          parsed.add(Map<String, dynamic>.from(m));
      }
      if (!mounted) return;
      setState(() {
        _groupDetail = detail;
        _members = parsed;
      });
      // Determine if current user is admin/owner in this group
      final uid = FirebaseAuth.instance.currentUser?.uid;
      _isAdminOrOwner = false;
      for (final m in parsed) {
        try {
          final possibleIds = <dynamic>[
            m['userId'],
            m['uid'],
            m['user']?['id'],
            m['user']?['_id'],
            m['id'],
          ];
          final matches =
              uid != null &&
              possibleIds.any((x) => x != null && x.toString() == uid);
          final role = (m['role'] ?? 'member').toString();
          if (matches) {
            // store current user's role for later decisions (leave vs delete)
            _myRole = role;
            if (role == 'admin' || role == 'owner') {
              _isAdminOrOwner = true;
            }
            // stop searching once we matched the current user
            break;
          }
        } catch (_) {}
      }
      // Load group savings (metas)
      await _loadSavings();
      // Intentar obtener joinCode (si el usuario tiene permiso el backend lo retornará)
      try {
        final code = await _groupService.getJoinCode(widget.groupId!);
        if (mounted) setState(() => _joinCode = code);
      } catch (_) {
        // Ignorar errores no críticos al obtener joinCode
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSavings() async {
    if (widget.groupId == null) return;
    try {
      final data = await _groupService.getSavings(groupId: widget.groupId);
      final parsed = <Map<String, dynamic>>[];
      for (final s in data) {
        if (s is Map<String, dynamic>)
          parsed.add(s);
        else if (s is Map)
          parsed.add(Map<String, dynamic>.from(s));
      }
      if (!mounted) return;
      setState(() => _savings = parsed);
    } catch (e) {
      // ignore non-critical error but keep user informed in debug
      // (we don't set _error to avoid replacing main error UI)
    }
  }

  Future<void> _loadSavingDetail(String savingId, int index) async {
    if (_savingLoading[savingId] == true) return;
    _savingLoading[savingId] = true;
    if (mounted) setState(() {});
    try {
      final data = await _groupService.getSavingById(savingId);
      // normalize movements field name
      final moves =
          data['movements'] ??
          data['contributions'] ??
          data['transactions'] ??
          data['movementsList'] ??
          [];
      final merged = Map<String, dynamic>.from(_savings[index])..addAll(data);
      merged['movements'] = moves is List ? moves : [];
      merged['_detailed'] = true;
      if (!mounted) return;
      setState(() {
        _savings[index] = merged;
      });
    } catch (e) {
      // ignore; keep UI responsive
    } finally {
      _savingLoading[savingId] = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _showCreateSavingDialog() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool?>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con gradiente
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B9DC3), Color(0xFF6B7FA8)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.savings_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Crear Meta de Grupo',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: 'Título',
                          hintText: 'Ej. Viaje a la playa',
                          prefixIcon: Icon(Icons.label_outlined, color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF6B7FA8), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingresa un título'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: amountCtrl,
                        decoration: InputDecoration(
                          labelText: 'Monto objetivo',
                          hintText: 'Ej. 5000',
                          prefixIcon: Icon(Icons.attach_money, color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF6B7FA8), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;
                            if (text.isEmpty) return newValue;
                            if (!RegExp(r'^[0-9]*[\.,]?[0-9]*$').hasMatch(text)) {
                              return oldValue;
                            }
                            final sepMatches = RegExp(r'[\.,]').allMatches(text).length;
                            if (sepMatches > 1) return oldValue;
                            return newValue;
                          }),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                          final n = num.tryParse(v.replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Monto inválido';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Botones
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false)
                          Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7FA8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Crear',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true) return;
    final title = titleCtrl.text.trim();
    final amount = num.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un monto válido')),
        );
      }
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _groupService.createSaving(
        title: title,
        targetAmount: amount,
        groupId: widget.groupId,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meta creada')));
      await _loadSavings();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creando meta: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addIncomeToSaving(String savingId) async {
    final amountCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con gradiente verde suave
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF10B981).withOpacity(0.9),
                      const Color(0xFF059669).withOpacity(0.9),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Agregar Ingreso',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: amountCtrl,
                        decoration: InputDecoration(
                          labelText: 'Monto',
                          hintText: 'Ej. 500',
                          prefixIcon: Icon(Icons.attach_money, color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;
                            if (text.isEmpty) return newValue;
                            if (!RegExp(r'^[0-9]*[\.,]?[0-9]*$').hasMatch(text)) {
                              return oldValue;
                            }
                            final sepMatches = RegExp(r'[\.,]').allMatches(text).length;
                            if (sepMatches > 1) return oldValue;
                            return newValue;
                          }),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                          final n = num.tryParse(v.replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Monto inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: noteCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nota (opcional)',
                          hintText: 'Agrega un comentario...',
                          prefixIcon: Icon(Icons.note_outlined, color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              // Botones
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false)
                          Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Agregar',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    final amount = num.tryParse(amountCtrl.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa un monto válido')),
        );
      return;
    }
    final note = noteCtrl.text.trim();
    setState(() => _isLoading = true);
    try {
      await _groupService.createSavingMovement(
        savingId: savingId,
        amount: amount,
        note: note.isEmpty ? null : note,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingreso agregado')));
      await _loadSavings();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error agregando ingreso: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _regenerateJoinCode() async {
    final confirm = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Regenerar código'),
        content: const Text(
          '¿Seguro quieres regenerar el código de invitación? Esto invalidará el anterior.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Regenerar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      final newCode = await _groupService.regenerateJoinCode(widget.groupId!);
      if (!mounted) return;
      setState(() => _joinCode = newCode);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Código regenerado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error regenerando código: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _inviteMember() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String?>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header elegante
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B9DC3), Color(0xFF6B7FA8)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add_outlined, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Invitar Miembro',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ingresa el email del miembro que deseas invitar',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'ejemplo@correo.com',
                          prefixIcon: Icon(Icons.email_outlined, color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF6B7FA8), width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Ingresa un email';
                          if (!v.contains('@')) return 'Email inválido';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Botones
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          Navigator.of(context).pop(emailController.text.trim());
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7FA8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Invitar',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;
    setState(() => _isLoading = true);
    try {
      await _groupService.inviteMember(
        groupId: widget.groupId!,
        inviteeEmail: result,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitación enviada')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error invitando: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeRole(String memberId) async {
    final roles = ['member', 'admin'];
    String? newRole = roles.first;
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambiar rol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: roles.map((r) {
            return RadioListTile<String>(
              value: r,
              groupValue: newRole,
              title: Text(r),
              onChanged: (v) => newRole = v,
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(newRole),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    setState(() => _isLoading = true);
    try {
      await _groupService.updateMemberRole(memberId: memberId, newRole: result);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rol actualizado')));
      _loadDetail();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error actualizando rol: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMember(String memberId) async {
    final confirm = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar miembro'),
        content: const Text('¿Eliminar este miembro del grupo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      await _groupService.deleteMember(memberId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Miembro eliminado')));
      _loadDetail();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error eliminando miembro: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveGroup() async {
    final isOwner = _myRole == 'owner';
    final confirm = await showDialog<bool?>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con gradiente rojo elegante
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.shade400.withOpacity(0.9),
                      Colors.red.shade600.withOpacity(0.9),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isOwner ? Icons.delete_forever_outlined : Icons.exit_to_app_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isOwner ? 'Eliminar Grupo' : 'Salir del Grupo',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOwner ? Icons.warning_amber_rounded : Icons.info_outline,
                      size: 56,
                      color: isOwner ? Colors.orange.shade400 : Colors.blue.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isOwner
                          ? 'Eres el líder de este grupo'
                          : '¿Estás seguro?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOwner
                          ? 'Si sales, el grupo será eliminado permanentemente junto con toda su información.'
                          : 'Al salir del grupo, perderás acceso a todas sus funciones y contenido.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // Botones
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isOwner ? 'Eliminar' : 'Salir',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      if (_myRole == 'owner') {
        // Owner leaving -> delete the group
        await _groupService.deleteGroup(widget.groupId!);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Grupo eliminado')));
        }
        // Close the detail page
        Navigator.of(context).pop();
      } else {
        // Regular member leaves
        await _groupService.leaveGroup(widget.groupId!);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Has salido del grupo')));
        }
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Show a cleaner message (remove the "Exception: " prefix if present)
      String msg;
      try {
        msg = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
      } catch (_) {
        msg = e.toString();
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saliendo del grupo: $msg')),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildGoalCard({
    required String title,
    required double currentAmount,
    required double targetAmount,
    required double progress,
    required MaterialColor primaryColor,
    required String? savingId,
    required List contributions,
  }) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.shade50,
            Colors.white,
            primaryColor.shade50.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.shade100.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.savings,
                  color: primaryColor.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: primaryColor.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => _showMovementsDialog(title, contributions),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor.shade100.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.history,
                    size: 18,
                    color: primaryColor.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acumulado',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${currentAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primaryColor.shade700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Objetivo',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${targetAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: primaryColor.shade100.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                height: 8,
                width: MediaQuery.of(context).size.width * progress * 0.85,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor.shade400, primaryColor.shade600],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(0)}% completado',
                style: TextStyle(
                  fontSize: 11,
                  color: primaryColor.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (savingId != null) _addIncomeToSaving(savingId);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Agregar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMovementsDialog(String title, List contributions) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con gradiente azul-gris
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF8B9DC3), Color(0xFF6B7FA8)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.history_outlined, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Historial: $title',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: contributions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No hay movimientos',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: contributions.length,
                        separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200),
                        itemBuilder: (_, i) {
                          final c = contributions[i];
                          final who = c['userName'] ??
                              c['name'] ??
                              c['user']?['name'] ??
                              c['user']?['email'] ??
                              'Miembro';
                          final amt = c['amount'] ?? c['value'] ?? 0;
                          final note = c['note'] ?? c['description'] ?? '';
                          final date = c['createdAt'] ?? c['date'] ?? '';
                          
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        who.toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (note.toString().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          note.toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      if (date.toString().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          date.toString().substring(0, 10),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  '+\$${amt.toString()}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              // Close button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B7FA8),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.groupData?['name'] ?? _groupDetail?['name'] ?? 'Grupo';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _inviteMember,
            icon: const Icon(Icons.person_add),
          ),
          IconButton(
            onPressed: _leaveGroup,
            icon: const Icon(Icons.exit_to_app),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : RefreshIndicator(
              onRefresh: _loadDetail,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_groupDetail != null) ...[
                    // Header moderno del grupo
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF6B7280),
                            Color(0xFF4B5563),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.group_outlined,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _groupDetail!['name'] ?? 'Grupo',
                                      style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _groupDetail!['description'] ?? 'Sin descripción',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_joinCode != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.key_outlined,
                                    color: Colors.white.withOpacity(0.9),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Código: $_joinCode',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.95),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Copiar código',
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: _joinCode ?? ""),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Código copiado')),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_outlined, color: Colors.white),
                                    iconSize: 18,
                                  ),
                                  IconButton(
                                    tooltip: 'Regenerar código',
                                    onPressed: _regenerateJoinCode,
                                    icon: const Icon(Icons.refresh, color: Colors.white),
                                    iconSize: 18,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Tabs: Miembros | Metas
                  DefaultTabController(
                    length: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.primary,
                          unselectedLabelColor: Colors.black54,
                          tabs: const [
                            Tab(text: 'Miembros'),
                            Tab(text: 'Metas'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height:
                              400, // reasonable default; ListView inside will shrinkwrap
                          child: TabBarView(
                            children: [
                              // Members tab
                              _members.isEmpty
                                  ? Center(
                                      child: Container(
                                        margin: const EdgeInsets.all(32),
                                        padding: const EdgeInsets.all(32),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.blue.shade50,
                                              Colors.blue.shade100.withOpacity(0.3),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                            width: 2,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.people_outlined,
                                              size: 48,
                                              color: Colors.blue.shade300,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'No hay miembros',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.blue.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemCount: _members.length,
                                      itemBuilder: (_, index) {
                                        final m = _members[index];
                                        final memberId =
                                            m['id']?.toString() ??
                                            m['_id']?.toString() ??
                                            '';
                                        final role = m['role'] ?? 'member';
                                        final firebaseUser =
                                            FirebaseAuth.instance.currentUser;
                                        String memberName = '';
                                        String? memberPhoto;
                                        if (m['name'] != null &&
                                            m['name'].toString().trim().isNotEmpty) {
                                          memberName = m['name'].toString();
                                        } else if (m['email'] != null) {
                                          memberName = m['email'].toString();
                                        }
                                        memberPhoto =
                                            m['photoURL'] as String? ??
                                            m['photoUrl'] as String? ??
                                            m['avatar'] as String? ??
                                            m['picture'] as String?;
                                        final uid = firebaseUser?.uid;
                                        final possibleIds = <dynamic>[
                                          m['userId'],
                                          m['uid'],
                                          m['user']?['id'],
                                          m['user']?['_id'],
                                          m['id'],
                                        ];
                                        final matchesCurrentUser =
                                            uid != null &&
                                            possibleIds.any(
                                              (x) => x != null && x.toString() == uid,
                                            );
                                        if ((memberName.isEmpty ||
                                                memberPhoto == null) &&
                                            matchesCurrentUser) {
                                          memberName = memberName.isEmpty
                                              ? (firebaseUser?.displayName ??
                                                    firebaseUser?.email ??
                                                    'Miembro')
                                              : memberName;
                                          memberPhoto =
                                              memberPhoto ?? firebaseUser?.photoURL;
                                        }
                                        if (memberName.isEmpty)
                                          memberName = 'Miembro';
                                        String initials = '';
                                        try {
                                          final parts = memberName.split(
                                            RegExp(r"\s+"),
                                          );
                                          if (parts.length == 1)
                                            initials = parts[0]
                                                .substring(0, 1)
                                                .toUpperCase();
                                          else
                                            initials =
                                                (parts[0].substring(0, 1) +
                                                        parts[1].substring(0, 1))
                                                    .toUpperCase();
                                        } catch (_) {
                                          initials = memberName.isNotEmpty
                                              ? memberName[0].toUpperCase()
                                              : '?';
                                        }
                                        
                                        // Color para el rol
                                        final roleColor = role == 'owner'
                                            ? Colors.orange
                                            : role == 'admin'
                                                ? Colors.blue
                                                : Colors.grey;
                                        
                                        return Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                roleColor.shade50.withOpacity(0.3),
                                                Colors.white,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: roleColor.shade200,
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: roleColor.withOpacity(0.1),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            leading: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: roleColor.shade300,
                                                  width: 2,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: roleColor.withOpacity(0.2),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: CircleAvatar(
                                                radius: 24,
                                                backgroundImage: memberPhoto != null
                                                    ? NetworkImage(memberPhoto)
                                                    : null,
                                                backgroundColor: roleColor.shade100,
                                                child: memberPhoto == null
                                                    ? Text(
                                                        initials,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          color: roleColor.shade700,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            ),
                                            title: Text(
                                              memberName.toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            subtitle: Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    roleColor.shade400,
                                                    roleColor.shade600,
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                role == 'owner'
                                                    ? '👑 Líder'
                                                    : role == 'admin'
                                                        ? '⭐ Admin'
                                                        : '👤 Miembro',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            trailing: _isAdminOrOwner
                                                ? PopupMenuButton<String>(
                                                    icon: Icon(
                                                      Icons.more_vert,
                                                      color: roleColor.shade600,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    onSelected: (v) async {
                                                      if (v == 'role') {
                                                        await _changeRole(memberId);
                                                      } else if (v == 'delete') {
                                                        await _deleteMember(memberId);
                                                      }
                                                    },
                                                    itemBuilder: (_) => [
                                                      const PopupMenuItem(
                                                        value: 'role',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.admin_panel_settings, size: 20),
                                                            SizedBox(width: 8),
                                                            Text('Cambiar rol'),
                                                          ],
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'delete',
                                                        child: Row(
                                                          children: [
                                                            Icon(Icons.delete, size: 20, color: Colors.red),
                                                            SizedBox(width: 8),
                                                            Text('Eliminar', style: TextStyle(color: Colors.red)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),

                              // Savings (Metas) tab
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isAdminOrOwner) ...[
                                    Container(
                                      height: 50,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.08),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(14),
                                          onTap: _showCreateSavingDialog,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Icon(
                                                  Icons.add,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                'Crear Meta',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Expanded(
                                    child: _savings.isEmpty
                                        ? Center(
                                            child: Container(
                                              padding: const EdgeInsets.all(32),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.savings_outlined,
                                                    size: 48,
                                                    color: Colors.grey.shade400,
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    'No hay metas creadas',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Crea una meta para este grupo',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : ListView.separated(
                                            padding: const EdgeInsets.only(bottom: 16),
                                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                                            itemCount: _savings.length,
                                            itemBuilder: (_, i) {
                                              final s = _savings[i];
                                              final title = s['title'] ?? s['name'] ?? 'Meta';
                                              final target =
                                                  (s['targetAmount'] ??
                                                  s['target_amount'] ??
                                                  s['amount'] ??
                                                  0).toDouble();
                                              
                                              final contributions = s['movements'] ??
                                                  s['contributions'] ??
                                                  s['transactions'] ??
                                                  [];
                                              final savingId =
                                                  s['id']?.toString() ?? s['_id']?.toString();
                                              
                                              // Calcular total acumulado
                                              double currentAmount = 0;
                                              if (contributions is List) {
                                                for (var c in contributions) {
                                                  final amt = c['amount'] ?? c['value'] ?? 0;
                                                  currentAmount += (amt is num ? amt.toDouble() : 0);
                                                }
                                              }
                                              
                                              final progress = target > 0 ? (currentAmount / target).clamp(0.0, 1.0) : 0.0;
                                              
                                              // Colores sutiles y elegantes basados en progreso
                                              final MaterialColor primaryColor;
                                              if (progress >= 0.9) {
                                                primaryColor = Colors.blueGrey; // Completado
                                              } else if (progress >= 0.6) {
                                                primaryColor = Colors.grey; // Buen progreso
                                              } else if (progress >= 0.3) {
                                                primaryColor = Colors.grey; // Progreso medio
                                              } else {
                                                primaryColor = Colors.grey; // Inicio
                                              }
                                              
                                              // Load details if needed
                                              if ((contributions == null ||
                                                      (contributions is List &&
                                                          contributions.isEmpty)) &&
                                                  savingId != null &&
                                                  (s['_detailed'] == null ||
                                                      s['_detailed'] != true)) {
                                                if (_savingLoading[savingId] != true) {
                                                  Future.microtask(
                                                    () => _loadSavingDetail(savingId, i),
                                                  );
                                                }
                                              }
                                              
                                              return _buildGoalCard(
                                                title: title.toString(),
                                                currentAmount: currentAmount,
                                                targetAmount: target,
                                                progress: progress,
                                                primaryColor: primaryColor,
                                                savingId: savingId,
                                                contributions: contributions is List ? contributions : [],
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
