# CLAUDE.md

Guía para agentes que trabajan en este repo.

## Qué es
Centavo: tracker de gastos minimalista para iOS. Captura cada pago de Apple Wallet con la automatización «Transacción» de Atajos, que llama al App Intent `LogExpenseIntent`. Offline y on-device. Decisiones en [docs/DECISIONS.md](docs/DECISIONS.md): léelas antes de proponer algo que las toque y agrega las nuevas en el mismo PR.

## Arquitectura
- `Packages/CentavoCore` — lógica pura (Foundation). Todo lo que se pueda probar sin app va aquí, con `swift test`.
- `Centavo/` — app SwiftUI. `Model/` (SwiftData, `Store.container` compartido por UI e intent), `Intents/` (App Intents), `Screens/`, `App/`.
- El `.xcodeproj` se genera con `xcodegen generate`; nunca se versiona.

## Verificar
`Tools/verify.sh` antes de terminar cualquier cambio Swift (`package` = solo el paquete; `app` = solo el build). Builds con `-jobs 4` y nunca en paralelo con otro build en la Mac.

## Diseño
La app sigue las **Human Interface Guidelines de Apple** y usa **componentes nativos** (decisión del dueño, 2026-10-13): `List`, `Form`, `NavigationStack` con barra de navegación y barra inferior del sistema, `ContentUnavailableView`, `Menu`, hojas estándar. En iOS 26 esos componentes son Liquid Glass sin código extra; **no los tapes con piezas propias** (fondos, barras o botones hechos a mano).
- Tipografía del sistema con estilos de texto (`.body`, `.footnote`, …); nunca tamaños fijos ni mayúsculas forzadas.
- Colores semánticos (`.primary`, `.secondary`, `.background`, `.quaternary`) y **un solo acento** en `Assets.xcassets/AccentColor` (claro y oscuro). La app sigue la apariencia del sistema; no fuerces claro ni oscuro.
- Cuidado: dentro de un `Button` (p. ej. una fila de `List`), `.primary`/`.secondary` siguen el acento; usa `Color.primary`/`Color.secondary`.
- La referencia visual son las **capturas del simulador de la CI** (artefacto `capturas`), no un boceto. Las ideas de producto (calendario por intensidad, presupuesto con línea de «hoy», meses) viven en [docs/DECISIONS.md](docs/DECISIONS.md).

## Reglas
- **Cero red.** Sin servidor, telemetría ni cuenta.
- **Minimalismo.** Antes de agregar una pantalla o un ajuste, pregunta si cabe en lo que ya existe.
- **Componentes nativos** de SwiftUI y estilos del sistema (Dynamic Type, modo oscuro). Nada de tamaños de fuente fijos.
- **Copy en es-MX**, sin suponer género.
- Una rama por issue (`cen-NN-slug`) desde `main`, PR con `Closes CEN-NN`, squash-merge, borrar rama. Entrada en CHANGELOG para cambios visibles.

## Tablero
Multica, workspace **Centavo** (prefijo `CEN`). Usa `--workspace-id` o `multica workspace switch centavo` antes de crear issues. Estados: todo → in_progress → in_review → done.
