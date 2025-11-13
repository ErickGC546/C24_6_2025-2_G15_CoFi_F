// Tab Metas
// lib/features/home/tabs/metas_view.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/metas_service.dart';

class Goal {
  final String? id;
  final String title;
  final double saved;
  final double target;
  final DateTime targetDate;

  Goal({
    this.id,
    required this.title,
    required this.saved,
    required this.target,
    required this.targetDate,
  });

  double get progress => (target <= 0) ? 0 : (saved / target).clamp(0.0, 1.0);

  int get daysLeft => targetDate.difference(DateTime.now()).inDays;

  // Robust mapper from API response
  factory Goal.fromMap(Map<String, dynamic> m) {
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
      return 0.0;
    }

    DateTime _parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          // Try common formats via DateTime.tryParse
          return DateTime.tryParse(v) ?? DateTime.now();
        }
      }
      return DateTime.now();
    }

    final id = m['id']?.toString() ?? m['_id']?.toString();
    final title = (m['title'] ?? m['name'] ?? '') as String;
    final saved = _toDouble(
      m['currentAmount'] ?? m['saved'] ?? m['savedAmount'] ?? m['amountSaved'],
    );
    final target = _toDouble(
      m['targetAmount'] ?? m['target'] ?? m['goalAmount'],
    );
    final targetDate = _parseDate(
      m['targetDate'] ?? m['date'] ?? m['goalDate'],
    );

    return Goal(
      id: id,
      title: title,
      saved: saved,
      target: target,
      targetDate: targetDate,
    );
  }
}

class MetasView extends StatefulWidget {
  const MetasView({super.key});

  @override
  State<MetasView> createState() => _MetasViewState();
}

class _MetasViewState extends State<MetasView> {
  final List<Goal> _goals = [];
  final GoalService _service = GoalService();
  bool _isLoading = false;
  bool _isSaving = false;

