# Auditoría del sistema de diseño «Noche ticket» (segunda pasada)

Primera auditoría: solo lectura sobre `origin/main` en `690cc0c` (2026-10-23), calificación **4.5 / 10**. Esta segunda pasada califica la rama `feat/sistema-diseno-reforzado` después del refuerzo, **con la misma rúbrica y los mismos conteos** (pantallas de la app en `Centavo/Screens/**` y ahora también `Centavo/Components/**`; los dos dibujos de Atajos, `ShortcutsDrawing.swift` y `GuideFrames.swift`, se cuentan aparte porque imitan otra app a propósito).

---

## En corto (para quien no programa)

**Calificación global: 4.5 → 8.3 / 10.**

Antes, el sistema vivía en la cabeza de quien hizo la app: los colores eran un catálogo, pero los espacios, las esquinas, los tamaños de letra y las animaciones se escribían a mano en cada pantalla. Ahora **cada valor tiene nombre** (un «margen de pantalla», un «radio de tarjeta», un «estilo de texto de pista»), las piezas repetidas son **componentes** que cualquiera puede usar, hay una **guía** con una receta de pantalla nueva que compila, y un **lint** que hace fallar la CI si alguien escribe un número, un tamaño de letra o un color sueltos. Con letra normal la app se ve igual (los pocos cambios a propósito están en el CHANGELOG); con letra muy grande ya no se cortan el divisor de cada día ni el «Mosaico».

| Apartado | Antes | Después | Por qué |
|---|---:|---:|---|
| 1. Tokens de diseño | 4 | **8.5** | Existen y están documentados todos los grupos: espacio, radio, tamaño, símbolo, trazo, guion, opacidad, interletrado, encogimiento mínimo y movimiento, más 24 estilos de texto con nombre. Faltan colores con variante de día y de alto contraste. |
| 2. Componentes reutilizables | 5 | **8** | 17 piezas públicas nuevas con `#Preview` (botón prominente con Liquid Glass, etiqueta de acción principal, recuadro punteado, campo de monto, etiquetas, filas con ícono, pila adaptable, tarjetas…). `ExpenseListView.swift` sigue largo y con piezas privadas; quedan 34 `textCase(.uppercase)` a mano. |
| 3. Valores fijos en pantallas | 4 | **9** | 0 números de layout, 0 tamaños de letra con número, 0 interletrados y opacidades sueltos; el lint lo garantiza. 2 excepciones `ds-allow` justificadas. |
| 4. Dynamic Type y modo oscuro | 6 | **7.5** | Divisor del día y «Mosaico» se acomodan en AX5 (con pruebas), columnas de íconos con `@ScaledMetric`, nada se encoge por debajo de 60 %. Siguen pendientes la versión de día, «Aumentar contraste» y capturas de hojas con letra grande. |
| 5. Documentación y barandales | 3 | **8.5** | `docs/DESIGN_SYSTEM.md` (lectura obligatoria desde `CLAUDE.md`), lint en `verify.sh` y en la CI de cada PR, catálogo con `#Preview`, receta compilada. Las capturas siguen sin compararse contra una referencia. |

---

## Conteos antes / después

Mismo método que la primera auditoría (pantallas de la app, sin los dibujos de Atajos).

| Medida | Antes | Después |
|---|---:|---:|
| `padding(N)` con número | 45 | **0** |
| `spacing: N` con número | 71 | **0** |
| `cornerRadius: N` con número | 29 | **0** |
| `frame(…: N)` con número | 43 | **0** |
| **Números mágicos de layout (suma)** | **188** | **0** |
| `.ticket(N…)` (tamaño de letra con número) | 123 | **0** |
| Tamaños de letra distintos escritos en pantallas | 14 | **0** (24 roles con nombre en `TicketStyle`) |
| `.font(.system(size:))` | 0 | 0 |
| `tracking(N)` con número | 47 | **0** |
| `.opacity(N)` con número | 12 | **0** |
| `minimumScaleFactor(N)`; mínimo | 11; 0.4 | **0** literales; mínimo `Theme.MinimumScale.figure` = 0.6 |
| Colores sueltos | 1 (dibujo) | 1 (dibujo, con `ds-allow`) |
| `#Preview` | 4 | **12** (5 de componentes, 3 del catálogo y la receta, 4 de pantallas) |
| `@ScaledMetric` | 16 | **22** |
| Archivos con disposición alterna para letra de accesibilidad | 2 | **3** (+ `AdaptiveStack` reutilizable) |
| Problemas del lint de diseño | 446 (primera corrida) | **0** |
| Excepciones `// ds-allow` | — | 2 |

Dibujos de Atajos: siguen con sus medidas propias (180 números); el lint solo les aplica las reglas de color.

---

## Qué se hizo, por prioridad de la primera auditoría

