import 'package:flutter/material.dart';

class PianoWidget extends StatelessWidget {
  final List<String> keys;
  final void Function(String note) onTap;

  const PianoWidget({super.key, required this.keys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keys
          .map((n) => InkWell(
                onTap: () => onTap(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: Text(n, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ))
          .toList(),
    );
  }
}
