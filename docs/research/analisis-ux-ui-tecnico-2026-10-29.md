# Análisis UX, UI y técnico de «Al día» (2026-10-29)

Hecho a pedido del dueño: revisión a fondo de la app (pantallas, widgets y código), y un onboarding y una guía del atajo nuevos. Lo construido va en el mismo PR; lo demás queda como propuesta, en orden de prioridad. Cada propuesta dice si toca una decisión aprobada (DECISIONS.md): esas no se hacen sin el OK del dueño.

## 1. Lo que ya se hizo en este PR

### Bienvenida nueva (4 páginas en vez de 5)
Buenas prácticas que sigue: **mostrar antes de pedir** (la primera pantalla es una demostración viva, no una lista), **una sola acción principal por pantalla** (botón ancho «Empezar»/«Continuar» abajo, al alcance del pulgar), **progreso visible** (puntitos y «Paso X de 4»), **todo se puede omitir y nada se pierde**, **respuesta inmediata a cada toque** (la cifra del día cambia al teclear) y **atajos de un toque** (montos y gastos fijos sugeridos).

1. **Al día**: un ticket animado. Llega un aviso de Wallet («Café del Sol · $65.00»), se dobla en la lista como renglón nuevo y «Hoy puedes gastar» baja con la cifra rodando y una vibración ligera. Se repite con tres pagos. Debajo, tres frases cortas.
2. **Tu mes**: moneda (selector MXN | USD | EUR, el mismo de la hoja de gasto) y presupuesto en una sola página. Montos de un toque (5, 8, 12, 20 mil; o 1, 2, 3, 5 mil en dólares y euros). Dentro de la tarjeta del monto, «Al día: $290» responde a cada tecla, y queda visible con el teclado abierto.
3. **Gastos fijos**: sugerencias de un toque (Renta, Luz, Internet, Celular, Netflix, Spotify, Gimnasio, Agua) que llenan el nombre y piden el monto. Cada fijo entra con animación, se puede quitar con ⓧ, y la tarjeta dice cuánto queda al día después de los fijos.
4. **Conecta Wallet**: la cadena «Pagas → Atajos avisa → Al día lo anota» se enciende nodo por nodo. Luego «Configurar ahora» o «Después».

Cada bloque sube y aparece después del de arriba. Con «Reducir movimiento» todo queda quieto y completo.

### Guía flotante (picture in picture) para configurar el atajo
- **El problema:** la guía vive en Al día y el trabajo se hace en Atajos, así que hay que ir y venir entre apps a cada paso.
- **La solución:** «Abrir Atajos» hace flotar una ventanita sobre Atajos, como un video de YouTube en picture in picture. Muestra la captura real del paso, con el aro latón donde hay que tocar y la frase de qué hacer.
  - Los botones ⏪ ⏩ de la ventanita pasan al toque anterior o siguiente. ▶︎ avanza solo, cada 8 segundos.
  - Al regresar a Al día, la guía está en el paso donde iba la persona.
  - Cuando llega el primer pago, la ventanita se cierra y la guía lo celebra con la palomita y una vibración de éxito.
- **No es un video grabado.** Cada imagen se dibuja en el momento con las mismas capturas que ya usa la guía. Así se resuelven las tres razones por las que se descartó el video el 2026-10-15:
  - no hay que grabar nada;
  - no se queda viejo con cada iOS, porque usa las capturas que ya se actualizan con `GuideScreenshotsTests`;
  - no pesa: 0 KB extra.
- **Lo que pide:** el modo en segundo plano «audio», que es el que Apple exige para picture in picture. La app no reproduce sonido y se mezcla con la música que estés oyendo.
  - Riesgo: App Review a veces pregunta por ese modo. La respuesta es «picture in picture de la guía de configuración».
- **Sin verificar en simulador:** el simulador no tiene picture in picture. Hay que probar la ventanita en el iPhone.

### Guía del atajo, pulida
Una barra fija abajo, en cada paso que se hace en Atajos: la miniatura de la guía flotante y «Abrir Atajos». Antes, el botón quedaba perdido a media página. La comprobación final celebra el primer pago.

