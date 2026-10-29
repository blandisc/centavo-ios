# Investigación: el atajo ya armado, dentro de la app (opción B)

29 de octubre de 2026. El dueño eligió la opción B: que Al día traiga el atajo listo en vez de la guía de 8 pasos.

## Lo que se confirmó

- **El nombre interno de la acción en iOS 27.** Se armó la automatización en Atajos del simulador (iOS 27.0) y se leyó de su base de datos:
  - la acción se llama `com.blandisc.centavo.LogWalletNoticeIntent`;
  - su campo «Notificación» se conecta a lo que entrega el disparador: `{Type: TriggerOutput, TriggerIdentifier: WFNotificationTrigger}`.
- **La Mac firma atajos para cualquiera.** `shortcuts sign --mode anyone` devuelve un archivo AEA1 firmado por Apple en unos 5 segundos. Para eso Apple recibe una copia del atajo; el atajo no trae datos personales.
- **Un atajo firmado se puede abrir para leerlo.** La llave pública está en el certificado que viene adentro; con ella, `aea decrypt` y `aa extract` sacan el `Shortcut.wflow`.
- **El simulador necesitaba servicios apagados.** Con simslim, Atajos abre en negro y la acción de Al día sale como «Acción desconocida». Hay que apagar simslim mientras se prueba Atajos.

## Lo que dicen las fuentes y falta probar

- **En iOS 27 un atajo compartido puede traer su automatización.** Llega apagada y quien lo importa la enciende con un interruptor antes de «Agregar atajo». Fuentes: [MacStories](https://www.macstories.net/stories/ios-and-ipados-27-review/13/) y [one sec](https://tutorials.one-sec.app/en/articles/10309122). Si se confirma, la guía queda en unos 3 toques.

## Lo que no se pudo

- **Exportar el atajo desde el simulador.** Atajos pide una sesión de iCloud para exportar, incluso para «Personas que me conocen». Sin el archivo exportado no se conoce cómo guarda iOS 27 el disparador. La salida es exportarlo una vez desde el iPhone del dueño, donde ya existe.
- **Importar con `shortcuts://import-shortcut?url=file://…`.** Atajos responde «The shortcut URL provided was invalid»: ese esquema solo acepta enlaces, no archivos locales. Abrir el archivo con `simctl openurl` tampoco hace nada. Desde la app, el camino que queda es la hoja de compartir («Abrir en Atajos»), por probar.

## Siguiente paso

1. El dueño exporta «Registrar aviso de Wallet» desde su iPhone: Compartir › Opciones › Archivo, para Cualquiera › Guardar en Archivos.
2. Se abre en la Mac, se revisa qué trae (que no lleve datos personales), se vuelve a firmar para cualquiera y se agrega a la app.
3. Botón en «Conectar Wallet» que abre la hoja de compartir con el archivo; se prueba en el iPhone que importa con el disparador.
4. La guía de 8 pasos queda de respaldo.

## Resultado (mismo día)

- El dueño exportó el atajo de su iPhone. Trae `WFWorkflowTriggers` con el disparador «Notificación» de Wallet (`com.apple.Passbook`) y la acción con «Notificación» y «Subtítulo» conectados. Sin datos personales; solo el `TeamIdentifier` del equipo de la app.
- **No se puede volver a firmar en la Mac:** `shortcuts sign` en macOS 26 borra `WFWorkflowTriggers`. Se usa tal cual el archivo firmado en el iPhone.
- **Probado en el simulador (iOS 27.0):** «Agregar a Atajos» abre la hoja de compartir, Atajos sale primero e importa el archivo. Queda «When I receive a notification from Wallet» con «Registrar Notification con comercio Subtitle», y arriba «Automation is turned off».
- **Falta en el iPhone:** encender la automatización (en el simulador los toques rebotaban en esa pantalla) y que el primer pago real se anote.
