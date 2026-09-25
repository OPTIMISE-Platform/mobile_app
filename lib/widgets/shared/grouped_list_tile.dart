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
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

/// One row's slice of a grouped-list section surface.
///
/// A section (rows that belong together) sits on one card-tone surface with
/// rounded outer corners, but a long list stays lazily built: each row draws
/// only its own background, outer-corner rounding for [position] and inset
/// hairline, instead of one widget wrapping the whole section. [child] is
/// clipped to the row's shape so its ink response never bleeds past a
/// rounded corner into the next row.
class GroupedListTile extends StatelessWidget {
  const GroupedListTile({
    required this.position,
    required this.child,
    this.horizontalMargin = Spacing.lg,
    this.hairlineInset = insetButtonLeading,
    super.key,
  });

  final SlicePosition position;
  final Widget child;

  /// Horizontal distance from the page edge to the surface.
  final double horizontalMargin;

  /// Distance of the hairline's start from the row's left edge, matching
  /// where that row's own title starts. [ListTile]'s content padding (16) is
  /// shared by all three; they differ in what sits before the title.
  final double hairlineInset;

  /// A row with no leading widget: content padding only.
  static const double insetNoLeading = Spacing.lg;

  /// A row with a plain, non-interactive icon leading (intrinsic width 24,
  /// [ListTile]'s own default minimum), plus the horizontal title gap (16)
  /// on both sides of it.
  static const double insetIconLeading = Spacing.lg + 24 + Spacing.lg;

  /// A row with a tappable leading control sized to the platform's minimum
  /// touch target (48, `kMinInteractiveDimension`) - a [FavorizeButton]'s
  /// `IconButton` or a class/network avatar of the same size - plus the
  /// horizontal title gap on both sides of it.
  static const double insetButtonLeading =
      Spacing.lg + kMinInteractiveDimension + Spacing.lg;

  static const _cardRadius = Radius.circular(14); // theme.dart's CardThemeData

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.vertical(
      top: position.roundsTop ? _cardRadius : Radius.zero,
      bottom: position.roundsBottom ? _cardRadius : Radius.zero,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Material(
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (position.drawsHairline)
              Divider(
                height: 1,
                thickness: 1,
                indent: hairlineInset,
                color: scheme.outlineVariant,
              ),
          ],
        ),
      ),
    );
  }
}
