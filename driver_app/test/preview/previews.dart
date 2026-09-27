import 'package:flutter/material.dart';
import 'package:shipeast_driver/driver_constants.dart';
import 'package:shipeast_driver/theme/se_brand.dart';
import 'package:shipeast_driver/theme/se_colors.dart';
import 'package:shipeast_driver/theme/se_icons.dart';
import 'package:shipeast_driver/theme/se_spacing.dart';
import 'package:shipeast_driver/theme/se_typography.dart';
import 'package:shipeast_driver/widgets/se_button.dart';
import 'package:shipeast_driver/widgets/se_card.dart';
import 'package:shipeast_driver/widgets/se_earnings_chart.dart';
import 'package:shipeast_driver/widgets/se_empty_state.dart';
import 'package:shipeast_driver/widgets/se_online_toggle.dart';
import 'package:shipeast_driver/widgets/se_page.dart';
import 'package:shipeast_driver/widgets/se_stat_tile.dart';
import 'package:shipeast_driver/widgets/se_step_tracker.dart';

/// Mirrors of the screens that cannot be pumped.
///
/// Five driver screens read Firestore in `initState` or `build`, and there is
/// no Firebase in a `flutter test` binary — they throw before their first
/// frame. Each mirror rebuilds the same composition from the same widgets
/// against fixed data, so what gets photographed is the real chrome, the real
/// tokens and the real components, with only the data faked.
///
/// A mirror is not a test. When one of these drifts from the screen it mirrors,
/// the mirror is the thing that is wrong.

// ── Dashboard ───────────────────────────────────────────────────────────────

Widget dashboardPreview({DriverPresence presence = DriverPresence.online}) =>
    SePageScaffold(
      showBack: false,
      capTitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Good afternoon',
              style: SeType.bodyS
                  .copyWith(color: SeColors.shellInk.withValues(alpha: 0.80))),
          const SizedBox(height: 2),
          Text('Andre Campbell',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  SeType.h1.copyWith(color: SeColors.shellInk, height: 1.15)),
        ],
      ),
      trailing: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: const Icon(SeIcons.userFill, color: SeColors.shellInk, size: 24),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeOnlineToggle(presence: presence, onChanged: (_) {}),
            const SizedBox(height: SeSpacing.x6),
            const SeSectionTitle(title: 'Today'),
            const SizedBox(height: SeSpacing.x3),
            const Row(
              children: [
                Expanded(
                  child: SeStatTile(
                    icon: SeIcons.wallet,
                    label: 'Earned today',
                    value: 4820,
                    prefix: Money.symbol,
                  ),
                ),
                SizedBox(width: SeSpacing.x3),
                Expanded(
                  child: SeStatTile(
                    icon: SeIcons.bike,
                    label: 'Deliveries',
                    value: 7,
                    hue: SeColors.info,
                    tint: SeColors.infoSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SeSpacing.x6),
            const SeSectionTitle(title: 'Current job'),
            const SizedBox(height: SeSpacing.x3),
            presence == DriverPresence.offline
                ? _offlineCard()
                : _activeJobCard(),
            const SizedBox(height: SeSpacing.x6),
            const SeSectionTitle(title: 'Quick actions'),
            const SizedBox(height: SeSpacing.x3),
            SeRowGroup(
              children: [
                SeRow(
                  icon: SeIcons.wallet,
                  label: 'View earnings',
                  subtitle: 'Trips, commission and payouts',
                  onTap: () {},
                ),
                SeRow(
                  icon: SeIcons.history,
                  label: 'Delivery history',
                  subtitle: 'Every job you have run',
                  hue: SeColors.success,
                  onTap: () {},
                ),
                SeRow(
                  icon: SeIcons.user,
                  label: 'My profile',
                  subtitle: 'Vehicle, licence and rating',
                  hue: SeColors.info,
                  onTap: () {},
                ),
                SeRow(
                  icon: SeIcons.chat,
                  label: 'Help & support',
                  subtitle: 'Reach the dispatch desk',
                  hue: SeColors.warning,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );

Widget dashboardOfflinePreview() =>
    dashboardPreview(presence: DriverPresence.offline);

Widget _offlineCard() => SeCard(
      padding: const EdgeInsets.all(SeSpacing.x5),
      color: SeColors.warningTint,
      border: Border.all(
          color: SeColors.warning.withValues(alpha: 0.35), width: 1.5),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SeColors.warning.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(SeIcons.warning, color: SeColors.warning, size: 22),
          ),
          const SizedBox(width: SeSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You are offline', style: SeType.title),
                const SizedBox(height: 2),
                Text('Flip the switch above to start receiving orders.',
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
        ],
      ),
    );

Widget _activeJobCard() => SeCard(
      padding: const EdgeInsets.all(SeSpacing.x5),
      border:
          Border.all(color: SeColors.brand.withValues(alpha: 0.40), width: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SeColors.brandSoft,
                  borderRadius: SeRadius.all(SeRadius.xs),
                ),
                child: const Icon(SeIcons.storefront,
                    color: SeColors.brandInk, size: 20),
              ),
              const SizedBox(width: SeSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACTIVE DELIVERY', style: SeType.eyebrow),
                    Text('Head to merchant', style: SeType.h3),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: SeSpacing.x2, vertical: SeSpacing.x1),
                decoration: BoxDecoration(
                  color: SeColors.surface50,
                  borderRadius: SeRadius.all(SeRadius.xs),
                ),
                child: Text('#SE4821BF',
                    style: SeType.tabular(SeType.label)
                        .copyWith(color: SeColors.ink500)),
              ),
            ],
          ),
          const SizedBox(height: SeSpacing.x4),
          _routeLine(),
          const SizedBox(height: SeSpacing.x4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: SeSpacing.x3),
            decoration: const BoxDecoration(
              color: SeColors.brandAction,
              borderRadius: SeRadius.pill,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(SeIcons.navigation, color: Colors.white, size: 18),
                const SizedBox(width: SeSpacing.x2),
                Text('Go to pickup',
                    style:
                        SeType.jakarta(15, FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );

Widget _routeLine() => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: SeColors.brandAction, shape: BoxShape.circle),
            ),
            Container(width: 2, height: 26, color: SeColors.ink200),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                  color: SeColors.ink300, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(width: SeSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Island Grill Morant Bay',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeType.title.copyWith(fontSize: 15)),
              const SizedBox(height: 14),
              Text('Kemar Brown · 14 Yallahs Main Road, St. Thomas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeType.bodyS.copyWith(color: SeColors.ink500)),
            ],
          ),
        ),
      ],
    );

