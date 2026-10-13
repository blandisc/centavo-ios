# Changelog

## [Unreleased]
### Fixed
- Los días del calendario y el selector de fecha salían en inglés: la app ahora se declara en español.
- Con letra muy grande ya no se rompen las palabras («CENTA/VO», «OXX/O»): el encabezado y los pagos se acomodan en vertical y el botón «Anotar gasto» deja de crecer sin límite.
- «Te quedan» en el presupuesto ya no se encima sobre la barra dorada cuando no cabe.
- El interruptor de devolución y los botones de las hojas ya no se recortan en el borde derecho.
- La pantalla se actualiza sola al cambiar de día, en vez de quedarse en el mes anterior.
- No se puede guardar un gasto de $0 a mano.
- Borrar un gasto ahora pide confirmación.

### Added
- Ícono de la app (provisional, igual que el nombre): el ticket del presupuesto llenándose de latón, con la línea de «hoy».
- La guía para configurar el atajo estrena el diseño «Noche ticket». Los pagos rechazados se borran tocándolos, ya no deslizando.
- La hoja para anotar o corregir un gasto estrena el diseño «Noche ticket», con el interruptor «Es una devolución» (el teclado de montos no tiene signo menos) y un aviso de la última categoría que usaste con ese comercio.
- Nueva pantalla principal «Noche ticket»: el total del mes, un carrusel que se desliza entre el calendario del mes y tu presupuesto, y la lista de pagos como un ticket. El presupuesto se fija desde el menú «Más». Se quita el total por categoría de esta pantalla.
- Base del nuevo diseño «Noche ticket»: modo oscuro, color latón y tipografía de ticket. Lógica del calendario y del presupuesto.
- Captura más confiable: los pagos repetidos y los que Wallet manda vacíos ya no se anotan, y la guía explica qué pagos se capturan solos y cuáles no.
- Categorías que se recuerdan por comercio: la que usaste la última vez se aplica sola al siguiente pago de ese comercio, incluso a los que captura Wallet. Total por categoría en la pantalla principal y columna nueva en el CSV (CEN-3).
- Exportar todos los gastos a CSV desde el menú «Más», con la hoja de compartir de iOS (CEN-8).
- Moneda correcta: cada marcador de Wallet ($, MX$, €, USD, …) se traduce a su código ISO; el total del mes suma solo tu moneda y las demás se muestran aparte. Los reembolsos restan (CEN-4).
- Agregar un gasto a mano con «+» y editar o borrar cualquier gasto tocándolo (CEN-2).
- CI en GitHub Actions: corre las pruebas de CentavoCore y el build de iOS en cada PR (CEN-5).
- Esqueleto inicial: acción «Registrar gasto» para la automatización Transacción de Atajos, parser de montos multi-formato, lista con total del mes y guía de configuración.
