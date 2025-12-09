import 'package:flutter/material.dart';
import 'package:cofi/core/services/notification_service.dart';
import 'package:intl/intl.dart';

class NotificationsView extends StatefulWidget {
  @override
  _NotificationsViewState createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifications = await NotificationService.getNotifications();
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando notificaciones: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    await NotificationService.markAsRead(id);
    await _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.markAllAsRead();
    await _loadNotifications();
  }

  Future<void> _deleteNotification(String id) async {
    await NotificationService.deleteNotification(id);
    await _loadNotifications();
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'BUDGET_EXCEEDED':
        return Icons.warning_amber;
      case 'BUDGET_WARNING':
        return Icons.info_outline;
      case 'GOAL_ACHIEVED':
        return Icons.celebration;
      case 'GROUP_CONTRIBUTION':
        return Icons.add_circle_outline;
      case 'GROUP_WITHDRAWAL':
        return Icons.remove_circle_outline;
      case 'MEMBER_JOINED':
        return Icons.person_add;
      case 'MEMBER_LEFT':
        return Icons.person_remove;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'BUDGET_EXCEEDED':
        return Colors.red;
      case 'BUDGET_WARNING':
        return Colors.orange;
      case 'GOAL_ACHIEVED':
        return Colors.green;
      case 'GROUP_CONTRIBUTION':
        return Colors.blue;
      case 'GROUP_WITHDRAWAL':
        return Colors.purple;
      case 'MEMBER_JOINED':
        return Colors.teal;
      case 'MEMBER_LEFT':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'Ahora';
      } else if (difference.inHours < 1) {
        return 'Hace ${difference.inMinutes} min';
      } else if (difference.inDays < 1) {
        return 'Hace ${difference.inHours} h';
      } else if (difference.inDays < 7) {
        return 'Hace ${difference.inDays} días';
      } else {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notificaciones',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _markAllAsRead,
              child: Text(
                'Marcar todas',
                style: TextStyle(
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  return _buildNotificationCard(notification);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey[300]),
          SizedBox(height: 16),
          Text(
            'No tienes notificaciones',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Te avisaremos cuando haya algo nuevo',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final id = notification['id'] ?? '';
    final type = notification['type'] ?? '';
    final title = notification['title'] ?? '';
    final message = notification['message'] ?? '';
    final isRead = notification['isRead'] ?? false;
    final createdAt = notification['createdAt'];

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) => _deleteNotification(id),
      child: GestureDetector(
        onTap: () {
          if (!isRead) {
            _markAsRead(id);
          }
        },
        child: Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getColorForType(type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconForType(type),
                  color: _getColorForType(type),
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(0xFF6C63FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
