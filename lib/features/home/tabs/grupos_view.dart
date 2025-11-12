// Tab Grupos
import 'package:flutter/material.dart';
import '../../../core/services/group_service.dart';
import 'group_detail_page.dart';

class GruposView extends StatefulWidget {
  const GruposView({super.key});

  @override
  State<GruposView> createState() => _GruposViewState();
}

class _GruposViewState extends State<GruposView> {
  final List<Map<String, dynamic>> _groups = [];
  final GroupService _groupService = GroupService();
  bool _isLoading = false;
  String? _error;

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Gradient gradient,
    required Color shadowColor,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onCreateGroupPressed() async {
    await _showCreateGroupDialog();
  }

  Future<void> _onJoinByCodePressed() async {
    final TextEditingController controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final code = await showDialog<String?>(
      context: context,
      builder: (context) {
        return Dialog(
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
                // Header con gradiente sutil
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
                          Icons.qr_code_scanner_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Unirse por código',
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
                    child: TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Código de invitación',
                        hintText: 'Ingresa el código del grupo',
                        prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.grey.shade600),
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
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa un código válido';
                        }
                        return null;
                      },
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
                            Navigator.of(context).pop(controller.text.trim());
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
                          'Unirse',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (code != null && code.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final resp = await _groupService.joinGroup(code);
        final message =
            resp['message'] ?? 'Te has unido al grupo correctamente';
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        // Refrescar la lista de grupos
        await _fetchGroups();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al unirse: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showCreateGroupDialog() async {
    final TextEditingController controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<String?>(
      context: context,
      builder: (context) {
        return Dialog(
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
                // Header con gradiente sutil
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
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
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Crear Nuevo Grupo',
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
                    child: TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Nombre del grupo',
                        hintText: 'Ej. Viaje con amigos',
                        prefixIcon: Icon(Icons.group_outlined, color: Colors.grey.shade600),
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
                          borderSide: const BorderSide(color: Color(0xFF4B5563), width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa un nombre válido';
                        }
                        return null;
                      },
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
                            Navigator.of(context).pop(controller.text.trim());
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4B5563),
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
        );
      },
    );

    if (created != null && created.isNotEmpty) {
      // Attempt to create group via API
      setState(() => _isLoading = true);
      try {
        final resp = await _groupService.createGroup(name: created);
        // Use server response name when available
        final name = resp['name'] ?? created;
        if (!mounted) return;
        // Refresh groups list so the newly created group includes server-side
        // fields (id, members, etc.). This ensures the creator appears
        // properly when opening the group detail.
        await _fetchGroups();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Grupo "${name}" creado')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al crear grupo: $e')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchGroups();
  }

  Future<void> _fetchGroups() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _groupService.getUserGroups();
      // Expecting a List of group objects; map to names
      final groups = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          groups.add(item);
        } else if (item is Map) {
          groups.add(Map<String, dynamic>.from(item));
        }
      }
      // If backend doesn't include member counts in the group list response,
      // try to fetch members for groups that lack that information.
      // We'll do this concurrently but keep it best-effort (ignore failures).
      try {
        final futures = <Future<void>>[];
        for (final g in groups) {
          final memberCount = _extractMemberCount(g);
          if (memberCount == 0) {
            final id = g['id']?.toString() ?? g['_id']?.toString();
            if (id != null) {
              futures.add(
                _groupService
                    .getGroupMembers(id)
                    .then((members) {
                      // store the members array so UI can read its length
                      g['members'] = members;
                    })
                    .catchError((_) {
                      // ignore errors here; it's optional
                    }),
              );
            }
          }
        }
        if (futures.isNotEmpty) await Future.wait(futures);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _groups.clear();
        _groups.addAll(groups);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper to extract member count from a group object using several
  // conventions the backend might use.
  int _extractMemberCount(Map<String, dynamic> group) {
    try {
      final membersField = group['members'];
      if (membersField is List) return membersField.length;
      if (membersField is int) return membersField;
      if (membersField is Map) {
        // maybe { count: X }
        final c =
            membersField['count'] ??
            membersField['length'] ??
            membersField['total'];
        if (c != null) return int.tryParse(c.toString()) ?? 0;
      }
    } catch (_) {}

    final possible =
        group['membersCount'] ??
        group['members_count'] ??
        group['memberCount'] ??
        group['member_count'] ??
        group['membersLength'];
    if (possible != null) return int.tryParse(possible.toString()) ?? 0;
    return 0;
  }

  int _extractExpenseCount(Map<String, dynamic> group) {
    try {
      final expensesField = group['expenses'];
      if (expensesField is List) return expensesField.length;
      if (expensesField is int) return expensesField;
      if (expensesField is Map) {
        final c =
            expensesField['count'] ??
            expensesField['length'] ??
            expensesField['total'];
        if (c != null) return int.tryParse(c.toString()) ?? 0;
      }
    } catch (_) {}

    final possibleE =
        group['expensesCount'] ??
        group['expenses_count'] ??
        group['expenseCount'] ??
        group['expense_count'] ??
        group['totalExpenses'];
    if (possibleE != null) return int.tryParse(possibleE.toString()) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título principal
          const Text(
            'Mis Grupos',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          // Subtítulo
          const Text(
            'Gestiona tus gastos compartidos',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black38,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 28),
          // Invitaciones pendientes - Diseño mejorado
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.shade200,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mail_outline,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invitaciones Pendientes',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Revisa tus invitaciones a grupos',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '0',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        color: Colors.grey.shade400,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'No tienes invitaciones pendientes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Botones de acción mejorados
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  onPressed: _onCreateGroupPressed,
                  icon: Icons.add_circle_outline,
                  label: 'Crear Grupo',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
                  ),
                  shadowColor: const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  onPressed: _onJoinByCodePressed,
                  icon: Icons.qr_code_scanner_outlined,
                  label: 'Unirse',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B9DC3), Color(0xFF6B7FA8)],
                  ),
                  shadowColor: const Color(0xFF8B9DC3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // Mostrar lista de grupos o texto cuando no hay
          if (_groups.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.grey.shade50,
                    Colors.grey.shade100.withOpacity(0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300, width: 1.5),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.group_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes grupos aún',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crea uno nuevo o únete usando un código',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF6B7280),
                            const Color(0xFF4B5563),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.groups,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Mis Grupos',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final name = group['name']?.toString() ?? 'Grupo';
                    final memberCount = _extractMemberCount(group);
                    final expenseCount = _extractExpenseCount(group);
                    
                    // Colores sutiles y elegantes
                    final colors = [
                      [const Color(0xFF8B9DC3), const Color(0xFF6B7FA8)], // Azul grisáceo
                      [const Color(0xFFA8B4C8), const Color(0xFF7D8BA3)], // Gris azulado
                      [const Color(0xFF9CA3AF), const Color(0xFF6B7280)], // Gris neutro
                      [const Color(0xFF94A3B8), const Color(0xFF64748B)], // Slate
                    ];
                    final colorSet = colors[index % colors.length];

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            final id =
                                group['id']?.toString() ??
                                group['_id']?.toString();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupDetailPage(
                                  groupId: id,
                                  groupData: group,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: colorSet,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorSet[0].withOpacity(0.2),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.group,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.people,
                                            size: 16,
                                            color: Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$memberCount miembros',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            Icons.receipt_long,
                                            size: 16,
                                            color: Colors.grey.shade500,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$expenseCount gastos',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.grey.shade400,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}
