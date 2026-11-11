# Al día

_En el código y el repo sigue llamándose Centavo._

[![CI](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml)

Un tracker de gastos minimalista para iOS. Cada pago con **Apple Wallet** se anota solo, mediante una automatización de **Atajos**. Tus gastos viven en tu iPhone y se respaldan en tu iCloud privado: sin cuenta de Centavo, sin servidor propio.

## Cómo funciona

1. Centavo expone la acción **«Registrar gasto»** (App Intent) con tres campos: Monto, Comercio y Tarjeta.
2. Tú creas una automatización de Atajos con el disparador **Transacción** que llama esa acción con las variables del pago.
3. Centavo interpreta el monto (`$1,234.56`, `12,50 €`, …), lo guarda en SwiftData y te muestra el total del mes.

Después de cada pago, el aviso de Atajos te dice cuánto te queda del presupuesto. Y en cualquier momento puedes preguntarle a Siri **«¿Cuánto llevo en Centavo?»**.

Lo que no captura Wallet (efectivo, tarjeta física, compras en línea) se anota a mano con «Anotar gasto».

## Las pantallas

Dos pestañas, **«Hoy»** y **«Mi dinero»**, estilo «Noche ticket» (modo oscuro, latón, tipografía de ticket) sobre componentes nativos de iOS (barras con Liquid Glass).

«Hoy»:

- **La cifra del día:** con presupuesto, «Hoy puedes gastar»; sin él, el total del mes en tu moneda (las demás aparecen aparte).
- **Carrusel que se desliza:** primero el **boleto** (una celda por día del mes: lo gastado la llena, hoy va delineado y los días por venir punteados), con «En qué se va» debajo, y luego el **calendario** (cada día más dorado mientras más gastaste).
- **Lista de pagos** como ticket del mes. Tocar uno lo edita; deslizarlo lo borra. La categoría se recuerda por comercio.
- **Meses anteriores** con las flechas de la barra superior, hacia atrás hasta tu primer gasto.
- **Menú «Más»** y botón «+»: la vista, el presupuesto, los gastos fijos, pagos y categorías, la guía del atajo, Ajustes (ahí se exporta todo a CSV) y anotar un gasto.

«Mi dinero», protegida con Face ID, lleva tus cuentas.

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

Requiere Xcode 27 y `xcodegen` (`brew install xcodegen`). La app funciona desde **iOS 26** (se prueba en iOS 26 y 27).

La app sincroniza con iCloud, y eso solo se puede firmar con la cuenta de desarrollador de pago. Con una cuenta gratuita, compila con `Centavo/CentavoGratis.entitlements` (solo el grupo de llavero que comparte con los widgets, sin iCloud ni App Group; dejar el valor en blanco no basta) y la app guarda solo en el teléfono:

```bash
xcodebuild -scheme Centavo -configuration Release -destination 'platform=iOS,id=<tu iPhone>' -allowProvisioningUpdates DEVELOPMENT_TEAM=<tu equipo> CODE_SIGN_ENTITLEMENTS=Centavo/CentavoGratis.entitlements build
```

`CODE_SIGN_ENTITLEMENTS` en la línea de comandos aplica a todos los objetivos; la extensión de widgets usa el mismo grupo de llavero, así que también le sirve.

En Linux solo corre el paquete (`Tools/verify.sh package`): la app necesita macOS.
El build de iOS lo verifica la CI en un runner macOS en cada push a `main` y en cada PR.