// ── History ─────────────────────────────────────────────────────────────────

Widget historyPreview() => SePageScaffold(
      showBack: false,
      title: 'Delivery history',
      subtitle: 'Every job you have run',
      capBottom: SeShellTabs(
        tabs: const ['All', 'Completed', 'Cancelled'],
        selected: 0,
        onSelect: (_) {},
      ),
      child: Column(
        children: [
          _summaryStrip(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, SeSpacing.x4, SeSpacing.gutter, 24),
              children: [
                _historyRow('Island Grill Morant Bay', 'Delivered',
                    '2 Aug · 7:04 pm', 620, true),
                const SizedBox(height: SeSpacing.x3),
                _historyRow('Fontana Pharmacy', 'Delivered', '2 Aug · 4:12 pm',
                    480, true),
                const SizedBox(height: SeSpacing.x3),
                _historyRow('Package pickup · Bath', 'Cancelled',
                    '1 Aug · 11:30 am', 0, false),
              ],
            ),
          ),
        ],
      ),
    );

Widget historyEmptyPreview() => SePageScaffold(
      showBack: false,
      title: 'Delivery history',
      subtitle: 'Every job you have run',
      capBottom: SeShellTabs(
        tabs: const ['All', 'Completed', 'Cancelled'],
        selected: 2,
        onSelect: (_) {},
      ),
      child: const SeEmptyState(
        icon: SeIcons.history,
        title: 'No cancelled trips',
        message: 'Nothing here — every job you took, you finished.',
        hue: SeColors.success,
        tint: SeColors.successTint,
      ),
    );

Widget _summaryStrip() => SeCard(
      margin: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, SeSpacing.x4, SeSpacing.gutter, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: SeSpacing.x4, vertical: SeSpacing.x4),
      child: Row(
        children: [
          _summaryItem('34', 'Total trips', SeColors.ink900),
          Container(width: 1, height: 34, color: SeColors.ink200),
          _summaryItem('32', 'Completed', SeColors.success),
          Container(width: 1, height: 34, color: SeColors.ink200),
          _summaryItem('94%', 'Completion', SeColors.info),
        ],
      ),
    );

Widget _summaryItem(String value, String label, Color color) => Expanded(
      child: Column(
        children: [
          Text(value, style: SeType.tabular(SeType.h3).copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: SeType.bodyS.copyWith(color: SeColors.ink500)),
        ],
      ),
    );

Widget _historyRow(
        String title, String status, String when, int pay, bool done) =>
    SeCard(
      padding: const EdgeInsets.all(SeSpacing.x4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: done ? SeColors.successTint : SeColors.dangerTint,
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: Icon(done ? SeIcons.checkCircle : SeIcons.close,
                color: done ? SeColors.success : SeColors.danger, size: 20),
          ),
          const SizedBox(width: SeSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.title.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text('$status · $when',
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
          if (pay > 0)
            Text(Money.format(pay),
                style: SeType.tabular(SeType.title)
                    .copyWith(color: SeColors.success)),
        ],
      ),
    );

