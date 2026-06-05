import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_constants.dart';

// ─── Global Warm Charcoal Palette ────────────────────────────────────────────
// Dark mode: near-black charcoal, amber/cream accents.
// Light mode: warm off-white paper, deep charcoal text.

// ── Dark backgrounds ──────────────────────────────────────────────────────────
/// Scaffold background — near-black charcoal
const leatherBrown = Color(0xFF16140F);

/// Card / container surface
const coverDark = Color(0xFF1E1C16);

/// Elevated surfaces — sheets, dialogs
const coverMid = Color(0xFF28251C);

/// Higher elevation
const coverHigh = Color(0xFF332F23);

/// Dividers, card borders
const pageEdge = Color(0xFF3D382A);

/// Warm border variant
const pageEdgeWarm = Color(0xFF4A4330);

// ── Brand accents ─────────────────────────────────────────────────────────────
/// Primary accent — warm amber
const spineAccent = Color(0xFFBF8C3A);

/// Mid amber
const spineMid = Color(0xFFD4A050);

/// Light amber
const spineLight = Color(0xFFE8B86D);

/// Gold highlight — super-like, premium
const goldLeaf = Color(0xFFD4A85A);

/// Deep gold
const goldDeep = Color(0xFFAA8030);

// ── Dark text ─────────────────────────────────────────────────────────────────
/// Primary — warm cream
const inkParchment = Color(0xFFF4EDD8);

/// Secondary — muted amber-grey
const inkFaded = Color(0xFFAA9A72);

/// Tertiary / disabled
const inkDust = Color(0xFF7A6A48);

// ── Signals ───────────────────────────────────────────────────────────────────
const swipeLike = Color(0xFFBF8C3A);
const swipeSkip = Color(0xFF5A3A20);
const bookmarkGold = goldLeaf;

// ── Light mode ────────────────────────────────────────────────────────────────
const _lightSurface    = Color(0xFFFAF6EE);
const _lightCard       = Color(0xFFF2EBE0);
const _lightBorder     = Color(0xFFDDD2BE);
const _lightOnSurface  = Color(0xFF1C1A14);
const _lightOnVariant  = Color(0xFF6B6250);
const _lightPrimary    = Color(0xFF8B6914);

// ─── Story / Swipe Card — same charcoal palette (now unified) ─────────────────
// These aliases remain so the card/reading-view code compiles unchanged.
const cardCharcoalDark    = coverDark;
const cardCharcoalMid     = coverMid;
const cardCharcoalEdge    = pageEdge;
const cardCharcoalText    = Color(0xFFEDE3C8); // lighter cream — dark card title
const cardCharcoalSubtext = Color(0xFFA89878); // lighter muted amber — dark card body
const cardCharcoalAccent  = spineAccent;

const cardCreamLight   = _lightSurface;
const cardCreamMid     = _lightCard;
const cardCreamEdge    = _lightBorder;
const cardCreamText    = Color(0xFF2A2518); // darker charcoal — light card title
const cardCreamSubtext = Color(0xFF5A5245); // deeper warm grey — light card body
const cardCreamAccent  = _lightPrimary;

// ─── Legacy aliases ───────────────────────────────────────────────────────────
const softBlack   = coverMid;
const borderBlack = pageEdge;
const cardBlack   = coverDark;
const primaryPurple = spineAccent;

class AppTheme {
  const AppTheme._();

