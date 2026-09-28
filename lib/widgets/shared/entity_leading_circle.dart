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

/// A row's leading avatar: a tonal circle in [colorScheme.primaryContainer]
/// with [image] or [fallbackIcon] tinted [colorScheme.onPrimaryContainer] on
/// top. Used for a device's class icon, a group's icon and the class-list
/// screen, so all three read as the same control.
///
/// [image] is assumed to be a single-colour glyph on a transparent
/// background: [ColorFilter.mode] with [BlendMode.srcIn] recolours every
/// opaque pixel to the tint and leaves the alpha untouched, which only looks
/// right for a glyph, not a photo.
///
/// While [image] is a network-backed [Image] whose first frame has not
/// decoded yet, the circle shows [fallbackIcon] instead of sitting empty -
/// tracked by resolving its [ImageProvider] directly, since a bare [Widget]
/// gives no "has a frame" signal of its own.
class EntityLeadingCircle extends StatefulWidget {
  const EntityLeadingCircle({
    required this.size,
    required this.fallbackIcon,
    this.image,
    super.key,
  });

  final double size;
  final IconData fallbackIcon;
  final Widget? image;

  @override
  State<EntityLeadingCircle> createState() => _EntityLeadingCircleState();
}

class _EntityLeadingCircleState extends State<EntityLeadingCircle> {
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
  void didUpdateWidget(covariant EntityLeadingCircle oldWidget) {
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
    return Container(
      height: scaler.scale(widget.size),
      width: scaler.scale(widget.size),
      decoration:
          BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(scaler.scale(widget.size / 6)),
        child: showImage
            ? ColorFiltered(
                colorFilter:
                    ColorFilter.mode(scheme.onPrimaryContainer, BlendMode.srcIn),
                child: widget.image,
              )
            : Icon(widget.fallbackIcon, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