  final _titleController = TextEditingController();
  final _targetController = TextEditingController();
  DateTime? _selectedDate;
  final _dateController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    _safeSetState(() {
      _isLoading = true;
    });
    try {
      final data = await _service.getGoals();
      // Filter out group goals so personal view shows only user-owned goals
      final filtered = data.where((e) {
        final hasGroup =
            (e['groupId'] != null) ||
            (e['group'] != null) ||
            (e['group_id'] != null);
        return !hasGroup;
      }).toList();
      _safeSetState(() {
        _goals.clear();
        _goals.addAll(filtered.map((e) => Goal.fromMap(e)).toList());
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando metas: ${e.toString()}')),
        );
      }
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPad =
        MediaQuery.of(context).viewPadding.bottom +
        kBottomNavigationBarHeight +
        24;
    return RefreshIndicator(
      onRefresh: _loadGoals,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0,
          bottom: bottomPad,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Text(
              'Metas de Ahorro',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Visualiza y gestiona tus objetivos financieros',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildNewGoalButton(context),
            const SizedBox(height: 24),
            const Text(
              'Tus metas activas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildGoalsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    // Aggregated values
    final totalSaved = _goals.fold<double>(0, (p, e) => p + e.saved);
    final nearest = _goals.isEmpty
        ? null
        : _goals.reduce((a, b) => a.daysLeft < b.daysLeft ? a : b);

    Widget buildTile({
      required IconData icon,
      required String label,
      required String value,
      String? subtitle,
      MaterialColor? accent,
    }) {
      final MaterialColor color = accent ?? Colors.blueGrey;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color.shade700, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: buildTile(
            icon: Icons.flag_outlined,
            label: 'Meta más cercana',
            value: nearest?.title ?? '-',
            subtitle: nearest != null
                ? '${nearest.daysLeft} días restantes'
                : '-',
            accent: Colors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: buildTile(
            icon: Icons.savings_outlined,
            label: 'Total Ahorrado',
            value: 'S/ ${totalSaved.toStringAsFixed(0)}',
            subtitle: 'en ${_goals.length} metas activas',
            accent: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildNewGoalButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.purple.shade600],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showGoalModal(context),
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          label: const Text(
            'Crear nueva Meta',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _buildGoalsList() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_goals.isEmpty) {
      return const Text('No tienes metas activas');
    }

    return Column(
      children: List.generate(_goals.length * 2 - 1, (i) {
        final index = i ~/ 2;
        if (i.isOdd) return const SizedBox(height: 12);
        final g = _goals[index];
        return _buildGoalCardFromModel(g, index);
      }),
    );
  }

  Widget _buildGoalCardFromModel(Goal g, int index) {
    final formattedDate = DateFormat.yMMMMd().format(g.targetDate);
    final progress = g.progress;
    final percent = (progress * 100).clamp(0, 100).round();
    final remaining = (g.target - g.saved).clamp(0.0, double.infinity);

    // Colores dinámicos según progreso (igual que inicio)
    final MaterialColor primaryColor = progress >= 1.0
        ? Colors.green
        : progress >= 0.7
        ? Colors.blue
        : progress >= 0.4
        ? Colors.orange
        : Colors.purple;

    return GestureDetector(
      onTap: () => _showGoalActionsModal(context, g, index),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primaryColor.shade50,
              Colors.white,
              primaryColor.shade50.withOpacity(0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                Icons.savings,
                size: 80,
                color: primaryColor.withOpacity(0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          progress >= 1.0 ? Icons.check_circle : Icons.flag,
                          color: primaryColor.shade700,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: primaryColor.shade900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primaryColor.shade400,
                              primaryColor.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Barra de progreso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: primaryColor.shade100.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    primaryColor.shade400,
                                    primaryColor.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ahorrado',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'S/ ${g.saved.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: primaryColor.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'de S/ ${g.target.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Falta',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'S/ ${remaining.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Acciones: usar Wrap dentro de un SizedBox para evitar overflow en pantallas pequeñas
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => _showGoalModal(
                            context,
                            editingGoal: g,
                            index: index,
                          ),
                          child: const Text('Editar'),
                        ),
                        TextButton(
                          onPressed: () async {
                            // Confirm delete
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(20),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFEF4444),
                                              Color(0xFFDC2626),
                                            ],
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
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.warning_amber_outlined,
                                                color: Colors.white,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                'Eliminar meta',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Text(
                                              'Esta acción no se puede deshacer.',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Se eliminará la meta y su progreso asociado. ¿Deseas continuar?',
                                              style: TextStyle(
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          0,
                                          20,
                                          20,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(
                                                'Cancelar',
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFFDC2626,
                                                ),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Text(
                                                'Eliminar',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
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

                            if (confirmed == true) {
                              if (g.id == null) {
                                _safeSetState(() {
                                  _goals.removeAt(index);
                                });
                                return;
                              }
                              try {
                                _safeSetState(() {
                                  _isSaving = true;
                                });
                                await _service.deleteGoal(g.id!);
                                _safeSetState(() {
                                  _goals.removeAt(index);
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Meta eliminada'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error eliminando meta: ${e.toString()}',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                _safeSetState(() {
                                  _isSaving = false;
                                });
                              }
                            }
                          },
                          child: const Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        // NOTE: 'Retirar' and 'Ahorrar' buttons removed from list view.
                        // The actions are available when tapping the goal card.
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

  void _showGoalActionsModal(BuildContext context, Goal g, int index) async {
    final amountController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Title + simple amount
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.savings_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Ahorrado: S/ ${g.saved.toStringAsFixed(0)}'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto',
                    prefixText: 'S/ ',
                    prefixIcon: Icon(
                      Icons.attach_money,
                      color: Colors.grey.shade600,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final text = amountController.text.trim();
                        final amount = double.tryParse(
                          text.replaceAll(',', '.'),
                        );
                        if (amount == null || amount <= 0) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un monto válido'),
                              ),
                            );
                          return;
                        }
                        final gIndex = index;
                        if (gIndex < 0 || gIndex >= _goals.length) return;
                        final g0 = _goals[gIndex];
                        _safeSetState(() => _isSaving = true);
                        try {
                          final newSaved = (g0.saved + amount);
                          if (g0.id != null) {
                            await _service.updateGoal(g0.id!, {
                              'currentAmount': newSaved,
                            });
                          }
                          final updated = Goal(
                            id: g0.id,
                            title: g0.title,
                            saved: newSaved,
                            target: g0.target,
                            targetDate: g0.targetDate,
                          );
                          _safeSetState(() {
                            _goals[gIndex] = updated;
                          });
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ahorro agregado')),
                            );
                          Navigator.pop(ctx);
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error al agregar ahorro: ${e.toString()}',
                                ),
                              ),
                            );
                        } finally {
                          _safeSetState(() => _isSaving = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Ahorrar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final text = amountController.text.trim();
                        final amount = double.tryParse(
                          text.replaceAll(',', '.'),
                        );
                        if (amount == null || amount <= 0) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ingresa un monto válido'),
                              ),
                            );
                          return;
                        }
                        final gIndex = index;
                        if (gIndex < 0 || gIndex >= _goals.length) return;
                        final g0 = _goals[gIndex];
                        if (amount > g0.saved) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No puedes retirar más de lo ahorrado',
                                ),
                              ),
                            );
                          return;
                        }
                        _safeSetState(() => _isSaving = true);
                        try {
                          final newSaved = (g0.saved - amount).clamp(
                            0.0,
                            double.infinity,
                          );
                          if (g0.id != null) {
                            await _service.updateGoal(g0.id!, {
                              'currentAmount': newSaved,
                            });
                          }
                          final updated = Goal(
                            id: g0.id,
                            title: g0.title,
                            saved: newSaved,
                            target: g0.target,
                            targetDate: g0.targetDate,
                          );
                          _safeSetState(() {
                            _goals[gIndex] = updated;
                          });
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Retiro realizado')),
                            );
                          Navigator.pop(ctx);
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error al retirar: ${e.toString()}',
                                ),
                              ),
                            );
                        } finally {
                          _safeSetState(() => _isSaving = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retirar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGoalModal(BuildContext context, {Goal? editingGoal, int? index}) {
    // Prefill controllers when editing
    if (editingGoal != null) {
      _titleController.text = editingGoal.title;
      _targetController.text = editingGoal.target.toStringAsFixed(0);
      _selectedDate = editingGoal.targetDate;
      _dateController.text = DateFormat.yMMMMd().format(editingGoal.targetDate);
    } else {
      _titleController.clear();
      _targetController.clear();
      _dateController.clear();
      _selectedDate = null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF8B9DC3), Color(0xFF6B7FA8)],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
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
                        Expanded(
                          child: Text(
                            editingGoal != null
                                ? 'Editar meta'
                                : 'Crear nueva meta',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Inputs
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Nombre de la meta',
                      prefixIcon: Icon(
                        Icons.flag_outlined,
                        color: Colors.grey.shade600,
                      ),
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
                        borderSide: const BorderSide(
                          color: Color(0xFF6B7FA8),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _targetController,
                    decoration: InputDecoration(
                      labelText: 'Monto objetivo',
                      prefixIcon: Icon(
                        Icons.attach_money,
                        color: Colors.grey.shade600,
                      ),
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
                        borderSide: const BorderSide(
                          color: Color(0xFF6B7FA8),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      prefixText: 'S/ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _selectedDate ?? now.add(const Duration(days: 7)),
                        firstDate: now,
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null) {
                        _safeSetState(() {
                          _selectedDate = picked;
                          _dateController.text = DateFormat.yMMMMd().format(
                            picked,
                          );
                        });
                      }
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _dateController,
                        decoration: InputDecoration(
                          labelText: 'Fecha objetivo',
                          prefixIcon: Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey.shade600,
                          ),
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
                            borderSide: const BorderSide(
                              color: Color(0xFF6B7FA8),
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          hintText: 'Selecciona una fecha',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () async {
                                final title = _titleController.text.trim();
                                final targetText = _targetController.text
                                    .trim();
                                final target = double.tryParse(
                                  targetText.replaceAll(',', '.'),
                                );

                                if (title.isEmpty ||
                                    target == null ||
                                    _selectedDate == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Por favor completa todos los campos válidos',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                _safeSetState(() {
                                  _isSaving = true;
                                });

                                try {
                                  if (editingGoal != null &&
                                      index != null &&
                                      editingGoal.id != null) {
                                    final data = {
                                      'title': title,
                                      'targetAmount': target,
                                      'targetDate': _selectedDate!
                                          .toIso8601String(),
                                    };
                                    await _service.updateGoal(
                                      editingGoal.id!,
                                      data,
                                    );
                                    // Update local model
                                    final updated = Goal(
                                      id: editingGoal.id,
                                      title: title,
                                      saved: editingGoal.saved,
                                      target: target,
                                      targetDate: _selectedDate!,
                                    );
                                    _safeSetState(() {
                                      _goals[index] = updated;
                                    });
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Meta actualizada'),
                                        ),
                                      );
                                  } else {
                                    final created = await _service.createGoal(
                                      title: title,
                                      targetAmount: target,
                                      targetDate: _selectedDate,
                                    );
                                    // Convert response and add
                                    final newGoal = Goal.fromMap(created);
                                    _safeSetState(() {
                                      _goals.add(newGoal);
                                    });
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Meta creada'),
                                        ),
                                      );
                                  }
                                  Navigator.pop(context);
                                } catch (e) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error guardando meta: ${e.toString()}',
                                        ),
                                      ),
                                    );
                                } finally {
                                  _safeSetState(() {
                                    _isSaving = false;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B7FA8),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          editingGoal != null
                              ? 'Guardar cambios'
                              : 'Crear Meta',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
