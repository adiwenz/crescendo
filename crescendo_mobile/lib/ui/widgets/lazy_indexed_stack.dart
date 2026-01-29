import 'package:flutter/material.dart';

/// An IndexedStack that builds its children lazily.
/// 
/// Standard [IndexedStack] builds all children immediately, which can cause
/// performance issues during startup if the children are heavy.
/// This widget only builds the currently active child and keeps previously
/// visited children alive.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final AlignmentGeometry alignment;
  final TextDirection? textDirection;
  final StackFit sizing;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = AlignmentDirectional.topStart,
    this.textDirection,
    this.sizing = StackFit.loose,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late List<bool> _activated;

  @override
  void initState() {
    super.initState();
    _activated = List<bool>.filled(widget.children.length, false);
    _activateIndex(widget.index);
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.length != _activated.length) {
      // Rebuild activated list if children count changed (preserving what we can)
      _activated = List<bool>.filled(widget.children.length, false);
    }
    _activateIndex(widget.index);
  }

  void _activateIndex(int index) {
    if (index >= 0 && index < _activated.length) {
      _activated[index] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      alignment: widget.alignment,
      textDirection: widget.textDirection,
      sizing: widget.sizing,
      children: List.generate(widget.children.length, (i) {
        if (_activated[i]) {
          return widget.children[i];
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }
}
