// group_detail_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/group_service.dart';

class GroupDetailPage extends StatefulWidget {
  final String? groupId;
  final Map<String, dynamic>? groupData;

  const GroupDetailPage({super.key, required this.groupId, this.groupData});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final GroupService _groupService = GroupService();
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic>? _groupDetail;
  List<dynamic> _transactions = [];
  double _currentBalance = 0.0;
  double _savingGoal = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.groupId != null) {
      _loadGroupDetails();
    } else {
      setState(() {
        _error = "ID de grupo no proporcionado.";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadGroupDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _groupService.getGroupDetail(widget.groupId!),
        _groupService.getTransactions(widget.groupId!),
      ]);

      final groupDetail = results[0] as Map<String, dynamic>;
      final transactions = results[1] as List<dynamic>;

      double balance = 0.0;
      for (var tx in transactions) {
        final amount = tx['amount'];
        if (amount is num) {
          balance += amount;
        }
      }

      if (!mounted) return;
      setState(() {
        _groupDetail = groupDetail;
        _savingGoal = (groupDetail['savingGoal'] as num? ?? 0.0).toDouble();
        _transactions = transactions;
        _currentBalance = balance;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Error al cargar datos: ${e.toString()}";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showTransactionDialog({required bool isDeposit}) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isDeposit ? 'Agregar Ahorro' : 'Retirar Dinero'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Monto (S/) *'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un monto';
                  final amount = double.tryParse(v);
                  if (amount == null || amount <= 0) return 'Monto inválido';
                  if (!isDeposit && amount > _currentBalance) return 'No puedes retirar más de lo que hay';
                  return null;
                },
              ),
              TextFormField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Descripción (Opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, {
                  'amount': amountController.text,
                  'description': descriptionController.text,
                });
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        double amount = double.parse(result['amount']!);
        if (!isDeposit) {
          amount = -amount;
        }
        await _groupService.addTransaction(
          groupId: widget.groupId!,
          amount: amount,
          type: isDeposit ? 'deposit' : 'withdrawal',
          description: result['description'],
        );
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transacción registrada')));
        _loadGroupDetails();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _inviteMemberByEmail() async {
    // Implementación de invitar por email
  }

  Future<void> _generateAndShareLink() async {
    if (widget.groupId == null) return;
    try {
      final inviteLink = await _groupService.generateInviteLink(widget.groupId!);
      await Clipboard.setData(ClipboardData(text: inviteLink));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Link de invitación copiado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar link: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _savingGoal > 0 ? (_currentBalance / _savingGoal).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupData?['name'] ?? _groupDetail?['name'] ?? 'Detalle del Grupo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _inviteMemberByEmail,
            tooltip: 'Invitar por Email',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadGroupDetails,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Progreso del Ahorro', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Text(
                                    'S/ ${_currentBalance.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green[700]),
                                  ),
                                  const Spacer(),
                                  Text('Meta: S/ ${_savingGoal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(5)),
                              const SizedBox(height: 8),
                              Align(alignment: Alignment.centerRight, child: Text('${(progress * 100).toStringAsFixed(1)}% completado')),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _showTransactionDialog(isDeposit: true),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Ahorrar'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _showTransactionDialog(isDeposit: false),
                                    icon: const Icon(Icons.remove),
                                    label: const Text('Retirar'),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _generateAndShareLink,
                        icon: const Icon(Icons.link),
                        label: const Text('Generar Link de Invitación'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Historial', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      _transactions.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Aún no hay movimientos.')))
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _transactions.length,
                              itemBuilder: (context, index) {
                                final tx = _transactions.reversed.toList()[index];
                                final amount = (tx['amount'] as num).toDouble();
                                final isDeposit = amount >= 0;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(isDeposit ? Icons.arrow_upward : Icons.arrow_downward, color: isDeposit ? Colors.green : Colors.red),
                                    title: Text(tx['description'] ?? (isDeposit ? 'Depósito' : 'Retiro')),
                                    subtitle: Text('Por: ${tx['userName'] ?? 'Usuario'}'),
                                    trailing: Text(
                                      'S/ ${amount.abs().toStringAsFixed(2)}',
                                      style: TextStyle(color: isDeposit ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
    );
  }
}