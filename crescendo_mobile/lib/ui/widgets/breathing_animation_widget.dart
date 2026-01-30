import 'package:flutter/material.dart';
import '../../controllers/breathing_controller.dart';
import '../../design/app_text.dart';

/// Reusable breathing animation widget with circular visual and countdown
class BreathingAnimationWidget extends StatefulWidget {
  final BreathingController controller;
  final double baseSize;
  final Color primaryColor;
  final Color secondaryColor;
  final TextStyle? countdownTextStyle;
  final TextStyle? phaseTextStyle;

  const BreathingAnimationWidget({
    super.key,
    required this.controller,
    this.baseSize = 200.0,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.purple,
    this.countdownTextStyle,
    this.phaseTextStyle,
  });

  @override
  State<BreathingAnimationWidget> createState() => _BreathingAnimationWidgetState();
}

class _BreathingAnimationWidgetState extends State<BreathingAnimationWidget> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circle with countdown (only shows during exercise, not pre-roll)
          SizedBox(
            width: widget.baseSize * 2, // Allow space for expansion
            height: widget.baseSize * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated breathing circle
                AnimatedBuilder(
                  animation: widget.controller.scaleAnimation,
                  builder: (context, child) {
                    final scale = widget.controller.scaleAnimation.value;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: widget.baseSize,
                        height: widget.baseSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.primaryColor,
                        ),
                      ),
                    );
                  },
                ),

                // Countdown number (center) - ONLY during exercise, NOT during pre-roll
                ValueListenableBuilder<int>(
                  valueListenable: widget.controller.countdown,
                  builder: (context, count, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: widget.controller.isPreRoll,
                      builder: (context, isPreRoll, _) {
                        // Don't show countdown inside circle during pre-roll
                        if (isPreRoll) {
                          return const SizedBox.shrink();
                        }
                        
                        return Text(
                          count.toString(),
                          style: widget.countdownTextStyle ?? AppText.countdownNumber,
                        );
                      },
                    );
                  },
                ),

                // Cycle indicator (top, optional)
                if (widget.controller.repeatCount > 1)
                  Positioned(
                    top: 20,
                    child: ValueListenableBuilder<int>(
                      valueListenable: widget.controller.currentCycle,
                      builder: (context, cycle, child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: widget.controller.isPreRoll,
                          builder: (context, isPreRoll, _) {
                            if (isPreRoll) return const SizedBox.shrink();
                            
                            return Text(
                              'Cycle ${cycle + 1} / ${widget.controller.repeatCount}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Manrope',
                                color: Colors.white70,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Gap between circle and label
          const SizedBox(height: 24),

          // Phase label OR pre-roll countdown (below circle)
          ValueListenableBuilder<String>(
            valueListenable: widget.controller.currentPhaseName,
            builder: (context, phaseName, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.controller.isPreRoll,
                builder: (context, isPreRoll, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: widget.controller.countdown,
                    builder: (context, count, _) {
                      // During pre-roll: show countdown number below circle
                      if (isPreRoll) {
                        return Text(
                          count.toString(),
                          style: widget.phaseTextStyle ?? AppText.phaseLabel,
                        );
                      }
                      
                      // During exercise: show phase name below circle
                      if (phaseName.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Text(
                        phaseName,
                        style: widget.phaseTextStyle ?? AppText.phaseLabel,
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