// ── Earnings ────────────────────────────────────────────────────────────────

Widget earningsPreview() => SePageScaffold(
      showBack: false,
      title: 'Earnings',
      subtitle: 'Your commission, trip by trip',
      capBottom: SeShellTabs(
        tabs: const ['Today', 'Week', 'Month'],
        selected: 1,
        onSelect: (_) {},
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: SeStatTile(
                    icon: SeIcons.trendUp,
                    label: 'Earned · Week',
                    value: 18640,
                    prefix: Money.symbol,
                  ),
                ),
                SizedBox(width: SeSpacing.x3),
                Expanded(
                  child: SeStatTile(
                    icon: SeIcons.bike,
                    label: 'Deliveries',
                    value: 29,
                    hue: SeColors.info,
                    tint: SeColors.infoSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SeSpacing.x5),
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This week', style: SeType.title),
                  const SizedBox(height: SeSpacing.x5),
                  const SeEarningsChart(
                    values: [1800, 2400, 3100, 2050, 4200, 3300, 1790],
                    labels: ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x5),
            const SeSectionTitle(title: 'Recent trips'),
            const SizedBox(height: SeSpacing.x3),
            _tripRow('Island Grill Morant Bay', '2 Aug', 620),
            const SizedBox(height: SeSpacing.x2),
            _tripRow('Fontana Pharmacy', '2 Aug', 480),
            const SizedBox(height: SeSpacing.x5),
            _payoutCard(),
          ],
        ),
      ),
    );

Widget _tripRow(String title, String when, int pay) => SeCard(
      padding: const EdgeInsets.all(SeSpacing.x4),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: SeColors.brandSoft,
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child:
                const Icon(SeIcons.bike, color: SeColors.brandInk, size: 18),
          ),
          const SizedBox(width: SeSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.title.copyWith(fontSize: 15)),
                Text(when,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
          Text(Money.format(pay),
              style: SeType.tabular(SeType.title)
                  .copyWith(color: SeColors.success)),
        ],
      ),
    );

Widget _payoutCard() => Container(
      padding: const EdgeInsets.all(SeSpacing.x5),
      decoration: BoxDecoration(
        color: SeColors.shell,
        borderRadius: SeRadius.all(SeRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(SeIcons.receipt,
                    color: SeColors.shellInk, size: 20),
              ),
              const SizedBox(width: SeSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('COMMISSION ACCRUED',
                        style: SeType.eyebrow.copyWith(
                            color:
                                SeColors.shellInk.withValues(alpha: 0.82))),
                    Text('Week',
                        style:
                            SeType.title.copyWith(color: SeColors.shellInk)),
                  ],
                ),
              ),
              Text(Money.format(18640),
                  style: SeType.tabular(SeType.h2)
                      .copyWith(color: SeColors.shellInk)),
            ],
          ),
          const SizedBox(height: SeSpacing.x3),
          Text(
            'Payouts are arranged by the ShipEast office — check with dispatch '
            'for your schedule.',
            style: SeType.bodyS
                .copyWith(color: SeColors.shellInk.withValues(alpha: 0.80)),
          ),
        ],
      ),
    );

// ── Profile ─────────────────────────────────────────────────────────────────