### P1
1. **Escalas en `Theme`** — `Centavo/Theme/Tokens.swift`: `Theme.Space` (14 pasos + `screen` y `outset`), `Theme.Radius` (8), `Theme.Size` (toque 44 y bases de `@ScaledMetric`), `Theme.Symbol`, `Theme.Stroke`, `Theme.Dash`, `Theme.Opacity`, `Theme.Tracking`, `Theme.MinimumScale`, `Theme.Motion` (+ `Entrance` para la barra del mes y `animation(_:reduceMotion:)`). Geometría de una sola gráfica en `Tokens+Home.swift`, `Tokens+Editor.swift`, `Tokens+Sheets.swift`. ✅
2. **Roles tipográficos** — `TicketStyle` (24 casos con tamaño, peso y estilo de Dynamic Type) y `.font(.ticket(.rol))`. `.ticket(N)` queda solo para `Theme/` y los dibujos. ✅
3. **`docs/DESIGN_SYSTEM.md`** — tokens, catálogo de componentes con cuándo usarlos, receta de hoja nueva (compilada como `RecipeSheet` en el catálogo), tabla «nunca / en su lugar», Dynamic Type y accesibilidad. Enlazada desde `CLAUDE.md`. ✅
4. **Componentes públicos** — en `Centavo/Components/`: `ticketProminent(_:)` (une `ProminentCapsule` y `DangerCapsule`, Liquid Glass en iOS 26), `PrimaryButtonLabel`, `SecondaryButton`, `TicketOutline`/`.ticketOutline`, `.ticketPanel`, `.selectableCard`, `.choiceTile`, `AmountInputField`, `TicketTextField`, `SectionLabel`, `HintText`, `NoteText`, `IconRow`, `AdaptiveStack`, `saveBar` (movido), `.ticketPreview`. ✅
5. **Lint** — `Tools/lint-design.sh` (Python estándar, corre en Linux): números en modificadores de layout, `.ticket(N)`, `.font(.system…)`, estilos de texto del sistema, colores literales y del sistema, botones prominentes a mano, `preferredColorScheme`, `@ScaledMetric` con número. Excepción por línea `// ds-allow: motivo` (se cuenta y se lista; sin motivo falla). En `Tools/verify.sh` y en el job «Pruebas y build» de la CI. ✅

### P2
6. **Movimiento y opacidad** — tokens creados y usados en todas las animaciones. ✅
7. **Letra grande** — `AdaptiveStack`, columnas de íconos con `@ScaledMetric` (catálogo, guía, bienvenida, salud de la captura), divisor del día y «Mosaico» con disposición apilada en tamaños de accesibilidad, encogimiento mínimo 0.6/0.75. Pruebas nuevas en AX5: `testElDivisorDelDiaConLetraDeAccesibilidadCabeCompleto` y `testMosaicoConLetraDeAccesibilidadMuestraCadaCategoriaCompleta`. ✅ (parcial: ver pendientes)
8. **`#Preview` y catálogo** — `DesignSystemCatalog` (normal y AX5) y un `#Preview` por archivo de componentes con `.ticketPreview()`. ✅
9. **Capturas de hojas con letra grande** — ❌ pendiente.
10. **Partir `ExpenseListView.swift`** — ❌ pendiente (se migró a tokens, pero sigue con ~1,100 líneas y piezas privadas).

### P3
11. **Colores con variante de día y alto contraste** — ❌ pendiente. Los colores siguen como `Color(hex:)` fijos en `Theme.swift` (una sola fuente de verdad, que es lo que hace barato el cambio después).
12. **Comparación de capturas** — ❌ pendiente.
13. **Prueba de contrastes de `Theme`** — ❌ pendiente.

---

## Lo que queda pendiente (honesto)

- **Etiquetas en mayúsculas a mano:** 34 `textCase(.uppercase)` siguen escritos en pantallas (ya con tokens de tipo e interletrado, pero sin pasar por `SectionLabel`/`ticketCaption()`). El lint no lo detecta.
- **Tokens de zona con nombres débiles:** algunos de `Tokens+Home.swift` (p. ej. `barFullScale = 1`, `todayMarkHalf = 1`, `Space.tuck = −10`) existen para que no haya números sueltos, pero describen geometría de una gráfica más que una decisión de diseño. Son válidos para el lint; conviene revisarlos al tocar esas gráficas.
- **El lint lee línea por línea:** un número en un modificador partido en varias líneas puede escaparse; y no entiende semántica (un `Theme.Space.l` donde iba `Theme.Space.m` pasa).
- **`ExpenseListView.swift`** sigue siendo el archivo más grande y tiene piezas privadas que un modelo podría copiar en vez de reutilizar.
- **Modo claro y «Aumentar contraste»:** sin variantes.
- **Capturas:** no se comparan contra una referencia; las hojas no tienen captura con letra grande.

---

## Resumen de calificaciones

| Apartado | Antes | Después |
|---|---:|---:|
| Tokens | 4 | 8.5 |
| Componentes | 5 | 8 |
| Valores fijos | 4 | 9 |
| Dynamic Type y modo | 6 | 7.5 |
| Documentación y barandales | 3 | 8.5 |
| **Global** | **4.5** | **8.3** |
