import 'package:flutter/material.dart';
import 'balance_bar_row.dart';

class DailyBalanceCard extends StatelessWidget {
  final List<BalanceBarData> bars;

  const DailyBalanceCard({
    super.key,
    required this.bars,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFD4D0CA),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Balance',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF7A7A7A),
            ),
          ),
          const SizedBox(height: 12),
          ...bars.map((bar) => Padding(
                padding: EdgeInsets.only(
                  bottom: bar == bars.last ? 0 : 10,
                ),
                child: BalanceBarRow(
                  label: bar.label,
                  value: bar.value,
                  icon: bar.icon,
                  accentColor: bar.accentColor,
                ),
              )),
        ],
      ),
    );
  }
}

class BalanceBarData {
  final String label;
  final double value; // 0.0 to 1.0
  final IconData icon;
  final Color accentColor;

  BalanceBarData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });
}

