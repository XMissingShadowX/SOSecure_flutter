import 'package:flutter/material.dart';

// Marca de SOSecure dentro de la app. Antes cada pantalla dibujaba su propio
// icono de Material (`Icons.shield_moon` en login y en el gate de permisos,
// `Icons.verified_user` en el header) — tres escudos distintos entre sí y
// distintos del icono del lanzador, que sí es el logo real. Este widget es la
// única fuente del logo en pantalla: el mismo escudo del que
// tool/generate_app_icons.sh saca los iconos de todas las plataformas.
//
// `sosecure_shield.png` es el master con fondo transparente (el escudo solo,
// sin el texto "SOSecure" ni el fondo de marca), así que se ve bien tanto en
// tema claro como en oscuro y se puede acompañar del nombre en texto.
class SosecureLogo extends StatelessWidget {
  const SosecureLogo({super.key, this.size = 64});

  final double size;

  static const asset = 'assets/icon/sosecure_shield.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      // El PNG no es cuadrado (el escudo es más alto que ancho); contain lo
      // deja centrado dentro de la caja sin deformarlo.
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // Si el asset faltara, el logo no debe tumbar una pantalla de arranque.
      errorBuilder: (context, _, _) => Icon(
        Icons.shield,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
