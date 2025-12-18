import 'package:flutter/material.dart';

class TuningMeter extends StatelessWidget {
  final double cents; // expected -50..+50

  const TuningMeter({super.key, required this.cents});

  @override
  Widget build(BuildContext context) {
    final clamped = cents.clamp(-50.0, 50.0);
    final pct = (clamped + 50) / 100; // 0..1
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: const [
                Expanded(child: SizedBox()),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final x = constraints.maxWidth * pct;
              return Stack(
                children: [
                  Positioned(
                    left: x - 6,
                    top: 4,
                    child: Container(
                      width: 12,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Center(
            child: Container(
              width: 2,
              color: Colors.black26,
            ),
          ),
        ],
      ),
    );
  }
}
