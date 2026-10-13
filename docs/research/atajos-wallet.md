# Investigación: la automatización de Wallet en Atajos

Octubre 2026. Investigación de escritorio, sin prueba en un iPhone. El dueño pidió asumir que la captura funciona y avanzar con lo que dicen las fuentes.

## Lo que se confirma

- **Existe y pasa los datos que necesitamos.** El disparador entrega a la acción siguiente el monto, el comercio y la tarjeta, como «Entrada del atajo». ([iDrop News](https://www.idropnews.com/ios-17/this-new-ios-17-shortcut-will-help-you-keep-track-of-your-spending/197589/), [TechTiff](https://techtiff.substack.com/p/apple-wallet-expense-tracker-shortcuts))
- **Es el patrón de toda la categoría.** Varias apps de gastos (MoneyCoach, BalanceTrackr, WalletPal, Skwad, Moneko) viven de este mismo disparador. ([WalletPal](https://walletpalapp.github.io/apple-pay-expense-tracker-shortcuts.html), [BalanceTrackr](https://balancetrackr.com/SiriShortcutsSetup/en.html))
- **«Ejecutar inmediatamente»** evita que iOS pregunte en cada pago.
- **El monto llega como texto con símbolo**, p. ej. `$6.22`, con el formato de la región del teléfono. ([tgul.dev](https://tgul.dev/articles/ios-shortcuts-ynab/), [MoneyCoach](https://moneycoach.ai/blog/troubleshooting-common-issues-with-shortcut-automations-for-apple-pay-transaction-import)) Por eso la acción recibe el monto como texto y lo interpreta Centavo.

## Límites conocidos

| Qué pasa | Qué hace Centavo |
|---|---|
| **Solo pagos acercando el teléfono o el reloj.** Las compras en línea o dentro de apps no disparan nada. ([Graham Haley](https://grahamhaley.co.uk/2024/11/19/apple-pay-automation/), [CashJot](https://www.cashjot.com/blog/apple-pay-expense-tracking)) | Ya está cubierto: lo demás se registra a mano. La guía lo dice. |
| **A veces llega vacío:** comercio en blanco y monto 0. Sin respuesta de Apple. ([foro de Apple](https://developer.apple.com/forums/thread/797233)) | No guarda un gasto de $0; la acción falla con un mensaje que pide agregarlo a mano. |
| **Puede dispararse dos veces** por el mismo pago. ([mise #153](https://github.com/MGRL2201/mise/issues/153)) | Ignora un pago idéntico (monto, comercio, tarjeta) dentro de 5 minutos. |
| **Se dispara también con pagos rechazados.** ([foro de Apple](https://developer.apple.com/forums/thread/765516)) | No hay forma de distinguirlos. La guía dice que se borran deslizando. |
| **Con algunos bancos no se dispara**: Wallet recibe el pago tarde y el atajo se rinde. Reportado con Mastercard de algunos emisores y con Nubank; abierto desde 2024 (FB14035016). ([foro de Apple](https://developer.apple.com/forums/thread/765516)) | No hay arreglo de nuestro lado. La guía dice que se agregue con «+». |
| **Filtrar por categoría de comercio rompe el disparador.** ([Apple Community](https://discussions.apple.com/thread/255836983)) | La guía pide dejar todas las categorías. |
| **En iOS 26 se renombró** de «Transacción» a «Wallet». ([WalletPal](https://walletpalapp.github.io/apple-pay-expense-tracker-shortcuts.html)) | La guía menciona ambos nombres. |

## Lo que no se pudo confirmar

- Lista de países y bancos de México donde funciona. Ninguna fuente lo dice.
- El formato exacto del monto con una tarjeta mexicana (¿`$89.00` o `MX$89.00`?). El lector de montos acepta ambos.
- Si un reembolso dispara la automatización y con qué signo.
- Que no exista una API para leer el historial de Wallet de otras tarjetas: se confirma de nuevo; FinanceKit sigue limitado. ([foro de Apple](https://developer.apple.com/forums/thread/773797))

## Riesgo principal

El disparador es frágil y Apple no ha respondido los reportes. Una parte de los pagos no se va a capturar sola. El producto ya asume captura manual para todo lo demás, así que esto no cambia la decisión de arranque, pero sí la promesa: **«la mayoría de tus pagos con Wallet se anotan solos»**, no «todos».
