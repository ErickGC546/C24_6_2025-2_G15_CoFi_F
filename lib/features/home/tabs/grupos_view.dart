// grupos_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necesario para el input de números
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
      final groups = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          groups.add(item);
        } else if (item is Map) {
          groups.add(Map<String, dynamic>.from(item));
        }
      }
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

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final savingGoalController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Crear Nuevo Grupo'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del grupo *',
                      hintText: 'Ej. Viaje a Cusco',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingresa un nombre válido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: savingGoalController,
                    decoration: const InputDecoration(
                      labelText: 'Monto a ahorrar (S/) *',
                      hintText: 'Ej. 1500.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                      if (double.tryParse(v) == null) return 'Ingresa un número válido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (Opcional)',
                      hintText: 'Ej. Ahorro para los pasajes y hotel',
                    ),
                  ),
                ],
              ),
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
                  Navigator.of(context).pop({
                    "name": nameController.text.trim(),
                    "description": descriptionController.text.trim(),
                    "savingGoal": savingGoalController.text.trim(),
                  });
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() => _isLoading = true);
      try {
        final newGroup = await _groupService.createGroup(
          name: result['name']!,
          description: result['description'],
          savingGoal: double.parse(result['savingGoal']!),
        );

        _fetchGroups();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Grupo "${newGroup['name']}" creado')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear grupo: $e')),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchGroups,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mis Grupos',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 28),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
              if (_error != null) Center(child: Text('Error: $_error')),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _showCreateGroupDialog,
                  icon: Icon(Icons.add, color: Colors.orange[700]),
                  label: const Text(
                    'Crear Nuevo Grupo',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontSize: 16,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.orange.shade200, width: 1.4),
                    minimumSize: const Size(260, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              if (_groups.isEmpty && !_isLoading)
                const Center(
                  child: Text('Aún no tienes grupos. ¡Crea uno!'),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final name = group['name']?.toString() ?? 'Grupo sin nombre';
                    final membersCount = group['membersCount'] ?? 0;
                    final savingGoal = group['savingGoal'] ?? 0.0;

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$membersCount miembros • Meta: S/ ${savingGoal.toStringAsFixed(2)}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final id = group['id']?.toString() ?? group['_id']?.toString();
                          if (id != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupDetailPage(
                                  groupId: id,
                                  groupData: group,
                                ),
                              ),
                            ).then((_) => _fetchGroups());
                          }
                        },
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}