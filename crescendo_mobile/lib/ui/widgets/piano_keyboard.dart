import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class PianoKeyboard extends StatelessWidget {
  final int startMidi;
  final int endMidi;
  final int? highlightedMidi;
  final ValueChanged<int> onKeyTap;
  final double keyHeight;

  const PianoKeyboard({
    super.key,
    required this.startMidi,
    required this.endMidi,
    required this.highlightedMidi,
    required this.onKeyTap,
    this.keyHeight = 36,
  });

  @override
  Widget build(BuildContext context) {
    final whiteKeys = _whiteKeys(startMidi, endMidi);
    final blackKeys = _blackKeys(startMidi, endMidi);
    return LayoutBuilder(
      builder: (context, constraints) {
        final blackWidth = constraints.maxWidth * 0.6;
        final blackHeight = keyHeight * 0.6;
        final whiteIndex = {
          for (var i = 0; i < whiteKeys.length; i++) whiteKeys[i]: i
        };

        final content = SizedBox(
          height: keyHeight * whiteKeys.length,
          child: Stack(
            children: [
              Column(
                children: whiteKeys
                    .map((midi) => _WhiteKey(
                          height: keyHeight,
                          highlighted: highlightedMidi == midi,
                          label: _noteLabel(midi),
                          onTap: () => onKeyTap(midi),
                        ))
                    .toList(),
              ),
              ...blackKeys.map((midi) {
                final upperWhite = midi + 1;
                final upperIndex = whiteIndex[upperWhite];
                if (upperIndex == null) return const SizedBox.shrink();
                final boundary = (upperIndex + 1) * keyHeight;
                final top = boundary - blackHeight / 2;
                return Positioned(
                  top: top,
                  right: 0,
                  width: blackWidth,
                  height: blackHeight,
                  child: _BlackKey(
                    highlighted: highlightedMidi == midi,
                    onTap: () => onKeyTap(midi),
                  ),
                );
              }),
            ],
          ),
        );

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: content,
        );
      },
    );
  }

  List<int> _whiteKeys(int start, int end) {
    final keys = <int>[];
    for (var midi = start; midi <= end; midi++) {
      if (_isWhite(midi)) keys.add(midi);
    }
    return keys.reversed.toList();
  }

  List<int> _blackKeys(int start, int end) {
    final keys = <int>[];
    for (var midi = start; midi <= end; midi++) {
      if (_isBlack(midi)) keys.add(midi);
    }
    return keys.reversed.toList();
  }

  bool _isWhite(int midi) {
    const white = {0, 2, 4, 5, 7, 9, 11};
    return white.contains(midi % 12);
  }

  bool _isBlack(int midi) {
    const black = {1, 3, 6, 8, 10};
    return black.contains(midi % 12);
  }

  String _noteLabel(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}

class _WhiteKey extends StatelessWidget {
  final double height;
  final bool highlighted;
  final String label;
  final VoidCallback onTap;

  const _WhiteKey({
    required this.height,
    required this.highlighted,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted ? BalladTheme.accentGold : Colors.white10;
    final fill = highlighted ? BalladTheme.accentGold.withOpacity(0.2) : Colors.white.withOpacity(0.05);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: fill,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
            bottom: BorderSide(color: borderColor, width: 1),
            right: BorderSide(color: borderColor, width: 1),
          ),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: BalladTheme.accentGold.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: highlighted ? BalladTheme.accentGold : BalladTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BlackKey extends StatelessWidget {
  final bool highlighted;
  final VoidCallback onTap;

  const _BlackKey({
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fill = highlighted ? BalladTheme.accentTeal : Colors.black54;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: highlighted ? BalladTheme.accentTeal.withOpacity(0.4) : Colors.black26,
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
