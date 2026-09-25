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
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';

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
      statusBarIconBrightness: Brightness.dark,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 14,
          bottom: 14,
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
        ),
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(bottom: BorderSide(color: SeColors.ink200)),
        ),
        child: Row(
          children: [
            // When reached as a pushed route (from Profile) there was no way
            // back — the bare title read as a broken, half-rendered header.
            if (Navigator.canPop(context)) ...[
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: SeColors.surface50, shape: BoxShape.circle),
                  child: const Icon(SeIcons.arrowLeft,
                      size: 20, color: SeColors.ink900),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text('Notifications', style: SeType.h1),
          ],
        ),
      );

  Widget _buildBody() {
    if (_loading) {
      return SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          itemCount: 6,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => Row(
            children: const [
              SeSkeleton.circle(size: 44),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 140, height: 13, radius: 5),
                    SizedBox(height: 8),
                    SeSkeleton(width: double.infinity, height: 11, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_notifications.isEmpty) {
      return Center(
        child: SeEmptyState(
          icon: SeIcons.bell,
          title: 'No notifications yet',
          message: "You're all caught up!",
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(SeSpacing.gutter),
      itemCount: _notifications.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildCard(_notifications[i]),
    );
  }

  Widget _buildCard(Map<String, dynamic> notif) {
    final title = notif['title'] as String? ?? 'Notification';
    final message = notif['message'] as String? ?? '';
    final type = notif['type'] as String? ?? 'info';
    final ts = notif['createdAt'] as Timestamp?;
    final unread = _isUnread(notif);

    final (IconData iconData, Color hue, Color tint) = switch (type) {
      'order' => (SeIcons.orders, SeColors.red500, SeColors.red50),
      'promo' => (SeIcons.tag, SeColors.gold500, SeColors.goldTint),
      _ => (SeIcons.bell, SeColors.ocean500, SeColors.oceanTint),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unread ? SeColors.red50 : SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(
            color: unread ? SeColors.red100 : SeColors.ink200,
            width: unread ? 1.5 : 1),
        boxShadow: unread ? SeElevation.e0 : SeElevation.e1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(iconData, size: 21, color: hue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: SeType.title)),
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: SeColors.red500, shape: BoxShape.circle),
                      ),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(message,
                      style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                ],
                if (ts != null) ...[
                  const SizedBox(height: 6),
                  Text(_timeAgo(ts.toDate()),
                      style: SeType.label.copyWith(color: SeColors.ink400)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
