# Decisiones del dueño

Registro de decisiones. Se revierten solo de forma explícita.

## 2026-10-11 — Arranque
- **Captura vía Atajos.** La fuente de datos es la automatización «Transacción» de Atajos con Apple Wallet. No hay API de Apple para leer el historial de Wallet de terceros; FinanceKit queda fuera de alcance por ahora (requiere entitlement especial y aplica a tarjetas Apple/Apple Cash).
- **Offline y on-device.** Sin cuenta, sin servidor, sin red.
- **Minimalismo.** Una pantalla principal: total del mes y lista de pagos.
- **Repo privado** en GitHub (`blandisc/centavo-ios`).
- **Tablero propio** en Multica: workspace «Centavo», prefijo `CEN`.
- **Nombre de trabajo «Centavo»**, provisional.
- **Stack:** SwiftUI + SwiftData + App Intents, iOS 18+, XcodeGen; lógica pura en el paquete `CentavoCore`.

## 2026-10-11 — Verificación
- **La CI de GitHub Actions es la única fuente de verdad del build de iOS.** Corre en un runner macOS con el Xcode más nuevo de la imagen; ningún PR que toque `Centavo/` se mergea sin ella en verde.
- **El desarrollo también ocurre en Linux**, donde solo se puede correr `Tools/verify.sh package`. Por eso toda la lógica probable vive en `CentavoCore`.
- **Sin plan de migraciones de SwiftData todavía:** cualquier cambio al esquema de `Expense` se consulta antes de hacerlo.

## 2026-10-11 — Alcance de la captura
- **Automático = solo pagos con Apple Wallet** (disparador «Transacción» de Atajos). **Todo lo demás se registra a mano** (efectivo, tarjeta física, en línea).
- Se descartan los SMS y correos del banco como fuente. Leer las notificaciones de otras apps es imposible en iOS.
