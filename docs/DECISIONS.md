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

## 2026-10-29 · Firma «al día.» y un color fijo para cada categoría y forma de pago
Elegido por el dueño (propuestas C y 2 del lienzo de pulido).
- **El nombre de la pantalla principal es una firma:** «al día» en minúsculas, a 20 pt seminegrita, con un punto en latón. Deja de verse igual que el título de una hoja («NUEVO GASTO»). Las hojas siguen con su título chico y espaciado.
- **Cada categoría y cada forma de pago (efectivo incluido) tiene un color fijo** de una paleta de ocho (`Theme.categories`: ocre, verde, azul, rosa, violeta, turquesa, coral, oliva). Sustituye el «el color sigue el lugar en el mes» del 2026-10-21: Comida es verde en la lista, en «En qué se va», en «Tarjetas y categorías», en la hoja de gasto y en el widget, sea primera o cuarta.
  - Las categorías de la app traen su color; las ocho más usadas no comparten. Una nueva toma el color que menos se repite. El efectivo empieza en verde.
  - Se cambia en «Tarjetas y categorías»: «Color» en el menú de cada mosaico, o la fila de colores al crear o editar. Se guarda solo la posición en la paleta (`ColorTags`, sincronizado por iCloud como el resto).
  - Con más de ocho, algunos se repiten, y para quien no distingue rojo y verde algunos pares se parecen: por eso el nombre siempre va escrito al lado. «Otras» y lo que no tiene categoría siguen en gris.

## 2026-10-29 · Un solo lenguaje: cada cosa se ve igual en toda la app
Pedido del dueño tras la revisión de pantallas (seis ajustes y detalles chicos, en ese orden).
- **Un solo «Borrar»** dentro de las hojas (`DestructiveRowButton`): rojo, mayúsculas espaciadas y centrado. Lo usan «Borrar gasto», «Borrar», «Quitar presupuesto» y «Quitar ubicación». La confirmación conserva su botón prominente.
- **Una sola acción en latón** (`LinkActionLabel`), igual en «Ajustar presupuesto», «Agregar gasto fijo», «Agregar» de la bienvenida, «Dejar de repetir» y «Deshacer».
- **Una sola pastilla de sugerencia** (`TicketChip`): delineada y llena de latón al elegirla. Reemplaza las cuatro formas que había y los botones grises del sistema (pantalla vacía y ejemplos de búsqueda). El lint ya no deja usar `.buttonStyle(.bordered)`.
- **Un solo mosaico de categoría y forma de pago** (`CategoryTile`), en la hoja de gasto y en «Pagos y categorías». Toda acción de agregar se llama «Nueva» y va punteada.
- **«Forma de pago», no «tarjeta»:** el efectivo no es tarjeta. La pantalla se llama «Pagos y categorías» (el título largo no cabe en la barra). Las secciones se llaman «Formas de pago» y «Forma de pago · opcional», y sin elegir dice «Sin especificar».
- **Títulos iguales:** cada bloque de la pantalla principal usa el mismo encabezado (`ticketCaption`); el de la cifra grande, siempre en seminegrita. Las llaves chicas sobre una cifra usan `ticketKey`.
- **Una sola fila de gasto** (`ExpenseRowLayout`): los gastos fijos se ven como la lista, con su categoría y su color. La bienvenida y «¿Borrar este gasto?» escriben el nombre en mayúsculas, y los montos llevan siempre centavos.
- **Detalles:** todo pie de sección es `HintText`; dentro de un ticket las divisiones son punteadas; las fechas siempre salen en español; la bienvenida ya no pone «−» a los pagos; el título de «¿Borrar este gasto?» va en tinta, como el de las demás hojas.
- **Espacios medidos al píxel** (capturas de la CI a 3x):
  - Pasado del presupuesto y sin categorías, el carrusel ya no deja un hueco de 263 pt: las dos páginas solo miden lo mismo si «En qué se va» tiene algo.
  - En la pantalla principal, los nombres de «En qué se va» empiezan en la misma línea que el renglón de Wallet y los días (46 pt); antes había tres columnas, en 46, 52 y 68.
  - Los renglones de «En qué se va» miden 29 pt: la página mide lo mismo que la del calendario, y el aire sobre los puntitos es parejo.
  - La barra de «Guardar» queda a 16 pt de cada lado, como «Cancelar», y su resumen va en la línea del texto de las secciones.
  - En «Gastos fijos», la explicación y las sugerencias van en la línea de los encabezados.
  - Un renglón partido ya no empieza con «·».
  - La línea punteada empieza y termina en guion, centrada (antes, 24 pt de un lado y 27 del otro).
  - Las cifras alineadas a la derecha terminan justo en el borde, sin el espacio de letra que sobraba.
  - La flecha «Siguiente» queda pegada al borde de la tarjeta del monto.

## 2026-10-29 · La lista con jerarquía (opción A)
Elegida por el dueño entre tres: «se siente muy cargada».
- **Dos niveles por gasto:** el nombre tal como llega del banco, en mayúsculas y en una sola línea (el completo está en la hoja), y debajo una línea más callada en minúsculas. El dueño descartó acortar el nombre (opción B): es el nombre con el que llegan los cargos.
- **La forma de pago, sin ícono y con su nombre corto en su color** («Amex» en vez del ícono de tarjeta y «American Express México»), el único toque de color de la línea (`PaymentName.short`). El gasto conserva el nombre completo.
- **«No cuenta», corto:** el porqué («Entre mis cuentas», «Me lo reembolsan») queda en la hoja y en VoiceOver. Así cada gasto mide dos líneas. Sustituye en la lista el «No cuenta en el presupuesto» que salió de la prueba con personas; el monto tachado sigue diciéndolo.

## 2026-10-29 · El código de barras del mes y el folio
Elegido por el dueño tras varios prototipos: «decorativo, pero que signifique algo».
- **Bajo la barra del mes, el mes como código de barras** (`MonthCodeView`, `MonthCode`): una barra por día, tan alta como lo gastado ese día (raíz cuadrada, para que la renta no aplaste a los demás). En latón los días con un fijo, en rojo los que pasaron el tope del día (`dailyBase`, sin contar fijos), hoy respira y los días por venir quedan en blanco. Cada 9 s lo cruza la luz de un escáner: lo único que se mueve solo en la pantalla. Con «Reducir movimiento», quieto.
- **Con el dedo:** deslizarlo muestra la ficha del día (cuánto, cuántos pagos, el más grande y contra el tope), con un toque háptico por día; soltarlo en un día filtra la lista, igual que el calendario, y los dos marcan el mismo día.
- **Debajo, donde un código imprime sus cifras, las del mes:** pagos, promedio por día y tope por día, separados por puntos en latón.
- **El folio «N.º 058»** junto al título de la cifra: cuántos pagos tiene el mes. Arriba de todo, la fecha como encabezado de ticket («JUE 29 OCT»). El dueño descartó la hora, «día 29 de 31 · quedan 2» y la doble raya bajo la cifra: la cifra se queda como estaba.
- **Lo que cambia al deslizar es la parte de abajo:** la barra, el código y «Para cerrar el mes» se quedan quietos; el carrusel cambia entre «En qué se va» y el calendario. Sin «En qué se va» ni nota, el calendario queda solo, sin puntitos.
- **«Para cerrar el mes» se quita con su ✕** por lo que queda del mes; si el mes siguiente también se pasa, vuelve.
- **Los puntos que separan las partes de un gasto** («Despensa · Amex») van en latón, como los del encabezado.

## 2026-10-29 · El hero, versión 4
Elegido por el dueño tras el prototipo v4. Sustituye en lo que choca a «El código de barras del mes y el folio».
- **Arriba fijo:** «JUE 29 DE OCT» y, en la misma línea y con el mismo formato, el folio «N.º 042» con el número en latón (`ReceiptHead`); la cifra como estaba; la barra del mes y «Llevas…».
- **La barra del mes, por días:** cortada en una celda por día del mes (`DayCells`, máscara), como boleto perforado; lo gastado las llena, el exceso en rojo, lo de fijos por venir en latón bajo y la celda de hoy delineada. Ya no hay casillas sueltas para los días que faltan.
- **«Para cerrar el mes» se quita** por completo, fila y hoja: era mucha información.
- **El carrusel:** «En qué se va» (Lista o Mosaico, como siempre) y, a la derecha, el calendario con el **código de barras debajo**; los dos filtran la misma lista.
- **Vista «Mínima»** en Ajustes (antes «No mostrar», mismo valor guardado): sin carrusel, sin calendario y sin código. «Barra» se llama ahora «Lista», y el ajuste se llama «Vista».
- **Sin margen:** si los fijos se comen el presupuesto, el código dice «sin margen» en vez de «tope $0» y no pinta días de rojo. Un día con un fijo va en latón aunque ese día se haya gastado más.

## 2026-10-30 · La vista vuelve al menú y el carrusel está siempre
Pedido del dueño tras usar la versión 4 en su iPhone.
- **«Vista» en el menú «···», en primer nivel** (Lista, Mosaico, Mínima, con la elegida marcada), como estaba; sale de Ajustes, que queda con la moneda.
- **El carrusel está en todas las vistas:** a la izquierda siempre el código de barras, con «En qué se va» debajo en Lista o Mosaico (solo el código en Mínima); a la derecha siempre el calendario. Sustituye «Mínima: sin carrusel» y «el código bajo el calendario».
- **La cifra respira:** 24 pt entre la cabecera del ticket y «Te pasaste del presupuesto», 8 entre ese título y la cifra, y 20 de la cifra a la barra.

## 2026-10-30 · Arreglos del código de barras
Visto en el iPhone del dueño.
- **El tope por día es el presupuesto (menos fijos) entre los días del mes**, en cualquier regla. Con «Se reparte» tomaba lo que queda por repartir, que llega a $0 al pasarse, y el código decía «tope $0»/«sin margen» y dejaba todo gris.
- **Sin color para los fijos** en el código (el dueño no tiene) y **sin la luz del escáner**.
- **La ficha del día se queda** sobre el día elegido; **un toque en cualquier otro lugar** quita el día o la categoría elegidos y su ficha.

## 2026-10-30 · El boleto
Elegido por el dueño entre tres formas de juntar la barra del mes y el código de barras.
- **El boleto** (`MonthCodeView`): una celda por día, tan alta como el tope de un día (presupuesto menos fijos entre los días del mes). El latón sube con lo gastado; lo que sobró lleva el **verde rayado de la barra de antes** (`Hatch`, `Theme.good`, `paceBehind`); un día pasado del tope va rojo con una marca encima; hoy delineado; los días por venir punteados. Sin presupuesto, cada día se mide contra el más grande del mes.
- **Boleto ⇄ calendario:** el carrusel tiene a la izquierda el boleto y, debajo, «En qué se va» (Lista o Mosaico; nada en Mínima), y a la derecha el calendario.
- **Los datos, en una línea fija** sobre el carrusel, que no cambia al deslizar: «Llevas $X de $Y · $Z/día» y «Ver cuenta». La barra del mes deja su pista (`MonthBar.showsTrack`) y queda solo esa línea y la cuenta.
- La ficha del día sale sobre el boleto y se queda en el día elegido; el carrusel deja lugar arriba para ella.

## 2026-10-30 · Deslizar sobre el boleto
En «Mínima» la página izquierda es casi solo el boleto, y el boleto tomaba el dedo al primer contacto: casi no quedaba dónde deslizar al calendario. Ahora un **deslizamiento rápido** es del carrusel; **un toque** elige el día; **sostener un instante (0.25 s) y deslizar** recorre los días con su ficha, como las gráficas de Salud y Bolsa dentro de algo que se desliza.

