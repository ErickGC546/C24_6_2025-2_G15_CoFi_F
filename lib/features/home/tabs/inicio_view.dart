import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'dart:async';
import 'package:cofi/core/services/home_service.dart';
import 'package:cofi/core/services/metas_service.dart';
import 'package:cofi/core/services/transaction_service.dart';
import 'package:cofi/core/services/budget_service.dart';
import 'package:cofi/core/services/category_service.dart';
import 'package:flutter/services.dart';

// Paquete para las acciones de deslizar (swipe)
import 'package:flutter_slidable/flutter_slidable.dart';

// Importar el widget del micrófono
import 'package:cofi/core/widgets/microphone_button.dart';

class InicioView extends StatefulWidget {
  const InicioView({super.key});

  @override
  State<InicioView> createState() => _InicioViewState();
}

class _InicioViewState extends State<InicioView> {
  final user = FirebaseAuth.instance.currentUser;
  // Inicializar listas vacías para evitar errores por acceso antes de cargar
  List<Map<String, dynamic>> goals = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> movements = <Map<String, dynamic>>[];
  double totalBalance = 0.0;
  double monthlyBudget = 0.0; // monto gastado o usado en el mes
  double monthlyBudgetGoal = 0.0; // presupuesto total del mes
  bool isLoading = true;
  String? error;
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> categories = [];
  String? selectedAccountId;

  // Notifiers para actualizaciones puntuales (evita rebuild completo)
  final ValueNotifier<List<Map<String, dynamic>>> _accountsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _movementsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _goalsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<double> _totalBalanceNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<double> _monthlyBudgetNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<double> _monthlyBudgetGoalNotifier =
      ValueNotifier<double>(0.0);

