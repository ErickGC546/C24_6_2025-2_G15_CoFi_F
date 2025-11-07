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
      builder: (_) => AlertDialog(
        title: const Text('Crear Meta de Grupo'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresa un título'
                    : null,
              ),
              TextFormField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Monto objetivo'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                // Allow only digits and one decimal separator (dot or comma)
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final text = newValue.text;
                    if (text.isEmpty) return newValue;
                    // Reject if characters other than digits, dot or comma
                    if (!RegExp(r'^[0-9]*[\.,]?[0-9]*$').hasMatch(text)) {
                      return oldValue;
                    }
                    // Reject if more than one separator (dot or comma) is present
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false)
                Navigator.of(context).pop(true);
            },
            child: const Text('Crear'),
          ),
        ],
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
      builder: (_) => AlertDialog(
        title: const Text('Agregar ingreso'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Monto'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
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
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false)
                Navigator.of(context).pop(true);
            },
            child: const Text('Agregar'),
          ),
        ],
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
      builder: (_) => AlertDialog(
        title: const Text('Invitar miembro'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa un email';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(emailController.text.trim());
              }
            },
            child: const Text('Invitar'),
          ),
        ],
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
    final confirm = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salir del grupo'),
        content: Text(
          _myRole == 'owner'
              ? 'Eres el líder de este grupo. Si sales, el grupo será eliminado. ¿Deseas continuar?'
              : '¿Estás seguro que quieres salir del grupo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salir'),
          ),
        ],
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _groupDetail!['name'] ?? 'Grupo',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(_groupDetail!['description'] ?? ''),
                            const SizedBox(height: 8),
                            // Mostrar joinCode si está disponible
                            if (_joinCode != null) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      'Código de invitación: $_joinCode',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Copiar código',
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: _joinCode ?? ""),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Código copiado'),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy),
                                  ),
                                  IconButton(
                                    tooltip: 'Regenerar código',
                                    onPressed: _regenerateJoinCode,
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
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
                              ListView(
                                shrinkWrap: true,
                                children: _members.map((m) {
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
                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundImage: memberPhoto != null
                                            ? NetworkImage(memberPhoto)
                                            : null,
                                        child: memberPhoto == null
                                            ? Text(initials)
                                            : null,
                                      ),
                                      title: Text(memberName.toString()),
                                      subtitle: Text('Rol: $role'),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (v) async {
                                          if (v == 'role') {
                                            await _changeRole(memberId);
                                          } else if (v == 'delete') {
                                            await _deleteMember(memberId);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'role',
                                            child: Text('Cambiar rol'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),

                              // Savings (Metas) tab
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isAdminOrOwner) ...[
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: ElevatedButton.icon(
                                        onPressed: _showCreateSavingDialog,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Crear Meta'),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Expanded(
                                    child: _savings.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No hay metas para este grupo',
                                            ),
                                          )
                                        : ListView.builder(
                                            itemCount: _savings.length,
                                            itemBuilder: (_, i) {
                                              final s = _savings[i];
                                              final title =
                                                  s['title'] ??
                                                  s['name'] ??
                                                  'Meta';
                                              final target =
                                                  s['targetAmount'] ??
                                                  s['target_amount'] ??
                                                  s['amount'] ??
                                                  0;
                                              final date =
                                                  s['targetDate'] ??
                                                  s['target_date'] ??
                                                  s['dueDate'];
                                              // contributions/movements
                                              final contributions =
                                                  s['movements'] ??
                                                  s['contributions'] ??
                                                  s['transactions'] ??
                                                  [];
                                              final savingId =
                                                  s['id']?.toString() ??
                                                  s['_id']?.toString();
                                              // If we don't have details yet, load them lazily
                                              if ((contributions == null ||
                                                      (contributions is List &&
                                                          contributions
                                                              .isEmpty)) &&
                                                  savingId != null &&
                                                  (s['_detailed'] == null ||
                                                      s['_detailed'] != true)) {
                                                if (_savingLoading[savingId] !=
                                                    true) {
                                                  // schedule load after this build frame
                                                  Future.microtask(
                                                    () => _loadSavingDetail(
                                                      savingId,
                                                      i,
                                                    ),
                                                  );
                                                }
                                              }
                                              return Card(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              title.toString(),
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          Text(
                                                            'Objetivo: ${target.toString()}',
                                                          ),
                                                        ],
                                                      ),
                                                      if (date != null)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 6,
                                                              ),
                                                          child: Text(
                                                            'Fecha objetivo: ${date.toString()}',
                                                          ),
                                                        ),
                                                      const SizedBox(height: 8),
                                                      // show contributions if available
                                                      if (contributions
                                                              is List &&
                                                          contributions
                                                              .isNotEmpty) ...[
                                                        const Text(
                                                          'Movimientos:',
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        ...contributions.map<
                                                          Widget
                                                        >((c) {
                                                          final who =
                                                              c['userName'] ??
                                                              c['name'] ??
                                                              c['user']?['name'] ??
                                                              c['user']?['email'] ??
                                                              'Miembro';
                                                          final amt =
                                                              c['amount'] ??
                                                              c['value'] ??
                                                              0;
                                                          return ListTile(
                                                            dense: true,
                                                            title: Text(
                                                              who.toString(),
                                                            ),
                                                            trailing: Text(
                                                              amt.toString(),
                                                            ),
                                                          );
                                                        }).toList(),
                                                      ] else ...[
                                                        const Text(
                                                          'No hay movimientos aún',
                                                        ),
                                                      ],
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .end,
                                                        children: [
                                                          ElevatedButton(
                                                            onPressed: () {
                                                              final savingId =
                                                                  s['id']
                                                                      ?.toString() ??
                                                                  s['_id']
                                                                      ?.toString();
                                                              if (savingId !=
                                                                  null)
                                                                _addIncomeToSaving(
                                                                  savingId,
                                                                );
                                                            },
                                                            child: const Text(
                                                              '+ Ingreso',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
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
