# Centavo

[![CI](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/blandisc/centavo-ios/actions/workflows/ci.yml)

Un tracker de gastos minimalista para iOS. Cada pago con **Apple Wallet** se anota solo, mediante una automatización de **Atajos**. Todo vive en tu iPhone: sin cuenta, sin servidor, sin red.

## Cómo funciona

1. Centavo expone la acción **«Registrar gasto»** (App Intent) con tres campos: Monto, Comercio y Tarjeta.
2. Tú creas una automatización de Atajos con el disparador **Transacción** (iOS 17+) que llama esa acción con las variables del pago.
3. Centavo interpreta el monto (`$1,234.56`, `12,50 €`, …), lo guarda en SwiftData y te muestra el total del mes.

Lo que no captura Wallet (efectivo, tarjeta física, compras en línea) se anota a mano con «Anotar gasto».

## La pantalla

Una sola pantalla, con los componentes nativos de iOS (Liquid Glass en iOS 26) y la apariencia del teléfono (claro u oscuro):

- **Total del mes** en tu moneda; las demás aparecen aparte.
- **Carrusel que se desliza:** el **calendario** (cada día más dorado mientras más gastaste) y el **presupuesto** (una barra que se llena hasta lo gastado, con una línea donde deberías ir hoy y lo que te queda).
- **Lista de pagos** del mes. Tocar uno lo edita; deslizarlo lo borra. La categoría se recuerda por comercio.
- **Meses anteriores** con las flechas de la barra inferior, hacia atrás hasta tu primer gasto.
- **Menú «Más»:** fijar presupuesto, exportar todo a CSV y la guía del atajo.

## Estructura

| Ruta | Qué es |
|---|---|
| `Packages/CentavoCore` | Lógica pura y probada: montos, monedas, resumen del mes, calendario, presupuesto, categorías, CSV, captura. Sin UI, sin SwiftData. |
| `Centavo/` | App SwiftUI: modelo SwiftData, App Intent, pantallas. |
| `CentavoTests/`, `CentavoUITests/` | Pruebas con base de datos, de interfaz, de flujo y de accesibilidad (corren en la CI). |
| `docs/` | Decisiones del dueño (`DECISIONS.md`) e investigación (`research/`). |
| `project.yml` | Spec de XcodeGen. El `.xcodeproj` se genera, no se versiona. |

## Build

```bash
Tools/verify.sh
```

Requiere Xcode 27 y `xcodegen` (`brew install xcodegen`).

En Linux solo corre el paquete (`Tools/verify.sh package`): la app necesita macOS.
El build de iOS lo verifica la CI en un runner macOS en cada PR.
