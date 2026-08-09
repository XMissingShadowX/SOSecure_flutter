import 'dart:ui';

import 'package:flutter/material.dart';

/// Puerto del sistema "Liquid Glass" de app/globals.css (proyecto Next.js).
///
/// En la web son tres piezas que trabajan juntas:
///   1. `.ambient-bg` — tres manchas radiales difusas (cyan / rojo / verde) detrás
///      de todo el contenido, para que el vidrio tenga color que refractar.
///   2. `.glass` / `.glass-strong` — superficies translúcidas con `backdrop-filter`,
///      borde tenue y un `inset 0 1px 0` blanco arriba (brillo especular).
///   3. Sombras suaves en capas (`--glass-shadow-sm` / `--glass-shadow`).
///
/// Flutter no tiene `backdrop-filter` sobre un widget arbitrario sin `BackdropFilter`
/// (que es caro si se anida decenas de veces en una lista scrolleable), así que
/// [GlassCard] simula el efecto con un degradado vertical translúcido sobre el
/// fondo ambiental. Para las superficies grandes y estáticas (header, nav) sí vale
/// la pena el blur real — ver [GlassSurface].
class AppGlass {
  const AppGlass._();

  // --glass-bg / --glass-bg-strong
  static Color bg(Brightness b) => b == Brightness.dark
      ? const Color(0xFF101720).withValues(alpha: 0.55)
      : Colors.white.withValues(alpha: 0.55);

  static Color bgStrong(Brightness b) => b == Brightness.dark
      ? const Color(0xFF101720).withValues(alpha: 0.80)
      : Colors.white.withValues(alpha: 0.82);

  // --glass-border / --glass-border-strong
  static Color border(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFF232933).withValues(alpha: 0.10);

  static Color borderStrong(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0xFF232933).withValues(alpha: 0.12);

  // --glass-highlight (el `inset 0 1px 0` del borde superior)
  static Color highlight(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.70);

  // --glass-shadow-sm / --glass-shadow
  static List<BoxShadow> shadowSm(Brightness b) => [
    BoxShadow(
      color: b == Brightness.dark
          ? Colors.black.withValues(alpha: 0.25)
          : const Color(0xFF232933).withValues(alpha: 0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadow(Brightness b) => [
    BoxShadow(
      color: b == Brightness.dark
          ? Colors.black.withValues(alpha: 0.35)
          : const Color(0xFF232933).withValues(alpha: 0.14),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  /// Radio equivalente a `--radius: 0.75rem` (12px) — el de popovers, menús y
  /// superficies pequeñas.
  static const radius = 12.0;
  static const borderRadius = BorderRadius.all(Radius.circular(radius));

  /// Las Card de la web no usan `--radius` sino `rounded-2xl` (16px), ver la
  /// clase base en components/ui/card.tsx.
  static const cardRadius = 16.0;
  static const cardBorderRadius = BorderRadius.all(Radius.circular(cardRadius));

  /// `cubic-bezier(0.34, 1.56, 0.64, 1)` — `--ease-spring` de globals.css.
  static const easeSpring = Cubic(0.34, 1.56, 0.64, 1);
}

/// Puerto de `.ambient-bg`: tres manchas radiales difusas detrás del contenido.
///
/// Cada `radial-gradient(circle at X% Y%, color, transparent N%)` de CSS se traduce
/// a un [RadialGradient] con `center` en coordenadas de [Alignment] (-1..1) y
/// `radius` relativo al lado menor del contenedor.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    // Mismos hues que --chart-4 (cyan/primary), --destructive y --safe en globals.css.
    final cyan = dark ? const Color(0xFF00CCB2) : const Color(0xFF008C75);
    const red = Color(0xFFDF000D);
    final green = dark ? const Color(0xFF31AA40) : const Color(0xFF008B1D);

    // Opacidades de .ambient-bg (bloque dark) y html.light .ambient-bg.
    final aCyan = dark ? 0.16 : 0.10;
    final aRed = dark ? 0.10 : 0.07;
    final aGreen = dark ? 0.09 : 0.07;

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // circle at 12% 18% → Alignment(-0.76, -0.64)
          _blob(const Alignment(-0.76, -0.64), cyan, aCyan, 0.90),
          // circle at 88% 12% → Alignment(0.76, -0.76)
          _blob(const Alignment(0.76, -0.76), red, aRed, 0.84),
          // circle at 50% 95% → Alignment(0, 0.90)
          _blob(const Alignment(0, 0.90), green, aGreen, 0.90),
          child,
        ],
      ),
    );
  }