## 2. UX y UI del resto de la app (propuestas)

Leyenda: esfuerzo **S** = horas · **M** = 1 o 2 días. **⚠︎** = toca una decisión aprobada.

### Victorias rápidas
1. **Pantalla vacía sin presupuesto.**
   - Hoy: quien omite la bienvenida ve un «$0.00» gigante y solo «Configurar atajo».
   - Propuesta: «Anotar un gasto» como botón principal, con «Fijar presupuesto» y «Conectar Wallet» abajo, y quitar el $0.00. (S)
2. **La cuenta escondida en la barra.**
   - Hoy: «Te quedan», «Fijos» y «Sobró» solo aparecen si alguien adivina que la barra se toca.
   - Propuesta: un «Ver la cuenta ⌄» pequeño. (S)
3. **«Más» es un cajón de sastre.**
   - Hoy: 9 renglones sin orden.
   - Propuesta: separarlos en secciones: Tu mes · Vista · Datos · Wallet. (S)
4. **Textos rotos.**
   - Tarjetas y categorías dice «Toca una para borrarla», pero tocar la edita.
   - «Dejar de repetir cada mes» quedó viejo: ya hay fijos semanales.
   - «Sugerida por Al día con tus gastos de ejemplo» no se entiende.
   - El mes de abajo sale en el idioma del teléfono y los días en es-MX. (S)
5. **Accesibilidad.**
   - VoiceOver lee la cifra principal sin «Hoy puedes gastar».
   - «Deshacer» desaparece en 6 s sin anunciarse.
   - Los íconos se leen con su nombre técnico («cart.fill»).
   - Los widgets de inicio se leen en pedazos. (S)
6. **Calendario y búsqueda.**
   - Al tocar un día, decir cuánto se gastó: «Día 12 · 2 gastos · $310».
   - En la búsqueda, ejemplos («Uber de octubre, más de 200»), porque ya entiende frases. (S)
7. **Aviso de captura rota.**
   - Hoy: una frase de 11 pt en mayúsculas.
   - Propuesta: dos renglones legibles, y «No uso Wallet» para apagarlo. (S)

### Apuestas grandes
8. **Hoja del gasto: lo común primero.**
   - Hoy: «Es una devolución», la moneda y «Cuenta para el presupuesto» van antes que la categoría.
   - Propuesta:
     - orden: Monto → Comercio → Categoría → Tarjeta;
     - la moneda como cápsula junto al monto;
     - «Tipo: Gasto / Devolución / No cuenta» dentro de «Más detalles». (M) ⚠︎ Toca decisiones del 2026-10-12, 10-16 y 10-23.
9. **Control «Anotar gasto»** en el Centro de control y en la pantalla bloqueada (iOS 18), y **«Anotar otra vez»** al mantener presionado un gasto. (M)
10. **Una hoja «Ajustes»** que vacíe «Más», y **letra mínima de 12 pt** para lo que lleva información; hoy hay datos en 10 y 11 pt. (M) ⚠︎ Mostrarlo lado a lado antes.

### Widgets
- **El «+» solo existe en el mediano.** Propuesta: que el pequeño abra «Anotar gasto» al tocar la esquina. (S)
- **Un widget sin datos dice «Sin presupuesto».** Eso pasa si la app nunca se abrió o con la cuenta gratuita sin App Group, y confunde.
  - Estado propio: «Abre Al día una vez».
  - «Actualizado hace 2 días» cuando pasen más de 24 h. (S)
- **StandBy:** comprobar que el latón se lea en el modo nocturno rojo. (S)

## 3. Revisión técnica: más rápida y más liviana

