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
