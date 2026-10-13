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

## 2026-10-11 — Moneda
- **El total del mes es de una sola moneda:** la del dispositivo (`Locale.current`). Sumar monedas distintas sería mentir, así que las demás se listan aparte, debajo del total.
- **No hay ajuste de moneda.** Cambiarla es cambiar tu región en iOS.
- **`$` a secas significa tu moneda.** Decenas de países usan ese signo; Wallet no dice cuál. `MX$`, `US$`, `€`, `USD` y compañía sí se resuelven.
- **Marcador desconocido no se adivina:** se agrupa tal cual y se muestra con el símbolo que mandó Wallet.
- **Los reembolsos son montos negativos** del mismo gasto, no un tipo aparte. Un mes puede quedar en negativo.

## 2026-10-11 — Exportar
- **CSV y nada más.** Un archivo que abre Numbers, Excel y cualquier hoja de cálculo. Sin PDF ni formatos de apps ajenas.
- **Se exporta todo**, no solo el mes a la vista. Lo que filtres lo haces en la hoja de cálculo.
- **Columnas:** Fecha, Comercio, Monto, Moneda, Tarjeta. Fechas en ISO 8601 con su huso y montos con punto decimal, para que cualquier hoja las lea igual.
- **Sale por la hoja de compartir de iOS,** así tú decides dónde queda. La app no escribe en ningún lado ni manda nada por la red.
- **La guía del atajo y la exportación viven en un menú «Más»** en la barra, para no llenarla de botones.

## 2026-10-11 — Categorías
- **La categoría vive en el gasto** (`Expense.category`, opcional). La «memoria» por comercio es la regla, no una tabla: la categoría que usaste la última vez para ese comercio. Agregar una propiedad opcional es migración ligera y SwiftData la hace sola.
- **Texto libre, sin lista fija.** No sé cómo organizas tu dinero. Lo que evita que se fragmente en casi-duplicados es la memoria por comercio y un menú con las categorías que ya usas.
- **Los comercios se comparan ignorando mayúsculas, acentos y espacios**, pero nada más. Adivinar que «OXXO 1234» y «OXXO 5678» son el mismo lugar sería adivinar, y se equivocaría lo suficiente para estorbar.
- **El total por categoría es solo de la moneda principal**, por la misma razón que el total del mes: sumar monedas distintas sería mentir.
- **Sin pantalla de categorías.** Se escribe en la hoja de edición que ya existe y se lee en una sección de la pantalla principal.

## 2026-10-12 — Captura con base en investigación
- **Se avanza sin prueba en el teléfono.** El dueño pidió asumir que la automatización funciona; el respaldo es `docs/research/atajos-wallet.md`.
- **La promesa es «la mayoría», no «todos».** El disparador falla con algunos bancos y solo cubre pagos acercando el teléfono.
- **Un pago con monto 0 no se guarda:** la acción falla y pide agregarlo a mano. Un gasto de $0 casi siempre es un error de Wallet.
- **Un pago idéntico (monto, comercio, tarjeta) dentro de 5 minutos se ignora** como repetido.
- **Los pagos rechazados no se pueden distinguir;** se borran a mano.

## 2026-10-12 — Diseño primero y estilo «Noche ticket»
- **El diseño va antes que la funcionalidad.** Cada pantalla se boceta en el lienzo y se aprueba antes de construirla. Lienzo: https://claude.ai/artifact/EuRdR9c1mQ4nNivNwQGVYN. (La noche del 2026-10-12 el dueño pidió terminar la app completa sin aprobar cada paso; los bocetos quedaron en el lienzo y cada PR dice qué boceto sigue.)
- **Estilo «Noche ticket»:** papel casi negro cálido, un solo acento latón, tipografía de ticket (IBM Plex Mono, licencia OFL, incluida en la app). Minimalista, sobrio, elegante.
- **Solo modo oscuro por ahora.** La app fuerza el modo oscuro. La versión de día queda pendiente.
- **La pantalla principal es un carrusel de dos vistas** que se desliza: calendario del mes y presupuesto. Se quita la vista de categorías: el total por categoría ya no se muestra en la pantalla principal (la categoría se sigue guardando, se ve en cada gasto y sale en el CSV).
- **Calendario:** cada día se pinta más dorado mientras más se gastó, relativo al día más fuerte del mes. Solo cuenta la moneda principal. La semana empieza en el día que marque la región del teléfono.
- **Presupuesto:** una sola cifra mensual en la moneda principal, guardada en el teléfono (no toca el esquema de SwiftData). «Lo que deberías llevar hoy» reparte el presupuesto parejo entre los días del mes.
- **Devoluciones:** se muestran como dinero que regresa («+230.00»). El teclado decimal no tiene signo menos, así que la hoja del gasto trae el interruptor «Es una devolución».

## 2026-10-13 — Entrega
- **Ícono provisional,** igual que el nombre «Centavo»: el ticket del presupuesto llenándose de latón con la línea de «hoy». Se cambia cuando se decida el nombre definitivo.
- **El arranque también es oscuro:** la app declara el estilo oscuro en su configuración, no solo en las pantallas, para que no parpadee en blanco al abrir.
- **La CI comprueba el contenido de la app** (fuentes, ícono, modo oscuro), porque desde Linux no se puede abrir la app.
- **Quedó en el código, sin usarse:** el desglose por categoría del mes (`MonthSummary.categories`). Se dejó por si se quiere volver a mostrar.

## 2026-10-13 — Robustez
- **Un monto con más de 12 dígitos enteros no es un monto:** se rechaza. `Decimal` redondea en silencio después de 38 dígitos y un número así solo puede ser un error o un ataque.
- **Un decimal que no es de centavos ni un grupo de tres se rechaza** (`0.0001`, `1.23456`), en vez de leerse como otra cosa.
- **El CSV neutraliza fórmulas:** un texto que empieza con `=`, `+`, `-` o `@` sale con un apóstrofo delante. Los comercios llegan de afuera y abrir el CSV no debe ejecutar nada. Los montos negativos no se tocan.
- **A mano, una «moneda» que es una palabra («pesos») se ignora** y el gasto queda en la moneda principal. Se conservan los símbolos sueltos (`₱`), los códigos de tres letras y los conocidos.

## 2026-10-13 — Meses anteriores
- **Se puede ver cada mes, hacia atrás hasta el primer gasto.** Flechas junto al mes, en el encabezado; no hay hacia adelante. La lista muestra solo los pagos del mes que se ve (antes mezclaba todos).
- **Un mes cerrado se mide completo:** el presupuesto entero «tocaba» gastarse, así que no hay línea de «hoy» y el texto dice «te quedaron». Hay un solo presupuesto para todos los meses.
- **Anotar un gasto mientras se ve un mes anterior lo pone en ese mes** (último día), en vez de en hoy, para que no «desaparezca» de la vista.
- **Exportar CSV sigue sacando todos los meses.**
- **Las pruebas de interfaz, de flujo y de zonas táctiles corren en cada PR** (simulador de la CI) y deben pasar antes de mergear.
