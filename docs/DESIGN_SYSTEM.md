# Sistema de diseño «Noche ticket»

**Lectura obligatoria antes de tocar cualquier pantalla.** Si sigues este documento al pie de la letra, tu pantalla se verá como el resto de la app y pasará el lint. Si algo que necesitas no está aquí, **no inventes un valor**: agrega el token o el componente (con comentario) en el mismo PR y anótalo en este documento.

- Código fuente: `Centavo/Theme/` (tokens) y `Centavo/Components/` (piezas reutilizables).
- Catálogo visual: `Centavo/Components/DesignSystemCatalog.swift` (ábrelo en el lienzo de Xcode, `#Preview`).
- Barandal automático: `Tools/lint-design.sh` (corre en `Tools/verify.sh` y en la CI de cada PR). **Falla** si escribes un número, un tamaño de letra o un color sueltos.
- Decisiones de diseño: [DECISIONS.md](DECISIONS.md). Estilo aprobado por el dueño: no se cambia sin preguntar.

---

## 1. Principios (HIG de Apple + identidad)

1. **Estructura nativa, ropa propia.** `NavigationStack`, `Form`, `List`, `Section`, `Toggle`, `Picker`, `Menu`, `.sheet`, `.toolbar`, `swipeActions`. En iOS 26 eso es Liquid Glass sin código extra. Nunca dibujes barras, pestañas o botones de sistema a mano.
2. **Lo que se viste usa tokens.** Fondo, colores, tipografía, espacios, radios, trazos, opacidades y animaciones salen de `Theme` y `TicketStyle`.
3. **Modo oscuro forzado.** La app ya lo fuerza en `CentavoApp`; no uses `.preferredColorScheme` ni colores del sistema (`.primary`, `.red`, `Color.gray`…).
4. **Dynamic Type siempre.** Todo texto escala (los roles de `TicketStyle` ya lo hacen). Lo que mide junto al texto (íconos, columnas, alturas de barra) va con `@ScaledMetric`. Con letra de accesibilidad, las filas se apilan; el texto se envuelve, no se encoge.
5. **Toque mínimo de 44 pt** (`Theme.Size.tapTarget`) en todo lo que se toca.
6. **Copy en es-MX**, sin suponer género. Identificadores de accesibilidad en español (`"hoja-guardar"`).
7. **Minimalismo.** Antes de agregar una pantalla, pregunta si cabe en una que ya existe.

---

## 2. Tokens

Todos los valores son puntos al tamaño de letra predeterminado.

### Color (`Theme`, en `Theme/Theme.swift`)

| Token | Uso |
|---|---|
| `Theme.background` | Papel: fondo de toda pantalla y hoja |
| `Theme.surface` | Filas de `Form` (`.listRowBackground(Theme.surface)`), campos, paneles |
| `Theme.raised` | Un paso arriba de `surface` (días por venir en la barra del mes) |
| `Theme.ink` | Texto principal |
| `Theme.muted` | Texto secundario (6.5:1) |
| `Theme.faint` | Texto más callado: pistas, *placeholders* (5.2:1) |
| `Theme.brass` | El único acento: acción principal, selección, cifra héroe |
| `Theme.brassMid` / `Theme.brassLow` | Latón atenuado para gráficas (nunca texto) |
| `Theme.onBrass` | Texto sobre latón |
| `Theme.hairline` | Perforación y bordes finos |
| `Theme.outline` | Borde punteado del ticket en blanco (3:1, solo líneas) |
| `Theme.dimmed` | Algo presente pero no actual (el otro puntito del carrusel) |
| `Theme.danger` | Solo borrar |
| `Theme.good` | «Vas bien» |
| `Theme.categories[i]`, `Theme.categoryRest` | Las 4 categorías más grandes y «Otras» |
| `Theme.Shortcuts.*` | **Solo** para los dibujos de la app Atajos en la guía |

### Tipografía (`TicketStyle`, en `Theme/TicketFont.swift`)

Se usa así: `.font(.ticket(.body))`. Nunca `.ticket(15, …)` ni `.font(.system(size:))`.

