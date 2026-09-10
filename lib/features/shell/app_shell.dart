import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import '../inbox/inbox_providers.dart';

/// The five places worth a permanent tab.
///
/// The web app is ~30 screens at desk density and porting all of it is how a
/// mobile app becomes unfriendly. These five are the ones that are genuinely
/// *better* on a phone; everything else lives one tap deeper under More.
class ShellTab {
  const ShellTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  static const tabs = [
    ShellTab(
      path: '/home',
      label: 'Home',
      icon: LucideIcons.house,
      activeIcon: LucideIcons.house,
    ),
    ShellTab(
      path: '/tasks',
      label: 'Tasks',
      icon: LucideIcons.listTodo,
      activeIcon: LucideIcons.listTodo,
    ),
    ShellTab(
      path: '/triage',
      label: 'Triage',
      icon: LucideIcons.inbox,
      activeIcon: LucideIcons.inbox,
    ),
    ShellTab(
      path: '/inbox',
      label: 'Inbox',
      icon: LucideIcons.bell,
      activeIcon: LucideIcons.bell,
    ),
    ShellTab(
      path: '/more',
      label: 'More',
      icon: LucideIcons.menu,
      activeIcon: LucideIcons.menu,
    ),
  ];
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: context.colors.background,
        body: navigationShell,
        bottomNavigationBar: _BottomBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            // Tapping the tab you are already on pops back to its root, which
            // is the behaviour people expect from every other app.
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      );
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Polled, not pushed: there is no APNs/FCM channel on the server, so the
    // badge is refreshed on a timer the way the web app refreshes its own.
    final unread = ref.watch(unreadCountProvider).value ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < ShellTab.tabs.length; i++)
                Expanded(
                  child: _BarItem(
                    tab: ShellTab.tabs[i],
                    selected: i == currentIndex,
                    badge: ShellTab.tabs[i].path == '/inbox' ? unread : 0,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final ShellTab tab;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? context.colors.primary : context.colors.mutedForeground;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(selected ? tab.activeIcon : tab.icon, size: 21, color: color),
              if (badge > 0)
                Positioned(
                  right: -9,
                  top: -6,
                  child: CountBadge(badge, emphasised: true),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tab.label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.1,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
