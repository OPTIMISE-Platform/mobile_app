/*
 * Copyright 2026 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import 'package:flutter/material.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/value_change_style.dart';

export 'package:mobile_app/shared/value_change_style.dart';

/// Shows [child], the rendering of [value], and marks a change of [value]
/// with [style] (default: the user's setting). The first value, or one after
/// none, is not a change.
class ValueChange extends StatefulWidget {
  final Object? value;
  final ValueChangeStyle style;
  final Widget child;

  ValueChange({super.key, required this.value, ValueChangeStyle? style, required this.child})
      : style = style ?? Settings.getValueChangeStyle();

  @override
  State<ValueChange> createState() => _ValueChangeState();
}

class _ValueChangeState extends State<ValueChange> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _durationOf(widget.style))..value = 1;

  /// 1 when the value rose, -1 when it fell, 0 when that cannot be told.
  int _direction = 0;

  static Duration _durationOf(ValueChangeStyle style) => switch (style) {
        ValueChangeStyle.arrow => const Duration(seconds: 3),
        ValueChangeStyle.slide => const Duration(milliseconds: 350),
        _ => const Duration(milliseconds: 1500),
      };

  @override
  void didUpdateWidget(ValueChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _durationOf(widget.style);
    final before = oldWidget.value, after = widget.value;
    if (before == null || after == null || before == after) return;
    _direction = before is num && after is num ? (after > before ? 1 : -1) : 0;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Strong at the change, gone at the end.
    double fade() => 1 - Curves.easeOut.transform(_controller.value);
    switch (widget.style) {
      case ValueChangeStyle.flash:
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.35 * fade()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          ),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: widget.child),
        );
      case ValueChangeStyle.arrow:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: _direction == 0 ? 0 : fade(),
                child: Icon(_direction < 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 16, color: scheme.primary),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(child: widget.child),
          ],
        );
      case ValueChangeStyle.slide:
        return ClipRect(
          child: AnimatedSwitcher(
            duration: _durationOf(ValueChangeStyle.slide),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey(widget.value);
              final from = Offset(0, (incoming ? 0.6 : -0.6) * (_direction == 0 ? 1 : _direction));
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: from, end: Offset.zero).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey(widget.value), child: widget.child),
          ),
        );
    }
  }
}
