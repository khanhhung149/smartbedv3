import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../sharing/models/pending_invite_out.dart';
import '../sharing/providers/sharing_providers.dart';
import '../sharing/providers/sharing_repository_provider.dart';
import '../../l10n/app_localizations.dart';

// PENDING INVITES section tile — accept/decline an incoming device share invite.
// Uses Riverpod ref to call repo and invalidate providers after action.

class PendingInviteTile extends ConsumerStatefulWidget {
  const PendingInviteTile({super.key, required this.invite});
  final PendingInviteOut invite;

  @override
  ConsumerState<PendingInviteTile> createState() => _PendingInviteTileState();
}

class _PendingInviteTileState extends ConsumerState<PendingInviteTile> {
  bool _busy = false;

  Future<void> _accept() async {
    final repo = ref.read(sharingRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await repo.acceptInvite(widget.invite.shareId);
      ref.invalidate(pendingInvitesProvider);
      ref.invalidate(mySharedDevicesProvider);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final repo = ref.read(sharingRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await repo.deleteShare(widget.invite.shareId);
      ref.invalidate(pendingInvitesProvider);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invite;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.defaultBr,
        border: Border.all(
          color: AppColors.primaryContainer.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mail_outline,
                  color: AppColors.primaryContainer, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inv.deviceName,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.base,
                      fontWeight: AppFontWeight.semiBold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.inviteFrom(inv.ownerEmail),
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xs,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _decline,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  side: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text(AppLocalizations.of(context)!.decline,
                    style: GoogleFonts.inter(color: AppColors.onSurface)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _accept,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimaryContainer),
                      )
                    : Text(AppLocalizations.of(context)!.accept,
                        style: GoogleFonts.inter(
                            fontWeight: AppFontWeight.semiBold)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
