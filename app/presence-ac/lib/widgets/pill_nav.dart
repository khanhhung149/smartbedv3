import 'package:flutter/material.dart';

import '../theme.dart';

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Thanh nav dạng viên thuốc nổi — item đang chọn là pill đen có chữ, các item khác
/// chỉ có icon. Mẫu lấy từ shot "Travia" (Layo, Dribbble).
///
/// Nổi trên nội dung nên mọi màn phải chừa padding dưới (~120) kẻo bị che.
class PillNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<NavItem> items;

  const PillNav({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (i) {
              final active = i == index;
              return Expanded(
                flex: active ? 3 : 2, // pill đang chọn rộng hơn để chứa chữ
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? AppTheme.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].icon,
                            size: 19,
                            color: active ? Colors.white : AppTheme.inkSoft),
                        // Chỉ item active mới hiện chữ — 4 nhãn cùng lúc sẽ chật.
                        if (active) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              items[i].label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