## 2026-10-30 · Los widgets con el boleto
Pedido del dueño: los widgets siguen los cambios del hero.
- **El boleto en los widgets** (`DayTicket`): «Hoy puedes gastar» chico y mediano y el lado izquierdo de «Hoy y en qué se va» cambian la barra larga y «Podrías llevar» por el boleto por días, con el mismo verde rayado, el rojo y el día de hoy delineado.
- **El mediano lleva la línea de la pantalla principal:** «Llevas $X de $Y · $Z/día».
- La app guarda para los widgets lo gastado cada día fuera de los fijos (`WidgetSnapshot.days`, opcional: una foto de antes sigue mostrando la barra vieja hasta que la app vuelva a escribir). En un mes nuevo el boleto arranca vacío.
- Los de la pantalla bloqueada no cambian: el sistema los pinta en un solo tono.
- **Segunda vuelta (mismo día):** seguía costando atinarle. Ahora el toque y el «sostener» del boleto nunca le quitan el deslizamiento al carrusel (fallan en cuanto el dedo viaja); mientras se recorren los días el carrusel se queda quieto. **Un deslizamiento de lado sobre la cifra o la línea «Llevas…» también cambia de página**, y el carrusel tiene más alto para deslizar arriba y abajo del boleto.

## 2026-10-30 · La línea bajo el boleto y la versión a la vista
Visto en el iPhone del dueño.
- **«Llevas $X de $Y · $Z/día» y «Ver cuenta» van justo debajo del boleto**, en la página izquierda; a la derecha queda **solo el calendario**. Sustituye «la línea fija sobre el carrusel». La cifra queda a 8 pt del carrusel: había demasiado aire entre la cifra y la línea.
- **Versión a la vista:** cada compilación lleva su número (los commits de la rama) y su commit (`Tools/stamp-build.sh`, al final del build de la app y del widget). Ajustes lo dice al pie: «Al día 0.1.0 · compilación 312 · 59f8d9e» («+» si se compiló con cambios sin guardar).
- **Tercera vuelta:** seguía costando. El deslizamiento de SwiftUI se cancelaba en cuanto el pulgar iba un poco en diagonal dentro del scroll vertical. Ahora toda la parte de arriba (cifra, boleto, línea, calendario, renglón de Wallet) tiene un reconocedor de iOS (`SidewaysPan`, el mismo de «deslizar para borrar») que arranca con que el dedo vaya un poco más de lado que hacia arriba, y cambia de página con 36 pt o un movimiento rápido; convive con el scroll del carrusel y con los botones. Mientras se recorren los días del boleto no cambia de página.

## 2026-10-30 · Boleto y calendario al mismo nivel
Boceto aprobado por el dueño (opción A de tres).
- **«Cada día del mes» es el título de las dos páginas**, fuera del carrusel: no se mueve al deslizar. El boleto y la cuadrícula del calendario empiezan en el mismo renglón debajo. Antes el calendario traía su propio título y empezaba más abajo, y al deslizar todo brincaba.
- **Transición más suave:** el cambio de página tarda 0.55 s y frena sin rebote (`Theme.Motion.pageTurn`, antes 0.3 s). La página que sale se desvanece mientras entra la otra, al ritmo del dedo, así nunca se ven las dos completas lado a lado. Con «Reducir movimiento» no hay desvanecido ni animación.
- **Segunda vuelta (mismo día): «sigue siendo muy brusca».** Al soltar el dedo sobre el carrusel, iOS ya llevaba la página con su impulso y el deslizamiento de la cabecera (`SidewaysPan`) le daba encima un `scrollTo` animado, que la frenaba en seco y la arrancaba otra vez. Ahora, mientras el carrusel se mueve, esa orden se ignora y la página la lleva solo iOS. `EasyPaging` (en vez de `.paging`) decide la página con el mismo umbral corto de 36 pt, contando el impulso. El desvanecido es cuadrático: a medio camino las dos páginas ya no se ven a media luz.
- **Tercera vuelta (mismo día): «se regresa» y «cambia de golpe».** Mientras se arrastraba, la página no seguía al dedo (el carrusel era un scroll y el deslizamiento de la cabecera solo decidía al soltar). Ahora el carrusel no es un scroll: las dos páginas están en una fila que se recorre con `CarouselMotion` (en `HomeModel`). El deslizamiento de toda la parte de arriba la arrastra pegada al dedo y, al soltar, sigue con la velocidad del dedo y frena sin rebote (`Theme.Motion.pageGlide`). Cambia con 36 pt o un movimiento rápido; si no, regresa suave; en las orillas resiste como una lista de iOS. Mientras se desliza de lado, la pantalla no se mueve hacia arriba o abajo (`SidewaysPan.holdsScroll`). Sustituye a `EasyPaging` y a `pageTurn`. La página que no se ve no recibe toques ni VoiceOver.

## 2026-10-31 · Respaldo diario con contraseña
Pedido del dueño: «si se pierde puede ser muy complicado». Con la cuenta de desarrollador gratuita no hay iCloud, así que los datos viven solo en el iPhone. Por eso va antes que «Mi dinero». Plan revisado por un agente independiente; se adoptaron sus cambios.
- **La app escribe el archivo ella misma** en una carpeta que la persona elige en Archivos (marcador guardado; no pide el entitlement de iCloud). Atajos solo la despierta con la acción «Respaldar Al día» en una automatización diaria (21:00, cuando el teléfono suele estar despierto). Así la app vuelve a leer el archivo, lo abre con la contraseña y solo entonces anota «Último respaldo»: nunca dice que respaldó un archivo que no llegó.
- **Un archivo `.aldia` por día** con todo: cada gasto con todos sus campos y todos los ajustes. Los ajustes se leen del dominio de `UserDefaults` de la app, no de una lista de claves, para que uno nuevo entre solo. Quedan fuera los del propio respaldo (`respaldo.*`).
- **Los montos van como texto**, no como número JSON: `JSONDecoder` lee `Decimal` pasando por `Double` y alteraría los centavos en cada restauración.
- **Cifrado AES-GCM** con llave PBKDF2-SHA256 (600,000 vueltas, sal propia por archivo). Una contraseña equivocada o un archivo alterado no abren. La contraseña vive en el llavero de este iPhone (solo este dispositivo) para que el respaldo nocturno no pregunte; «Ver contraseña» pide Face ID. Sin ella el respaldo no se puede abrir: la pantalla lo dice y sugiere guardarla en Contraseñas.
- **Se conservan los últimos 30 días y el más nuevo de cada mes** (`BackupRetention`). Nunca se toca un archivo que no sea un respaldo diario.
- **Restaurar reemplaza todo, en un solo guardado** (contexto propio sin guardado automático): o quedan los datos de antes o los del respaldo, nunca una mezcla. Antes se guarda una copia de lo actual (`al-dia-antes-de-restaurar-…`, que nunca se recorta) en la carpeta y en Documentos de la app. Antes de confirmar se ve de qué día es y cuántos gastos trae.
- **Falta (siguiente paso):** la guía con dibujos para armar la automatización, el aviso de «sin respaldo en 3 días» fuera de Ajustes y un recordatorio para comprobar que recuerdas la contraseña.

## 2026-10-31 · «Mi dinero»: concepto aprobado
Bocetos: https://claude.ai/artifact/3nX4njaKgV7fegF9zvzaxC. Se construye por pasos después del respaldo.
- **Dos pestañas abajo, «Hoy» y «Mi dinero».** Revierte «Una pantalla principal» (2026-10-11). Pendiente: dónde quedan el cambio de mes y la búsqueda de «Hoy», que hoy viven en la barra inferior; se decide con bocetos antes de construir ese paso.
- **Face ID cada vez que se abre la pestaña.** Widgets, Siri y avisos nunca muestran cifras de «Mi dinero».
- **Patrimonio** = cuentas e inversiones (en la moneda principal, al tipo de cambio que se escribe en cada corte) + por cobrar − deudas. Lo «por caer» suma desde que se anota, marcado.
- **Debías ahorrar** = ingresos del mes − presupuesto de «Hoy». **Ahorraste** = patrimonio de este corte − el del anterior, separado en: de tu bolsillo, por caer nuevo, rendimientos (tasa anual, corregible), inversiones (valor con lo que metiste o sacaste) y tipo de cambio por cuenta (saldo en moneda × diferencia del cambio).
- **Día del corte opcional**; ingresos: el sueldo se repite y los extras se agregan en el corte.
- **Gráficas mes a mes:** patrimonio, ahorro contra lo que debías y gasto por categoría.
- **Importar y exportar** un CSV (`corte,tipo,nombre,moneda,monto,tasa_anual,movimiento,repite`) que pueda armar el agente del dueño.
- **Fuera:** conectar bancos y metas.