  static TextTheme _buildTextTheme(TextTheme base) {
    final lora = GoogleFonts.loraTextTheme(base);
    return lora.copyWith(
      displayLarge:  GoogleFonts.playfairDisplay(textStyle: lora.displayLarge?.copyWith(fontWeight: FontWeight.w700)),
      displayMedium: GoogleFonts.playfairDisplay(textStyle: lora.displayMedium?.copyWith(fontWeight: FontWeight.w700)),
      displaySmall:  GoogleFonts.playfairDisplay(textStyle: lora.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
      headlineLarge: GoogleFonts.playfairDisplay(textStyle: lora.headlineLarge?.copyWith(fontWeight: FontWeight.w700)),
      headlineMedium:GoogleFonts.playfairDisplay(textStyle: lora.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
      headlineSmall: GoogleFonts.playfairDisplay(textStyle: lora.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  // ── Dark theme ──────────────────────────────────────────────────────────────
  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppConstants.seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface:                    leatherBrown,
      surfaceContainerLowest:     coverDark,
      surfaceContainerLow:        coverDark,
      surfaceContainer:           coverMid,
      surfaceContainerHigh:       coverHigh,
      surfaceContainerHighest:    const Color(0xFF3E3826),
      primary:                    spineAccent,
      onPrimary:                  inkParchment,
      primaryContainer:           coverMid,
      onPrimaryContainer:         inkParchment,
      secondary:                  goldLeaf,
      onSecondary:                coverDark,
      secondaryContainer:         const Color(0xFF3A3218),
      onSecondaryContainer:       goldLeaf,
      onSurface:                  inkParchment,
      onSurfaceVariant:           inkFaded,
      outline:                    pageEdgeWarm,
      outlineVariant:             pageEdge,
      error:                      swipeSkip,
      onError:                    inkParchment,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: leatherBrown,
      canvasColor: leatherBrown,
      cardColor: coverDark,
      textTheme: _buildTextTheme(ThemeData.dark(useMaterial3: true).textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: leatherBrown,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: inkParchment,
      ),
      cardTheme: CardThemeData(
        color: coverDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: pageEdge, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: coverMid,
        labelStyle: const TextStyle(color: inkFaded),
        hintStyle: TextStyle(color: inkFaded.withValues(alpha: 0.6)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pageEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pageEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: spineAccent.withValues(alpha: 0.7)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: spineAccent,
          foregroundColor: inkParchment,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: spineAccent,
          foregroundColor: inkParchment,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: spineAccent),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: spineAccent,
        foregroundColor: inkParchment,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: spineAccent,
        unselectedLabelColor: inkFaded,
        indicatorColor: spineAccent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: spineAccent,
        unselectedItemColor: inkFaded,
        backgroundColor: leatherBrown,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: pageEdge,
        space: 1,
        thickness: 0.8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: coverMid,
        selectedColor: spineAccent.withValues(alpha: 0.22),
        labelStyle: GoogleFonts.lora(color: inkFaded, fontSize: 12, fontWeight: FontWeight.w500),
        side: const BorderSide(color: pageEdge, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: coverHigh,
        contentTextStyle: GoogleFonts.lora(color: inkParchment),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: coverMid,
        modalBackgroundColor: coverMid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: coverMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.playfairDisplay(color: inkParchment, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: GoogleFonts.lora(color: inkFaded, fontSize: 14),
      ),
    );
  }

  // ── Light theme ─────────────────────────────────────────────────────────────
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppConstants.seedColor,
      brightness: Brightness.light,
    ).copyWith(
      primary:                 _lightPrimary,
      surface:                 _lightSurface,
      onSurface:               _lightOnSurface,
      onSurfaceVariant:        _lightOnVariant,
      outline:                 const Color(0xFFB8A878),
      outlineVariant:          _lightBorder,
      surfaceContainerLowest:  _lightCard,
      surfaceContainerLow:     const Color(0xFFEDE5D6),
      surfaceContainer:        const Color(0xFFE5DBCA),
      surfaceContainerHigh:    const Color(0xFFDAD0BC),
      surfaceContainerHighest: const Color(0xFFCDC2AB),
      secondary:               goldLeaf,
      onSecondary:             _lightOnSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightSurface,
      textTheme: _buildTextTheme(ThemeData.light(useMaterial3: true).textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _lightOnSurface,
      ),
      cardTheme: CardThemeData(
        color: _lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _lightBorder, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightCard,
        labelStyle: const TextStyle(color: _lightOnVariant),
        hintStyle: TextStyle(color: _lightOnVariant.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _lightPrimary.withValues(alpha: 0.6)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _lightPrimary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _lightPrimary,
        foregroundColor: Colors.white,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: _lightPrimary,
        unselectedLabelColor: _lightOnVariant,
        indicatorColor: _lightPrimary,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: _lightPrimary,
        unselectedItemColor: _lightOnVariant,
        backgroundColor: _lightSurface,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: _lightBorder,
        space: 1,
        thickness: 0.8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightCard,
        selectedColor: _lightPrimary.withValues(alpha: 0.14),
        labelStyle: GoogleFonts.lora(color: _lightOnVariant, fontSize: 12, fontWeight: FontWeight.w500),
        side: const BorderSide(color: _lightBorder, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightCard,
        contentTextStyle: GoogleFonts.lora(color: _lightOnSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _lightCard,
        modalBackgroundColor: _lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _lightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.playfairDisplay(color: _lightOnSurface, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: GoogleFonts.lora(color: _lightOnVariant, fontSize: 14),
      ),
    );
  }
}
