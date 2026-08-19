import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/breakpoints.dart';
import '../../data/models/sleep_session.dart';
import '../../data/session_repository.dart';
import 'sessions_providers.dart';
import 'widgets/disclaimer_footer.dart';
import 'widgets/empty_state.dart';
import 'widgets/session_card.dart';
import 'widgets/stale_data_banner.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giấc ngủ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => refreshSessions(ref),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(error: e),
          data: (result) {
            if (result.items.isEmpty) {
              return ListView(
                children: [
                  if (result.isStale) StaleDataBanner(cachedAt: result.cachedAt),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const EmptyState(
                      title: 'Chưa có đêm nào được ghi',
                      detail: 'Phiên xuất hiện sau khi cảm biến ghi được ít nhất '
                          '30 giây liên tục trên giường.',
                    ),
                  ),
                ],
              );
            }
            return _SessionList(result: result);
          },
        ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.result});

  final RepoResult<List<SleepSession>> result;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = Breakpoints.isCompact(width);
    final items = result.items;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (result.isStale)
          StaleDataBanner(cachedAt: result.cachedAt),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _SectionHeader(
            title: 'Những đêm gần đây',
            count: items.length,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: compact
              ? Column(
                  children: [
                    for (final s in items) ...[
                      SessionCard(
                        session: s,
                        onTap: () => context.push('/session/${s.id}'),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                )
              // Wrap rather than GridView: a grid needs a fixed cell height,
              // and a card's height depends on how many rows its metric tiles
              // reflow into. Any constant picked here would clip at some width.
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    final columns =
                        (constraints.maxWidth / 480).floor().clamp(2, 3);
                    final cardWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final s in items)
                          SizedBox(
                            width: cardWidth,
                            child: SessionCard(
                              session: s,
                              onTap: () => context.push('/session/${s.id}'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        const DisclaimerFooter(),
      ],
    );
  }
}

/// "Những đêm gần đây · 12" — the count is information, not decoration: it
/// tells the reader at a glance how much history the list holds.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    // An expired token is the one failure the user can fix themselves, so it
    // gets its own message and a way to act on it.
    final expired = error is DevTokenExpiredException;
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: EmptyState(
            title: expired
                ? 'Dev token hết hạn hoặc không hợp lệ'
                : 'Không đọc được dữ liệu',
            detail: expired
                ? 'Lấy token mới bằng POST /auth/login rồi dán vào cài đặt.'
                : '$error',
            action: FilledButton.icon(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Mở cài đặt'),
            ),
          ),
        ),
      ],
    );
  }
}