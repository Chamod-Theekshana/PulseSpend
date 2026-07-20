import 'package:flutter/material.dart';
import 'app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/socket_service.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n_ext.dart';
import '../../providers/connectivity_provider.dart';

/// A slim, animated status pill overlaid at the top of the app. It appears
/// while the realtime socket is reconnecting and briefly confirms recovery,
/// so a dropped connection never looks like a silent freeze (Sections 1 & 10).
class ConnectivityBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectivityBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool _showBackOnline = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<SocketStatus>(socketStatusProvider, (prev, next) {
      // Confirm recovery briefly when we transition back to connected.
      if (prev == SocketStatus.reconnecting && next == SocketStatus.connected) {
        setState(() => _showBackOnline = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showBackOnline = false);
        });
      }
    });

    final status = ref.watch(socketStatusProvider);
    final isReconnecting = status == SocketStatus.reconnecting;
    final show = isReconnecting || _showBackOnline;

    final l = context.l10n;
    final Color bg = isReconnecting ? AppColors.warning : AppColors.income;
    final String label = isReconnecting ? l.statusReconnecting : l.statusBackOnline;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SafeArea(
              bottom: false,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                offset: show ? Offset.zero : const Offset(0, -2),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: show ? 1 : 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isReconnecting)
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: AppLoader(size: 13, color: Colors.white),
                            )
                          else
                            const Icon(Icons.check_circle, color: Colors.white, size: 15),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