  // Helper para actualizar el estado de forma segura (evita setState cuando
  // el widget ya no está montado).
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    // Cargar datos al montar el widget. Usamos addPostFrameCallback para
    // asegurar que el contexto esté listo y evitar llamados prematuros.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHomeData();
    });
  }

  // Robust number parser used across the view (acepta String, num o null)
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  // Helper para formatear fechas usadas en la UI (admits DateTime, String or null)
  String _formatDisplayDate(dynamic raw) {
    if (raw == null) return _formatDate();

    DateTime dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is String) {
      dt = DateTime.tryParse(raw) ?? DateTime.now();
    } else if (raw is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else {
      // Fallback
      dt = DateTime.now();
    }

    final day = dt.day;
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final monthName = months[(dt.month - 1).clamp(0, 11)];
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day $monthName, $hour:$minute';
  }

  Future<void> _loadHomeData({bool showLoading = true}) async {
    if (showLoading) {
      _safeSetState(() {
        isLoading = true;
        error = null;
      });
    } else {
      // keep previous isLoading value; clear error silently
      error = null;
    }

    try {
      final data = await HomeService.getHomeData();

      // Mapear accounts. Solo reemplazar si el backend devolvió datos.
      final accountsData = data['accounts'] as List<dynamic>? ?? [];
      if (accountsData.isNotEmpty) {
        final newAccounts = accountsData
            .map((a) {
              return {
                'id': (a['id'] ?? '').toString(),
                'name': (a['name'] ?? 'Cuenta').toString(),
                'balance': _toDouble(a['balance']),
                'currency': (a['currency'] ?? 'PEN').toString(),
              };
            })
            .cast<Map<String, dynamic>>()
            .where((a) => (a['id'] as String).isNotEmpty)
            .toList();

        accounts = newAccounts;
        _accountsNotifier.value = List<Map<String, dynamic>>.from(newAccounts);
        // Mantener la cuenta seleccionada si ya existe, sino seleccionar la primera
        selectedAccountId =
            selectedAccountId ??
            (accounts.isNotEmpty ? accounts.first['id'] as String? : null);
      }

      // Mapear budgets -> obtener presupuesto mensual si existe
      final budgetsData = data['budgets'] as List<dynamic>? ?? [];
      if (budgetsData.isNotEmpty) {
        try {
          // Intentar encontrar presupuesto mensual entre los budgets devueltos
          final monthlyObj = budgetsData.firstWhere((b) {
            if (b is Map) {
              final p = (b['period'] ?? b['type'] ?? b['frequency'])
                  ?.toString()
                  .toLowerCase();
              return p == 'monthly' || p == 'mensual';
            }
            return false;
          }, orElse: () => budgetsData.first);

          if (monthlyObj is Map) {
            final budgetAmount = _toDouble(
              monthlyObj['budget'] ??
                  monthlyObj['amount'] ??
                  monthlyObj['value'] ??
                  0,
            );
            if (budgetAmount > 0) {
              monthlyBudgetGoal = budgetAmount;
              _monthlyBudgetGoalNotifier.value = monthlyBudgetGoal;
            }
          }
        } catch (_) {
          // ignore parsing errors, no budgets available
        }
      }

      // Mapear categories (solo si el backend devolvió categorías)
      final categoriesData = data['categories'] as List<dynamic>? ?? [];
      if (categoriesData.isNotEmpty) {
        categories = categoriesData
            .map((c) {
              return {
                'id': c['id'] ?? c['_id'],
                'name': c['name'] ?? c['title'] ?? 'Otros',
                'type': c['type'] ?? 'expense',
              };
            })
            .cast<Map<String, dynamic>>()
            .toList();
      }

      // Mapear transactions (solo si el backend devolvió datos). Evitar sobrescribir
      // movimientos existentes con una lista vacía por errores transitorios.
      final transactionsData = data['transactions'] as List<dynamic>? ?? [];
      if (transactionsData.isNotEmpty) {
        final newMovements = transactionsData
            .map((t) {
              final type = (t['type'] ?? 'expense').toString().toLowerCase();
              final rawAmount = t['amount'];
              final parsedAmount = _toDouble(rawAmount);
              // Ensure amount sign reflects the type
              final amount = type == 'income'
                  ? parsedAmount.abs()
                  : -parsedAmount.abs();
              final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
              final displayDate = _formatDisplayDate(rawDate);

              return {
                'id': t['id'] ?? t['_id'] ?? t['transactionId'],
                // backend uses 'note' for extra text
                'amount': amount,
                'title': t['note'] ?? t['description'] ?? t['title'] ?? '',
                'type': type,
                'date': displayDate,
                // si la transacción incluye un objeto category, preferir su nombre
                'category': (t['category'] is Map)
                    ? (t['category']['name'] ?? 'Otros')
                    : (t['category'] ?? t['categoryId'] ?? 'Otros'),
                'categoryId': (t['category'] is Map)
                    ? (t['category']['id'] ?? t['category']['_id'])
                    : (t['categoryId'] ?? t['category'] ?? null),
              };
            })
            .cast<Map<String, dynamic>>()
            .toList();

        movements = newMovements;
        _movementsNotifier.value = newMovements;

        // Initialize monthlyBudget as the sum of expenses (absolute value)
        monthlyBudget = movements.fold(0.0, (sum, m) {
          final amt = _toDouble(m['amount']);
          return sum + (amt < 0 ? amt.abs() : 0.0);
        });
        _monthlyBudgetNotifier.value = monthlyBudget;

        // totalBalance: if a monthly budget is set, treat the budget as the
        // starting balance and subtract expenses; otherwise, sum all amounts.
        if (monthlyBudgetGoal > 0) {
          totalBalance = (monthlyBudgetGoal - monthlyBudget);
        } else {
          totalBalance = movements.fold(
            0.0,
            (sum, m) => sum + _toDouble(m['amount']),
          );
        }
        _totalBalanceNotifier.value = totalBalance;
      }

      // Si no vinieron transacciones desde el backend, aún recalcular
      // montos a partir del estado local (puede venir de cache o estado previo)
      if (transactionsData.isEmpty) {
        // Recalcular monthlyBudget como suma de gastos actuales
        monthlyBudget = movements.fold(0.0, (sum, m) {
          final amt = _toDouble(m['amount']);
          return sum + (amt < 0 ? amt.abs() : 0.0);
        });
        _monthlyBudgetNotifier.value = monthlyBudget;

        if (monthlyBudgetGoal > 0) {
          totalBalance = (monthlyBudgetGoal - monthlyBudget);
        } else {
          totalBalance = movements.fold(
            0.0,
            (sum, m) => sum + _toDouble(m['amount']),
          );
        }
        _totalBalanceNotifier.value = totalBalance;
      }

      // Mapear metas (goals)
      // Obtener metas directamente desde el servicio de metas (/savings)
      try {
        final goalService = GoalService();
        final fetchedGoals = await goalService.getGoals();
        if (fetchedGoals.isNotEmpty) {
          final mapped = fetchedGoals
              .map((g) {
                return {
                  'id': g['id'] ?? g['_id'],
                  'title': g['title'] ?? g['name'] ?? 'Meta',
                  'current': _toDouble(
                    g['currentAmount'] ??
                        g['saved'] ??
                        g['amountSaved'] ??
                        g['current'] ??
                        0,
                  ),
                  'total': _toDouble(
                    g['targetAmount'] ??
                        g['target'] ??
                        g['goalAmount'] ??
                        g['amount'] ??
                        0,
                  ),
                };
              })
              .cast<Map<String, dynamic>>()
              .toList();

          goals = mapped;
          _goalsNotifier.value = mapped;
        } else {
          // No reemplazar metas existentes si la respuesta está vacía
        }
      } catch (_) {
        // Si falla la petición de metas, conservar las metas cargadas previamente
      }

      // Si no tiene metas, dejamos una lista vacía (la UI mostrará mensaje)

      if (showLoading) {
        _safeSetState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (showLoading) {
        _safeSetState(() {
          isLoading = false;
          error = e.toString();
        });
      } else {
        // For background refreshes, record error silently
        error = e.toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = user?.displayName ?? 'Usuario';
    // totalBalance y otros valores se actualizan mediante ValueNotifiers para
    // evitar reconstruir todo el árbol; no calcular aquí.

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              '¡Hola, $nombre!',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Resumen de tus finanzas',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            // account selector + total card
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Column(
                children: [
                  Text(
                    'Error: $error',
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadHomeData,
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            else ...[
              _buildTotalBalanceCard(context),
            ],
            const SizedBox(height: 16),
            _buildMonthlyBudgetCard(context),
            const SizedBox(height: 24),
            _buildRecentMovements(),
            const SizedBox(height: 20),
            _buildSavingsGoals(context),
            const SizedBox(height: 24),
            // 📊 GRÁFICOS PRINCIPALES
            _buildIncomeByCategory(),
            const SizedBox(height: 20),
            _buildWeeklyExpenses(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: const MicrophoneButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// --- TARJETA DE SALDO TOTAL (DISEÑO MEJORADO) ---
  Widget _buildTotalBalanceCard(BuildContext context) {
    // Calcular porcentaje de cambio (simulado)
    return ValueListenableBuilder<double>(
      valueListenable: _totalBalanceNotifier,
      builder: (context, total, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo Total',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'S/ ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: CustomActionButton(
                      onPressed: () =>
                          _showAddTransactionModal(context, isIncome: true),
                      backgroundColor: Colors.green.shade500,
                      icon: Icons.arrow_upward,
                      label: 'Ingreso',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomActionButton(
                      onPressed: () =>
                          _showAddTransactionModal(context, isIncome: false),
                      backgroundColor: Colors.red.shade500,
                      icon: Icons.arrow_downward,
                      label: 'Gasto',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// --- TARJETA DE PRESUPUESTO (DISEÑO MEJORADO) ---
  Widget _buildMonthlyBudgetCard(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBudgetModal(context),
      child: ValueListenableBuilder<double>(
        valueListenable: _monthlyBudgetNotifier,
        builder: (context, monthly, _) {
          return ValueListenableBuilder<double>(
            valueListenable: _monthlyBudgetGoalNotifier,
            builder: (context, goal, __) {
              final progress = (goal > 0)
                  ? (monthly / goal).clamp(0.0, 1.0)
                  : 0.0;
              final remaining = goal - monthly;
              final percentUsed = (progress * 100).toInt();

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Presupuesto Mensual',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (goal > 0)
                          InkWell(
                            onTap: () => _showBudgetModal(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Montos debajo del título
                    Text(
                      'S/ ${monthly.toStringAsFixed(2)} / S/ ${goal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 12,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.blue.shade100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress > 0.8
                                ? Colors.orange
                                : Colors.green.shade500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Queda S/ ${remaining.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$percentUsed% usado',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showBudgetModal(BuildContext context) {
    // Determinar si estamos editando o creando
    final bool isEditing = monthlyBudgetGoal > 0;
    
    final controller = TextEditingController(
      text: monthlyBudgetGoal > 0 ? monthlyBudgetGoal.toStringAsFixed(2) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEditing ? Icons.edit : Icons.add_circle_outline,
                        color: Colors.blue.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditing 
                          ? 'Editar Presupuesto Mensual' 
                          : 'Establecer Presupuesto Mensual',
                        style: const TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Presupuesto actual: S/ ${monthlyBudgetGoal.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      // Permitir solo números y un punto decimal (máx 2 decimales)
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Presupuesto mensual (S/)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: CustomActionButton(
                      onPressed: () async {
                        final value = double.tryParse(controller.text) ?? 0.0;
                        if (value <= 0) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ingresa un monto válido mayor a 0',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }

                        final bs = BudgetService();
                        final success = await bs.saveMonthlyBudget(
                          value,
                          categoryId: null,
                        );
                        if (success) {
                          monthlyBudgetGoal = value;
                          _monthlyBudgetGoalNotifier.value = value;

                          totalBalance = (monthlyBudgetGoal - monthlyBudget);
                          _totalBalanceNotifier.value = totalBalance;

                          try {
                            await _loadHomeData(showLoading: false);
                          } catch (_) {}

                          Navigator.pop(context);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEditing
                                    ? 'Presupuesto actualizado: S/ ${value.toStringAsFixed(2)}'
                                    : 'Presupuesto mensual guardado: S/ ${value.toStringAsFixed(2)}',
                                ),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            final msg =
                                bs.lastErrorMessage ??
                                'Error guardando presupuesto. Intenta de nuevo.';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      backgroundColor: isEditing 
                        ? Colors.orange.shade600 
                        : Colors.blue.shade500,
                      icon: isEditing ? Icons.edit : Icons.save,
                      label: isEditing 
                        ? 'Actualizar Presupuesto' 
                        : 'Guardar Presupuesto',
                    ),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          // Confirmar antes de eliminar
                          showDialog(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text('Eliminar Presupuesto'),
                              content: const Text(
                                '¿Estás seguro de que deseas eliminar el presupuesto mensual? Esta acción no se puede deshacer.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogCtx),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(dialogCtx); // cerrar diálogo
                                    
                                    // Resetear el presupuesto localmente
                                    monthlyBudgetGoal = 0.0;
                                    _monthlyBudgetGoalNotifier.value = 0.0;
                                    
                                    // Recalcular balance
                                    totalBalance = movements.fold(
                                      0.0,
                                      (sum, m) => sum + _toDouble(m['amount']),
                                    );
                                    _totalBalanceNotifier.value = totalBalance;
                                    
                                    Navigator.pop(ctx); // cerrar modal
                                    
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Presupuesto eliminado correctamente',
                                          ),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar Presupuesto'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🟢 Gráfico de Ingresos por Categoría
  Widget _buildIncomeByCategory() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _movementsNotifier,
      builder: (context, movementsList, _) {
        // Filtrar ingresos de los últimos 7 días
        final now = DateTime.now();
        final incomeByCategory = <String, double>{};
        final categoryNames = <String, String>{};
        
        // Mapear IDs de categoría a nombres
        for (final cat in categories) {
          final id = (cat['_id'] ?? cat['id'])?.toString();
          final name = (cat['name'] ?? cat['title'] ?? 'Sin categoría').toString();
          if (id != null) categoryNames[id] = name;
        }
        
        for (final t in movementsList) {
          try {
            // Verificar tipo de transacción
            final typeRaw = t['type'] ?? t['tipo'] ?? '';
            final typeStr = typeRaw.toString().toLowerCase();
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            
            // Determinar si es ingreso
            bool isIncome = typeStr.contains('income') || 
                           typeStr.contains('ingres') || 
                           amount > 0;
            
            if (!isIncome) continue;
            
            // Verificar si está en los últimos 7 días
            final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            DateTime dt;
            if (rawDate is DateTime)
              dt = rawDate;
            else if (rawDate is int)
              dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else
              dt = DateTime.tryParse(rawDate?.toString() ?? '') ?? now;

            final diff = now.difference(dt).inDays;
            if (diff < 0 || diff > 6) continue;

            // Obtener categoría (usar ID primero, luego nombre)
            final categoryId = (t['categoryId'] ?? t['category'])?.toString();
            String categoryName = 'Sin categoría';
            
            if (categoryId != null && categoryNames.containsKey(categoryId)) {
              categoryName = categoryNames[categoryId]!;
            } else if (t['categoryName'] != null) {
              categoryName = t['categoryName'].toString();
            } else if (categoryId != null) {
              categoryName = categoryId;
            }
            
            incomeByCategory[categoryName] = 
                (incomeByCategory[categoryName] ?? 0) + amount.abs();
          } catch (_) {}
        }

        // Ordenar por monto y tomar top 5
        final sortedEntries = incomeByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topEntries = sortedEntries.take(5).toList();
        
        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.green.shade50,
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.trending_up,
                        color: Colors.green.shade700,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ingresos por Categoría',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Últimos 7 días',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 200,
                  child: topEntries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.insert_chart, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'No hay ingresos en los últimos 7 días',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : _buildIncomeChart(topEntries),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIncomeChart(List<MapEntry<String, double>> topEntries) {
    final maxValue = topEntries.first.value;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: topEntries.map((entry) {
              final barHeight = (entry.value / maxValue) * 140;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'S/ ${entry.value.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        height: barHeight.clamp(20.0, 140.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.green.shade400,
                              Colors.green.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.shade300.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: topEntries.map((entry) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  entry.key.length > 8 
                      ? '${entry.key.substring(0, 8)}...'
                      : entry.key,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // 🔴 Gráfico de Gastos de la Semana
  Widget _buildWeeklyExpenses() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _movementsNotifier,
      builder: (context, movementsList, _) {
        // Obtener últimos 7 días
        final now = DateTime.now();
        final Map<String, double> dailyExpenses = {};
        
        // Inicializar últimos 7 días
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final label = '${date.day}/${date.month}';
          dailyExpenses[label] = 0.0;
        }

        // Sumar gastos por día
        for (final t in movementsList) {
          try {
            final typeRaw = t['type'] ?? t['tipo'] ?? '';
            final typeStr = typeRaw.toString().toLowerCase();
            final rawAmount = t['amount'] ?? t['monto'] ?? 0;
            final amount = rawAmount is num
                ? rawAmount.toDouble()
                : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
            
            // Determinar si es gasto
            bool isExpense = typeStr.contains('expense') || 
                            typeStr.contains('gasto') || 
                            amount < 0;
            
            if (!isExpense) continue;
            
            // Obtener fecha
            final rawDate = t['occurredAt'] ?? t['createdAt'] ?? t['date'];
            DateTime dt;
            if (rawDate is DateTime)
              dt = rawDate;
            else if (rawDate is int)
              dt = DateTime.fromMillisecondsSinceEpoch(rawDate);
            else
              dt = DateTime.tryParse(rawDate?.toString() ?? '') ?? now;

            // Verificar si está en los últimos 7 días
            final diff = now.difference(dt).inDays;
            if (diff >= 0 && diff <= 6) {
              final label = '${dt.day}/${dt.month}';
              if (dailyExpenses.containsKey(label)) {
                dailyExpenses[label] = 
                    (dailyExpenses[label] ?? 0) + amount.abs();
              }
            }
          } catch (_) {}
        }

        final values = dailyExpenses.values.toList();
        final labels = dailyExpenses.keys.toList();

        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.red.shade50,
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.trending_down,
                        color: Colors.red.shade700,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gastos de la Semana',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Últimos 7 días',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 230,
                  child: values.every((v) => v == 0)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.insert_chart, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'No hay gastos en los últimos 7 días',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : _buildWeeklyChart(values, labels),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeeklyChart(List<double> values, List<String> labels) {
    final maxValue = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final usableMax = maxValue > 0 ? maxValue : 1.0;
    final now = DateTime.now();

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final barHeight = (values[i] / usableMax) * 120;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (values[i] > 0)
                        Text(
                          'S/ ${values[i].toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        height: barHeight.clamp(4.0, 120.0),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.red.shade400,
                              Colors.red.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade300.withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(labels.length, (i) {
            // Obtener día de la semana
            final parts = labels[i].split('/');
            final day = int.tryParse(parts[0]) ?? 1;
            final month = int.tryParse(parts[1]) ?? 1;
            final date = DateTime(now.year, month, day);
            final weekday = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'][date.weekday % 7];
            
            return Expanded(
              child: Column(
                children: [
                  Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  /// --- MOVIMIENTOS RECIENTES (CON SWIPE ACTIONS) ---
  Widget _buildRecentMovements() {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _movementsNotifier,
      builder: (context, movementsList, _) {
        // Calcular altura máxima para 3 elementos (aproximadamente 80px cada uno)
        const double itemHeight = 80.0;
        const int maxVisibleItems = 3;
        final double maxHeight = itemHeight * maxVisibleItems;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Movimientos Recientes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (movementsList.length > maxVisibleItems)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${movementsList.length} total',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Container con altura máxima y scroll independiente
            Container(
              constraints: BoxConstraints(
                maxHeight: movementsList.isEmpty 
                    ? 100 
                    : (movementsList.length > maxVisibleItems 
                        ? maxHeight 
                        : movementsList.length * itemHeight),
              ),
              child: movementsList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No hay movimientos',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      // Habilitar scroll solo cuando hay más de 6 elementos
                      physics: movementsList.length > maxVisibleItems
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: movementsList.length,
                      itemBuilder: (context, index) {
                        final movement = movementsList[index];
                        return Slidable(
                          key: Key(
                            (movement['title'] ?? '') + (movement['date'] ?? ''),
                          ),

                          startActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (context) {
                                  _showEditTransactionModal(context, index);
                                },
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                icon: Icons.edit,
                                label: 'Editar',
                              ),
                            ],
                          ),

                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (context) {
                                  _deleteMovement(context, index);
                                },
                                backgroundColor: const Color(0xFFFE4A49),
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Eliminar',
                              ),
                            ],
                          ),

                          child: _MovementItem(
                            title: movement['title'],
                            amount: movement['amount'],
                            date: movement['date'],
                            category: movement['category'],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// --- METAS DE AHORRO ---
  Widget _buildSavingsGoals(BuildContext context) {
    const double cardHeight = 170.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Metas de Ahorro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.purple.shade600],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: _goalsNotifier,
                    builder: (context, goalsList, _) {
                      return Text(
                        '${goalsList.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: _goalsNotifier,
          builder: (context, goalsList, _) {
            if (goalsList.isEmpty) {
              return Container(
                height: cardHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple.shade50,
                      Colors.purple.shade100.withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.purple.shade200,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 48,
                      color: Colors.purple.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No tienes metas de ahorro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.purple.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toca una meta para comenzar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.purple.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              height: cardHeight,
              child: PageView.builder(
                controller: PageController(viewportFraction: 1.0),
                itemCount: goalsList.length,
                itemBuilder: (context, index) {
                  final g = goalsList[index];
                  final double current = _toDouble(g['current']);
                  final double total = _toDouble(g['total']);
                  final double progress = (total > 0)
                      ? (current / total).clamp(0.0, 1.0)
                      : 0.0;
                  final title = (g['title'] ?? 'Meta').toString();

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildGoalCard(
                      title,
                      current,
                      total,
                      progress,
                      index,
                      context,
                      cardHeight,
                      goalsList.length,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGoalCard(
    String title,
    double current,
    double total,
    double progress,
    int index,
    BuildContext context, [
    double cardHeight = 160,
    int totalGoals = 1,
  ]) {
    final cardWidth = MediaQuery.of(context).size.width - 48;
    final percent = (progress * 100).clamp(0, 100).round();
    final remaining = (total - current).clamp(0.0, double.infinity);

    // Colores dinámicos según el progreso
    final MaterialColor primaryColor = progress >= 1.0
        ? Colors.green
        : progress >= 0.7
            ? Colors.blue
            : progress >= 0.4
                ? Colors.orange
                : Colors.purple;

    return GestureDetector(
      onTap: () => _showGoalFormModal(context, index),
      child: Container(
        width: cardWidth,
        height: cardHeight,
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
              color: primaryColor.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Icono decorativo en el fondo
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                Icons.savings,
                size: 100,
                color: primaryColor.withOpacity(0.05),
              ),
            ),
            // Contenido principal
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
                          progress >= 1.0
                              ? Icons.check_circle
                              : Icons.flag,
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
                              title,
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
                              'Meta ${index + 1} de $totalGoals',
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
                  // Barra de progreso moderna
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
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
                            'S/ ${current.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: primaryColor.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'de S/ ${total.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Column(
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Acciones: Retirar y Ahorrar (modernas)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Retirar
                      ElevatedButton(
                        onPressed: () async {
                          final amountController = TextEditingController();
                          final confirmed = await showModalBottomSheet<bool>(
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
                                      const SizedBox(height: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
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
                                              child: const Icon(Icons.remove_circle_outline, color: Colors.white, size: 22),
                                            ),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                'Retirar Ahorro',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: amountController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'Monto a retirar',
                                          prefixText: 'S/ ',
                                          prefixIcon: Icon(Icons.attach_money, color: Colors.grey.shade600),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: const OutlineInputBorder(
                                            borderRadius: BorderRadius.all(Radius.circular(14)),
                                            borderSide: BorderSide(color: Color(0xFFDC2626), width: 2),
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
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFDC2626),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: const Text('Retirar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );

                          if (confirmed != true) return;

                          final text = amountController.text.trim();
                          final amount = double.tryParse(text.replaceAll(',', '.'));
                          if (amount == null || amount <= 0) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto válido')));
                            return;
                          }

                          final List<Map<String, dynamic>> currentGoals = List<Map<String, dynamic>>.from(_goalsNotifier.value);
                          if (index < 0 || index >= currentGoals.length) return;
                          final item = Map<String, dynamic>.from(currentGoals[index]);
                          final double cur = _toDouble(item['current']);
                          if (amount > cur) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No puedes retirar más de lo ahorrado')));
                            return;
                          }

                          final newSaved = (cur - amount).clamp(0.0, double.infinity);
                          // Backend update if id available
                          try {
                            final id = item['id']?.toString();
                            if (id != null && id.isNotEmpty) {
                              final goalService = GoalService();
                              await goalService.updateGoal(id, {'currentAmount': newSaved});
                            }
                          } catch (e) {
                            // Soft fail: keep UI responsive
                          }

                          // Update UI list and notifier
                          item['current'] = newSaved;
                          currentGoals[index] = item;
                          _goalsNotifier.value = List<Map<String, dynamic>>.from(currentGoals);
                          goals = currentGoals;
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retiro realizado')));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Retirar'),
                      ),
                      const SizedBox(width: 8),
                      // Ahorrar
                      ElevatedButton(
                        onPressed: () async {
                          final amountController = TextEditingController();
                          final confirmed = await showModalBottomSheet<bool>(
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
                                      const SizedBox(height: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Color(0xFF10B981), Color(0xFF059669)],
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
                                              child: const Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
                                            ),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                'Agregar Ahorro',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: amountController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'Monto a ahorrar',
                                          prefixText: 'S/ ',
                                          prefixIcon: Icon(Icons.attach_money, color: Colors.grey.shade600),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(14),
                                            borderSide: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: const OutlineInputBorder(
                                            borderRadius: BorderRadius.all(Radius.circular(14)),
                                            borderSide: BorderSide(color: Color(0xFF059669), width: 2),
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
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF059669),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );

                          if (confirmed != true) return;

                          final text = amountController.text.trim();
                          final amount = double.tryParse(text.replaceAll(',', '.'));
                          if (amount == null || amount <= 0) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa un monto válido')));
                            return;
                          }

                          final List<Map<String, dynamic>> currentGoals = List<Map<String, dynamic>>.from(_goalsNotifier.value);
                          if (index < 0 || index >= currentGoals.length) return;
                          final item = Map<String, dynamic>.from(currentGoals[index]);
                          final double cur = _toDouble(item['current']);
                          final newSaved = cur + amount;

                          try {
                            final id = item['id']?.toString();
                            if (id != null && id.isNotEmpty) {
                              final goalService = GoalService();
                              await goalService.updateGoal(id, {'currentAmount': newSaved});
                            }
                          } catch (e) {
                            // ignore backend failure for UI responsiveness
                          }

                          item['current'] = newSaved;
                          currentGoals[index] = item;
                          _goalsNotifier.value = List<Map<String, dynamic>>.from(currentGoals);
                          goals = currentGoals;
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ahorro agregado')));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Ahorrar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// --- FUNCIÓN PARA ELIMINAR UN MOVIMIENTO ---
  void _deleteMovement(BuildContext parentContext, int index) {
    final deletedMovement = movements[index];
    final id = deletedMovement['id'] as String?;

    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar este movimiento?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                if (id != null) {
                  await TransactionService.deleteTransaction(id);
                }

                if (!mounted) return;

                // Update local lists and notifiers without triggering a full rebuild
                final double amount = _toDouble(deletedMovement['amount']);
                totalBalance -= amount;
                if (amount < 0) {
                  monthlyBudget -= amount.abs();
                }
                movements.removeAt(index);
                _movementsNotifier.value = List<Map<String, dynamic>>.from(
                  movements,
                );
                _totalBalanceNotifier.value = totalBalance;
                _monthlyBudgetNotifier.value = monthlyBudget;
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Movimiento eliminado correctamente'),
                      backgroundColor: Colors.red,
                    ),
                  );
                // refresh to reflect backend state (silent refresh, no spinner)
                if (mounted) await _loadHomeData(showLoading: false);
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error eliminando: $e'),
                      backgroundColor: Colors.orange,
                    ),
                  );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  /// --- MODAL PARA EDITAR UN MOVIMIENTO ---
  void _showEditTransactionModal(BuildContext context, int index) {
    final originalMovement = movements[index];
    final double originalAmount = originalMovement['amount'];

    final montoController = TextEditingController(
      text: originalAmount.abs().toStringAsFixed(2),
    );
    final descripcionController = TextEditingController(
      text: originalMovement['title'],
    );

    // categorias vienen del backend; se usa id como valor y name para mostrar
    final categorias = categories;
    String categoriaSeleccionada = '';
    // intentar mapear category existente a id
    final origCat = originalMovement['category'];
    if (origCat is String) {
      // buscar por name
      final found = categories.firstWhere(
        (c) =>
            (c['name'] ?? '').toString().toLowerCase() == origCat.toLowerCase(),
        orElse: () => {},
      );
      if (found.isNotEmpty)
        categoriaSeleccionada = (found['id'] ?? '').toString();
    } else if (origCat is Map && origCat['id'] != null) {
      categoriaSeleccionada = origCat['id'].toString();
    } else if (origCat != null) {
      categoriaSeleccionada = origCat.toString();
    }
    final bool isIncome = originalAmount >= 0;

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
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
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  top: 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Barra de arrastre
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Título con ícono y gradiente
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isIncome
                                ? [Colors.green.shade400, Colors.green.shade600]
                                : [Colors.red.shade400, Colors.red.shade600],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (isIncome
                                      ? Colors.green.shade400
                                      : Colors.red.shade400)
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Editar ${isIncome ? "Ingreso" : "Gasto"}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Campo de Monto
                      TextField(
                        controller: montoController,
                        decoration: InputDecoration(
                          labelText: 'Monto',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixText: 'S/ ',
                          prefixStyle: TextStyle(
                            color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      // Campo de Descripción
                      TextField(
                        controller: descripcionController,
                        decoration: InputDecoration(
                          labelText: 'Descripción',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: Icon(
                            Icons.description_outlined,
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Dropdown de Categoría
                      DropdownButtonFormField<String>(
                        value: categoriaSeleccionada.isEmpty
                            ? null
                            : categoriaSeleccionada,
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: Icon(
                            Icons.category_outlined,
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        items: categorias
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: (c['id'] ?? '').toString(),
                                child: Text((c['name'] ?? 'Otros').toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setModalState(() {
                            categoriaSeleccionada = v ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 28),
                      // Botón de acción moderno
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () async {
                        final newMonto =
                            double.tryParse(montoController.text) ?? 0.0;
                        if (newMonto <= 0 ||
                            descripcionController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Por favor, completa todos los campos',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        final id = originalMovement['id'] as String?;
                        final newAmount = isIncome ? newMonto : -newMonto;

                        try {
                          if (id != null) {
                            final updated =
                                await TransactionService.updateTransaction(
                                  id: id,
                                  amount: newAmount,
                                  type: isIncome ? 'income' : 'expense',
                                  note: descripcionController.text.trim(),
                                  categoryId: categoriaSeleccionada,
                                );

                            // Update local model and notifiers without a full rebuild
                            final amountDifference = newAmount - originalAmount;
                            totalBalance += amountDifference;

                            if (originalAmount < 0)
                              monthlyBudget -= originalAmount.abs();
                            if (!isIncome) monthlyBudget += newMonto;

                            final rawDate =
                                updated['occurredAt'] ?? updated['createdAt'];

                            movements[index] = {
                              'id': updated['id'] ?? updated['_id'] ?? id,
                              'title': descripcionController.text.trim(),
                              'amount': newAmount,
                              'date': _formatDisplayDate(
                                rawDate ?? _formatDate(),
                              ),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            };
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _monthlyBudgetNotifier.value = monthlyBudget;
                          } else {
                            // If no id, just update locally
                            final amountDifference = newAmount - originalAmount;
                            totalBalance += amountDifference;
                            movements[index] = {
                              'title': descripcionController.text.trim(),
                              'amount': newAmount,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            };
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                          }

                          Navigator.pop(context);
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '✓ Movimiento actualizado correctamente',
                                ),
                                backgroundColor: Colors.blue,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          // refresh data from backend after update (silent)
                          if (mounted) await _loadHomeData(showLoading: false);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error actualizando: $e'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade500,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.blue.shade500.withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Guardar Cambios',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// --- MODAL PARA AGREGAR O RETIRAR EN METAS ---
  void _showGoalFormModal(BuildContext context, int index) {
    final goal = goals[index];
    final montoController = TextEditingController();
    final descripcionController = TextEditingController();

    final categorias = categories;
    String categoriaSeleccionada = categorias.isNotEmpty
        ? (categorias.first['id'] ?? '').toString()
        : '';

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
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
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  top: 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Barra de arrastre
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Título con ícono y gradiente
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.purple.shade400, Colors.purple.shade600],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.shade400.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.savings_outlined,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                goal['title'],
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Campo de Monto
                      TextField(
                        controller: montoController,
                        decoration: InputDecoration(
                          labelText: 'Monto',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixText: 'S/ ',
                          prefixStyle: TextStyle(
                            color: Colors.purple.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.purple.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      // Campo de Descripción
                      TextField(
                        controller: descripcionController,
                        decoration: InputDecoration(
                          labelText: 'Descripción',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: Icon(
                            Icons.description_outlined,
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.purple.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Dropdown de Categoría
                      DropdownButtonFormField<String>(
                        value: categoriaSeleccionada.isEmpty
                            ? null
                            : categoriaSeleccionada,
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          labelStyle: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: Icon(
                            Icons.category_outlined,
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: Colors.purple.shade500,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        items: categorias
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: (c['id'] ?? '').toString(),
                                child: Text((c['name'] ?? 'Otros').toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setModalState(() {
                            categoriaSeleccionada = v ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 28),
                      // Botones de acción
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () {
                            final monto =
                                double.tryParse(montoController.text) ?? 0.0;
                            // Update local state and notifiers without full rebuild
                            goal['current'] = (goal['current'] + monto).clamp(
                              0,
                              goal['total'],
                            );
                            totalBalance += monto;
                            movements.insert(0, {
                              'title': descripcionController.text.isEmpty
                                  ? goal['title']
                                  : descripcionController.text,
                              'amount': monto,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            });
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _goalsNotifier.value =
                                List<Map<String, dynamic>>.from(goals);
                            Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade500,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.green.shade500.withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Agregar',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: () {
                            final monto =
                                double.tryParse(montoController.text) ?? 0.0;
                            goal['current'] = max(0, goal['current'] - monto);
                            totalBalance -= monto;
                            monthlyBudget += monto;
                            movements.insert(0, {
                              'title': descripcionController.text.isEmpty
                                  ? goal['title']
                                  : descripcionController.text,
                              'amount': -monto,
                              'date': _formatDate(),
                              'category':
                                  (categories.firstWhere(
                                    (c) =>
                                        (c['id'] ?? '').toString() ==
                                        categoriaSeleccionada,
                                    orElse: () => {},
                                  )['name']) ??
                                  categoriaSeleccionada,
                              'categoryId': categoriaSeleccionada,
                            });
                            _movementsNotifier.value =
                                List<Map<String, dynamic>>.from(movements);
                            _totalBalanceNotifier.value = totalBalance;
                            _monthlyBudgetNotifier.value = monthlyBudget;
                            _goalsNotifier.value =
                                List<Map<String, dynamic>>.from(goals);
                            Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade500,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.red.shade500.withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.remove, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Retirar',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
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
      },
    );
  }

  /// --- MODAL PARA AGREGAR INGRESO O GASTO ---
  void _showAddTransactionModal(
    BuildContext context, {
    required bool isIncome,
  }) {
    final montoController = TextEditingController();
    final descripcionController = TextEditingController();

    final categorias = categories;
    String categoriaSeleccionada = isIncome
        ? (categorias.firstWhere(
                    (c) => (c['type'] ?? 'income') == 'income',
                    orElse: () =>
                        (categorias.isNotEmpty ? categorias.first : {}),
                  )['id'] ??
                  '')
              .toString()
        : (categorias.isNotEmpty
              ? (categorias.first['id'] ?? '').toString()
              : '');

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
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
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  top: 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // Barra de arrastre
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Título con ícono y gradiente
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isIncome
                              ? [Colors.green.shade400, Colors.green.shade600]
                              : [Colors.red.shade400, Colors.red.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (isIncome
                                    ? Colors.green.shade400
                                    : Colors.red.shade400)
                                .withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isIncome
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isIncome ? 'Agregar Ingreso' : 'Agregar Gasto',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Campo de Monto
                    TextField(
                      controller: montoController,
                      decoration: InputDecoration(
                        labelText: 'Monto',
                        labelStyle: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixText: 'S/ ',
                        prefixStyle: TextStyle(
                          color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    // Campo de Descripción
                    TextField(
                      controller: descripcionController,
                      decoration: InputDecoration(
                        labelText: 'Descripción',
                        labelStyle: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        hintText: 'Ej: Compra en supermercado',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: Icon(
                          Icons.description_outlined,
                          color: Colors.grey.shade600,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Dropdown de Categoría
                    DropdownButtonFormField<String>(
                      value: categoriaSeleccionada.isEmpty
                          ? null
                          : categoriaSeleccionada,
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        labelStyle: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          color: Colors.grey.shade600,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      items: categorias
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: (c['id'] ?? '').toString(),
                              child: Text((c['name'] ?? 'Otros').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setModalState(() {
                          categoriaSeleccionada = v ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    // Botón para crear nueva categoría
                    TextButton.icon(
                      onPressed: () async {
                        await _showCreateCategoryDialog(
                          context,
                          isIncome: isIncome,
                          onCategoryCreated: (newCategory) {
                            setModalState(() {
                              // Agregar la nueva categoría a la lista local
                              categories.add(newCategory);
                              // Seleccionarla automáticamente
                              categoriaSeleccionada = 
                                  (newCategory['id'] ?? '').toString();
                            });
                          },
                        );
                      },
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: isIncome ? Colors.green.shade600 : Colors.red.shade600,
                      ),
                      label: Text(
                        'Crear nueva categoría',
                        style: TextStyle(
                          color: isIncome ? Colors.green.shade600 : Colors.red.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Botón de acción moderno
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () async {
                          final monto =
                              double.tryParse(montoController.text) ?? 0.0;

                          if (monto <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor ingresa un monto válido',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                          if (descripcionController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor ingresa una descripción',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }

                        // llamar al backend para crear transacción (backend crea/encuentra cuenta principal)
                        try {
                          final amount = isIncome ? monto : -monto;
                          final createdResp =
                              await TransactionService.createTransaction(
                                amount: monto,
                                type: isIncome ? 'income' : 'expense',
                                note: descripcionController.text.trim(),
                                categoryId: categoriaSeleccionada,
                              );

                          // backend devuelve { message, transaction, newBalance }
                          final created =
                              createdResp['transaction'] ?? createdResp;
                          final newBalanceRaw = createdResp['newBalance'];
                          final newBalance = newBalanceRaw != null
                              ? _toDouble(newBalanceRaw)
                              : null;

                          // Update local state and notifiers without full rebuild
                          // Priorizar el balance del backend si está disponible
                          if (newBalance != null) {
                            totalBalance = newBalance;
                          } else {
                            // Fallback: calcular localmente
                            if (!isIncome) {
                              monthlyBudget += monto;
                              if (monthlyBudgetGoal > 0) {
                                totalBalance = monthlyBudgetGoal - monthlyBudget;
                              } else {
                                totalBalance += amount;
                              }
                            } else {
                              // Para ingresos
                              if (monthlyBudgetGoal > 0) {
                                // Si hay presupuesto mensual, los ingresos no afectan el balance
                                // El balance es: presupuesto - gastos
                                totalBalance = monthlyBudgetGoal - monthlyBudget;
                              } else {
                                // Sin presupuesto, sumar el ingreso
                                totalBalance += amount;
                              }
                            }
                          }

                          // Actualizar monthlyBudget solo si es gasto
                          if (!isIncome) {
                            monthlyBudget += monto;
                          }

                          final rawDate = created != null
                              ? (created['occurredAt'] ?? created['createdAt'])
                              : null;

                          movements.insert(0, {
                            'id': created != null
                                ? (created['id'] ??
                                      created['_id'] ??
                                      created['transactionId'])
                                : null,
                            'title': descripcionController.text.trim(),
                            'amount': amount,
                            'date': _formatDisplayDate(
                              rawDate ?? _formatDate(),
                            ),
                            'category':
                                (categories.firstWhere(
                                  (c) =>
                                      (c['id'] ?? '').toString() ==
                                      categoriaSeleccionada,
                                  orElse: () => {},
                                )['name']) ??
                                categoriaSeleccionada,
                            'categoryId': categoriaSeleccionada,
                          });
                          _movementsNotifier.value =
                              List<Map<String, dynamic>>.from(movements);
                          _totalBalanceNotifier.value = totalBalance;
                          _monthlyBudgetNotifier.value = monthlyBudget;

                          Navigator.pop(context);

                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isIncome
                                      ? '✓ Ingreso agregado correctamente'
                                      : '✓ Gasto registrado correctamente',
                                ),
                                backgroundColor: isIncome
                                    ? Colors.green
                                    : Colors.red,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          // No hacer refresh inmediato para evitar parpadeo
                          // El estado local ya está actualizado correctamente
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error creando transacción: $e'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isIncome
                              ? Colors.green.shade500
                              : Colors.red.shade500,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: (isIncome
                                  ? Colors.green.shade500
                                  : Colors.red.shade500)
                              .withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isIncome ? 'Confirmar Ingreso' : 'Confirmar Gasto',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  String _formatDate() {
    final now = DateTime.now();
    return '${now.day}/${now.month}, ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  /// --- MODAL PARA CREAR NUEVA CATEGORÍA ---
  Future<void> _showCreateCategoryDialog(
    BuildContext context, {
    required bool isIncome,
    required Function(Map<String, dynamic>) onCategoryCreated,
  }) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isIncome ? Colors.green : Colors.red).shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.category_outlined,
                  color: isIncome ? Colors.green.shade600 : Colors.red.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Nueva Categoría',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nombre de la categoría',
                  hintText: 'Ej: Restaurantes, Salario, etc.',
                  prefixIcon: Icon(
                    Icons.label_outline,
                    color: Colors.grey.shade600,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Descripción (opcional)',
                  hintText: 'Describe esta categoría...',
                  prefixIcon: Icon(
                    Icons.description_outlined,
                    color: Colors.grey.shade600,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isIncome ? Colors.green : Colors.red).shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tipo: ${isIncome ? "Ingreso" : "Gasto"}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancelar',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final name = nameController.text.trim();
                
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa un nombre para la categoría'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Crear la categoría en el backend
                final newCategory = await CategoryService.createCategory(
                  name: name,
                  type: isIncome ? 'income' : 'expense',
                  description: descriptionController.text.trim().isEmpty 
                      ? null 
                      : descriptionController.text.trim(),
                );

                if (newCategory != null) {
                  Navigator.pop(dialogContext);
                  
                  // Llamar al callback con la nueva categoría
                  onCategoryCreated(newCategory);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ Categoría "$name" creada correctamente'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error al crear la categoría. Intenta de nuevo.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isIncome ? Colors.green.shade500 : Colors.red.shade500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Crear',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================
// WIDGET REUTILIZABLE: CustomActionButton
// ============================================
class CustomActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color backgroundColor;
  final IconData icon;
  final String label;

  const CustomActionButton({
    super.key,
    required this.onPressed,
    required this.backgroundColor,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

// ============================================
// WIDGET PARA ITEM DE MOVIMIENTO
// ============================================
class _MovementItem extends StatelessWidget {
  final String title;
  final double amount;
  final String date;
  final String category;

  const _MovementItem({
    Key? key,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    return ListTile(
      title: Text(title.isEmpty ? category : title),
      subtitle: Text('$date | $category'),
      trailing: Text(
        'S/ ${amount.toStringAsFixed(2)}',
        style: TextStyle(
          color: isNegative ? Colors.red : Colors.green,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
