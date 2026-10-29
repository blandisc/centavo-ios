# Al día

_En el código y el repo sigue llamándose Centavo._

[![CI](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml)

Un tracker de gastos minimalista para iOS. Cada pago con **Apple Wallet** se anota solo, mediante una automatización de **Atajos**. Tus gastos viven en tu iPhone y se respaldan en tu iCloud privado: sin cuenta de Centavo, sin servidor propio.

## Cómo funciona

1. Centavo expone la acción **«Registrar gasto»** (App Intent) con tres campos: Monto, Comercio y Tarjeta.
2. Tú creas una automatización de Atajos con el disparador **Transacción** (iOS 17+) que llama esa acción con las variables del pago.
3. Centavo interpreta el monto (`$1,234.56`, `12,50 €`, …), lo guarda en SwiftData y te muestra el total del mes.

Después de cada pago, el aviso de Atajos te dice cuánto te queda del presupuesto. Y en cualquier momento puedes preguntarle a Siri **«¿Cuánto llevo en Centavo?»**.

Lo que no captura Wallet (efectivo, tarjeta física, compras en línea) se anota a mano con «Anotar gasto».

## La pantalla

Una sola pantalla, estilo «Noche ticket» (modo oscuro, latón, tipografía de ticket) sobre componentes nativos de iOS (barras con Liquid Glass en iOS 26):

- **Total del mes** en tu moneda; las demás aparecen aparte.
- **Carrusel que se desliza:** primero el **presupuesto** (un ticket que se llena hasta lo gastado, con el porcentaje que llevas, una línea donde deberías ir hoy y lo que te queda) y luego el **calendario** (cada día más dorado mientras más gastaste).
- **Lista de pagos** como ticket del mes. Tocar uno lo edita; deslizarlo lo borra. La categoría se recuerda por comercio.
- **Meses anteriores** con las flechas de la barra inferior, hacia atrás hasta tu primer gasto.
- **Menú «Más»** y botón «+»: fijar presupuesto, exportar todo a CSV, la guía del atajo y anotar un gasto.

Apple no deja que una app cree esa automatización por ti; la app trae una guía paso a paso.

## Estructura

| Ruta | Qué es |
|---|---|
| `Packages/CentavoCore` | Lógica pura y probada: montos, monedas, resumen del mes, calendario, presupuesto, categorías, CSV, captura. Sin UI, sin SwiftData. |
| `Centavo/` | App SwiftUI: modelo SwiftData, App Intent, pantallas. |
| `Centavo/Theme/` | Colores, tipografía de ticket y piezas compartidas del diseño. |
| `docs/` | Decisiones del dueño (`DECISIONS.md`) e investigación (`research/`). |
| `project.yml` | Spec de XcodeGen. El `.xcodeproj` se genera, no se versiona. |

## Build

```bash
Tools/verify.sh
```

Requiere Xcode 27 y `xcodegen` (`brew install xcodegen`).

La app sincroniza con iCloud, y eso solo se puede firmar con la cuenta de desarrollador de pago. Con una cuenta gratuita, compila con `Centavo/CentavoGratis.entitlements` (solo el App Group que comparte con los widgets; dejar el valor en blanco no basta) y la app guarda solo en el teléfono:

```bash
xcodebuild -scheme Centavo -configuration Release -destination 'platform=iOS,id=<tu iPhone>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<tu equipo> CODE_SIGN_ENTITLEMENTS=Centavo/CentavoGratis.entitlements build
```

`CODE_SIGN_ENTITLEMENTS` en la línea de comandos aplica a todos los objetivos; la extensión de widgets usa el mismo App Group, así que también le sirve.

En Linux solo corre el paquete (`Tools/verify.sh package`): la app necesita macOS.
El build de iOS lo verifica la CI en un runner macOS en cada PR.
