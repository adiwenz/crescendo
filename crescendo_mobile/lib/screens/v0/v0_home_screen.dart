import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import '../../ui/theme/app_theme.dart';
import 'v0_session_screen.dart';

class V0HomeScreen extends StatelessWidget {
  const V0HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Manually setting a dark-ish background or using AppBackground if available.
    // Assuming AppBackground is available and appropriate, but V0 might want a specific look.
    // For now, using Scaffold with a clean background color.
    
    final colors = AppThemeColors.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Container(
        decoration: BoxDecoration(
          gradient: colors.backgroundGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // Header Area
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // The text is the anchor
                    Padding(
                      padding: const EdgeInsets.only(right:40.0),
                      child: Text(
                        "Ballad",
                        style: GoogleFonts.baskervville(
                          textStyle: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 56),
                          fontWeight: FontWeight.bold, // Baskerville looks better normal usually
                          color: const Color(0xffcbc2e5), // Pastel purple from reference
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // The logo/swoosh, positioned relative to text
                    Positioned(
                      bottom: -45,
                      right: 40, // Offset to the side as requested
                      child: Opacity(
                        opacity: 0.8,
                        child: Image.asset(
                          'assets/ballad_logo_bg_removed.png',
                          height: 50, // Adjust size to fit under text nicely
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 90),
                // Spacer(),              
                // Cards
              _buildCard(
                context,
                title: "Match the Note",
                subtitle: "Match the note you hear",
                icon: Icons.music_note_rounded,
                color: colors.lavenderGlow,
              ),
              const SizedBox(height: 16),
              _buildCard(
                context,
                title: "Follow the Notes",
                subtitle: "follow the notes smoothly",
                icon: Icons.show_chart_rounded, // Visual looks like bars/chart
                color: colors.blueAccent,
              ),
              const SizedBox(height: 16),
              _buildCard(
                context,
                title: "Easy Slides",
                subtitle: "slide comfortably between pitches",
                icon: Icons.waves_rounded,
                color: colors.lavenderGlow,
              ),  
                Spacer(),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored Side Panel
            Container(
              width: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
              ),
              child: Center(
                child: Icon(icon, color: color, size: 32),
              ),
            ),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.baskervville(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF5D4E70), // Darker purple for readability
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8699),
                        fontFamily: 'Manrope',
                        height: 1.3,
                      ),
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
