import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_page.dart';
import '../widgets/se_skeleton.dart';

/// Alerts.
///
/// The old version drew each notification as its own shadowed card, and gave
/// unread ones a red fill plus a heavier red border plus a red dot — three
/// signals for one bit of information, which made a normal inbox look like a
/// list of errors. Unread is now carried by ONE thing: a red rule down the
/// leading edge. The rows sit in a single hairlined group, so the list reads as
/// an inbox rather than a pile.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  DateTime? _lastReadAt;
  StreamSubscription<List<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _subscribe();
    _markRead();
  }

  void _subscribe() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _notifSub =
        FirestoreService.notificationsStream(uid: uid).listen((notifs) {
      if (mounted) {
        setState(() {
          _notifications = notifs;
          _loading = false;
        });
      }
    });
    if (uid != null) {
      _profileSub = FirestoreService.watchUserProfile(uid).listen((data) {
        if (mounted) {
          final ts = data?['notificationsReadAt'] as Timestamp?;
          setState(() => _lastReadAt = ts?.toDate());
        }
      });
    }
  }

  Future<void> _markRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirestoreService.markNotificationsRead(uid);
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  bool _isUnread(Map<String, dynamic> notif) {
    if (_lastReadAt == null) return true;
    final ts = notif['createdAt'] as Timestamp?;
    if (ts == null) return false;
    return ts.toDate().isAfter(_lastReadAt!);
  }

  int get _unreadCount => _notifications.where(_isUnread).length;

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    return SePageScaffold(
      title: 'Alerts',
      subtitle: _loading
          ? null
          : unread > 0
              ? '$unread new ${unread == 1 ? 'update' : 'updates'}'
              : 'You are all caught up',
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading) return _loadingList();
    if (_notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.bell,
            title: 'Nothing yet',
            message:
                'Order updates and offers will land here as they happen.',
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, 20, SeSpacing.gutter, 110),
      itemCount: _notifications.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final n = _notifications[i];
        final ts = n['createdAt'] as Timestamp?;
        return SeNotificationRow(
          title: n['title'] as String? ?? 'Notification',
          message: n['message'] as String? ?? '',
          type: n['type'] as String? ?? 'info',
          when: ts == null ? '' : _timeAgo(ts.toDate()),
          unread: _isUnread(n),
        );
      },
    );
  }

  Widget _loadingList() => SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 20, SeSpacing.gutter, 24),
          itemCount: 6,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Row(
            children: const [
              SeSkeleton.circle(size: 38),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 150, height: 13, radius: 5),
                    SizedBox(height: 8),
                    SeSkeleton(width: double.infinity, height: 11, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// One alert. Unread is a red rule on the leading edge and nothing else.
class SeNotificationRow extends StatelessWidget {
  final String title;
  final String message;
  final String type;
  final String when;
  final bool unread;

  const SeNotificationRow({
    super.key,
    required this.title,
    required this.message,
    required this.type,
    required this.when,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color hue) = switch (type) {
      'order' => (SeIcons.bike, SeColors.brand),
      'delivered' => (SeIcons.checkCircle, SeColors.success),
      'promo' => (SeIcons.tag, SeColors.warning),
      _ => (SeIcons.info, SeColors.info),
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(color: SeColors.ink200),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The whole unread signal.
            SizedBox(
              width: 3,
              child: ColoredBox(
                color: unread ? SeColors.brandAction : Colors.transparent,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: hue.withValues(alpha: 0.10),
                        borderRadius: SeRadius.all(SeRadius.sm),
                      ),
                      child: Icon(icon, size: 19, color: hue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: SeType.title.copyWith(
                                    fontSize: 15,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (when.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(when,
                                      style: SeType.label
                                          .copyWith(color: SeColors.ink400)),
                                ),
                              ],
                            ],
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(message,
                                style: SeType.bodyS
                                    .copyWith(color: SeColors.ink500, height: 1.45)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