| Rol | Tamaño / peso | Crece con | Interletrado sugerido | Para |
|---|---|---|---|---|
| `.hero` | 54 medium | largeTitle | `Tracking.hero` | La cifra principal de la pantalla de inicio |
| `.amountInput` | 44 medium | largeTitle | `Tracking.amount` | Monto que se escribe (`AmountInputField`) |
| `.amountInputCompact` | 40 medium | largeTitle | — | Monto dentro de una tarjeta |
| `.display` | 32 semibold | largeTitle | — | Cifra que encabeza una hoja |
| `.pageTitle` | 28 semibold | title | — | Título de página sin barra (bienvenida) |
| `.heading` | 22 medium | title2 | — | Título de un mensaje |
| `.figure` | 22 regular | title2 | `Tracking.figure` | Cifra dentro de una tarjeta |
| `.subheading` | 20 semibold | title3 | — | Título de un paso |
| `.field` | 17 regular | body | `Tracking.detail` | Texto que se escribe (`TicketTextField`) |
| `.headline` | 17 medium | headline | — | Cifra de una fila junto a su nombre |
| `.body` | 15 regular | body | — | Texto y filas normales |
| `.bodyMedium` | 15 medium | body | `Tracking.name` si va en mayúsculas | Nombre de una fila (comercio) |
| `.bodyStrong` | 15 semibold | body | — | Línea fuerte, botón destructivo |
| `.callout` | 14 regular | callout | — | Párrafo que explica |
| `.button` | 14 semibold | body | — | Título de botón cápsula («Guardar») |
| `.footnote` | 13 regular | footnote | — | Líneas secundarias, botones de barra |
| `.footnoteStrong` | 13 semibold | footnote | `Tracking.action` / `.title` | Títulos de barra, acciones en mayúsculas |
| `.detail` | 12 regular | footnote | — | Notas bajo un campo, resúmenes |
| `.label` | 12 semibold | footnote | `Tracking.label` | Etiquetas y botones compactos |
| `.caption` | 11 regular | caption | `Tracking.caption` | Encabezados de sección (`ticketCaption()`) |
| `.captionStrong` | 11 semibold | caption | `Tracking.caption` | Encabezado de la cifra héroe |
| `.hint` | 11 regular | caption2 | `Tracking.detail` | Pistas (`HintText`), detalles de fila |
| `.micro` | 10 regular | caption2 | — | Ejes, letras de la semana, total del día |
| `.microStrong` | 10 semibold | caption2 | `Tracking.action` | Nombre del día en la lista |

Símbolos SF: `.font(Theme.Symbol.regular)` o `.font(Theme.Symbol.large)`.

### Espaciado (`Theme.Space`)

| Token | pt | Uso típico |
|---|---:|---|
| `none` | 0 | Pegado |
| `xxxs` | 2 | Líneas de un mismo bloque |
| `xxs` | 4 | Etiqueta y valor; filas apiladas con letra grande |
| `xs` | 6 | Encabezado y su texto |
| `s` | 8 | Elementos de una fila (el hueco chico por omisión) |
| `sm` | 10 | Filas de una lista corta |
| `m` | 12 | Ícono a texto; elementos de una tarjeta |
| `ml` | 14 | Dentro de un ticket en blanco |
| `l` | 16 | Dentro de una tarjeta o fila seleccionable |
| `lx` | 18 | Alrededor del ticket de «Borrar» |
| `xl` | 20 | Entre bloques de una página |
| `xlx` | 22 | Dentro del ticket de lista vacía |
| `xxl` | 24 | Arriba y abajo de una página |
| `xxxl` | 28 | Arriba de una hoja sin barra |
| `screen` | 24 | **Margen izquierdo y derecho de toda pantalla** |
| `outset` | −3 | Ajuste óptico (el «$» del héroe, un anillo por fuera) |

### Radios (`Theme.Radius`)

`bar` 2 · `tile` 3 · `chip` 4 · `ticket` 6 · `control` 8 · `panel` 10 · `card` 12 · `sheet` 28. Los tickets son casi cuadrados: nunca tarjetas en forma de píldora.

### Tamaños (`Theme.Size`)

