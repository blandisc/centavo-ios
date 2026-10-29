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
- **Los reembolsos son montos negativos** del mismo gasto, no un tipo aparte. Un mes puede quedar en negativo. (Desde el 2026-10-23, un gasto que te van a reembolsar se marca «No cuenta» en vez de anotar su negativo; las devoluciones de verdad siguen siendo negativas.)

## 2026-10-11 — Exportar
- **CSV y nada más.** Un archivo que abre Numbers, Excel y cualquier hoja de cálculo. Sin PDF ni formatos de apps ajenas.
- **Se exporta todo**, no solo el mes a la vista. Lo que filtres lo haces en la hoja de cálculo.
- **Columnas:** Fecha, Comercio, Monto, Moneda, Tarjeta (luego Categoría; y desde el 2026-10-23, Cuenta y Motivo). Fechas en ISO 8601 con su huso y montos con punto decimal, para que cualquier hoja las lea igual.
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

## 2026-10-13 — Listo para la App Store
- **Manifiesto de privacidad:** la app no rastrea ni recolecta datos; declara solo el uso de UserDefaults (el presupuesto), motivo CA92.1 (datos propios de la app).
- **Cifrado:** la app no usa cifrado propio (`ITSAppUsesNonExemptEncryption = NO`). **Categoría:** Finanzas.
- **Si la base no abre, la app se explica en vez de cerrarse.** Dice que los gastos siguen en el teléfono y que no se desinstale la app.

