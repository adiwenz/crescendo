import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';
import 'v0_session_screen.dart';

class V0HomeScreen extends StatelessWidget {
  const V0HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Retro off-white/cream paper background
    const backgroundColor = Color(0xFFF9F7F2);
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Bottom Retro Stripes Decoration
          Positioned(
            bottom: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(400, 600), // Increased container size for safety
              painter: _RetroStripesPainter(),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  
                  // Header Title
                  Text(
                    "BALLAD",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D2A32), // Dark, almost black, soft ink
                      letterSpacing: -1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Exercise Cards
                  _buildExerciseCard(
                    context,
                    title: "Match the Note",
                    subtitle: "Match the note you hear",
                    icon: Icons.music_note_rounded,
                    accentColor: const Color(0xFF6B9080), // Muted Green
                    onTap: () {
                      // Todo: Navigate to exercise
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildExerciseCard(
                    context,
                    title: "Follow the Notes",
                    subtitle: "Follow the notes smoothly",
                    icon: Icons.show_chart_rounded,
                    accentColor: const Color(0xFFE9C46A), // Amber/Orange
                    onTap: () {
                       // Todo: Navigate to exercise
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildExerciseCard(
                    context,
                    title: "Easy Slides",
                    subtitle: "Slide comfortably between pitches",
                    icon: Icons.waves_rounded,
                    accentColor: const Color(0xFF2A9D8F), // Teal
                    onTap: () {
                       // Todo: Navigate to exercise
                    },
                  ),
                  
                  const Spacer(),
                  
                  // Progress Bar Section
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today: 3 exercises · ~6 min",
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF5D5A60),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildProgressSegment(const Color(0xFF6B9080))), // Green
                            const SizedBox(width: 4),
                            Expanded(child: _buildProgressSegment(const Color(0xFFE9C46A))), // Amber
                            const SizedBox(width: 4),
                            Expanded(child: _buildProgressSegment(const Color(0xFF2A9D8F))), // Teal
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSegment(Color color) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: color.withOpacity(0.3), // Unfilled state
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: 0.0, // Progress is 0 for now
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100, // Fixed height for visual consistency
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08), // Softer shadow
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Left Accent Stripe
            Container(
              width: 8,
              color: accentColor,
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: accentColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Texts
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2D2A32),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: const Color(0xFF8E8699),
                              height: 1.2,
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
                      color: Colors.grey.withOpacity(0.4),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetroStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    
    // Stripe colors inspired by the retro palette
    final colors = [
      const Color(0xFF2A9D8F), // Teal
      const Color(0xFFE9C46A), // Amber
      const Color(0xFFF4A261), // Orange
      const Color(0xFF6B9080), // Muted Green
    ];
    
    // Made stripes thicker for visibility
    const double stripeWidth = 60.0;
    
    // Draw diagonal stripes from bottom-right corner
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.rotate(-0.5); // Slight rotation
    
    for (int i = 0; i < colors.length; i++) {
      paint.color = colors[i].withOpacity(0.8);
      // Determine offset
      double offset = i * stripeWidth;
      
      // Draw a rectangle for the stripe
      // Extending far up (-1000) so the top edge is off-screen
      canvas.drawRect(
        Rect.fromLTWH(-400 + offset, -1000, stripeWidth, 2000),
        paint,
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



