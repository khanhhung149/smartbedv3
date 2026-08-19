import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'providers/provisioning_provider.dart';

// 4-step provisioning progress checklist.
// Maps ProvisioningState to done/active/pending status for each step.

enum BlePairingStepStatus { done, active, pending }

class BlePairingProgressChecklist extends StatelessWidget {
  const BlePairingProgressChecklist({super.key, required this.state});
  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final steps = _resolveSteps(state);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepItem(label: steps[i].label, status: steps[i].status),
            if (i < steps.length - 1) const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  List<({String label, BlePairingStepStatus status})> _resolveSteps(
      ProvisioningState s) {
    final isDone = s is ProvisioningSuccess;
    final isFailed = s is ProvisioningFailure;

    bool wifiDone = isDone ||
        s is ProvisioningConnectingWifi ||
        s is ProvisioningConnectingMqtt;
    bool wifiActive = s is ProvisioningFetchingDeviceId ||
        s is ProvisioningSelected ||
        s is ProvisioningPairedWithBackend;
    bool connectingActive = s is ProvisioningConnectingWifi;
    bool mqttActive = s is ProvisioningConnectingMqtt;
    bool mqttDone = isDone;
    final finalizingDone = isDone;

    if (isFailed) {
      wifiDone = false;
      wifiActive = false;
    }

    return [
      (
        label: 'Saved WiFi credentials',
        status: wifiDone
            ? BlePairingStepStatus.done
            : (wifiActive
                ? BlePairingStepStatus.active
                : BlePairingStepStatus.done),
      ),
      (
        label: 'Connecting to WiFi',
        status: connectingActive
            ? BlePairingStepStatus.active
            : (wifiDone || mqttActive || mqttDone
                ? BlePairingStepStatus.done
                : BlePairingStepStatus.pending),
      ),
      (
        label: 'Connecting to server',
        status: mqttActive
            ? BlePairingStepStatus.active
            : (mqttDone
                ? BlePairingStepStatus.done
                : BlePairingStepStatus.pending),
      ),
      (
        label: 'Finalizing',
        status: finalizingDone
            ? BlePairingStepStatus.done
            : BlePairingStepStatus.pending,
      ),
    ];
  }
}

// ── Step item ─────────────────────────────────────────────────────────────────

class _StepItem extends StatelessWidget {
  const _StepItem({required this.label, required this.status});
  final String label;
  final BlePairingStepStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepIcon(status: status),
        const SizedBox(width: 16),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: AppTextSize.lg,
            fontWeight: AppFontWeight.medium,
            color: switch (status) {
              BlePairingStepStatus.done => AppColors.onSurface,
              BlePairingStepStatus.active => AppColors.primaryContainer,
              BlePairingStepStatus.pending =>
                AppColors.onSurface.withValues(alpha: 0.4),
            },
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ── Step icon ─────────────────────────────────────────────────────────────────

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.status});
  final BlePairingStepStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      BlePairingStepStatus.done => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check,
              color: AppColors.primaryContainer, size: 18),
        ),
      BlePairingStepStatus.active => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryContainer, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D5EE7DF),
                blurRadius: 12,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      BlePairingStepStatus.pending => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: AppColors.outlineVariant, width: 2),
          ),
        ),
    };
  }
}