## 2026-10-31 · «Mi dinero», primera parte: pestañas, Face ID, cuentas y el corte
Decisiones del dueño sobre el recorrido (bocetos: https://claude.ai/artifact/9NGPJEhPnWb2TWL7PXJApA) y plan revisado por un agente independiente.
- **Pestañas abajo: «Hoy» y «Mi dinero».** Probado en el simulador: la barra de pestañas tapa la barra inferior de «Hoy». El cambio de mes sube arriba a la izquierda **solo con las flechas ‹ ›** (el mes ya lo dice la cabecera del ticket); con la etiqueta «OCT 2026» iOS escondía la firma, y el dueño pidió no perderla. La búsqueda queda abajo, como botón junto a las pestañas (iOS lo acomoda solo). Fuera de eso «Hoy» no cambia: el dueño pidió no tocarlo por ahora (sin línea de ahorro, sin aviso del respaldo).
- **Almacén aparte** (`dinero.store`, sin iCloud): un problema con «Mi dinero» nunca detiene «Hoy» ni la captura de Wallet, y el almacén de gastos no se migra. Modelos con forma compatible con CloudKit (todo opcional, relaciones con inversa, sin `.unique`).
- **Face ID cada vez que se abre la pestaña**, y se vuelve a bloquear al cambiar de pestaña o salir de la app. En el selector de apps la pestaña se tapa. Si Face ID falla, el código del iPhone. Un iPhone sin código abre sin pedir nada (no hay con qué comprobar).
- **Cuentas, inversiones, por cobrar y deudas**, con moneda (fija desde que se crea), tipo de cambio y tasa anual opcional. Se archivan, no se borran: los cortes pasados las conservan. Una cuenta nueva entra en el último corte con su saldo de hoy.
- **El corte (decisión 1 A): una sola hoja con pendientes.** Cada cuenta espera su saldo escrito o «Sin cambio»; el saldo anterior es solo el texto de ejemplo y el rendimiento estimado solo una pista. «Guardar» dice «N sin revisar» hasta que no falte nada. El teclado trae «Sin cambio» y «Siguiente» (a la próxima pendiente). Si sales, el corte te espera como lo dejaste (borrador que nunca cuenta). Un corte por mes: rehacerlo reemplaza al del mismo mes.
- **Respaldo formato 2:** incluye «Mi dinero» (sin borradores) y comprueba también cuántas cuentas y cortes trae. Restaurar un respaldo de formato 1 deja «Mi dinero» como está y lo dice antes de confirmar.
- **Siguiente:** el desglose de «ahorraste» (con altas, transferencias, tipo de cambio por cuenta, «ya cayó» con monto), la primera vez guiada, el cierre del mes, gráficas, importar y el aviso del corte.

## 2026-10-31 · La forma de pago, como tarjetita en su color
Pedido del dueño: «no me gusta que diga Amex, me gustaría que esté en una tarjetita naranja».
- **En la línea de cada gasto, la forma de pago es su ícono relleno** (una tarjeta, o el que tenga en «Pagos y categorías») **en su color**, en vez del nombre corto. Sustituye «la forma de pago, sin ícono y con su nombre corto en su color» (2026-10-29). En gris si el gasto no cuenta.
- VoiceOver sigue leyendo el nombre completo; la hoja del gasto también lo muestra.

## 2026-11-01 · Borrar pagos no desconecta Wallet
Visto por el dueño: borró algunos cargos y la pantalla dijo «Wallet sin conectar». La salud de la captura (2026-10-15) salía del gasto de Wallet más nuevo guardado; al borrarlos, parecía que Wallet nunca había mandado nada.
- **La app recuerda cuándo llegó el último pago de Wallet** (`WalletWatch.lastArrivalKey`), aparte de los gastos: cada vez que la automatización manda un pago legible, aunque sea repetido. El aviso toma lo más reciente entre ese recuerdo y el gasto de Wallet más nuevo que quede.
- La primera vez que abre la app con esto, el recuerdo se llena con el gasto de Wallet más nuevo que ya tenía.

## 2026-11-01 · «Mi dinero»: la primera vez
Aprobado por el dueño sobre el prototipo v5 (https://claude.ai/artifact/UwwQEAmuqgeNj1SK7DAEU3); construido y revisado por un agente independiente, cuyos hallazgos se corrigieron.
- **Sin mascota.** Todo en el lenguaje de la app: líneas finas, el punteado del ticket, las celdas del boleto y un solo latón; sin rebote; con «Reducir movimiento», todo quieto.
- **Presentación:** el mismo cuadro punteado y el botón, con un boleto encima que muestra un patrimonio de ejemplo creciendo mes a mes y la cifra contando.
- **Face ID se explica antes de pedirse,** con su símbolo dibujado con líneas: la cara, una línea de luz, la palomita y las esquinas en latón.
- **«Primera cuenta» en cuatro pasos,** con «Paso N de 4» siempre arriba: 1 Lo que tienes (Cuenta, Inversión), 2 Lo que debes (Tarjeta, Préstamo, Otros), 3 Lo que te deben, opcional (Me deben, Por caer), 4 el resultado con una animación de éxito y el patrimonio contando. Cada tipo trae su dibujo animado, qué es y ejemplos; «Me deben» y «Por caer» llevan su leyenda como texto real («tú → ana · regresa», «hoy · te llega»).
- **Las cuentas son renglones que se abren en su lugar** (como los Ajustes de iOS): ves todas y llenas la que abres. Cada campo dice qué poner y de dónde sacarlo. Cada renglón se guarda al tocar «Listo». La moneda se elige por su símbolo en un carrusel ($, US$, €, £, CA$, ¥, CHF); en otra moneda se pide el tipo de cambio.
- **Las cuentas tienen un subtipo** (`MoneyAccount.subtype`: tarjeta, préstamo, otros, me deben, por caer), opcional; las de antes toman el de su tipo.
- **Detalles de la revisión:** la tasa y el tipo de cambio se leen como decimales («18.125» no es 18,125); «Mi dinero» queda montado bajo el candado, así que salir a ver el banco no borra un renglón a medias; cambiar de tipo conserva lo escrito y salir de un paso con un renglón a medias pregunta antes; «Anterior» en el paso 1 vuelve a la presentación; el teclado trae «Ocultar teclado» y el botón del paso se aparta mientras escribes; con letra de accesibilidad las tarjetas se apilan y la explicación de Face ID se desplaza; quitar una cuenta con historia la archiva.
- **El lint deja pasar los trazos de `MoneyArt.swift`** (rutas de Canvas en su propio espacio de dibujo), como los dibujos de Atajos; la interfaz alrededor sí se revisa.

## 2026-11-01 · «¿Lo tienes en Excel?»: importar con la IA de la persona
Pedido del dueño: cargar «Mi dinero» desde su Excel pasándolo por su IA de confianza. Propuesta: https://claude.ai/artifact/MpDVJyS9a12nfXBJ23BjbU (v3). Plan revisado por un agente independiente antes de construir; se adoptaron sus correcciones.
- **Dónde:** en el paso 1, debajo de las dos tarjetas principales (Cuenta e Inversión), un botón secundario a todo lo ancho con su animación (una hoja de cálculo cuyas filas vuelan al ticket). Abre una pantalla dentro de los pasos, no una hoja: así ir a la IA y volver la deja bajo el candado de Face ID.
- **Cómo:** copiar instrucciones (con la moneda principal) → la IA las sigue con el Excel → pegar (`PasteButton`, sin el aviso de permiso de iOS) o subir un archivo. Formato en `docs/formato-mi-dinero.md`. Al día nunca recibe el Excel; lo pegado se borra del portapapeles al guardar si nada más se copió después.
- **Revisión editable antes de guardar:** «N listas · M por revisar», lo dudoso primero y en latón con su motivo («12k», «25 mil», un tipo desconocido, una moneda rara, un ingreso de una vez); cada renglón se abre para corregir, se puede quitar y agregar; lo que se parece a algo ya guardado se ofrece apagado con «¿Ya la tienes?». Se guarda solo lo listo, todo en un guardado.
- **Varios tipos de cambio:** uno por moneda, arriba de los renglones; si el Excel trae dos distintos para la misma, se elige; si falta, se pide y no se puede guardar sin él.
- **Ingresos:** solo los que se repiten (`MoneyIncome`, con `since`), aparte del patrimonio. Uno de una sola vez se convierte en «por caer». En el paso 4 dicen cuánto entra al mes y, con presupuesto en «Hoy» y todo en la moneda principal, cuánto debes ahorrar. Si no se importaron, se pedirán en el primer corte.
- **Institución** en cada cuenta (`MoneyAccount.institution`), también al llenar a mano y en «Nueva cuenta».
- **Respaldo formato 3:** guarda subtipo (antes se perdía), institución e ingresos.
- **Arreglos que salieron de la revisión:** las hojas de «Mi dinero» se tapan cuando la app no está al frente y piden Face ID al volver, con el mismo candado de la pestaña (`MoneyLockState`), sin cerrarse ni perder lo escrito (sus saldos se veían en el selector de apps); «Nueva cuenta» leía «18.125» como 18,125; el importador de gastos de Ajustes reconoce el archivo de «Mi dinero» y dice dónde va.
- **Segunda revisión (código ya construido):** un monto con comas sin comillas («12,500») ya no se lee como 12 en silencio; un renglón no cambia de grupo mientras se edita (se acomoda al tocar «Listo»); los renglones se editan por su id (quitar uno ya no puede tronar la app); una tasa menor a 1 o mayor a 100 se pregunta; la moneda pegada al monto («USD 2000») llena o contradice la columna; el texto después de la tabla y las negritas no estorban; un ingreso de una vez pasa a «por caer»; las inversiones conservan su tasa; solo lo que se va a guardar pide tipo de cambio, prellenado con el que ya había; un corte de otro mes no cambia sus tipos de cambio y solo ingresos no crean corte; los ingresos se comparan solo con ingresos; el archivo se lee en UTF-16 solo con su marca.
- **La pantalla de importar no usa `@Query`:** empujada desde los pasos, que consultan lo mismo, SwiftUI la redibujaba sin fin y la app se congelaba al abrirla (lo encontró la prueba de interfaz). Lee lo que necesita al cargar la respuesta.

## 2026-11-01 · La bienvenida con el lenguaje de «Mi dinero»
Pedido del dueño: «más bonito, más entendible, más sencillo», con el estilo de «Mi dinero». Propuesta: https://claude.ai/artifact/687UktPfqt5mmVCwhM8TkU. Plan atacado por un agente experto (técnica, UX/UI y animación); se adoptaron sus correcciones.
- **Una barra de pasos** (`StepBar`, compartida con «Mi dinero») sustituye «PASO N DE 4» con emblema y los puntitos: cuatro partes, el nombre del paso y un brillo que la cruza una vez al entrar. Cada paso tiene una pregunta por título y la firma «al día.» arriba.
- **Paso 1:** la demostración (un aviso de Wallet se vuelve renglón y la cifra baja) gana el boleto del mes, cuya celda de hoy se llena con cada pago; corre tres pagos y se queda quieta. Los cuatro puntos se quitan: una frase que no pierde el efectivo («…lo demás, con «+»»).
- **Paso 2:** moneda por su símbolo (tres pastillas, las monedas que suma la app); la ecuación «($X − fijos) ÷ días del mes = $Y» con el redondeo de «Hoy» (hacia abajo) y un boleto con los días reales del mes que se llena una vez al escribir.
- **Paso 3:** un calendario del mes: su día se elige tocándolo y cada fijo agregado se sella ahí, una vez. Los campos van arriba del calendario (abajo, el teclado los tapaba). Si los fijos pasan el presupuesto lo dice, nunca un «$0» suelto.
- **Paso 4:** igual que antes, sin rebote. «Agregar a Atajos» (iOS 27) o «Configurar ahora» llevan a la guía, como antes; «Después» lleva al final.
- **Final nuevo:** la animación de éxito y **«Cada día tienes $X»**, no «Hoy puedes gastar» (sigue la decisión del 2026-10-29: a mitad de mes acumularía días). Sin presupuesto, dónde fijarlo; con fijos de más, por cuánto. No dice «Wallet conectado»: el atajo llega apagado.
- **Una sola regla de «quieto»** (`MotionPolicy`): «Reducir movimiento», modo de bajo consumo y las pruebas (`-centavo-sin-animaciones` o `-centavo-dibujos-quietos`). Las animaciones de la bienvenida ya no rebotan.
- Se guarda una sola vez, salga por donde salga (antes, guardar dos veces habría duplicado los fijos).

## 2026-11-01 · «Hoy» sin datos: dos tarjetas con dibujo (opción A)
Pedido del dueño: la pantalla vacía más bonita y los botones de abajo con movimiento. Es el único cambio en «Hoy».
- **Título «Tu mes empieza aquí»**, el mismo cuadro punteado y un renglón fantasma («Tu primer gasto · $0.00») que se imprime una vez. El boleto del mes vacío aparece solo sin presupuesto (con presupuesto ya lo muestra la cabecera); su celda de hoy respira tres veces y se queda.
- **«Anotar un gasto»** sigue como acción principal. Debajo, «Fijar presupuesto» y «Conectar Wallet» como tarjetas con su dibujo (celdas que se llenan; iPhone → ticket). Una vez, en secuencia, y quietas: nada corre en bucle en la pantalla de todos los días.
- Lo hecho desaparece en vez de quedarse con palomita: con presupuesto queda solo la tarjeta de Wallet, a lo ancho.
- Con `MotionPolicy` quieto (Reducir movimiento, bajo consumo, pruebas) todo se dibuja en su estado final.

## 2026-11-02 · «Cómo funciona»: historias animadas
Pedido del dueño: un tutorial divertido y animado, como historias, al final de la bienvenida y en «···». Plan atacado por un agente experto antes de construir.
- **Siete historias**, no nueve: la cifra, la barra del mes, lo que sobra, se anota solo (y a mano con «+»), lo que no es gasto («No cuenta»), en qué se va y el respaldo. «Mi dinero» se presenta solo la primera vez que se abre su pestaña.
- **Cuánto dura cada una** depende de lo que hay que leer (`StoryTiming`: 4 s más 0.25 s por palabra, máximo 10), no 6 s fijos.
- **Un solo gesto:** tocar avanza (el 30 % de la izquierda regresa), mantener pausa, deslizar hacia abajo cierra. Siempre hay «Anterior» y «Siguiente» visibles: el gesto es un atajo, no la única forma.
- **No avanza sola** con VoiceOver, «Reducir movimiento», modo de bajo consumo o letra de accesibilidad (ahí el texto se desplaza). Cada dibujo corre una vez y se queda quieto.
- **«Pruébalo»** cierra las historias y abre lo que nombra (presupuesto, guía del atajo, Ajustes) cuando ya se fueron, en el `onDismiss`: dos pantallas completas no pueden estar arriba a la vez. La bienvenida hace lo mismo con su salida (antes esperaba 500 ms fijos).
- No se muestra sola nunca; al final de la bienvenida es un botón secundario, «Cómo funciona · 1 min».

## 2026-11-02 · Auditoría: números y pérdidas
Pedido del dueño: «corrija todos tus hallazgos» de la auditoría del 2026-11-01. Nadie debe perder datos ni que lleguen mal.
- **«$» se guarda con su moneda real al capturar** (decisión del dueño). Un pago de Wallet con «$» (o sin moneda) se guarda con el código de la moneda principal de ese momento. Los gastos viejos con «$» se fijan una vez a la moneda principal de hoy, cada vez que se abre la app (idempotente). Cambia «Lo que llega de Wallet con «$» sigue significando la moneda principal» (2026-10-16).
- **Dos compras idénticas en menos de 5 minutos** (decisión del dueño): la segunda ya no se descarta; se guarda marcada «¿Repetida?» (en latón en la fila), que se quita con «No es repetida» (menú de la fila u hoja del gasto) o borrándola. Solo entre capturas de Wallet: un gasto a mano igual no la marca.
- **El corte pregunta su mes** (decisión del dueño): del 1 al 7, primero el mes que acaba de terminar; después, el actual. Si ese mes ya tiene corte: «¿Reemplazar el corte de octubre?», con la fecha en que se hizo. Nunca se borra un corte en silencio. Un borrador a medias, de cualquier mes, se abre tal cual al tocar «Hacer corte».
- **Esquema:** tres propiedades opcionales en `Expense` (`fixedID`, `fixedOf`, `maybeRepeated`), migración ligera y compatible con iCloud, autorizadas por el encargo. Cada gasto fijo original tiene su id y cada copia el de su original: dos fijos iguales anotan cada uno su copia. Las copias de antes se reconocen por comercio, monto y periodo, una por original. Dos copias del mismo original y día (dos dispositivos) dejan una.
- **Una cuenta nueva o archivada mientras hay un corte a medias** entra (o sale) también del borrador; al reemplazar el corte de un mes, lo que el viejo tenía y el borrador no pasa al borrador. Un tipo de cambio escrito hoy solo cambia un corte de este mes, un borrador, o uno que no tenía esa moneda.
- **Archivar:** las archivadas tienen su sección «Archivadas» con «Regresar». Dejan de sumar en el patrimonio de hoy (`activeNetWorth`); los cortes pasados no cambian. No se hizo una barra de «Deshacer» aparte: «Regresar» cubre lo mismo.
- **Montos de «Mi dinero»** (`MoneyAmount`): el punto es el decimal, las comas solo miles, nunca más de centavos. En la importación, lo que trae más de dos decimales va a revisión.
- **Una cuenta en otra moneda** dice su código («USD 20.00», «MX$500.00») junto a la moneda principal, en «Mi dinero» y en Siri.
- **Respaldo:** si `dinero.store` existe y no abre, el respaldo falla con un error claro (antes salía sin «Mi dinero», se marcaba hecho y la limpieza borraba los buenos). «Mi dinero» se vuelve a intentar abrir en vez de recordar el primer error. Se muestra si el archivo subió a iCloud; una carpeta solo en el iPhone se avisa al elegirla; una carpeta en la papelera cuenta como perdida.
- **Aviso del respaldo en «Hoy»**, bajo la línea de Wallet y solo si el respaldo está configurado: falló el último intento, o más de 3 días sin respaldo. Cambia «sin aviso del respaldo» (2026-10-31); lo pidió el encargo.
- **Archivo del respaldo, versión 2:** trae un verificador de la contraseña, así un archivo dañado ya no se confunde con una contraseña equivocada. Los de antes siguen abriendo. Un tope de 10 millones de vueltas a lo que dice el archivo. Respalda también cuándo se agregó un ingreso y qué líneas del corte se revisaron.
- **Restaurar:** si los gastos fallan después de cambiar «Mi dinero», «Mi dinero» vuelve a como estaba. Un archivo con «Mi dinero» sin almacén donde ponerlo no se restaura a medias. La alerta dice que también cambia en otros dispositivos con iCloud.
- **CSV:** los montos van completos; lo que cuenta en parte se escribe como monto en «Cuenta» (antes solo Sí/No); el comercio que empieza con tabulador regresa igual. Importar cuenta repetidos por fecha, monto, comercio, tarjeta y moneda: dos iguales en el archivo son dos. Ajustes aclara que el CSV no sustituye al respaldo.
- **Listas en ajustes** (fijos por empezar, categorías, tarjetas) se leen elemento por elemento (`LenientList`): uno ilegible ya no vacía la lista y se vuelve a escribir tal cual.
- **Guardado explícito:** cada acción de la persona guarda en ese momento y, si falla, lo dice. Las capturas guardan antes de buscar la ubicación.
- **Revisión independiente (mismo día), corregida antes de fusionar:** con dos dispositivos, cada copia de un fijo tiene su propio id y siempre se queda la de id menor (antes cada uno podía borrar la del otro y perderse el cargo); un fijo que empieza desde un plan toma el id del plan (dos dispositivos no lo duplican) y guarda el día pedido («31»); si «Mi dinero» no abre, el respaldo guarda los gastos en un archivo aparte («solo-gastos», que la limpieza no toca) sin marcar el día como respaldado, y restaurar un archivo sin «Mi dinero» no lo necesita; «$» no se fija mientras no hay moneda principal elegida; en «Cuenta» del CSV solo un monto con punto decimal y menor al gasto es «lo que cuenta».
- **Lectores:** «mil» y «millones» en una frase; un número tras «de» seguido de un sustantivo es una cantidad, no el monto. Reembolsos y dinero recibido también en inglés; el guion «–» es signo menos. Códigos que también son palabras («ALL», «TOP») solo cuentan si no hay otra cifra.

## 2026-11-02 · Auditoría: privacidad y respaldo
Una auditoría encontró fallas de privacidad y de errores en «Mi dinero» y en el respaldo; el dueño pidió corregirlas todas.
- **Face ID sin carreras:** cada bloqueo empieza una «generación» nueva (`UnlockGate`) y cancela la pregunta de Face ID en curso (`LAContext.invalidate`). Una respuesta solo abre si es de la generación actual y la pestaña sigue a la vista. Antes, tocar «Mi dinero» y volver a «Hoy» antes de contestar la dejaba abierta.
- **Al bloquear, las hojas se apagan:** el contenido no se toca ni lo lee VoiceOver, se guarda el teclado y se cierran sus avisos y diálogos (`onMoneyCovered`), que iOS dibuja encima de todo, tapa incluida. Lo escrito no se pierde.
- **Restaurar y «Cambiar contraseña» piden al dueño** (Face ID o el código, `OwnerCheck`), con la misma regla que «Mi dinero»: un iPhone sin código pasa sin pedir nada. «Ver contraseña» sigue como estaba.
- **La explicación del candado dice lo que hay** (`UnlockMethod`): cara, huella o código; con Touch ID o código se ve su símbolo en vez del dibujo de la cara. Sin código, lo avisa y dice dónde ponerlo.
- **«Mi dinero» no pudo abrir** ya no manda primero a restaurar: restaurar también regresa los gastos de «Hoy» al día del respaldo.
- **Importar:** se mantiene que solo se guarda lo listo; el texto lo dice («N por revisar no se agregan»). «Pegar otra respuesta» pregunta si hubo correcciones.
- **Ingresos:** se ven, cambian y quitan en «Te entra al mes», dentro de la lista de «Mi dinero» (sin pantalla nueva). Cambiar el monto o la moneda en un mes posterior archiva el anterior y empieza uno nuevo desde este mes (`MoneyIncomeRule`), para no reescribir lo que los meses pasados debían ahorrar. Quitar archiva. Si no hay ninguno, el corte lo pregunta arriba, opcional.
- **El corte recuerda los tipos de cambio revisados** (`MoneyCut.reviewedRates`) mientras es borrador.
- **Revisión independiente (mismo día), corregida antes de fusionar:** al bloquearse se cierran también «¿Reemplazar el corte?» y «¿De qué mes es el corte?» (antes quedaban encima de la tapa); cada ingreso guarda hasta cuándo contó (`MoneyIncome.until`, también en el respaldo); el monto de un ingreso se lee como los demás de «Mi dinero» (`MoneyAmount`); el aviso de «Quitar» cuenta solo cortes terminados, igual que lo que hace; salir de la app con «Cambiar contraseña» abierto lo cierra.

## 2026-11-02 · Auditoría: textos y animaciones
Pedido del dueño: corregir todo lo que encontró la auditoría (secciones de textos, UX, animaciones y rendimiento).
- **Nada corre sin fin:** la celda de hoy del boleto respira tres veces y descansa a opacidad completa (`breathes`; sustituye «hoy respira» sin fin del 2026-10-29); los dibujos de «Mi dinero» dan tres vueltas y paran en su cuadro quieto; la cadena de Wallet se enciende una vez y se queda encendida.
- **Sin rebote en ningún lado:** `quick`, `page`, `countUp`, `toggle` y la entrada de la barra del mes ya no usan `.snappy` ni `bounce`; la frase del veredicto aparece sin bajar; la palomita de la guía ya no rebota.
- **`MotionPolicy` observa el bajo consumo en vivo** (`LowPowerWatch`) y la usan también la explicación de «Lo que no gastas un día» y los dibujos de Atajos.
- **Bienvenida:** la barra de pasos queda fija arriba y las páginas ya no se cruzan al regresar (la dirección se fija antes de cambiar de página).
- **«Cómo funciona»:** la barra de avance se mide con el reloj en su propia vista; la pantalla ya no se redibuja 20 veces por segundo.
- **Rendimiento:** la búsqueda filtra en el almacén (`localizedStandardContains`, sin acentos ni mayúsculas) y luego aplica la regla exacta de siempre; «Hoy» cuenta los gastos con `fetchCount` y pide solo el más nuevo y el más viejo.
- **Textos:** las rutas son «Más › …» (el menú «···» se llama «Más»); «por defecto»; «Te deben»; «Por día:»; «Cada día tienes»; la app habla en tercera persona; los errores dicen qué no se pudo; «Corte del mes» y «Forma de pago» como títulos cortos.
- **«Quitar presupuesto» pregunta antes; «Quitar ubicación» se aplica al guardar;** las hojas con algo escrito no se cierran al deslizar.
- **Revisión independiente (mismo día), corregida antes de fusionar:** «Cómo funciona» se pausa mientras la app no está al frente y vuelve a medir su tiempo cuando cambia si avanza sola (bajo consumo, VoiceOver, letra); abrir la app justo después de un pago ya no vibra como si llegara uno; el conteo de «Hoy» también se rehace con lo que trae iCloud y al volver a la app; el dibujo de «Mi dinero» que apareció quieto se queda quieto.

## 2026-11-02 · Lo que quedó por decidir de la auditoría
Respuestas del dueño a lo que chocaba con decisiones aprobadas.
- **El candado dice lo que tiene el iPhone:** el dibujo de la cara solo con Face ID; con Touch ID o código, su símbolo. Aprobado («de eso está súper bien»).
- **«Corte del mes» se queda como título** de la hoja del corte (el mes va abajo, en el pie). Visto lado a lado con «Corte de oct»; aprobado.
- **El aviso del respaldo en «Hoy» se queda:** una línea discreta solo cuando el respaldo falló o lleva más de 3 días sin hacerse. Reemplaza «sin aviso del respaldo» (2026-10-31).
- **Bucles que quedaban, por recomendación aceptada:** el ejemplo de «Hoy puedes gastar» (hoja del presupuesto) recorre la semana una vez y descansa en su final; un toque lo repite. La guía animada del atajo (2026-10-17) sigue en bucle a propósito: es para seguirla paso a paso mientras se arma la automatización en Atajos, y con «Reducir movimiento» o bajo consumo queda quieta.

## 2026-11-02 · Segunda auditoría: datos y respaldo
Pedido del dueño: corregir las fallas de guardado, captura, gastos fijos y respaldo de la segunda auditoría. Nadie debe perder, duplicar ni corromper datos. Cada falla tiene primero una prueba que la reproduce (`SecondAuditDataTests` en CentavoCore y en CentavoTests).
- **Restaurar arregla un «Mi dinero» dañado:** si el archivo trae «Mi dinero» y el almacén no abre, `dinero.store`, `-wal` y `-shm` se mueven juntos a `dinero.store.danado-<fecha>` (nunca se borran; si uno no se puede mover, los demás regresan), se olvida el contenedor guardado (`MoneyStore.forget`, única línea tocada en `MoneyModels.swift`) y se restaura en uno nuevo. Restaurar tiene sus propios errores; si los gastos fallan y «Mi dinero» no pudo regresar, lo dice y manda a la copia «antes de restaurar».
- **Un respaldo vacío o con menos no pisa el bueno** (`BackupPlan`): si el iPhone no tiene gastos y la carpeta ya tiene respaldos, no respalda ni limpia («Parece un iPhone nuevo: restaura tu respaldo antes de respaldar.»). Si el archivo del día tiene más gastos, o tiene «Mi dinero» y el nuevo no, o no se puede abrir (otra contraseña, o está en iCloud sin bajar), el nuevo se escribe aparte (`al-dia-aparte-…`, que la limpieza no toca) y no se limpia. Sin gastos nunca se limpia.
- **iCloud lleno:** «Hoy» avisa si el último archivo falló al subir o lleva más de 24 h subiendo. En una carpeta de iCloud la limpieza espera a que el respaldo anterior haya subido (un borrado sí sube aunque el archivo nuevo no).
- **El corte a medias:** restaurar sigue reemplazando todo (decisión del 2026-10-31), borradores incluidos; para que no se pierdan, la copia «antes de restaurar» los guarda (`BackupMoney.drafts`, opcional; los respaldos diarios siguen sin borradores) y restaurar esa copia los trae de vuelta. Se eligió sobre dejarlos en su lugar porque sus renglones apuntan a cuentas que el respaldo reemplaza: dejarlos mezclaría un corte de hoy con cuentas de otro día.
- **Escritura comprobada:** cada coordinación de archivos revisa su error; el archivo leído se compara byte por byte con lo escrito y además se abre con la contraseña. El sellado (PBKDF2) y la escritura corren fuera del hilo principal: «Respaldar ahora» y restaurar ya no congelan la pantalla.
- **Nombres:** calendario gregoriano y la zona del iPhone en el archivo diario, «solo-gastos» y «antes-de-restaurar» (antes, UTC daba la fecha de mañana a las 21:00 en México). Compatibles con los ya escritos.
- **Llavero:** «no hay contraseña» se distingue de «no se pudo leer» (iPhone bloqueado desde que se encendió), con su mensaje. Guardar actualiza (`SecItemUpdate`) y solo agrega si no existe; si falla, la pantalla lo dice. La automatización que no puede abrir los gastos anota el fallo.
- **Captura:** un pago con aviso (`rawNotice`) y otro sin él —las dos automatizaciones— se comparan solo por monto y moneda dentro de 2 minutos y el segundo queda «¿Repetida?». La guía de iOS 27 pide borrar la automatización vieja de «Transacción». Monedas de tres decimales (KWD, BHD, OMR, JOD, TND, LYD) leen tres dígitos finales como decimales; un aviso con moneda que no se pudo leer siempre se anota. «te envió», «te mandó» y demás se buscan como palabras completas.
- **Gastos fijos:** dos originales con el mismo `fixedID` dejan uno, el mismo en todos los dispositivos (el de fecha menor; conserva el `repeatsThrough` mayor). Un original que empieza desde un plan lleva menos de medio milisegundo propio en su fecha para que dos dispositivos se distingan; si nada los distingue (los de antes), se quedan los dos y se anota una sola copia. El plan sale de Ajustes solo después de guardar. Marcar un gasto viejo como fijo repite desde el último cobro que ya pasó; cambiar la fecha nunca deja `repeatsThrough` antes de ella. «Dejar de repetir» deja el original como fijo ya cobrado (`isRepeat` y `fixedOf` a sí mismo) y busca el original por `fixedOf`; comercio y monto solo para copias de antes.
- **Guardado:** Siri hace `rollback` si no guarda; la reparación de comercios del banco no toca un nombre escrito a mano; el monto no se reescribe si su texto no cambió (0.125 ya no pasa a 0.13); «No es repetida», «Sí cuenta» y «No cuenta» guardan y avisan como el resto.
- **«Al día no pudo abrir tus gastos»** se desplaza con letra grande; no se agregó restaurar desde ahí (sin almacén de gastos no hay dónde restaurar).
- **Revisión independiente (mismo día), corregida antes de fusionar:** «Parece un iPhone nuevo» ya no depende de que la carpeta tenga algo: se compara con el respaldo diario más reciente (gastos y «Mi dinero» con contenido), así que quien solo usa «Mi dinero» o vació todo después de un respaldo vacío sigue respaldando; un iPhone con pocos gastos (5 o más menos y menos de la mitad) o sin «Mi dinero» frente a ese respaldo escribe aparte y no limpia; si ese respaldo no se puede leer (otra contraseña, o solo en iCloud), escribe el del día pero no limpia. Los nombres con años imposibles («al-dia-2569-…», de un calendario budista) no cuentan entre los 30 y no se borran. Antes de apartar un «Mi dinero» dañado se comprueba todo lo del respaldo (cifras y la cuenta de cada línea de cortes y borradores) y se reintenta abrirlo una vez; si restaurar en el almacén nuevo falla, se borra el nuevo y los archivos dañados regresan a su lugar. La copia «antes de restaurar» se vuelve a tomar si mientras se sellaba llegó un pago (conteo y fecha más nueva), hasta 3 veces. El dinar iraquí sale de los de 3 decimales (iOS lo escribe sin decimales) y en dinares solo se leen 3 decimales tras un punto sin otro separador antes, o tras el otro tipo de separador; «JOD 1,250» o «1.250.500» no se adivinan y el aviso queda guardado. Entre automatizaciones también se pide un comercio que empiece igual o la misma tarjeta, y cada pareja es de uno a uno (una captura ya marcada y su pareja no marcan a otra). Dos originales del mismo fijo con la misma fecha exacta se quedan los dos: no se desempata por contenido (podría ser una edición, Netflix 299 → 329).

## 2026-11-02 · Segunda auditoría: «Mi dinero» y cálculos
Una segunda auditoría encontró fallas en «Mi dinero» y en los cálculos de «Hoy»; el dueño pidió corregirlas. Cada una con una prueba que la reproduce primero (`MoneyImportCommaTests`, `MoneyChangeTests`, `TodayMathAuditTests` en CentavoCore; `SecondAuditMoneyTests` en CentavoTests).
- **Importar:** con separador «,», un renglón que no tiene el mismo número de campos que el encabezado, o con exactamente tres dígitos después del monto, va a revisión («¿un monto con comas?»). Un código de moneda que no está en `Locale.commonISOCurrencyCodes` también.
- **«Desde sep» con las mismas cuentas** (`MoneyChange.since`, `MoneyCut.change(since:)`): cuenta solo las cuentas que tienen saldo en los dos cortes y se pueden convertir en los dos, archivadas incluidas (el corte como se hizo). Archivar no es pérdida y una cuenta nueva no es ahorro: precisa «el saldo inicial no es dinero ahorrado» (2026-10-31).
- **Tipo de cambio entre cortes:** si «Nueva cuenta» o «Cuenta» escriben uno que el último corte (de un mes pasado, con el suyo) no recibe y no hay corte a medias, espera en `dinero.cambiosPendientes` (UserDefaults; no es una cifra del dinero de la persona) y el siguiente corte empieza con él («el que escribiste», «Usar ese»). La hoja lo avisa. No va en el respaldo.
- **Meses del corte** (`MoneyMath.cutMonths`): nunca uno anterior al último corte terminado. Un corte de un mes pasado no pide cuentas creadas después de ese mes (`MoneyMath.belongs`); al terminarlo, esas cuentas siguen con el saldo del corte anterior, ya revisadas, para no caerse del patrimonio.
- **«Mi dinero» vacío** solo si no hay ninguna cuenta, ni activa ni archivada. Los pasos suman sin archivadas.
- **Corte a medias:** al abrir, los campos traen los saldos ya revisados y el movimiento guardado (`MoneyTyping`). Un texto que no se lee deja la línea sin revisar y lo dice en rojo; un movimiento ilegible también cuenta como pendiente.
- **«Nueva cuenta»** pide el subtipo de una deuda (Tarjeta, Préstamo, Otros) o de lo que te deben (Me deben, Por caer), como la primera vez. El tipo dice «Te deben» y «Debes».
- **Errores:** cambiar una cuenta que no se guarda hace `rollback` y avisa; «Descartar corte» que falla avisa y no cierra.
- **Hojas:** la del ingreso no se cierra al deslizar con cambios y muestra la moneda del ingreso aunque no esté entre las ofrecidas; en la importación con correcciones, el regreso del sistema se cambia por «Salir» con «¿Salir sin agregar?».
- **Animación:** el renglón que se abre en los pasos usa el pliegue de la app (`Theme.Motion.fold` y `.unfold`, 2026-10-29). Cada dibujo de «Mi dinero» tiene su propio cuadro de descanso, completo (`MoneyArtKind.rest`; Face ID en 0.88). La bienvenida usa un solo reloj para la cifra y las barras. `MoneyLoopClock` y `PlayOnceClock`: si el bajo consumo se enciende a media animación, quedan quietos para siempre.
- **Fijos mayores que el presupuesto** (`BudgetPace.fixedOverBudget`): cuando presupuesto − fijos del mes ≤ 0 es un estado propio. «Hoy», widgets y Siri dicen «Tus fijos pasan el presupuesto por $X» (con exactamente el presupuesto, «Tus fijos se llevan todo el presupuesto»), en latón y no en rojo: no se gastó de más. `dailyBase` nunca es negativo y «Hoy puedes gastar» es $0 en los dos modos. Precisa el «puede ser negativo» del 2026-10-22: lo sigue siendo por gasto de más, no por fijos.
- **Siri y lo apartado** (`BudgetPace.setAside`, `isShortForFixed`): si lo que queda no cubre los fijos por venir, «Te quedan $4,000 y faltan $5,000 de fijos.»; si sí, lo apartado nunca pasa de lo que queda. Precisa la frase del 2026-10-22.
- **La proyección de la nota del mes** suma los fijos por venir (`SpendingFacts.detect(reserved:)`).
- **«Te pasaste» redondea hacia arriba** (`BudgetPace.overBudgetShown`), como `OverspendPlan`: en el héroe, la barra, el widget y la cuenta al tocar la barra (donde «Llevas» lo sigue, para que la resta cuadre).
- **La hoja del presupuesto** con lo gastado igual al presupuesto dice «Este mes ya gastaste justo eso.».


- **Revisión independiente (mismo día), corregida antes de fusionar:** una cuenta archivada antes del corte (y por eso fuera de él) cuenta en «desde» con saldo 0 en el corte nuevo: cerrar Caja y pasar su dinero a Nu, o pagar Amex y archivarla, da 0 y no ±. Una cuenta creada después del mes del último corte guarda su saldo inicial en ese corte (así se ve de inmediato, 2026-10-31), pero «desde» solo cuenta las cuentas que existían en el mes del corte anterior (`MoneyMath.belongs` con `createdAt`, que va en el respaldo), y ya no se copia a cortes de meses en que no existía: bajo un corte más nuevo se ve con ese saldo inicial (`MoneyCut.shownEntry`, `worthToday`) hasta su primer corte. Si el dinero de la cuenta nueva salió de otra, Al día no lo puede saber: la hoja pide cambiar también el saldo de esa (si no, el patrimonio lo cuenta dos veces) y su baja sale en «desde». El tipo de cambio pendiente guarda el mes en que se escribió, solo entra a cortes de ese mes o posteriores y se borra al terminar uno (descartar no lo pierde); `update` no pone línea ni tipo en un corte a medias de un mes anterior a la cuenta, y el aviso de la hoja sigue la misma regla. Con fijos sobre el presupuesto, «Te pasaste» (pantalla, barra, widgets y Siri, `BudgetPace.isOverspent`) solo sale si se gastó algo fuera de los fijos, por lo que se gastó fuera de ellos; cobrar los fijos sigue siendo «Tus fijos pasan…». Siri dice el exceso entero y hacia arriba como la pantalla; la cuenta de la barra con fijos sobre el presupuesto cuadra al peso; la pantalla bloqueada dice «fijos: todo el presupuesto» en vez de «$0».

## 2026-11-02 · Segunda auditoría: textos y animaciones
Una segunda auditoría encontró fallas de textos, UX y animación fuera de «Mi dinero» y del respaldo; el dueño pidió corregirlas.
- **«Cómo funciona»:** «Tu mes en una barra» pasa a **«Tu mes en un boleto»**, con su dibujo (celdas por día, una en rojo, hoy delineado, los días por venir punteados); la cifra de arriba explica que se le suma o resta lo de días anteriores; el respaldo dice que necesita la automatización «Respaldar Al día» (sin ella no hay copia diaria).
- **Gastos fijos:** tocar uno que aún no empieza abre su hoja para cambiarlo (mismo id; si su primer cobro ya llegó, empieza). Al editar uno ya iniciado, la hoja avisa que el monto también cambia el primer cobro y sugiere dejar de repetirlo y agregar otro para un aumento (la lógica la revisa otra sesión). «Por venir» dice que **ya se apartó** de «Hoy puedes gastar».
- **Renombrar una categoría o forma de pago renombra también los gastos** que tienen exactamente el nombre viejo (mayúsculas, acentos y espacios no cuentan), en un solo guardado y con aviso si falla. Ocultar o borrar sigue sin tocar los gastos.
- **«Anotar otra vez» se deshace** con la misma barra de «Borraste…»: «Anotaste otra vez {nombre} · Deshacer» borra la copia.
- **«Guardar dónde pagas» con la ubicación negada:** se ve apagado y sin tocar, y el pie dice «La ubicación está apagada para Al día en Ajustes del iPhone.» Se vuelve a leer al regresar a la app.
- **Letra grande:** las pastillas de montos de la bienvenida y los ejemplos de búsqueda bajan de renglón (`WrapLayout`); «¿Borrar este gasto?» se vuelve una hoja grande que se desplaza con letra de accesibilidad.
- **Textos:** «cada pago con Apple Pay se anota solo»; «Más › Presupuesto del mes» y «Más › Gastos fijos»; «Ya tienes una con ese nombre»; «No hay un monto en «…». Escríbelo arriba.» (los diálogos de Siri siguen en primera persona); VoiceOver dice «Día 15: todavía no llega» y «Ver cuenta» como en pantalla; la ficha del día dice «tu cifra por día», no «tu tope». Los encabezados en mayúsculas de «Hoy» usan `ticketCaption()`/`SectionLabel`, y «Ver todo el mes» es un `SecondaryButton`.
- **Íconos del respaldo:** `lock.doc` en Ajustes y `exclamationmark.triangle` en el aviso de «Hoy» (el respaldo no es de iCloud).
- **Animaciones:** las historias cambian en dos tiempos (sale la vieja, luego entra la nueva; `storyChange`), nunca encimadas; su barra es una sola animación lineal que se detiene al sostener. La celda de hoy respira hasta que el boleto terminó de entrar (`breathes(begins:after:)`). La demostración de la bienvenida, la cadena de Wallet y la respiración revisan `MotionPolicy` antes de cada paso y saltan al final si se volvió quieto. El renglón nuevo de la demostración solo aparece (sin bajar sobre la perforación). La guía del atajo y la barra de deshacer usan `Theme.Motion.animation(_:reduceMotion:)` y solo opacidad con «Reducir movimiento». El bucle de «Conecta el importe» se detiene en la página que no está a la vista. En «Hoy» vacío el reloj de 30 cuadros envuelve solo los dibujos de las tarjetas.
- **Rendimiento:** los números del mes y la nota se recalculan con un contador de guardados (`HomeModel.revision`, que sube con cada guardado y con lo que trae iCloud) y los conteos, no con un hash de cada fila. «Pagos y categorías» lee solo categoría, tarjeta y fecha al abrir, sin `@Query`.
- **Código muerto fuera:** `Theme.Motion.pulse`, `resize`, `Entrance.bar(_:)`, `barStart`, `Money.sheenRest`, `MoneyMotion.stillForTests`.
- **«Tu mes empieza aquí»** pasa a `ticketCaption(strong:)` (antes letra de cuerpo con interletrado a mano): queda más chico y en gris, como los demás encabezados de bloque.
- **Revisión independiente (mismo día), corregida antes de fusionar:** renombrar guarda primero los gastos y solo si se guardaron cambia el catálogo, las reglas y el color; si falla, la hoja se queda abierta con lo escrito y lo dice, y se puede reintentar. Renombrar una forma de pago se recuerda (`UserCatalog.cardRenames`, sincronizado) y el siguiente pago de Wallet con el nombre viejo llega con el nuevo; los fijos por empezar también se renombran. «Hoy» vuelve a usar una huella ligera de las filas (id, fecha, monto, lo que cuenta, moneda, categoría) junto al contador: el contador solo no veía lo que iCloud o un respaldo mezclaban después. Guardar un plan que entretanto empezó avisa en vez de duplicarlo, y la categoría se aprende solo si cambió. «Deshacer» de una copia ya borrada solo quita la barra. «Pagos y categorías» se vuelve a leer con cada guardado. El bucle de «Conecta el importe» se congela donde va al salir de la página (sin saltar mientras se desliza). La celda de hoy se marca como respirada hasta que de verdad empieza.

## 2026-11-02 · «Ver más» de categorías se abre hacia abajo
Pedido del dueño: que se abra «de manera más pulida hacia abajo» en la hoja del gasto. Visto en video del simulador antes de cambiar: al tocar «Ver 7 más», las categorías a la vista brincaban abajo y arriba mientras crecía el cuadro, las nuevas entraban con un pequeño zoom y «Ver 7 más» y «Ver menos» se encimaban.
- **Las categorías a la vista no se mueven:** la rejilla ya trae todas en su lugar (`RevealGrid`, en Components) y solo muestra la altura de las primeras; «Ver más» abre el espacio hacia abajo (`fold`) y las demás aparecen en orden, cada una cuando el espacio llega a ella, sin zoom.
- **Al cerrar, primero se desvanecen y luego se cierra el espacio** (`foldClosed`), como el resto de los pliegues (2026-10-29).
- **El texto del botón cambia de golpe** («Ver 7 más» ↔ «Ver menos»): mezclado mientras el botón se mueve se leía como una mancha.
- Las ocultas no son botones ni las ve VoiceOver: solo guardan su lugar. Las formas de pago no tienen «Ver más»: se ven todas.

## 2026-11-02 · Las pruebas de interfaz otra vez en verde
Pedido del dueño: «arregla las pruebas que están fallando en GitHub». Las pruebas del simulador (que corren al entrar a `main`) fallaban desde el 2026-10-31: 23 de 89.
- **Un «hoy» fijo para la demostración** (`AppClock`, solo en DEBUG y solo con `-centavo-demo`): los gastos de ejemplo van del día 1 al 12 y solo se mostraban los que ya habían pasado; en los primeros días del mes faltaban casi todos y 18 pruebas fallaban por la fecha. La demostración vive el día 20 del mes en curso, con el reloj corriendo. Toda la app lee la hora de `AppClock.now` (fuera de la demostración es la del sistema), también «hace 1 h» y «hoy».
- **Un error real que encontraron:** con la letra más grande, «Llevas $X de $Y · $Z/día» no se partía y empujaba la página fuera de la pantalla; ahora pasa a dos renglones.
- **Pruebas al día con la app:** «Dilo en una frase» se espera a que se guarde el teclado (el botón está donde va «Siguiente»); la hoja de «No cuenta» se desplaza antes de buscar «Tipo»; la guía paso a paso se salta en iOS 27, donde «Configurar atajo» agrega el atajo armado.

## 2026-11-02 · Deslizar hacia arriba sobre el código del mes mueve la pantalla
Pedido del dueño: arreglar el error que encontraron las pruebas. Un deslizamiento hacia arriba que empezaba sobre «Cada día del mes» no movía la pantalla (desde la cifra o la lista sí).
- **La causa:** el gesto de «mantener y deslizar» para leer los días (`LongPressGesture` seguido de `DragGesture` de SwiftUI) se quedaba con todo toque que empezara ahí.
- **Ahora es el «mantener» del sistema** (`HoldAndSlide`, en Components): hasta que se mantiene el dedo, el toque es también de la pantalla y del carrusel; una vez que se mantiene, deslizar lee los días como antes. Tocar un día y deslizar de lado al calendario no cambian.
- Prueba nueva: `testDeslizarHaciaArribaSobreElCodigoMueveLaPantalla`.

## 2026-11-02 · Trabajar como Orbital: rápido y directo a `main`
Pedido del dueño: «tú tardas demasiado… ve cómo trabaja Orbital y trabaja igual». Orbital hace commits directos a `main` (decenas al día, sin PR) y su CI no corre pruebas en el simulador. Centavo hacía, por cada cambio: rama, PR, esperar la CI (~4 min, a veces cancelada por falta de Macs en GitHub), una revisión con agente, pruebas en el simulador y a veces la suite completa (~35 min aquí, ~60 en GitHub).
- **Directo a `main`** tras `Tools/verify.sh`; la CI corre después y no se espera. Reemplaza «Una rama por issue, PR, squash-merge» (2026-10-11) y «En un PR la CI decide el merge» (2026-10-20).
- **En el simulador, solo las pruebas de lo que cambió.** La suite completa se queda en GitHub al entrar a `main`.
- **Revisión con agente solo para cambios que pueden perder datos.**


## 2026-11-05 · Ritmo: una curva, una separación, un renglón
Pedido del dueño: aplicar «Rhythm» a todo el sistema de diseño (opción R1a, tras ver capturas reales de antes y después).
- **Curvas:** 12 para tarjetas, campos, botones y el boleto; 4 para barras y días; 28 para hojas. Se acaban las de 2, 3, 6, 8 y 10.
- **Espacios de 4 en 4** (4, 8, 12, 16, 24, 32); 24 es la separación entre bloques.
- **Excepción:** las tarjetas de «En qué se va» conservan su aire de antes (`tileLine`, `tileItem`); con la escala, Despensa y Salidas perdían su monto.
- La regla vive en [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) («Ritmo»).

## 2026-11-11 · Tercera auditoría: punta a punta
Pedido del dueño: una auditoría de arquitectura, código e interfaz para dejar la app más ligera, más rápida y mejor armada. Reporte y decisiones pendientes: https://claude.ai/artifact/VCXfEzWnKd2LLUW8dWdF4P. Primera tanda (errores), sin cambios a la vista con letra normal:
- **Reglas nuevas del repo:** el área de toque va dentro del botón (`.buttonStyle(.tapTarget)`; el lint falla con un `.frame` de 44 por fuera de un `Button`), y dos textos en un renglón se apilan con letra de accesibilidad (la fecha y el folio de «Hoy» se cortaban a «VIE 2… N.º 0…»; prueba `testLaFechaYElFolioConLetraDeAccesibilidadSeApilan`). La firma de las barras es un componente (`Signature`) que deja de crecer donde la barra.
- **Los widgets se recargan solo si cambió lo que muestran** (`WidgetSnapshot.needsReload`): la foto del mes lleva su hora, así que el «no reescribir si es igual» nunca se cumplía y cada guardado, cada regreso y cada intent gastaba una recarga. Se sigue escribiendo siempre (para «Actualizado hace X») y se recarga con un cambio, un día nuevo o una hora de diferencia.
- **Editar un gasto de 1,000 o más ya no reescribe su monto** si no se tocó (el campo lo reagrupaba a «1,234.13» y se leía como escrito de nuevo; 1,234.125 pasaba a 1,234.13).
- **Guardados:** «Borra el último gasto» hace `rollback` si no guarda; la primera vez de «Mi dinero» no cambia de paso si el renglón no se guardó.
- **La contraseña del respaldo se oculta** al salir de la app o de la pantalla.
- **«Borrar» ya no se ofrece** en una forma de pago que solo llegó en los pagos (no había qué borrar).
- **VoiceOver en «Cada día del mes»** parte de hoy y no pasa a días que no llegan.
- **Un pago ilegible por «Registrar gasto»** también se anota para «Hoy» (`UnreadNotice`), como el de la otra automatización.
- **Velocidad (tanda 2, nada visible cambia):** tocar un día o una categoría ya no rehace los números del mes, solo la lista (`HomeModel`: `MonthNumbers` aparte de la lista filtrada); recordar la categoría de un comercio al capturar lee cinco datos de cada gasto y no la fila entera; «Respaldo» se arma al abrirse y no cada vez que se dibuja Ajustes (`Deferred`); el aviso del respaldo en «Hoy» se calcula fuera del hilo principal.
- **Medido:** la versión Release compila (era la primera vez) y su código pesa 4.8 MB; la de desarrollo, 27.6 MB.
- **CI:** compila Release y dice su peso; las pruebas de datos (`CentavoTests`) tienen su propio trabajo; el simulador corre en dos máquinas (capturas y flujos) y ya no se cancela con cada push. `verify.sh` usa `/tmp/dd-centavo` y espera por `xcodebuild` (máximo 2), no por cualquier compilación de Swift.

## 2026-11-11 · Revisión de UX/UI: 27 propuestas y tres decisiones
Revisión sobre 107 capturas reales (https://claude.ai/artifact/NyJKhqRUnTbudnh1xVR7Vt). El dueño aprobó todas las propuestas («vamos con tu propuesta») menos la U25, que no mencionó y queda como estaba; la U3 ya estaba corregida. Y decidió: **D1a** (un presupuesto fijado a mitad de mes da la cifra de un día normal: presupuesto ÷ días del mes), **D2a** («Corte N.º» cuenta solo los cortes hechos a mano) y **D3b con buscador**.
- **Reglas nuevas del repo:** el latón es solo para lo que se toca, lo elegido y la cifra principal (U19; los avisos, con `WarningText`); todo selector de menú es `TicketMenuPicker` (U13) y lo que va sobre el teclado es `.keyboardBar` (U18), las dos revisadas por el lint; toda pantalla principal usa el margen, las líneas punteadas y las separaciones de «Hoy» (U5, cabecera compartida `TicketHead`); la app se queda en vertical (U27).
- **«Mi dinero»:** mismos márgenes, perforaciones y cabecera que «Hoy» (pasa de `List` a `ScrollView`); «Corte» con su nombre en la barra y «Hacer corte de noviembre» bajo el patrimonio cuando ese mes no tiene corte hecho (no en el mes de inicio); el corte en dos líneas por cuenta con «Sin cambio» bajo el monto y «Escribe el saldo» (reabre «el saldo anterior es el texto de ejemplo», 2026-10-31; quedó en ~78 pt por renglón, no 64, por el toque de 44); la barra del paso con piso y, apagada, «Falta una cuenta»; tarjetas que crecen con su texto; «Pegar» como paso principal (su ancho y su título los fija iOS).
- **«Hoy»:** un día con un solo gasto no repite su total; la ficha del día en dos renglones con su frase completa («$43 arriba del tope del día»); en el filtro, el resumen en gris y «Quitar filtro ✕» en latón; el menú «Más» dice «Presupuesto» y «Categorías» (reabre parte de «Un solo lenguaje», 2026-10-29; el título de la pantalla sigue siendo «Pagos y categorías»); con letra de accesibilidad el calendario vuelve a ser de cuadros; el mosaico cede su renglón a «Menos devoluciones»; el final de la lista se desvanece bajo la barra en vez de teñirla; «Guardar» abajo en «Tu presupuesto» (reabre «hoja del presupuesto 2.0», 2026-10-29).
- **Hoja del gasto y ajustes:** «Dilo en una frase» es un renglón con palabras bajo el monto, siempre a la vista en un gasto nuevo (cambia «ícono junto al monto»); «Pagos y categorías» a tres columnas y con la leyenda de ★ y ))) solo cuando aplica; el aviso del respaldo «aparte» en una línea con dos salidas («Este iPhone es el bueno», «Restaurar el respaldo anterior»).
- **Bienvenida y «Cómo funciona»:** días del calendario de 44 pt; los títulos son preguntas («¿Cuánto puedes gastar hoy?», «¿Y si cada pago se anota solo?»); las sugerencias de presupuesto van arriba del campo; el título de cada historia queda en el mismo renglón.
- **«Lo que recuerdo» (D3b):** arriba «Con el nombre que les pusiste»; abajo, plegado, «Solo su categoría» (abierto si arriba no hay ninguno); buscador por comercio, nombre o categoría.
- **Se quedan en latón, decidido por el dueño (2026-11-12, E2a):** el encabezado de cada día de la lista, los puntos «·» entre partes de un renglón y el monto de una devolución. Son las tres excepciones a «el latón es para lo que se toca».
- **Encontrado por la CI en iOS 26 (2026-11-12):** con «Dilo en una frase» en su renglón, en un iPhone más chico y con el teclado arriba las sugerencias de comercio quedaban bajo «Guardar» y el toque caía en la barra. Al enfocar el comercio, la hoja lo lleva arriba. Regla: lo que aparece al escribir (sugerencias) debe quedar a la vista sobre el teclado y la barra de guardar también en el iPhone más chico de la CI.
- **El sello de versión de «Ajustes» entra como ajuste de compilación** (`CURRENT_PROJECT_VERSION`, `CENTAVO_COMMIT`, que pasa `Tools/instalar.sh`), ya no lo escribe un script después de compilar (`Tools/stamp-build.sh`, 2026-10-30): su lugar entre los pasos de Xcode quedaba al azar; al instalar la versión Release se perdió el sello una vez y otra rompió la firma del widget. Una compilación que no sea de `instalar.sh` dice «compilación 1 · local».
- **Decidido el 2026-11-12:** la ficha del día se queda en dos renglones aunque pise un poco la cifra mientras se mantiene el dedo (E1); «Lo que recuerdo» sale abierta cuando ningún comercio tiene nombre (E3a); la presentación de «Mi dinero» se queda como estaba (la U25 no se aplica).
- **De paso:** la CI compila con un Xcode más lento para revisar tipos y el commit de los huecos no compilaba allá; el cuerpo de «Hoy» va en etapas y `verify.sh` falla con expresiones de más de 300 ms. En iOS 26 `rollback()` no devuelve al momento los valores a los objetos en memoria (en iOS 27 sí), pero lo guardado queda intacto: las 249 pruebas de datos pasan en iOS 26.3.

