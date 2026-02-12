
import 'package:flutter/material.dart';
import '../../theme/ballad_theme.dart';

class BalladScaffold extends StatelessWidget {
  const BalladScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
    this.actions,
    this.showStars = true,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24.0),
  });

  final String title;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;
  final bool showStars;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _BalladBackground(),

        if (showStars) const _StarField(),

        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            leading: showBack
                ? IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              title,
              style: BalladTheme.titleMedium,
            ),
            actions: actions,
          ),
          body: SafeArea(
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
          floatingActionButton: floatingActionButton,
        ),
      ],
    );
  }
}

class _BalladBackground extends StatelessWidget {
  const _BalladBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BalladTheme.bgTop,
            BalladTheme.bgMid,
            BalladTheme.bgBottom,
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
    );
  }
}

class _StarField extends StatelessWidget {
  const _StarField();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.35,
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/glow_stars.png'), // Using glow_stars.png
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