Widget profilePreview() => SePageScaffold(
      showBack: false,
      capTitle: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
            ),
            child: const Icon(SeIcons.userFill,
                size: 32, color: SeColors.shellInk),
          ),
          const SizedBox(width: SeSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Andre Campbell',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.h1
                        .copyWith(color: SeColors.shellInk, height: 1.15)),
                const SizedBox(height: 3),
                Text('Motorcycle · ShipEast Driver',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.bodyS.copyWith(
                        color: SeColors.shellInk.withValues(alpha: 0.76))),
              ],
            ),
          ),
        ],
      ),
      trailing: SeCapButton(icon: SeIcons.edit, onTap: () {}),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SeStat(
                    icon: SeIcons.star,
                    value: '4.9',
                    label: 'Rating',
                    hue: SeColors.star,
                  ),
                ),
                const SizedBox(width: SeSpacing.x3),
                const Expanded(
                  child: SeStat(
                    icon: SeIcons.bike,
                    value: '341',
                    label: 'Trips',
                    hue: SeColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SeSpacing.x4),
            SeRowGroup(
              children: [
                SeRow(
                    icon: SeIcons.phone,
                    label: 'Phone',
                    value: '876 445 9812',
                    onTap: () {}),
                SeRow(
                    icon: SeIcons.envelope,
                    label: 'Email',
                    value: 'andre@example.com',
                    onTap: () {}),
                SeRow(
                    icon: SeIcons.badge,
                    label: 'Licence',
                    value: 'DL-4471902',
                    onTap: () {}),
              ],
            ),
            const SizedBox(height: SeSpacing.x4),
            SeRowGroup(
              children: [
                SeRow(icon: SeIcons.bell, label: 'Notifications', onTap: () {}),
                SeRow(
                    icon: SeIcons.shield,
                    label: 'Privacy & Security',
                    onTap: () {}),
                SeRow(
                    icon: SeIcons.help, label: 'Help & Support', onTap: () {}),
                SeRow(
                    icon: SeIcons.info,
                    label: 'About ShipEast',
                    value: 'v${SeBrand.version}',
                    onTap: () {}),
              ],
            ),
            const SizedBox(height: SeSpacing.x4),
            SeButton(
              label: 'Sign out',
              icon: SeIcons.signOut,
              variant: SeButtonVariant.destructive,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

// ── Pending approval ────────────────────────────────────────────────────────

/// Mirrors [PendingApprovalScreen] in its default `pending` state.
///
/// The old mirror here had drifted badly — a different medallion, different
/// copy, different tracker steps. Per the rule at the top of this file, the
/// mirror was the thing that was wrong.
Widget pendingApprovalPreview() => SePageScaffold(
      showBack: false,
      title: 'Application submitted',
      subtitle: 'This screen updates the moment a decision is made — there is '
          'no need to reopen the app.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x6, SeSpacing.gutter, SeSpacing.x8),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: SeSpacing.x4, vertical: SeSpacing.x2),
              decoration: BoxDecoration(
                color: SeColors.warningSoft,
                borderRadius: SeRadius.pill,
                border: Border.all(
                    color: SeColors.warningInk.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(SeIcons.hourglass,
                      color: SeColors.warningInk, size: 16),
                  const SizedBox(width: SeSpacing.x2),
                  Text('Under review',
                      style: SeType.label.copyWith(color: SeColors.warningInk)),
                ],
              ),
            ),
          ),
          const SizedBox(height: SeSpacing.x5),
          const SeSectionTitle(title: 'Where you are'),
          const SeCard(
            padding: EdgeInsets.all(SeSpacing.x5),
            child: SeStepTracker(
              current: 1,
              steps: [
                SeStep('Application received',
                    caption: 'We have your registration details'),
                SeStep('Background check',
                    caption: 'Dispatch is reviewing your documents'),
                SeStep('Account activated',
                    caption: 'Start accepting deliveries'),
              ],
            ),
          ),
          const SizedBox(height: SeSpacing.x5),
          SeNotice.info('Most applications are reviewed within 24–48 hours.'),
          const SizedBox(height: SeSpacing.x8),
          SeButton(
            label: 'Sign out',
            variant: SeButtonVariant.ghost,
            onPressed: () {},
          ),
        ],
      ),
    );

// ── Delivery complete ───────────────────────────────────────────────────────

Widget deliveryDonePreview() => Scaffold(
      backgroundColor: SeColors.shell,
      body: Column(
        children: [
          const Spacer(),
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: SeColors.shell,
              borderRadius: SeRadius.sheetTop,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(SeSpacing.gutter,
                    SeSpacing.x5, SeSpacing.gutter, SeSpacing.x6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(SeIcons.checkCircle,
                          color: SeColors.shellInk, size: 42),
                    ),
                    const SizedBox(height: SeSpacing.x5),
                    Text('Delivery complete',
                        style: SeType.h1.copyWith(color: SeColors.shellInk)),
                    const SizedBox(height: SeSpacing.x2),
                    Text('Handed off to Kemar Brown. Nice work.',
                        textAlign: TextAlign.center,
                        style: SeType.body.copyWith(
                            color:
                                SeColors.shellInk.withValues(alpha: 0.88))),
                    const SizedBox(height: SeSpacing.x5),
                    Text('YOU EARNED',
                        style: SeType.eyebrow.copyWith(
                            color:
                                SeColors.shellInk.withValues(alpha: 0.80))),
                    Text(Money.format(620),
                        style: SeType.tabular(SeType.display)
                            .copyWith(color: SeColors.shellInk, fontSize: 40)),
                    const SizedBox(height: SeSpacing.x6),
                    Container(
                      width: double.infinity,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: SeColors.shellInk,
                        borderRadius: SeRadius.pill,
                      ),
                      child: Text('Back to dashboard',
                          style: SeType.jakarta(16, FontWeight.w600,
                              color: SeColors.shell)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
