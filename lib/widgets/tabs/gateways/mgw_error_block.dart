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
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/theme.dart';

/// Readable text for a failure from the gateway services.
String describeMgwError(Object error) {
  if (error is Failure) {
    final detail = error.detailedMessage.trim();
    final text = detail.isEmpty ? error.errorCode.name : detail;
    return error.statusCode == null ? text : "$text (HTTP ${error.statusCode})";
  }
  if (error is MgwSessionException) return error.message;
  return error.toString();
}

/// A failure shown on the page itself: what went wrong, what the gateway said
/// and, where one is known, what to do about it.
class MgwErrorBlock extends StatelessWidget {
  const MgwErrorBlock({
    required this.title,
    this.message,
    this.hint,
    this.margin = const EdgeInsets.symmetric(horizontal: Spacing.lg),
    super.key,
  });

  final String title;
  final String? message;
  final String? hint;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.appColors.warnInk;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: ink),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(color: ink)),
                    if (message != null && message!.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(message!, style: theme.textTheme.bodyMedium),
                    ],
                    if (hint != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(hint!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