| Token | pt | Uso |
|---|---:|---|
| `tapTarget` | 44 | Altura mínima de todo lo que se toca |
| `compactRow` | 28 | Fila que no se toca sola |
| `capsuleLabel` / `wideCapsuleLabel` | 34 / 36 | Alto de la etiqueta dentro de un botón cápsula |
| `choiceTile` | 48 | Cuadro de elección en una cuadrícula |
| `tallRow` | 52 | Fila de dos líneas; tarjeta seleccionable |
| `categoryTile` | 58 | Botón de categoría |
| `iconColumn` / `iconColumnNarrow` / `iconColumnWide` | 28 / 22 / 32 | **Base de `@ScaledMetric`** para la columna del ícono |
| `rowTile`, `rowTileSymbol`, `categorySymbol`, `glyph`, `stepNumber` | 32, 15, 22, 14, 16 | **Base de `@ScaledMetric`** |
| `stepEmblem` | 44 | **Base de `@ScaledMetric`**: el emblema de latón de cada paso (bienvenida y guía del atajo), del alto de un renglón de título, con `Theme.Space.m` de hueco |
| `pageDot`, `pageDotCurrent`, `legendDot`, `dayTick`, `todayMarkWidth`, `mapPreview` | | Piezas de gráficas y de la lista |

Más tokens de gráficas por zona en `Theme/Tokens+Home.swift`, `Tokens+List.swift`, `Tokens+Editor.swift`, `Tokens+Sheets.swift`, `Tokens+Onboarding.swift`.

### Trazos, guiones, opacidad, interletrado, encogimiento y movimiento

| Grupo | Tokens |
|---|---|
| `Theme.Stroke` | `fine` 0.5 · `hairline` 1 · `mark` 1.2 · `emphasis` 1.5 · `strong` 2 |
| `Theme.Dash` | `perforation` [3,3] · `ticket` [5,4] · `dotted` [3,2] |
| `Theme.Opacity` | `hidden` 0 · `visible` 1 · `rule` 0.25 · `glow` 0.35 · `unselected` 0.4 · `paceBehind` 0.55 · `paceAhead` 0.8 · `onTileSecondary` 0.75. Solo marcas y rellenos; el texto usa `ink`/`muted`/`faint`. |
| `Theme.Tracking` | `none` 0 · `hero` −2 · `amount` −1.5 · `figure` −0.5 · `name` 0.4 · `detail` 0.6 · `compactLabel` 0.8 · `tag` 1 · `label` 1.2 · `action` 1.4 · `caption` 1.6 · `title` 2 |
| `Theme.MinimumScale` | `text` 0.75 (palabras) · `figure` 0.6 (una cifra en una línea). Último recurso: primero envuelve o apila. |
| `Theme.Motion` | `quick` (toque) · `page` · `settle` · `resize` · `restyle` · `countUp` · `pulse` · `toggle` · `Entrance.*` (la barra del mes). Siempre con `accessibilityReduceMotion`: `Theme.Motion.animation(.quick, reduceMotion: reduceMotion)`. |

---

## 3. Componentes (`Centavo/Components/` y `Theme/Theme.swift`)

