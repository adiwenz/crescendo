---
name: crescendo-theme-first-ui-builder
description: Helps with building Flutter UI code that matches Crescendo’s visual theme.
---
## Goal
When writing Flutter UI code, always match Crescendo’s visual theme:
calm, modern, Apple-like, soft gradients, gentle depth, minimal chrome,
rounded shapes, subtle micro-animations.

## Operating Rules
1. Consistency first: always use theme tokens. No ad-hoc styling.
2. White space is a feature: fewer elements, generous padding.
3. No harsh borders: prefer translucent fills and soft shadows.
4. Micro-animations only: fade + slight translate (2–6px).
5. Accessibility first: respect Reduce Motion and readable contrast.
6. Copy hierarchy: short titles, breathable body, anchored CTA.
7. Refer to styles.dart and app_theme.dartfor the theme.

## Theme Tokens
- AppColors: backgroundGradient, surface, surfaceElevated, textPrimary, textSecondary, accent
- AppRadius: r12, r16, r20, r28
- AppSpace: s8, s12, s16, s20, s24, s32
- AppText: title, headline, body, caption, button
- AppMotion: 180–420ms, easeOutCubic / easeInOutCubic

## Preferred Patterns
- Subtle vertical gradients (lavender → blue)
- Rounded glass cards (blur + low opacity)
- Pill CTAs, no loud shadows
- Abstract pitch lines / arcs for visuals

## Micro-Animation Recipe
- Entry: opacity 0→1, translateY 6→0, 260–420ms
- Idle: very slow pulse or shimmer (3–6s)
- Disable idle animations when Reduce Motion is enabled

## Code Expectations
- Extract reusable widgets
- Use ThemeExtension for tokens
- SafeArea + consistent padding
- CTA pinned to bottom

## Defaults
- Accent: #8055e3
- Gradient: #dfbdfe → #badbfe
- Radius: 24
- Button height: 52–56
- Max width: 420

## Don’t
- No bright scoring colors
- No dense text blocks