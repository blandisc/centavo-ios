# CLAUDE.md

Guía para agentes que trabajan en este repo.

## Qué es
Centavo (en el iPhone se llama **Al día**; decisión del 2026-10-17): tracker de gastos minimalista para iOS. El identificador y el código siguen como Centavo. Captura cada pago de Apple Wallet con la automatización «Transacción» de Atajos, que llama al App Intent `LogExpenseIntent`. Offline y on-device. Decisiones en [docs/DECISIONS.md](docs/DECISIONS.md): léelas antes de proponer algo que las toque y agrega las nuevas en el mismo PR.

## Arquitectura
- `Packages/CentavoCore` — lógica pura (Foundation). Todo lo que se pueda probar sin app va aquí, con `swift test`.
- `Centavo/` — app SwiftUI. `Model/` (SwiftData, `Store.container` compartido por UI e intent), `Intents/` (App Intents), `Screens/`, `App/`.
- El `.xcodeproj` se genera con `xcodegen generate`; nunca se versiona.

## Verificar
`Tools/verify.sh` antes de terminar cualquier cambio Swift (`package` = solo el paquete; `app` = solo el build). Builds con `-jobs 4` y nunca en paralelo con otro build en la Mac.
En un PR la CI corre solo «Pruebas y build» (build y pruebas unitarias); eso decide el merge. El simulador (flujos, zonas táctiles, capturas) corre solo al entrar a `main` o a mano, nunca en un PR (decisión del 2026-10-20). Antes de abrir un PR que toque pantallas o flujos, corre tú las pruebas de interfaz en el simulador local.

## Diseño
Estilo **«Noche ticket»** aprobado por el dueño: modo oscuro forzado, acento latón, tipografía de ticket (IBM Plex Mono). Colores y tipografía viven en `Centavo/Theme/`; nunca se escriben sueltos en una pantalla.
La **estructura es nativa de Apple** (Human Interface Guidelines): `NavigationStack` con barra superior e inferior del sistema, `List` con `swipeActions`, `Form`, `Menu`, hojas y botones estándar. En iOS 26 eso es Liquid Glass sin código extra: **no lo tapes con piezas propias** (barras o botones hechos a mano). Lo que se viste (fondos, tipografía, colores) usa los tokens de `Theme`.
- Cuidado: dentro de un `Button` el estilo jerárquico (`.primary`) sigue el acento; usa colores explícitos de `Theme`.
- La referencia visual son las **capturas del simulador de la CI** (artefacto `capturas`). Los bocetos están en el lienzo: https://claude.ai/artifact/EuRdR9c1mQ4nNivNwQGVYN
- Si una petición de diseño puede leerse de dos maneras, **pregunta antes de cambiar lo aprobado**. Detalle en [docs/DECISIONS.md](docs/DECISIONS.md).

## Reglas
- **Sin servidor propio.** Ni servidor, ni telemetría, ni cuenta de Centavo. La única red es el iCloud privado de la persona, que sincroniza el sistema (decisión del 2026-10-15); la app no hace llamadas por su cuenta.
- **Minimalismo.** Antes de agregar una pantalla o un ajuste, pregunta si cabe en lo que ya existe.
- **Componentes nativos** de SwiftUI y estilos del sistema (Dynamic Type, modo oscuro). Nada de tamaños de fuente fijos.
- **Copy en es-MX**, sin suponer género.
- Una rama por issue (`cen-NN-slug`) desde `main`, PR con `Closes CEN-NN`, squash-merge, borrar rama. Entrada en CHANGELOG para cambios visibles.

## Tablero
Multica, workspace **Centavo** (prefijo `CEN`). Usa `--workspace-id` o `multica workspace switch centavo` antes de crear issues. Estados: todo → in_progress → in_review → done.
