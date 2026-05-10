import 'package:flutter/material.dart';

import '../services/sync_service.dart';

/// Widget that displays the current sync status
class SyncStatusIndicator extends StatelessWidget {
  final SyncStatus status;
  final DateTime? lastSync;
  final VoidCallback? onTap;
  final bool showLabel;

  const SyncStatusIndicator({
    super.key,
    required this.status,
    this.lastSync,
    this.onTap,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = _getIconData();
    final color = _getColor();
    final tooltip = _getTooltip();

    Widget icon = Icon(
      iconData,
      color: color,
      size: 20,
    );

    // Add animation for syncing state
    if (status == SyncStatus.syncing) {
      icon = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }

    Widget content = icon;

    if (showLabel) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            _getLabel(),
            style: TextStyle(
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    if (onTap != null) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: status == SyncStatus.syncing ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: content,
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: content,
      ),
    );
  }

  IconData _getIconData() {
    switch (status) {
      case SyncStatus.idle:
        return Icons.cloud_done_outlined;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.success:
        return Icons.cloud_done;
      case SyncStatus.error:
        return Icons.cloud_off;
      case SyncStatus.offline:
        return Icons.cloud_off_outlined;
    }
  }

  Color _getColor() {
    switch (status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
      case SyncStatus.offline:
        return Colors.orange;
    }
  }

  String _getLabel() {
    switch (status) {
      case SyncStatus.idle:
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.success:
        return 'Synced';
      case SyncStatus.error:
        return 'Sync failed';
      case SyncStatus.offline:
        return 'Offline';
    }
  }

  String _getTooltip() {
    final baseMessage = _getLabel();

    if (lastSync != null && status != SyncStatus.syncing) {
      final ago = _formatTimeAgo(lastSync!);
      return '$baseMessage - Last sync: $ago';
    }

    if (status == SyncStatus.syncing) {
      return 'Syncing your data...';
    }

    if (status == SyncStatus.error) {
      return 'Sync failed - tap to retry';
    }

    if (status == SyncStatus.offline) {
      return 'Offline - will sync when online';
    }

    return baseMessage;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    }
  }
}

/// A more detailed sync status card for settings screens
class SyncStatusCard extends StatelessWidget {
  final SyncStatus status;
  final DateTime? lastSync;
  final String? userEmail;
  final VoidCallback? onSync;
  final VoidCallback? onLogout;

  const SyncStatusCard({
    super.key,
    required this.status,
    this.lastSync,
    this.userEmail,
    this.onSync,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User email
          if (userEmail != null) ...[
            Row(
              children: [
                Icon(Icons.account_circle, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    userEmail!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
          ],

          // Sync status
          Row(
            children: [
              SyncStatusIndicator(status: status, showLabel: true),
              const Spacer(),
              if (lastSync != null)
                Text(
                  'Last: ${_formatDateTime(lastSync!)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: status == SyncStatus.syncing ? null : onSync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync Now'),
                ),
              ),
              if (onLogout != null) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final timeStr =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    if (date == today) {
      return 'Today $timeStr';
    } else if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $timeStr';
    } else {
      return '${dateTime.month}/${dateTime.day} $timeStr';
    }
  }
}
