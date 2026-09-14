import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Identidad visual de FashionStore, espejo de las custom properties de
/// `frontend/src/styles.css` (--ink, --paper, --flame, --gold, --paper-line, --white).
class Paleta {
  static const Color ink = Color(0xFF2E2530);
  static const Color inkSuave = Color(0xFF7A6B76);
  static const Color paper = Color(0xFFFAF1EC);
  static const Color paperLinea = Color(0xFFECD9D1);
  static const Color blanco = Color(0xFFFFFAF6);
  static const Color flame = Color(0xFFC1516B);
  static const Color flameOscuro = Color(0xFF93384F);
  static const Color gold = Color(0xFFC9A15F);
  static const Color verde = Color(0xFF3F7D5C);
  static const Color rojo = Color(0xFFB3453F);
}

/// `--font-display` de la web: Bodoni Moda italica, para titulares y precios.
TextStyle fuenteDisplay({
  double? fontSize,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.bodoniModa(
      fontStyle: FontStyle.italic,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

/// `--font-mono` de la web: JetBrains Mono, para etiquetas de datos y badges.
TextStyle fuenteMono({
  double fontSize = 11,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double letterSpacing = 0.8,
}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );

ThemeData construirTema() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Paleta.flame,
      primary: Paleta.flame,
      secondary: Paleta.gold,
      surface: Paleta.blanco,
      onSurface: Paleta.ink,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Paleta.paper,
  );

  final textTheme = GoogleFonts.workSansTextTheme(base.textTheme)
      .apply(bodyColor: Paleta.ink, displayColor: Paleta.ink);

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Paleta.ink,
      foregroundColor: Paleta.paper,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: fuenteDisplay(fontSize: 19, color: Paleta.paper, letterSpacing: 0.3),
    ),
    cardTheme: CardThemeData(
      color: Paleta.blanco,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Paleta.paperLinea),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Paleta.blanco,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Paleta.paperLinea),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Paleta.paperLinea),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Paleta.flame, width: 2),
      ),
      labelStyle: GoogleFonts.workSans(color: Paleta.inkSuave),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Paleta.flame,
        foregroundColor: Paleta.blanco,
        disabledBackgroundColor: Paleta.paperLinea,
        disabledForegroundColor: Paleta.inkSuave,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w700, letterSpacing: 0.6, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Paleta.ink,
        side: const BorderSide(color: Paleta.ink, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Paleta.flameOscuro,
        textStyle: GoogleFonts.workSans(fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Paleta.paperLinea, space: 1, thickness: 1),
    // labelStyle y secondaryLabelStyle necesitan color explicito: sin el, el texto de
    // los chips no seleccionados sale en blanco sobre el fondo claro.
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Paleta.blanco,
      selectedColor: Paleta.flame.withValues(alpha: 0.16),
      checkmarkColor: Paleta.flameOscuro,
      shape: const StadiumBorder(side: BorderSide(color: Paleta.paperLinea)),
      side: const BorderSide(color: Paleta.paperLinea),
      labelStyle: GoogleFonts.workSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Paleta.ink,
      ),
      secondaryLabelStyle: GoogleFonts.workSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Paleta.flameOscuro,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Paleta.blanco,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Paleta.ink,
      contentTextStyle: GoogleFonts.workSans(color: Paleta.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Titular con el aire del `--font-display` de la web: Bodoni Moda italica.
/// Por defecto va en mayusculas (wordmark, encabezados de seccion); para un
/// nombre propio (persona, prenda) pasa `mayusculas: false`.
class Titular extends StatelessWidget {
  const Titular(this.texto, {super.key, this.tamano = 24, this.color, this.mayusculas = true});

  final String texto;
  final double tamano;
  final Color? color;
  final bool mayusculas;

  @override
  Widget build(BuildContext context) => Text(
        mayusculas ? texto.toUpperCase() : texto,
        style: fuenteDisplay(
          fontSize: tamano,
          height: 1.08,
          color: color ?? Paleta.ink,
          letterSpacing: mayusculas ? 0.5 : 0,
        ),
      );
}

/// Etiqueta monoespaciada, el vocabulario de datos del panel web.
class EtiquetaDato extends StatelessWidget {
  const EtiquetaDato(this.texto, {super.key, this.color});

  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        texto.toUpperCase(),
        style: fuenteMono(fontSize: 11, letterSpacing: 1, color: color ?? Paleta.inkSuave),
      );
}
