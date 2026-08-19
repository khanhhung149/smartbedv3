import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';
import '../sharing/models/share_out.dart';

// Sharing section — list of current shares + invite button.
// onRevoke receives shareId; onInvite opens invite sheet.

class DeviceDetailSharingCard extends StatelessWidget {
  const DeviceDetailSharingCard({
    super.key,
    required this.sharesAsync,
    required this.onInvite,
    required this.onRevoke,
  });

  final AsyncValue<List<ShareOut>> sharesAsync;
  final VoidCallback onInvite;
  final ValueChanged<String> onRevoke;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sharing',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.medium,
                color: AppColors.onSurface)),
        const SizedBox(height: 16),
        sharesAsync.when(
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(
                color: AppColors.primaryContainer, strokeWidth: 2),
          )),
          error: (e, _) => Text(e.toString(),
              style: GoogleFonts.inter(
                  color: AppColors.error, fontSize: AppTextSize.sm)),
          data: (shares) => Column(
            children: [
              ...shares.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ShareRow(
                        share: s, onRevoke: () => onRevoke(s.id)),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
        PrimaryButton(
          label: 'Invite family member',
          onPressed: onInvite,
        ),
      ],
    );
  }
}

// ── Share row ─────────────────────────────────────────────────────────────────

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.onRevoke});
  final ShareOut share;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person,
              color: AppColors.onSurfaceVariant, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(share.invitedEmail,
                    style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.onSurface)),
                const SizedBox(height: 2),
                Text(share.accepted ? 'Accepted' : 'Pending',
                    style: GoogleFonts.inter(
                        fontSize: AppTextSize.xs,
                        color: share.accepted
                            ? AppColors.primaryContainer
                            : AppColors.onSurfaceVariant)),
              ]),
        ),
        TextButton(
          onPressed: onRevoke,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          child: Text(share.accepted ? 'Revoke' : 'Cancel',
              style: GoogleFonts.inter(
                  fontSize: AppTextSize.sm,
                  fontWeight: AppFontWeight.medium)),
        ),
      ]),
    );
  }
}