### Rendimiento
| # | Qué | Dónde | Ganancia | Riesgo |
|---|---|---|---|---|
| R1 | Instalar en el iPhone en **Release**, no en Debug (el README no dice `-configuration`). Desde hoy ya se instala así. | README | 3–10× en cálculos | bajo |
| R2 | La pantalla principal **recorre todo el historial unas 7 veces cada vez que se redibuja** (al deslizar un renglón o teclear en la búsqueda). Pasarlo a un modelo que solo recalcule cuando cambian los gastos o el mes. | `ExpenseListView.swift:89-113` | grande con miles de gastos | medio |
| R3 | La consulta principal trae **todos** los gastos de todos los meses. Usar consultas por mes, y para los fijos, el primer gasto y la búsqueda. | `ExpenseListView.swift:13` | arranque y memoria que no crecen con los años | medio |
| R4 | **Cada pago de Wallet lee todo el historial** para recordar la categoría, en segundo plano, con poco tiempo. Acotarlo a 12 meses. | `ExpenseRecorder.swift:174` | captura constante | bajo |
| R5 | La reparación de nombres de bancos corre **en cada regreso a la app**. Que corra una sola vez. | `ExpenseListView.swift:560` | regresar más rápido | bajo |
| R6 | **Widget atrasado tras un pago:** se refresca 300 ms después de guardar, y Atajos puede suspender el proceso antes. Refrescarlo al final de cada intent. | `WidgetBridge.swift:25` | widget confiable | muy bajo |
| R7–R9 | Cada renglón decodifica JSON de categorías, `.ticket()` busca la fuente 144 veces y el CSV se arma en cada redibujo. Cachear las tres cosas. | varios | lista más fluida | bajo |
| R10 | La hoja del gasto recorre el historial con cada letra que tecleas. | `ExpenseEditorView.swift` | tecleo fluido | bajo |
| R11 | El carrusel redibuja las dos páginas en cada cuadro del deslizamiento. | `MonthCarousel.swift:47` | deslizar a 120 Hz | medio (diseño aprobado) |

### Arquitectura
- **`ExpenseListView` tiene 1,199 líneas y 29 estados.** Mezcla la pantalla, el menú «Más», el CSV, deshacer, la sincronización con iCloud y los widgets. Propuesta: separar `HomeModel`, `MoreMenu`, `CSVImportExport` y `SettingsSync`.
  - Además, hoy un ajuste que cambia cuando esa pantalla no está montada no llega a iCloud.
- **Las pruebas de la app (`CentavoTests`: captura de Wallet, fijos, lo que no cuenta) no corren en los PR.** Solo corren las del paquete. Propuesta: mover esa lógica a `CentavoCore`. ⚠︎ La otra opción, simulador en el PR, choca con la decisión del 2026-10-20.

### Peso
- **Tipografías:** 412 KB, copiadas dos veces (app y widgets). Recortadas a los caracteres latinos y de moneda quedan unos 600 KB menos. Pedir el visto bueno con capturas.
- **Código muerto:** unas 370 líneas de dibujos de Atajos para iOS 27 que ya se reemplazaron con capturas reales (`GuideFrames.swift`). También restos del modelo de IA que se quitó y `DesignSystemCatalog` en Release.
- **Imágenes de la guía:** pasarlas de JPG a HEIC ahorra unos 200 KB.
- **Build:** activar `DEAD_CODE_STRIPPING`, y cachear `xcodegen` en la CI (1–3 min por corrida).

### Lo que ya está bien
- `CentavoCore` puro, con 297 pruebas.
- Una sola cuenta (`BudgetPace`) para la pantalla, Siri y los widgets.
- Los widgets no abren la base de datos.
- Si la base no abre, la app se explica en vez de cerrarse.
- Swift 6 estricto.
- Lint de diseño en la CI.
- «Reducir movimiento» respetado en todo.
- Contraste del latón ≈ 8:1.

## 4. Orden sugerido
1. Probar la guía flotante en el iPhone (ya instalada).
2. R6 (widget tras un pago) y R4 (captura): son de confiabilidad.
3. Victorias rápidas 1–7 de UX.
4. R2, R3 y R5 (pantalla principal más rápida). Medir con la prueba de 5,000 gastos antes y después.
5. Peso: tipografías y código muerto.
6. Apuestas grandes 8–10, con maquetas lado a lado para el dueño.