## 2026-11-11 · Mapa de estados: los once huecos graves, y «Lo que recuerdo»
El dueño pidió un mapa de todos los estados (https://claude.ai/artifact/HMMoHZeGDwTAcSQcjs8WT4: 378 estados, 69 huecos) y cerrar los graves con las propuestas del mapa («dale con tu propuesta»). El mismo día pidió que un cargo corregido se recuerde como regla y «una pantallita» para verlas. Revisión de UX/UI aparte, sin aplicar: https://claude.ai/artifact/NyJKhqRUnTbudnh1xVR7Vt.
- **Regla nueva del repo: un pago que la captura recibe y no puede anotar nunca se pierde.** Se guarda fuera del almacén (`UnreadNotice`, lista `respaldo.pagosPendientes`, que no viaja en el respaldo ni se pisa al restaurar) y solo la persona lo quita. Un intent de captura reintenta abrir el almacén una vez y nunca lanza un error sin dejar antes el pago ahí.
- **Pagos pendientes** (`PendingPayments`): los ilegibles y los que no se pudieron guardar se juntan en un recuadro de «Hoy» («2 pagos no se pudieron leer», «1 pago no se pudo guardar», mezclados «N pagos sin anotar»), también en la pantalla vacía, con «Anotar» (abre la hoja ya llena con lo que se leyó; el pendiente se quita solo si se guardó) y «Descartar». Tope de 20 (salen primero los ilegibles) y 30 días. Cambia «el aviso se borra al llegar un pago bueno o al tocarlo y caduca a las 48 h» (2026-10-18): solo un aviso sin cifra ni moneda se quita solo, y solo si ese mismo comercio se anotó en los 2 minutos de alrededor (las dos automatizaciones).
- **La guía solo dice «Ya funciona» con un pago que llegó a este iPhone después de abrirla** (`CaptureProof`, marcas `respaldo.esteIPhone.*`); si el último es anterior, «Último pago: ayer. Paga algo con Apple Pay para comprobar.» Un respaldo restaurado o un pago que llegó por iCloud no son prueba. Cambia «Ya funciona si llegó un pago en los últimos 3 días» (2026-10-15).
- **Historial del presupuesto** (`BudgetHistory`, llave `budgetHistory`, sincronizada y en el respaldo): «desde tal día, tanto / sin presupuesto». `monthlyBudget` sigue siendo la verdad del vigente. Quien tiene presupuesto y ningún cambio anotado es «desde siempre»: nada cambia para esa persona hasta que lo modifique; su primer cambio conserva la cifra anterior para los meses pasados.
  - **Los meses pasados se juzgan con el presupuesto vigente al cerrar ese mes.** Si cerró sin presupuesto: el total y «Este mes no tenías presupuesto.»
  - **Un presupuesto fijado a mitad de mes cuenta desde ese día** con «Se acumula»: por día sigue siendo (presupuesto − fijos) ÷ días del mes (la cifra de «Cada día tienes $X»), y hoy = por día × días desde ese día − lo gastado fuera de fijos desde entonces. Lo de antes sigue en «Llevas» y «Te quedan», pero no es sobrante ni exceso. Hoy nunca ofrece más de lo que queda del mes. Cambiar el monto no mueve el día; quitar y volver a poner el mismo mes tampoco. La cuenta lo dice: «Tu presupuesto cuenta desde el 14 nov.» Widgets y Siri, la misma cifra (`WidgetSnapshot.startDay`). Queda a confirmación del dueño la alternativa de repartir lo que queda entre los días que faltan.
  - Restaurar un respaldo o recibir el presupuesto por iCloud no fecha «hoy» un cambio (revisión independiente): solo la hoja y la bienvenida anotan cambios; lo demás se concilia (`settleHistory`). «Del futuro» es posterior al día en curso, no al instante (la pantalla guarda su hora y descartaba el cambio recién hecho; lo encontró la prueba de interfaz).
- **Restaurar nunca reemplaza sin una copia visible:** la copia «antes de restaurar» va a la carpeta del respaldo o a una que se elige en ese momento (no cambia la del respaldo), comprobada; sin carpeta no se restaura. «Vacío» es sin gastos, sin «Mi dinero» y sin presupuesto ni listas propias. Cambia «en la carpeta y en Documentos de la app» (2026-10-31). Las copias que ya estaban dentro de la app se listan en «Respaldo» para restaurarlas, guardarlas en Archivos o borrarlas.
- **iPhone recién restaurado:** «Seguir respaldando aquí» guarda la contraseña con que se abrió el archivo (nunca pisa una existente) y toma o pide la carpeta; con «Ahora no», la pantalla y «Hoy» lo avisan, no más de una vez por semana.
- **«Al día no pudo abrir tus gastos»** dice si es falta de espacio, tiene «Intentar de nuevo» (`Store.retry`, nunca abre dos veces) y «Guardar una copia de mis datos» (los archivos del almacén tal cual a Archivos, tras `OwnerCheck`). Sigue sin ofrecer restaurar desde ahí (2026-11-02).
- **«Mi dinero»: los saldos iniciales son el punto de partida, no un corte** (`MoneyStart`, sin cambiar el esquema: se deduce de fechas que ya viajan). El primer corte del mes de inicio no pregunta «¿Reemplazar?» y se compara «desde el inicio»; el mes de inicio puede tener dos cortes terminados. «Corte N.º» cuenta solo los hechos a mano (a confirmación del dueño).
- **Importar CSV clasifica en nuevos, ya están y parecen repetidos** (`CSVImportPlan`): reconoce tarjetas renombradas y comercios corregidos; lo que tiene el mismo momento, monto y moneda con otro nombre o tarjeta se pregunta («Solo los nuevos» por defecto) y el resultado dice cuántos quedaron fuera. Precisa «mismo momento en otra tarjeta es otro gasto» (2026-11-02): ahora se pregunta.
- **«Lo que recuerdo»** (`MerchantRules`, en «Más › Pagos y categorías»): el motor ya existía (`merchantRenames`, `categoryRules`, sincronizados y en el respaldo; coincidencia exacta salvo mayúsculas, acentos y espacios: otra sucursal es otro comercio, 2026-10-11). Nuevo: renombrar conserva la categoría como elección del nombre nuevo; la regla se aprende después de guardar bien; «Cambiar también los otros N gastos» en la hoja (nunca toca una categoría puesta a mano ni los fijos); y la lista «Lo que llega como… → Se anota como…» para cambiar u «Olvidar». Vocabulario «recordar / olvidar», sin la palabra «regla» en pantalla.

## 2026-11-11 · Tercera auditoría: las trece decisiones del dueño
El dueño aprobó las recomendaciones del reporte («vamos con tus sugerencias»): A1a, A2b, A3a, A4b, A5b, A6b, A7b, A8a, A9b, A10b, A11b, A12b, A13b. Mapa de estados pedido el mismo día: https://claude.ai/artifact/HMMoHZeGDwTAcSQcjs8WT4.
- **A1a · En su iPhone va la versión Release** (`Tools/instalar.sh`: Release, sin símbolos, firma gratuita). La de desarrollo pesa cinco veces más y no está optimizada.
- **A2b · La app funciona desde iOS 26.** Cambia «iOS 18+» (2026-10-11): el camino de iOS 18 a 25 se compilaba y nadie lo probaba. Se van las ramas `#available(iOS 26, *)`; la guía paso a paso para iOS 26 se conserva.
- **A3a · Un respaldo guardado «aparte» se dice y se puede resolver.** Queda una marca (`respaldo.aparte`) con su motivo; «Respaldo diario» lo explica («este iPhone tiene menos gastos (118) que el respaldo del 10 nov (131)») y «Hoy» lo avisa, al final de los otros avisos. «Este iPhone es el bueno» (tras confirmar y `OwnerCheck`) escribe el diario desde este iPhone; el diario del día que reemplaza no se borra: queda como `al-dia-reemplazado-<fecha+hora>`, que ninguna limpieza toca, y esa noche no se limpia nada. De los «aparte» se conservan los 5 más nuevos, con las mismas precauciones que la limpieza de diarios. Un «aparte» sigue contando como «Último respaldo» (está completo y comprobado). Un iPhone vacío sigue siendo «Parece un iPhone nuevo» aunque se confíe en él.
- **A4b · «Guardar» abajo con resumen** también en «Cuenta» e «Ingreso» de «Mi dinero» (`saveBar`); el corte se queda con su botón arriba.
- **A5b · «¿Descartar cambios?»** (`confirmsDiscard`): «Cancelar» o deslizar una hoja con cambios pregunta una vez, con «Descartar» y «Seguir editando». En el gasto, el gasto fijo, la categoría o forma de pago, el presupuesto y las hojas de cuenta e ingreso. El corte no: su borrador se conserva al cerrar.
- **A6b · Una sola forma de preguntar antes de borrar** (`TicketQuestion`, `confirmsRemoval`): la hoja propia de los gastos (2026-10-21), generalizada, también para dejar de repetir, borrar un fijo, una categoría o forma de pago, archivar una cuenta, quitar un ingreso o un renglón, descartar un corte y quitar el presupuesto. Siempre «Conservar». Las alertas de error y las preguntas que no son borrar («¿Reemplazar el corte…?», «¿Salir sin agregar?») siguen siendo alertas.
- **A7b · La barra de abajo de los pasos de «Mi dinero» tiene piso** (`safeAreaBar`, como «Guardar») y las pestañas se esconden durante la primera vez y la importación (solo con «Mi dinero» desbloqueado, para que cancelar Face ID no deje sin salida).
- **A8a · Los renglones de «En qué se va» se quedan en 29 pt:** caben cinco sin desplazar y van pegados. Excepción con nombre (`shareRow`).
- **A9b · Una frase por tipo en la primera vez de «Mi dinero»:** «Agregar una cuenta», «Agregar un préstamo», «Agregar algo que te deben»…; el renglón nuevo, «Cuenta nueva», «Préstamo nuevo».
- **A10b · Miles con coma al escribir saldos y montos de «Mi dinero»**, también en el corte, con su signo (`groupsMoney`); nunca en tasas ni tipos de cambio.
- **A11b · Con presupuesto y sin gastos se ve el boleto vacío,** igual que cualquier otro día; se va la barra con riel (2026-10-15…29), que solo quedaba en ese estado, con unas 370 líneas.
- **A12b · «N sin revisar» en el corte se toca** y lleva al siguiente renglón pendiente.
- **A13b · Borrar una forma de pago o categoría con gastos lo dice antes:** «12 gastos la tienen» y «Seguirá en la lista porque llegó en tus pagos. Tus gastos no cambian.» No cambia que borrar no toca los gastos (2026-10-22).
- **Del mapa de estados, corregido de paso:** en un iPhone con coma decimal (España, Argentina, Alemania…) editar un gasto o el presupuesto mostraba el monto cien veces mayor («1234,50» perdía la coma); lo que la app escribe en un campo va siempre con punto (`AmountTyping.written`).
- **Gastos fijos:** las copias de un fijo detenido ya no cuentan como copias «de antes» (`FixedCopies`), así que no dan por anotado el cobro de otro fijo igual. Queda sin resolver, a propósito, el caso de un original **borrado** y otro idéntico creado el mismo periodo: no se distingue de una copia cuyo original está en otro dispositivo; la salida sería una lista sincronizada de ids retirados.
- **Prueba nueva:** `BackupCoverageTests` falla si una propiedad de `Expense` o de los modelos de «Mi dinero» no viaja en el respaldo.

## 2026-11-08 · El talón, el promedio junto al ritmo y el widget como la app
Pedido del dueño: algo más creativo para «Ver cuenta», el promedio por día en el renglón del ritmo y widgets con el estilo de la pantalla. Eligió en el lienzo (https://claude.ai/artifact/B8MZLgZyzpLDnk7XXTULG8) P1, B1 y W2.
- **P1 · Perforado fino:** sin la pista del mes, «la cuenta» se abre desde una línea de puntitos redondos con «cuenta ⌄» al centro (`Perforation(tear: true)`, `Dash.tear`). Queda abajo para que la cuenta baje desde el corte; abierta va sin panel, separada por los mismos puntitos. Sin muescas: en Hoy el boleto no tiene orilla visible. Reemplaza «Ver cuenta» bajo el boleto.
- **B1 · Promedio junto al ritmo:** «Vas $665 abajo del ritmo · $711/día» (lo que llevas entre los días que van). El renglón de abajo no cambia. Revierte «sin el promedio por día» del 2026-11-04.
- **W2 · El widget mediano con los dos renglones:** con el boleto, el ritmo sale de la esquina y va bajo los días con su promedio, y abajo «Llevas $X y podrías llevar $Y de $Z», sin mayúsculas; la cifra baja a `figure` para que quepa. Los días que se pasaron llevan tapita roja (`widgetCap`).
- **Ajustes del mismo día, tras verlo en su iPhone:** el widget mediano se queda solo con el renglón del ritmo (sin «Llevas … y podrías llevar …») y recupera su cifra grande; el ritmo y «Llevas» quedan más juntos en Hoy; y la cuenta ya no se dobla en 3D («como una hoja que se cae de atrás para adelante»): sale de debajo del corte, recta hacia abajo, como un recibo de la impresora (`.printOut`), su último renglón al paso de la página.
- **L3 · «Llevas…» dentro de la cuenta (mismo día):** en Hoy, dentro del presupuesto, ya no va el renglón «Llevas $X y podrías llevar $Y de $Z». La cuenta abre con «El ritmo» (A hoy podrías llevar − Llevas = Vas abajo/arriba del ritmo) y luego «Hoy»; con «Repartir» se omite el primer bloque (Presupuesto − Llevas = Te quedan) porque el de hoy ya empieza así. Pasado del presupuesto y en meses cerrados, «Llevas $X de $Y» se queda. Se descartaron L1 (la frase tal cual) y L2 (un renglón suelto).
- **La cuenta sin encimarse (mismo día):** el dueño vio que al abrir y cerrar la cuenta se enciman las cosas. En video: el carrusel medía su nueva altura un paso después y solo él la animaba; la lista de abajo («Wallet», «Hoy», pagos) brincaba a su lugar final y, al cerrar, la cuenta pasaba encima. Ahora la altura medida se cambia dentro de `withAnimation(Theme.Motion.fold)` (`MonthCarousel.setHeight`), así la lista se mueve con la misma curva; también aplica a «Mínima», que antes usaba `restyle`.
- **Sin promedio por día (mismo día):** el dueño lo quitó de la app y del widget; se revierte B1. Además: «Cada día del mes» entra con su propio tiempo (`Entrance.code`, 0.1 s + 0.3 s; antes `legend`, 0.9 s + 0.4 s, pensado para la barra que en Hoy ya no se dibuja), el ritmo justo después (`codeLine`) y «hoy» respira a los 0.5 s; el ritmo queda pegado al corte (sin espacio bajo la frase y el área táctil de 44 pt sube 8 pt).

