# Arranque con cuenta guardada

Con JID y contraseña completos, xat conecta automáticamente y oculta el login
antes del primer frame. La esfera de la mente aparece con pulso de actividad;
el estado «Conectado» y su color sólo se muestran tras CONNECTED. El éxito
desvanece la pantalla y libera la esfera temporal. No se bloquea el chat durante
reconexiones posteriores.

Cancelar interrumpe la conexión y muestra la cuenta. Un error de inicio o de
autenticación vuelve al formulario con su explicación; a los 15 segundos sin
conectar se permite reintentar. Las credenciales y el historial no se borran.
`XAT_AUTOCONNECT=0` permite arrancar deliberadamente en el formulario y se usa
en pruebas de UI para impedir conexiones reales.

Validación local: 65 checks de arranque, flujo completo simulado, UI y sesión sin fallos usando
`XDG_DATA_HOME=/tmp/xat-startup-tests` y `SDL_AUDIODRIVER=dummy`. El directorio
temporal evita fallos de escritura del sandbox en los tests de persistencia.
El runner desactiva autoconexión en tests y asigna un directorio temporal único
al test del flujo, que nunca abre una conexión ni usa credenciales reales.
Captura GLES3/llvmpipe; falta confirmar interacción y aspecto en el teléfono.

![Animación de arranque](screenshots/startup.gif)

El entorno de esta sesión oculta `.git`, no permite USB/ADB ni sockets de red.
Se conserva un snapshot Git portátil en `bin/xat-source.bundle`, sin sustituir
la historia del checkout original. `sh tools/publish_github.sh` en el host usa
esa historia si está disponible, o clona el bundle en un directorio temporal,
y publica un repositorio privado `icarito/xat` usando exclusivamente esa cuenta.
No imprime tokens y no hace force-push.

Para instalar el APK preparado desde el host:

```sh
adb install -r bin/xat-debug.apk
adb shell monkey -p org.fuentelibre.xat -c android.intent.category.LAUNCHER 1
```

La instalación y la publicación remota no están verificadas desde el sandbox.