| Componente | Cuándo usarlo | Ejemplo |
|---|---|---|
| `.ticketForm()` | Todo `Form`/`List` de pantalla u hoja | `Form { … }.ticketForm()` |
| `.ticketBarTitle(_:)` | Título chico en mayúsculas de una hoja | `.ticketBarTitle("Nuevo gasto")` con `.navigationBarTitleDisplayMode(.inline)` |
| `Text(…).ticketCaption()` | Encabezado de `Section` | `header: { Text("Tarjetas").ticketCaption() }` |
| `.saveBar(_:enabled:action:)` | «Guardar» de toda hoja que guarda (abajo, con resumen) | `.saveBar("$89 en Oxxo", enabled: ok, action: save)` |
| `.ticketProminent(_:)` | **El único** estilo de botón prominente (Liquid Glass en iOS 26) | `Button { … } label: { PrimaryButtonLabel("Listo") }.ticketProminent()` |
| `PrimaryButtonLabel` | Etiqueta de la acción principal a todo lo ancho | `PrimaryButtonLabel("Configurar ahora", systemImage: "wallet.pass")` |
| `SecondaryButton` | La alternativa callada («Después») | `SecondaryButton("Después") { … }` |
| `AmountInputField` | Escribir un monto (teclado decimal, miles automáticos) | `AmountInputField("Monto", text: $t, prompt: "0.00", identifier: "monto")` |
| `TicketTextField` | Escribir texto de una línea | `TicketTextField("Comercio", text: $n, prompt: "Oxxo, Uber…")` |
| `SectionLabel` | Etiqueta en mayúsculas dentro de una fila (toggle, stepper) | `Toggle(isOn: $x) { SectionLabel("Es una devolución") }` |
| `HintText` | Pista bajo un campo o en el pie de sección | `footer: { HintText("Puedes cambiarlo después.") }` |
| `NoteText` | Nota que explica (`muted`) o avisa (`color: Theme.danger`) | `NoteText("Ya existe.", color: Theme.danger)` |
| `IconRow` | Fila de formulario con ícono (columna escalable) | `IconRow("BBVA", systemImage: "creditcard")` |
| `AdaptiveStack` | Fila que con letra de accesibilidad se vuelve columna | `AdaptiveStack { a; b }` |
| `TicketOutline` / `.ticketOutline(_:)` | Ticket en blanco punteado (estado vacío, aviso) | `.ticketOutline(.emphasis)` |
| `.ticketPanel()` | Panel callado (`surface`, radio `panel`) | nota, vista previa |
| `.selectableCard(selected:)` | Opción como tarjeta con borde latón al elegirla | monedas en la bienvenida |
| `StepEmblem` | Emblema de latón decorativo que acompaña al título; oculto con letra de accesibilidad | Se usa dentro de `StepHeader`, no sola |
| `StepHeader` | Encabezado reutilizable de cada paso: «Paso X de N» + emblema junto al título | `StepHeader(step: 3, of: 8, title: "Conecta el importe", systemImage: "wallet.pass")` |
| `StepDots` | Avance de pasos por puntitos en la barra inferior; decorativo (la etiqueta «Paso X de N» lleva el progreso) | `StepDots(current: 2, of: 5)` |
| `.choiceTile(selected:)` | Cuadro chico de elección (categoría, símbolo) | cuadrícula de íconos |
| `Perforation()` | Línea punteada entre renglones del ticket | `.overlay(alignment: .top) { Perforation() }` |
| `.confirmsDelete(of:…)` | Preguntar antes de borrar un gasto | lista y hoja de gasto |
| `.ticketPreview()` | Envoltura de todo `#Preview` | `#Preview { MiVista().ticketPreview() }` |

---

## 4. Receta: pantalla (hoja) nueva

Copia esto y cambia el contenido. Compila tal cual (está en `DesignSystemCatalog.swift` como `RecipeSheet`).

```swift
import SwiftUI

/// Una hoja nueva: Form nativo vestido de ticket, título chico, «Guardar» abajo.
struct RecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var name = ""
    @State private var repeats = false

    private var canSave: Bool { !amount.isEmpty && !name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountInputField("Monto", text: $amount, prompt: "0.00", identifier: "receta-monto")
                    TicketTextField("Nombre", text: $name, prompt: "Renta, gimnasio…",
                                    identifier: "receta-nombre")
                    Toggle(isOn: $repeats) { SectionLabel("Se repite") }
                        .tint(Theme.brass)
                } header: {
                    Text("Gasto").ticketCaption()
                } footer: {
                    HintText("Puedes cambiarlo después en «Más».")
                }
                .listRowBackground(Theme.surface)
                Section {
                    IconRow("Efectivo", systemImage: "banknote")
                } header: {
                    Text("Cómo pagas").ticketCaption()
                }
                .listRowBackground(Theme.surface)
            }
            .ticketForm()
            .navigationBarTitleDisplayMode(.inline)
            .ticketBarTitle("Nuevo fijo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.font(.ticket(.footnote))
                }
            }
            .saveBar(canSave ? "\(name) · \(amount)" : "Falta el monto", enabled: canSave) { dismiss() }
        }
    }
}

#Preview { RecipeSheet().ticketPreview() }
```

Para una pantalla que no es formulario (p. ej. una página de bienvenida): `ScrollView { VStack(alignment: .leading, spacing: Theme.Space.xl) { … } .padding(.horizontal, Theme.Space.screen).padding(.vertical, Theme.Space.xxl) }` con `.background(Theme.background)`, título en `.ticket(.pageTitle)` + `.accessibilityAddTraits(.isHeader)` y la acción principal con `PrimaryButtonLabel` + `.ticketProminent()`.

---

## 5. Nunca hagas esto (el lint lo detecta)

