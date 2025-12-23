import 'package:flutter/material.dart';
import 'training_timeline_card.dart';

class TrainingTimeline extends StatelessWidget {
  final List<TrainingTimelineCard> cards;

  const TrainingTimeline({
    super.key,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    const cardSpacing = 16.0;
    const circleSize = 24.0;
    const lineTopOffset = 12.0;
    const lineBottomOffset = 12.0;

    return Stack(
      children: [
        // Vertical connecting line (continuous, behind circles)
        Positioned(
          left: 12,
          top: lineTopOffset + circleSize / 2,
          bottom: lineBottomOffset + circleSize / 2,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: const Color(0xFFE6E1DC),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        // Cards with status circles
        Column(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status circle area (aligned with line)
                  SizedBox(
                    width: 28,
                    child: _StatusCircle(
                      status: _getStatusForCard(cards[i]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Card
                  Expanded(child: cards[i]),
                ],
              ),
              if (i < cards.length - 1) const SizedBox(height: cardSpacing),
            ],
          ],
        ),
      ],
    );
  }

  TrainingStatus _getStatusForCard(TrainingTimelineCard card) {
    return card.status;
  }
}

class _StatusCircle extends StatelessWidget {
  final TrainingStatus status;

  const _StatusCircle({
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    const size = 24.0;

    switch (status) {
      case TrainingStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF8FC9A8),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            size: 16,
            color: Colors.white,
          ),
        );
      case TrainingStatus.inProgress:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Color(0xFF7FD1B9),
            shape: BoxShape.circle,
          ),
        );
      case TrainingStatus.next:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFD1D1D6),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.add,
            size: 16,
            color: Color(0xFFD1D1D6),
          ),
        );
    }
  }
}
