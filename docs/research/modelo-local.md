# Spike: un modelo de lenguaje local en Al día

Octubre 2026. Investigación de escritorio sobre el framework **Foundation Models** de Apple (iOS 26 y 27) y lectura completa del código. Sin prueba en un iPhone: lo que depende del modelo real (precisión, latencia, límites en segundo plano) está marcado y se mide en la fase 0.

**Resumen en tres líneas.**
1. Sí se puede, sin red y sin cuentas, con el modelo de Apple Intelligence que ya viene en el iPhone. Funciona en iOS 26 o posterior con un iPhone compatible; en el resto la app sigue igual que hoy.
2. La regla que lo hace confiable: **el modelo no suma ni inventa cifras.** Elige entre opciones que la app le da (categorías) y redacta hechos que `CentavoCore` ya calculó. Todo lo que devuelve se valida en código probado.
3. Lo primero que conviene construir es **clasificar comercios desconocidos usando tus propias categorías como ejemplos**. Le sigue **una nota del mes** con insights. Después vienen la captura en lenguaje natural y la foto del ticket.

---

## 1. Lo que ya existe y se reutiliza

Antes de diseñar hice este inventario. Casi todo lo que necesita la función ya existe:

| Pieza | Dónde | Qué aporta |
|---|---|---|
| `CategoryMemory` | `CentavoCore` | La categoría que **tú** le pusiste a ese comercio. Siempre manda. |
| `MerchantCatalog` | `CentavoCore` | ~90 marcas de México → categoría, por palabras completas. Determinista. |
| `MerchantCatalog.suggestion` | `CentavoCore` | Ya define el orden: tu memoria y, si no hay, el catálogo. El modelo entra como **tercer** escalón. |
| `CategoryStyle.common` + `UserCatalog` (categorías propias) + `CategoryMemory.known` | app | La lista cerrada de categorías válidas que se le ofrece al modelo. |
| `MonthSummarizer`, `CategoryShare`, `BudgetPace` | `CentavoCore` | Totales, reparto por categoría y ritmo. Son los «hechos» de los insights. |
| `CaptureText`, `AmountParser`, `WalletNotice` | `CentavoCore` | Validan cualquier monto que el modelo extraiga de un texto. |
| Hint «Sugerida para Oxxo: Despensa. Cámbiala si no te queda.» | `ExpenseEditorView` | La interfaz para mostrar una sugerencia ya existe y está aprobada (2026-10-18). |
| `LogExpenseIntent` / `LogWalletNoticeIntent` | app | Corren **en segundo plano**, en cada pago. Ahí no conviene llamar al modelo (ver §3.3). |

Hoy, un comercio que no está en el catálogo y que nunca categorizaste («TAQ EL GUERO SUC 2», «CLIP*MX ESTETICA») llega con `category = nil`. «En qué se va» lo cuenta como «sin categoría». Ese es el hueco concreto que llena el modelo.

## 2. La plataforma (lo que confirma Apple)