| ✗ Nunca | ✓ En su lugar |
|---|---|
| `.padding(16)`, `spacing: 12`, `.frame(minHeight: 44)` | `Theme.Space.l`, `Theme.Space.m`, `Theme.Size.tapTarget` |
| `.cornerRadius(8)`, `RoundedRectangle(cornerRadius: 8)` | `RoundedRectangle(cornerRadius: Theme.Radius.control)` |
| `.font(.system(size: 15))`, `.font(.ticket(15))`, `.font(.body)` en texto | `.font(.ticket(.body))` |
| `Color(red:…)`, `Color(hex:)`, `.foregroundStyle(.secondary)`, `Color.gray`, `.red` | `Theme.muted`, `Theme.danger`… |
| `.buttonStyle(.borderedProminent)` | `.ticketProminent()` |
| `.opacity(0.4)`, `.tracking(1.2)`, `lineWidth: 1.5`, `dash: [5, 4]` | `Theme.Opacity.unselected`, `Theme.Tracking.label`, `Theme.Stroke.emphasis`, `Theme.Dash.ticket` |
| `.minimumScaleFactor(0.5)` | Envolver/apilar; si no hay otra, `Theme.MinimumScale.text` |
| `withAnimation(.spring(duration: 0.4))` | `withAnimation(Theme.Motion.animation(.resize, reduceMotion: reduceMotion))` |
| `@ScaledMetric var w: CGFloat = 28` | `@ScaledMetric(relativeTo: .body) private var w = Theme.Size.iconColumn` |
| `.frame(width: 28)` en un ícono junto a texto | `@ScaledMetric` (crece con la letra) |
| `.preferredColorScheme(.dark)` en un preview | `.ticketPreview()` |
| Barras, pestañas o botones de sistema hechos a mano | Los nativos (`toolbar`, `TabView`, `Button`) |

Lo que el lint no ve pero también está prohibido: colores con opacidad para texto (`Theme.ink.opacity(…)`), `.textCase(.uppercase)` + `tracking` a mano cuando existe `SectionLabel`/`ticketCaption()`, y copiar una pieza privada de otra pantalla (súbela a `Components/`).

**Excepción por línea:** solo si un valor de verdad no es de diseño (p. ej. una altura inicial antes de medir), termina la línea con `// ds-allow: <motivo>`. El lint las cuenta y las lista; cada una se justifica en el PR. Los dibujos de Atajos (`ShortcutsDrawing.swift`, `GuideFrames.swift`) imitan otra app y solo pasan por las reglas de color.

---

## 6. Dynamic Type y accesibilidad

- **Prueba en AX5**: `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` (ver `CentavoUITests/FlowTests.swift`). Toda pantalla nueva entra a una prueba así.
- **Filas**: con `dynamicTypeSize.isAccessibilitySize`, apila (`AdaptiveStack`) en vez de cortar. `ViewThatFits` para elegir entre una versión ancha y una angosta.
- **`lineLimit`**: deja crecer (2–3 líneas) los nombres; `lineLimit(1)` solo para cifras con `Theme.MinimumScale.figure`.
- **Medidas junto al texto** (íconos, columnas, barras): `@ScaledMetric(relativeTo:)` con base en `Theme.Size`.
- **VoiceOver**: `.accessibilityElement(children: .combine)` en filas, `.accessibilityAddTraits(.isHeader)` en títulos, `.accessibilityHidden(true)` en adornos, `.isSelected` en opciones elegidas.
- **Toque**: 44 pt mínimo; `contentShape(Rectangle())` en filas tocables.
- **Reducir movimiento**: `@Environment(\.accessibilityReduceMotion)` y `Theme.Motion.animation(_:reduceMotion:)`.
- **Contraste**: el texto solo en `ink`, `muted` o `faint` sobre `background`/`surface` (≥ 4.5:1). `outline` y `hairline` son para líneas, no texto.

---

## 7. Cómo agregar un token o componente

1. Si el valor se repite o tiene un rol, va en `Theme/Tokens.swift` (o en `Tokens+<zona>.swift` si es geometría de una sola gráfica) con un comentario de dónde se usa.
2. Si un patrón aparece en dos pantallas, se vuelve componente en `Components/` con `#Preview` y se agrega al catálogo y a la tabla de arriba.
3. `Tools/lint-design.sh` debe pasar; `Tools/verify.sh` lo corre.
