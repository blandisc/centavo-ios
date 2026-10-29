# El atajo que trae la app

`Centavo/Resources/Registrar aviso de Wallet.shortcut` es la automatización completa, ya armada:
- el disparador: «Al recibir una notificación de Wallet»;
- la acción «Registrar aviso de Wallet», con «Notificación» y «Subtítulo» conectados.

Al día lo abre en Atajos con «Agregar a Atajos» (`ShortcutInstaller`). En iOS 27 la automatización llega apagada y la persona la enciende al agregarla.

## De dónde sale

Se exportó del iPhone del dueño (iOS 27, 2026-10-29) desde Atajos › Compartir › Opciones › Archivo › Cualquiera. Así ya viene firmado por Apple para cualquiera.

`registrar-aviso-de-wallet.plist` es lo que trae adentro, legible, para revisarlo en un diff. Se saca con:

    python3 Tools/atajo/abrir.py "Centavo/Resources/Registrar aviso de Wallet.shortcut" /tmp/atajo
    plutil -convert xml1 -o - /tmp/atajo/x/Shortcut.wflow

## Para cambiarlo

Hay que exportarlo otra vez desde un iPhone con iOS 27. No sirve armarlo en la Mac y firmarlo con `shortcuts sign`: macOS 26 borra `WFWorkflowTriggers` al firmar, y el atajo llega sin disparador (visto el 2026-10-29). Con una Mac en macOS 27 habría que volver a probarlo.

`TeamIdentifier` de la acción es el equipo con el que se firma la app (B7KRCF776Z). Si la app cambia de equipo, hay que exportarlo de nuevo.
