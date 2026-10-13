# Changelog

## [Unreleased]
### Added
- Categorías que se recuerdan por comercio: la que usaste la última vez se aplica sola al siguiente pago de ese comercio, incluso a los que captura Wallet. Total por categoría en la pantalla principal y columna nueva en el CSV (CEN-3).
- Exportar todos los gastos a CSV desde el menú «Más», con la hoja de compartir de iOS (CEN-8).
- Moneda correcta: cada marcador de Wallet ($, MX$, €, USD, …) se traduce a su código ISO; el total del mes suma solo tu moneda y las demás se muestran aparte. Los reembolsos restan (CEN-4).
- Agregar un gasto a mano con «+» y editar o borrar cualquier gasto tocándolo (CEN-2).
- CI en GitHub Actions: corre las pruebas de CentavoCore y el build de iOS en cada PR (CEN-5).
- Esqueleto inicial: acción «Registrar gasto» para la automatización Transacción de Atajos, parser de montos multi-formato, lista con total del mes y guía de configuración.