| Hecho | Consecuencia para Al día |
|---|---|
| **Foundation Models** da acceso al modelo on-device de Apple Intelligence: `SystemLanguageModel`, `LanguageModelSession`, `@Generable`/`@Guide` (salida estructurada garantizada), `Tool` (herramientas que el modelo llama). Desde **iOS 26**. ([docs](https://developer.apple.com/documentation/foundationmodels)) | El proyecto apunta a iOS 18: todo va detrás de `if #available(iOS 26, *)` y `#if canImport(FoundationModels)`. |
| Necesita un **dispositivo compatible con Apple Intelligence** y la región e idioma soportados. `model.availability` dice `.deviceNotEligible`, `.appleIntelligenceNotEnabled` o `.modelNotReady` (descargando). ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)) | Sin modelo, la función no aparece y no hay ningún mensaje de «actualiza tu iPhone». La app sigue como hoy. |
| **El español está soportado** (lista de idiomas de Apple Intelligence desde iOS 26.1). El modelo es multilingüe. Apple recomienda poner en las instrucciones la frase exacta en inglés `"The person's locale is es_MX."` y luego «MUST respond in…». ([idiomas y locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), [Apple Support](https://support.apple.com/en-mt/121115)) | Instrucciones en inglés con esa frase, y salida en es-MX. Antes de usarlo, `supportsLocale()`. |
| **Hay tres versiones del modelo**: iOS 26.0–26.3, 26.4 y 27.0. Apple lo cambia con las actualizaciones del sistema. ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [versiones de prompts](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)) | Un set de evaluación fijo (§6) que se corre en cada iOS nuevo, igual que las capturas de la guía. |
| **Contexto chico.** En iOS 26 eran 4096 tokens por sesión, contando instrucciones, herramientas y respuesta. En iOS 27 el ejemplo de Apple imprime `contextSize == 8192`. Desde 26.4 hay `tokenCount(for:)`. ([TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window), [WWDC26 «What's new»](https://developer.apple.com/videos/play/wwdc2026/241/)) | **Nunca se le pasa la lista de gastos.** Se le pasan agregados que ya calculó `CentavoCore`, en unas decenas de líneas. |
| **Lo que no hace bien:** aritmética, conocimiento del mundo, razonamiento largo. ([Natasha the Robot](https://www.natashatherobot.com/p/apple-foundation-models)) | Confirma la regla «el modelo no suma». |
| **`DynamicGenerationSchema`** construye el esquema en tiempo de ejecución, con `anyOf: [String]` («la cadena debe ser uno de estos valores»). Hay un reporte en el foro de que a veces devuelve valores fuera de la lista. ([docs](https://developer.apple.com/documentation/foundationmodels/dynamicgenerationschema), [foro](https://developer.apple.com/forums/topics/machine-learning-and-ai/machine-learning-and-ai-foundation-models?page=2)) | Sirve para «elige una de *tus* categorías», aunque sean propias. Igual se valida en código: si no está en la lista, es `nil`. |
| **Caso de uso `.contentTagging`**: un adaptador que produce etiquetas libres de 1–3 palabras. ([docs](https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags)) | **No es el adecuado** para categorías: inventa etiquetas en vez de elegir entre las tuyas. Se usa `.general` con `anyOf`. |
| **Límite en segundo plano.** Según ingenieros de Apple, con batería y la app en segundo plano hay un presupuesto; si se pasa, sale el error `rateLimited`. En primer plano no hay límite salvo carga alta. También recomiendan no hacer *streaming* en segundo plano. ([foro 789788](https://developer.apple.com/forums/thread/789788), [foro 793787](https://developer.apple.com/forums/thread/793787)) | Los intents de Wallet corren en segundo plano: **la captura nunca espera al modelo** (§3.3). |
| **iOS 27 agrega:** imágenes en el prompt (`Attachment(UIImage)`), `OCRTool`/`BarcodeReaderTool`, `SpotlightSearchTool` (búsqueda local tipo RAG sobre el índice de Spotlight), errores nuevos `LanguageModelError` (en 26 era `GenerationError`), *dynamic profiles* y un framework de **Evaluaciones**. ([WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), [sesión 246](https://developer.apple.com/videos/play/wwdc2026/246/)) | La foto del ticket y las preguntas sobre tus gastos son viables en iOS 27 sin red. |
| **`PrivateCloudComputeLanguageModel`** (iOS 27): un modelo más grande en la nube privada de Apple, con 32K de contexto. Gratis para apps con menos de 2 millones de descargas. Requiere el entitlement `com.apple.developer.private-cloud-compute`. ([PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute)) | **Choca con la regla «la app no hace llamadas de red por su cuenta»** (decisión 2026-10-15). Propuesta: no usarlo. Si algún día se quiere, lo decide el dueño (§7). |

Lo que **no** pude confirmar desde aquí y se mide en la fase 0:
- La latencia real por clasificación en un iPhone (estimo menos de 1 s con la sesión precalentada, sin verificar).
- Si el disparador de Wallet en segundo plano tiene presupuesto suficiente para una llamada por pago.
- Qué tan seguido los *guardrails* bloquean nombres de comercio inocentes (licorerías, farmacias, sex shops, «Casino»…). Apple dice que bajaron los falsos positivos en 26.4 y 27, pero no hay cifras.

## 3. Feature 1: clasificar el gasto

### 3.1 Comportamiento

1. Llega un pago de un comercio que **no** está en tu memoria ni en el catálogo.
2. En cuanto abres la app, el modelo le propone una de **tus** categorías: las comunes, las tuyas y las que ya usaste. También puede decir «ninguna».
3. La propuesta se ve como hoy se ve la del catálogo. En la hoja del gasto dice «Sugerida para Taq El Güero: Comida. Cámbiala si no te queda.», y en la lista sale con su ícono.
4. Si la cambias o la confirmas, pasa a ser **tuya** (`CategoryMemory`) y el modelo ya no vuelve a opinar sobre ese comercio.

Orden de prioridad: **tu memoria → catálogo → modelo → sin categoría.** Es la misma regla del 2026-10-18 («lo que tú elegiste siempre manda»). El modelo solo agrega un escalón al final.

### 3.2 Por qué funciona bien con este modelo

- **Elegir de una lista cerrada** es la tarea en la que un modelo de unos 3B parámetros es más fiable. `anyOf` restringe la salida a esas opciones.
- **Tus propios gastos son los ejemplos.** El prompt lleva de 6 a 10 comercios que ya categorizaste («Tacos Don Beto → Comida», «Gym Sport City → Salud»). Así aprende *tu* manera de organizar el dinero sin entrenar nada. Si tienes una categoría «Perrhijos», el modelo la puede usar en cuanto le pusiste un gasto. Eso no lo logra ningún catálogo.
- La entrada es diminuta (un nombre de comercio y, a veces, la tarjeta y la hora), así que cada llamada usa unos 400–600 tokens, muy por debajo del límite.

### 3.3 Dónde corre (y dónde no)

| Lugar | Decisión | Por qué |
|---|---|---|
| Dentro de `LogExpenseIntent` / `LogWalletNoticeIntent` | **No** (v1) | Corre en segundo plano en cada pago: hay límite de uso, el modelo puede estar descargándose, y Atajos tiene un tiempo máximo. La captura nunca depende de esto, por la misma regla que «si calcular el presupuesto falla, el pago se guarda igual». |
| Al pasar la app a primer plano (`scenePhase == .active`) | **Sí** | Junta los comercios distintos sin categoría (normalmente 0–5) y los clasifica en lote. Sin límite en primer plano. La sesión se precalienta con `prewarm()`. |
| Al escribir el comercio en la hoja «+» | **Sí** | Con un *debounce* de unos 400 ms, igual que el hint del catálogo. |
| Idea para después | Llamarlo desde el intent con un límite de 2 s y quedarse con la sugerencia solo si llegó a tiempo | Solo después de medir el presupuesto real en segundo plano (fase 0). |

Una sola llamada por **comercio distinto**. El resultado se guarda en un caché `merchantKey → categoría sugerida` (JSON en UserDefaults, como `UserCatalog`), para no volver a clasificar «OXXO» 40 veces.

### 3.4 El problema de fondo: no confundir «lo dijo el modelo» con «lo elegiste tú»

`CategoryMemory` toma como verdad la última categoría guardada en el gasto. Si el modelo escribe `expense.category = "Comida"` directamente, la próxima vez la memoria lo trata como decisión tuya, y un error del modelo se vuelve permanente sin que nadie lo haya aprobado. Hay dos salidas:

- **A. Campo nuevo `categorySource: String?`** (`"yo" | "catalogo" | "modelo"`), opcional. Es una migración ligera y compatible con CloudKit, como `repeatDay`. `CategoryMemory` ignora lo que viene del modelo. «En qué se va» cuenta lo sugerido, y la lista puede marcarlo como sugerido. **Toca el esquema de `Expense`: por la decisión 2026-10-11, se consulta al dueño antes.**
- **B. Sin tocar el esquema:** la sugerencia vive solo en el caché por comercio y se muestra al vuelo. El gasto conserva `category = nil` hasta que la confirmas. Es más simple, pero «En qué se va» y el CSV no la ven.

Recomendación: **B para la fase 0 y A para la fase 1**, si el dueño aprueba el campo.

> Hoy ya pasa algo parecido con el catálogo. `ExpenseRecorder.rememberedCategory` escribe la categoría del catálogo en el gasto, y desde ese momento cuenta como «memoria». Con A, ese caso también se arregla, porque queda marcado como `catalogo`.

### 3.5 Esbozo de código (sin compilar)

En **`CentavoCore`** (Foundation, probado con `swift test` en Linux) va todo lo que se puede probar:

```swift
/// Las opciones que se le dan al modelo y la validación de lo que contesta.
public enum CategoryPick {
    /// Comunes + propias + usadas, cada nombre una vez (misma regla que `CategoryStyle.offered`).
    public static func candidates(common: [String], custom: [String], known: [String]) -> [String]

    /// Ejemplos para el prompt: un comercio tuyo por categoría, los más recientes primero.
    public static func examples(from history: [CategorizedExpense], limit: Int = 8) -> [(merchant: String, category: String)]

    /// Lo que contestó el modelo, solo si es una de las opciones (sin mayúsculas ni acentos).
    /// «Ninguna», vacío o algo fuera de la lista → nil.
    public static func validate(_ raw: String?, among candidates: [String]) -> String?

    /// El texto del prompt, corto y estable (se prueba con snapshots de texto).
    public static func prompt(merchant: String, card: String?, examples: [(String, String)]) -> String
}
```

En la **app** (`Centavo/Intelligence/CategoryClassifier.swift`) va una capa delgada:

```swift
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
actor CategoryClassifier {
    private let model = SystemLanguageModel.default

    var isReady: Bool { model.isAvailable && model.supportsLocale() }

    func suggest(merchant: String, card: String?, candidates: [String],
                 examples: [(String, String)]) async -> String? {
        guard isReady, !candidates.isEmpty else { return nil }
        let choice = DynamicGenerationSchema(name: "Categoria", anyOf: candidates + ["Ninguna"])
        let root = DynamicGenerationSchema(name: "Clasificacion", properties: [
            .init(name: "categoria", schema: choice)
        ])
        do {
            let schema = try GenerationSchema(root: root, dependencies: [])
            // Una sesión por comercio: el historial de otra clasificación no debe influir.
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            let response = try await session.respond(
                to: CategoryPick.prompt(merchant: merchant, card: card, examples: examples),
                schema: schema,
                options: GenerationOptions(sampling: .greedy)   // misma entrada, misma respuesta
            )
            let raw = try response.content.value(String.self, forProperty: "categoria")
            return CategoryPick.validate(raw, among: candidates)
        } catch {
            // Guardrail, rateLimited, modelo descargando… → sin sugerencia, nunca un error visible.
            return nil
        }
    }

    static let instructions = """
        The person's locale is es_MX.
        You file card payments from Mexico into the person's own spending categories.
        Pick the single category that fits the merchant best, using the person's past choices as examples.
        If the name does not say what was bought, answer "Ninguna". Never guess from a single letter or a number.
        """
}
#endif
```

La parte de la app es pequeña a propósito. En Linux solo corre `CentavoCore`, y la CI de macOS **no tiene Apple Intelligence**, así que el modelo no se puede ejecutar en la CI. Las pruebas de la app usan un `protocol CategorySuggesting` con una implementación falsa. El modelo de verdad se mide con el set de evaluación (§6).

## 4. Feature 2: insights

### 4.1 La regla

El modelo **redacta**, no **descubre**. Los hallazgos son funciones puras en `CentavoCore`, cada una con su prueba. El modelo recibe 3–6 hechos ya calculados y los convierte en una o dos frases cálidas en es-MX. Luego un verificador revisa que **cada cifra del texto esté en los hechos**. Si encuentra una cifra que no estaba, se descarta el texto y se usa una plantilla fija. Con eso, que el modelo invente un número deja de ser un riesgo silencioso.

### 4.2 Hechos (deterministas, en `CentavoCore`)

| Hecho | Cómo se calcula | Ejemplo redactado |
|---|---|---|
| Categoría que subió | Mes actual al día N contra la mediana de los 3 meses previos al mismo día N (comparación justa a mitad de mes) | «Comida va 40 % arriba de lo normal a estas alturas: 6 pedidos de Uber Eats.» |
| Proyección de cierre | `BudgetPace` extendido: gasto variable promedio por día × días restantes + fijos que faltan | «A este ritmo cierras el mes en $14,200, unos $800 arriba del presupuesto.» |
| Gasto fuera de lo común | Más de 3 veces la mediana de ese comercio o de la categoría | «El de Liverpool ($3,450) es tu gasto más grande del mes.» |
| Suscripción no marcada | Mismo comercio, monto ±5 %, separado 28–33 días, al menos 2 veces, sin `repeatsMonthly` | «Spotify se repite cada mes. ¿Lo marco como fijo?» (esto conecta con «Gastos fijos») |
| Cobro doble probable | Mismo comercio y monto en menos de 2 h, fuera de la ventana de 5 min de `CaptureGuard` | «Hay dos cargos iguales en Pemex hoy. ¿Fue a propósito?» |
| Patrón por día de la semana | Participación de los viernes y sábados contra lo esperado | «La mitad de lo que gastas en Salidas cae en viernes.» |
| Comercio nuevo frecuente | Primera aparición este mes y 3 o más visitas | «Cafecito La Ceiba ya es tu tercer café de la semana.» |
| Buena noticia | Categoría abajo de su mediana o mes cerrado bajo presupuesto | «Septiembre cerró $1,100 abajo del presupuesto.» |

Varios de estos **no necesitan el modelo**: con una plantilla ya sirven. El modelo aporta variedad, tono y la posibilidad de unir dos hechos en una frase natural («subió Comida, sobre todo por Uber Eats en fin de semana»). Conviene ser honestos con eso: la mitad del valor está en los detectores, y esos se pueden construir aunque el modelo no esté disponible.

### 4.3 Dónde se ve (sin pantallas nuevas)

Respetando el minimalismo:
- **Una línea en el ticket del presupuesto**, debajo de «En qué se va»: «Nota · Comida va 40 % arriba de lo normal.» Cambia como mucho una vez al día.
- **El aviso de «¿Cuánto llevo?» de Siri** puede agregar la nota como última frase (con plantilla, porque corre en segundo plano).
- **Cierre de mes**: el día 1, al abrir la app, una hoja que se puede descartar con 3–4 renglones sobre el mes anterior, con el estilo de ticket. Es lo que más se presta a redacción.

### 4.4 Esbozo

```swift
// CentavoCore
public struct SpendingFact: Equatable, Sendable {
    public enum Kind: String, Sendable { case categoryUp, projection, outlier, subscription, doubleCharge, weekday, newRegular, goodNews }
    public let kind: Kind
    public let weight: Double              // para ordenar: el más relevante primero
    public let figures: [String]           // cifras ya formateadas («$3,450», «40 %»): las únicas permitidas
    public let line: String                // la versión con plantilla, siempre válida
}
public enum SpendingFacts {
    // `SpentExpense`: ExpenseAmount + merchant + isFixed, nuevo y sin SwiftData.
    public static func detect(_ expenses: [SpentExpense], now: Date, primary: String,
                              budget: Decimal?, calendar: Calendar) -> [SpendingFact]
}
public enum FactCheck {
    /// Todas las cifras del texto (montos, porcentajes, conteos) deben estar en `facts.figures`.
    public static func accepts(_ text: String, facts: [SpendingFact]) -> Bool
}

// App
@Generable struct Nota {
    @Guide(description: "One or two short sentences in Mexican Spanish, gender-neutral, warm, no advice about debt or investing. Use only the figures given.")
    var texto: String
}
```

Tamaño del prompt: instrucciones (~150 tokens) + 6 hechos (~200) + respuesta (~80). Cabe sin problema en 4096.

## 5. Más ideas: qué más puede hacer un modelo local aquí

Ordenadas por valor y esfuerzo, con su choque, si lo hay, con decisiones vigentes.

| # | Idea | Cómo | Valor | Esfuerzo | Choque con decisiones |
|---|---|---|---|---|---|
| 1 | **Anotar en lenguaje natural**: «230 de tacos con Ana ayer, en efectivo» | `@Generable struct GastoDicho { montoTexto, comercio, diasAtras, fuente, categoria? }`. El monto lo vuelve a leer `AmountParser` sobre el **fragmento literal**, nunca sobre un número que «pensó» el modelo. Entra por el campo de la hoja «+» y por `AddExpenseIntent` (Siri ya pregunta «¿Cuánto?», «¿Dónde?»; con esto basta una frase). | Alto | Medio | Ninguno |
| 2 | **Foto del ticket** (efectivo, restaurante) | iOS 27: `Attachment(UIImage)` + `OCRTool`, o Vision `RecognizeDocumentsRequest` + modelo para elegir total, comercio y fecha. Rellena la hoja y tú confirmas. Sin guardar la foto. | Alto (el efectivo es el hueco) | Medio | Solo iOS 27 |
| 3 | **Avisos de Wallet que no entiende `WalletNotice`** (bancos o formatos nuevos) | Solo cuando el parser determinista devuelve `nil`: el modelo extrae `{comercio, tarjeta, fragmentoMonto}`, y `CaptureText` exige que el fragmento esté literal en el aviso. Corre en segundo plano, pero es raro, así que el presupuesto alcanza. | Medio-alto (robustez de la captura) | Bajo | Ninguno; refuerza «nunca adivinar el monto» |
| 4 | **Buscar como hablas**: «uber de octubre arriba de 200» | El modelo produce un `@Generable struct Filtro { comercio?, categoria?, desde?, hasta?, montoMin?, montoMax? }`, y el filtro lo aplica la app. Cabe en la lista actual (ya filtra por día). | Medio | Bajo | Ninguno |
| 5 | **Preguntas a Siri**: «¿Cuánto gasté en cafecitos este mes?» | App Intent con texto libre. El modelo mapea «cafecitos» → «Café» (misma validación que §3) y la suma la hace `MonthSummarizer`. En iOS 27, con `Tool`s que devuelven agregados, se pueden contestar preguntas comparativas («¿gasto más que en agosto?»). | Medio | Medio | Ninguno |
| 6 | **Nombre legible del comercio**: «AMZN MKTP MX*2K3J» → «Amazon», «CLIP*MX TAQ GUERO» → «Taq. El Güero» | Solo **para mostrar**: el gasto guarda el nombre original y se agrega un alias por comercio en el caché. | Medio (la lista se lee mejor) | Bajo | **Roza** el «no unir comercios» de 2026-10-11. Es solo de pantalla, pero lo decide el dueño. |
| 7 | **Ordenar tus categorías**: detecta «Súper», «Super» y «Supermercado» y propone unirlas | Lote ocasional, propuesta con un toque. | Bajo-medio | Bajo | Ninguno |
| 8 | **Detectar fijos y suscripciones** (§4.2) y ofrecer «¿Lo marco como fijo?» | Determinista; el modelo solo redacta. | Alto | Bajo | Ninguno |
| 9 | **Modo viaje**: varios gastos en USD o EUR más una aerolínea → «Parece un viaje: ¿los junto como “Viaje NY”?» | Determinista con el texto redactado. | Bajo | Medio | Agrega concepto nuevo (minimalismo) |
| 10 | **Explicar el «Hoy puedes gastar»** al tocarlo: «Te quedan $4,200 y 12 días; ya se descontó la renta del 30.» | Plantilla con redacción. | Bajo | Bajo | Ninguno |

Descartadas a propósito:
- **Chat abierto con tus finanzas**: con 4–8K de contexto no ve tus datos, termina inventando y además va contra el minimalismo. Las preguntas cerradas (#5) cubren el 80 % del uso.
- **Consejos de inversión o deuda**: el modelo no es experto y hay riesgo de *claims* financieros. Fuera.
- **PCC / modelos en la nube** (incluidos los paquetes de socios que anunció Apple): son red y la regla dice que la app no hace llamadas por su cuenta. Fuera, salvo decisión explícita.
- **`.contentTagging` para categorías**: inventa etiquetas en vez de elegir las tuyas (§2).

## 6. Cómo saber si funciona (evaluación)

- **Set dorado** en `Packages/CentavoCore/Tests/Fixtures/comercios.json`: ~200 nombres de comercio reales y desordenados de México (sucursales, `CLIP*`, `MERPAGO*`, `PAYPAL *`, abreviaturas), cada uno con la categoría esperada **o «Ninguna»**. Las pruebas de Linux solo validan el formato y que el catálogo no se contradiga con el set.
- **Corrida en el iPhone del dueño** (pantalla de Debug, como `DemoData`, o el framework **Evaluations** de iOS 27 en la Mac). Se mide:
  - Aciertos en comercios fuera del catálogo. Meta ≥ 85 %.
  - **Equivocaciones con seguridad**: cuántas veces sugiere algo incorrecto en vez de «Ninguna». Meta ≤ 5 %. Esta importa más que los aciertos: una sugerencia mala molesta más que ninguna.
  - Latencia mediana por comercio.
  - Bloqueos por *guardrail*.
- Se vuelve a correr **con cada iOS nuevo** (el modelo cambia: 26.0, 26.4, 27.0…), igual que las capturas de la guía.
- Para los insights: 30 meses sintéticos (de `DemoData`) y comprobar que `FactCheck` acepte ≥ 90 % de los textos. Los que no pasan usan la plantilla.

## 7. Decisiones que tiene que tomar el dueño

1. **Requisito:** estas funciones solo existen en iOS 26 o posterior con Apple Intelligence encendido. En lo demás, la app es idéntica a hoy, sin avisos. *(Recomendado: sí.)*
2. **¿El modelo escribe la categoría o solo la sugiere?** *(Recomendado: la escribe marcada como «sugerida» con `categorySource`; nunca cuenta como memoria tuya.)* Implica el **cambio de esquema** de §3.4-A.
3. **Private Cloud Compute:** *(Recomendado: no. Todo on-device.)*
4. **Dónde viven los insights:** una línea en el ticket, Siri y el cierre de mes, o solo alguno. *(Recomendado: empezar con la línea del ticket.)*
5. **Alias de comercio solo para mostrar** (idea #6): ¿se permite o contradice «no unir comercios»?

## 8. Plan propuesto

| Fase | Qué | Cómo se verifica | Issue sugerido |
|---|---|---|---|
| **0 · Prueba en el teléfono** (1–2 días) | Pantalla de Debug que clasifica el set dorado con el modelo real y muestra aciertos, latencia y bloqueos. Sin cambios para el usuario. | Números de §6 en el iPhone del dueño. **Ir / no ir.** | CEN-·· «Spike: clasificar comercios con el modelo de Apple» |
| **1 · Categoría sugerida** | `CategoryPick` en Core + `CategoryClassifier` + caché + clasificación al abrir + hint en la hoja. Esquema: `categorySource` si se aprueba. | `swift test` de Core; CI de iOS; set dorado ≥ meta. | CEN-·· «Sugerir categoría con el modelo local» |
| **2 · Nota del mes** | `SpendingFacts` + `FactCheck` en Core (se puede hacer **antes** que la fase 1, porque no depende del modelo), redacción con el modelo y una línea en el ticket. | Pruebas por detector; `FactCheck` con salidas adversariales. | CEN-·· «Detectores de insights» y CEN-·· «Nota del mes» |
| **3 · Captura natural** | Ideas #1 y #3. Después #2 (ticket) en iOS 27. | Set de frases dictadas; el monto siempre lo valida `AmountParser`. | CEN-·· |
| **4 · Preguntas** | Ideas #4 y #5. | | CEN-·· |

## Fuentes

- [Foundation Models — documentación](https://developer.apple.com/documentation/foundationmodels)
- [What's new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) · [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror)
- [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
- [Categorizing and organizing data with content tags](https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags)
- [TN3193: Managing the on-device model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [LLM search using Core Spotlight — WWDC26](https://developer.apple.com/videos/play/wwdc2026/246/)
- Foros de Apple sobre límites en segundo plano: [789788](https://developer.apple.com/forums/thread/789788), [793787](https://developer.apple.com/forums/thread/793787)
- [Introduction to Apple's FoundationModels — Natasha the Robot](https://www.natashatherobot.com/p/apple-foundation-models)
- [Apple Intelligence: idiomas soportados](https://support.apple.com/en-mt/121115)
