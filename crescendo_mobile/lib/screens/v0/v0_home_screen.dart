import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';
import 'v0_session_screen.dart';

class V0HomeScreen extends StatelessWidget {
  const V0HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Music-Tech Component Styles
    final Color primaryIndigo = const Color(0xFF3F51B5);
    final Color deepViolet = const Color(0xFF673AB7);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Off-white tech background
      body: Stack(
        children: [
          // 2. Background Gradient & Subtle Wash
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFFFFF), // Pure White start
                    Color(0xFFE8EAF6), // Pale Indigo end
                  ],
                ),
              ),
            ),
          ),
          // Subtle Diagonal Wash
          Positioned(
            top: -200,
            right: -100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    deepViolet.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // 3. Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Ballad",
                        style: GoogleFonts.manrope(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A2E), // Almost black indigo
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Vocal Calibration System",
                        style: GoogleFonts.robotoMono( // Tech font for subtitle
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.indigo.withOpacity(0.6),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // 4. Exercise Cards List
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
                    children: [
                      _TechExerciseCard(
                        title: "Pitch Matching",
                        subtitle: "Frequency alignment training",
                        icon: Icons.graphic_eq,
                        gradientColors: [primaryIndigo, deepViolet],
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      _TechExerciseCard(
                        title: "Smooth Slides",
                        subtitle: "Continuous glissando control",
                        icon: Icons.waves,
                        gradientColors: [deepViolet, const Color(0xFF9C27B0)],
                        onTap: () {},
                      ),
                      const SizedBox(height: 16),
                      _TechExerciseCard(
                        title: "Vowel Tuning",
                        subtitle: "Formant resonance shaping",
                        icon: Icons.record_voice_over,
                        gradientColors: [const Color(0xFF2196F3), primaryIndigo],
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                // 5. Bottom Progress Section (Docked)
                _TechBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechExerciseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _TechExerciseCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.indigo.shade100.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              // Vertical Gradient Accent
              Container(
                width: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradientColors,
                  ),
                ),
              ),
              
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Row(
                    children: [
                      // Gradient Icon
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ).createShader(bounds),
                        child: Icon(
                          icon,
                          color: Colors.white, // Required for ShaderMask
                          size: 28,
                        ),
                      ),
                      
                      const SizedBox(width: 20),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF7986CB), // Muted Indigo
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      
                      // Chevron
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.withOpacity(0.3),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechBottomBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40), // Extra bottom padding for safe area
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: Colors.indigo.shade50,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Brief Session Info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "TODAY'S SESSION",
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.withOpacity(0.4),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "6 min",
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3F51B5),
                ),
              ),
            ],
          ),
          
          const SizedBox(width: 24),
          
          // Waveform/Beats Progress Visualization
          Expanded(
            child: SizedBox(
              height: 30,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(12, (index) {
                  // Simulate specific waveform heights
                  // 3 filled (complete), rest empty
                  final bool isCompleted = index < 3;
                  final double heightFactor = 0.4 + (index % 3) * 0.2 + (index % 2) * 0.1; 
                  
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: FractionallySizedBox(
                        heightFactor: heightFactor,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isCompleted 
                                ? const Color(0xFF3F51B5) // Indigo Filled
                                : const Color(0xFFE8EAF6), // Empty Pale
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
