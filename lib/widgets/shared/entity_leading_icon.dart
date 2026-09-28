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

/// A row's leading icon: a rounded square in a faint tint of
/// [colorScheme.primary] with [image] or [fallbackIcon] in [colorScheme.primary]
/// on top. Used for a device's class icon, a group's icon and the class-list
/// screen, so all three read as the same control.
///
/// [image] is assumed to be a single-colour glyph on a transparent
/// background: [ColorFilter.mode] with [BlendMode.srcIn] recolours every
/// opaque pixel to the tint and leaves the alpha untouched, which only looks
/// right for a glyph, not a photo.
///
/// While [image] is a network-backed [Image] whose first frame has not
/// decoded yet, the square shows [fallbackIcon] instead of sitting empty -
/// tracked by resolving its [ImageProvider] directly, since a bare [Widget]
/// gives no "has a frame" signal of its own.
class EntityLeadingIcon extends StatefulWidget {
  const EntityLeadingIcon({
    required this.size,
    required this.fallbackIcon,
    this.image,
    super.key,
  });

  final double size;
  final IconData fallbackIcon;
  final Widget? image;

  @override
  State<EntityLeadingIcon> createState() => _EntityLeadingIconState();
}

class _EntityLeadingIconState extends State<EntityLeadingIcon> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _hasFrame = false;

  ImageProvider? get _provider {
    final image = widget.image;
    return image is Image ? image.image : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant EntityLeadingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _hasFrame = false;
      _resolve();
    }
  }

  void _resolve() {
    _unlisten();
    final provider = _provider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((image, synchronousCall) {
      // A cached provider completes synchronously, inside didChangeDependencies
      // itself (before this build); setState there is redundant and would
      // just mark the element dirty a second time for the same frame.
      if (synchronousCall) {
        _hasFrame = true;
      } else {
        if (!mounted) return;
        setState(() => _hasFrame = true);
      }
    });
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unlisten() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    // No image, or one we can't track (not an Image - show it right away),
    // or an Image whose first frame has already landed.
    final showImage = widget.image != null && (_provider == null || _hasFrame);
    final size = scaler.scale(widget.size);
    // A faint tint of the ink behind the ink itself, the same colour the
    // navigation bar marks its selection with.
    final background = scheme.primary.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10);
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Padding(
        padding: EdgeInsets.all(scaler.scale(widget.size / 5)),
        child: showImage
            ? ColorFiltered(
                colorFilter: ColorFilter.mode(scheme.primary, BlendMode.srcIn),
                child: widget.image,
              )
            : Icon(widget.fallbackIcon, color: scheme.primary, size: size * 0.55),
      ),
    );
  }
}