  static Widget _blob(
    Alignment center,
    Color color,
    double alpha,
    double radius,
  ) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
            // El `transparent 45%` de CSS corta el degradado antes del borde;
            // aquí el stop intermedio hace que se desvanezca a la misma altura.
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Reemplazo drop-in de [Card] con el look de `.glass` de la web: degradado
/// vertical translúcido, borde tenue con el brillo especular arriba y sombra suave.
///
/// Acepta el mismo subconjunto de parámetros de [Card] que usa el proyecto
/// (`color`, `margin`, `clipBehavior`, `child`) para poder sustituirlo sin tocar
/// los call sites. Cuando se pasa [color] — las cards tintadas de éxito/alerta,
/// que en el código vienen de `Color.alphaBlend(tinte, surface)` — ese color se
/// usa como base del degradado en lugar de la superficie neutra, así que el tinte
/// semántico se conserva.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    this.child,
    this.color,
    this.margin,
    this.clipBehavior = Clip.none,
    this.borderRadius,
    this.shape,
    this.strong = false,
  });

  final Widget? child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final BorderRadius? borderRadius;

  /// Compatibilidad con los call sites que venían de [Card]: cuando el shape es
  /// un [RoundedRectangleBorder] con `side` de color (las cards de acento —
  /// ruta seleccionada, alerta pendiente) se respetan su radio y su borde en
  /// lugar del borde de vidrio genérico, que es demasiado tenue para señalar
  /// selección.
  final ShapeBorder? shape;

  /// Equivalente a `.glass-strong`: más opaco, borde más marcado y sombra mayor.
  /// Para paneles flotantes sobre el mapa o diálogos, donde hace falta contraste.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final rounded = shape is RoundedRectangleBorder
        ? shape as RoundedRectangleBorder
        : null;
    final radii =
        borderRadius ??
        (rounded?.borderRadius.resolve(Directionality.of(context))) ??
        AppGlass.cardBorderRadius;
    final accentSide = rounded?.side;
    final hasAccent =
        accentSide != null &&
        accentSide.style != BorderStyle.none &&
        accentSide.color.a > 0;

    // Base del degradado: el tinte semántico si el call site lo pidió, si no la
    // superficie de vidrio genérica.
    final base = color ?? (strong ? AppGlass.bgStrong(b) : AppGlass.bg(b));

    // `.glass` en CSS es un color plano + `inset 0 1px 0` blanco: NO lleva
    // degradado vertical. Aquí se conserva uno mínimo porque sin blur real
    // detrás la card se ve completamente chata, pero deliberadamente sutil —
    // un degradado marcado se aleja del look de la web en lugar de imitarlo.
    final top = Color.alphaBlend(
      Colors.white.withValues(alpha: b == Brightness.dark ? 0.03 : 0.20),
      base,
    );
    final bottom = Color.alphaBlend(
      Colors.black.withValues(alpha: b == Brightness.dark ? 0.04 : 0.015),
      base,
    );

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      clipBehavior: clipBehavior == Clip.none ? Clip.antiAlias : clipBehavior,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        borderRadius: radii,
        border: hasAccent
            ? Border.all(color: accentSide.color, width: accentSide.width)
            : Border.all(
                color: strong ? AppGlass.borderStrong(b) : AppGlass.border(b),
                width: 1,
              ),
        boxShadow: strong ? AppGlass.shadow(b) : AppGlass.shadowSm(b),
      ),
      // El borde superior con brillo (`border-top-color: var(--glass-highlight)`)
      // se dibuja aparte porque Border.all no permite un color distinto por lado
      // junto con borderRadius.
      foregroundDecoration: BoxDecoration(
        borderRadius: radii,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppGlass.highlight(b),
            AppGlass.highlight(b).withValues(alpha: 0),
          ],
          stops: const [0.0, 0.012],
        ),
      ),
      child: child,
    );
  }
}

/// Superficie de vidrio con blur real (`backdrop-filter`). Se usa solo en
/// elementos grandes y únicos — header y barra de navegación — donde el costo
/// del [BackdropFilter] se paga una sola vez por frame.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppGlass.bgStrong(b),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}