## 2026-10-13 — Estilo aprobado + componentes nativos de Apple; el repo es público
- **Se conserva «Noche ticket» y la estructura pasa a componentes nativos.** Decisión del dueño (opción 1 de tres): modo oscuro, latón y tipografía de ticket se quedan; las barras (superior e inferior), la lista, las hojas con formulario, los menús y los botones de Cancelar/Guardar son los del sistema, que en iOS 26 son Liquid Glass sin código extra.
- **No se reemplaza la identidad por los valores estándar del sistema.** Se probó un rediseño totalmente estándar (PR #20, cerrado sin mergear) y el dueño no lo quiso. Ante una petición que puede leerse de dos maneras («usa los guidelines de Apple»), se pregunta antes de cambiar lo aprobado.
- **«Anotar gasto» va en la barra superior** (botón «+») y las flechas de mes en la barra inferior; se quita el botón flotante hecho a mano. Deslizar para borrar vuelve, con confirmación.
- **El repo es público** (antes privado). La CI en Macs de GitHub agotó los minutos del plan privado y dejó de correr; en un repo público es gratis. Se revisó que el historial no tuviera secretos ni correos personales.

## 2026-10-15 — El presupuesto va primero
- **La pantalla principal abre en el presupuesto; el calendario pasa a la segunda página del carrusel.** Decisión del dueño. Reemplaza el orden «calendario, luego presupuesto» del 2026-10-12. Sin presupuesto fijado, la primera página es la invitación «Fijar presupuesto».

## 2026-10-15 — Aviso al pagar
- **El aviso que muestra Atajos después de un pago dice cuánto te queda del presupuesto** («Anotado: $47.50 en OXXO. Te quedan $5,586.50 del presupuesto.»), o por cuánto te pasaste. Es el momento en que más sirve y no pide permisos: es el mismo diálogo que la acción ya devolvía. Sin presupuesto, el aviso queda como antes.
- **Si calcular el presupuesto falla, el pago se guarda igual** y el aviso dice menos. La captura nunca depende de eso.

## 2026-10-15 — Guía del atajo paso a paso
- **La guía es un recorrido de 8 pasos, uno por pantalla, con un dibujo de la pantalla de Atajos** y un anillo latón donde hay que tocar. El dueño no pudo crear la automatización con la lista de texto. Se descartó un video grabado: el simulador no llega a esa parte con el disparador de Wallet, se volvería viejo con cada iOS y pesaría en la app. Los dibujos se ajustan en código.
- **El paso de conectar variables se anima en bucle, con subtítulos** (los 4 toques). Con «Reducir movimiento» se queda quieto.
- **Los textos de la guía salen del Atajos real** (iOS 26, es-MX), no de supuestos. Detalle en `docs/research/atajos-wallet.md`.
- **El campo «Monto» de «Registrar gasto» se llama «Importe»**, como lo llama Atajos en español. Solo cambia el título visible: las automatizaciones ya hechas siguen funcionando.
- **El último paso comprueba que funciona:** detecta el primer pago que guardó la automatización (los únicos que guardan el texto original de Wallet).

## 2026-10-15 — Respaldo en iCloud
- **Los gastos y el presupuesto se sincronizan en el iCloud privado de la persona.** Decisión del dueño: guardar solo en el teléfono era frágil (borrar la app borraba todo y el CSV no se puede reimportar). Reemplaza «Offline y on-device» y la regla «Cero red» del arranque: sigue sin haber servidor propio, telemetría ni cuenta de Centavo, y la app no hace llamadas de red; sincroniza el sistema, con la cuenta de iCloud del teléfono.
- **Gastos:** SwiftData con CloudKit (base privada `iCloud.com.blandisc.centavo`). Para eso cada campo del gasto tiene un valor por omisión; no cambia lo que ya está guardado. **Presupuesto:** almacén clave-valor de iCloud.
- **Requiere la cuenta de desarrollador de pago.** Con la gratuita no se puede firmar iCloud: se compila con `CODE_SIGN_ENTITLEMENTS=` vacío y la app guarda solo en el teléfono, como antes. Al reinstalar con la cuenta de pago, lo que ya había en el teléfono se sube solo.
- **Sin iCloud en el teléfono (sesión cerrada), la app funciona igual** y guarda localmente.

## 2026-10-15 — Captura tolerante
- **Si llega el pago completo en vez del importe, se busca la cifra con moneda** (`CaptureText`): solo cuenta un número con signo o código de moneda real al lado. Un número sin moneda (la tarjeta, un folio) nunca se toma como monto; si no hay cifra con moneda, la acción falla como antes. Un texto que es solo un monto se lee exactamente igual que antes.
- **El parámetro «Importe» se conecta solo a lo anterior** donde Atajos lo permite (`connectToPreviousIntentResult`). No verificado con el disparador de Wallet.

## 2026-10-15 — Salud de la captura
- **Una línea bajo el carrusel dice cuándo llegó el último pago de Wallet** (solo en el mes actual). Una automatización rota fallaba en silencio. Tres días sin pagos, o ningún pago de Wallet nunca, se muestra en latón y abre la guía. Se distingue un pago de Wallet porque solo la automatización guarda el texto original del importe.

## 2026-10-15 — Anotar con Siri
- **«Anotar gasto» es un atajo listo de Siri, Spotlight y el botón de Acción**: pregunta «¿Cuánto fue?» y «¿Dónde?» y guarda sin abrir la app. Un gasto a mano no cuenta como captura de Wallet ni se descarta como repetido. Una moneda escrita como palabra se ignora, igual que en la hoja.
- **«Registrar gasto» deja de ser atajo listo** y queda solo como acción de Atajos, que es su lugar. Ofrecido como atajo listo aparecía en la lista de apps al crear la automatización, y elegirlo ahí la guardaba sin importe.

## 2026-10-15 — En qué se va
- **Vuelve el desglose por categoría, dentro del ticket del presupuesto**: las tres categorías más grandes del mes como porcentaje de lo gastado (moneda principal), con una raya latón proporcional. Revierte en parte el «se quita la vista de categorías» del 2026-10-12: sin pantalla ni página propia, en el espacio que ya existía. Las devoluciones no cuentan para los porcentajes; si nada tiene categoría, no se muestra.

## 2026-10-15 — Guía para iOS 27
- **La guía muestra los pasos de la versión de iOS del teléfono**: iOS 27 arma la automatización en el editor (Biblioteca → Automatización → «+» → «Editor» → categoría «Automatización» → «Wallet»). Verificado en el simulador de iOS 27 es-MX.
- **En iOS 27 «Entrada de atajo» no es el pago** (agrega un bloque «Recibir… de Ningún lado»); la guía pide conectar la variable del bloque de Wallet. Esa última parte no se pudo ver en el simulador (no tiene tarjetas) y se confirma en el teléfono.

## 2026-10-16 — Monedas
- **Hay moneda principal elegible: pesos, dólares o euros** (menú «Más» → «Moneda principal»). Por omisión, la de la región si es una de esas tres; si no, pesos. Reemplaza «No hay ajuste de moneda» del 2026-10-11: el dueño quiere pesos sin depender de cómo esté la región del teléfono.
- **Al anotar se elige la moneda con un selector MXN | USD | EUR.** El teclado de montos es numérico: la pista anterior («escribe USD 20») era imposible de seguir.
- **Lo anotado a mano se guarda con su código ISO, nunca con «$»**, para que no cambie de moneda si después se cambia la principal. Lo que llega de Wallet con «$» sigue significando la moneda principal.
- **Siri entiende «dólares», «euros» y «pesos».**
- **Anotar desde los avisos del banco queda como idea (CEN-58), no se hace por ahora:** la captura no supone integración con bancos de México.

## 2026-10-16 — Hoy puedes gastar
- **El presupuesto dice cuánto puedes gastar hoy:** lo que queda repartido entre los días que faltan, hoy incluido, redondeado hacia abajo (es peor prometer un peso de más). También lo dicen el aviso de cada pago y Siri («Te quedan $X del presupuesto: $345 al día»). No aparece si ya te pasaste ni en meses cerrados.
- **La marca de la barra se llama «Ritmo»** (antes «Hoy»): es lo que llevarías gastando parejo a estas alturas, y junto a «Hoy puedes gastar» se confundía.

## 2026-10-16 — Gastos fijos
- **Un gasto puede repetirse cada mes** (interruptor «Se repite cada mes» en la hoja). La copia se anota sola el mismo día del mes, o el último si el mes es más corto, en cuanto ese día llega; se revisa al abrir la app y antes de cada aviso de Wallet y de Siri.
- **Esquema:** tres propiedades opcionales en `Expense` (`repeatsMonthly`, `repeatsThrough`, `isRepeat`), migración ligera y compatible con iCloud. Se decide sin consulta previa porque el dueño dio carta blanca el 2026-10-16.
- **Al activarlo empieza a contar desde ahora:** marcar un gasto viejo no rellena meses pasados (podrían estar anotados a mano). Una copia borrada no regresa. Las copias se ven con «Fijo» y no generan más copias.

## 2026-10-17 — Guía animada
- **Cada paso de la guía de iOS 27 es una animación de sus toques**, uno por uno con subtítulo, en bucle (quieta y desplegada con «Reducir movimiento»). El dueño no pudo seguirla con dibujos fijos.
- **Fuente: la pantalla real del iPhone del dueño (iOS 27).** La burbuja del pago se llama «Transacción»; al tocarla, «Obtener» ofrece Transacción, Tarjeta o pase, Comercio, **Cantidad** y Nombre. El monto es «Cantidad».

## 2026-10-17 — Se llama «Al día»
- **El nombre definitivo es «Al día»** (antes «Centavo», provisional). Elegido por el dueño entre cinco opciones: va con «Hoy puedes gastar» y con lo que hace la app, tenerte al día con tu dinero.
- **Ícono:** la cuadrícula de días del mes con el de hoy en latón y días anteriores en tonos de latón, sobre el papel casi negro.
- **Solo cambia lo que se ve:** nombre en el iPhone, textos, Siri («anotar gasto en Al día»), CSV («AlDia-fecha.csv»). El identificador `com.blandisc.centavo`, el repo, el código y el tablero siguen como «Centavo»: cambiar el identificador haría que el iPhone lo tomara como otra app y se perderían gastos y automatizaciones.

## 2026-10-17 — Capturar desde la notificación de Wallet
- **En iOS 27 la captura usa el disparador «Notificación» sobre la app Wallet**, con la acción nueva «Registrar aviso de Wallet». Wallet manda una notificación por compra, en línea o sin contacto (lo confirmó el dueño), así que una sola automatización cubre ambas; el disparador «Wallet» solo dispara con pagos sin contacto. En iOS 26 sigue la guía con «Wallet».
- **No es integración con bancos** (eso sigue fuera, CEN-58): la notificación es de Wallet. Formato visto en el iPhone del dueño: título = tarjeta («American Express México»), luego comercio («Google») y monto con moneda («MXN 319.00»). `WalletNotice` lo lee por renglones, venga junto o separado.
- **Un aviso de Wallet que no es compra** (pase de abordar, Apple Cash sin monto) se ignora sin error.
- **La guía pide borrar la automatización vieja de «Wallet»** para que cada compra se anote una vez.
- Verificado en el simulador de iOS 27: «Al recibir una notificación de [App]» → Wallet; el campo «Notificación» de la acción no se conecta solo. Sin verificar (no hay notificaciones reales en el simulador): la burbuja «Notificación» arriba del teclado; la guía da la alternativa «Seleccionar variable».

## 2026-10-18 — El número del día al frente
- **En el mes actual, con presupuesto y sin pasarte, lo más grande de la pantalla es «Hoy puedes gastar $X»**, en latón; el total del mes queda en la línea de abajo. Sin presupuesto, pasado del presupuesto o en meses cerrados, el total sigue arriba como antes. El presupuesto ya no repite «Hoy puedes gastar».
- **«Probar ahora» en la guía se descarta:** Al día no puede fabricar una notificación de Wallet, así que un botón de prueba no comprobaría la automatización y daría falsa confianza.

## 2026-10-18 — Importar CSV
- **«Más» → «Importar CSV» carga el mismo archivo que exporta la app**, para recuperar gastos sin iCloud. Columnas por nombre (Fecha, Comercio, Monto, Moneda obligatorias; Tarjeta y Categoría opcionales), así que un archivo reordenado en una hoja de cálculo sirve.
- **No duplica:** mismo segundo, monto y comercio (sin mayúsculas ni acentos) se toma como el mismo gasto. Renglones ilegibles se cuentan y se avisan, nunca se adivinan. Un CSV que no es de Al día se rechaza con explicación.

## 2026-10-18 — Tocar un día y deshacer
- **Tocar un día del calendario filtra la lista a ese día**, con «Día 12 · 2 gastos · Ver todo el mes» arriba; se limpia al cambiar de mes. Sin pantalla nueva.
- **Después de borrar un gasto aparece «Deshacer» seis segundos** (desde la lista o desde la hoja), y lo regresa igual que estaba, con su categoría y si era fijo. La barra usa Liquid Glass en iOS 26+.

## 2026-10-18 — Animaciones y hápticos
- **Con intención y pocas:** la barra del presupuesto crece hasta el nuevo gasto con un resorte corto; las cifras grandes cambian con transición numérica; vibración de éxito al entrar un gasto y de advertencia al pasarte del presupuesto en el mes actual. Con «Reducir movimiento» no hay animaciones.

## 2026-10-18 — Categorías sugeridas
- **Un comercio que nunca categorizaste recibe una categoría sugerida** de un catálogo de marcas comunes en México (Oxxo → Despensa, Uber → Transporte, Uber Eats → Comida, Netflix → Suscripciones, CFE → Servicios…). Lo que tú elegiste para ese comercio siempre manda.
- **Marca como palabras completas dentro del nombre** («OXXO ROBLE MTY 1234» es Oxxo; «Boxxon» no). No contradice la regla de 2026-10-11 de no adivinar que dos sucursales son el mismo comercio: aquí no se unen comercios, solo se propone una categoría que se puede cambiar. Se dejaron fuera palabras ambiguas como «Max».
- La hoja de gasto dice «Sugerida para Oxxo: Despensa. Cámbiala si no te queda.»

## 2026-10-18 — Primera vez guiada
- **Al abrir la app vacía por primera vez, cinco pantallas cortas:** qué hace, moneda, presupuesto, gastos fijos (nombre, monto y día del mes) y conectar Wallet (lleva a la guía). Todas se pueden omitir; lo llenado se guarda aunque se omita el resto.
- **Solo una vez y solo sin gastos:** quien ya tiene gastos no la ve (se marca como vista sin mostrarla). Los modos de prueba la saltan salvo `-centavo-onboarding`.
- **Un gasto fijo del día que aún no llega empieza el mes pasado** (`RecurringSchedule.firstDate`), para que la copia de este mes se anote sola ese día y nada quede con fecha futura.
- **El teclado numérico tapa la barra de abajo:** las pantallas con monto llevan «Siguiente» arriba del teclado.
## 2026-10-18 — CI más rápida
- **En un PR no corren las pruebas de capturas** (`ScreenshotTests`): solo sirven para ver el diseño y no deciden el merge. Corren cuando algo entra a `main`, que sigue publicando el artefacto `capturas`. Las de flujo, accesibilidad y unitarias siguen bloqueando cada PR.
- **Tampoco corren en un PR las auditorías de accesibilidad que solo informan**; la de zonas táctiles, que sí bloquea, sigue. Con 46 pruebas, un PR tardaba casi media hora en las máquinas de GitHub, sobre todo por abrir la app en cada prueba.
- Se probó correr en dos simuladores a la vez: en los runners de GitHub el segundo se desconectó y casi no hubo ahorro, así que se quitó.

## 2026-10-18 · Pruebas de interfaz sin animaciones
Las pruebas de flujo abren la app con `-centavo-sin-animaciones` (solo en Debug): XCTest espera a que cada animación termine y sin ellas cada paso es más corto (medido: 326 s → 205 s en seis pruebas). Las capturas siguen con animaciones. La prueba de 5,000 gastos mide tiempos y solo se lee comparando corridas, así que corre en main y no en los PR.

## 2026-10-18 · Avisos de Wallet que no son gasto y día de los fijos
- Un aviso de Wallet con «reembolso», «devolución», «reverso» o «cancelado» se anota en negativo (resta); uno de dinero recibido («recibiste», «te enviaron») no se anota. El texto exacto de Wallet para estos casos no está verificado en un iPhone real; si llega distinto, se ajustan las palabras.
- Un gasto fijo guarda el día que se pidió (`repeatDay`, opcional: migración ligera y compatible con CloudKit). Antes, un fijo del 31 que empezaba en un mes de 30 días se quedaba en el 30 para siempre.
- Las copias de un fijo se anotan una por comercio, monto y mes, aunque dos iPhones con el mismo iCloud las generen a la vez.

## 2026-10-18 · La moneda principal sale de los pagos, no de la región
Antes, sin elección explícita, la moneda principal era la de la región del iPhone; una región de EE. UU. dejó el presupuesto en dólares con todos los pagos de Wallet en pesos. Ahora: lo elegido (bienvenida o «Más»); si no hay, la moneda de la mayoría de los pagos; si no, pesos. Se fija una vez y no vuelve a moverse sola. Si la mayoría de los pagos del mes está en otra moneda ofrecida, se sugiere cambiar con un toque (y se pregunta por el presupuesto). El dinero se formatea con la convención de México en cualquier región.

## 2026-10-19 · Tarjetas y categorías propias
A pedido del dueño: una pantalla nueva en «Más» (Tarjetas y categorías) con las fuentes de pago (nombre, ícono, una predeterminada) y categorías propias (nombre, ícono). Se guardan como JSON en los mismos ajustes que el presupuesto y se sincronizan igual (`BudgetSync`); los gastos siguen guardando solo el nombre, así que borrar una no toca gastos. La predeterminada solo aplica a lo anotado a mano: lo de Wallet trae su propia tarjeta.

## 2026-10-19 · La guía de iOS 27 usa capturas reales
Las imágenes de la guía salen de `GuideScreenshotsTests`, que recorre Atajos de verdad en un simulador recién borrado (es-MX, oscuro) y guarda cada pantalla; un script les dibuja el aro de latón. Cuando Apple cambie Atajos se vuelven a sacar con `TEST_RUNNER_CENTAVO_GUIA=1`. En iOS 27 el «+» abre el editor directo o «Describir un atajo» (con Apple Intelligence; se sale con «Editar»), y la automatización queda con «Automatización» encendida y «Notificar» apagado: corre sin preguntar.

## 2026-10-19 · Dos capas: la manual y la del modelo local
Decisión del dueño después del spike (`docs/research/modelo-local.md`).
- **Dos capas.** Todo lo nuevo funciona primero con reglas en `CentavoCore`, en cualquier iPhone: nombres legibles, anotar con una frase, avisos del mes, búsqueda y «¿Cuánto llevo en Café?». Con iOS 26 o posterior y Apple Intelligence encendido, el modelo del iPhone mejora lo que necesita leer lenguaje. Sin él no aparece nada nuevo ni ningún aviso de «actualiza».
- **Solo en el iPhone.** Se usa el modelo on-device de Foundation Models; **no** Private Cloud Compute ni modelos en la nube, porque son red y la regla del 2026-10-15 dice que la app no hace llamadas por su cuenta.
- **El modelo no suma ni inventa.** Elige de una lista (tus categorías o «Ninguna»), copia las palabras que se dijeron o redacta un hecho ya calculado. `CentavoCore` revisa todo antes de tocar un gasto: el nombre nuevo tiene que ser el mismo comercio (`MerchantName.isFaithful`), la categoría tiene que estar en la lista, el monto tiene que estar literal en lo dicho y una nota no puede traer cifras que la app no calculó (`FactCheck`).
- **Esquema: dos propiedades opcionales en `Expense`**, `displayName` y `categorySource`. Migración ligera y compatible con iCloud. Aprobado por el dueño.
- **El nombre legible es solo para mostrar.** El CSV, la memoria por comercio y los repetidos usan el nombre que mandó Wallet; dos sucursales siguen siendo dos comercios. El modelo solo renombra lo que llegó de Wallet, nunca un nombre que alguien escribió.
- **Una categoría sugerida no es memoria.** Se ve igual, la hoja dice que es sugerida y no cuenta como «lo que elegiste» para el siguiente pago. Elegir otra la vuelve tuya; quitarla la deja sin categoría y no se vuelve a sugerir. El CSV no exporta sugerencias sin confirmar, para que al importarlo no parezcan elecciones.
- **Un nombre que escribes es el que se ve**, y el modelo ya no lo toca. Las marcas conocidas tampoco se reescriben.
- **No corre durante la captura de Wallet**, que es en segundo plano y donde Apple raciona el modelo: los comercios se revisan al abrir la app, ocho a la vez. Única excepción: un aviso de Wallet con monto que el lector no entendió.
- **Siri en dos pasos:** «Anota esto en Al día» y luego la frase. Apple no deja texto libre en la frase que arranca Siri.
- **La foto del ticket se pospone** (decisión del dueño).
- **La búsqueda es el campo nativo** que aparece al bajar la lista, y busca en todos los meses.
- **La nota del mes** es la última línea del ticket del presupuesto, solo en el mes actual.

## 2026-10-19 · El simulador no frena los PR
Decisión del dueño (opción 2 de tres): en un PR solo corren el build y las pruebas unitarias (unos 2 min). Las pruebas de interfaz en el simulador (flujos, zonas táctiles y capturas, unos 25 min) corren en cada push a `main`, a mano («Run workflow») y en un PR solo si lleva la etiqueta `ci-app`. Revierte la regla del 2026-10-13 de que las pruebas de interfaz corran y bloqueen cada PR. A cambio, un error de pantalla puede llegar a `main`: se ve en la corrida de `main` y se arregla ahí. Un PR que toca pantallas o flujos lleva `ci-app`.

## 2026-10-19 · Gastos fijos con cualquier frecuencia, y lo que falta se aparta
Decisión del dueño.
- **Frecuencias:** cada N semanas (el día de la semana del primer cobro), cada quincena (15 y último día) y cada N meses (el día del primer cobro, o el último en meses más cortos). Lo mensual se queda exactamente como estaba.
- **Un fijo solo cuenta el día que llega:** la copia se anota sola ese día, nunca antes, como ya pasaba con lo mensual.
- **Lo que falta del mes se aparta de «Hoy puedes gastar»** (opción «apartar» de tres). «Te quedan» no cambia, porque el fijo todavía no se gasta; solo baja lo que puedes gastar al día. El ticket dice «Fijos por venir · $X», y el aviso de Wallet y Siri también lo descuentan.
- **«Más › Gastos fijos»:** la lista con frecuencia, próximo cobro y lo que llegó y lo que falta este mes; agregar, cambiar (abre la hoja del gasto) y dejar de repetir (lo ya anotado se queda).
- **Un fijo cuyo primer cobro todavía no llega** espera en los ajustes sincronizados (`FixedPlan`, como el presupuesto) y se vuelve gasto ese día: nada en la base tiene fecha futura. Ya se aparta si cae en el mes.
- **Esquema:** `Expense.repeatRule` (opcional; `nil` es mensual, así que los fijos de antes no cambian). Migración ligera, compatible con iCloud. `repeatsMonthly` conserva su nombre y significa «se repite».
- **Las copias se cuentan una por día** para lo que se repite más seguido que cada mes (dos lunes del mismo mes son dos cobros); lo mensual sigue en una por mes.


## 2026-10-20 · Sin modelo de IA por ahora
Se quitó el modelo local de Apple Intelligence (nombres legibles por modelo, categorías, nota del mes reescrita, frase, búsqueda y Siri por significado). Medido en el iPhone del dueño: 15/33 categorías bien, «Compras» como cajón de sastre y nunca «Ninguna». Todo sigue funcionando con las reglas normales de CentavoCore (frase, búsqueda, avisos, nombres legibles). Se puede volver a evaluar con otra versión del modelo; la prueba («Probar el modelo») se quitó con él.

## 2026-10-20 · Dónde se pagó
A pedido del dueño, cada gasto puede guardar dónde estaba el iPhone al anotarse (interruptor «Guardar dónde pagas» en «Más», con permiso de ubicación «Al usar la app»). Wallet guarda la ubicación de cada cargo pero no se la da a Atajos, así que es la del iPhone: exacta en tiendas, la tuya en compras en línea. El detalle del gasto muestra un mapa y el nombre del lugar; el mapa y el nombre los da Apple (MapKit/CLGeocoder), igual que en Wallet: no hay servidor propio. Latitud, longitud y nombre son opcionales y viajan por iCloud como el resto.

## 2026-10-20 · El simulador de la CI solo corre al entrar a `main`
Decisión del dueño: en un PR solo corre «Pruebas y build» y eso decide el merge. Las pruebas de interfaz en el simulador (unos 25 min) corren en cada push a `main` y a mano («Run workflow»), nunca en un PR; desaparece la etiqueta `ci-app`. Motivo: un merge esperó horas por corridas lentas o atoradas del simulador. A cambio, quien hace un PR que toca pantallas corre las pruebas de interfaz en su simulador local, y un error que solo aparezca en la CI se ve en la corrida de `main` y se arregla ahí.

## 2026-10-21 · El banco se reconoce por su nombre
Tercera vez que un aviso de Wallet guardaba el banco como comercio: adivinar por la posición de los renglones falla en cuanto Atajos o el banco agregan uno («Ahora», la hora) o cambian el orden. Ahora `WalletNotice` reconoce la tarjeta por su nombre: una lista de bancos y emisores de México, palabras de tarjeta («crédito», «•••• 1234») y las tarjetas que la persona dio de alta. Esa línea nunca es el comercio; la posición solo decide entre las que quedan. Si un banco nuevo no está en la lista, se agrega ahí. Los gastos de Wallet guardados con el banco como comercio se vuelven a leer de su aviso original al abrir la app; un nombre escrito a mano no se toca.

## 2026-10-21 · «En qué se va» con colores, en barra o mosaico
A pedido del dueño: todo en latón no se distinguía.
- **Cuatro colores para las cuatro categorías más grandes, y «Otras» en gris.** Con cinco, siempre hubo dos que se confundían en el papel oscuro (azul y violeta, medido con visión normal y con daltonismo). Ocre, verde, azul y rosa (`Theme.categories`); con daltonismo rojo-verde el rosa y el verde quedan cerca, por eso el nombre va siempre escrito. El color sigue el lugar en el mes (la más grande es ocre), no la categoría: con cuatro colores no alcanza para darle uno fijo a cada categoría.
- **Dos maneras o ninguna, a elegir en «Más»** (un ajuste, no una pantalla; «No mostrar» deja la página del presupuesto solo con la barra del mes): **Barra**, una barra al 100 % con un renglón por categoría (ícono en su color, monto, porcentaje), y **Mosaico**, un bloque por categoría del tamaño de lo gastado (treemap «squarified», `ShareMosaic`). Por omisión, Barra.
- **En el mosaico cada bloque se puede tocar (44 pt) y muestra lo que cabe:** completo, en una línea, el nombre en vertical si es angosto y alto, o solo el ícono. Un bloque muy chico se dibuja un poco más grande de lo que le toca para poder tocarlo; el monto escrito es el real.
- **Tocar un bloque filtra la lista** a esa categoría («Ropa · 2 gastos · Ver todo el mes»), como tocar un día del calendario; elegir uno quita el otro.
- **El carrusel mide lo que la página que se ve, y la pantalla principal ya no es un `List`.** Medido cuadro por cuadro en video: dentro de un `List`, el renglón del carrusel tomaba su alto nuevo de golpe (171 pt en un cuadro) mientras su contenido sí se animaba, y eso era el brinco y el baile, con cualquier animación que se probara (#77, #81). Ahora la pantalla es un `ScrollView` con `LazyVStack`: el alto y la lista se mueven en la misma animación (1–14 pt por cuadro). Entre páginas, el carrusel tiene el alto de la más alta; al llegar a una (a un décimo de ella), el suyo, en 0.45 s. No depende de la dirección del dedo (decidir por dirección se invertía a la mitad y la lista bajaba, subía y bajaba). Recorta lo que sobra para que nada se encime en la lista. Con «Reducir movimiento», sin animación.
- **Deslizar para borrar se hace a mano** (`SwipeToDelete`), porque `.swipeActions` solo existe en `List`: deslizar muestra «Borrar»; hasta el fondo, pide confirmar; tocar el renglón o mover la lista lo cierra; VoiceOver tiene la acción «Borrar». Mantener presionado sigue ofreciendo «Borrar gasto».

## 2026-10-21 · Confirmar el borrado con una hoja propia
A pedido del dueño, «¿Borrar este gasto?» deja el diálogo del sistema (en iOS 26 sale como globo arriba, lejos del dedo y en gris) por una hoja chica que sube desde abajo, del alto de su contenido, con el estilo «Noche ticket»: el gasto que se va a borrar, «Borrar» en `Theme.danger` y «Conservar». Sigue siendo una hoja del sistema (`sheet` con `presentationDetents`), así que respeta Dynamic Type y VoiceOver. Mantiene la confirmación del 2026-10-13 y el «Deshacer» del 2026-10-18.

## 2026-10-21 · El comercio viene del subtítulo
Visto en el iPhone del dueño (texto guardado de cada captura): Atajos convierte la notificación de Wallet en texto con título y cuerpo, **sin el subtítulo**, y ahí va el comercio («American Express México · MXN 205.00» por un viaje en Didi). Ningún lector podía sacar un comercio que no llegaba. «Registrar aviso de Wallet» suma el parámetro opcional «Comercio», que se conecta a Notificación › Subtítulo (Atajos lo ofrece al tocar la burbuja); se agrega después del monto y lo lee `WalletNotice` como el concepto. Las automatizaciones sin él siguen funcionando como antes.

## 2026-10-21 · El aviso de Wallet ya no dice el presupuesto
Decisión del dueño: el aviso de Atajos al anotar un pago de Wallet dice solo «Anotado: $X en Comercio.». Revierte «Aviso al pagar» del 2026-10-15. Siri («Anotar gasto», «Anota esto») lo sigue diciendo.
- **Un aviso de una línea sin monto se guarda y la pantalla principal lo dice** («Wallet · llegó «Didi Mobility Mexico» sin monto · Revisar el atajo»): es la señal de que el campo «Notificación» quedó como «Subtítulo» (pasó en el iPhone del dueño y el pago se perdió en silencio). Un pase o una promoción traen título y cuerpo, así que no cuentan.

## 2026-10-22 · «Hoy puedes gastar»: el mismo gráfico, cinco cifras en su lugar
Decisión del dueño (opción A de tres, después de probar una versión sin números en el veredicto, que no quiso). Se queda la barra de siempre (latón, apartado para fijos, rayado, rayita, un cuadrito por día) y contesta con número cinco preguntas: cuánto hoy, cómo voy («Vas $3,311 abajo de lo que podrías llevar»), cuánto podría llevar a hoy (sobre la rayita), cuánto llevo (bajo el latón) y el presupuesto (al final de la barra). «Esperado» se dice «podrías llevar». «Te quedan» y «Apartado para fijos» pasan a la cuenta que sale al tocar la barra.
- **Anotar un pago de Wallet no muestra nada:** cualquier diálogo, aun vacío, hacía que Atajos abriera una hoja con «Listo» después de cada compra.

## 2026-10-22 · Borrar tarjetas y categorías, y ocultar las de siempre
A pedido del dueño. «Borrar» va también en la hoja de editar (deslizar no se descubre). Las categorías de la app y las ya usadas no se borran: se ocultan del selector al anotar (`hiddenCategories`, sincronizado como el resto de los ajustes). Un gasto que ya tiene una categoría oculta la sigue mostrando, y al editarlo aparece en el selector.

## 2026-10-23 · Recordar mi categoría: gana tu última elección
Afina la memoria por comercio del 2026-10-11. El historial dice en qué categoría está cada gasto, pero no *cuándo* se decidió: corregir el Oxxo del mes pasado perdía contra el Oxxo de esta semana, que solo tenía la categoría porque la memoria se la puso.
- **Cada elección a mano se anota** (`CategoryRules`, en `CentavoCore`): comercio → la última categoría que elegiste en la hoja, o «ninguna» si se la quitaste. Gana la más reciente, sin importar la fecha del gasto. Es una lista chica (una entrada por comercio, máximo 1,000) que se guarda y sincroniza con los demás ajustes (`categoryRules` en `BudgetSync`), no una propiedad nueva de `Expense`: el esquema no cambia.
- **Sin elección anotada, manda el historial** como antes (para lo archivado antes de esto); luego el catálogo de marcas. Quitar la categoría también es una decisión: ese comercio ya no recibe ni la memoria ni el catálogo.
- **El comercio se compara sin mayúsculas, acentos ni espacios de más** (`MerchantKey`), también entre palabras («OXXO  ROBLE» es «Oxxo Roble»). Los números siguen contando: dos sucursales son dos comercios. «Sin comercio» no se recuerda.
- **Solo gastos nuevos:** lo de Wallet, Siri, la hoja a mano (que ya se llenaba sola) e «Importar CSV» en las filas sin categoría; una fila con categoría la conserva, y la importación no usa el catálogo (una categoría vacía en el archivo puede ser a propósito). Nunca se recategoriza un gasto guardado.
- **Una categoría oculta o borrada no se pone sola**, aunque haya sido tu elección; ese comercio cae al catálogo. Borrar una categoría propia **no** la oculta del selector (decisión del dueño): si algún gasto la usa, sigue apareciendo como antes. Para saber que se borró se anota aparte (`deletedCategories`, sincronizado con los demás ajustes), y solo la memoria por comercio lo consulta; crearla otra vez con el mismo nombre la quita de esa lista. Renombrarla mueve sus comercios al nombre nuevo.

## 2026-10-23 · Montos: ante la duda, rechazar antes que inflar
Hallazgos de una revisión adversarial (probados en 97421b3). Regla general: **un monto dudoso se rechaza, nunca se lee más grande en silencio**. Lo rechazado en la captura de Wallet hace fallar la acción como antes; a mano, el botón de guardar no se habilita.
- **Un grupo de tres solo es grupo si puede serlo.** `1.234` y `1,000` siguen siendo miles (decisión del 2026-10-13), pero `0.005`, `0,005` y `.500` se rechazan: un cero no lleva separador de miles. Con dos separadores distintos el último es el decimal (la regla del último separador), así que `$1,234.567` tiene tres decimales, no son centavos y se rechaza; antes daba 1,234,567. Se eligió rechazar y no truncar a 1,234.56 porque tres decimales no los manda Wallet y adivinar podría equivocarse en cualquier sentido.
- **Los grupos de miles son de dos o tres dígitos** (`1,234,567`, también `1,23,456` de la India). Un grupo de uno (`1.2.3`, `1,2.3`) no es un número y se rechaza.
- **La moneda va a un lado del número, nunca en medio:** `1e5`, `1.5e2` o `50ht1` se rechazan. Un espacio o un salto de línea nunca son moneda (`50\n.00` es 50 sin moneda), y un `+` es un signo, no una moneda: `+50` es 50 y `+-50` se rechaza.
- **En la captura, unas mayúsculas que no son un código ISO no son moneda** (`BBVA 1234`, `NU 1234`, `HSBC 4321`, `AMEX 1005` no son un monto), igual que ya pasaba entre más texto: sin cifra con moneda no hay monto. Un código real (`CAD 99.99`) o un símbolo con letras (`Bs. 50`) siguen como antes.
- **Un espacio agrupa miles solo si le siguen exactamente tres dígitos en el mismo renglón** (`1 234,56 €`). Así los cuatro últimos de la tarjeta después del monto (`$89.00 1234`, aun en otro renglón) ya no se pegan al monto y se encuentra $89.00.
- No cambia: una moneda desconocida se guarda aparte, `$-20` es un reembolso, un número solo (`89.00`, `1234`) es un monto cuando el texto es solo eso, y el último separador define los centavos.

## 2026-10-23 · «En qué se va» con letra de accesibilidad
Con los tamaños de accesibilidad (`dynamicTypeSize.isAccessibilitySize`), la Barra apila cada renglón: ícono y nombre arriba, monto y porcentaje abajo (o uno bajo otro si no caben), y el encabezado pone el total bajo «En qué se va». Antes se cortaban los montos («$2,3…») y desaparecían los nombres. En los tamaños normales se ve igual que antes. Mismo patrón que los renglones de la lista de gastos.

## 2026-10-22 · Lo de hoy sale de hoy; «Te quedan» y «En qué se va» cuadran
Arreglos de la auditoría de sumas (`docs/research/2026-10-22-auditoria-sumas.md`, #3, #4 y #5).
- **«Hoy puedes gastar» = (presupuesto − fijos por venir − lo gastado antes de hoy) ÷ días que faltan (hoy incluido) − lo gastado hoy**, redondeado hacia abajo y nunca menos de cero. Precisa la regla del 2026-10-16: antes lo de hoy se repartía entre los días que faltan y la cifra casi no bajaba al pagar ($630 → gasto $630 → $567). Mañana se recalcula con todo lo gastado hasta hoy. Lo mismo en la pantalla, la cuenta de la barra, la hoja del presupuesto y Siri. Una devolución de hoy regresa a hoy.
- **Siri dice lo libre y lo apartado:** «Te quedan $X libres (más $Y apartados para fijos). Hoy puedes gastar $Z.»; sin fijos por venir, «Te quedan $X del presupuesto». Cambia «Te quedan» del 2026-10-19 («no cambia, porque el fijo todavía no se gasta») para Siri: decir el total sin apartar junto a una cifra por día que sí aparta no cuadraba. Se dice «Hoy puedes gastar» en vez de «al día» porque, con lo de hoy restado, la cifra es de hoy, no de cada día.
- **«En qué se va» suma lo mismo que «Llevas».** Los porcentajes siguen sin contar devoluciones (2026-10-15), pero arriba va el total del mes y, si una categoría quedó en negativo, la diferencia se ve en «Menos devoluciones». Una categoría se compara sin espacios a los lados, igual al sumar que al filtrar.

## 2026-10-22 · «Hoy puedes gastar»: lo que sobra o falta pasa completo al día siguiente
Decisión del dueño. Reemplaza la fórmula de «Lo de hoy sale de hoy» (mismo día) y el reparto entre los días que faltan del 2026-10-16.
- **Monto por día = (presupuesto − fijos del mes) ÷ días del mes.** «Fijos del mes» son los que ya llegaron este mes más los que faltan (los que antes solo se apartaban). Se eligió esta base, y no «lo que queda ÷ días que faltan», porque es fija todo el mes: así un día que gasta de más o de menos mueve solo al siguiente, que es lo que pidió el dueño.
- **Hoy puedes gastar = monto por día × días transcurridos (hoy incluido) − lo gastado antes de hoy − lo gastado hoy**, sin contar fijos en lo gastado (ya salieron del monto por día), redondeado hacia abajo. **Puede ser negativo:** la pantalla dice «Hoy te pasaste $X» en rojo, Siri «Hoy ya te pasaste por $X», la pantalla bloqueada «−$X». Con $700 al día: el día 1 gastas $300 → el día 2 puedes $1,100; el día 2 gastas $1,500 → el día 3 puedes $300.
- **«Vas $X abajo/arriba del ritmo» = lo que sobró (o faltó) de los días anteriores**, lo que hoy recibe además de su monto. No cuenta lo de hoy para no repetir la cifra grande. El día 1 dice «Día 1 de 31 · mes nuevo». «Podrías llevar» (la rayita) = fijos ya cobrados + monto por día × días transcurridos; lo rayado entre lo gastado y la rayita es justo lo que puedes gastar hoy.
- **La cuenta al tocar la barra:** Presupuesto − Llevas = Te quedan; luego Presupuesto − Fijos del mes ÷ Días del mes = Por día, + Sobró (o − Te pasaste) de otros días, − Gastado hoy = Hoy puedes gastar.
- **Una sola cuenta:** `BudgetPace` (CentavoCore) con las entradas que arma `TodayBudget` (app): pantalla, barra, hoja del presupuesto, Siri y widgets.

## 2026-10-22 · Widgets
Decisión del dueño, sobre las propuestas de `docs/research/widgets-propuestas/`.
- **Cuatro formas, en tres widgets de la galería:** «Hoy puedes gastar» en pequeño (propuesta A) y mediano (propuesta A, con «+» que abre «Anotar gasto»); «Hoy y en qué se va» en mediano (propuesta B: las tres categorías más grandes con sus colores y «Otras» en gris); y en la pantalla bloqueada el círculo (anillo de lo gastado hoy contra lo que podías gastar hoy, con la cifra o «−$X»), el rectangular de la propuesta A y la línea junto a la fecha («Al día $190 hoy»). Las dos variantes del mediano son dos widgets distintos en la galería: se elige al agregarlo, sin pantalla de ajustes.
- **El widget no abre la base de datos.** Después de cada cambio (guardar desde la app, Siri o Atajos, que corren dentro de la app; cambiar presupuesto, fijos o moneda; abrir la app) la app escribe las sumas del mes (`WidgetSnapshot`) en un App Group y recarga los widgets. El widget calcula «Hoy puedes gastar» con el mismo `BudgetPace` para cualquier momento: su línea de tiempo trae las siguientes dos medianoches, así que el día nuevo empieza solo. Si cambia el mes sin abrir la app, empieza en cero apartando los fijos del mes anterior (se repiten) hasta que la app cuente los reales. Mover la base al App Group se descartó: es migrar los datos de la persona por un widget.
- **App Group `group.com.blandisc.centavo`, extensión `com.blandisc.centavo.widgets`.** La cuenta gratuita sí firma App Groups (iCloud no): para el iPhone con cuenta gratuita se compila con `CODE_SIGN_ENTITLEMENTS=Centavo/CentavoGratis.entitlements`, que trae solo el App Group, en lugar del archivo vacío.
- **Estados:** sin presupuesto («Llevas en octubre $8,140», «hoy $84» y «Fijar presupuesto», que abre la hoja), te pasaste del mes (rojo, barra llena, sin «Hoy puedes gastar»), hoy te pasaste («Hoy te pasaste $X» en rojo; «−$X» en la bloqueada) y día 1 («Día 1 de 30 · mes nuevo»). En la pantalla bloqueada y en los modos tintado y transparente no hay latón ni rojo: el sistema pinta un solo tono, la cifra y la barra se marcan como lo importante (`widgetAccentable`) y lo demás va en opacidades, así la barra se entiende por su forma.
- **La pantalla bloqueada muestra cifras con el teléfono bloqueado,** como cualquier widget; iOS permite ocultarlas hasta desbloquear si la persona lo prefiere.

## 2026-10-23 · Widgets con la cuenta gratuita: llavero compartido si no hay App Group
`xcodebuild -allowProvisioningUpdates` con la cuenta gratuita (equipo `B7KRCF776Z`) genera perfiles con la lista de App Groups vacía, aun con un archivo de entitlements que solo pide `group.com.blandisc.centavo` (la firma falla: el perfil no coincide). Sin App Group el widget no ve nada y dice «Sin presupuesto».
- **El App Group sigue primero:** `WidgetSnapshotStore` (CentavoCore) lo usa cuando su contenedor existe (`FileManager.containerURL` no es nil). Sin el entitlement, `UserDefaults(suiteName:)` igual responde pero escribe en los ajustes propios del proceso, por eso se mira el contenedor y no la suite.
- **Si no hay App Group, un llavero compartido:** la app guarda el `WidgetSnapshot` en JSON como contraseña genérica (servicio `centavo.widget`, cuenta `snapshot`, legible después del primer desbloqueo, para dibujar con el teléfono bloqueado) en el grupo de llavero `TEAMID.com.blandisc.centavo.shared`, y el widget la lee. Los perfiles gratuitos permiten cualquier `TEAMID.*` sin registrarlo. El grupo llega a cada target con la clave `CentavoKeychainGroup` del Info.plist (`$(AppIdentifierPrefix)com.blandisc.centavo.shared`), que se resuelve al firmar.
- **`CentavoGratis.entitlements` ya no trae el App Group:** solo el grupo de llavero, y se usa para los dos targets (`CODE_SIGN_ENTITLEMENTS=Centavo/CentavoGratis.entitlements` en la línea de `xcodebuild` aplica a la app y a la extensión). Los entitlements normales traen los dos.
- La fecha de demostración de los widgets (solo DEBUG) sigue solo en el App Group.

## 2026-10-23 · «Hoy puedes gastar»: acumular o repartir, a elegir
Decisión del dueño. La hoja del presupuesto trae un selector con una línea de explicación bajo cada opción; se guarda junto con el monto (Cancelar no lo cambia) y se sincroniza por iCloud como el resto de los ajustes (`allowanceMode`).
- **«Acumular día a día»** (por defecto, y lo que vale si no hay nada guardado o llega un valor desconocido): la regla del 2026-10-22, lo que sobra o falta pasa completo al día siguiente.
- **«Repartir entre los días que quedan»**: la regla del PR #94 («Lo de hoy sale de hoy», 2026-10-22). Hoy puedes gastar = (presupuesto − fijos por venir − lo gastado antes de hoy) ÷ días que faltan (hoy incluido) − lo gastado hoy, redondeado hacia abajo y **nunca menos de cero**. Un fijo cobrado hoy cuenta como si se hubiera apartado al empezar el día: sale de lo que se reparte, no de lo de hoy. «Podrías llevar» es el presupuesto parejo entre los días del mes y «Vas $X abajo/arriba del ritmo» compara contra eso. La cuenta al tocar la barra dice Presupuesto − Llevas antes de hoy − Fijos por venir ÷ Días que faltan = Para hoy − Gastado hoy.
- **Una sola elección para todo:** `BudgetPace(mode:)` en CentavoCore; `TodayBudget` lee el modo guardado, así la pantalla, la barra, la hoja del presupuesto, Siri y los widgets dicen lo mismo. El modo viaja en el `WidgetSnapshot` (opcional: uno escrito antes se lee como «Acumular»), y al cambiarlo la app reescribe el snapshot y llama `WidgetCenter.reloadAllTimelines()`.

## 2026-10-23 · Un solo widget mediano, a elegir en «Editar widget»
Decisión del dueño. «Hoy puedes gastar» y «Hoy y en qué se va» en mediano eran dos widgets de la galería; ahora es uno.
- **`HoyWidget` pasa a `AppIntentConfiguration`** con `HoyConfiguration` (`WidgetConfigurationIntent`, definido en la extensión): un parámetro «Mostrar» con «Ritmo del presupuesto» (por defecto, la propuesta A) o «En qué se va» (la propuesta B). Se elige manteniendo presionado el widget › «Editar widget». El pequeño no tiene nada que elegir (`When(widgetFamily:)` oculta el parámetro) y se ve igual.
- **El `kind` sigue siendo `"Hoy"`:** los widgets pequeños y medianos ya puestos se quedan, con «Ritmo del presupuesto». El widget `"EnQueSeVa"` se quita de la galería; los que ya estaban puestos desaparecen y hay que poner el mediano otra vez y elegir «En qué se va».
- **Fila de abajo del pequeño:** solo «Llevas $X» (ticket 12 medium, mayúsculas, una línea, puede bajar a 80 %), sin «de $Y»: completo y legible (opción B de la maqueta). Gris la etiqueta y blanca la cifra.

## 2026-10-23 · Gastos que no cuentan
Aprobado por Fernando (alternativa A de tres y el cambio de esquema; propuesta en `centavo-gasto-cero/propuesta.md`). Un gasto que te reembolsan, una transferencia entre tus cuentas o lo que quieras dejar fuera se marca «No cuenta»: se queda en la lista con su monto real y no suma en ningún lado. Reemplaza el truco de anotar un negativo que lo compense.
- **Esquema: dos propiedades opcionales en `Expense`**, `countedAmount` (cuánto cuenta: `nil` todo, como cualquier gasto de antes; `0` nada) y `uncountedReason` (`reembolso`, `entre-cuentas` u `otro`, valores que no cambian). Migración ligera y compatible con iCloud; los gastos guardados se ven y suman exactamente igual. Se guarda una cantidad y no un sí/no para que «solo cuenta mi mitad» quepa después sin otro cambio de esquema (en CloudKit de producción un campo no se borra); por ahora no hay pantalla para una parte.
- **Una sola cuenta:** `CountedAmount.effective` (en `CentavoCore`) nunca cuenta más que el monto y respeta su signo. Todas las sumas pasan por `Expense.asAmount`, la única que arma un `ExpenseAmount`: la pantalla, Siri y los avisos no pueden dar cifras distintas.
- **Dónde no cuenta:** «Hoy puedes gastar» (lo gastado hoy y antes de hoy, en los dos modos: acumular y repartir), «Llevas», la barra, «En qué se va», el calendario (un día solo con eso se ve vacío), el total de cada día, Siri, los widgets (el `WidgetSnapshot` sale de `TodayBudget`, que también pasa por `Expense.asAmount`), lo apartado para fijos y la proyección y las categorías de la nota del mes. **Sí cuenta para el cobro doble:** un cargo doble es un problema aunque te lo paguen.
- **Se marca en la hoja del gasto** («Cuenta para el presupuesto», encendido por omisión; al apagarlo, «Motivo»: Me lo reembolsan, Entre mis cuentas u Otro) **o al mantener presionado el renglón** («No cuenta» / «Sí cuenta»). Desde el menú el motivo es «Me lo reembolsan», o el que tuvo antes: volver a contarlo no borra el motivo.
- **En la lista:** el monto tachado en gris (`Theme.muted`, no latón: el latón es dinero que regresa), el ícono en gris y «No cuenta · Me lo reembolsan» primero en la línea de abajo. VoiceOver dice «no cuenta para el presupuesto».
- **Nada desaparece sin explicación:** al tocar la barra, la cuenta agrega «Fuera del presupuesto · $X» si en el mes hay algo que no cuenta.
- **Gastos fijos:** las copias heredan la marca.
- **CSV:** el monto real y dos columnas nuevas, «Cuenta» (Sí/No) y «Motivo». Al importar, solo un «No» deja fuera; un CSV sin esas columnas cuenta todo.
- **Fuera por ahora:** reglas automáticas por tarjeta o comercio, un parámetro en el Atajo, la parte («mi mitad») y convertir las compensaciones ya anotadas.

## 2026-10-25 · Pendientes: «Deberías llevar», ritmo igual en los dos modos, nombres recordados
Pedidos del dueño.
- **«Deberías llevar»** sustituye a «Podrías llevar» cuando lo gastado pasa la rayita (`BudgetPace.isAheadOfPace`: `spent > expectedToDate`, la misma condición que pinta de rojo lo rayado). En la barra, el widget mediano y VoiceOver.
- **«Podrías llevar» no depende del modo:** siempre fijos cobrados + monto por día × días transcurridos.
- **«Vas $X del ritmo», alternativa C** (de tres, dibujadas en el tablero de pendientes con doce escenarios). La frase de antes (días anteriores, sin hoy y sin fijos) no cuadraba con la barra: decía «justo al ritmo» junto a «Deberías llevar» y «Hoy te pasaste», o «$4,000 abajo» con la barra mostrando $2,000. Con «Acumular», «Hoy puedes gastar» es exactamente rayita − llevas, así que la frase se quita y la barra sube a su lugar. Con «Repartir» se queda y mide lo mismo que la barra (`BudgetPace.rhythm` = rayita − llevas, hoy y fijos cobrados incluidos); aparece desplegándose bajo la cifra. Reemplaza la definición del 2026-10-22 para la frase y lo dicho el 2026-10-23 para «Repartir». La cuenta al tocar la barra sigue diciendo «Sobró de otros días» (`carriedOver`).
- **Widgets:** el pequeño y la columna de «En qué se va», con «Acumular», usan ese renglón para «Podrías/Deberías llevar $X», la etiqueta de la rayita que su barra no tiene; el mediano ya la lleva sobre la barra y deja la esquina libre.
- **Comercios renombrados (`MerchantRenames`, CentavoCore):** al cambiar el nombre en la hoja del gasto se guarda «nombre de Wallet → nombre tuyo» por `MerchantKey` (mayúsculas, acentos y espacios no cuentan; otra sucursal sí). `ExpenseRecorder.record` lo aplica antes de todo, así el comercio, el nombre que se ve, la categoría recordada y el filtro de repetidos usan el nombre nuevo. Renombrar dos veces lleva al último nombre; regresar al original lo olvida. Se guarda en la clave `merchantRenames` y se sincroniza como las demás (`BudgetSync`). Solo Wallet: lo que se dicta a Siri o se escribe se queda como se dijo. No cambia gastos ya guardados.

## 2026-10-26 · Pantalla principal: entrada una sola vez, filtros al instante, páginas de la misma altura
Revisión de espacios y movimiento del héroe («Hoy puedes gastar»), la barra del mes, el carrusel y «En qué se va».
- **La entrada (la cifra contando, la barra dibujándose) solo corre al abrir la app.** El estado vive en `Entrance` (lo guarda `ExpenseListView`), no en cada vista: la lista construye sus renglones de forma perezosa y una vista reconstruida (al bajar y volver, o al buscar y volver) empezaba de cero y repetía la animación. La parte de arriba (héroe, carrusel, filtros) ya no es perezosa; solo los días de abajo.
- **Tocar un día del calendario o un bloque del mosaico filtra la lista al instante** (`Theme.Motion.instantly`). Antes se animaba con `.snappy` (0.5 s): los renglones viejos se desvanecían encima de los nuevos y el filtro se corría debajo del calendario. Lo único que se anima es el aro o el tinte de lo tocado (`Theme.Motion.select`, 0.12 s).
- **Proximidad en el héroe:** «Hoy puedes gastar», la cifra y el veredicto son un grupo. Estaban tan separados entre sí (≈ 23–26 pt de aire) como una sección de la otra (≈ 23 pt), y nada se leía como unidad. `Theme.Space.heroTrim` quita el aire del interlineado de la cifra: ≈ 14 pt dentro del grupo (medido de tinta a tinta en el simulador; antes 22 y 17) y ≈ 26 pt entre secciones; el calendario abre con su propio título, 12 pt más abajo, porque no es parte del héroe.
- **Barra y mosaico miden lo mismo** (`Theme.Size.shareChartHeight`, 157 pt: la barra, su hueco y cinco renglones de 27), así que cambiar de uno a otro en «Más» no mueve la lista. **Con «En qué se va» visible, la página del presupuesto y la del calendario miden lo mismo** (la mayor de las dos): deslizar entre ellas no sube ni baja lo de abajo. Sin «En qué se va» (la página del presupuesto es solo la barra) cada página conserva su altura, o quedaría un hueco sobre la lista. **Cómo:** sin medir y volver a aplicar una altura. Con las dos páginas a la vista, el carrusel toma la altura de la fila de páginas, que ya es la de la más alta. Una altura medida y puesta de vuelta en la misma vista entraba en un ciclo y, en el iPhone del dueño, se quedó en la del calendario y cortó «Otras» (2026-10-26).
- **Cada bloque del mosaico muestra lo que de verdad cabe, nunca cortado** (sustituye lo del 2026-10-21 sobre «lo que cabe»): ícono, nombre, monto y porcentaje; o una sola línea; o solo ícono y nombre; o el nombre en vertical si es alto y angosto; o solo el ícono. Se decide midiendo el texto real (`ViewThatFits`) y no estimando su ancho: la estimación dejaba pasar nombres largos que se cortaban («ENTRETENIM…»). `ShareMosaic.fit` salió de `CentavoCore`.
- **Mantener presionado un bloque abre su detalle** (menú contextual nativo con vista previa: nombre completo, monto y porcentaje, más «Ver sus gastos» / «Ver todo el mes»). Un bloque chico puede mostrar solo el ícono para no cortar su nombre; el detalle es donde se lee todo. Tocar sigue filtrando la lista.
- **Sin «En qué se va», la altura del carrusel sigue al dedo** (sustituye lo de #77 de cambiarla una vez por deslizamiento). Con páginas de alturas distintas, la altura es la que hay entre las dos según cuánto se ha deslizado (o según la animación del puntito), así que el calendario sale como un ticket de la impresora, renglón por renglón, y llega completo. Mientras se mueve, el borde de abajo se desvanece (`Theme.Size.carouselFold`, 28 pt a medio camino; nada en reposo) en vez de cortarse. Se probó una perforación de ticket en el borde y el dueño prefirió el desvanecido (2026-10-26). Antes la altura corría con su propio reloj, terminaba después que la página y dejaba la última fila tapada un momento. Medido en video: cuadros parejos (~16 ms) mientras se desliza.
- **Los puntitos siguen al dedo:** la píldora encendida se angosta en la página que se deja y se ensancha en la que llega, al ritmo del deslizamiento. **Un toque háptico de selección** cuando la página se asienta en la otra; ninguno mientras se mueve ni si regresa. Elegidos por el dueño (2026-10-26) entre cuatro ideas; quedó fuera «los días se van imprimiendo».

## 2026-10-29 · Bienvenida en cuatro páginas y guía flotante
A pedido del dueño («un onboarding con las mejores prácticas, animaciones e interacciones, que te lleve de la mano», y explorar un video en picture in picture que acompañe la configuración del atajo). Análisis completo en `docs/research/analisis-ux-ui-tecnico-2026-10-29.md`.
- **Cuatro páginas en vez de cinco** (sustituye el «cinco pantallas cortas» del 2026-10-18): la moneda y el presupuesto van juntos («Tu mes»), con el mismo selector MXN | USD | EUR de la hoja de gasto. Todo se sigue pudiendo omitir y lo llenado se guarda.
- **La primera página es una demostración animada** (un aviso de Wallet que se vuelve renglón y baja «Hoy puedes gastar»), no una lista. Con «Reducir movimiento» se queda quieta.
- **La bienvenida enseña la cifra por día** (presupuesto menos fijos, entre los días del mes), no «Hoy puedes gastar»: a mitad de mes, la regla de acumular sumaría los días ya pasados y alguien que apenas empieza leería una cifra enorme.
- **Un botón ancho «Continuar» abajo**, en lugar de las flechas de la barra inferior; «Anterior» va arriba a la izquierda. Queda arriba del teclado numérico, así que ya no hace falta el «Siguiente» sobre el teclado.
- **Guía flotante (picture in picture) en vez de video grabado.** Las imágenes se dibujan al momento con las capturas reales que ya usa la guía. Así no hay que grabar nada, no se queda vieja con cada iOS (se rehace con `GuideScreenshotsTests`) y no pesa. Esas tres eran las razones por las que el 2026-10-15 se descartó un video. ⏪ y ⏩ cambian de toque, y ▶︎ avanza solo cada 8 s.
- **Requiere el modo en segundo plano «audio»,** que es el que Apple pide para picture in picture. La app no reproduce sonido y no interrumpe la música (`mixWithOthers`). El simulador no tiene picture in picture: se verifica en el iPhone.

## 2026-10-29 · Te pasaste del mes: un plan para cerrarlo
A pedido del dueño, que está en ese caso: la pantalla de «te pasaste» no ayudaba a decidir nada.
- **La cifra grande es cuánto te pasaste**, en rojo, en el mes actual. Antes volvía al total del mes en blanco y el «te pasaste» quedaba en letra chica.
- **«Para cerrar el mes» muestra tres caminos** para los días después de hoy: sin gastar más, lo que tocaba por día (presupuesto menos fijos, entre los días del mes) o tu ritmo de este mes (lo gastado fuera de fijos, entre los días transcurridos). Cada uno dice con cuánto de más cierra el mes.
  - Los fijos que faltan cuentan aunque no gastes nada.
  - Un camino de $0 al día no se repite.
  - El último día solo dice cómo cierras.
  - La cuenta vive en `OverspendPlan` (CentavoCore).
- **La nota del mes no sale cuando te pasaste:** su «a este ritmo cierras…» es uno de los tres caminos.
- **La barra muestra cuánto te pasaste:** el presupuesto en latón, lo de más en rojo y la rayita donde termina el presupuesto. En lugar de «Deberías llevar» dice «Presupuesto $X · de más $Y».
- **El panel se puede cerrar** con su ✕ (pedido del dueño): queda una sola línea, «Ver cómo cerrar el mes ⌄», para volver a abrirlo. Cerrado dura el resto de ese mes; si el mes siguiente también te pasas, vuelve a salir.
- **No se hace por ahora:** pasar lo de más al presupuesto del mes siguiente. Cambiaría la regla de un solo presupuesto para todos los meses (2026-10-13).

## 2026-10-29 · «Más» con Ajustes, y mejoras rápidas
Aprobado por el dueño, sobre el análisis del mismo día.
- **«Más» queda con lo que forma tu mes** (presupuesto, gastos fijos, tarjetas y categorías), **el atajo y Ajustes.** La moneda, «En qué se va», la ubicación, el aviso de Wallet y el CSV pasan a una hoja de Ajustes (`Form`).
  - Revisa en parte «La guía del atajo y la exportación viven en un menú "Más"» (2026-10-11) y los ajustes de «En qué se va» en el menú (2026-10-21).
  - Cambiar la moneda pregunta por el presupuesto al cerrar Ajustes.
- **«Avisar si no llegan pagos»** (encendido por omisión, guardado en el teléfono): apagado, la pantalla principal deja de pedir que conectes Wallet y de avisar días sin pagos. Un aviso de Wallet sin monto se sigue mostrando.
- **La pantalla vacía y sin presupuesto no muestra «$0.00»:** ofrece anotar un gasto como acción principal, y fijar el presupuesto y conectar Wallet como secundarias.
- **Las categorías de la barra de «En qué se va» filtran la lista,** igual que el mosaico (amplía 2026-10-21).
- **Mantener presionado un gasto:** «Categoría» (cuenta como elección tuya y se recuerda para ese comercio) y «Anotar otra vez» (copia el monto, comercio, tarjeta y categoría con la fecha de hoy).


## 2026-10-29 · Hoja del gasto: lo común primero
Aprobado por Fernando (propuesta 8 del análisis `docs/research/analisis-ux-ui-tecnico-2026-10-29.md`, con las marcadas ⚠︎). Reemplaza los interruptores «Es una devolución» (2026-10-12) y «Cuenta para el presupuesto» (2026-10-23) y el selector segmentado MXN | USD | EUR (2026-10-16). Lo que hacen no cambia.
- **Orden:** Monto → Comercio → Categoría → ¿Con qué pagaste?. Lo demás va en «Más detalles», cerrado por omisión, con su resumen en el renglón («Hoy · Gasto»). Se abre solo al editar un gasto que ya tiene algo ahí (devolución, «No cuenta», se repite, es copia de un fijo o tiene ubicación).
- **La moneda es una cápsula «MXN ▾» junto al monto** (un `Menu` con MXN, USD y EUR, más la del gasto si llegó en otra). Se sigue guardando con su código ISO.
- **«Tipo: Gasto / Devolución / No cuenta»** en un solo `Picker`, dentro de «Más detalles». Devolución = monto negativo; «No cuenta» = `countedAmount` 0 con su «Motivo» justo debajo. Un gasto ya guardado como devolución que no cuenta conserva su signo al editarlo.
- **Comercio opcional con categoría:** con monto y categoría se puede guardar sin comercio, y el gasto se llama como la categoría («Despensa»). Sin categoría el comercio sigue siendo obligatorio («Falta el comercio»). Ese nombre no se aprende como comercio (ni renombre ni categoría recordada).
- **Categorías:** primero la sugerida o la que ya tiene, luego las 5 más usadas (con poco historial, las de siempre), y «Ver todas» para el resto (`CategoryShortlist`, en `CentavoCore`).
- **«Dilo en una frase» vive junto al monto** (ícono de globo). Si la frase no trae monto lo dice: «No encontré un monto en «…». Escríbelo arriba.»
- **«Siguiente» sobre el teclado numérico** pasa del monto al comercio.
- **Origen de Wallet:** al pie de un gasto que llegó de Wallet, «Llegó de Wallet · 28 oct 14:32» y el texto del aviso tal como llegó.
- **Rendimiento (R10):** la hoja ya no consulta todo el historial en vivo; lo lee una vez al abrir, y las sugerencias de comercio y la categoría recordada se recalculan solo al cambiar el comercio.
- **También:** en «Tarjetas y categorías», «Usar por defecto» es un interruptor dentro de la hoja de la tarjeta (ya no un deslizar escondido) y borrar una tarjeta o categoría pregunta antes. En «Gastos fijos», «Dejar de repetir» y «Borrar» preguntan antes, y «Nuevo gasto fijo» tiene Categoría y Tarjeta opcionales (`FixedPlan.card`, opcional: los planes guardados antes se leen igual). VoiceOver lee los íconos con su nombre en español.
## 2026-10-29 · Widgets: «+» en el pequeño, una sola frase para VoiceOver, «Abre Al día una vez» y «Actualizado hace X»
Pendientes de la revisión del 2026-10-29 (`docs/research/analisis-ux-ui-tecnico-2026-10-29.md`), aprobados por el dueño.
- **El pequeño tiene «+»** junto a la cifra, más chico que el del mediano (`Theme.Size.widgetAddButtonSmall`). El pequeño no admite `Link`, así que es un botón con `OpenAddExpenseIntent`, que abre la app en «Anotar gasto». Tocar el resto del widget sigue igual: abre la app, o la hoja del presupuesto si no hay. La cifra se encoge un poco si no cabe junto al «+».
- **VoiceOver lee cada widget de inicio como una frase,** la misma de la pantalla bloqueada (`DayState.spoken`): «Hoy puedes gastar $290». Luego el «+» y «Fijar presupuesto» como botones aparte. «En qué se va» agrega sus categorías a la frase.
- **Sin datos, «Abre Al día una vez»** en lugar de «Sin presupuesto»: un widget sin `WidgetSnapshot` (la app nunca se abrió, o falta el App Group y el llavero) no sabe si hay presupuesto. Tocarlo abre la app. En la pantalla bloqueada: «—» en el círculo y «Al día · ábrela una vez» en la línea.
- **«Actualizado hace X» solo si lo que dejó la app tiene 24 h o más** (`WidgetSnapshot.daysOld`), en el renglón bajo la cifra. Un pago, Siri o abrir la app lo reescribe, así que casi nunca sale. La línea de tiempo trae el momento exacto en que cumple un día.
- **Los widgets se actualizan antes de que termine cada intent** (Wallet, Siri, Atajos): `WidgetBridge.refreshAfterIntent()`. Atajos puede suspender la app justo después del pago, antes de los 300 ms del refresco por `ModelContext.didSave`, y el widget quedaba un pago atrás. El refresco por `didSave` sigue para la app.

## 2026-10-29 · Control «Anotar gasto»
- **Un control de iOS 18 (`ControlWidgetButton`) en la extensión de widgets,** para el Centro de control, la pantalla bloqueada (en lugar de la linterna o la cámara) y el botón de acción. Un toque abre Al día en «Anotar gasto».
- **Cómo abre la hoja:** `OpenAddExpenseIntent` (`openAppWhenRun`) se compila en la app y en la extensión. El sistema lo corre en la app, que abre su propio `centavo://anotar`, el mismo enlace del «+» del mediano. `OpenURLIntent` no sirve: solo acepta enlaces universales, y la app no tiene servidor ni dominio.

## 2026-10-29 · Siri: «Borra el último gasto» y «¿Cuánto puedo gastar hoy?»
- **«Borra el último gasto en Al día»:** Siri dice cuál es («¿Borro $89.00 en Oxxo, de ayer?») y pide confirmación antes de borrarlo. Es el más reciente hasta ahora, nunca un gasto fijo: borrar uno por voz pararía o saltaría su repetición sin que se note.
- **«¿Cuánto puedo gastar hoy en Al día?»:** solo la cifra del día, la misma de la pantalla. «Cuánto llevo» sigue diciendo el mes completo.
- **«Anotar gasto» acepta una categoría opcional.** Siri no la pide; se elige en Atajos y gana sobre la memoria del comercio.
- Quedan 6 atajos de los 10 que permite Apple.

## 2026-10-29 · Captura más liviana
- **Recordar la categoría de un comercio mira solo el último año** (máximo 2,000 gastos, los más nuevos primero). Antes cada pago de Wallet leía todo el historial, en segundo plano y con poco tiempo. Un comercio que no se usa desde hace más de un año empieza de cero; una categoría elegida como regla («Recordar mi categoría») sigue ganando.
- **La reparación de nombres de bancos lee solo lo que llegó desde la última vez** (fecha guardada en `UserDefaults`). Si cambia la lista de tarjetas, lo vuelve a leer todo, porque una tarjeta nueva puede volver legible un renglón viejo.
## 2026-10-29 · Peso de la app
A pedido del dueño (sección «Peso» del análisis `docs/research/analisis-ux-ui-tecnico-2026-10-29.md`). Nada visible cambia.
- **Tipografía recortada.** Las tres IBM Plex Mono (que viajan dos veces: en la app y en los widgets) solo llevan latín básico, Latin-1, Latin Extendido-A, acentos combinables, puntuación general («», —, …, •, ·), símbolos de moneda (U+20A0–20CF), flechas y los signos que usa el código (−, ✓, ⏩…). Pasan de 412 KB a 228 KB cada juego. Un carácter fuera de esa lista (por ejemplo, un comercio en griego o cirílico) se dibuja con la letra del sistema en lugar de Plex. Si algún día hace falta, se vuelve a generar desde las fuentes originales con `pyftsubset`.
- **Capturas de la guía en HEIC** en lugar de JPG (calidad 70): mismas imágenes, 40 % menos peso.
- **Se quitó código que nada usaba:** los dibujos de Atajos para iOS 27 que ya se reemplazaron con capturas reales, los restos del modelo de IA que se quitó el 2026-10-20 (`FactCheck`, `CategoryPick.prompt`/`examples`, `MerchantName.isFaithful`) y el catálogo del sistema de diseño en Release (solo vive en Debug, para el lienzo de Xcode).
- **Build:** `DEAD_CODE_STRIPPING` encendido, y la CI baja el binario fijo de xcodegen en vez de instalarlo con Homebrew.

## 2026-10-29 · Letra mínima de 12 en la app
Aprobado por el dueño. Lo que lleva información no baja de 12 puntos: `caption`, `captionStrong` y `hint` (eran 11) y `micro` y `microStrong` (eran 10) pasan a 12. Sigue siendo «Noche ticket»: la misma tipografía y las mismas mayúsculas espaciadas en las etiquetas, solo más grandes. Todos crecen con Dynamic Type como antes.
- **Los widgets quedan fuera por ahora:** su caja la fija el sistema, y su letra (de 8 a 11) no puede crecer sin rediseñar qué cabe en cada tamaño. Se trata aparte.

## 2026-10-29 · Pulido: plan del mes, tarjetas y categorías, gastos fijos, guía flotante
Pedidos del dueño.
- **«Para cerrar el mes» es un solo panel que se pliega en su lugar:** el mismo título abierto y cerrado («Para cerrar el mes · 2 días más»), con una flecha que gira y, cerrado, una línea («Sin gastar más, cierras $X arriba»). Reemplaza la ✕ y la línea suelta «Ver cómo cerrar el mes». Cada camino muestra a la derecha la cifra con la que cierras («$866 / de más»).
- **Tarjetas y categorías en mosaicos con menú**, en vez de una lista con interruptores:
  - Las tarjetas que llegaron en los pagos y no están dadas de alta se muestran como «De tus pagos». Usarlas por defecto o darles ícono las da de alta.
  - Una categoría oculta se ve tenue con un ojo tachado.
- **Gastos fijos empieza explicando para qué sirve.** El resumen del mes (una barra de cobrado y por venir) solo sale si hay fijos, y se agregan sugerencias de un toque que abren la hoja con el nombre puesto.
- **La guía flotante nunca deja a la persona sin Atajos:** si en 1.2 s la ventanita no arrancó (en el iPhone del dueño no abría nada), Atajos se abre sin ella. Queda una bitácora (`guia-flotante`) para saber por qué. Tocar la miniatura la muestra sin salir de la app.
- **Ajuste del mismo día:**
  - En «Para cerrar el mes», el título y el primer camino («Sin gastar más») se quedan quietos abierto y cerrado; plegar solo esconde lo de abajo, sin cambiar el texto. El título ya no se atenúa al tocarlo.
  - Los mosaicos de tarjetas miden todos lo mismo; «De tus pagos» pasa a ser una marca en la esquina, como la estrella.
  - La guía flotante escribe un diario (`Library/Caches/guia-flotante.log`) que se puede copiar del iPhone con `devicectl` para saber por qué no arranca.

## 2026-10-29 · La guía flotante pasa a video; «Ver más» en categorías
- **La guía flotante es ahora un video MP4 armado en el teléfono:** las mismas capturas de la guía, una cada 8 s, guardado en la caché (unos 850 KB, una sola vez por guía) y reproducido con el reproductor del sistema. El diario del iPhone del dueño mostró que con la capa de imágenes sueltas el sistema nunca dejaba flotar la ventana («no posible» en cada intento). Sigue sin pesar en la app y sin quedarse viejo. ⏩ y ⏪ de la ventanita llevan a la imagen siguiente o anterior, salte lo que salte el sistema. La miniatura muestra la imagen del paso desde el principio (antes podía verse negra).
- **Hoja del gasto, categorías:** al abrir «Ver N más» las que ya se ven se quedan en su lugar y las demás aparecen debajo, una tras otra. «Ver más» y «Nueva» van en un renglón propio bajo la cuadrícula; la flecha gira.
- **La causa real era que la app no traía sus modos en segundo plano:** `INFOPLIST_KEY_UIBackgroundModes` en `project.yml` no llegaba a la app compilada (no aparecía en su `Info.plist`). Sin «audio», iOS no deja flotar ninguna ventana, ni con la capa ni con video. Tampoco estaba «remote-notification», el que iCloud usa para sincronizar en segundo plano. Los dos pasan al `Info.plist` de la app y se comprueban en la app compilada.
- **La cápsula de pasos de la guía ya no corre los puntos a un lado** (el último quedaba cortado por el borde); tiene margen a los dos lados.
- **Toda sección que se pliega se mueve igual** (pedido del dueño): `Theme.Motion.fold` para el espacio y `.transition(.unfold)` para el contenido, que aparece cuando ya hay lugar y se va antes de cerrarlo. La cuenta de la barra ya no se desliza con rebote ni se dibuja encima de «En qué se va»; su flecha gira. En «Sin gastar más» el detalle dice cuánto suman los fijos que faltan, para que se entienda por qué esa cifra es mayor que «de más» de hoy.

## 2026-10-29 · Te pasaste: opción A, y hoja del presupuesto 2.0
Elegido por el dueño sobre el lienzo de análisis del mismo día.
- **Cuando te pasas, la pantalla va en este orden:** la cifra («Te pasaste $366»), su barra, «Llevas $2,366 de $2,000 · Ver cuenta» y el renglón «Para cerrar el mes ›». Reemplaza el panel plegable entre la cifra y la barra.
  - Todo el renglón de la leyenda abre la cuenta, con 44 pt de alto; la flechita sola era un blanco muy chico.
  - «+ USD 24.99 aparte» va en minúsculas.
- **«Para cerrar el mes» es una hoja del alto de lo que dice:**
  - las fechas que quedan («30 y 31 de oct»);
  - los tres caminos, cada uno con una barra de con cuánto cierras de más;
  - y «el 1 de noviembre empiezas de cero».
- **No se ofrece ajustar el presupuesto al pasarte** (decisión del dueño): la app avisa cómo vas contra un presupuesto que ya fijaste; subirlo cuando te pasas va contra eso. El presupuesto solo se cambia en «Más › Presupuesto del mes».
- **Hoja «Tu presupuesto» 2.0, igual entres por donde entres:**
  - el monto, con «Al día: $X» en vivo (el mismo con las dos reglas) y lo que llevas este mes;
  - luego «Lo que no gastas un día: Se acumula | Se reparte» (antes «Hoy puedes gastar», que es el nombre de una cifra);
  - una semana de ejemplo animada de $100 por día con los mismos gastos en las dos reglas: lo que sobra o falta sale como moneda y va completo a mañana o se reparte entre los días que quedan. La cuenta está en `AllowanceDemo` (CentavoCore), con pruebas;
  - una frase de a quién le conviene cada regla;
  - «Guardar» arriba, donde el teclado no lo tapa (reemplaza la barra de guardar de abajo en esta hoja);
  - sin el párrafo largo;
  - con «Reducir movimiento», la semana se queda quieta y completa.

  - la semana de ejemplo usa gastos con los que cada reparto es exacto (nada se redondea, así lo que se mueve suma justo lo que sobró), va más despacio y se pausa al tocarla (dueño, 2026-10-29).
- **Guía flotante y pasos 5–6, tras una prueba con tres personas simuladas (2026-10-29):**
  - la ventanita arranca reproduciéndose al tocar «Abrir Atajos» y no hay miniatura junto al botón; la capa que iOS necesita para flotar queda escondida detrás;
  - cada cuadro del video: barra de avance por paso, instrucción en blanco y nunca cortada, y la captura recortada a mano (`GuideFrame.focus`) en vez de detectar el anillo por píxeles, que era frágil;
  - las tres personas se perdían en «Conéctalos» y «Conecta el comercio»: ahora va una acción por cuadro, sin palabras de Atajos («burbuja», «barra»), y cada paso cierra con «Así debe verse»;
  - «unos 2 minutos» pasó a «unos 5 minutos» (nadie lo creía con 8 pasos) y la bienvenida dice qué es Atajos.
- **Segunda ronda con tres personas nuevas, desde la App Store (2026-10-29):** las tres entendían la app y abandonaban en el paso 5, cuadro 10. Pedido del dueño: atender todos los hallazgos.
  - la ventanita ya no avanza sola en los cuadros donde hay que tocar algo: se detiene al final y dice «Al terminar, toca ▶︎»; los «Así debe verse» sí avanzan solos. Corrige en parte la decisión de esta mañana de que todo avanzara solo: a 8 segundos nadie alcanzaba;
  - el cuadro 10 nombra lo que se ve («la fila empieza con «Seleccionar variable». No es esa») y el 11 muestra la fila completa con la campana;
  - «No elijas Wallet» pasó a «Wallet va en el siguiente paso», y «la palabra gris» a «en azul tenue», que es como se ve;
  - la bienvenida dice «Apple Pay» en vez de «Wallet» donde habla de pagar (se leía «cartera»), aclara que el efectivo y el plástico se anotan con «+», y lo repite en «Conecta Wallet» antes de la guía, no hasta el paso 8;
  - en la bienvenida: «Ejemplo» sobre la tarjeta animada, monedas por nombre («Pesos») en vez de código, gastos fijos sugeridos en renglones en vez de una fila que se cortaba, y «sin lo que vas a ahorrar» en el presupuesto;
  - el botón secundario («Después») va en blanco y seminegrita en toda la app: en gris no se leía como botón;
  - en el inicio, «+ USD 24.99 aparte» pasó a «en otra moneda» y la etiqueta de un gasto excluido dice «No cuenta en el presupuesto».
  - Queda por investigar: instalar el atajo ya armado con un toque, lo único que quitaría los pasos 5 y 6, revisando que no choque con «sin servidor».

## 2026-10-29 · El atajo ya viene armado (opción B)
Elegido por el dueño tras dos rondas con personas: todas se perdían armando el atajo a mano.
- **En iOS 27 Al día trae la automatización completa** (`Centavo/Resources/Registrar aviso de Wallet.shortcut`): el disparador «Notificación» de Wallet y la acción con «Notificación» y «Subtítulo» conectados. «Configurar atajo» abre primero «Conecta Wallet» con un botón «Agregar a Atajos»; la guía de 8 pasos queda detrás de «Prefiero hacerlo paso a paso».
- **Se entrega por la hoja de compartir**, donde Atajos sale primero: el esquema `shortcuts://import-shortcut` solo acepta enlaces, no archivos. No hay enlace ni servidor; el archivo viaja dentro de la app.
- **El archivo se exportó del iPhone del dueño**, firmado por Apple para cualquiera. No se puede armar en la Mac: macOS 26 borra el disparador al firmar. Cómo cambiarlo: Tools/atajo/README.md.
- **Llega con la automatización apagada** (así lo hace iOS 27 con lo compartido): la pantalla dice cómo encenderla. Visto en el simulador que el atajo llega completo; encenderlo y el primer pago, por probar en el iPhone.
- Antes de iOS 27 no cambia nada: la guía de siempre.
